//go:build windows

package main

import (
	"runtime"
	"syscall"
	"time"
	"unsafe"
)

var (
	procCreateWindowExW = user32.NewProc("CreateWindowExW")
	procDestroyWindow   = user32.NewProc("DestroyWindow")
	procShowWindow      = user32.NewProc("ShowWindow")
)

// cyclePlayerActivation gives an already-foreground player a real
// deactivate/activate transition, as the manual Alt+Tab workaround
// does. A watchdog-owned tool window works even when VPX exposes no
// companion window. It has no taskbar entry and sits off screen for
// the brief excursion; neither the editor nor another app is raised.
//
// Keep the native window and every input-queue attachment on one OS
// thread. A Go goroutine may otherwise migrate between user32 calls.
func cyclePlayerActivation(target uintptr) bool {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	fg, _, _ := procGetForegroundWindow.Call()
	if fg != target {
		// The snapshot became stale: don't cycle away from a window
		// the user may have deliberately switched to in the meantime.
		return false
	}
	class, _ := syscall.UTF16PtrFromString("STATIC")
	title, _ := syscall.UTF16PtrFromString("LaunchPin input handoff")
	const (
		wsExToolWindow   = 0x00000080
		wsPopup          = 0x80000000
		swShowNoActivate = 4
	)
	helper, _, err := procCreateWindowExW.Call(
		wsExToolWindow, uintptr(unsafe.Pointer(class)), uintptr(unsafe.Pointer(title)),
		wsPopup, 32000, 32000, 1, 1, 0, 0, 0, 0)
	if helper == 0 {
		logf("watchdog: activation cycle: could not create handoff window: %v", err)
		return false
	}
	defer procDestroyWindow.Call(helper)
	procShowWindow.Call(helper, swShowNoActivate)
	raiseForeground(helper, target)
	away, _, _ := procGetForegroundWindow.Call()
	if away != helper {
		logf("watchdog: activation cycle: Windows refused the switch away from the player")
		return false
	}
	// Let VPX's own event pump observe the loss before reacquiring
	// input. No synthetic keyboard or controller events are sent.
	time.Sleep(150 * time.Millisecond)
	fg, _, _ = procGetForegroundWindow.Call()
	if fg != helper && fg != target {
		logf("watchdog: activation cycle: interrupted by another foreground window; yielding")
		return false
	}
	ok := deliverFocusForeground(target, fg)
	landed, _, _ := procGetForegroundWindow.Call()
	logf("watchdog: activation cycle: switched away from player hwnd %#x and back (returned=%t)", target, landed == target)
	return ok && landed == target
}
