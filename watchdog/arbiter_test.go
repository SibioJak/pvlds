package main

import "testing"

// The exit arbitrator's decision logic (arbiter.go), exercised on
// Linux with stub window states and synthetic button snapshots -
// the same timelines the integration smokes drive through the
// stub button feed, pinned down deterministically here.

var (
	noBtn = buttonSnapshot{}
)

// heldBtn is a snapshot with the button down in a press that began
// at startMs.
func heldBtn(startMs int64) buttonSnapshot {
	return buttonSnapshot{pressed: true, pressStartMs: startMs, lastPressStartMs: startMs, anyPress: true}
}

// releasedBtn is a snapshot whose latest press ran startMs..releaseMs.
func releasedBtn(startMs, releaseMs int64) buttonSnapshot {
	return buttonSnapshot{pressed: false, lastPressStartMs: startMs, lastReleaseMs: releaseMs, anyPress: true}
}

// armArb plays the arming prologue: the player window observed
// during the loading phase (what latches playerSeen).
func armArb(a *exitArbitrator, session int) {
	for t := int64(0); t <= 300; t += 100 {
		a.tick(t, session, "loading", true, playerState, noBtn)
	}
}

// arbTicks advances a in 100ms steps from fromMs to toMs in a live
// session with fixed window/button facts, returning the actions.
func arbTicks(a *exitArbitrator, fromMs, toMs int64, ws windowState, btn buttonSnapshot) []arbAction {
	var out []arbAction
	for t := fromMs; t <= toMs; t += 100 {
		if act := a.tick(t, 1, "live", true, ws, btn); act != arbNone {
			out = append(out, act)
		}
	}
	return out
}

func TestArbiterTapBeforeLanding(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// Play, then the exit press begins during play at t=1000.
	arbTicks(a, 500, 900, playerState, noBtn)
	if got := arbTicks(a, 1000, 1200, playerState, heldBtn(1000)); len(got) != 0 {
		t.Fatalf("acted during play: %v", got)
	}
	// The landing at t=1300, press still down (age 300ms).
	if got := arbTicks(a, 1300, 1500, editorState, heldBtn(1000)); len(got) != 0 {
		t.Fatalf("acted before the tap resolved: %v", got)
	}
	// Released at t=1600: the close fires after the 150ms debounce.
	if got := arbTicks(a, 1600, 1700, editorState, releasedBtn(1000, 1600)); len(got) != 0 {
		t.Fatalf("fired inside the release debounce: %v", got)
	}
	got := arbTicks(a, 1800, 1800, editorState, releasedBtn(1000, 1600))
	if len(got) != 1 || got[0] != arbCloseFEC {
		t.Fatalf("expected the TAP close after the debounce, got %v", got)
	}
}

func TestArbiterTapCompletedBeforeLanding(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// A quick tap at 1000-1200, entirely during play (the window
	// state settles after the gesture is already over).
	arbTicks(a, 1000, 1100, playerState, heldBtn(1000))
	arbTicks(a, 1200, 1200, playerState, releasedBtn(1000, 1200))
	// Landing at t=1300 with the released snapshot: the release
	// still governs, and the debounce (from the release) is
	// nearly spent - the close fires on the next tick.
	if got := arbTicks(a, 1300, 1300, editorState, releasedBtn(1000, 1200)); len(got) != 0 {
		t.Fatalf("fired on the landing tick itself: %v", got)
	}
	got := arbTicks(a, 1400, 1400, editorState, releasedBtn(1000, 1200))
	if len(got) != 1 || got[0] != arbCloseFEC {
		t.Fatalf("expected the TAP close right after the landed debounce, got %v", got)
	}
}

func TestArbiterTapAfterLanding(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// Landing at t=2000 with no press anywhere.
	if got := arbTicks(a, 2000, 2200, editorState, noBtn); len(got) != 0 {
		t.Fatalf("acted before any press: %v", got)
	}
	// A press begins inside the window at t=2300: it governs, so
	// the no-press resolution (due t=2500) must NOT fire.
	if got := arbTicks(a, 2300, 2500, editorState, heldBtn(2300)); len(got) != 0 {
		t.Fatalf("the no-press resolution raced a governing press: %v", got)
	}
	// Released at t=2600 (a tap): close after the debounce.
	if got := arbTicks(a, 2600, 2700, editorState, releasedBtn(2300, 2600)); len(got) != 0 {
		t.Fatalf("fired inside the release debounce: %v", got)
	}
	got := arbTicks(a, 2800, 2800, editorState, releasedBtn(2300, 2600))
	if len(got) != 1 || got[0] != arbCloseFEC {
		t.Fatalf("expected the TAP close, got %v", got)
	}
}

func TestArbiterHoldThroughThreshold(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	arbTicks(a, 1000, 1200, playerState, heldBtn(1000))
	// Landing at t=1300, still held: nothing until the threshold.
	if got := arbTicks(a, 1300, 2400, editorState, heldBtn(1000)); len(got) != 0 {
		t.Fatalf("acted before the hold threshold: %v", got)
	}
	got := arbTicks(a, 2500, 2500, editorState, heldBtn(1000))
	if len(got) != 1 || got[0] != arbBail {
		t.Fatalf("expected the bail at the threshold, got %v", got)
	}
	// The bail is terminal: no close ever follows for that gesture.
	if got := arbTicks(a, 2600, 30000, editorState, heldBtn(1000)); len(got) != 0 {
		t.Fatalf("acted after the bail: %v", got)
	}
}

func TestArbiterHoldCrossedBeforeLanding(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// A press held from t=400 through play (VPX slow to exit):
	// by the landing at t=2000 the threshold has long passed, so
	// the bail resolves on the landing tick itself.
	arbTicks(a, 400, 1900, playerState, heldBtn(400))
	got := arbTicks(a, 2000, 2000, editorState, heldBtn(400))
	if len(got) != 1 || got[0] != arbBail {
		t.Fatalf("expected an immediate bail for a hold completed during play, got %v", got)
	}
}

func TestArbiterNoPressLanding(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// Keyboard/menu/crash exit: no press ever. The return resolves
	// as a TAP after the 500ms grace - no 2.5s sustain.
	if got := arbTicks(a, 2000, 2400, editorState, noBtn); len(got) != 0 {
		t.Fatalf("fired inside the no-press grace: %v", got)
	}
	got := arbTicks(a, 2500, 2500, editorState, noBtn)
	if len(got) != 1 || got[0] != arbCloseFEC {
		t.Fatalf("expected the no-press TAP close after the grace, got %v", got)
	}
}

func TestArbiterLatePress(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	arbTicks(a, 2000, 2300, editorState, noBtn)
	// A press beginning shortly after the landing (inside the
	// window) is tracked the same way: held -> bail at ITS
	// threshold, not the landing's.
	if got := arbTicks(a, 2400, 3800, editorState, heldBtn(2400)); len(got) != 0 {
		t.Fatalf("acted before the late press's threshold: %v", got)
	}
	got := arbTicks(a, 3900, 3900, editorState, heldBtn(2400))
	if len(got) != 1 || got[0] != arbBail {
		t.Fatalf("expected the late press to bail at its threshold, got %v", got)
	}
}

func TestArbiterOldReleaseDoesNotGovern(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// An old tap during play (some input VPX did not exit on),
	// released long before the eventual landing: it must not
	// govern - the landing is a no-press landing.
	arbTicks(a, 1000, 1000, playerState, heldBtn(1000))
	arbTicks(a, 1100, 1100, playerState, releasedBtn(1000, 1100))
	arbTicks(a, 1200, 19900, playerState, releasedBtn(1000, 1100))
	if got := arbTicks(a, 20000, 20400, editorState, releasedBtn(1000, 1100)); len(got) != 0 {
		t.Fatalf("the stale release resolved the window early: %v", got)
	}
	got := arbTicks(a, 20500, 20500, editorState, releasedBtn(1000, 1100))
	if len(got) != 1 || got[0] != arbCloseFEC {
		t.Fatalf("expected the no-press grace resolution, got %v", got)
	}
}

func TestArbiterLadderEscalates(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// No-press landing fires FEC at t=2500; the ladder then runs
	// on the closer's constants: WM_CLOSE at +4000, give up at
	// +12000 more, and silence afterwards.
	got := arbTicks(a, 2000, 2500, editorState, noBtn)
	if len(got) != 1 || got[0] != arbCloseFEC {
		t.Fatalf("expected the FEC, got %v", got)
	}
	if got := arbTicks(a, 2600, 6400, editorState, noBtn); len(got) != 0 {
		t.Fatalf("escalated inside the FEC grace: %v", got)
	}
	got = arbTicks(a, 6500, 6500, editorState, noBtn)
	if len(got) != 1 || got[0] != arbCloseWMClose {
		t.Fatalf("expected the WM_CLOSE escalation, got %v", got)
	}
	if got := arbTicks(a, 6600, 18400, editorState, noBtn); len(got) != 0 {
		t.Fatalf("gave up inside the close window: %v", got)
	}
	got = arbTicks(a, 18500, 18500, editorState, noBtn)
	if len(got) != 1 || got[0] != arbGiveUp {
		t.Fatalf("expected the give-up, got %v", got)
	}
	if got := arbTicks(a, 18600, 60000, editorState, noBtn); len(got) != 0 {
		t.Fatalf("acted after giving up: %v", got)
	}
}

func TestArbiterUnarmedNeverFires(t *testing.T) {
	a := &exitArbitrator{}
	// No player window ever observed: editor-present is the load
	// state. No close, and no bail either, however long it lasts.
	if got := arbTicks(a, 0, 60000, editorState, noBtn); len(got) != 0 {
		t.Fatalf("fired unarmed: %v", got)
	}
	if got := arbTicks(a, 60100, 90000, editorState, heldBtn(60100)); len(got) != 0 {
		t.Fatalf("bailed unarmed: %v", got)
	}
}

func TestArbiterGates(t *testing.T) {
	a := &exitArbitrator{}
	armArb(a, 1)
	// Loading state: the composite never opens a window.
	for tm := int64(1000); tm <= 20000; tm += 100 {
		if act := a.tick(tm, 1, "loading", true, editorState, noBtn); act != arbNone {
			t.Fatalf("acted while loading at %d: %v", tm, act)
		}
	}
	// Dead process: nothing.
	for tm := int64(20100); tm <= 40000; tm += 100 {
		if act := a.tick(tm, 1, "live", false, editorState, heldBtn(20100)); act != arbNone {
			t.Fatalf("acted against a dead game at %d: %v", tm, act)
		}
	}
	// A new session starts fresh (no carried window or verdict).
	armArb(a, 2)
	for tm := int64(50000); tm <= 50400; tm += 100 {
		if act := a.tick(tm, 2, "live", true, editorState, noBtn); act != arbNone {
			t.Fatalf("the new session inherited state at %d: %v", tm, act)
		}
	}
}

func TestPressTracker(t *testing.T) {
	tr := &pressTracker{}
	s := tr.observe(100, 7, false)
	if s.pressed || s.anyPress {
		t.Fatalf("an idle poll invented a press: %+v", s)
	}
	s = tr.observe(200, 7, true)
	if !s.pressed || s.pressStartMs != 200 || s.lastPressStartMs != 200 || !s.anyPress {
		t.Fatalf("the press start was not stamped: %+v", s)
	}
	s = tr.observe(500, 7, true)
	if s.pressStartMs != 200 {
		t.Fatalf("a continuing press moved its start: %+v", s)
	}
	s = tr.observe(600, 7, false)
	if s.pressed || s.lastReleaseMs != 600 || s.lastPressStartMs != 200 {
		t.Fatalf("the release was not stamped: %+v", s)
	}
	// A new session wipes the history: no stale release can govern.
	s = tr.observe(700, 8, true)
	if !s.pressed || s.pressStartMs != 700 || s.lastReleaseMs != 0 {
		t.Fatalf("the session change did not reset the tracker: %+v", s)
	}
	s = tr.reset(9)
	if s.pressed || s.anyPress {
		t.Fatalf("reset left state behind: %+v", s)
	}
}
