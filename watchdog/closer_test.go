package main

import "testing"

// The session-close DECISION logic (closer.go), exercised on Linux.
// The window snapshots are stubs here exactly as the integration
// smokes stub them (window_linux.go); the Windows message leaves
// are compile-verified only - what these tests prove is when the
// duty decides to act, escalate, and stop.

var (
	editorState = windowState{playerPresent: false, editorPresent: true, editorHWND: 99}
	playerState = windowState{playerPresent: true, editorPresent: false}
	bothState   = windowState{playerPresent: true, editorPresent: true, editorHWND: 99}
)

// runTicks advances c in 100ms steps from fromMs to toMs, returning
// the actions it produced, in order.
func runTicks(c *closer, fromMs, toMs int64, session int, state string, enabled bool, ws windowState) []closeAction {
	var out []closeAction
	for t := fromMs; t <= toMs; t += 100 {
		if a := c.tick(t, session, state, enabled, true, ws); a != closeNone {
			out = append(out, a)
		}
	}
	return out
}

// arm plays the prologue every real firing sequence has: the
// player window is up for a few ticks (which is what arms the
// duty). Played in the loading state - the player window normally
// appears while the launcher is still resident, and the sighting
// arms the duty there (see TestCloserArmsDuringLoading).
func arm(c *closer, session int) {
	runTicks(c, 0, 300, session, "loading", true, playerState)
}

func TestCloserFiresAfterSustain(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	// Editor state appears at t=1000: nothing inside the sustain.
	if got := runTicks(c, 1000, 3400, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("fired inside the sustain window: %v", got)
	}
	got := runTicks(c, 3500, 3600, 1, "live", true, editorState)
	if len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected exactly the FrontEndControls action after ~2.5s sustained, got %v", got)
	}
}

func TestCloserTransientEditorStateDoesNotFire(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	runTicks(c, 1000, 2000, 1, "live", true, editorState)
	// Player window back after 1s: the shuffle was transient.
	if got := runTicks(c, 2100, 9000, 1, "live", true, playerState); len(got) != 0 {
		t.Fatalf("fired on a transient editor state: %v", got)
	}
	// And a later genuine editor return starts the clock fresh.
	if got := runTicks(c, 10000, 12400, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("fired without a fresh full sustain: %v", got)
	}
	if got := runTicks(c, 12500, 12600, 1, "live", true, editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the fresh sustain, got %v", got)
	}
}

// The load-window failure, as a unit test: a session that begins
// in the editor state (VPX started, table still loading) and NEVER
// shows a player window must never be closed - not inside the
// sustain, not past the whole escalation ladder's worth of time.
func TestCloserNeverArmedNeverFires(t *testing.T) {
	c := &closer{}
	if got := runTicks(c, 0, 120000, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("fired in a session whose player window was never seen (the mid-load kill): %v", got)
	}
	// Editor state breaking and returning changes nothing while
	// unarmed: the player still has to show up first.
	runTicks(c, 120100, 121000, 1, "live", true, windowState{})
	if got := runTicks(c, 121100, 180000, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("fired after a windowless gap, still unarmed: %v", got)
	}
}

// Arming is a latch, not a mood: once the player has been seen,
// later windowless shuffles do not disarm the duty.
func TestCloserArmingSurvivesShuffles(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	runTicks(c, 1000, 2000, 1, "live", true, windowState{}) // both windows gone briefly
	if got := runTicks(c, 2100, 4500, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("fired inside the sustain after a shuffle: %v", got)
	}
	if got := runTicks(c, 4600, 4700, 1, "live", true, editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the sustained editor return, got %v", got)
	}
}

// A player sighting during the LOADING phase arms the duty too:
// the observation is about the session's history, not the state
// the contract happened to be in when the window appeared.
func TestCloserArmsDuringLoading(t *testing.T) {
	c := &closer{}
	runTicks(c, 0, 2000, 1, "loading", true, editorState) // VPX up, still loading: silent
	runTicks(c, 2100, 2400, 1, "loading", true, playerState)
	if got := runTicks(c, 2500, 30000, 1, "loading", true, editorState); len(got) != 0 {
		t.Fatalf("fired during loading: %v", got)
	}
	// The session goes live in the editor state (the table exited
	// before the launcher even left): the sustain runs from the
	// live transition, then the duty fires.
	if got := runTicks(c, 30100, 32500, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("fired inside the live sustain: %v", got)
	}
	if got := runTicks(c, 32600, 32700, 1, "live", true, editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the live sustain, got %v", got)
	}
}

func TestCloserRequiresPlayerGone(t *testing.T) {
	c := &closer{}
	// Editor present but the player is still up (both class cues):
	// not a table exit - never fires.
	if got := runTicks(c, 0, 30000, 1, "live", true, bothState); len(got) != 0 {
		t.Fatalf("fired while the player window was present: %v", got)
	}
}

func TestCloserEscalatesThenGivesUpOnce(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	var got []closeAction
	got = append(got, runTicks(c, 0, 3000, 1, "live", true, editorState)...)    // FEC at ~2.5s
	got = append(got, runTicks(c, 3100, 6400, 1, "live", true, editorState)...) // nothing yet
	got = append(got, runTicks(c, 6500, 6600, 1, "live", true, editorState)...) // WM_CLOSE at FEC+4s
	got = append(got, runTicks(c, 6700, 18400, 1, "live", true, editorState)...)
	got = append(got, runTicks(c, 18500, 18600, 1, "live", true, editorState)...) // give up at WM_CLOSE+12s
	got = append(got, runTicks(c, 18700, 60000, 1, "live", true, editorState)...) // and never again
	want := []closeAction{closeFEC, closeWMClose, closeGiveUp}
	if len(got) != len(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("expected %v, got %v", want, got)
		}
	}
}

func TestCloserBounds(t *testing.T) {
	// Switch off: never fires (armed or not).
	c := &closer{}
	arm(c, 1)
	if got := runTicks(c, 1000, 30000, 1, "live", false, editorState); len(got) != 0 {
		t.Fatalf("fired with the close-duty switch off: %v", got)
	}
	// Loading (launcher resident): never fires, and the sustain
	// clock does not pre-run - it starts when the session goes live.
	c2 := &closer{}
	arm(c2, 1) // sighted during loading in this scenario (see the arming-during-loading test)
	if got := runTicks(c2, 1000, 30000, 1, "loading", true, editorState); len(got) != 0 {
		t.Fatalf("fired during loading: %v", got)
	}
	if got := runTicks(c2, 30100, 32400, 1, "live", true, editorState); len(got) != 0 {
		t.Fatalf("sustain clock leaked across the loading phase: %v", got)
	}
	if got := runTicks(c2, 32500, 32600, 1, "live", true, editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after a live-only sustain, got %v", got)
	}
	// Dead process: never fires.
	c3 := &closer{}
	for tm := int64(0); tm <= 30000; tm += 100 {
		if a := c3.tick(tm, 1, "live", true, false, editorState); a != closeNone {
			t.Fatalf("fired against a dead process: %v", a)
		}
	}
}

func TestCloserNewSessionStartsFresh(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	runTicks(c, 1000, 60000, 1, "live", true, editorState) // burns session 1 to give-up
	// Session 2 is a NEW session: unarmed again until ITS player
	// window has been seen - its own editor-from-birth is a load.
	if got := runTicks(c, 100000, 160000, 2, "live", true, editorState); len(got) != 0 {
		t.Fatalf("session 2 fired before its own player was seen: %v", got)
	}
	arm(c, 2)
	if got := runTicks(c, 161000, 163400, 2, "live", true, editorState); len(got) != 0 {
		t.Fatalf("session 2 fired inside its sustain: %v", got)
	}
	if got := runTicks(c, 163500, 163600, 2, "live", true, editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("session 2 did not start fresh: %v", got)
	}
}
