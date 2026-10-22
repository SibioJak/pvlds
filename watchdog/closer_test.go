package main

import "testing"

// The session-close DECISION logic (closer.go), exercised on Linux.
// The window snapshots are stubs here exactly as the integration
// smokes stub them (window_linux.go); the Windows message leaves
// are compile-verified only - what these tests prove is when the
// duty decides to act, escalate, and stop.
//
// The duty is unconditional (no switch, no hold gesture - both
// stricken 2026-10-22): tick() takes no enabled flag. The
// windowState's playerPresent is the sighting gate's output
// (sighting.go), so a session sighted by the class-independent
// rule - a player window of some foreign class - arms and fires
// through exactly the path these tests walk; sighting_test.go
// covers the rule itself, and the integration smokes cover it
// end to end (the SDL_app scenario).

var (
	editorState = windowState{playerPresent: false, editorPresent: true, editorHWND: 99}
	playerState = windowState{playerPresent: true, editorPresent: false}
	bothState   = windowState{playerPresent: true, editorPresent: true, editorHWND: 99}
)

// runTicks advances c in 100ms steps from fromMs to toMs, returning
// the actions it produced, in order.
func runTicks(c *closer, fromMs, toMs int64, session int, state string, ws windowState) []closeAction {
	var out []closeAction
	for t := fromMs; t <= toMs; t += 100 {
		if a := c.tick(t, session, state, true, ws); a != closeNone {
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
	runTicks(c, 0, 300, session, "loading", playerState)
}

// The landing confirmation is ~400ms (editorSustainMs): the close
// fires on the first tick at/after it - promptly, never inside it.
func TestCloserFiresPromptlyAfterLanding(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	// Editor state appears at t=1000: nothing inside the ~400ms
	// confirmation window.
	if got := runTicks(c, 1000, 1300, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("fired inside the landing confirmation: %v", got)
	}
	got := runTicks(c, 1400, 1500, 1, "live", editorState)
	if len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected exactly the FrontEndControls action ~400ms after the landing, got %v", got)
	}
}

func TestCloserTransientEditorStateDoesNotFire(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	// A 100ms editor blip - far under the confirmation - then the
	// player window is back: a shuffle, not an exit.
	runTicks(c, 1000, 1100, 1, "live", editorState)
	if got := runTicks(c, 1200, 9000, 1, "live", playerState); len(got) != 0 {
		t.Fatalf("fired on a transient editor state: %v", got)
	}
	// And a later genuine editor return starts the clock fresh.
	if got := runTicks(c, 10000, 10300, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("fired without a fresh confirmation: %v", got)
	}
	if got := runTicks(c, 10400, 10500, 1, "live", editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the fresh confirmation, got %v", got)
	}
}

// The load-window failure, as a unit test: a session that begins
// in the editor state (VPX started, table still loading) and NEVER
// shows a player window must never be closed - not inside the
// confirmation, not past the whole escalation ladder's worth of
// time. This is also the editor-only-from-start case: no sighting,
// no fire, ever.
func TestCloserNeverArmedNeverFires(t *testing.T) {
	c := &closer{}
	if got := runTicks(c, 0, 120000, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("fired in a session whose player window was never seen (the mid-load kill): %v", got)
	}
	// Editor state breaking and returning changes nothing while
	// unarmed: the player still has to show up first.
	runTicks(c, 120100, 121000, 1, "live", windowState{})
	if got := runTicks(c, 121100, 180000, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("fired after a windowless gap, still unarmed: %v", got)
	}
}

// Arming is a latch, not a mood: once the player has been seen,
// later windowless shuffles do not disarm the duty.
func TestCloserArmingSurvivesShuffles(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	runTicks(c, 1000, 2000, 1, "live", windowState{}) // both windows gone briefly
	if got := runTicks(c, 2100, 2400, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("fired inside the confirmation after a shuffle: %v", got)
	}
	if got := runTicks(c, 2500, 2600, 1, "live", editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the confirmed editor return, got %v", got)
	}
}

// A player sighting during the LOADING phase arms the duty too:
// the observation is about the session's history, not the state
// the contract happened to be in when the window appeared.
func TestCloserArmsDuringLoading(t *testing.T) {
	c := &closer{}
	runTicks(c, 0, 2000, 1, "loading", editorState) // VPX up, still loading: silent
	runTicks(c, 2100, 2400, 1, "loading", playerState)
	if got := runTicks(c, 2500, 30000, 1, "loading", editorState); len(got) != 0 {
		t.Fatalf("fired during loading: %v", got)
	}
	// The session goes live in the editor state (the table exited
	// before the launcher even left): the confirmation runs from
	// the live transition, then the duty fires.
	if got := runTicks(c, 30100, 30400, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("fired inside the live confirmation: %v", got)
	}
	if got := runTicks(c, 30500, 30600, 1, "live", editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the live confirmation, got %v", got)
	}
}

func TestCloserRequiresPlayerGone(t *testing.T) {
	c := &closer{}
	// Editor present but the player is still up (both class cues):
	// not a table exit - never fires.
	if got := runTicks(c, 0, 30000, 1, "live", bothState); len(got) != 0 {
		t.Fatalf("fired while the player window was present: %v", got)
	}
}

func TestCloserEscalatesThenGivesUpOnce(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	var got []closeAction
	got = append(got, runTicks(c, 1000, 1300, 1, "live", editorState)...)   // confirming
	got = append(got, runTicks(c, 1400, 1500, 1, "live", editorState)...)   // FEC at landing+~400ms
	got = append(got, runTicks(c, 1600, 5300, 1, "live", editorState)...)   // nothing yet
	got = append(got, runTicks(c, 5400, 5500, 1, "live", editorState)...)   // WM_CLOSE at FEC+4s
	got = append(got, runTicks(c, 5600, 17300, 1, "live", editorState)...)  // waiting
	got = append(got, runTicks(c, 17400, 17500, 1, "live", editorState)...) // give up at WM_CLOSE+12s
	got = append(got, runTicks(c, 17600, 60000, 1, "live", editorState)...) // and never again
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
	// Loading (launcher resident): never fires, and the
	// confirmation clock does not pre-run - it starts when the
	// session goes live.
	c2 := &closer{}
	arm(c2, 1) // sighted during loading in this scenario (see the arming-during-loading test)
	if got := runTicks(c2, 1000, 30000, 1, "loading", editorState); len(got) != 0 {
		t.Fatalf("fired during loading: %v", got)
	}
	if got := runTicks(c2, 30100, 30400, 1, "live", editorState); len(got) != 0 {
		t.Fatalf("confirmation clock leaked across the loading phase: %v", got)
	}
	if got := runTicks(c2, 30500, 30600, 1, "live", editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after a live-only confirmation, got %v", got)
	}
	// Dead process: never fires.
	c3 := &closer{}
	for tm := int64(0); tm <= 30000; tm += 100 {
		if a := c3.tick(tm, 1, "live", false, editorState); a != closeNone {
			t.Fatalf("fired against a dead process: %v", a)
		}
	}
}

func TestCloserNewSessionStartsFresh(t *testing.T) {
	c := &closer{}
	arm(c, 1)
	runTicks(c, 1000, 60000, 1, "live", editorState) // burns session 1 to give-up
	// Session 2 is a NEW session: unarmed again until ITS player
	// window has been seen - its own editor-from-birth is a load.
	if got := runTicks(c, 100000, 160000, 2, "live", editorState); len(got) != 0 {
		t.Fatalf("session 2 fired before its own player was seen: %v", got)
	}
	arm(c, 2)
	if got := runTicks(c, 161000, 161300, 2, "live", editorState); len(got) != 0 {
		t.Fatalf("session 2 fired inside its confirmation: %v", got)
	}
	if got := runTicks(c, 161400, 161500, 2, "live", editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("session 2 did not start fresh: %v", got)
	}
}
