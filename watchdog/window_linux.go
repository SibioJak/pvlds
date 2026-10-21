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

// stubEditorMarker is the smoke stub's "I am sitting in the editor
// now" signal: a file in the temp dir named by pid. There is no
// real VPX on Linux to enumerate; the stub contract is how the
// session-close DECISION logic (closer.go) gets exercised end to
// end here, the same spirit as the maps contract above.
func stubEditorMarker(gamePID int) string {
	return "/tmp/pvlds-stub-editor-" + strconv.Itoa(gamePID)
}

// gameWindowState on Linux (smoke build only): the player is
// "present" while the stub is in its X-linked window phase and no
// editor marker exists; the editor is "present" once the stub
// drops its marker (its table-exit-to-editor moment). No editor
// handle exists off Windows.
func gameWindowState(gamePID int) windowState {
	var ws windowState
	if gamePID <= 0 {
		return ws
	}
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		ws.editorPresent = true
		return ws
	}
	ws.playerPresent = gameWindowExists(gamePID)
	return ws
}
