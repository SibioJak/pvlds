package main

// Exit arbitrator: the decision logic for the merged exit duty
// (platform-free, unit-tested on Linux; the button feed and the
// window snapshot are platform leaves, the sends are the closer's
// own - closer_windows.go / closer_other.go).
//
// Why this exists: the gesture mapping Chris settled, matching
// VPX Launcher's. During a live session, a TAP of the exit button
// means "back to table selection" and a HOLD of the same button
// means "leave me in the VPX editor; PVLDS stands down". VPX's
// own tap handling always lands in the editor first - nothing
// outside VPX can change that - so the two gestures arrive here
// looking identical: game process alive, player window gone,
// editor window present. They differ only in what the button does
// NEXT, which is what this brain watches:
//
//   - The hold watch (main.go) tracks the configured exit button
//     continuously during live sessions and publishes a
//     buttonSnapshot per poll (~50ms). The press that exited the
//     table normally BEGAN during play (VPX exits on the press),
//     so by the time the editor landing is observed the press is
//     already in progress, with its true start time.
//   - The landing (the closer's composite: player seen, player
//     gone, editor present) opens an arbitration window. The
//     governing press is: the press in progress at the landing,
//     or the latest press released shortly before it (a quick tap
//     can complete before the window state settles), or a press
//     that begins inside the window.
//   - Governing press released before the hold threshold -> TAP:
//     the orderly close ladder fires after a short release
//     debounce, and the ordinary death/relaunch machinery returns
//     the player to the room - the closer's trip, decided by the
//     button instead of a 2.5s sustain.
//   - Governing press still held when the threshold passes ->
//     BAIL: no close is ever sent for that gesture; the caller
//     disarms the contract ("hold to editor") and stands down,
//     leaving VPX open in the editor.
//   - No press at the landing and none begins within a short
//     grace (keyboard / menu / crash-to-editor exits) -> TAP after
//     the grace: the return still happens, promptly.
//
// Arming mirrors the closer's: the player window must have been
// observed at least once this session before any landing counts -
// editor-present + player-absent during a load is the load state,
// never an exit.
//
// This brain runs ONLY in arbitration mode (both desk switches
// on). The mode table lives at the dispatch in main.go.

// buttonSnapshot is the hold watch's published view of the
// configured exit button for one session (see pressTracker).
type buttonSnapshot struct {
	pressed          bool  // the button is down right now
	pressStartMs     int64 // when the current continuous press began; valid while pressed
	lastPressStartMs int64 // when the most recent press began (this session)
	lastReleaseMs    int64 // when the most recent press ended; 0 = none released yet
	anyPress         bool  // any press observed this session
}

// pressTracker turns the raw polled button level into a
// buttonSnapshot. It lives on the hold-watch goroutine; only the
// published snapshot crosses to the main loop (mutex-guarded
// there). Session changes reset it.
type pressTracker struct {
	sessionID      int
	pressed        bool
	pressStartMs   int64
	lastPressStart int64
	lastReleaseMs  int64
	anyPress       bool
}

func (t *pressTracker) observe(nowMs int64, sessionID int, pressed bool) buttonSnapshot {
	if sessionID != t.sessionID {
		*t = pressTracker{sessionID: sessionID}
	}
	if pressed && !t.pressed {
		t.pressed = true
		t.pressStartMs = nowMs
		t.lastPressStart = nowMs
		t.anyPress = true
	} else if !pressed && t.pressed {
		t.pressed = false
		t.lastReleaseMs = nowMs
	}
	return t.snapshot()
}

func (t *pressTracker) reset(sessionID int) buttonSnapshot {
	*t = pressTracker{sessionID: sessionID}
	return t.snapshot()
}

func (t *pressTracker) snapshot() buttonSnapshot {
	return buttonSnapshot{
		pressed:          t.pressed,
		pressStartMs:     t.pressStartMs,
		lastPressStartMs: t.lastPressStart,
		lastReleaseMs:    t.lastReleaseMs,
		anyPress:         t.anyPress,
	}
}

// arbAction is what one arbitrator tick decided.
type arbAction int

const (
	arbNone         arbAction = iota
	arbCloseFEC               // TAP resolved: send the FrontEndControls CLOSE_APP now
	arbCloseWMClose           // escalate: send WM_CLOSE to the editor window now
	arbGiveUp                 // the close never landed; log it and leave VPX alone
	arbBail                   // HOLD resolved: disarm ("hold to editor") and stand down
)

const (
	// After a governing release, wait this long before firing the
	// TAP close: long enough that a release-then-repress reads as
	// a new gesture, short enough that the return feels instant.
	arbReleaseDebounceMs = 150
	// A landing with no press in progress gets this long for a
	// press to begin (and govern) before it resolves as a TAP on
	// its own - keyboard/menu/crash exits return without the old
	// 2.5s sustain, but a deliberate press is never raced.
	arbNoPressGraceMs = 500
	// A press released this long BEFORE the landing can still be
	// the governing press (a tap can complete while the window
	// state settles). Older releases are some earlier play input,
	// not this exit.
	arbReleasedPressRecencyMs = 5000
)

type exitArbitrator struct {
	sessionID  int
	playerSeen bool // arming: a player window observed at least once this session

	windowOpen  bool  // the editor landing is being arbitrated
	landingMs   int64 // when the current window opened
	governing   bool  // a press governs this window
	govStartMs  int64 // when the governing press began
	govReleased bool  // the governing press has been released
	govRelease  int64 // when it was released

	tapPending bool  // a TAP resolution is scheduled
	fireAtMs   int64 // when it fires
	bailed     bool  // terminal for this session's arbitration

	stage      int   // 0 undecided/watching, 1 FEC sent, 2 WM_CLOSE sent, 3 gave up
	actionAtMs int64 // when the current stage's action went out
}

// tick advances the arbitrator by one watchdog tick. It is fed
// only in arbitration mode (both switches on); the caller passes
// the session's live-ness through state/alive like the closer's
// tick. Each escalation step fires at most once per window; the
// bail fires at most once per session.
func (a *exitArbitrator) tick(nowMs int64, sessionID int, state string, alive bool, ws windowState, btn buttonSnapshot) arbAction {
	if sessionID != a.sessionID {
		*a = exitArbitrator{sessionID: sessionID}
	}
	if a.bailed {
		return arbNone
	}
	// Arming latches exactly like the closer's: any tick that
	// observes the player window, loading phase included.
	if alive && ws.playerPresent {
		a.playerSeen = true
	}
	// The escalation ladder runs on its own clock once the TAP
	// close has gone out; from there the gesture is resolved and
	// no button movement can turn it into a bail.
	switch a.stage {
	case 1:
		if nowMs-a.actionAtMs >= fecGraceMs {
			a.stage = 2
			a.actionAtMs = nowMs
			return arbCloseWMClose
		}
	case 2:
		if nowMs-a.actionAtMs >= closeGiveUpMs {
			a.stage = 3
			return arbGiveUp
		}
	}
	if a.stage != 0 {
		return arbNone
	}
	if state != "live" || !alive {
		a.windowOpen = false
		a.governing = false
		a.tapPending = false
		return arbNone
	}
	editorReturned := a.playerSeen && !ws.playerPresent && ws.editorPresent
	if !editorReturned {
		// No window (still playing, or the composite broke before
		// resolving): any partial arbitration is void.
		a.windowOpen = false
		a.governing = false
		a.tapPending = false
		return arbNone
	}
	if !a.windowOpen {
		// The landing. Pick the governing press.
		a.windowOpen = true
		a.landingMs = nowMs
		a.governing = false
		a.govReleased = false
		a.tapPending = false
		switch {
		case btn.pressed:
			a.governing = true
			a.govStartMs = btn.pressStartMs
		case btn.anyPress && btn.lastReleaseMs > 0 && btn.lastPressStartMs > 0 &&
			nowMs-btn.lastReleaseMs <= arbReleasedPressRecencyMs:
			// A tap that completed while the window state was
			// still settling: it began before the landing and
			// its release is fresh - it is this exit's press.
			a.governing = true
			a.govStartMs = btn.lastPressStartMs
			a.govReleased = true
			a.govRelease = btn.lastReleaseMs
		}
		if a.governing && !a.govReleased && nowMs-a.govStartMs >= holdThresholdMs {
			// The threshold passed during play: the hold is
			// already complete at the landing.
			a.bailed = true
			return arbBail
		}
		if a.governing && a.govReleased {
			a.tapPending = true
			a.fireAtMs = a.govRelease + arbReleaseDebounceMs
		} else if !a.governing {
			a.tapPending = true
			a.fireAtMs = nowMs + arbNoPressGraceMs
		}
	}
	// Track the governing press while the window is open.
	if !a.governing && btn.pressed {
		// A press beginning inside the window governs (and
		// supersedes the no-press schedule).
		a.governing = true
		a.govStartMs = btn.pressStartMs
		a.govReleased = false
		a.tapPending = false
	}
	if a.governing && !a.govReleased {
		if btn.pressed {
			if nowMs-a.govStartMs >= holdThresholdMs {
				a.bailed = true
				return arbBail
			}
		} else {
			a.govReleased = true
			a.govRelease = btn.lastReleaseMs
			if a.govRelease == 0 {
				a.govRelease = nowMs
			}
			a.tapPending = true
			a.fireAtMs = a.govRelease + arbReleaseDebounceMs
		}
	}
	if a.tapPending && nowMs >= a.fireAtMs {
		a.tapPending = false
		a.stage = 1
		a.actionAtMs = nowMs
		return arbCloseFEC
	}
	return arbNone
}
