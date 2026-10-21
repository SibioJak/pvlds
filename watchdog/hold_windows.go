//go:build windows

package main

// Hold-to-exit: the Windows button feed. Reads XInput controller
// state (XInputGetState via the xinput DLL, loaded lazily like
// the user32 plumbing) across slots 0-3 and reports whether the
// configured button bit is down on ANY connected controller -
// Chris plays on one pad, possibly forwarded to the PC by Virtual
// Desktop; from this process's side it is simply an XInput device,
// whichever slot it lands on. Strictly read-only: XInputSetState
// (rumble) is never called and no state is ever written back.

import (
	"sync"
	"syscall"
	"unsafe"
)

// XINPUT_STATE / XINPUT_GAMEPAD, as laid out for the call
// (xinput.h): a packet counter, then the gamepad - buttons first.
type xinputGamepad struct {
	wButtons      uint16
	bLeftTrigger  uint8
	bRightTrigger uint8
	sThumbLX      int16
	sThumbLY      int16
	sThumbRX      int16
	sThumbRY      int16
}

type xinputState struct {
	dwPacketNumber uint32
	gamepad        xinputGamepad
}

const errorSuccess = 0 // XInputGetState's success return

var (
	xinputProc *syscall.LazyProc
	xinputOnce sync.Once
)

// resolveXInputProc finds XInputGetState in whichever xinput DLL
// the system carries: 1_4 ships with Windows 8+, 9_1_0 with the
// older DirectX redistributables, 1_3 older still. A machine with
// none of them has no XInput controllers to read; the feed then
// simply never reports a press.
func resolveXInputProc() *syscall.LazyProc {
	xinputOnce.Do(func() {
		for _, dll := range []string{"xinput1_4.dll", "xinput9_1_0.dll", "xinput1_3.dll"} {
			d := syscall.NewLazyDLL(dll)
			p := d.NewProc("XInputGetState")
			// Force the load now so a missing DLL resolves to nil
			// here instead of failing on the first real poll.
			if err := d.Load(); err != nil {
				continue
			}
			xinputProc = p
			break
		}
	})
	return xinputProc
}

// anyButtonPressed reports whether the given XInput button mask
// is currently down on any connected controller (slots 0-3).
// Slots with no controller answer an error and are skipped.
func anyButtonPressed(mask uint16) bool {
	if mask == 0 {
		return false
	}
	proc := resolveXInputProc()
	if proc == nil {
		return false
	}
	for slot := uintptr(0); slot < 4; slot++ {
		var st xinputState
		r, _, _ := proc.Call(slot, uintptr(unsafe.Pointer(&st)))
		if r == errorSuccess && st.gamepad.wButtons&mask != 0 {
			return true
		}
	}
	return false
}
