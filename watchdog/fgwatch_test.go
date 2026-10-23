package main

import "testing"

// The foreground-change detector (fgwatch.go), exercised on
// Linux. The detector's whole contract: the first live tick of
// a session is a baseline, never a change; after that, EVERY
// identity change reports, in order, with the class + pid of
// both sides - no cap, no de-dup - because a flapping
// foreground is precisely the evidence the mid-play input-loss
// forensics exist to collect. Identity is the window handle:
// class + pid are attributes, so two windows of the same
// class and owner are still two identities.

func fgH(class string, pid int, hwnd uintptr) windowState {
	ws := fgOf(class, pid)
	ws.fgHWND = hwnd
	return ws
}

var (
	fgSDL1   = fgH(sdlWindowClass, gamePID, 0xA1)
	fgSDL2   = fgH(sdlWindowClass, gamePID, 0xA2) // same class + owner, another window
	fgMAME1  = fgH("MAME", gamePID, 0xB1)
	fgVD1    = fgH(vdWindowClass, vdPID, 0xC1)
	fgNoneWS = fgH("", 0, 0) // no foreground window
)

func TestFGWatchBaselineIsNotAChange(t *testing.T) {
	var tr fgTracker
	if _, changed := tr.observe(7, fgSDL1); changed {
		t.Fatal("first tick of the session reported a change; want baseline only")
	}
	if _, changed := tr.observe(7, fgSDL1); changed {
		t.Fatal("unchanged identity reported a change")
	}
}

func TestFGWatchChangeReportsBothSides(t *testing.T) {
	var tr fgTracker
	tr.observe(7, fgSDL1)
	ch, changed := tr.observe(7, fgMAME1)
	if !changed {
		t.Fatal("SDL -> MAME reported no change")
	}
	if got, want := ch.oldSide(), `"SDL_app" (pid 5264)`; got != want {
		t.Fatalf("oldSide = %s, want %s", got, want)
	}
	if got, want := ch.newSide(), `"MAME" (pid 5264)`; got != want {
		t.Fatalf("newSide = %s, want %s", got, want)
	}
	// The next change chains off the new side, not the baseline.
	ch, changed = tr.observe(7, fgVD1)
	if !changed {
		t.Fatal("MAME -> VD reported no change")
	}
	if got, want := ch.oldSide(), `"MAME" (pid 5264)`; got != want {
		t.Fatalf("oldSide = %s, want %s", got, want)
	}
	if got, want := ch.newSide(), `"CabinetWClass" (pid 9932)`; got != want {
		t.Fatalf("newSide = %s, want %s", got, want)
	}
}

func TestFGWatchIdentityIsTheWindowNotTheClass(t *testing.T) {
	var tr fgTracker
	tr.observe(7, fgSDL1)
	if _, changed := tr.observe(7, fgSDL2); !changed {
		t.Fatal("a different window of the same class + owner reported no change; identity is the window")
	}
}

func TestFGWatchNoneHandling(t *testing.T) {
	var tr fgTracker
	tr.observe(7, fgSDL1)
	ch, changed := tr.observe(7, fgNoneWS)
	if !changed {
		t.Fatal("window -> none reported no change")
	}
	if got := ch.newSide(); got != "none" {
		t.Fatalf("newSide = %q, want none", got)
	}
	if _, changed := tr.observe(7, fgNoneWS); changed {
		t.Fatal("none -> none reported a change")
	}
	ch, changed = tr.observe(7, fgMAME1)
	if !changed {
		t.Fatal("none -> window reported no change")
	}
	if got := ch.oldSide(); got != "none" {
		t.Fatalf("oldSide = %q, want none", got)
	}
}

func TestFGWatchBaselineMayBeNone(t *testing.T) {
	var tr fgTracker
	if _, changed := tr.observe(7, fgNoneWS); changed {
		t.Fatal("a none baseline reported a change")
	}
	ch, changed := tr.observe(7, fgSDL1)
	if !changed || ch.oldSide() != "none" {
		t.Fatalf("none -> SDL: changed=%v oldSide=%q, want a change out of none", changed, ch.oldSide())
	}
}

func TestFGWatchEveryChangeIsReported(t *testing.T) {
	var tr fgTracker
	tr.observe(7, fgSDL1)
	seq := []windowState{fgMAME1, fgSDL1, fgMAME1, fgSDL1, fgMAME1}
	for i, ws := range seq {
		if _, changed := tr.observe(7, ws); !changed {
			t.Fatalf("flap step %d reported no change; every change must be reported", i)
		}
	}
}

func TestFGWatchPerSessionReset(t *testing.T) {
	var tr fgTracker
	tr.observe(7, fgSDL1)
	tr.observe(7, fgMAME1)
	// A new session re-baselines: its first tick is never a
	// change, even when the identity differs from the previous
	// session's last - and even when it matches it.
	if _, changed := tr.observe(8, fgSDL1); changed {
		t.Fatal("first tick of session 8 reported a change")
	}
	if _, changed := tr.observe(8, fgMAME1); !changed {
		t.Fatal("session 8's own first change was not reported")
	}
	if _, changed := tr.observe(9, fgMAME1); changed {
		t.Fatal("first tick of session 9 reported a change")
	}
}
