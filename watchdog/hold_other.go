//go:build !windows

package main

// Hold-to-exit: the button feed off Windows. There is no XInput
// here and no real controller to read; the Linux build exists to
// exercise the DECISION logic (hold_logic.go) end to end in
// smokes. The feed is a stub the harness drives, in the same
// spirit as stub_vpx's editor marker: a small text file holding
// the bit mask of the buttons currently "held". Its path comes
// from PVLDS_STUB_BUTTON_FILE (default /tmp/pvlds-stub-buttons);
// a missing or unparseable file means "nothing held". The
// shipping Windows feed is hold_windows.go.

import (
	"os"
	"strconv"
	"strings"
)

func stubButtonFilePath() string {
	if p := os.Getenv("PVLDS_STUB_BUTTON_FILE"); p != "" {
		return p
	}
	return "/tmp/pvlds-stub-buttons"
}

// anyButtonPressed reports whether any bit of mask is set in the
// stub feed's currently-held mask.
func anyButtonPressed(mask uint16) bool {
	if mask == 0 {
		return false
	}
	data, err := os.ReadFile(stubButtonFilePath())
	if err != nil {
		return false
	}
	v, err := strconv.ParseUint(strings.TrimSpace(string(data)), 0, 32)
	if err != nil {
		return false
	}
	return uint16(v)&mask != 0
}
