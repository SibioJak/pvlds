package main

import "testing"

// The herding brain (herd_logic.go): grace, rate limit, and the
// yield-to-deliberate-use counter, exercised on Linux. Foreground
// observations are scripted; the Windows leaf only supplies them.

const (
	gameWin    = uintptr(1000)
	foreignWin = uintptr(2000)
	otherWin   = uintptr(3000)
)

// The session-state gate (herdingAllowed): herding exists for
// the loading phase's spawn settle and NEVER runs in a live
// session - on the VR rig its only anchor there is the editor
// frame, which it was caught forcing to the foreground mid-play
// (field sessions 25/26, 2026-10-23), polluting the exit
// detector's foreground signal. The desk switch gates on top.
func TestHerdingAllowedGate(t *testing.T) {
	cases := []struct {
		switchOn bool
		state    string
		want     bool
	}{
		{true, "loading", true},   // the one phase herding serves
		{true, "live", false},     // handed off: never, no exceptions
		{true, "idle", false},     // no session at all
		{true, "returned", false}, // consumed sessions stay quiet
		{true, "failed", false},
		{true, "", false},
		{false, "loading", false}, // the desk switch still wins
		{false, "live", false},
	}
	for _, tc := range cases {
		if got := herdingAllowed(tc.switchOn, tc.state); got != tc.want {
			t.Fatalf("herdingAllowed(%v, %q) = %v, want %v", tc.switchOn, tc.state, got, tc.want)
		}
	}
}

func TestHerdGraceAndRateLimit(t *testing.T) {
	b := &herdBrain{}
	b.reset(1)
	// Foreign window takes foreground at t=0: grace runs first.
	if d := b.decide(0, foreignWin, false); d != herdNone {
		t.Fatalf("acted on the change tick: %v", d)
	}
	if d := b.decide(1900, foreignWin, false); d != herdNone {
		t.Fatalf("acted inside the grace period: %v", d)
	}
	if d := b.decide(2100, foreignWin, false); d != herdAssert {
		t.Fatalf("expected an assert after grace, got %v", d)
	}
	// Rate limit: the same window, still in front, is not chased
	// again for 3s.
	if d := b.decide(4000, foreignWin, false); d != herdNone {
		t.Fatalf("asserted inside the rate limit: %v", d)
	}
	if d := b.decide(5200, foreignWin, false); d != herdAssert {
		t.Fatalf("expected a second assert after the rate limit, got %v", d)
	}
}

func TestHerdGameForegroundIsLeftAlone(t *testing.T) {
	b := &herdBrain{}
	b.reset(1)
	if d := b.decide(0, gameWin, true); d != herdNone {
		t.Fatalf("acted on the game window: %v", d)
	}
	if d := b.decide(60000, gameWin, true); d != herdNone {
		t.Fatalf("acted on the settled game window: %v", d)
	}
	if d := b.decide(60000, 0, false); d != herdNone {
		t.Fatalf("acted with no foreground window: %v", d)
	}
}

// fightRound plays one herding round against w: it steals the
// foreground, the brain (eventually) asserts, the game briefly
// holds foreground, then w takes it back. Returns the decision the
// brain produced on w's return tick.
func fightRound(t *testing.T, b *herdBrain, now *int64, w uintptr) herdDecision {
	t.Helper()
	// The foreign window takes foreground.
	if d := b.decide(*now, w, false); d == herdYielded {
		return d
	}
	// Let grace + rate limit pass, then the brain must assert.
	*now += herdGraceMs + herdMinIntervalMs + 100
	if d := b.decide(*now, w, false); d != herdAssert {
		t.Fatalf("expected an assert against %#x, got %v", w, d)
	}
	// The assert lands: the game holds foreground briefly...
	*now += 300
	if d := b.decide(*now, gameWin, true); d != herdNone {
		t.Fatalf("acted while the game held foreground: %v", d)
	}
	// ...and the user takes the foreign window back.
	*now += 300
	return b.decide(*now, w, false)
}

func TestHerdYieldsAtThreeFailedAsserts(t *testing.T) {
	b := &herdBrain{}
	b.reset(1)
	now := int64(0)
	for round := 1; round <= 2; round++ {
		if d := fightRound(t, b, &now, foreignWin); d != herdNone {
			t.Fatalf("round %d: yielded early: %v", round, d)
		}
	}
	if d := fightRound(t, b, &now, foreignWin); d != herdYielded {
		t.Fatalf("the third failed re-assertion must trip the yield, got %v", d)
	}
	// Yielded is sticky for the session: no more asserts, and the
	// yield is reported once only.
	now += herdGraceMs + herdMinIntervalMs + 100
	if d := b.decide(now, foreignWin, false); d != herdNone {
		t.Fatalf("herded after yielding: %v", d)
	}
	// A new session starts fresh.
	b.reset(2)
	now = 0
	if d := b.decide(now, foreignWin, false); d != herdNone {
		t.Fatalf("acted on a fresh session's change tick: %v", d)
	}
	now += herdGraceMs + herdMinIntervalMs + 100
	if d := b.decide(now, foreignWin, false); d != herdAssert {
		t.Fatalf("new session did not herd again: %v", d)
	}
}

func TestHerdYieldCountsPerWindow(t *testing.T) {
	b := &herdBrain{}
	b.reset(1)
	now := int64(0)
	// Two failed rounds against foreignWin...
	fightRound(t, b, &now, foreignWin)
	fightRound(t, b, &now, foreignWin)
	// ...then the user moves to a different window: its count
	// starts at zero, so two rounds against it must not yield.
	fightRound(t, b, &now, otherWin)
	if d := fightRound(t, b, &now, otherWin); d != herdNone {
		t.Fatalf("yielded on the second window's second failure: %v", d)
	}
	// Its third does.
	if d := fightRound(t, b, &now, otherWin); d != herdYielded {
		t.Fatalf("the second window's third failure must yield, got %v", d)
	}
}
