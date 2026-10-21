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

func TestCloserFiresAfterSustain(t *testing.T) {
	c := &closer{}
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
	runTicks(c, 0, 1000, 1, "live", true, editorState)
	// Player window back after 1s: the shuffle was transient.
	if got := runTicks(c, 1100, 9000, 1, "live", true, playerState); len(got) != 0 {
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
	// Switch off: never fires.
	c := &closer{}
	if got := runTicks(c, 0, 30000, 1, "live", false, editorState); len(got) != 0 {
		t.Fatalf("fired with the close-duty switch off: %v", got)
	}
	// Loading (launcher resident): never fires, and the sustain
	// clock does not pre-run - it starts when the session goes live.
	c2 := &closer{}
	if got := runTicks(c2, 0, 30000, 1, "loading", true, editorState); len(got) != 0 {
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
	runTicks(c, 0, 60000, 1, "live", true, editorState) // burns session 1 to give-up
	if got := runTicks(c, 100000, 102400, 2, "live", true, editorState); len(got) != 0 {
		t.Fatalf("session 2 fired inside its sustain: %v", got)
	}
	if got := runTicks(c, 102500, 102600, 2, "live", true, editorState); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("session 2 did not start fresh: %v", got)
	}
}
