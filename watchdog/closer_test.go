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
// detector arms on (sighting stamped) + (a play excursion:
// the player window holding the foreground - FIX153; a merely
// non-editor foreground is the load's own cycling and arms
// nothing), then fires when the editor holds the foreground
// for editorForegroundSustainMs. A session that never latches
// play and never stamps its runtime is closed at the
// never-played bound instead (FIX153's editor landing). The duty
// is unconditional (no switch, no hold gesture - both stricken
// 2026-10-22): tick() takes no enabled flag.

// tickIn is one scripted tick's inputs to the detector.
type tickIn struct {
	state    string
	alive    bool
	sighted  bool
	runtime  bool // the session's runtime has been sighted (FIX150's loading witness half)
	fgEd     bool // the foreground is the editor window
	fgPlayer bool // the foreground is the player window itself
}

var (
	// FIX153: the excursion tick is the PLAYER WINDOW holding
	// the foreground - the fixture now actually sets fgPlayer
	// (it never did: the old tests scripted a generic
	// non-editor foreground, the exact looseness FIX153
	// removes from the live latch).
	fgPlayer  = tickIn{state: "live", alive: true, sighted: true, fgEd: false, fgPlayer: true}
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
		a, armed := c.tick(fromMs+int64(i)*stepMs, session, in.state, in.alive, in.sighted, in.runtime, windowState{fgIsEditor: in.fgEd, fgIsPlayer: in.fgPlayer, editorHWND: 99})
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
// tick with the player window holding the foreground (the
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

// Defensive core: the editor holds the foreground from the
// spawn instant and never leaves it. Even with the sighting
// stamped, the detector never arms - there was no excursion -
// so a silent exit inside that state is undetectable BY
// DESIGN and the duty must not guess at it. (What happens
// when this state outlives the never-played bound is
// FIX153's editor-landing leg, below - the bound is a
// separate judgement, not an arm; this drive stays well
// inside it.)
func TestDetectorNoExcursionNeverArms(t *testing.T) {
	c := &closer{}
	// 60s of editor foreground, sighted the whole time.
	got, arms := drive(c, 1, 0, 600, 100, fgEditor)
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

// FIX150 (the hand-off gate era): the gate holds the
// launcher's exit while the table is already playing, so a
// fast table's whole play phase - and its exit landing -
// can happen inside the loading phase. The excursion may
// therefore latch during loading, but only on the witness
// the load cannot counterfeit: the runtime has been
// sighted AND the foreground is the player window itself.
// Nothing arms or fires during loading; the arm completes
// on the first live tick, the sustain runs from there, and
// the close fires on it - the pre-gate choreography,
// restored for a table that exited during the hold.
func TestDetectorLoadingWitnessLatches(t *testing.T) {
	c := &closer{}
	// Loading: runtime sighted, the player window holds the
	// foreground (play, witnessed). Inert: no arm, no fire.
	loadPlay := tickIn{state: "loading", alive: true, sighted: true, runtime: true, fgPlayer: true}
	if got, arms := drive(c, 1, 0, 30, 100, loadPlay); arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired during loading on the witness (arms=%d, actions=%v)", arms, got)
	}
	// The table lands in its editor, still loading: inert,
	// and the sustain does not pre-run.
	loadEd := tickIn{state: "loading", alive: true, sighted: true, runtime: true, fgEd: true}
	if got, arms := drive(c, 1, 3000, 30, 100, loadEd); arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired during loading on the landing (arms=%d, actions=%v)", arms, got)
	}
	// Live, the editor still holding the foreground: the
	// arm completes on the first live tick (the latched
	// excursion + the sighting), the sustain runs its full
	// length from there, then the close fires.
	if got, arms := drive(c, 1, 6000, 12, 100, fgEditor); arms != 1 || len(got) != 0 {
		t.Fatalf("expected exactly the arm inside the sustain (arms=%d, actions=%v)", arms, got)
	}
	if got, _ := drive(c, 1, 7300, 1, 100, fgEditor); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC at the sustain boundary, got %v", got)
	}
}

// The witness is a conjunction - either half alone latches
// nothing. Player foreground during loading WITHOUT the
// runtime is the load's own story (the focus sequence puts
// it there while the table is still coming up); the
// runtime without the player foreground is a table up
// behind a dialog. After either, a live editor continuation
// arms nothing - the inert-during-loading law, unchanged
// for every input the witness does not cover.
func TestDetectorLoadingNoWitnessNoLatch(t *testing.T) {
	noRuntime := &closer{}
	loadPlay := tickIn{state: "loading", alive: true, sighted: true, fgPlayer: true}
	drive(noRuntime, 1, 0, 30, 100, loadPlay)
	if got, arms := drive(noRuntime, 1, 3000, 50, 100, fgEditor); arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired without the runtime witness (arms=%d, actions=%v)", arms, got)
	}
	noPlayer := &closer{}
	loadBehind := tickIn{state: "loading", alive: true, sighted: true, runtime: true}
	drive(noPlayer, 1, 0, 30, 100, loadBehind)
	if got, arms := drive(noPlayer, 1, 3000, 50, 100, fgEditor); arms != 0 || len(got) != 0 {
		t.Fatalf("armed/fired without the player-foreground witness (arms=%d, actions=%v)", arms, got)
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

// FIX153 leg (a) - the session 329 replay, and the NC against
// the pre-FIX153 law. A cold-spawn session, live from the
// spawn's first seconds: the sighting stamps off the editor
// canvas, the runtime stamps, the foreground cycles editor ->
// Preparing Table dialog -> editor, and the editor then holds
// the foreground well past the sustain while the table is
// STILL LOADING. Under the old live latch the dialog tick
// (merely not-the-editor) armed the detector and the editor's
// hold killed the table; here nothing may arm and nothing may
// fire. Leg (b) rides the same session: the player foreground
// arrives late (the load finished), play proceeds, and a
// genuine exit landing afterwards fires exactly as before.
func TestFix153Session329Replay(t *testing.T) {
	c := &closer{}
	// Spawn instant: live (promoted), editor foreground, the
	// sighting not yet stamped.
	spawn := tickIn{state: "live", alive: true, sighted: false, fgEd: true}
	if got, arms := drive(c, 1, 0, 10, 100, spawn); arms != 0 || len(got) != 0 {
		t.Fatalf("acted at the spawn instant (arms=%d, actions=%v)", arms, got)
	}
	// The sighting stamps; the editor still holds the
	// foreground mid-load.
	loadEd := tickIn{state: "live", alive: true, sighted: true, fgEd: true}
	if got, arms := drive(c, 1, 1000, 10, 100, loadEd); arms != 0 || len(got) != 0 {
		t.Fatalf("armed on the mid-load editor foreground (arms=%d, actions=%v)", arms, got)
	}
	// The runtime stamps and the Preparing Table dialog takes
	// the foreground for a tick - the old law's arming tick.
	dialog := tickIn{state: "live", alive: true, sighted: true, runtime: true, fgEd: false}
	if got, arms := drive(c, 1, 2000, 1, 100, dialog); arms != 0 || len(got) != 0 {
		t.Fatalf("the dialog tick armed the detector (arms=%d, actions=%v)", arms, got)
	}
	// The editor resumes and holds for 3s - past the sustain,
	// with the sighting AND the runtime both stamped. This is
	// the exact window session 329 died in: no arm, no fire.
	loadEdRt := tickIn{state: "live", alive: true, sighted: true, runtime: true, fgEd: true}
	if got, arms := drive(c, 1, 2100, 30, 100, loadEdRt); arms != 0 || len(got) != 0 {
		t.Fatalf("fired on a loading table (arms=%d, actions=%v)", arms, got)
	}
	if c.armed {
		t.Fatalf("detector armed during the load")
	}
	// The player window takes the foreground - the load
	// finished. NOW the excursion latches and the arm lands.
	play := tickIn{state: "live", alive: true, sighted: true, runtime: true, fgPlayer: true}
	if got, arms := drive(c, 1, 5100, 10, 100, play); arms != 1 || len(got) != 0 {
		t.Fatalf("expected exactly the arm when play took the foreground (arms=%d, actions=%v)", arms, got)
	}
	// A genuine exit landing: the editor holds the foreground
	// and the close fires on the full sustain (leg (b)).
	exitEd := tickIn{state: "live", alive: true, sighted: true, runtime: true, fgEd: true}
	if got, _ := drive(c, 1, 6100, 12, 100, exitEd); len(got) != 0 {
		t.Fatalf("fired inside the post-play sustain: %v", got)
	}
	if got, _ := drive(c, 1, 7300, 1, 100, exitEd); len(got) != 1 || got[0] != closeFEC {
		t.Fatalf("expected FEC after the post-play sustain, got %v", got)
	}
}

// FIX153 leg (c) - the editor landing: live from spawn, the
// sighting stamped (the editor canvas qualifies), the runtime
// NEVER stamps, the player foreground NEVER happens, the
// editor holds the foreground throughout. The exit detector
// never arms (nothing to arm on), and at the never-played
// bound the landing resolves on the standing ladder - its own
// action first, then the ordinary escalation and give-up -
// instead of hanging forever. One tick before the bound:
// still nothing.
func TestFix153EditorLandingBound(t *testing.T) {
	c := &closer{}
	landing := tickIn{state: "live", alive: true, sighted: true, fgEd: true}
	// 400ms cadence (the watchdog's real tick) up to one tick
	// before the bound: no arm, no action.
	if got, arms := drive(c, 1, 0, 300, 400, landing); arms != 0 || len(got) != 0 {
		t.Fatalf("acted before the bound (arms=%d, actions=%v)", arms, got)
	}
	if c.armed {
		t.Fatalf("an editor landing armed the exit detector")
	}
	// The bound tick (t=120000): the landing fires, in its
	// own words.
	got, arms := drive(c, 1, 120000, 1, 400, landing)
	if arms != 0 || len(got) != 1 || got[0] != closeNeverPlayed {
		t.Fatalf("expected the never-played fire at the bound, got arms=%d actions=%v", arms, got)
	}
	// The ladder completes unarmed: WM_CLOSE after the FEC
	// grace, the give-up after its window, then silence.
	if got, _ := drive(c, 1, 120400, 9, 400, landing); len(got) != 0 {
		t.Fatalf("escalated inside the grace: %v", got)
	}
	if got, _ := drive(c, 1, 124000, 1, 400, landing); len(got) != 1 || got[0] != closeWMClose {
		t.Fatalf("expected WM_CLOSE after the grace, got %v", got)
	}
	if got, _ := drive(c, 1, 124400, 29, 400, landing); len(got) != 0 {
		t.Fatalf("gave up early: %v", got)
	}
	if got, _ := drive(c, 1, 136000, 1, 400, landing); len(got) != 1 || got[0] != closeGiveUp {
		t.Fatalf("expected the give-up, got %v", got)
	}
	if got, _ := drive(c, 1, 136400, 50, 400, landing); len(got) != 0 {
		t.Fatalf("acted after the landing's give-up: %v", got)
	}
}

// FIX153 bound exclusions: the bound judges ONLY the
// never-became-a-table shape. A session whose runtime stamped
// (a table demonstrably exists, however invisible its play)
// sits in the editor past the bound untouched - its landing
// is the standing undetectable-by-design case, not a landing
// to close on a clock. And a session that latched play but
// never sighted (no arm possible) is likewise untouched: play
// happened, so it is not the bound's subject either.
func TestFix153BoundExclusions(t *testing.T) {
	runtimeUp := &closer{}
	rtEd := tickIn{state: "live", alive: true, sighted: true, runtime: true, fgEd: true}
	if got, arms := drive(runtimeUp, 1, 0, 400, 400, rtEd); arms != 0 || len(got) != 0 {
		t.Fatalf("the bound fired on a runtime-stamped session (arms=%d, actions=%v)", arms, got)
	}
	latched := &closer{}
	playBlind := tickIn{state: "live", alive: true, sighted: false, fgPlayer: true}
	drive(latched, 1, 0, 5, 400, playBlind) // play latches; no sighting, no arm
	edBlind := tickIn{state: "live", alive: true, sighted: false, fgEd: true}
	if got, arms := drive(latched, 1, 2000, 400, 400, edBlind); arms != 0 || len(got) != 0 {
		t.Fatalf("the bound fired on a play-latched session (arms=%d, actions=%v)", arms, got)
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
