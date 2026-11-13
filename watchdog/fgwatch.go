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
// The identity is the foreground WINDOW (its handle); class,
// owning pid, process basename and title are the attributes
// the line reports. No cap and
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
// owning pid at the tick it was sampled. FIX116 adds the two
// facts the pre-FIX116 log could not see - the window's TITLE
// and its owning process's image basename - because class +
// pid cannot distinguish two same-class processes or identify
// a companion window (the PINemHi board) at all.
type fgChange struct {
	oldHWND  uintptr
	oldClass string
	oldPID   int
	oldProc  string
	oldTitle string
	newHWND  uintptr
	newClass string
	newPID   int
	newProc  string
	newTitle string
}

// holderDesc renders one foreground holder for a log line: a
// window as "CLASS" (pid N), extended with the process
// basename and the title when the leaf knows them -
// "CLASS" (pid N, proc.exe, "Some Title") - and no window at
// all as none. The focus sequence and the guard speak of
// holders in the same words (focus.go / guard.go).
func holderDesc(class string, pid int, proc, title string) string {
	if pid == 0 && class == "" {
		return "none"
	}
	s := fmt.Sprintf("%q (pid %d", class, pid)
	if proc != "" {
		s += ", " + proc
	}
	if title != "" {
		s += fmt.Sprintf(", %q", title)
	}
	return s + ")"
}

// fgSide renders one side of a transition for the log line.
func fgSide(hwnd uintptr, class string, pid int, proc, title string) string {
	if hwnd == 0 {
		return "none"
	}
	return holderDesc(class, pid, proc, title)
}

func (c fgChange) oldSide() string {
	return fgSide(c.oldHWND, c.oldClass, c.oldPID, c.oldProc, c.oldTitle)
}
func (c fgChange) newSide() string {
	return fgSide(c.newHWND, c.newClass, c.newPID, c.newProc, c.newTitle)
}

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
	proc      string
	title     string
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
		t.proc, t.title = ws.fgProcName, ws.fgTitle
		return fgChange{}, false
	}
	if ws.fgHWND == t.hwnd {
		return fgChange{}, false
	}
	ch := fgChange{
		oldHWND: t.hwnd, oldClass: t.class, oldPID: t.pid,
		oldProc: t.proc, oldTitle: t.title,
		newHWND: ws.fgHWND, newClass: ws.fgClass, newPID: ws.fgPID,
		newProc: ws.fgProcName, newTitle: ws.fgTitle,
	}
	t.hwnd, t.class, t.pid = ws.fgHWND, ws.fgClass, ws.fgPID
	t.proc, t.title = ws.fgProcName, ws.fgTitle
	return ch, true
}

// playerFocusDesc renders the player thread's focus window
// for a log line, in plain words: the window's class and
// handle, "no window" when the thread has none, and the
// player-window suffix when the focus IS the player target -
// the one distinction a field log is read for (FIX117).
func playerFocusDesc(ws windowState) string {
	if ws.playerFocusHWND == 0 {
		return "no window"
	}
	s := fmt.Sprintf("%q window (hwnd %#x)", ws.playerFocusClass, ws.playerFocusHWND)
	if ws.focusIsPlayer {
		s += " - the player window itself"
	}
	return s
}

// playerFocusTracker is the per-session change detector for
// the PLAYER THREAD'S focus (FIX117 instrumentation): fed
// every active-session tick, it reports the focus reading
// ONCE PER CHANGE - the same discipline as the foreground
// tracker above, for the state the foreground tracker cannot
// see (a session whose foreground never moves can still have
// its player thread's focus land, move, or never arrive).
// A failed reader is reported once per session; an unknown
// reading (no target yet, a leaf with no reader) is silent -
// it is the absence of a fact, not a fact. LOGGING ONLY, like
// everything in this file: no decision reads the tracker.
type playerFocusTracker struct {
	sessionID    int
	seen         bool // a positive reading has been recorded
	hwnd         uintptr
	class        string
	isPlayer     bool
	failedLogged bool // the reader-failure line has been written this session
}

// observe folds one tick's focus snapshot in. changed=true
// says the caller logs playerFocusDesc(ws) as the new state;
// failed=true (once per session) says the caller logs the
// reader-unavailable line.
func (t *playerFocusTracker) observe(sessionID int, ws windowState) (changed, failed bool) {
	if sessionID != t.sessionID {
		t.sessionID = sessionID
		t.seen = false
		t.failedLogged = false
	}
	switch ws.focusRead {
	case focusReadFailed:
		// Only a failure WITH a target standing is the
		// reader's failure; with no target there is nothing
		// to read and nothing to report.
		if ws.playerHWND != 0 && !t.failedLogged {
			t.failedLogged = true
			return false, true
		}
		return false, false
	case focusReadOK:
		if t.seen && t.hwnd == ws.playerFocusHWND && t.class == ws.playerFocusClass && t.isPlayer == ws.focusIsPlayer {
			return false, false
		}
		t.seen = true
		t.hwnd, t.class, t.isPlayer = ws.playerFocusHWND, ws.playerFocusClass, ws.focusIsPlayer
		return true, false
	}
	return false, false
}
