package main

import "testing"

// The exit detector (closer.go), exercised on Linux. The
// foreground facts are scripted here exactly as the integration
// smokes script them (window_linux.go's foreground marker); the
// Windows message leaves are compile-verified only - what these
// tests prove is when the detector arms, sustains, fires,
// escalates, and stops.
//
// The detector's trigger is the FOREGROUND (field forensics,
// sessions 25/26, 2026-10-23): the old player-gone + editor-
// present composite can never complete on Chris's rig because
// the window the sighting stamps off - a hidden "CVFrame" - is
// VPX's editor canvas and persists in the editor state. The
// detector arms on (sighting stamped) + (a live foreground
// excursion away from the editor), then fires when the editor
// holds the foreground for editorForegroundSustainMs. The duty
// is unconditional (no switch, no hold gesture - both stricken
// 2026-10-22): tick() takes no enabled flag.

// tickIn is one scripted tick's inputs to the detector.
type tickIn struct {
	state   string
	alive   bool
	sighted bool
	fgEd    bool // the foreground is the editor window
}

var (
	fgPlayer  = tickIn{state: "live", alive: true, sighted: true, fgEd: false}
	fgEditor  = tickIn{state: "live", alive: true, sighted: true, fgEd: true}
	fgLoading = tickIn{state: "loading", alive: true, sighted: false, fgEd: true}
)

// drive runs n identical ticks at stepMs spacing starting at
// fromMs, returning the actions produced and how many arm
// events fired.
func drive(c *closer, session int, fromMs int64, n int, stepMs int64, in tickIn) ([]closeAction, int) {
	var out []closeAction
	arms := 0
	for i := 0; i < n; i++ {
		a, armed := c.tick(fromMs+int64(i)*stepMs, session, in.state, in.alive, in.sighted, windowState{fgIsEditor: in.fgEd, editorHWND: 99})
		if a != closeNone {
			out = append(out, a)
		}
		if armed {
			arms++
		}
	}
	return out, arms
}

// arm walks the prologue every firing sequence has: one live
// tick with the foreground away from the editor (the
// excursion), with the sighting already stamped. Asserts the
// arm event fired exactly once.
func arm(t *testing.T, c *closer, session int, atMs int64) {
	t.Helper()
	_, arms := drive(c, session, atMs, 1, 100, fgPlayer)
	if arms != 1 {
		t.Fatalf("excursion tick did not arm the detector (arms=%d)", arms)
	}
}

// The arm latches on the excursion tick, the sustain runs on
// elapsed time, and the close fires at editorForegroundSustainMs
// after the editor foreground begins - not a tick inside it.
func TestDetectorArmsAndFiresOnSustain(t *testing.T) {
	c := &closer{}
	arm(t, c, 1, 0)
	// Editor foreground from t=100: nothing up to +1100ms of it.
	if got, _ := drive(c, 1, 100, 12, 100, fgEditor); len(got) != 0 {
		t.Fatalf("fired inside the sustain: %v", got)
	}
	got, arms := drive(c, 1, 1300, 1, 100, fgEditor)
	if len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC at the sustain boundary, got %v", got)
	}
	if arms != 0 {
		t.Fatalf("arm event fired twice")
	}
}

// A sub-sustain editor blip (a dialog shuffle, a focus flicker)
// breaks the sustain clock; a later genuine landing starts it
// fresh and fires on its own full sustain.
func TestDetectorSustainResetsWhenForegroundLeaves(t *testing.T) {
	c := &closer{}
	arm(t, c, 1, 0)
	drive(c, 1, 100, 8, 100, fgEditor) // 800ms of editor foreground
	drive(c, 1, 900, 1, 100, fgPlayer) // leaves: clock resets
	if got, _ := drive(c, 1, 1000, 12, 100, fgEditor); len(got) != 0 {
		t.Fatalf("fired on the stale sustain after the reset: %v", got)
	}
	if got, _ := drive(c, 1, 2200, 1, 100, fgEditor); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the fresh full sustain, got %v", got)
	}
}

// Scenario (a)/(d) defensive core: the editor holds the
// foreground from the spawn instant and never leaves it. Even
// with the sighting stamped (a table demonstrably played), the
// detector never arms - there was no excursion - so a silent
// exit inside that state is undetectable BY DESIGN and the
// duty must not guess at it.
func TestDetectorNoExcursionNeverArms(t *testing.T) {
	c := &closer{}
	// 120s of editor foreground, sighted the whole time.
	got, arms := drive(c, 1, 0, 1200, 100, fgEditor)
	if arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired without an excursion (arms=%d, actions=%v)", arms, got)
	}
}

// The other arming half: excursions aplenty, but the sighting
// never stamps (the table never loaded - editor-only from
// birth, the mid-load-kill shape). Never arms, never fires.
func TestDetectorNoSightingNeverArms(t *testing.T) {
	c := &closer{}
	unsighted := fgPlayer
	unsighted.sighted = false
	if _, arms := drive(c, 1, 0, 10, 100, unsighted); arms != 0 {
		t.Fatalf("armed without a sighting")
	}
	unsightedEd := fgEditor
	unsightedEd.sighted = false
	if got, arms := drive(c, 1, 1000, 600, 100, unsightedEd); arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired without a sighting (arms=%d, actions=%v)", arms, got)
	}
}

// Arming observations are a live-session story: the same inputs
// during loading arm nothing, and the sustain clock does not
// pre-run there - it starts when the (now armed) detector first
// sees the editor foreground in live.
func TestDetectorInertDuringLoading(t *testing.T) {
	c := &closer{}
	drive(c, 1, 0, 50, 100, fgLoading) // VPX up, loading, editor foreground
	// Sighted + excursion inputs, but still loading: inert.
	loadPlay := tickIn{state: "loading", alive: true, sighted: true, fgEd: false}
	if _, arms := drive(c, 1, 5000, 5, 100, loadPlay); arms != 0 {
		t.Fatalf("armed during loading")
	}
	loadEd := tickIn{state: "loading", alive: true, sighted: true, fgEd: true}
	if got, _ := drive(c, 1, 5500, 50, 100, loadEd); len(got) != 0 {
		t.Fatalf("fired during loading: %v", got)
	}
	// Live now, editor foreground held from before: still no
	// excursion observed in live, so no arm and no fire...
	if got, arms := drive(c, 1, 10500, 50, 100, fgEditor); arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired on a live continuation without a live excursion (arms=%d, actions=%v)", arms, got)
	}
	// ...until a live excursion happens, after which a fresh
	// full sustain fires.
	arm(t, c, 1, 15500)
	if got, _ := drive(c, 1, 15600, 12, 100, fgEditor); len(got) != 0 {
		t.Fatalf("fired inside the post-arm sustain: %v", got)
	}
	if got, _ := drive(c, 1, 16800, 1, 100, fgEditor); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the post-arm sustain, got %v", got)
	}
}

// The ladder still escalates on elapsed time (FEC, +4s WM_CLOSE,
// +12s give up, exactly once), and a foreground departure
// mid-ladder pauses it instead of advancing it: the stages only
// advance while the editor holds the foreground.
func TestDetectorEscalatesPausesAndGivesUpOnce(t *testing.T) {
	c := &closer{}
	arm(t, c, 1, 0)
	drive(c, 1, 100, 12, 100, fgEditor) // sustain runs to t=1200
	got, _ := drive(c, 1, 1300, 1, 100, fgEditor)
	if len(got) != 1 || got[0] != closeFEC { // FEC at 1300
		t.Fatalf("expected FEC, got %v", got)
	}
	// Foreground leaves for a long stretch: no escalation.
	if got, _ := drive(c, 1, 1400, 100, 100, fgPlayer); len(got) != 0 {
		t.Fatalf("ladder advanced while the foreground was away: %v", got)
	}
	// The editor state returns; the grace is long past, so the
	// escalation lands on the first editor tick.
	if got, _ := drive(c, 1, 11400, 1, 100, fgEditor); len(got) != 1 || got[0] != closeWMClose {
		t.Fatalf("expected WM_CLOSE on the ladder's return, got %v", got)
	}
	// Give up 12s later, and never anything again.
	if got, _ := drive(c, 1, 11500, 119, 100, fgEditor); len(got) != 0 {
		t.Fatalf("gave up early: %v", got)
	}
	if got, _ := drive(c, 1, 23400, 1, 100, fgEditor); len(got) != 1 || got[0] != closeGiveUp {
		t.Fatalf("expected the give-up, got %v", got)
	}
	if got, _ := drive(c, 1, 23500, 200, 100, fgEditor); len(got) != 0 {
		t.Fatalf("acted after giving up: %v", got)
	}
}

// The push guard: the watchdog's one-shot focus handoff can
// itself place the foreground on a non-editor game window, so
// an excursion manufactured by the push must not arm the
// detector. Excursions at the push tick (and any latched
// before it) do not count; the first excursion at a tick AFTER
// the push arms as usual, and the full sequence then fires.
func TestDetectorPushGuard(t *testing.T) {
	c := &closer{}
	// Arm BEFORE the push (the launcher marked the session
	// live while still exiting; play's excursion latched on
	// its own evidence): the push does NOT revoke a latched
	// arm, and a sustained editor foreground still fires.
	drive(c, 1, 0, 1, 100, fgPlayer) // excursion -> arm
	c.notePush(1, 100)
	if !c.armed {
		t.Fatalf("the push revoked a latched arm")
	}
	if got, _ := drive(c, 1, 200, 13, 100, fgEditor); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("pre-push arm did not survive the push: %v", got)
	}

	// The strict sequence: push recorded first, then the
	// foreground away at the push's own tick and before it
	// could be play's doing.
	c2 := &closer{}
	c2.notePush(1, 1000)
	// Tick AT the push time with the foreground away (what
	// the push itself may have manufactured): no excursion.
	if _, arms := drive(c2, 1, 1000, 1, 100, fgPlayer); arms != 0 {
		t.Fatalf("armed on the push tick's own excursion")
	}
	// A full editor sustain right after cannot fire - the
	// detector never armed.
	if got, _ := drive(c2, 1, 1100, 30, 100, fgEditor); len(got) != 0 {
		t.Fatalf("fired without a post-push excursion: %v", got)
	}
	// Play takes the foreground at a tick after the push:
	// arms now, and the landing after it fires.
	arm(t, c2, 1, 4200)
	if got, _ := drive(c2, 1, 4300, 13, 100, fgEditor); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the post-push arm + sustain, got %v", got)
	}
}

// The push guard and session freshness: a push noted for a
// new session resets the detector like any other session
// change (no excursion, sighting, or sustain leaks across).
func TestDetectorPushGuardNewSession(t *testing.T) {
	c := &closer{}
	arm(t, c, 1, 0)
	c.notePush(2, 5000)
	if got, arms := drive(c, 2, 5100, 30, 100, fgEditor); arms != 0 || len(got) != 0 {
		t.Fatalf("session 2 inherited state across notePush (arms=%d, actions=%v)", arms, got)
	}
}

// Bounds: a dead process never fires (and its ticks do not run
// the sustain), and a new session starts completely fresh -
// its own sighting and excursion are required before anything
// can fire.
func TestDetectorBoundsAndNewSession(t *testing.T) {
	c := &closer{}
	dead := fgEditor
	dead.alive = false
	if got, arms := drive(c, 1, 0, 300, 100, dead); arms != 0 || len(got) != 0 {
		t.Fatalf("acted against a dead process (arms=%d, actions=%v)", arms, got)
	}
	// Burn session 1 to give-up...
	arm(t, c, 1, 30000)
	drive(c, 1, 30100, 12, 100, fgEditor)
	drive(c, 1, 31300, 1, 100, fgEditor)   // FEC
	drive(c, 1, 31400, 40, 100, fgEditor)  // grace
	drive(c, 1, 35400, 1, 100, fgEditor)   // WM_CLOSE
	drive(c, 1, 35500, 120, 100, fgEditor) // give-up window
	drive(c, 1, 47500, 1, 100, fgEditor)   // give up
	// ...session 2 must not inherit the arm: editor foreground
	// sustained, sighted, but no excursion yet in THIS session.
	if got, arms := drive(c, 2, 100000, 600, 100, fgEditor); arms != 0 || len(got) != 0 {
		t.Fatalf("session 2 inherited session 1's arm (arms=%d, actions=%v)", arms, got)
	}
	arm(t, c, 2, 160000)
	if got, _ := drive(c, 2, 160100, 13, 100, fgEditor); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("session 2 did not fire on its own arm + sustain: %v", got)
	}
}
