package main

import (
	"fmt"
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

// fgSeqB2S is the B2S server exe's DMD window (session
// 389's grabber): a window of the B2SBackglassServerEXE
// process - not the game pid, but game family by the
// server's name (FIX156's classification).
const (
	hwFB2S = uintptr(0xB2)
	b2sPID = 8704
)

func fgSeqB2S() windowState {
	ws := seqWS("WindowsForms10.Window.8.app.0.141b42a_r10_ad1", b2sPID, hwFB2S, hwFSDL, sdlWindowClass)
	ws.fgProcName = "B2SBackglassServerEXE.exe"
	ws.fgTitle = "B2S DMD"
	return ws
}

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
	// Session 35: the load's shuffle (dialog, SDL blip)
	// ends with PinMAME holding the foreground into the
	// live phase. Under FIX156 the shuffle is the settle
	// guard's whole duty: each family holder is answered
	// on the tick it is seen, the player then holds
	// through the dwell, and the session locks 3.2 s
	// after runtime-up. A late re-grab inside the launch
	// window reopens the sequence, and the re-lock is the
	// legacy machinery's (settle + floor) - the guard
	// does not re-arm.
	var s focusSequence
	up := int64(10000)
	if res := seqTick(&s, up, up, fgSeqDialog()); res.action != seqSettleAssert {
		t.Fatalf("dialog: got %v, want the guard's answer on the tick", res.action)
	}
	seqTick(&s, up+400, up, fgSeqSDL())
	res := seqTick(&s, up+800, up, fgSeqMAME())
	if res.action != seqSettleAssert {
		t.Fatalf("PinMAME grab: got %v, want the guard's answer on the tick", res.action)
	}
	if got := s.settleGrab(); got != `"MAME" (pid 5264)` {
		t.Fatalf("settleGrab() = %s, want the MAME holder named", got)
	}
	if got := s.settleInterrupted(); got != 400 {
		t.Fatalf("settleInterrupted() = %dms, want the 400ms blip the grab interrupted", got)
	}
	act, at := seqDrive(&s, up+1200, up, fgSeqSDL(), 10)
	if act != seqLogLocked || at != up+3200 {
		t.Fatalf("hold: got (%v, +%dms), want the settle lock at +3200", act, at-up)
	}
	if !s.settleLockUsed() || s.settleLockElapsed() != 3200 || s.settleAssertCount() != 2 {
		t.Fatalf("settle lock facts: used=%v elapsed=%d asserts=%d, want (true, 3200, 2)",
			s.settleLockUsed(), s.settleLockElapsed(), s.settleAssertCount())
	}
	// The late re-grab: MAME takes it again inside the
	// launch window - the sequence reopens.
	if res := seqTick(&s, at+400, up, fgSeqMAME()); res.action != seqLogReopen {
		t.Fatalf("re-grab inside the window: got %v, want the reopen", res.action)
	}
	// It settles again, asserts again (the legacy
	// assertion, at the floor), and re-locks.
	act, at3 := seqDrive(&s, at+800, up, fgSeqMAME(), 30)
	if act != seqAssert {
		t.Fatalf("post-reopen settle: got %v, want the legacy assertion", act)
	}
	if got := s.before(); got != `"MAME" (pid 5264)` {
		t.Fatalf("before() = %s, want the MAME holder named", got)
	}
	s.noteAssert(at3, true)
	if res := seqTick(&s, at3+250, up, fgSeqSDL()); res.action != seqNone {
		t.Fatalf("verify tick: got %v, want none (dwell running)", res.action)
	}
	act, _ = seqDrive(&s, at3+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("post-reopen dwell: got %v, want FocusLocked again", act)
	}
}

func TestFocusSession39Shape(t *testing.T) {
	// Session 39: the editor holds the whole spawn (the lull
	// - the settle guard never answers the editor, exactly
	// as the sequence never did), a one-tick SDL blip
	// passes, then PinMAME grabs at +6s. Under FIX156 the
	// grab is answered on the tick it is seen - it no
	// longer waits for PinMAME's own settle - and the
	// player then holds into the guard's lock.
	var s focusSequence
	up := int64(10000)
	for now := up; now <= up+2800; now += 400 {
		if res := seqTick(&s, now, up, fgSeqEditor()); res.action != seqNone {
			t.Fatalf("editor lull at +%dms: got %v, want silence", now-up, res.action)
		}
	}
	seqTick(&s, up+3200, up, fgSeqSDL()) // the blip
	if res := seqTick(&s, up+6000, up, fgSeqMAME()); res.action != seqSettleAssert {
		t.Fatalf("PinMAME grab: got %v, want the guard's answer on the tick", res.action)
	}
	act, at := seqDrive(&s, up+6400, up, fgSeqSDL(), 10)
	if act != seqLogLocked || at != up+8400 {
		t.Fatalf("got (%v, +%dms), want the settle lock at +8400", act, at-up)
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
	// comes up and simply stays - the session locks with
	// zero assertions of either path. Under FIX156 the
	// lock is the settle guard's: the hold starts at the
	// first grid tick at/after +7000 (+7200) and its
	// dwell completes at +9200 - the same tick the old
	// floor-bound lock landed on, reached by the guard
	// without the floor.
	var s focusSequence
	up := int64(10000)
	lockedAt := int64(-1)
	for now := up; now <= up+12000; now += 400 {
		ws := fgSeqEditor()
		if now >= up+7000 {
			ws = fgSeqSDL()
		}
		res := seqTick(&s, now, up, ws)
		if res.action == seqAssert || res.action == seqSettleAssert {
			t.Fatalf("at +%dms: an assertion was ordered against a settled player", now-up)
		}
		if res.action == seqLogLocked && lockedAt < 0 {
			lockedAt = now
		}
	}
	if lockedAt != up+9200 {
		t.Fatalf("locked at +%dms rel. runtime, want +9200 (the dwell from the +7200 hold, on the guard's watch)", lockedAt-up)
	}
	if !s.settleLockUsed() || s.settleLockElapsed() != 9200 || s.settleAssertCount() != 0 {
		t.Fatalf("settle lock facts: used=%v elapsed=%d asserts=%d, want (true, 9200, 0)",
			s.settleLockUsed(), s.settleLockElapsed(), s.settleAssertCount())
	}
}

func TestFocusBGFXThirdPartySteal(t *testing.T) {
	// Droscoe's launch: the target is the VPPlayer window,
	// the foreground sits on a third process (his streamer)
	// with no input evidence. Under FIX156 the settle
	// guard answers the foreign holder on the tick it is
	// seen - the assertion to the BGFX player window, the
	// act no pre-FIX116 code path could perform - and the
	// player then holds into the guard's lock.
	var s focusSequence
	up := int64(2000)
	if res := seqTick(&s, up, up, fgSeqThirdBGFX()); res.action != seqSettleAssert {
		t.Fatalf("got %v, want the guard's answer on the tick", res.action)
	}
	act, at := seqDrive(&s, up+400, up, fgSeqVP(), 10)
	if act != seqLogLocked || at != up+2400 {
		t.Fatalf("got (%v, +%dms), want the settle lock at +2400", act, at-up)
	}
	if s.playerClass() != playerWindowClass {
		t.Fatalf("playerClass() = %q, want %q (the lock line's subject)", s.playerClass(), playerWindowClass)
	}
}

func TestFocusBGFXPlayerFromStart(t *testing.T) {
	// The BGFX player holds the foreground from the first
	// tick: zero assertions, and under FIX156 the lock
	// lands at the dwell on the settle guard's watch -
	// the floor no longer gates an undisturbed hold.
	var s focusSequence
	up := int64(2000)
	for now := up; now < up+focusDwellMs; now += 400 {
		if res := seqTick(&s, now, up, fgSeqVP()); res.action != seqNone {
			t.Fatalf("at +%dms: got %v, want silence inside the dwell", now-up, res.action)
		}
	}
	if res := seqTick(&s, up+focusDwellMs, up, fgSeqVP()); res.action != seqLogLocked {
		t.Fatalf("at the dwell: got %v, want FocusLocked", res.action)
	}
	if !s.settleLockUsed() {
		t.Fatal("settleLockUsed() = false after the guard's lock")
	}
}

func TestFocusStubbornHolder(t *testing.T) {
	// The holder never yields. Under FIX156 the settle
	// guard answers it on every tick of the duty window -
	// no verify phase, no spacing; the next tick's
	// snapshot is the read-back - and at the deadline the
	// guard stands down and the sequence resolves on the
	// shared episode record: the foreground would not
	// move, and the count is the real one.
	var s focusSequence
	up := int64(2000)
	asserts := 0
	for now := up; now < up+focusDeadlineMs; now += 400 {
		res := seqTick(&s, now, up, fgSeqMAME())
		if res.action != seqSettleAssert {
			t.Fatalf("at +%dms: got %v, want the guard's per-tick answer", now-up, res.action)
		}
		asserts++
	}
	if asserts < 40 {
		t.Fatalf("guard assertions = %d, want a per-tick answer across the duty window", asserts)
	}
	res := seqTick(&s, up+focusDeadlineMs, up, fgSeqMAME())
	if res.action != seqLogUnresolved {
		t.Fatalf("deadline: got %v, want FocusUnresolved", res.action)
	}
	if !strings.Contains(s.reason(), "would not move after") || !strings.Contains(s.reason(), "MAME") {
		t.Fatalf("reason = %q, want the stubborn-holder wording naming MAME", s.reason())
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
	// detector owns what happens next. The in-flight
	// assertion is the hand-off tick's: with no runtime
	// anchor the settle guard never arms, so the legacy
	// verify machinery owns the shape end to end.
	var s focusSequence
	res := s.tick(5000, 1, 0, focusInputs{ws: fgSeqMAME(), state: "live", handoff: true})
	if res.action != seqAssert {
		t.Fatalf("hand-off tick: got %v, want the assertion", res.action)
	}
	s.noteAssert(5000, true)
	res = seqTick(&s, 5250, 0, fgSeqEditor())
	if res.action != seqLogUnresolved || s.reason() != "the editor holds the foreground" {
		t.Fatalf("got (%v, %q), want the editor abort", res.action, s.reason())
	}
}

func TestFocusDialogLull(t *testing.T) {
	// The load dialog holds. Under FIX156 it is a
	// game-family holder like any other, and the settle
	// guard answers it on the tick it is seen - the launch
	// is no longer silent under it. The lull rule itself
	// survives for the legacy settle: after the guard's
	// lock and a reopen, a dialog's stability still does
	// not count toward a settle resolution (its clock
	// restarts every tick it holds).
	var s focusSequence
	up := int64(2000)
	if res := seqTick(&s, up, up, fgSeqDialog()); res.action != seqSettleAssert {
		t.Fatalf("dialog: got %v, want the guard's answer on the tick", res.action)
	}
	act, at := seqDrive(&s, up+400, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want the settle lock behind the answered dialog", act)
	}
	if res := seqTick(&s, at+400, up, fgSeqDialog()); res.action != seqLogReopen {
		t.Fatalf("dialog re-grab: got %v, want the reopen", res.action)
	}
	for now := at + 800; now < up+focusDeadlineMs; now += 400 {
		if res := seqTick(&s, now, up, fgSeqDialog()); res.action == seqAssert {
			t.Fatalf("at +%dms: an assertion rode the dialog's stability (the lull)", now-up)
		}
	}
}

func TestFocusDeliberateHolderRespected(t *testing.T) {
	// A third process takes the foreground WITH desktop
	// input landing on it (the player alt-tabbed). The
	// sequence's provenance veto no longer gets the first
	// word during the duty window: the settle guard's law
	// is survivals, so it answers - and the holder, being
	// genuinely the user's, survives three answers and
	// the guard yields to it. From then on nothing asserts
	// against it (the sequence's own veto agrees), and
	// the deadline names the deliberate change.
	var s focusSequence
	up := int64(2000)
	third := func(now int64) windowState {
		ws := fgSeqThird()
		ws.inputAgeMs = now - up // input landed as it took the foreground
		return ws
	}
	for i, want := range []seqAction{seqSettleAssert, seqSettleAssert, seqSettleAssert, seqLogSettleYield} {
		now := up + int64(i)*400
		if res := seqTick(&s, now, up, third(now)); res.action != want {
			t.Fatalf("tick %d: got %v, want %v", i, res.action, want)
		}
	}
	for now := up + 1600; now < up+focusDeadlineMs; now += 400 {
		if res := seqTick(&s, now, up, third(now)); res.action != seqNone {
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
	// Desktop), so nothing ever settles: under FIX156 the
	// settle guard answers every tick of the shuffle (the
	// VD window never survives an answer - the foreground
	// leaves it on the next tick - so the yield never
	// trips), and at the deadline the guard stands down
	// and the sequence makes its one final attempt; a
	// verified placement still locks.
	var s focusSequence
	up := int64(2000)
	for now, i := up, 0; now < up+focusDeadlineMs; now, i = now+400, i+1 {
		ws := fgSeqMAME()
		if i%2 == 1 {
			ws = fgSeqVD()
		}
		if res := seqTick(&s, now, up, ws); res.action != seqSettleAssert {
			t.Fatalf("shuffle at +%dms: got %v, want the guard's answer", now-up, res.action)
		}
	}
	if s.settleYielded() {
		t.Fatal("the guard yielded during the shuffle: no window survived an answer")
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
	// and a later real attempt can still lock. Under
	// FIX156 the only assertion phase a no-target report
	// can answer is the hand-off tick's (the guard answers
	// only with a target in hand and never enters the
	// verify phase), so the shape enters through the
	// hand-off; the once-only latch then binds the
	// episode's later attempts too, and the eventual lock
	// rides the guard once the runtime anchor lands.
	var s focusSequence
	res := s.tick(5000, 1, 0, focusInputs{ws: fgSeqMAME(), state: "live", handoff: true})
	if res.action != seqAssert {
		t.Fatalf("hand-off tick: got %v, want the assertion", res.action)
	}
	if res := s.noteAssert(5000, false); res != seqLogNoTarget {
		t.Fatalf("noteAssert(false) = %v, want the no-target log", res)
	}
	if res := s.noteAssert(5000, false); res != seqNone {
		t.Fatalf("second noteAssert(false) = %v, want the log only once", res)
	}
	// The anchor lands; the player comes up and holds:
	// the guard locks the session.
	act, _ := seqDrive(&s, 20000, 20000, fgSeqSDL(), 10)
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
	// inner switch is the remaining half. Under FIX156 the
	// guard never enters the verify phase, so the shape
	// enters through the hand-off tick's assertion - whose
	// verify still owes the FIX118 blind delivery, and the
	// guard's completion deferral leaves that delivery
	// untouched when the anchor lands.
	var s focusSequence
	up := int64(2000)
	res := seqTickIn(&s, up, up, focusInputs{ws: fgSeqMAME(), state: "live", handoff: true})
	if res.action != seqAssert {
		t.Fatalf("hand-off tick: got %v, want the assertion", res.action)
	}
	s.noteAssert(up, true)
	res = seqTick(&s, up+250, up, fgSeqFocus(hwFMAME, "MAME"))
	if res.action != seqDeliverFocus {
		t.Fatalf("verify tick: got %v, want the delivery behind the verified assertion", res.action)
	}
	if !res.notePush {
		t.Fatal("a real delivery moves the foreground value: notePush must ride it")
	}
	s.noteDeliver(true)
	res = seqTick(&s, up+1250, up, fgSeqFocus(hwFMAME, "MAME"))
	if res.action != seqDeliverFocus {
		t.Fatalf("delivery-due tick: got %v, want the FIX118 delivery behind the blind hand-off", res.action)
	}
	if s.deliverWasUnconditional() {
		t.Fatal("deliverWasUnconditional() = true; the delivery follows a verified assertion")
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
	// born-foreground shape orders nothing FIX117 - zero
	// deliveries, zero probe lines - and locks on the
	// plain foreground record. Under FIX156 the lock is
	// the settle guard's at the dwell; the 1.1.6 surface
	// it degrades to is the absence of delivery machinery,
	// which is what this leg guards.
	for _, read := range []int{focusReadUnknown, focusReadFailed} {
		var s focusSequence
		up := int64(2000)
		ws := fgSeqVP()
		ws.focusRead = read
		ws.playerFocusHWND = hwFMAME // facts the reader never delivered - must be ignored
		ws.playerFocusClass = "MAME"
		act, at := seqDrive(&s, up, up, ws, 40)
		if act != seqLogLocked || at != up+focusDwellMs {
			t.Fatalf("read=%d: got (%v, +%dms), want the plain dwell lock with no delivery", read, act, at-up)
		}
	}
	// And with the focus already ON the player window, a
	// healthy reading likewise orders nothing.
	var s focusSequence
	up := int64(2000)
	act, _ := seqDrive(&s, up, up, fgSeqFocus(hwFVP, playerWindowClass), 40)
	if act != seqLogLocked {
		t.Fatalf("healthy focus: got %v, want the dwell lock with no delivery", act)
	}
}

// ----------------------------------------------------------------
// FIX118: the blind hand-off delivery. Droscoe's sessions
// 20-24 are the shape: the focus reading says the player
// window already holds its thread's focus - the state 1.1.7
// read as "nothing owed" - while the buttons stay dead.
// The hand-off order now fires regardless of the reading.

func TestFocusUnconditionalDeliveryHealthyFocus(t *testing.T) {
	// The healthy reading (focus ON the player window) at
	// the hand-off tick: 1.1.7 ordered nothing, ever. Now
	// the rung fires exactly once, flagged unconditional,
	// and the lock then lands on its ordinary criteria with
	// no second order behind it.
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFVP, playerWindowClass)
	in := focusInputs{ws: ws, state: "live", handoff: true}
	res := seqTickIn(&s, up, up, in)
	if res.action != seqDeliverFocus {
		t.Fatalf("hand-off tick: got %v, want the blind delivery", res.action)
	}
	if !s.deliverWasUnconditional() {
		t.Fatal("the hand-off order was not flagged unconditional")
	}
	if !res.notePush {
		t.Fatal("the hand-off tick must be recorded (notePush) whatever the order")
	}
	s.noteDeliver(true)
	deliveries := 1
	locked := false
	for now := up + 400; now <= up+focusResolveFloorMs+4000 && !locked; now += 400 {
		res := seqTickIn(&s, now, up, focusInputs{ws: ws, state: "live"})
		switch res.action {
		case seqDeliverFocus, seqProbe:
			deliveries++
		case seqLogLocked:
			locked = true
		case seqNone:
		default:
			t.Fatalf("at +%dms: unexpected action %v", now-up, res.action)
		}
	}
	if deliveries != 1 {
		t.Fatalf("deliveries = %d, want exactly the one blind order", deliveries)
	}
	if !locked {
		t.Fatal("the sequence never locked behind the blind delivery")
	}
}

func TestFocusUnconditionalDeliveryFailedReader(t *testing.T) {
	// A FAILED reading at the hand-off tick still orders:
	// the reading's value is not consulted, and a failed
	// read is a reader that exists. (An ABSENT reader -
	// focusReadUnknown - still orders nothing: that shape
	// stays 1.1.6, as TestFocusHandoffTick pins.)
	var s focusSequence
	up := int64(2000)
	ws := fgSeqVP()
	ws.focusRead = focusReadFailed
	res := seqTickIn(&s, up, up, focusInputs{ws: ws, state: "live", handoff: true})
	if res.action != seqDeliverFocus {
		t.Fatalf("hand-off tick with a failed reader: got %v, want the blind delivery", res.action)
	}
	if !s.deliverWasUnconditional() {
		t.Fatal("the failed-reader order was not flagged unconditional")
	}
}

func TestFocusUnconditionalProbeHealthyFocus(t *testing.T) {
	// The probe under its flag takes the blind moment the
	// same way: exactly one probe at the hand-off tick even
	// with the focus reading healthy, no probe behind it,
	// and the lock unaffected.
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFVP, playerWindowClass)
	in := focusInputs{ws: ws, state: "live", handoff: true, actuationProbe: true}
	res := seqTickIn(&s, up, up, in)
	if res.action != seqProbe {
		t.Fatalf("hand-off tick: got %v, want the blind probe", res.action)
	}
	if !s.deliverWasUnconditional() {
		t.Fatal("the hand-off probe was not flagged unconditional")
	}
	s.noteDeliver(true)
	probes := 1
	locked := false
	for now := up + 400; now <= up+focusResolveFloorMs+4000 && !locked; now += 400 {
		res := seqTickIn(&s, now, up, focusInputs{ws: ws, state: "live", actuationProbe: true})
		switch res.action {
		case seqProbe:
			probes++
		case seqDeliverFocus:
			t.Fatal("a delivery was ordered under the probe flag")
		case seqLogLocked:
			locked = true
		}
	}
	if probes != 1 {
		t.Fatalf("probes = %d, want exactly the one blind probe", probes)
	}
	if !locked {
		t.Fatal("the sequence never locked behind the blind probe")
	}
}

func TestFocusUnconditionalAfterHandoffAssertion(t *testing.T) {
	// The hand-off tick spends itself on an assertion (a
	// stranger holds the foreground): the blind order stays
	// owed and fires on the verify tick, the first tracking
	// tick with the player window in front - even though
	// the focus reading there is already healthy.
	var s focusSequence
	up := int64(2000)
	res := seqTickIn(&s, up, up, focusInputs{ws: fgSeqThirdBGFX(), state: "live", handoff: true})
	if res.action != seqAssert {
		t.Fatalf("hand-off tick: got %v, want the assertion", res.action)
	}
	s.noteAssert(up, true)
	res = seqTick(&s, up+250, up, fgSeqFocus(hwFVP, playerWindowClass))
	if res.action != seqDeliverFocus {
		t.Fatalf("verify tick: got %v, want the still-owed blind delivery", res.action)
	}
	if !s.deliverWasUnconditional() {
		t.Fatal("the post-assertion order was not flagged unconditional")
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

func TestFocusHandoffAfterLoadingLock(t *testing.T) {
	for _, delay := range []int64{focusResolveFloorMs + 1000, focusDeadlineMs + 1000} {
		t.Run(fmt.Sprintf("delay_%d", delay), func(t *testing.T) {
			var s focusSequence
			up := int64(2000)
			ws := fgSeqFocus(hwFVP, playerWindowClass)
			loading := focusInputs{ws: ws, state: "loading"}
			seqTickIn(&s, up, up, loading)
			if res := seqTickIn(&s, up+focusResolveFloorMs, up, loading); res.action != seqLogLocked {
				t.Fatalf("loading: got %v, want a foreground lock", res.action)
			}
			if delay > focusDeadlineMs {
				seqTickIn(&s, up+focusDeadlineMs, up, loading)
				if !s.done() {
					t.Fatal("expected the early lock to reach its deadline")
				}
			}
			in := focusInputs{ws: ws, state: "live", handoff: true}
			res := seqTickIn(&s, up+delay, up, in)
			if res.action != seqDeliverFocus || !res.notePush || !s.deliverWasUnconditional() {
				t.Fatalf("late hand-off: got %+v, want the unconditional delivery with push guard", res)
			}
			s.noteDeliver(true)
			for now := up + delay + 400; now <= up+delay+4000; now += 400 {
				res = seqTickIn(&s, now, up, in)
				if res.action == seqDeliverFocus || res.action == seqProbe {
					t.Fatal("late hand-off repeated its delivery")
				}
			}
		})
	}
}

func TestFocusHandoffDeliveryRetriesVanishedTarget(t *testing.T) {
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFVP, playerWindowClass)
	in := focusInputs{ws: ws, state: "live", handoff: true}
	if res := seqTickIn(&s, up, up, in); res.action != seqDeliverFocus {
		t.Fatalf("hand-off: got %v, want delivery", res.action)
	}
	s.noteDeliver(false)
	if s.handoffDeliveryDone {
		t.Fatal("a vanished target consumed the session's hand-off delivery")
	}
	if res := seqTickIn(&s, up+400, up, in); res.action != seqNone {
		t.Fatalf("before retry spacing: got %v, want none", res.action)
	}
	if res := seqTickIn(&s, up+focusAssertSpacingMs, up, in); res.action != seqDeliverFocus {
		t.Fatalf("retry: got %v, want delivery", res.action)
	}
}

func TestFocusLateHandoffRespectsEditorAndDeliberateUse(t *testing.T) {
	for _, ws := range []windowState{fgSeqEditor(), fgSeqThirdBGFX()} {
		var s focusSequence
		up := int64(2000)
		player := fgSeqFocus(hwFVP, playerWindowClass)
		seqTick(&s, up, up, player)
		seqTick(&s, up+focusResolveFloorMs, up, player)
		ws.altWinEdge = true
		res := seqTickIn(&s, up+focusResolveFloorMs+400, up,
			focusInputs{ws: ws, state: "live", handoff: true})
		if res.action == seqDeliverFocus || res.action == seqAssert || res.action == seqProbe {
			t.Fatalf("hand-off interfered with editor/deliberate foreground: %+v", res)
		}
	}
}

func TestFocusLockedHandoffWithoutReaderDoesNotRepeat(t *testing.T) {
	var s focusSequence
	up := int64(2000)
	ws := fgSeqVP() // A platform leaf with no focus reader.
	seqTick(&s, up, up, ws)
	seqTick(&s, up+focusResolveFloorMs, up, ws)
	in := focusInputs{ws: ws, state: "live", handoff: true}
	res := seqTickIn(&s, up+focusResolveFloorMs+400, up, in)
	if res.action != seqLogLocked || !res.notePush {
		t.Fatalf("readerless hand-off: got %+v, want the lock and push guard", res)
	}
	for now := up + focusResolveFloorMs + 800; now <= up+focusDeadlineMs+400; now += 400 {
		if res := seqTickIn(&s, now, up, in); res.action != seqNone {
			t.Fatalf("readerless hand-off repeated at %d: %+v", now, res)
		}
	}
}

func TestFocusLockedHandoffRetriesAtSpacing(t *testing.T) {
	var s focusSequence
	up := int64(2000)
	ws := fgSeqFocus(hwFVP, playerWindowClass)
	seqTick(&s, up, up, ws)
	seqTick(&s, up+focusResolveFloorMs, up, ws)
	in := focusInputs{ws: ws, state: "live", handoff: true}
	at := up + focusResolveFloorMs + 400
	if res := seqTickIn(&s, at, up, in); res.action != seqDeliverFocus {
		t.Fatalf("locked hand-off: got %v, want delivery", res.action)
	}
	s.noteDeliver(false)
	if res := seqTickIn(&s, at+400, up, in); res.action != seqNone {
		t.Fatalf("pending delivery locked or retried too soon: %+v", res)
	}
	if res := seqTickIn(&s, at+focusAssertSpacingMs, up, in); res.action != seqDeliverFocus {
		t.Fatalf("locked hand-off retry: got %v, want delivery", res.action)
	}
}

// ----------------------------------------------------------------
// FIX156: the settle guard. The convicted shape (session
// 389, Doctor Who): after runtime-up, family windows grab
// the foreground for seconds at a time while the sequence's
// settle/floor cadence is still winding up, and the user's
// input in those seconds is lost. The guard answers a grab
// on the tick it is seen, yields to a foreign window that
// survives three answers, and ends its duty at its lock.

func TestFocusSettleGuardDoctorWhoReplay(t *testing.T) {
	// Session 389 replayed at the guard's tick: the player
	// holds, the B2S DMD window grabs - answered on that
	// tick; the player holds, the VPinMAME window grabs -
	// answered on that tick; the player then holds
	// unbroken for the settle period and the session locks
	// 3.6 s after runtime-up, where the field took 14 s.
	// No grab is ever held longer than the tick that
	// answers it.
	var s focusSequence
	up := int64(10000)
	if res := seqTick(&s, up, up, fgSeqSDL()); res.action != seqNone {
		t.Fatalf("player's first hold: got %v, want silence", res.action)
	}
	res := seqTick(&s, up+400, up, fgSeqB2S())
	if res.action != seqSettleAssert {
		t.Fatalf("B2S grab: got %v, want the guard's answer on the tick", res.action)
	}
	if got := s.settleGrab(); !strings.Contains(got, "B2SBackglassServerEXE") {
		t.Fatalf("settleGrab() = %s, want the B2S server named", got)
	}
	if got := s.settleInterrupted(); got != 400 {
		t.Fatalf("settleInterrupted() = %dms, want the 400ms hold the grab interrupted", got)
	}
	if res := seqTick(&s, up+800, up, fgSeqSDL()); res.action != seqNone {
		t.Fatalf("restored hold: got %v, want silence", res.action)
	}
	res = seqTick(&s, up+1200, up, fgSeqMAME())
	if res.action != seqSettleAssert {
		t.Fatalf("MAME grab: got %v, want the guard's answer on the tick", res.action)
	}
	if got := s.settleGrab(); !strings.Contains(got, `"MAME"`) {
		t.Fatalf("settleGrab() = %s, want the MAME holder named", got)
	}
	if got := s.settleInterrupted(); got != 400 {
		t.Fatalf("settleInterrupted() = %dms, want the 400ms hold the grab interrupted", got)
	}
	act, at := seqDrive(&s, up+1600, up, fgSeqSDL(), 10)
	if act != seqLogLocked || at != up+3600 {
		t.Fatalf("hold: got (%v, +%dms), want the settle lock at +3600", act, at-up)
	}
	if !s.settleLockUsed() {
		t.Fatal("settleLockUsed() = false after the guard's lock")
	}
	if got := s.settleLockElapsed(); got != 3600 {
		t.Fatalf("settleLockElapsed() = %dms, want 3600 (the field's 14 s, beaten)", got)
	}
	if got := s.settleAssertCount(); got != 2 {
		t.Fatalf("settleAssertCount() = %d, want the 2 answered grabs", got)
	}
	if s.done() {
		t.Fatal("done() = true at the lock: the reopen watch still owns the launch window")
	}
}

func TestFocusSettleGuardYieldReplay(t *testing.T) {
	// A foreign window (a third process, no game relation)
	// takes the foreground during the duty window and keeps
	// it through the guard's answers: each survival is read
	// on the next tick, and at the third the guard yields -
	// deliberate use - and stands down for the session. No
	// branch asserts over it afterwards, and the deadline
	// names it deliberate use.
	var s focusSequence
	up := int64(2000)
	for i, want := range []seqAction{seqSettleAssert, seqSettleAssert, seqSettleAssert, seqLogSettleYield} {
		res := seqTick(&s, up+int64(i)*400, up, fgSeqThird())
		if res.action != want {
			t.Fatalf("tick %d: got %v, want %v", i, res.action, want)
		}
	}
	if !s.settleYielded() {
		t.Fatal("settleYielded() = false after the third survival")
	}
	if s.settleOnDuty() {
		t.Fatal("settleOnDuty() = true after the yield: the guard must stand down")
	}
	// Silence from then on, through the floor and the
	// settle: the yielded window is never asserted over
	// again by any branch.
	for now := up + 1600; now < up+focusDeadlineMs; now += 400 {
		if res := seqTick(&s, now, up, fgSeqThird()); res.action != seqNone {
			t.Fatalf("at +%dms: got %v, want silence after the yield", now-up, res.action)
		}
	}
	res := seqTick(&s, up+focusDeadlineMs, up, fgSeqThird())
	if res.action != seqLogUnresolved || !strings.Contains(s.reason(), "deliberate use") {
		t.Fatalf("deadline: got (%v, %q), want the deliberate-use resolution", res.action, s.reason())
	}
}

func TestFocusSettleGuardDoesNotRearm(t *testing.T) {
	// The guard's lock ends its duty for the session: a
	// later family grab inside the launch window reopens
	// the sequence (the standing law) and is worked by the
	// pre-existing machinery at its own cadence - the
	// guard never answers again.
	var s focusSequence
	up := int64(10000)
	act, at := seqDrive(&s, up, up, fgSeqSDL(), 10)
	if act != seqLogLocked || at != up+focusDwellMs {
		t.Fatalf("got (%v, +%dms), want the guard's lock at the dwell", act, at-up)
	}
	if !s.settleLockUsed() {
		t.Fatal("settleLockUsed() = false after the guard's lock")
	}
	if res := seqTick(&s, at+400, up, fgSeqMAME()); res.action != seqLogReopen {
		t.Fatalf("late grab: got %v, want the reopen", res.action)
	}
	assertAt := int64(-1)
	for now := at + 800; now <= up+focusDeadlineMs; now += 400 {
		res := seqTick(&s, now, up, fgSeqMAME())
		if res.action == seqSettleAssert {
			t.Fatalf("at +%dms: the guard answered after its lock - it must not re-arm", now-up)
		}
		if res.action == seqAssert {
			assertAt = now
			break
		}
	}
	if assertAt < 0 {
		t.Fatal("the legacy machinery never asserted against the post-lock grab")
	}
	s.noteAssert(assertAt, true)
	seqTick(&s, assertAt+250, up, fgSeqSDL())
	act, _ = seqDrive(&s, assertAt+650, up, fgSeqSDL(), 10)
	if act != seqLogLocked {
		t.Fatalf("got %v, want FocusLocked again from the legacy machinery", act)
	}
}
