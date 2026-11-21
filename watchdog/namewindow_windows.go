//go:build windows

package main

import (
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	procPeekMessageW    = user32.NewProc("PeekMessageW")
	procTranslateMsg    = user32.NewProc("TranslateMessage")
	procDispatchMessage = user32.NewProc("DispatchMessageW")
)

// nameWindowMsg is the Win32 MSG the pump drains.
type nameWindowMsg struct {
	hwnd    uintptr
	message uint32
	wParam  uintptr
	lParam  uintptr
	time    uint32
	ptX     int32
	ptY     int32
}

// The name window's native life (namewindow.go carries
// the law). The window is created and destroyed on a
// dedicated OS thread that pumps its message queue:
// the B2S scrape reads the title from another process
// (GetWindowText), and a window whose owner thread
// never services its queue is a window that can stall
// the reader. The window itself is the activation
// helper's shape - a 1x1 popup at 32000,32000 - plus
// WS_EX_NOACTIVATE: it must never take focus or
// activation (the VR law: the view is never broken;
// the desktop's focus belongs to the game and the
// watchdog's standing focus duties). No owner, no
// parent: the scrape's filter asks for exactly that.
var nameWindowNative struct {
	sync.Mutex
	hwnd uintptr
	stop chan struct{}
	done chan struct{}
}

func createNameWindow(title string) uintptr {
	nameWindowNative.Lock()
	defer nameWindowNative.Unlock()
	if nameWindowNative.hwnd != 0 {
		// The tracker guarantees one window at a time;
		// a live record here means a drop was skipped -
		// close the old window rather than leak its
		// thread.
		close(nameWindowNative.stop)
		<-nameWindowNative.done
		nameWindowNative.hwnd = 0
	}
	ready := make(chan uintptr, 1)
	stop := make(chan struct{})
	done := make(chan struct{})
	go runNameWindow(title, ready, stop, done)
	hwnd := <-ready
	if hwnd == 0 {
		<-done
		return 0
	}
	nameWindowNative.hwnd = hwnd
	nameWindowNative.stop = stop
	nameWindowNative.done = done
	return hwnd
}

func destroyNameWindow(hwnd uintptr) {
	nameWindowNative.Lock()
	defer nameWindowNative.Unlock()
	if hwnd == 0 || nameWindowNative.hwnd != hwnd {
		// Not ours (or already down): never destroy a
		// window we did not create.
		return
	}
	close(nameWindowNative.stop)
	select {
	case <-nameWindowNative.done:
	case <-time.After(time.Second):
		// The window dies with the process regardless;
		// a stuck pump thread must never stall a tick
		// or a stand-down.
	}
	nameWindowNative.hwnd = 0
}

// runNameWindow is the window's thread: create, pump,
// destroy on the stop signal - all on the one locked
// OS thread, like every user32 duty in this watchdog.
func runNameWindow(title string, ready chan<- uintptr, stop <-chan struct{}, done chan<- struct{}) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	defer close(done)
	class, _ := syscall.UTF16PtrFromString("STATIC")
	titlePtr, _ := syscall.UTF16PtrFromString(title)
	const (
		wsExToolWindow   = 0x00000080
		wsExNoActivate   = 0x08000000
		wsPopup          = 0x80000000
		wsVisible        = 0x10000000
		pmRemove         = 0x0001
	)
	hwnd, _, _ := procCreateWindowExW.Call(
		wsExToolWindow|wsExNoActivate, uintptr(unsafe.Pointer(class)), uintptr(unsafe.Pointer(titlePtr)),
		wsPopup|wsVisible, 32000, 32000, 1, 1, 0, 0, 0, 0)
	ready <- hwnd
	if hwnd == 0 {
		return
	}
	var msg nameWindowMsg
	for {
		for {
			r, _, _ := procPeekMessageW.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0, pmRemove)
			if r == 0 {
				break
			}
			procTranslateMsg.Call(uintptr(unsafe.Pointer(&msg)))
			procDispatchMessage.Call(uintptr(unsafe.Pointer(&msg)))
		}
		select {
		case <-stop:
			procDestroyWindow.Call(hwnd)
			return
		case <-time.After(10 * time.Millisecond):
		}
	}
}
