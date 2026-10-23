package main

import "testing"

// The activation sequence (activation.go), exercised on Linux.
// The foreground facts are scripted here in the same vocabulary
// the integration smokes script them (window_linux.go's
// foreground marker identities): class + owning pid, with the
// editor and SDL flags the leaves derive. The pinned shape is
// the field session this duty exists for (watchdog-6, session
// 35, Godzilla): the runtime stamps, the foreground shuffles
// inside the game process, PinMAME's window takes it last - and
// the SDL window, which owns input, never gets it back.

const (
	gamePID = 5264
	vdPID   = 9932
)

func fgOf(class string, pid int) windowState {
	ws := windowState{fgClass: class, fgPID: pid}
	ws.fgIsGame = pid == gamePID
	ws.fgIsEditor = class == editorWindowClass && pid == gamePID
	ws.fgIsSDL = class == sdlWindowClass && pid == gamePID
	return ws
}

var (
	fgMAME    = fgOf("MAME", gamePID)
	fgSDL     = fgOf(sdlWindowClass, gamePID)
	fgEditorA = fgOf(editorWindowClass, gamePID)
	fgDialog  = fgOf("#32770", gamePID)
	fgVD      = fgOf(vdWindowClass, vdPID)
	fgThird   = fgOf("OtherApp", 424242)
	fgNone    = windowState{}
)

// settleTo runs ticks at 400ms spacing from fromMs until the
// machine produces a non-none action (or the tick budget runs
// out), holding the foreground facts constant, and returns the
// action and the tick it fired on.
func settleTo(t *testing.T, a *activator, fromMs, runtimeUpMs int64, ws windowState) (actAction, int64) {
	t.Helper()
	for i := int64(0); i < 60; i++ {
		now := fromMs + i*400
		if act := a.tick(now, 1, runtimeUpMs, ws); act != actNone {
			return act, now
		}
	}
	t.Fatal("no action within the tick budget")
	return actNone, 0
}

func TestActivationSession35Shape(t *testing.T) {
	// Runtime up at 10000. The foreground shuffles dialog ->
	// SDL -> MAME inside the first seconds (identity changes
	// keep the settle clock restarting), then sits on MAME -
	// the session-35 signature. The sequence must resolve only
	// after MAME has held it for the settle constant, push
	// once, verify stuck, and then be DONE: a later wander of
	// the foreground among game-pid windows is not chased.
	var a activator
	up := int64(10000)
	if act := a.tick(up, 1, up, fgDialog); act != actNone {
		t.Fatalf("runtime tick: got %v, want none", act)
	}
	a.tick(up+400, 1, up, fgSDL)
	a.tick(up+800, 1, up, fgMAME)
	act, at := settleTo(t, &a, up+1200, up, fgMAME)
	if act != actPushNow {
		t.Fatalf("settled on MAME: got %v, want actPushNow", act)
	}
	if at-(up+800) < activationSettleMs {
		t.Fatalf("resolved %dms after the last shuffle, want >= the %dms settle", at-(up+800), activationSettleMs)
	}
	if at-up < activationResolveFloorMs {
		t.Fatalf("resolved %dms after runtime-up, before the %dms floor", at-up, activationResolveFloorMs)
	}
	if a.beforeClass() != "MAME" {
		t.Fatalf("beforeClass = %q, want MAME", a.beforeClass())
	}
	if r := a.notePushAttempted(at, true); r != actNone {
		t.Fatalf("push report: got %v, want none", r)
	}
	// Read-back before the verify delay: nothing yet.
	if act := a.tick(at+400, 1, up, fgMAME); act != actNone {
		t.Fatalf("early verify tick: got %v, want none", act)
	}
	// At the verify tick the foreground is the SDL window.
	if act := a.tick(at+activationVerifyMs, 1, up, fgSDL); act != actLogStuck {
		t.Fatalf("verify: got %v, want actLogStuck", act)
	}
	// Done: the foreground wandering back to MAME (and even to
	// the editor) afterwards produces nothing, ever.
	for i := int64(0); i < 10; i++ {
		if act := a.tick(at+2000+i*400, 1, up, fgMAME); act != actNone {
			t.Fatalf("after completion: got %v, want none", act)
		}
	}
}

func TestActivationNotNeededOnSDL(t *testing.T) {
	// The good-Getaway shape: the foreground settles on the
	// SDL window by itself. No push may be ordered.
	var a activator
	up := int64(5000)
	a.tick(up, 1, up, fgDialog)
	act, _ := settleTo(t, &a, up+400, up, fgSDL)
	if act != actLogNotNeeded {
		t.Fatalf("settled on SDL: got %v, want actLogNotNeeded", act)
	}
}

func TestActivationStubbornRetriesOnce(t *testing.T) {
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgMAME)
	act, at := settleTo(t, &a, up+400, up, fgMAME)
	if act != actPushNow {
		t.Fatalf("got %v, want actPushNow", act)
	}
	a.notePushAttempted(at, true)
	// Verify: still MAME - one retry is ordered.
	if act := a.tick(at+activationVerifyMs, 1, up, fgMAME); act != actPushNow {
		t.Fatalf("first verify: got %v, want the retry actPushNow", act)
	}
	a.notePushAttempted(at+activationVerifyMs, true)
	// Verify again: still MAME - honest failure, sequence over.
	if act := a.tick(at+2*activationVerifyMs, 1, up, fgMAME); act != actLogFailed {
		t.Fatalf("second verify: got %v, want actLogFailed", act)
	}
	if act := a.tick(at+3*activationVerifyMs, 1, up, fgMAME); act != actNone {
		t.Fatalf("after failure: got %v, want none", act)
	}
}

func TestActivationNoTarget(t *testing.T) {
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgMAME)
	act, at := settleTo(t, &a, up+400, up, fgMAME)
	if act != actPushNow {
		t.Fatalf("got %v, want actPushNow", act)
	}
	if r := a.notePushAttempted(at, false); r != actLogNoTarget {
		t.Fatalf("no-target report: got %v, want actLogNoTarget", r)
	}
	if act := a.tick(at+400, 1, up, fgMAME); act != actNone {
		t.Fatalf("after no-target: got %v, want none", act)
	}
}

func TestActivationEditorLullResolvesAtDeadline(t *testing.T) {
	// The editor holds the foreground from runtime-up and
	// never lets go: a lull, not a settle. NOTHING may resolve
	// - not at the bare settle constant, not at the floor -
	// until the deadline, where the sequence stands down on
	// the editor under the ordinary resolution rules.
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgEditorA)
	for now := up + 400; now < up+activationDeadlineMs; now += 400 {
		if act := a.tick(now, 1, up, fgEditorA); act != actNone {
			t.Fatalf("editor lull at +%dms: got %v, want none (no resolution before the deadline)", now-up, act)
		}
	}
	if act := a.tick(up+activationDeadlineMs, 1, up, fgEditorA); act != actLogEditor {
		t.Fatalf("deadline on the editor: got %v, want actLogEditor", act)
	}
}

func TestActivationDialogLullResolvesAtDeadline(t *testing.T) {
	// The loading dialog holding the foreground is a lull the
	// same way: no stability accumulates under it, no
	// resolution before the deadline - and at the deadline
	// the sequence resolves on it under the ordinary rules
	// (a game-pid holder is eligible: the push is ordered).
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgDialog)
	for now := up + 400; now < up+activationDeadlineMs; now += 400 {
		if act := a.tick(now, 1, up, fgDialog); act != actNone {
			t.Fatalf("dialog lull at +%dms: got %v, want none (no resolution before the deadline)", now-up, act)
		}
	}
	if act := a.tick(up+activationDeadlineMs, 1, up, fgDialog); act != actPushNow {
		t.Fatalf("deadline on the dialog: got %v, want actPushNow", act)
	}
	if a.beforeClass() != loadDialogClass {
		t.Fatalf("beforeClass = %q, want %q", a.beforeClass(), loadDialogClass)
	}
}

func TestActivationEditorLullDuringSettlePauses(t *testing.T) {
	// An editor foreground during settle-tracking is a lull,
	// NOT an abort: the sequence waits it out, the stability
	// clock does not accumulate under it, and once a real
	// holder follows and the floor has passed, the sequence
	// still fires. (Only an editor grab with a push in
	// flight aborts - see the verify-phase test.)
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgMAME)
	a.tick(up+400, 1, up, fgMAME)
	for now := up + 800; now <= up+2400; now += 400 {
		if act := a.tick(now, 1, up, fgEditorA); act != actNone {
			t.Fatalf("editor lull at +%dms: got %v, want none", now-up, act)
		}
	}
	// MAME again from +2800: stable, but the floor has not
	// passed - nothing may fire before runtime-up + floor.
	for now := up + 2800; now < up+activationResolveFloorMs; now += 400 {
		if act := a.tick(now, 1, up, fgMAME); act != actNone {
			t.Fatalf("pre-floor at +%dms: got %v, want none", now-up, act)
		}
	}
	if act := a.tick(up+activationResolveFloorMs, 1, up, fgMAME); act != actPushNow {
		t.Fatalf("at the floor: got %v, want actPushNow", act)
	}
	if a.beforeClass() != "MAME" {
		t.Fatalf("beforeClass = %q, want MAME", a.beforeClass())
	}
}

func TestActivationSession39Shape(t *testing.T) {
	// The pinned failure (watchdog-7, session 39, Godzilla):
	// the foreground sits stable on the editor PAST the bare
	// settle constant mid-load - the old sequence resolved
	// there and stood down. VPX's real moves land after: an
	// SDL blip, then PinMAME's grab at ~+6s, which holds
	// through dead play. The sequence must NOT stand down
	// during the lull, must not resolve before the floor, and
	// must fire once the floor has passed and PinMAME is the
	// stable holder - then verify stuck, as session 36 did
	// when the same push saved it.
	var a activator
	up := int64(10000)
	if act := a.tick(up, 1, up, fgEditorA); act != actNone {
		t.Fatalf("runtime tick: got %v, want none", act)
	}
	// The lull: editor stable through and past the old
	// settle point (+2800) - no stand-down, ever.
	for now := up + 400; now <= up+2800; now += 400 {
		if act := a.tick(now, 1, up, fgEditorA); act != actNone {
			t.Fatalf("editor lull at +%dms: got %v, want none (no stand-down during the lull)", now-up, act)
		}
	}
	// The SDL blip, then PinMAME's grab at +6000.
	a.tick(up+3200, 1, up, fgSDL)
	for now := up + 6000; now < up+8800; now += 400 {
		if act := a.tick(now, 1, up, fgMAME); act != actNone {
			t.Fatalf("pre-resolution at +%dms: got %v, want none", now-up, act)
		}
	}
	// At +8800 the floor has passed (8000) and MAME has held
	// for the settle constant (2800): fire.
	act := a.tick(up+8800, 1, up, fgMAME)
	if act != actPushNow {
		t.Fatalf("resolution: got %v, want actPushNow", act)
	}
	if a.beforeClass() != "MAME" {
		t.Fatalf("beforeClass = %q, want MAME", a.beforeClass())
	}
	if r := a.notePushAttempted(up+8800, true); r != actNone {
		t.Fatalf("push report: got %v, want none", r)
	}
	if act := a.tick(up+8800+activationVerifyMs, 1, up, fgSDL); act != actLogStuck {
		t.Fatalf("verify: got %v, want actLogStuck", act)
	}
}

func TestActivationSession37Shape(t *testing.T) {
	// The good-neighbor shape (watchdog-7, session 37, Game
	// of Thrones): an editor lull early, then the table's own
	// startup puts the SDL window in front at ~+7s and it
	// stays. The sequence outlasts the lull and, once the
	// floor has passed and SDL is stably the holder, resolves
	// "not needed" - no push is ever ordered.
	var a activator
	up := int64(10000)
	a.tick(up, 1, up, fgEditorA)
	resolved := actNone
	var resolvedAt int64
	for off := int64(400); off <= activationDeadlineMs+800; off += 400 {
		ws := fgEditorA
		if off >= 7000 {
			ws = fgSDL
		}
		if act := a.tick(up+off, 1, up, ws); act != actNone {
			resolved, resolvedAt = act, off
			break
		}
	}
	if resolved != actLogNotNeeded {
		t.Fatalf("got %v, want actLogNotNeeded", resolved)
	}
	if resolvedAt < activationResolveFloorMs {
		t.Fatalf("resolved at +%dms, before the %dms floor", resolvedAt, activationResolveFloorMs)
	}
}

func TestActivationEditorDuringVerifyAborts(t *testing.T) {
	// The landing arrives while a push is being verified: the
	// retry must NOT fire - the editor owns the foreground.
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgMAME)
	act, at := settleTo(t, &a, up+400, up, fgMAME)
	if act != actPushNow {
		t.Fatalf("got %v, want actPushNow", act)
	}
	a.notePushAttempted(at, true)
	if act := a.tick(at+400, 1, up, fgEditorA); act != actLogEditor {
		t.Fatalf("verify-phase editor: got %v, want actLogEditor", act)
	}
}

func TestActivationThirdPartyStandsDown(t *testing.T) {
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgDialog)
	act, _ := settleTo(t, &a, up+400, up, fgThird)
	if act != actLogThirdParty {
		t.Fatalf("settled on a stranger: got %v, want actLogThirdParty", act)
	}
}

func TestActivationEligibleHolders(t *testing.T) {
	// Virtual Desktop's window and no window at all are both
	// eligible: the act is ordered over them.
	for name, ws := range map[string]windowState{"vd": fgVD, "none": fgNone} {
		var a activator
		up := int64(2000)
		a.tick(up, 1, up, fgDialog)
		act, _ := settleTo(t, &a, up+400, up, ws)
		if act != actPushNow {
			t.Fatalf("%s holder: got %v, want actPushNow", name, act)
		}
	}
}

func TestActivationDeadlineResolvesUnsettled(t *testing.T) {
	// The foreground shuffles every tick (never unchanged for
	// the settle constant): nothing may fire before the
	// deadline, and at runtime-up + activationDeadlineMs the
	// sequence resolves on whatever holds it then.
	var a activator
	up := int64(1000)
	a.tick(up, 1, up, fgMAME)
	fired := actNone
	var firedAt int64
	for now := up + 400; now <= up+activationDeadlineMs+400; now += 400 {
		ws := fgMAME
		if (now/400)%2 == 0 {
			ws = fgDialog
		}
		if act := a.tick(now, 1, up, ws); act != actNone {
			fired, firedAt = act, now
			break
		}
	}
	if fired != actPushNow {
		t.Fatalf("deadline: got %v, want actPushNow", fired)
	}
	if firedAt-up < activationDeadlineMs {
		t.Fatalf("resolved %dms after runtime-up, before the %dms deadline", firedAt-up, activationDeadlineMs)
	}
}

func TestActivationIdleBeforeRuntime(t *testing.T) {
	// No runtime stamp, no sequence - whatever the foreground
	// does. And a new sessionID starts a fresh machine.
	var a activator
	for i := int64(0); i < 20; i++ {
		if act := a.tick(i*400, 1, 0, fgMAME); act != actNone {
			t.Fatalf("pre-runtime: got %v, want none", act)
		}
	}
	up := int64(100000)
	var b activator
	b.tick(up, 2, up, fgMAME) // a fresh machine, session 2
	got := actNone
	for now := up + 400; now < up+activationResolveFloorMs+2000; now += 400 {
		if x := b.tick(now, 2, up, fgMAME); x != actNone {
			got = x
			break
		}
	}
	if got != actPushNow {
		t.Fatalf("fresh session: got %v, want actPushNow", got)
	}
}
