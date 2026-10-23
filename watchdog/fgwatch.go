package main

import "fmt"

// Foreground-change forensics: in a live session, EVERY change
// of foreground identity is logged (platform-free detector,
// unit-tested on Linux; the foreground facts are the platform
// leaves' - herd_windows.go / window_linux.go). LOGGING ONLY:
// no decision reads this, and no behavior changes because of it.
//
// Why this exists (field report, Chris's rig, 2026-10-23):
// intermittent mid-play input loss - gamepad AND keyboard dead
// in bursts, flippers occasionally stuck up - while the table
// rendered fine, occurring both before and after a reboot. The
// watchdog's audit of the sessions in question (40-42) ACQUITTED
// PVLDS of acting mid-play (it takes no action after ~12s into
// a session), but the log itself could not see a mid-play
// foreground flicker if one happened: the window inventory
// lines (herd_windows.go's logWindowInventory) print only when
// the game process's window SET changes composition, and the
// set is static mid-play. The exit detector samples the
// foreground every tick but logs only its own close decisions.
// So the one fact that could name a focus thief - the
// foreground's identity, tick by tick - was read and thrown
// away. This tracker is fed exactly that already-sampled fact
// (main.go, live sessions only) and writes one line per change.
//
// The identity is the foreground WINDOW (its handle); class +
// owning pid are the attributes the line reports. No cap and
// no de-dup beyond per-tick identity: a flapping foreground is
// precisely the suspected fault, and summarizing it away would
// destroy the evidence this exists to collect. Changes the
// watchdog itself causes (the activation's push, activation.go)
// appear here too - truthful, and adjacent to the activation's
// own lines. During LOADING the tracker is not fed: the load's
// foreground shuffle is already covered by the inventory lines,
// and the hand-off's own story is told by the focus-push and
// activation lines.

// fgChange is one observed foreground transition, old side and
// new side, each as the window's identity plus its class and
// owning pid at the tick it was sampled.
type fgChange struct {
	oldHWND  uintptr
	oldClass string
	oldPID   int
	newHWND  uintptr
	newClass string
	newPID   int
}

// fgSide renders one side of a transition for the log line: a
// window as "CLASS" (pid N), and no window at all as none.
func fgSide(hwnd uintptr, class string, pid int) string {
	if hwnd == 0 {
		return "none"
	}
	return fmt.Sprintf("%q (pid %d)", class, pid)
}

func (c fgChange) oldSide() string { return fgSide(c.oldHWND, c.oldClass, c.oldPID) }
func (c fgChange) newSide() string { return fgSide(c.newHWND, c.newClass, c.newPID) }

// fgTracker is the per-session foreground-change detector. The
// first live tick of a session only sets the baseline (the
// foreground the hand-off left is a starting condition, not a
// change); every later tick whose foreground identity differs
// from the previous tick's reports a change. A new sessionID
// resets the baseline, exactly as the closer and the activator
// reset.
type fgTracker struct {
	sessionID int
	seen      bool // the baseline has been recorded for this session
	hwnd      uintptr
	class     string
	pid       int
}

// observe folds one live tick's foreground facts in and
// reports the transition when the foreground identity differs
// from the previous tick's.
func (t *fgTracker) observe(sessionID int, ws windowState) (fgChange, bool) {
	if sessionID != t.sessionID {
		t.sessionID = sessionID
		t.seen = false
	}
	if !t.seen {
		t.seen = true
		t.hwnd, t.class, t.pid = ws.fgHWND, ws.fgClass, ws.fgPID
		return fgChange{}, false
	}
	if ws.fgHWND == t.hwnd {
		return fgChange{}, false
	}
	ch := fgChange{
		oldHWND: t.hwnd, oldClass: t.class, oldPID: t.pid,
		newHWND: ws.fgHWND, newClass: ws.fgClass, newPID: ws.fgPID,
	}
	t.hwnd, t.class, t.pid = ws.fgHWND, ws.fgClass, ws.fgPID
	return ch, true
}
