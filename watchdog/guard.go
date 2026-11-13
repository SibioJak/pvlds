package main

import "fmt"

// The live-session focus guard (FIX116): after the launch
// focus sequence (focus.go) has ended - locked or unresolved -
// the guard owns the foreground for the rest of a live
// session, under the same focus_herding switch. It exists
// for one field shape (Chris, 2026-11-12): a PINemHi
// LeaderBoard window popped AFTER his table had loaded and
// took the foreground; the pre-FIX116 watchdog had no
// live-session recovery at all, so nothing opposed it and he
// alt-tabbed himself. The guard takes the foreground back -
// but only from holders it can NAME, and never against
// evidence that the user put the window there.
//
// Why the narrow licence (the design's centre): herding once
// ran live and forced the VPX EDITOR frame to the foreground
// mid-play - which is also the exit detector's close signal.
// A guard that fights for the foreground against everything
// becomes a focus bully and poisons that signal. So:
//
//   - the player HWND holding the foreground is healthy;
//     per-hold tracking resets (the attempt CAP below does
//     not - it is per session, or a repeat popper would
//     never trip it);
//   - the session pid's editor frame is NEVER acted on: that
//     foreground is the exit detector's landing, and the
//     guard also pauses wholesale while the closer's ladder
//     (or the hold-exit ladder) is in flight;
//   - a game-family window (any other window of the game
//     pid - PinMAME's late grab is the session-35 shape
//     arriving late) is focus drift inside the game's own
//     family: reclaim after the grace;
//   - a KNOWN BYSTANDER (bystanders.go: matched on at least
//     two identity signals) that raised itself: reclaim
//     after the grace, subject to the veto and the cap;
//   - anything else - an unknown process, the shell, a
//     notification - is LOGGED, once per window, and left
//     alone. v1's conservative line, deliberately.
//
// Steal vs deliberate alt-tab is decided by input provenance
// plus behaviour, with every ambiguity resolved toward the
// user (the classifier the launch sequence shares, in
// focus.go): desktop keyboard/mouse input does not advance
// on gamepad input, so -
//
//   STEAL signature: no desktop input within a second before
//   the holder took the foreground, no Alt/Win/mouse edge
//   around the change, and no desktop input while it holds
//   through the grace. A window that raises itself while the
//   player's hands are on a controller is interrupting, not
//   being visited.
//
//   DELIBERATE signature - any one vetoes the reclaim and
//   latches "the user owns the foreground" for that window
//   until the player window regains it or the session ends:
//   an Alt/Win/mouse edge at the change; desktop input
//   within the window before it; desktop input arriving
//   while the window holds (the input age DROPPING between
//   ticks - the last-input clock only advances on input);
//   or the window returning after a reclaim accompanied by
//   fresh input (the same age test on its new tenure). A
//   deliberate visit to the board to READ a score is
//   therefore never fought: the first input in it ends the
//   matter.
//
// The attempt cap is the final backstop: at most
// guardMaxReclaims silent reclamations per window per
// session. A bystander that silently re-raises past the cap
// wins the session, and the guard logs its yield. The
// reclaim act itself only ever raises the player HWND - it
// never closes, minimises, or moves the bystander - and the
// caller records it with the exit detector (notePush), like
// every watchdog assertion before it.

const (
	// How long a reclaimable holder must hold the foreground
	// before the guard acts: a transient pass-through is not
	// a steal.
	guardGraceMs = 1000
	// Minimum spacing between reclamations against one
	// holder whose tenure continues (a refused raise).
	guardMinIntervalMs = 1000
	// Silent reclamations per window per session before the
	// guard yields to it for the session.
	guardMaxReclaims = 3
	// Desktop input landing within this window before a
	// holder took the foreground counts as deliberate-use
	// evidence (shared with the launch sequence's test).
	guardIntentWindowMs = focusIntentWindowMs
	// A drop in the desktop-input age larger than this
	// between ticks means new input arrived (ages otherwise
	// grow by roughly the tick length; clock granularity is
	// not evidence).
	guardInputDropMs = 100
)

type guardAction int

const (
	guardNone   guardAction = iota
	guardAssert             // raise the player target now; the log detail rides in the result
	guardLog                // log the detail line (a classification, a veto, a yield)
)

// guardResult is one guard tick's report: the action and,
// for guardAssert and guardLog, the log line's tail (main.go
// prefixes it with the session stamp).
type guardResult struct {
	action guardAction
	detail string
}

// focusGuard is the per-session guard state. A new sessionID
// resets everything, caps and latches included.
type focusGuard struct {
	sessionID int

	holderHWND   uintptr // the foreign holder currently being tracked (0 = none)
	holderSince  int64   // when its current tenure began
	prevAgeMs    int64   // the desktop-input age at the previous tick of this tenure
	lastAssertMs int64   // the last reclamation against this tenure's holder

	attempts map[uintptr]int  // reclamations per window this session (the cap's count)
	yielded  map[uintptr]bool // windows the cap has yielded to (logged once)
	vetoed   map[uintptr]bool // windows latched as deliberate use (logged once)
	classed  map[uintptr]bool // unknown windows whose log-only line has been written
}

func (g *focusGuard) reset(sessionID int) {
	*g = focusGuard{
		sessionID: sessionID,
		attempts:  map[uintptr]int{},
		yielded:   map[uintptr]bool{},
		vetoed:    map[uintptr]bool{},
		classed:   map[uintptr]bool{},
	}
}

// tick advances the guard by one watchdog tick. The caller
// feeds it live sessions only, after the launch sequence has
// ended, while the focus switch is on. closerBusy pauses the
// guard wholesale (the exit ladder owns the foreground story
// while it is in flight).
func (g *focusGuard) tick(nowMs int64, sessionID int, ws windowState, closerBusy bool) guardResult {
	if sessionID != g.sessionID {
		g.reset(sessionID)
	}
	// Healthy: the player window holds the foreground. Per-
	// hold tracking and the deliberate-use latches clear; the
	// per-session attempt counts deliberately do NOT (see the
	// header).
	if ws.fgIsPlayer {
		g.holderHWND = 0
		g.vetoed = map[uintptr]bool{}
		return guardResult{}
	}
	// No window at all, or the editor: nothing to track, and
	// (the editor) never anything to do.
	if ws.fgHWND == 0 || ws.fgIsEditor {
		g.holderHWND = 0
		return guardResult{}
	}
	// The exit ladder is in flight: pause. A tracked holder's
	// grace restarts, so the ladder's own foreground story is
	// never mistaken for a steal's tenure.
	if closerBusy {
		if g.holderHWND == ws.fgHWND {
			g.holderSince = nowMs
		}
		return guardResult{}
	}

	hwnd := ws.fgHWND
	desc := holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)

	// Classify the holder.
	family := ws.fgIsGame // any other window of the game pid (player and editor are handled above)
	source := ""
	if family {
		source = "the game's own window family"
	} else if name, ok := matchBystander(holderFacts{proc: ws.fgProcName, class: ws.fgClass, title: ws.fgTitle}); ok {
		source = "known companion window (" + name + ")"
	} else {
		// Unknown: log once per window, and leave it alone.
		if !g.classed[hwnd] {
			g.classed[hwnd] = true
			return guardResult{action: guardLog, detail: fmt.Sprintf("%s is not a known companion window; logging only", desc)}
		}
		return guardResult{}
	}

	// A window latched as deliberate use is left alone for
	// the rest of its claim on the foreground.
	if g.vetoed[hwnd] {
		return guardResult{}
	}

	// Tenure bookkeeping: a new holder starts a fresh grace
	// and a fresh provenance read.
	if g.holderHWND != hwnd {
		g.holderHWND = hwnd
		g.holderSince = nowMs
		g.prevAgeMs = ws.inputAgeMs
		g.lastAssertMs = 0
		// No provenance at all is an ambiguity, and every
		// ambiguity resolves toward the user: a holder whose
		// tenure cannot be judged is never reclaimed over.
		// (On Windows the age is always readable; this is the
		// leaf-failure and bench-without-a-script case.)
		if ws.inputAgeMs < 0 {
			g.vetoed[hwnd] = true
			return guardResult{action: guardLog, detail: fmt.Sprintf("%s cannot be judged (no desktop-input provenance); leaving the foreground with it", desc)}
		}
		// Deliberate at the door: an edge on this tick, or
		// desktop input within the window before the change
		// (the change is at most a tick old at first sight,
		// so the age reads the landing directly).
		if ws.altWinEdge || ws.inputAgeMs <= guardIntentWindowMs {
			g.vetoed[hwnd] = true
			return guardResult{action: guardLog, detail: fmt.Sprintf("%s looks like deliberate use (desktop input); leaving the foreground with it", desc)}
		}
		return guardResult{}
	}

	// A continuing tenure: input arriving while the window
	// holds is use of it - the age dropping between ticks is
	// the arrival (the last-input clock only advances on
	// input). An edge mid-tenure is the same story.
	if ws.altWinEdge || (ws.inputAgeMs >= 0 && g.prevAgeMs >= 0 && ws.inputAgeMs < g.prevAgeMs-guardInputDropMs) {
		g.vetoed[hwnd] = true
		return guardResult{action: guardLog, detail: fmt.Sprintf("%s looks like deliberate use (desktop input); leaving the foreground with it", desc)}
	}
	if ws.inputAgeMs >= 0 {
		g.prevAgeMs = ws.inputAgeMs
	}

	// The cap: this window has been silently reclaimed the
	// budget of times; if it is back again, it wins.
	if g.attempts[hwnd] >= guardMaxReclaims {
		if !g.yielded[hwnd] {
			g.yielded[hwnd] = true
			return guardResult{action: guardLog, detail: fmt.Sprintf("%s has retaken the foreground %d times; yielding for this session", desc, guardMaxReclaims)}
		}
		return guardResult{}
	}

	// The reclaim: grace served, no veto, budget left.
	if nowMs-g.holderSince >= guardGraceMs && (g.lastAssertMs == 0 || nowMs-g.lastAssertMs >= guardMinIntervalMs) {
		g.attempts[hwnd]++
		g.lastAssertMs = nowMs
		return guardResult{action: guardAssert, detail: fmt.Sprintf("reclaimed the foreground from %s (%s)", desc, source)}
	}
	return guardResult{}
}
