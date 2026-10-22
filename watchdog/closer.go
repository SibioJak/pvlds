package main

// Session-close duty: the decision logic (platform-free, unit-tested
// on Linux; the window snapshot and the message-sending are platform
// leaves - closer_windows.go / closer_other.go, windows_state_*.go).
//
// Why this exists: VPX has no exit-after-table flag. The "-exit" once
// shipped in the launcher's default template came from frontend
// folklore; in vpinball's own parser the token is OPTION_FRONTEND_EXIT,
// commented "(ab)used by frontend, not handled by us"
// (src/core/AppCommands.cpp in vpinball/vpinball). The ecosystem's
// real pattern (PinballY) is that THE FRONTEND CLOSES VPX after a
// table exit. So when a live session's table exit lands the player
// in the VPX editor - game process alive, player window gone, editor
// window present - the watchdog asks VPX to close, orderly, and the
// ordinary process-death machinery brings the launcher back.
//
// The window discriminator is grounded in the vpinball source, not
// folklore: the player and its ancillary windows are SDL windows of
// class "VPPlayer" (SDL_RegisterApp("VPPlayer", ...) in
// src/core/VPApp.cpp), while the editor main frame registers the
// Win32 class "VPinball" (WinEditor::PreRegisterClass in
// src/ui/win/WinEditor.cpp). Neither cue alone fires the duty; the
// composite (player gone AND editor present), sustained, does.
//
// ARMING (the load-window fix): the editor frame exists from the
// moment VPX starts, but the player window is created only when a
// table's play begins - after the .vpx file has loaded. During a
// slow load, "editor present, player absent" is therefore TRUE for
// the wrong reason, and an unarmed duty reads it as a table exit
// and closes VPX mid-load (Chris's field failure on the first
// build with this duty: launch, freeze, flicker, back in the room,
// no game). So the duty is armed per session: it may fire only
// after a player window has been OBSERVED at least once in the
// session, under the sighting rule in sighting.go (a VPPlayer-class
// window, or - class-independently - a substantial non-editor
// window that persists across two polls; the editor class itself
// never counts). Player-never-seen + editor-present means "still
// loading", forever safe - the sustain clock does not even run.
//
// Escalation, per the design brief: (1) the PinSim::FrontEndControls
// terminate request (published protocol; PinballY's Application.cpp
// is the reference sender: RegisterWindowMessage("PinSim::
// FrontEndControls"), wParam 2 = CLOSE_APP, a reply of 1 acks);
// (2) WM_CLOSE to the editor main window. VP's own editor refuses
// WM_CLOSE while a player is open (WinEditor::OnClose: "Reject close
// if player was not closed before"), so step 2 cannot kill a live
// table - it only lands in exactly the state this duty targets.
// Never a hard process kill. If neither lands, log and leave VPX
// alone.

// windowState is one snapshot of the game process's top-level
// windows, classified by the platform leaf.
type windowState struct {
	playerPresent bool    // the sighting rule (sighting.go) counts a player window present
	editorPresent bool    // a visible "VPinball"-class editor frame exists
	editorHWND    uintptr // the editor frame (Windows close target); 0 elsewhere
}

// closeAction is what one closer tick decided.
type closeAction int

const (
	closeNone    closeAction = iota
	closeFEC                 // send the FrontEndControls CLOSE_APP request now
	closeWMClose             // send WM_CLOSE to the editor window now
	closeGiveUp              // nothing landed; log it and leave VPX alone
)

const (
	// How long the editor-returned state must hold before the first
	// close request: a transient window shuffle is not an exit.
	editorSustainMs = 2500
	// Grace after the FrontEndControls request before escalating to
	// WM_CLOSE (an acked request still needs a moment to act).
	fecGraceMs = 4000
	// After WM_CLOSE, wait this long for the process to die before
	// concluding the close did not land.
	closeGiveUpMs = 12000
)

type closer struct {
	sessionID     int
	playerSeen    bool  // arming: a player window observed at least once this session
	editorSinceMs int64 // first tick of the current sustained editor state; 0 = not in it
	stage         int   // 0 watching, 1 FEC sent, 2 WM_CLOSE sent, 3 gave up
	actionAtMs    int64 // when the current stage's action went out
}

// tick advances the duty by one watchdog tick. It only acts in a
// live session with the duty enabled and the game process alive, and
// fires each escalation step at most once per session. A new
// sessionID resets everything: the next session starts fresh.
func (cl *closer) tick(nowMs int64, sessionID int, state string, enabled bool, alive bool, ws windowState) closeAction {
	if sessionID != cl.sessionID {
		*cl = closer{sessionID: sessionID}
	}
	// Arming latches on ANY live-process tick that observes the
	// player window - including ticks during the loading phase
	// (the launcher still resident): a fast table can raise its
	// player before the launcher exits, and that sighting is real.
	if alive && ws.playerPresent {
		cl.playerSeen = true
	}
	if !enabled || state != "live" || !alive {
		// Never while the launcher is resident/loading, never with
		// the switch off, never against a dead process. A broken
		// editor state also restarts the sustain clock.
		cl.editorSinceMs = 0
		return closeNone
	}
	// Unarmed (the player window has never been seen this session):
	// editor-present is the load state, not an exit. Never fires,
	// and the sustain clock stays at zero.
	editorReturned := cl.playerSeen && !ws.playerPresent && ws.editorPresent
	if !editorReturned {
		cl.editorSinceMs = 0
		return closeNone
	}
	if cl.editorSinceMs == 0 {
		cl.editorSinceMs = nowMs
	}
	switch cl.stage {
	case 0:
		if nowMs-cl.editorSinceMs >= editorSustainMs {
			cl.stage = 1
			cl.actionAtMs = nowMs
			return closeFEC
		}
	case 1:
		if nowMs-cl.actionAtMs >= fecGraceMs {
			cl.stage = 2
			cl.actionAtMs = nowMs
			return closeWMClose
		}
	case 2:
		if nowMs-cl.actionAtMs >= closeGiveUpMs {
			cl.stage = 3
			return closeGiveUp
		}
	}
	return closeNone
}
