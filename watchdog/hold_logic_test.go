package main

import "testing"

// The hold-to-exit DECISION logic (hold_logic.go), exercised on
// Linux. The button snapshots are booleans here exactly as the
// integration smokes feed them (hold_other.go's stub feed); the
// Windows XInput leaf is compile-verified only - what these tests
// prove is when the gesture counts, when it fires, and that it
// fires exactly once per hold.

// runHold advances d in 50ms steps (the watch's poll cadence)
// from fromMs to toMs, returning the actions produced, in order.
func runHold(d *holdDuty, fromMs, toMs int64, session int, active bool, pressed bool) []holdAction {
	var out []holdAction
	for t := fromMs; t <= toMs; t += 50 {
		if a := d.tick(t, session, active, pressed); a != holdNone {
			out = append(out, a)
		}
	}
	return out
}

func TestHoldButtonTable(t *testing.T) {
	// The recorded binding: right directional = D-pad Right.
	if m, ok := holdButtonMask("dpad_right"); !ok || m != 0x0008 {
		t.Fatalf("dpad_right must resolve to the XInput bit 0x0008, got %#x, %v", m, ok)
	}
	if m, ok := holdButtonMask(defaultHoldButton); !ok || m != 0x0008 {
		t.Fatalf("the default button must be D-pad Right, got %#x, %v", m, ok)
	}
	// The whole standard set resolves; a nonsense name does not.
	for name := range xinputButtonMasks {
		if _, ok := holdButtonMask(name); !ok {
			t.Fatalf("button %q in the table does not resolve", name)
		}
	}
	if _, ok := holdButtonMask("paddle_9"); ok {
		t.Fatalf("an unknown button name resolved")
	}
	if len(xinputButtonMasks) != 14 {
		t.Fatalf("the standard XInput set is 14 named buttons, got %d", len(xinputButtonMasks))
	}
}

func TestHoldFiresAtThreshold(t *testing.T) {
	d := &holdDuty{}
	// Pressed from t=100: quiet through 1550 (1450ms in).
	if got := runHold(d, 100, 1550, 1, true, true); len(got) != 0 {
		t.Fatalf("fired before the 1500ms threshold: %v", got)
	}
	// The threshold crossing (1600 = press + 1500ms) fires once.
	got := runHold(d, 1600, 1650, 1, true, true)
	if len(got) != 1 || got[0] != holdFEC {
		t.Fatalf("expected exactly the FrontEndControls fire at the threshold, got %v", got)
	}
}

func TestHoldTapDoesNothing(t *testing.T) {
	d := &holdDuty{}
	// A 400ms tap: the VPX-bound half of the gesture. Silence.
	if got := runHold(d, 100, 500, 1, true, true); len(got) != 0 {
		t.Fatalf("a tap produced an action: %v", got)
	}
	if got := runHold(d, 550, 10000, 1, true, false); len(got) != 0 {
		t.Fatalf("actions after a tap's release: %v", got)
	}
	// A hold that breaks just short of the threshold restarts
	// from zero - two 1400ms presses are not one 2800ms hold.
	runHold(d, 10100, 11500, 1, true, true)
	runHold(d, 11550, 11600, 1, true, false)
	if got := runHold(d, 11650, 13000, 1, true, true); len(got) != 0 {
		t.Fatalf("two broken holds summed into a fire: %v", got)
	}
	// The second hold began at 11650; its crossing is at 13150.
	if got := runHold(d, 13050, 13200, 1, true, true); len(got) != 1 || got[0] != holdFEC {
		t.Fatalf("expected the fire once the second hold truly crossed, got %v", got)
	}
}

func TestHoldFiresOncePerHoldAndReArmsOnRelease(t *testing.T) {
	d := &holdDuty{}
	// Hold for a full minute: exactly one fire (the escalation
	// runs its course off that fire - see the ladder test - and
	// no second FEC ever comes out of the same hold).
	got := runHold(d, 100, 60000, 1, true, true)
	fec := 0
	for _, a := range got {
		if a == holdFEC {
			fec++
		}
	}
	if fec != 1 {
		t.Fatalf("a single endless hold fired %d times, want 1 (actions %v)", fec, got)
	}
	// Release, then hold again: a NEW deliberate gesture fires
	// again (the give-up left VPX open; the player is asking
	// once more).
	runHold(d, 60100, 61000, 1, true, false)
	got = runHold(d, 61100, 62600, 1, true, true)
	if len(got) != 1 || got[0] != holdFEC {
		t.Fatalf("expected a fresh fire after release + re-hold, got %v", got)
	}
}

func TestHoldEscalationLadder(t *testing.T) {
	d := &holdDuty{}
	var got []holdAction
	got = append(got, runHold(d, 100, 1600, 1, true, true)...)   // FEC at 1600
	got = append(got, runHold(d, 1650, 2000, 1, true, false)...) // released; ladder keeps its own clock
	got = append(got, runHold(d, 2050, 5550, 1, true, false)...) // nothing yet
	got = append(got, runHold(d, 5600, 5650, 1, true, false)...) // WM_CLOSE at FEC+4s
	got = append(got, runHold(d, 5700, 17550, 1, true, false)...)
	got = append(got, runHold(d, 17600, 17700, 1, true, false)...) // give up at WM_CLOSE+12s
	got = append(got, runHold(d, 17750, 40000, 1, true, false)...) // and nothing after
	want := []holdAction{holdFEC, holdWMClose, holdGiveUp}
	if len(got) != len(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("expected %v, got %v", want, got)
		}
	}
}

func TestHoldGates(t *testing.T) {
	// Loading (the caller feeds active=false): even an endless
	// hold is silent - there is no live session to exit.
	d := &holdDuty{}
	if got := runHold(d, 100, 30000, 1, false, true); len(got) != 0 {
		t.Fatalf("fired while gated off (loading): %v", got)
	}
	// Disarmed / feature off / game dead reach the duty the same
	// way - inactive. A hold that STARTED live and loses the gate
	// mid-hold restarts from zero when the gate returns.
	d2 := &holdDuty{}
	runHold(d2, 100, 1200, 1, true, true)   // 1100ms of hold
	runHold(d2, 1250, 5000, 1, false, true) // gate drops; hold continues but counts for nothing
	if got := runHold(d2, 5050, 6000, 1, true, true); len(got) != 0 {
		t.Fatalf("hold progress leaked across an inactive gap: %v", got)
	}
	if got := runHold(d2, 6050, 6600, 1, true, true); len(got) != 1 || got[0] != holdFEC {
		t.Fatalf("expected the fire 1500ms after the gate returned, got %v", got)
	}
}

func TestHoldNewSessionStartsFresh(t *testing.T) {
	d := &holdDuty{}
	// Session 1 burns to give-up.
	runHold(d, 100, 30000, 1, true, true)
	// Session 2: the still-held button from session 1's world
	// does not inherit progress or the spent ladder.
	if got := runHold(d, 30100, 31500, 2, true, true); len(got) != 0 {
		t.Fatalf("session 2 inherited session 1's hold: %v", got)
	}
	if got := runHold(d, 31550, 31650, 2, true, true); len(got) != 1 || got[0] != holdFEC {
		t.Fatalf("session 2 did not start fresh: %v", got)
	}
}

func TestHoldDeadProcessSilence(t *testing.T) {
	// FEC went out, then the process died (the close landed):
	// the caller drops active, and the pending ladder must NOT
	// escalate against the next thing that reuses the gate.
	d := &holdDuty{}
	runHold(d, 100, 1600, 1, true, true) // fired
	if got := runHold(d, 1650, 60000, 1, false, false); len(got) != 0 {
		t.Fatalf("escalated after the session went inactive: %v", got)
	}
}
