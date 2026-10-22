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
	"fmt"
	"strings"
	"sync"
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

// playerSight is this leaf's sighting gate (sighting.go): the
// one filtered record of whether the game process's PLAYER
// window has been observed this session, and whether it counts
// as present right now.
var playerSight playerSighting

// obsWindow pairs a window handle with its sighting observation.
type obsWindow struct {
	hwnd uintptr
	obs  windowObs
}

// enumLogOnce guards the per-session window inventory log line.
var (
	enumLogMu      sync.Mutex
	enumLogSession int
)

// enumerateGameWindows lists the game process's visible top-level
// windows as sighting observations. The FIRST enumeration of a
// session that finds any window logs the full inventory - class
// and size of each - exactly once: permanent field evidence of
// what the game process actually puts on screen, the evidence
// the old VPPlayer-only rule never produced while it silently
// matched nothing on Chris's rig.
func enumerateGameWindows(gamePID int, sessionID int) []obsWindow {
	var out []obsWindow
	for _, hwnd := range visibleWindows(gamePID) {
		var rc rect
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		out = append(out, obsWindow{hwnd: hwnd, obs: windowObs{
			class:  windowClassName(hwnd),
			width:  int64(rc.Right - rc.Left),
			height: int64(rc.Bottom - rc.Top),
		}})
	}
	if len(out) > 0 {
		enumLogMu.Lock()
		if enumLogSession != sessionID {
			enumLogSession = sessionID
			parts := make([]string, 0, len(out))
			for _, w := range out {
				parts = append(parts, fmt.Sprintf("class %q %dx%d", w.obs.class, w.obs.width, w.obs.height))
			}
			logf("watchdog: session %d: game pid %d visible windows: %s", sessionID, gamePID, strings.Join(parts, "; "))
		}
		enumLogMu.Unlock()
	}
	return out
}

// gameWindowExists reports whether a player sighting has
// STAMPED for this session - the hand-off cue the resident
// launcher waits for (plus a short settle) before it exits.
// Tightened in the diagnostic round: the cue used to accept ANY
// visible window, and VPX's editor frame is visible from app
// start while the player window appears only once the table has
// loaded and play begins - so the launcher could hand off (and
// mark the session live) while the table was still loading,
// which then exposed the session-close duty to the load state it
// must never act on (see closer.go's arming note). The stamp now
// reads the sighting gate's latch (sighting.go) - the same
// definition the session-close duties arm on - and reports the
// rule that stamped it, for the log.
func gameWindowExists(gamePID int, sessionID int) (bool, string) {
	if gamePID <= 0 {
		return false, ""
	}
	return playerSight.hasSighted(sessionID)
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
// windows for the session-close duties (closer.go / arbiter.go).
// The editor facts stay class-based (a visible "VPinball"-class
// frame; the close target is the largest such window - in
// practice the one frame). The player fact comes from the
// sighting gate (sighting.go): a VPPlayer-class window counts at
// once; a substantial non-editor window counts once it has
// persisted across two polls; the editor class never counts.
func gameWindowState(gamePID int, sessionID int) windowState {
	var ws windowState
	if gamePID <= 0 {
		return ws
	}
	windows := enumerateGameWindows(gamePID, sessionID)
	obs := make([]windowObs, 0, len(windows))
	var bestEditorArea int64
	for _, w := range windows {
		obs = append(obs, w.obs)
		if w.obs.class == editorWindowClass {
			ws.editorPresent = true
			if area := w.obs.area(); area > bestEditorArea {
				bestEditorArea = area
				ws.editorHWND = w.hwnd
			}
		}
	}
	candidate, rule := classifyPlayerCandidate(obs)
	present, _ := playerSight.observe(sessionID, candidate, rule)
	ws.playerPresent = present
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
