//go:build windows

package main

// Session-close duty: the Windows message-sending leaves. The
// decision of WHEN to close lives in closer.go (shared, tested on
// Linux); this file only delivers the two orderly requests, in the
// design's preference order. Neither is a process kill.

import (
	"sync"
	"syscall"
	"unsafe"
)

const (
	wmCloseMsg       = 0x0010 // WM_CLOSE
	smtoAbortIfHung  = 0x0002 // SMTO_ABORTIFHUNG
	fecCloseAppParam = 2      // PinSim::FrontEndControls sub-command CLOSE_APP
	fecTimeoutMs     = 100    // per-window reply timeout (PinballY uses 50)
)

var (
	fecMsgID  uintptr
	fecMsgOne sync.Once
)

// frontEndControlsMsgID resolves the session-wide registered
// message id for "PinSim::FrontEndControls" (the published
// protocol's name; RegisterWindowMessage is how senders and
// receivers agree on the id).
func frontEndControlsMsgID() uintptr {
	fecMsgOne.Do(func() {
		name, err := syscall.UTF16PtrFromString("PinSim::FrontEndControls")
		if err != nil {
			return
		}
		id, _, _ := procRegisterWindowMsgW.Call(uintptr(unsafe.Pointer(name)))
		fecMsgID = id
	})
	return fecMsgID
}

var (
	enumAllCollect   []uintptr
	enumAllTargetPID uint32
)

func enumAllCallback(hwnd uintptr, _ uintptr) uintptr {
	var pid uint32
	procGetWindowThreadProcID.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid == enumAllTargetPID {
		enumAllCollect = append(enumAllCollect, hwnd)
	}
	return 1
}

var enumAllProc = syscall.NewCallback(enumAllCallback)

// allTopWindows lists every top-level window of the process,
// visible or not: the FrontEndControls handler may sit on a window
// the visible-only enumeration (the discriminator's) skips.
func allTopWindows(gamePID int) []uintptr {
	enumAllCollect = enumAllCollect[:0]
	enumAllTargetPID = uint32(gamePID)
	procEnumWindows.Call(enumAllProc, 0)
	out := make([]uintptr, len(enumAllCollect))
	copy(out, enumAllCollect)
	return out
}

// sendFrontEndControlsClose asks the game process to close itself
// via the PinSim::FrontEndControls protocol: the registered message
// with wParam CLOSE_APP (2), sent to each of the process's windows
// until one acknowledges. Per the protocol (PinballY's
// Application.cpp is the reference sender), a reply of 1 means the
// application accepts and will close. Returns true if any window
// acknowledged.
func sendFrontEndControlsClose(gamePID int) bool {
	msg := frontEndControlsMsgID()
	if msg == 0 || gamePID <= 0 {
		return false
	}
	for _, hwnd := range allTopWindows(gamePID) {
		var result uintptr
		r, _, _ := procSendMessageTimeoutW.Call(hwnd, msg,
			fecCloseAppParam, 0, smtoAbortIfHung, fecTimeoutMs,
			uintptr(unsafe.Pointer(&result)))
		if r != 0 && result == 1 {
			return true
		}
	}
	return false
}

// sendEditorClose posts WM_CLOSE to the editor main window - the
// "click the X" request. VP's editor runs its ordinary shutdown
// for it (and refuses it while a player is open: WinEditor::
// OnClose in the vpinball source). PostMessage, not SendMessage:
// the watchdog never blocks on another process's window.
func sendEditorClose(editorHWND uintptr) bool {
	if editorHWND == 0 {
		return false
	}
	r, _, _ := procPostMessageW.Call(editorHWND, wmCloseMsg, 0, 0)
	return r != 0
}
