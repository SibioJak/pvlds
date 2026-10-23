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

func TestActivationEditorAtSettleHandsOff(t *testing.T) {
	// The foreground settles ON the editor: no push is ever
	// ordered - that foreground is the exit landing's.
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgDialog)
	act, _ := settleTo(t, &a, up+400, up, fgEditorA)
	if act != actLogEditor {
		t.Fatalf("settled on editor: got %v, want actLogEditor", act)
	}
}

func TestActivationEditorFlickerAborts(t *testing.T) {
	// An editor foreground observed mid-settle aborts the
	// sequence on the spot - even a flicker costs the session
	// its activation rather than risk fighting the exit path.
	var a activator
	up := int64(2000)
	a.tick(up, 1, up, fgMAME)
	a.tick(up+400, 1, up, fgMAME)
	if act := a.tick(up+800, 1, up, fgEditorA); act != actLogEditor {
		t.Fatalf("editor flicker: got %v, want actLogEditor", act)
	}
	if act := a.tick(up+1200, 1, up, fgMAME); act != actNone {
		t.Fatalf("after abort: got %v, want none", act)
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
	for now := up + 400; now < up+activationSettleMs+2000; now += 400 {
		if x := b.tick(now, 2, up, fgMAME); x != actNone {
			got = x
			break
		}
	}
	if got != actPushNow {
		t.Fatalf("fresh session: got %v, want actPushNow", got)
	}
}
