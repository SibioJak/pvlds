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

// stubPlayerHiddenMarker is the smoke stub's "my player window
// is hidden" signal: while the marker stands, the stub's player
// observation carries visible=false - present in the unfiltered
// window set the sighting gate reads, absent from the visible
// set herding would use. It mirrors the Windows field fault of
// 2026-10-22: the player rendering into a VR headset holds a
// window with no desktop visibility at all.
func stubPlayerHiddenMarker(gamePID int) string {
	return "/tmp/pvlds-stub-player-hidden-" + strconv.Itoa(gamePID)
}

// stubForegroundMarker scripts the FOREGROUND fact the exit
// detector (closer.go) reads: the file's contents name who
// holds the foreground - "editor" (the game pid's editor
// frame) or "other" (anything else: the player, Virtual
// Desktop, a dialog). The stub writes it through its phases
// the way the real rig behaves (editor at the spawn instant,
// away during play, editor again when the table exit lands -
// the field shape from sessions 25/26, 2026-10-23), with env
// knobs for the shapes a scenario needs to force (see
// stub_vpx_window.c). An absent file reads as "other": the
// foreground is simply not known to be the editor, which is
// the detector's safe default.
func stubForegroundMarker(gamePID int) string {
	return "/tmp/pvlds-stub-foreground-" + strconv.Itoa(gamePID)
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

// gameWindowState on Linux (smoke build only) gathers the same
// two facts the Windows leaf does. The sighting gate is fed
// sighting observations: the editor marker is a "VPinball"-
// class observation, VISIBLE (the editor is a presented frame
// wherever the facts matter; and while the marker stands, the
// player is gone - the stub's exit-to-editor state); the maps
// signal is a player-window observation carrying the stub's
// declared class at the stub window's real size (400x300),
// with visible=false while the hidden marker stands - the
// unfiltered gate must count it anyway (see
// stubPlayerHiddenMarker). The stub drops the editor marker
// in two situations the smokes keep distinct by session shape:
// its table-exit-to-editor moment (after a player phase), and
// - with STUB_EDITOR_FIRST_S - from birth, modelling VPX's
// startup order (editor frame first, player window only after
// the table loads), which is the state the detector's sighting
// half exists for. The foreground fact comes from the
// foreground marker (stubForegroundMarker): "editor" is the
// only content that marks the editor as foreground. No editor
// handle exists off Windows.
func gameWindowState(gamePID int, sessionID int) windowState {
	var ws windowState
	if gamePID <= 0 {
		return ws
	}
	var obs []windowObs
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		obs = append(obs, windowObs{class: editorWindowClass, width: 1280, height: 900, visible: true})
	} else if gameWindowPresentOnMaps(gamePID) {
		visible := true
		if _, err := os.Stat(stubPlayerHiddenMarker(gamePID)); err == nil {
			visible = false
		}
		obs = append(obs, windowObs{class: stubPlayerClass(gamePID), width: 400, height: 300, visible: visible})
	}
	candidate, rule := classifyPlayerCandidate(obs)
	playerSight.observe(sessionID, candidate, rule)
	if b, err := os.ReadFile(stubForegroundMarker(gamePID)); err == nil && strings.TrimSpace(string(b)) == "editor" {
		ws.fgIsEditor = true
	}
	return ws
}
