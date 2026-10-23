package main

// Session-close duty: the exit detector (platform-free decision
// logic, unit-tested on Linux) plus the orderly close ladder it
// fires. The window/foreground snapshot and the message-sending
// are platform leaves (closer_windows.go / closer_other.go,
// herd_windows.go / window_linux.go).
//
// Why this exists: VPX has no exit-after-table flag. The "-exit"
// once shipped in the launcher's default template came from
// frontend folklore; in vpinball's own parser the token is
// OPTION_FRONTEND_EXIT, commented "(ab)used by frontend, not
// handled by us" (src/core/AppCommands.cpp in vpinball/vpinball).
// The ecosystem's real pattern (PinballY) is that THE FRONTEND
// CLOSES VPX after a table exit. So when a live session's table
// exit lands the player in the VPX editor, the watchdog asks VPX
// to close, orderly, and the ordinary process-death machinery
// brings the launcher back.
//
// THE TRIGGER IS THE FOREGROUND (field forensics, Chris's rig,
// sessions 25/26, 2026-10-23). The previous trigger - player
// window gone AND editor window present - can never fire on his
// rig: the sighting stamps reliably now, but off a hidden
// "CVFrame" 1401x809 window that PERSISTS in the editor state
// after a table exits. CVFrame is VPX's editor canvas, not the
// player, so player-presence never drops and the composite never
// completes. What IS clean in his window data is the foreground:
// during load and play it cycles Virtual Desktop's window, the
// loading dialog, the SDL window, PinMAME - the editor window
// holds it only at the spawn instant and again exactly when a
// table exit lands. So the detector reads exactly that:
//
//   ARMING (both, observed in a live session): (a) the sighting
//   has stamped for this session (sighting.go; the table
//   demonstrably loaded - the editor frame is up from VPX's
//   start, so an unstamped session is a load, not an exit), and
//   (b) an EXCURSION: at least one live tick whose foreground
//   was NOT the editor window (play demonstrably took the
//   foreground story away from the editor; without one, an
//   editor foreground is just the spawn state continuing, and
//   a silent exit inside it is undetectable BY DESIGN - the
//   detector stays unarmed rather than guess).
//
//   FIRE: the editor window then holds the foreground
//   continuously for editorForegroundSustainMs. Any tick whose
//   foreground is not the editor resets the sustain clock -
//   elapsed time is compared, never tick counts, so cadence
//   jitter cannot stretch or shrink the sustain.
//
// THE LADDER (unchanged from the window-trigger era): (1) the
// PinSim::FrontEndControls terminate request (published
// protocol; PinballY's Application.cpp is the reference sender:
// RegisterWindowMessage("PinSim::FrontEndControls"), wParam 2 =
// CLOSE_APP, a reply of 1 acks); (2) after a grace, WM_CLOSE to
// the editor main window - which VP's own editor refuses while
// a player is open (WinEditor::OnClose: "Reject close if player
// was not closed before"), so step 2 cannot kill a live table.
// Never a hard process kill. If neither lands, log and leave
// VPX alone; the detector stands down for the session.

// windowState is one snapshot of the game process's window and
// foreground facts, classified by the platform leaf.
type windowState struct {
	fgIsEditor bool    // the foreground window IS the game pid's editor frame
	editorHWND uintptr // the editor frame (Windows WM_CLOSE target); 0 elsewhere
}

// closeAction is what one detector tick decided.
type closeAction int

const (
	closeNone    closeAction = iota
	closeFEC                 // send the FrontEndControls CLOSE_APP request now
	closeWMClose             // send WM_CLOSE to the editor window now
	closeGiveUp              // nothing landed; log it and leave VPX alone
)

const (
	// How long the editor must HOLD the foreground, continuously,
	// before the close fires: the landing confirmation. Long
	// enough that a transient editor focus (a dialog shuffle, a
	// herding-era blip) is not an exit; short enough that the
	// return still feels prompt. Elapsed milliseconds are
	// compared, so the 400ms tick cadence (~3 ticks) cannot
	// stretch it.
	editorForegroundSustainMs = 1200
	// Grace after the FrontEndControls request before escalating
	// to WM_CLOSE (an acked request still needs a moment to act).
	fecGraceMs = 4000
	// After WM_CLOSE, wait this long for the process to die
	// before concluding the close did not land.
	closeGiveUpMs = 12000
)

// closer is the per-session exit detector + close ladder. The
// duty is unconditional - there is no switch - but it only acts
// in a live session with the game process alive, armed as
// described above, and fires each escalation step at most once
// per session. A new sessionID resets everything.
type closer struct {
	sessionID     int
	excursion     bool  // arming half (b): a live tick whose foreground was not the editor
	armed         bool  // both arming halves latched; the arm is reported once, on its tick
	editorSinceMs int64 // first tick of the current sustained editor foreground; 0 = not in it
	stage         int   // 0 watching, 1 FEC sent, 2 WM_CLOSE sent, 3 gave up
	actionAtMs    int64 // when the current stage's action went out
}

// tick advances the detector by one watchdog tick. sighted is
// the sighting gate's latch for this session (the contract's
// game_window_seen - arming half (a)). The second return reports
// the arm event: true on exactly the tick the detector armed,
// so the caller can log it once per session.
func (cl *closer) tick(nowMs int64, sessionID int, state string, alive bool, sighted bool, ws windowState) (closeAction, bool) {
	if sessionID != cl.sessionID {
		*cl = closer{sessionID: sessionID}
	}
	if state != "live" || !alive {
		// Never while the launcher is resident/loading, never
		// against a dead process. Arming observations are a
		// live-session story only; a broken editor foreground
		// also restarts the sustain clock.
		cl.editorSinceMs = 0
		return closeNone, false
	}
	// Arming. The excursion half registers on any live tick
	// whose foreground is away from the editor - before or
	// after the sighting stamps; both orders arm.
	if !ws.fgIsEditor && !cl.excursion {
		cl.excursion = true
	}
	armedNow := false
	if !cl.armed && sighted && cl.excursion {
		cl.armed = true
		armedNow = true
	}
	if !cl.armed {
		// Unarmed, the editor holding the foreground is the
		// load/spawn state continuing - never an exit, and the
		// sustain clock does not run.
		cl.editorSinceMs = 0
		return closeNone, armedNow
	}
	if !ws.fgIsEditor {
		// The foreground left the editor: any sustain in
		// progress is broken, and a ladder already fired
		// pauses here (its stage waits for the editor state
		// to return, exactly as the window-trigger ladder
		// did) - it never advances against a foreground that
		// says the player is somewhere else.
		cl.editorSinceMs = 0
		return closeNone, armedNow
	}
	if cl.editorSinceMs == 0 {
		cl.editorSinceMs = nowMs
	}
	switch cl.stage {
	case 0:
		if nowMs-cl.editorSinceMs >= editorForegroundSustainMs {
			cl.stage = 1
			cl.actionAtMs = nowMs
			return closeFEC, armedNow
		}
	case 1:
		if nowMs-cl.actionAtMs >= fecGraceMs {
			cl.stage = 2
			cl.actionAtMs = nowMs
			return closeWMClose, armedNow
		}
	case 2:
		if nowMs-cl.actionAtMs >= closeGiveUpMs {
			cl.stage = 3
			return closeGiveUp, armedNow
		}
	}
	return closeNone, armedNow
}
