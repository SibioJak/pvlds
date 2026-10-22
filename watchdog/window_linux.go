package main

import (
	"os"
	"strconv"
	"strings"
)

// The Linux watchdog build exists to exercise the platform-free
// session logic in this repo's smokes - it never ships anywhere
// (the shipping watchdog is the Windows build, whose window
// facts are a real user32 enumeration). The stub contract below
// is how the shared DECISION logic (closer.go, sighting.go)
// gets exercised end to end here.
//
// gameWindowPresentOnMaps is the existence signal for the stub's
// player window: a process that has opened a display and created
// its window carries an X client library (libX11 / libxcb)
// mapped; a process still in its early load does not. The smokes'
// stub VPX is built to exactly that contract: a plain first stage
// that exec()s (same pid) into an X-linked second stage when its
// "window" phase begins - the same shape as a real binary pulling
// its display stack in as it comes up, and the reason a single
// X-linked stub would be useless here (it would map libX11 from
// birth).
func gameWindowPresentOnMaps(gamePID int) bool {
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

// stubPlayerClass names the Win32 class the stub's player window
// "carries" for the sighting rule: the contents of a marker file
// the smoke writes for the stub's pid (e.g. "SDL_app" rehearses a
// player window of some class the classic rule would miss). No
// marker = the stub plays a classic "VPPlayer" window.
func stubPlayerClass(gamePID int) string {
	b, err := os.ReadFile("/tmp/pvlds-stub-playerclass-" + strconv.Itoa(gamePID))
	if err != nil {
		return playerWindowClass
	}
	if s := strings.TrimSpace(string(b)); s != "" {
		return s
	}
	return playerWindowClass
}

// playerSight is this leaf's sighting gate (sighting.go) - the
// same shared gate the Windows leaf feeds, so the smokes exercise
// the shipped rule, persistence included.
var playerSight playerSighting

// gameWindowExists on Linux: whether a player sighting has
// STAMPED for this session, and the rule that stamped it - the
// sighting gate's latch, exactly as the Windows leaf reports it.
func gameWindowExists(gamePID int, sessionID int) (bool, string) {
	if gamePID <= 0 {
		return false, ""
	}
	return playerSight.hasSighted(sessionID)
}

// gameWindowState on Linux (smoke build only), expressed as
// sighting observations and folded through the shared gate: the
// editor marker is a "VPinball"-class observation (and while it
// stands, the player is gone - the stub's exit-to-editor state);
// the maps signal is a player-window observation carrying the
// stub's declared class at the stub window's real size
// (400x300). The stub drops the editor marker in two situations
// the smokes keep distinct by session shape: its
// table-exit-to-editor moment (after a player phase), and - with
// STUB_EDITOR_FIRST_S - from birth, modelling VPX's startup order
// (editor frame first, player window only after the table loads),
// which is the state the closer's arming gate exists for. No
// editor handle exists off Windows.
func gameWindowState(gamePID int, sessionID int) windowState {
	var ws windowState
	if gamePID <= 0 {
		return ws
	}
	var obs []windowObs
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		ws.editorPresent = true
		obs = append(obs, windowObs{class: editorWindowClass, width: 1280, height: 900})
	} else if gameWindowPresentOnMaps(gamePID) {
		obs = append(obs, windowObs{class: stubPlayerClass(gamePID), width: 400, height: 300})
	}
	candidate, rule := classifyPlayerCandidate(obs)
	present, _ := playerSight.observe(sessionID, candidate, rule)
	ws.playerPresent = present
	return ws
}
