package main

import (
	"strings"
	"testing"
)

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

func TestFGWatchProcAndTitleRender(t *testing.T) {
	// FIX116: a change side that knows its process and title
	// renders them; a side that doesn't stays byte-identical
	// to the pre-FIX116 line.
	var tr fgTracker
	tr.observe(7, fgSDL1)
	board := fgH("PinemhiLeaderboard", 5150, 0xBD)
	board.fgProcName = "PINemHi LeaderBoard.exe"
	board.fgTitle = "PINemHi LeaderBoard"
	ch, changed := tr.observe(7, board)
	if !changed {
		t.Fatal("no change reported for SDL -> board")
	}
	if got, want := ch.oldSide(), `"SDL_app" (pid 5264)`; got != want {
		t.Fatalf("oldSide() = %s, want %s", got, want)
	}
	if got, want := ch.newSide(), `"PinemhiLeaderboard" (pid 5150, PINemHi LeaderBoard.exe, "PINemHi LeaderBoard")`; got != want {
		t.Fatalf("newSide() = %s, want %s", got, want)
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

// ----------------------------------------------------------------
// FIX117: the player-thread focus tracker (playerFocusTracker)
// and its line rendering (playerFocusDesc).

func focusWS(read int, focusHWND uintptr, focusClass string, isPlayer bool) windowState {
	ws := windowState{inputAgeMs: -1}
	ws.playerHWND = hwFVP
	ws.focusRead = read
	ws.playerFocusHWND = focusHWND
	ws.playerFocusClass = focusClass
	ws.focusIsPlayer = isPlayer
	return ws
}

func TestPlayerFocusTrackerChangesOncePerChange(t *testing.T) {
	var tr playerFocusTracker
	// First positive reading is a change (the "before"
	// picture); the same reading again is not.
	if changed, failed := tr.observe(1, focusWS(focusReadOK, hwFMAME, "MAME", false)); !changed || failed {
		t.Fatalf("first reading: got (changed=%v, failed=%v), want the change reported", changed, failed)
	}
	if changed, _ := tr.observe(1, focusWS(focusReadOK, hwFMAME, "MAME", false)); changed {
		t.Fatal("an unchanged reading was reported twice")
	}
	// The focus lands on the player window: a change.
	if changed, _ := tr.observe(1, focusWS(focusReadOK, hwFVP, playerWindowClass, true)); !changed {
		t.Fatal("the focus landing on the player window was not reported")
	}
	// The zero window is a real reading and a real change.
	if changed, _ := tr.observe(1, focusWS(focusReadOK, 0, "", false)); !changed {
		t.Fatal("the focus dropping to no window was not reported")
	}
}

func TestPlayerFocusTrackerFailedReaderOncePerSession(t *testing.T) {
	var tr playerFocusTracker
	if _, failed := tr.observe(1, focusWS(focusReadFailed, 0, "", false)); !failed {
		t.Fatal("the reader failure was not reported")
	}
	if _, failed := tr.observe(1, focusWS(focusReadFailed, 0, "", false)); failed {
		t.Fatal("the reader failure was reported twice in one session")
	}
	// A new session reports it again - and a failure with no
	// target standing is not the reader's failure at all.
	if _, failed := tr.observe(2, focusWS(focusReadFailed, 0, "", false)); !failed {
		t.Fatal("session 2's reader failure was not reported")
	}
	noTarget := focusWS(focusReadFailed, 0, "", false)
	noTarget.playerHWND = 0
	if _, failed := tr.observe(3, noTarget); failed {
		t.Fatal("a failure with no player target was blamed on the reader")
	}
	// Unknown readings are silent throughout.
	if changed, failed := tr.observe(3, focusWS(focusReadUnknown, 0, "", false)); changed || failed {
		t.Fatal("an unknown reading produced a report")
	}
}

// ----------------------------------------------------------------
// FIX118: the player-thread ACTIVE-window tracker
// (playerActiveTracker) and its line rendering
// (playerActiveDesc) - the focus pair's twins.

func activeWS(read int, activeHWND uintptr, activeClass string, isPlayer bool) windowState {
	ws := focusWS(read, 0, "", false)
	ws.playerActiveHWND = activeHWND
	ws.playerActiveClass = activeClass
	ws.activeIsPlayer = isPlayer
	return ws
}

func TestPlayerActiveTrackerChangesOncePerChange(t *testing.T) {
	var tr playerActiveTracker
	// First positive reading is a change; the same reading
	// again is not.
	if changed := tr.observe(1, activeWS(focusReadOK, hwFMAME, "MAME", false)); !changed {
		t.Fatal("first reading: the change was not reported")
	}
	if changed := tr.observe(1, activeWS(focusReadOK, hwFMAME, "MAME", false)); changed {
		t.Fatal("an unchanged reading was reported twice")
	}
	// The active window lands on the player window: a change.
	if changed := tr.observe(1, activeWS(focusReadOK, hwFVP, playerWindowClass, true)); !changed {
		t.Fatal("the active window landing on the player window was not reported")
	}
	// A failed or unknown reading is silent here - the one
	// failure line belongs to the focus tracker.
	if changed := tr.observe(1, activeWS(focusReadFailed, 0, "", false)); changed {
		t.Fatal("a failed reading produced an active-window report")
	}
	if changed := tr.observe(1, activeWS(focusReadUnknown, 0, "", false)); changed {
		t.Fatal("an unknown reading produced an active-window report")
	}
	// A new session reports its first reading again.
	if changed := tr.observe(2, activeWS(focusReadOK, hwFVP, playerWindowClass, true)); !changed {
		t.Fatal("session 2's first reading was not reported")
	}
}

func TestPlayerActiveDescWording(t *testing.T) {
	if got := playerActiveDesc(activeWS(focusReadOK, 0, "", false)); got != "no window" {
		t.Fatalf("zero active window: got %q, want %q", got, "no window")
	}
	got := playerActiveDesc(activeWS(focusReadOK, hwFMAME, "MAME", false))
	if !strings.Contains(got, "\"MAME\"") {
		t.Fatalf("elsewhere active window: got %q, want the class named", got)
	}
	got = playerActiveDesc(activeWS(focusReadOK, hwFVP, playerWindowClass, true))
	if !strings.Contains(got, "the player window itself") {
		t.Fatalf("player active window: got %q, want the player-window suffix", got)
	}
}

func TestPlayerFocusDescWording(t *testing.T) {
	if got := playerFocusDesc(focusWS(focusReadOK, 0, "", false)); got != "no window" {
		t.Fatalf("zero focus window: got %q, want %q", got, "no window")
	}
	got := playerFocusDesc(focusWS(focusReadOK, hwFMAME, "MAME", false))
	if !strings.Contains(got, "\"MAME\"") {
		t.Fatalf("elsewhere focus: got %q, want the class named", got)
	}
	got = playerFocusDesc(focusWS(focusReadOK, hwFVP, playerWindowClass, true))
	if !strings.Contains(got, "the player window itself") {
		t.Fatalf("delivered focus: got %q, want the player-window suffix", got)
	}
}
