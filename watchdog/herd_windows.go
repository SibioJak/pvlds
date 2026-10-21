//go:build windows

package main

// Focus herding (Windows leaf) - the watchdog's window duties
// (design section 3 amendment; M2 corrected fix round). The
// DECISIONS live in shared, unit-tested logic: herd_logic.go for
// herding (grace, rate limit, the yield to deliberate use) and
// closer.go for the session-close duty. This file is only the
// user32 plumbing: read the foreground, enumerate the game
// process's windows, and - when a decision says so - hand
// foreground back to the game's main window.
//
// Herding bounds, unchanged: it NEVER moves, resizes, or closes a
// window to do its job; the only calls are SetForegroundWindow /
// BringWindowToTop (with the AttachThreadInput dance Windows
// requires of a background process). Windows may still refuse;
// effectiveness is the player's verdict, with the focus_herding
// config kill-switch one toggle away.

import (
	"syscall"
	"time"
	"unsafe"
)

var (
	user32                    = syscall.NewLazyDLL("user32.dll")
	procGetForegroundWindow   = user32.NewProc("GetForegroundWindow")
	procSetForegroundWindow   = user32.NewProc("SetForegroundWindow")
	procBringWindowToTop      = user32.NewProc("BringWindowToTop")
	procGetWindowThreadProcID = user32.NewProc("GetWindowThreadProcessId")
	procEnumWindows           = user32.NewProc("EnumWindows")
	procIsWindowVisible       = user32.NewProc("IsWindowVisible")
	procGetWindowRect         = user32.NewProc("GetWindowRect")
	procGetClassNameW         = user32.NewProc("GetClassNameW")
	procRegisterWindowMsgW    = user32.NewProc("RegisterWindowMessageW")
	procSendMessageTimeoutW   = user32.NewProc("SendMessageTimeoutW")
	procPostMessageW          = user32.NewProc("PostMessageW")
	procAttachThreadInput     = user32.NewProc("AttachThreadInput")
	procGetCurrentThreadID    = kernel32.NewProc("GetCurrentThreadId")
)

type rect struct {
	Left, Top, Right, Bottom int32
}

var (
	enumCollect   []uintptr
	enumTargetPID uint32
)

func enumCallback(hwnd uintptr, _ uintptr) uintptr {
	var pid uint32
	procGetWindowThreadProcID.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid != enumTargetPID {
		return 1
	}
	if r, _, _ := procIsWindowVisible.Call(hwnd); r == 0 {
		return 1
	}
	enumCollect = append(enumCollect, hwnd)
	return 1
}

var enumProc = syscall.NewCallback(enumCallback)

// visibleWindows lists the process's visible top-level windows.
func visibleWindows(gamePID int) []uintptr {
	enumCollect = enumCollect[:0]
	enumTargetPID = uint32(gamePID)
	procEnumWindows.Call(enumProc, 0)
	out := make([]uintptr, len(enumCollect))
	copy(out, enumCollect)
	return out
}

// gameWindow finds the game process's largest visible top-level
// window - the playfield window, not a helper.
func gameWindow(gamePID int) uintptr {
	var best uintptr
	var bestArea int64
	for _, hwnd := range visibleWindows(gamePID) {
		var rc rect
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		area := int64(rc.Right-rc.Left) * int64(rc.Bottom-rc.Top)
		if area > bestArea {
			bestArea = area
			best = hwnd
		}
	}
	return best
}

// gameWindowExists reports whether the game process owns a
// visible top-level window yet - the hand-off cue the resident
// launcher waits for (plus a short settle) before it exits. The
// game's largest visible window is the playfield window VPX raises
// as it comes up; helpers and splash remnants don't count unless
// they are all there is.
func gameWindowExists(gamePID int) bool {
	return gamePID > 0 && gameWindow(gamePID) != 0
}

// windowClassName reads a window's Win32 class name - "VPPlayer"
// for the VPX player's SDL windows, "VPinball" for the editor
// frame (see closer.go for the vpinball source citations).
func windowClassName(hwnd uintptr) string {
	buf := make([]uint16, 256)
	n, _, _ := procGetClassNameW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if n == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}

// gameWindowState classifies the game process's visible top-level
// windows for the session-close duty (closer.go). The close target
// is the largest editor-class window (in practice the one frame).
func gameWindowState(gamePID int) windowState {
	var ws windowState
	var bestEditorArea int64
	for _, hwnd := range visibleWindows(gamePID) {
		switch windowClassName(hwnd) {
		case "VPPlayer":
			ws.playerPresent = true
		case "VPinball":
			ws.editorPresent = true
			var rc rect
			procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
			area := int64(rc.Right-rc.Left) * int64(rc.Bottom-rc.Top)
			if area > bestEditorArea {
				bestEditorArea = area
				ws.editorHWND = hwnd
			}
		}
	}
	return ws
}

var herdState herdBrain

// herdTick performs one herding duty tick: read the foreground, ask
// the brain, act on its decision.
func herdTick(gamePID int, sessionID int, now time.Time) {
	if gamePID <= 0 {
		return
	}
	if herdState.sessionID != sessionID {
		herdState.reset(sessionID)
	}
	fg, _, _ := procGetForegroundWindow.Call()
	if fg == 0 {
		return
	}
	var fgPID uint32
	procGetWindowThreadProcID.Call(fg, uintptr(unsafe.Pointer(&fgPID)))
	if int(fgPID) == syscall.Getpid() {
		return // never chase our own (invisible) windows
	}
	fgIsGame := int(fgPID) == gamePID
	switch herdState.decide(now.UnixMilli(), fg, fgIsGame) {
	case herdAssert:
		target := gameWindow(gamePID)
		if target == 0 || target == fg {
			return
		}
		assertForeground(target, fg)
	case herdYielded:
		logf("watchdog: herding stands down for this session - the same window kept the foreground through %d re-assertions; deliberate use wins", herdMaxFails)
	}
}

// assertForeground hands foreground activation to the game window.
// Windows denies foreground theft to background processes unless
// the caller briefly shares the current foreground thread's input
// queue. Attach, assert, detach - windows are never moved or
// resized. Fire-and-forget: whether it stuck is the brain's next
// observation.
func assertForeground(target uintptr, fg uintptr) {
	fgThread, _, _ := procGetWindowThreadProcID.Call(fg, 0)
	myThread, _, _ := procGetCurrentThreadID.Call()
	attached := false
	if fgThread != 0 && fgThread != myThread {
		r, _, _ := procAttachThreadInput.Call(myThread, fgThread, 1)
		attached = r != 0
	}
	procBringWindowToTop.Call(target)
	procSetForegroundWindow.Call(target)
	if attached {
		procAttachThreadInput.Call(myThread, fgThread, 0)
	}
	logf("watchdog: focus herded back to the game window (was hwnd %#x)", fg)
}
