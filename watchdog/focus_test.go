package main

import (
	"strings"
	"testing"
)

// The launch focus sequence (focus.go), exercised on Linux:
// scripted foreground walks carrying the field sessions'
// shapes - the GL load shuffle (sessions 35/37/39), droscoe's
// BGFX launch (a VPPlayer target behind a streamer-held
// foreground), the stubborn holder, the editor cases, the
// deliberate holder, and the hand-off tick itself. Times are
// milliseconds relative to the sequence's own clock; the
// runtime anchor is passed the way main passes it (the
// absolute tick the watchdog first observed the runtime
// stamp).

const (
	hwFSDL   = uintptr(0xA1)
	hwFVP    = uintptr(0xA2)
	hwFMAME  = uintptr(0xB1)
	hwFEdit  = uintptr(0xE1)
	hwFDlg   = uintptr(0xD1)
	hwFVD    = uintptr(0xC4)
	hwFThird = uintptr(0xC3)
)

// seqWS builds a snapshot with the given foreground window
// and the given resolved player target (0 = none).
func seqWS(class string, pid int, hwnd, player uintptr, playerClass string) windowState {
	ws := windowState{inputAgeMs: -1}
	ws.fgClass, ws.fgPID, ws.fgHWND = class, pid, hwnd
	ws.fgIsGame = pid == gamePID && pid != 0
	ws.fgIsEditor = ws.fgIsGame && class == editorWindowClass
	ws.fgIsSDL = ws.fgIsGame && class == sdlWindowClass
	ws.playerHWND = player
	ws.playerClass = playerClass
	ws.fgIsPlayer = player != 0 && hwnd == player
	return ws
}

func fgSeqSDL() windowState  { return seqWS(sdlWindowClass, gamePID, hwFSDL, hwFSDL, sdlWindowClass) }
func fgSeqVP() windowState   { return seqWS(playerWindowClass, gamePID, hwFVP, hwFVP, playerWindowClass) }
func fgSeqMAME() windowState { return seqWS("MAME", gamePID, hwFMAME, hwFSDL, sdlWindowClass) }
func fgSeqEditor() windowState {
	return seqWS(editorWindowClass, gamePID, hwFEdit, hwFSDL, sdlWindowClass)
}
func fgSeqDialog() windowState {
	return seqWS(loadDialogClass, gamePID, hwFDlg, hwFSDL, sdlWindowClass)
}
func fgSeqVD() windowState    { return seqWS(vdWindowClass, vdPID, hwFVD, hwFSDL, sdlWindowClass) }
func fgSeqThird() windowState { return seqWS("OtherApp", 424242, hwFThird, hwFSDL, sdlWindowClass) }

// fgSeqThirdBGFX: droscoe's launch shape - the target is the
// VPPlayer window; the foreground sits on a third process
// (the streamer) with no desktop-input evidence either way.
func fgSeqThirdBGFX() windowState {
	return seqWS("OtherApp", 424242, hwFThird, hwFVP, playerWindowClass)
}

func seqTick(s *focusSequence, nowMs, runtimeUpMs int64, ws windowState) seqResult {
	return s.tick(nowMs, 1, runtimeUpMs, focusInputs{ws: ws, state: "live"})
}

// seqDrive feeds one steady foreground at 400ms spacing until
// the sequence returns a non-none action, and reports the
// action and the tick it landed on.
func seqDrive(s *focusSequence, fromMs, runtimeUpMs int64, ws windowState, maxTicks int) (seqAction, int64) {
	for i := 0; i < maxTicks; i++ {
		now := fromMs + int64(i)*400
		if res := seqTick(s, now, runtimeUpMs, ws); res.action != seqNone {
			return res.action, now
		}
	}
	return seqNone, fromMs + int64(maxTicks)*400
}

func TestFocusSession35Shape(t *testing.T) {
	// Session 35: the load's shuffle (dialog, SDL blip) ends
	// with PinMAME holding the foreground into the live
	// phase; the sequence asserts once the shuffle has
	// settled AND the load has had its floor, verifies, and
	// locks on the dwell - then a late re-grab inside the
	// launch window reopens it and it re-locks.
	var s focusSequence
	up := int64(10000)
	seqTick(&s, up, up, fgSeqDialog())
	seqTick(&s, up+400, up, fgSeqSDL())
	seqTick(&s, up+800, up, fgSeqMAME())
	act, at := seqDrive(&s, up+1200, up, fgSeqMAME(), 40)
	if act != seqAssert {
		t.Fatalf("settle+floor: got action %v at +%dms, want the assertion", act, at-up)
	}
	if at-up < focusResolveFloorMs {
		t.Fatalf("assertion at +%dms rel. runtime, before the %dms floor", at-up, focusResolveFloorMs)
	}
	if got := s.before(); got != `"MAME" (pid 5264)` {
		t.Fatalf("before() = %s, want the MAME holder named", got)
	}
	if res := s.noteAssert(at, true); res != seqNone {
		t.Fatalf("noteAssert = %v, want none", res)
	}
	if res := seqTick(&s, at+250, up, fgSeqSDL()); res.action != seqNone {
		t.Fatalf("verify tick: got %v, want none (dwell running)", res.action)
	}
	act, at2 := seqDrive(&s, at+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("dwell: got %v, want FocusLocked", act)
	}
	if at2 < at+250+focusDwellMs {
		t.Fatalf("locked at +%dms, before the %dms dwell ran", at2-at, focusDwellMs)
	}
	// The late re-grab: MAME takes it again inside the
	// launch window - the sequence reopens.
	res := seqTick(&s, at2+400, up, fgSeqMAME())
	if res.action != seqLogReopen {
		t.Fatalf("re-grab inside the window: got %v, want the reopen", res.action)
	}
	// It settles again, asserts again, and re-locks.
	act, at3 := seqDrive(&s, at2+800, up, fgSeqMAME(), 20)
	if act != seqAssert {
		t.Fatalf("post-reopen settle: got %v, want the assertion", act)
	}
	s.noteAssert(at3, true)
	seqTick(&s, at3+250, up, fgSeqSDL())
	act, _ = seqDrive(&s, at3+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("post-reopen dwell: got %v, want FocusLocked again", act)
	}
}

func TestFocusSession39Shape(t *testing.T) {
	// Session 39: the editor holds the whole spawn (the lull
	// - its clock must not start the settle), a one-tick SDL
	// blip passes, then PinMAME grabs at +6s and keeps it.
	// The assertion waits for PinMAME's own settle.
	var s focusSequence
	up := int64(10000)
	for now := up; now <= up+2800; now += 400 {
		if res := seqTick(&s, now, up, fgSeqEditor()); res.action != seqNone {
			t.Fatalf("editor lull at +%dms: got %v, want silence", now-up, res.action)
		}
	}
	seqTick(&s, up+3200, up, fgSeqSDL()) // the blip
	seqTick(&s, up+6000, up, fgSeqMAME())
	act, at := seqDrive(&s, up+6400, up, fgSeqMAME(), 20)
	if act != seqAssert {
		t.Fatalf("got %v, want the assertion against settled PinMAME", act)
	}
	if at != up+8800 {
		t.Fatalf("assertion at +%dms rel. runtime, want +8800 (PinMAME's settle)", at-up)
	}
	s.noteAssert(at, true)
	seqTick(&s, at+250, up, fgSeqSDL())
	act, _ = seqDrive(&s, at+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked", act)
	}
}

func TestFocusSession203LateMAMEFreshInput(t *testing.T) {
	// Session 203 (Chris's rig, 1.1.6's first field test):
	// the launch locks, then the game's own VPinMAME window
	// grabs the foreground LATE inside the launch window,
	// with desktop input landing right at the grab. Under
	// the shipped sequence the provenance veto read that
	// input as deliberate use, protected the game's own
	// shuffle, and resolved FocusUnresolved at the deadline
	// - a dead table. The veto is for foreign holders only:
	// over a game-family holder the sequence must re-assert
	// and re-lock, never resolve deliberate-use.
	var s focusSequence
	up := int64(10000)
	seqTick(&s, up, up, fgSeqDialog())
	res := s.tick(up+3000, 1, up, focusInputs{ws: fgSeqDialog(), state: "live", handoff: true})
	if res.action != seqAssert {
		t.Fatalf("hand-off over the load dialog: got %v, want the assertion", res.action)
	}
	s.noteAssert(up+3000, true)
	seqTick(&s, up+3250, up, fgSeqSDL())
	act, lockAt := seqDrive(&s, up+3650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("initial dwell: got %v, want FocusLocked", act)
	}
	// The late grab, one tick after the lock: MAME takes
	// the foreground with desktop input landing on it.
	grabAt := lockAt + 400
	mameFresh := func(now int64) windowState {
		ws := fgSeqMAME()
		ws.inputAgeMs = now - grabAt // the input landed as MAME took it
		ws.fgTitle = "VPinMAME: Tommy Pinball Wizard, The Who's (4.00)"
		return ws
	}
	if res := seqTick(&s, grabAt, up, mameFresh(grabAt)); res.action != seqLogReopen {
		t.Fatalf("late MAME grab: got %v, want the reopen", res.action)
	}
	// Work the holder: at its settle the sequence must
	// assert - the fresh desktop input beside a game-family
	// holder is not a veto.
	assertAt := int64(-1)
	for now := grabAt + 400; now <= up+focusDeadlineMs; now += 400 {
		if res := seqTick(&s, now, up, mameFresh(now)); res.action == seqAssert {
			assertAt = now
			break
		} else if res.action == seqLogUnresolved {
			t.Fatalf("at +%dms: resolved unresolved (%q) - the veto fired on a game-family holder", now-up, s.reason())
		}
	}
	if assertAt < 0 {
		t.Fatalf("no assertion against the late MAME grab before the deadline (reason %q)", s.reason())
	}
	if !s.beforeIsGameFamily() {
		t.Fatal("beforeIsGameFamily() = false, want true for the MAME assertion (the log line's wording)")
	}
	if got := s.before(); !strings.Contains(got, `"MAME"`) {
		t.Fatalf("before() = %s, want the MAME holder named", got)
	}
	s.noteAssert(assertAt, true)
	seqTick(&s, assertAt+250, up, fgSeqSDL())
	act, _ = seqDrive(&s, assertAt+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked again after the re-assertion", act)
	}
}

func TestFocusSession37Shape(t *testing.T) {
	// Session 37: the editor lulls, then the SDL window
	// comes up and simply stays - the sequence locks with
	// zero assertions.
	var s focusSequence
	up := int64(10000)
	lockedAt := int64(-1)
	for now := up; now <= up+12000; now += 400 {
		ws := fgSeqEditor()
		if now >= up+7000 {
			ws = fgSeqSDL()
		}
		res := seqTick(&s, now, up, ws)
		if res.action == seqAssert {
			t.Fatalf("at +%dms: an assertion was ordered against a settled player", now-up)
		}
		if res.action == seqLogLocked && lockedAt < 0 {
			lockedAt = now
		}
	}
	if lockedAt != up+9200 {
		t.Fatalf("locked at +%dms rel. runtime, want +9200 (the first 400ms-grid tick past floor 8000 + dwell 2000 from +7000)", lockedAt-up)
	}
}

func TestFocusBGFXThirdPartySteal(t *testing.T) {
	// Droscoe's launch: the target is the VPPlayer window,
	// the foreground sits on a third process (his streamer)
	// with no input evidence. The sequence asserts to the
	// BGFX player window - the act no pre-FIX116 code path
	// could perform - verifies, and locks.
	var s focusSequence
	up := int64(2000)
	act, at := seqDrive(&s, up, up, fgSeqThirdBGFX(), 40)
	if act != seqAssert || at != up+focusResolveFloorMs {
		t.Fatalf("got (%v, +%dms), want the assertion at the floor", act, at-up)
	}
	s.noteAssert(at, true)
	seqTick(&s, at+250, up, fgSeqVP())
	act, _ = seqDrive(&s, at+650, up, fgSeqVP(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked on the VPPlayer window", act)
	}
	if s.playerClass() != playerWindowClass {
		t.Fatalf("playerClass() = %q, want %q (the lock line's subject)", s.playerClass(), playerWindowClass)
	}
}

func TestFocusBGFXPlayerFromStart(t *testing.T) {
	// The BGFX player holds the foreground from the first
	// tick: locked at the floor with zero assertions.
	var s focusSequence
	up := int64(2000)
	for now := up; now < up+focusResolveFloorMs; now += 400 {
		if res := seqTick(&s, now, up, fgSeqVP()); res.action != seqNone {
			t.Fatalf("at +%dms: got %v, want silence before the floor", now-up, res.action)
		}
	}
	if res := seqTick(&s, up+focusResolveFloorMs, up, fgSeqVP()); res.action != seqLogLocked {
		t.Fatalf("at the floor: got %v, want FocusLocked", res.action)
	}
}

func TestFocusStubbornHolder(t *testing.T) {
	// The holder never yields: three verified attempts, then
	// the exhaustion IS the resolution.
	var s focusSequence
	up := int64(2000)
	act, at := seqDrive(&s, up, up, fgSeqMAME(), 40)
	if act != seqAssert {
		t.Fatalf("got %v, want the first assertion", act)
	}
	asserts := 1
	for cycle := 0; cycle < 2; cycle++ {
		s.noteAssert(at, true)
		if res := seqTick(&s, at+250, up, fgSeqMAME()); res.action != seqNone {
			t.Fatalf("cycle %d verify tick: got %v, want none", cycle, res.action)
		}
		res := seqTick(&s, at+1000, up, fgSeqMAME())
		if res.action != seqAssert {
			t.Fatalf("cycle %d verdict tick: got %v, want the retry assertion", cycle, res.action)
		}
		asserts++
		at += 1000
	}
	s.noteAssert(at, true)
	seqTick(&s, at+250, up, fgSeqMAME())
	res := seqTick(&s, at+1000, up, fgSeqMAME())
	if res.action != seqLogUnresolved {
		t.Fatalf("third verdict: got %v, want FocusUnresolved", res.action)
	}
	if asserts != 3 {
		t.Fatalf("assertions = %d, want exactly %d", asserts, focusMaxAttempts)
	}
	if !strings.Contains(s.reason(), "would not move after 3 attempts") {
		t.Fatalf("reason = %q, want the stubborn-holder wording", s.reason())
	}
	if !s.done() {
		t.Fatal("done() = false after the resolution")
	}
}

func TestFocusEditorAtDeadline(t *testing.T) {
	// The editor holds the foreground for the whole launch
	// window: silence (the lull) until the deadline names
	// it - and no assertion is ever ordered at it.
	var s focusSequence
	up := int64(2000)
	for now := up; now < up+focusDeadlineMs; now += 400 {
		if res := seqTick(&s, now, up, fgSeqEditor()); res.action != seqNone {
			t.Fatalf("at +%dms: got %v, want lull silence", now-up, res.action)
		}
	}
	res := seqTick(&s, up+focusDeadlineMs, up, fgSeqEditor())
	if res.action != seqLogUnresolved || s.reason() != "the editor holds the foreground" {
		t.Fatalf("deadline: got (%v, %q), want the editor resolution", res.action, s.reason())
	}
}

func TestFocusEditorDuringVerifyAborts(t *testing.T) {
	// An assertion is in flight and the editor takes the
	// foreground: the sequence resolves at once - the exit
	// detector owns what happens next.
	var s focusSequence
	up := int64(2000)
	_, at := seqDrive(&s, up, up, fgSeqMAME(), 40)
	s.noteAssert(at, true)
	res := seqTick(&s, at+250, up, fgSeqEditor())
	if res.action != seqLogUnresolved || s.reason() != "the editor holds the foreground" {
		t.Fatalf("got (%v, %q), want the editor abort", res.action, s.reason())
	}
}

func TestFocusDialogLull(t *testing.T) {
	// The load dialog holds past the floor: still a lull -
	// no settle runs under it. PinMAME after it settles and
	// is asserted on its own clock.
	var s focusSequence
	up := int64(2000)
	for now := up; now <= up+9000; now += 400 {
		if res := seqTick(&s, now, up, fgSeqDialog()); res.action != seqNone {
			t.Fatalf("dialog lull at +%dms: got %v, want silence", now-up, res.action)
		}
	}
	seqTick(&s, up+9200, up, fgSeqMAME())
	act, at := seqDrive(&s, up+9600, up, fgSeqMAME(), 20)
	if act != seqAssert || at != up+12000 {
		t.Fatalf("got (%v, +%dms), want the assertion at +12000 (PinMAME's settle)", act, at-up)
	}
}

func TestFocusDeliberateHolderRespected(t *testing.T) {
	// A third process takes the foreground WITH desktop
	// input landing on it (the player alt-tabbed): the
	// sequence never asserts against it, and the deadline
	// names the deliberate change.
	var s focusSequence
	up := int64(2000)
	for now := up; now < up+focusDeadlineMs; now += 400 {
		ws := fgSeqThird()
		ws.inputAgeMs = now - up // input landed as it took the foreground
		if res := seqTick(&s, now, up, ws); res.action != seqNone {
			t.Fatalf("at +%dms: got %v, want respect for the deliberate holder", now-up, res.action)
		}
	}
	res := seqTick(&s, up+focusDeadlineMs, up, fgSeqThird())
	if res.action != seqLogUnresolved || !strings.Contains(s.reason(), "deliberate use") {
		t.Fatalf("deadline: got (%v, %q), want the deliberate-use resolution", res.action, s.reason())
	}
}

func TestFocusNoTargetEver(t *testing.T) {
	// No player window ever resolves: nothing to assert, and
	// the deadline says so.
	var s focusSequence
	up := int64(2000)
	ws := fgSeqThird()
	ws.playerHWND = 0
	ws.playerClass = ""
	for now := up; now < up+focusDeadlineMs; now += 400 {
		if res := seqTick(&s, now, up, ws); res.action != seqNone {
			t.Fatalf("at +%dms: got %v, want silence without a target", now-up, res.action)
		}
	}
	res := seqTick(&s, up+focusDeadlineMs, up, ws)
	if res.action != seqLogUnresolved || s.reason() != "the player window never appeared" {
		t.Fatalf("deadline: got (%v, %q), want the never-appeared resolution", res.action, s.reason())
	}
}

func TestFocusHandoffTick(t *testing.T) {
	// The hand-off tick (the session first observed live
	// with the launcher gone) evaluates immediately - no
	// settle, no floor - because the foreground at that
	// moment is whatever the launcher's exit left behind.
	// The record with the exit detector is owed either way.
	var s focusSequence
	res := s.tick(5000, 1, 0, focusInputs{ws: fgSeqVD(), state: "live", handoff: true})
	if !res.notePush {
		t.Fatal("hand-off tick: notePush not owed")
	}
	if res.action != seqAssert {
		t.Fatalf("hand-off tick: got %v, want the immediate assertion", res.action)
	}
	s.noteAssert(5000, true)
	if res := seqTick(&s, 5250, 0, fgSeqSDL()); res.action != seqNone {
		t.Fatalf("verify tick: got %v, want none", res.action)
	}
	act, _ := seqDrive(&s, 5650, 0, fgSeqSDL(), 10)
	if act != seqLogLocked || !s.done() {
		t.Fatalf("got %v (done=%v), want the unanchored lock, final at once", act, s.done())
	}
	// The player already holding it: the record is still
	// owed, no assertion is ordered.
	var s2 focusSequence
	res = s2.tick(5000, 1, 0, focusInputs{ws: fgSeqSDL(), state: "live", handoff: true})
	if !res.notePush || res.action != seqNone {
		t.Fatalf("player-held hand-off: got (notePush=%v, %v), want (true, none)", res.notePush, res.action)
	}
}

func TestFocusDeadlineShuffle(t *testing.T) {
	// The foreground shuffles every tick (MAME <-> Virtual
	// Desktop), so nothing ever settles: at the deadline the
	// sequence makes its one final attempt, and a verified
	// placement still locks.
	var s focusSequence
	up := int64(2000)
	for now, i := up, 0; now < up+focusDeadlineMs; now, i = now+400, i+1 {
		ws := fgSeqMAME()
		if i%2 == 1 {
			ws = fgSeqVD()
		}
		if res := seqTick(&s, now, up, ws); res.action != seqNone {
			t.Fatalf("shuffle at +%dms: got %v, want silence until the deadline", now-up, res.action)
		}
	}
	res := seqTick(&s, up+focusDeadlineMs, up, fgSeqMAME())
	if res.action != seqAssert {
		t.Fatalf("deadline: got %v, want the final attempt", res.action)
	}
	at := up + focusDeadlineMs
	s.noteAssert(at, true)
	seqTick(&s, at+250, up, fgSeqSDL())
	act, _ := seqDrive(&s, at+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked off the final attempt", act)
	}
}

func TestFocusDeadlineFinalAttemptBrokenHold(t *testing.T) {
	// The deadline's final attempt VERIFIES - and then the
	// foreground flaps away again inside the dwell. The
	// sequence resolves ("would not hold") instead of
	// re-asserting past the deadline forever.
	var s focusSequence
	up := int64(2000)
	for now, i := up, 0; now < up+focusDeadlineMs; now, i = now+400, i+1 {
		ws := fgSeqMAME()
		if i%2 == 1 {
			ws = fgSeqVD()
		}
		seqTick(&s, now, up, ws)
	}
	at := up + focusDeadlineMs
	res := seqTick(&s, at, up, fgSeqMAME())
	if res.action != seqAssert {
		t.Fatalf("deadline: got %v, want the final attempt", res.action)
	}
	s.noteAssert(at, true)
	if res := seqTick(&s, at+250, up, fgSeqSDL()); res.action != seqNone {
		t.Fatalf("verify tick: got %v, want none (verified, dwell running)", res.action)
	}
	res = seqTick(&s, at+650, up, fgSeqVD())
	if res.action != seqLogUnresolved || !strings.Contains(s.reason(), "would not hold") {
		t.Fatalf("broken hold: got (%v, %q), want the would-not-hold resolution", res.action, s.reason())
	}
}

func TestFocusNoTargetAttemptLoggedOnce(t *testing.T) {
	// The leaf reports no target at the attempt: the
	// sequence logs it once and stands the attempt down -
	// and a later real attempt can still lock.
	var s focusSequence
	up := int64(2000)
	_, at := seqDrive(&s, up, up, fgSeqMAME(), 40)
	if res := s.noteAssert(at, false); res != seqLogNoTarget {
		t.Fatalf("noteAssert(false) = %v, want the no-target log", res)
	}
	act, at2 := seqDrive(&s, at+400, up, fgSeqMAME(), 20)
	if act != seqAssert {
		t.Fatalf("got %v, want a second attempt after the spacing", act)
	}
	if res := s.noteAssert(at2, false); res != seqNone {
		t.Fatalf("second noteAssert(false) = %v, want the log only once", res)
	}
	// The player takes it on its own and holds: locked
	// without any verified assertion (past the floor).
	seqTick(&s, at2+400, up, fgSeqSDL())
	act, _ = seqDrive(&s, at2+800, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked", act)
	}
}

// ----------------------------------------------------------------
// FIX117 focus delivery (the inner switch): the born-foreground
// shape (droscoe's sessions 18/19 - the player window foreground
// from the first tick, its thread's focus never delivered), the
// hand-off delivery moment, the verified-assertion delivery, the
// budget-end line, the probe flag, and the reader degradations.

// fgSeqFocus builds the born-foreground BGFX snapshot with the
// player thread's focus reading attached: focusHWND/focusClass
// are the thread's focus window as the leaf read it (the zero
// window with an empty class = the thread has no focus window).
func fgSeqFocus(focusHWND uintptr, focusClass string) windowState {
	ws := fgSeqVP()
	ws.focusRead = focusReadOK
	ws.playerFocusHWND = focusHWND
	ws.playerFocusClass = focusClass
	ws.focusIsPlayer = focusHWND != 0 && focusHWND == ws.playerHWND
	return ws
}

// seqTickIn feeds one tick with explicit sequence inputs (the
// ladder flags ride them).
func seqTickIn(s *focusSequence, nowMs, runtimeUpMs int64, in focusInputs) seqResult {
	return s.tick(nowMs, 1, runtimeUpMs, in)
}

func TestFocusBornForegroundOrdersDelivery(t *testing.T) {
	// Sessions 18/19 replayed with the reader attached: the
	// VPPlayer window holds the foreground from the first
	// tick (zero assertions in the field, a clean lock) while
	// its thread's focus sits on the game's own MAME window.
	// Today that shape produces NO actuation of any kind.
	// Now: the settle resolution (the lock branch, at the
	// floor) works the owed focus first - one delivery, rung
	// 1 by default - and once the focus lands, the lock
	// follows on its ordinary criteria.
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFMAME, "MAME")
	act, at := seqDrive(&s, up, up, ws, 40)
	if act != seqDeliverFocus || at != up+focusResolveFloorMs {
		t.Fatalf("got (%v, +%dms), want the delivery at the floor's resolution", act, at-up)
	}
	if s.deliverRung() != 1 {
		t.Fatalf("deliverRung() = %d, want the default rung 1", s.deliverRung())
	}
	if !strings.Contains(s.focusDesc(), "MAME") {
		t.Fatalf("focusDesc() = %q, want it to name where the focus sat", s.focusDesc())
	}
	s.noteDeliver(true)
	// The focus lands on the player window: the episode is
	// over, and the lock declares on the dwell behind it.
	act, _ = seqDrive(&s, at+400, up, fgSeqFocus(hwFVP, playerWindowClass), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked once the focus has landed", act)
	}
	if got := s.deliverAttempts; got != 0 {
		t.Fatalf("deliverAttempts = %d after the focus landed, want the episode reset", got)
	}
}

func TestFocusBornForegroundNoFocusWindow(t *testing.T) {
	// The zero-focus-window reading (the thread has NO focus
	// window - the other half of droscoe's state): a delivery
	// is owed exactly the same.
	var s focusSequence
	up := int64(2000)
	act, _ := seqDrive(&s, up, up, fgSeqFocus(0, ""), 40)
	if act != seqDeliverFocus {
		t.Fatalf("got %v, want a delivery ordered against the zero focus window", act)
	}
	if !strings.Contains(s.focusDesc(), "no window") {
		t.Fatalf("focusDesc() = %q, want the no-window wording", s.focusDesc())
	}
}

func TestFocusDeliveryAtHandoffTick(t *testing.T) {
	// The hand-off tick is the first delivery moment: the
	// player window already holds the foreground when the
	// launcher leaves, its thread focus elsewhere - the
	// delivery is ordered on that very tick, and the tick is
	// recorded with the exit detector as it always has been.
	var s focusSequence
	up := int64(2000)
	in := focusInputs{ws: fgSeqFocus(hwFMAME, "MAME"), state: "live", handoff: true}
	res := seqTickIn(&s, up, up, in)
	if res.action != seqDeliverFocus {
		t.Fatalf("got %v, want the delivery on the hand-off tick", res.action)
	}
	if !res.notePush {
		t.Fatal("the hand-off tick must be recorded (notePush) whatever the order")
	}
	// The ladder rides the inputs: rung 3 is honoured.
	var s3 focusSequence
	in.actuationRung = 3
	if res := seqTickIn(&s3, up, up, in); res.action != seqDeliverFocus || s3.deliverRung() != 3 {
		t.Fatalf("rung 3: got (%v, rung %d), want the delivery at rung 3", res.action, s3.deliverRung())
	}
	// An out-of-range rung clamps to 1.
	var s9 focusSequence
	in.actuationRung = 9
	if res := seqTickIn(&s9, up, up, in); res.action != seqDeliverFocus || s9.deliverRung() != 1 {
		t.Fatalf("rung 9: got (%v, rung %d), want the delivery clamped to rung 1", res.action, s9.deliverRung())
	}
}

func TestFocusDeliveryAfterVerifiedAssertion(t *testing.T) {
	// The foreground is won by OUR assertion (PinMAME held
	// it; the verify lands the player window) while the
	// thread focus still sits elsewhere: the delivery is due
	// on the verify tick itself - the foreground is ours, the
	// inner switch is the remaining half.
	var s focusSequence
	up := int64(2000)
	act, at := seqDrive(&s, up, up, fgSeqMAME(), 40)
	if act != seqAssert {
		t.Fatalf("got %v, want the assertion at the floor", act)
	}
	s.noteAssert(at, true)
	res := seqTick(&s, at+250, up, fgSeqFocus(hwFMAME, "MAME"))
	if res.action != seqDeliverFocus {
		t.Fatalf("verify tick: got %v, want the delivery behind the verified assertion", res.action)
	}
	if !res.notePush {
		t.Fatal("a real delivery moves the foreground value: notePush must ride it")
	}
}

func TestFocusDeliveryBudgetEndsWithNotDeliveredLine(t *testing.T) {
	// The focus never lands: three deliveries (the budget),
	// spaced; then ONE budget-end line naming the state; then
	// the lock on its 1.1.6 criteria anyway - the line is
	// log-only, never a lock blocker - and no second line.
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFMAME, "MAME")
	deliveries := 0
	notDelivered := 0
	locked := false
	for now := up; now <= up+focusResolveFloorMs+6000 && !locked; now += 400 {
		res := seqTick(&s, now, up, ws)
		switch res.action {
		case seqDeliverFocus:
			deliveries++
			s.noteDeliver(true)
		case seqLogFocusNotDelivered:
			notDelivered++
			if deliveries != focusMaxAttempts {
				t.Fatalf("budget-end line after %d deliveries, want the budget (%d) spent first", deliveries, focusMaxAttempts)
			}
		case seqLogLocked:
			locked = true
		case seqNone:
		default:
			t.Fatalf("at +%dms: unexpected action %v", now-up, res.action)
		}
	}
	if deliveries != focusMaxAttempts {
		t.Fatalf("deliveries = %d, want exactly the budget %d", deliveries, focusMaxAttempts)
	}
	if notDelivered != 1 {
		t.Fatalf("budget-end lines = %d, want exactly 1", notDelivered)
	}
	if !locked {
		t.Fatal("the sequence never locked: an undelivered focus must not block the 1.1.6 lock")
	}
}

func TestFocusProbeReplacesDelivery(t *testing.T) {
	// The probe flag: probes at the delivery moments, never a
	// rung delivery, and no foreground touch recorded (the
	// probe posts messages only).
	var s focusSequence
	up := int64(2000)
	probes := 0
	for now := up; now <= up+focusResolveFloorMs+2000; now += 400 {
		in := focusInputs{ws: fgSeqFocus(hwFMAME, "MAME"), state: "live", actuationProbe: true}
		res := seqTickIn(&s, now, up, in)
		switch res.action {
		case seqProbe:
			probes++
			if res.notePush {
				t.Fatal("a probe must never record a foreground touch")
			}
			s.noteDeliver(true)
		case seqDeliverFocus:
			t.Fatal("a delivery was ordered under the probe flag - the probe replaces rungs, never combines")
		case seqLogLocked:
			now = up + focusResolveFloorMs + 2000 // done: leave by the loop's end
		}
	}
	if probes == 0 {
		t.Fatal("no probe was ordered at the delivery moments")
	}
	if !s.deliverWasProbeAction() {
		t.Fatal("deliverWasProbeAction() = false after a probe order")
	}
}

func TestFocusReaderUnavailableDegradesTo116(t *testing.T) {
	// No reader (unknown) and a failed reader alike: the
	// born-foreground shape behaves EXACTLY as 1.1.6 - zero
	// deliveries, zero probe lines, the floor lock.
	for _, read := range []int{focusReadUnknown, focusReadFailed} {
		var s focusSequence
		up := int64(2000)
		ws := fgSeqVP()
		ws.focusRead = read
		ws.playerFocusHWND = hwFMAME // facts the reader never delivered - must be ignored
		ws.playerFocusClass = "MAME"
		act, at := seqDrive(&s, up, up, ws, 40)
		if act != seqLogLocked || at != up+focusResolveFloorMs {
			t.Fatalf("read=%d: got (%v, +%dms), want the plain 1.1.6 floor lock", read, act, at-up)
		}
	}
	// And with the focus already ON the player window, a
	// healthy reading likewise orders nothing.
	var s focusSequence
	up := int64(2000)
	act, _ := seqDrive(&s, up, up, fgSeqFocus(hwFVP, playerWindowClass), 40)
	if act != seqLogLocked {
		t.Fatalf("healthy focus: got %v, want the floor lock with no delivery", act)
	}
}

func TestFocusNoTargetDeliverNotSpent(t *testing.T) {
	// The leaf reports no target at a delivery: the attempt
	// is not spent against the episode budget (noteDeliver
	// rewinds it), so the delivery is ordered again on a
	// later due tick rather than burning the budget on
	// nothing.
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFMAME, "MAME")
	act, at := seqDrive(&s, up, up, ws, 40)
	if act != seqDeliverFocus {
		t.Fatalf("got %v, want the first delivery", act)
	}
	s.noteDeliver(false)
	if got := s.deliverAttempts; got != 0 {
		t.Fatalf("deliverAttempts = %d after a no-target delivery, want it unspent", got)
	}
	act, _ = seqDrive(&s, at+400, up, ws, 10)
	if act != seqDeliverFocus {
		t.Fatalf("got %v, want the delivery re-ordered after the no-target stand-down", act)
	}
}
