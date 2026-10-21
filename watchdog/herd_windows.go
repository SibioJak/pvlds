package main

// Focus herding (Windows only) - the watchdog's single window duty
// (design section 3, Chris's amendment). While a session is live,
// if the foreground window leaves the game process and stays away
// past the grace period, foreground is handed back to the game's
// main window. Bounds, by construction:
//   - herding NEVER moves or resizes any window;
//   - a grace period (2s) follows every foreground change before
//     any action - deliberate alt-tabs get their moment;
//   - re-asserts are rate-limited (3s) and re-check the foreground
//     immediately before acting;
//   - the only calls are SetForegroundWindow / BringWindowToTop
//     (with the AttachThreadInput dance Windows requires of a
//     background process). Windows may still refuse; Virtual
//     Desktop's own stream behaviour is outside our reach - both
//     limits are stated in the design, and effectiveness is the
//     player's verdict, with the focus_herding config kill-switch
//     one toggle away.

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
	procAttachThreadInput     = user32.NewProc("AttachThreadInput")
	procGetCurrentThreadID    = kernel32.NewProc("GetCurrentThreadId")
)

type rect struct {
	Left, Top, Right, Bottom int32
}

var (
	herdLastFg       uintptr
	herdLastFgChange int64 // unix millis
	herdLastAssert   int64 // unix millis
	enumCollect      []uintptr
	enumTargetPID    uint32
)

const (
	herdGraceMillis    = 2000
	herdMinIntervalMil = 3000
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

// gameWindow finds the game process's largest visible top-level
// window - the playfield window, not a helper.
func gameWindow(gamePID int) uintptr {
	enumCollect = enumCollect[:0]
	enumTargetPID = uint32(gamePID)
	procEnumWindows.Call(enumProc, 0)
	var best uintptr
	var bestArea int64
	for _, hwnd := range enumCollect {
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

func herdTick(gamePID int, _ int64, _ int64) {
	if gamePID <= 0 {
		return
	}
	fg, _, _ := procGetForegroundWindow.Call()
	if fg == 0 {
		return
	}
	var fgPID uint32
	procGetWindowThreadProcID.Call(fg, uintptr(unsafe.Pointer(&fgPID)))
	if int(fgPID) == gamePID {
		herdLastFg = fg
		return
	}
	if int(fgPID) == syscall.Getpid() {
		return // never chase our own (invisible) windows
	}
	nowMs := time.Now().UnixMilli()
	if fg != herdLastFg {
		herdLastFg = fg
		herdLastFgChange = nowMs
		return // grace period starts; deliberate action gets its moment
	}
	if nowMs-herdLastFgChange < herdGraceMillis {
		return
	}
	if nowMs-herdLastAssert < herdMinIntervalMil {
		return
	}
	target := gameWindow(gamePID)
	if target == 0 || target == fg {
		return
	}
	// Windows denies foreground theft to background processes unless
	// the caller briefly shares the current foreground thread's
	// input queue. Attach, assert, detach - windows are never moved
	// or resized.
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
	herdLastAssert = nowMs
	herdLastFg = target
	herdLastFgChange = nowMs
	logf("watchdog: focus herded back to the game window (was pid %d)", fgPID)
}
