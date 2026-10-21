package main

import (
	"os"
	"strconv"
	"strings"
)

// gameWindowExists on Linux. The Linux watchdog build exists to
// exercise the platform-free session logic in this repo's smokes -
// it never ships anywhere (the shipping watchdog is the Windows
// build, whose gameWindowExists is a real user32 enumeration).
// Under X11 the honest-enough signal available without cgo or
// external tools is the game's memory map: a process that has
// opened a display and created its window carries an X client
// library (libX11 / libxcb) mapped; a process still in its early
// load does not. The smokes' stub VPX is built to exactly that
// contract: a plain first stage that exec()s (same pid) into an
// X-linked second stage when its "window" phase begins - the same
// shape as a real binary pulling its display stack in as it comes
// up, and the reason a single X-linked stub would be useless here
// (it would map libX11 from birth).
func gameWindowExists(gamePID int) bool {
	if gamePID <= 0 {
		return false
	}
	maps, err := os.ReadFile("/proc/" + strconv.Itoa(gamePID) + "/maps")
	if err != nil {
		return false
	}
	s := string(maps)
	return strings.Contains(s, "libX11") || strings.Contains(s, "libxcb")
}
