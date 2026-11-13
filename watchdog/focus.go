package main

// The launch focus sequence (FIX116): ONE machine that owns
// the foreground from spawn through the hand-off until the
// player window verifiably holds it - or says, in the log,
// exactly why it does not. It replaces the two one-shot
// mechanisms that preceded it (the process-level hand-off push
// and the SDL-only activation; git history and INVESTIGATION
// §1/§3 carry their field record): the push worked at PROCESS
// level and certified success while the wrong window held the
// foreground, the activation knew only the SDL class and so
// could never raise a BGFX build's VPPlayer window at all,
// and each was a single act inside its own clock - a
// foreground move that landed after both had gone home (a
// slow streamer settle, a companion window's late grab) was
// permanent. This machine works at WINDOW level against the
// one resolved player target (target.go), verifies every
// assertion by read-back against the target's handle, and
// ends each session in one of two named, logged states:
//
//   FocusLocked    - the player HWND itself has held the
//                    foreground continuously for a 2 s dwell,
//                    past the resolve floor or behind a
//                    verified assertion of ours;
//   FocusUnresolved <reason> - the launch window closed
//                    without a lock: the editor holds it, the
//                    player window never appeared, a holder
//                    with deliberate-use evidence holds it, or
//                    the foreground would not move after the
//                    attempt budget. The reason names the
//                    holder and the branch.
//
// The machine is fed every tick of an active session (loading
// and live) by main.go, but only while the focus_herding
// switch is on: FIX116 makes the switch the gate for the
// whole focus family, so off means no focus help at all -
// the copy at the desk says exactly that. It is NOT herding:
// loading herding (herd_logic.go) keeps the early spawn
// settle and its yield law; this machine owns the launch's
// END - the guarantee that the hand-off does not finish in a
// silent, unverified state. Assertions it orders are recorded
// with the exit detector (closer.notePush) by the caller,
// exactly as both predecessor pushes were.
//
// Anchoring and patience (carried from the activation era's
// field forensics, watchdog-6/7 sessions 35-39): the sequence
// anchors on the session's runtime stamp; no resolution
// before runtime-up + focusResolveFloorMs however stable
// things look, because every field session's startup shuffle
// ran to ~+7 s and a stable editor mid-load is a LULL that
// fooled the bare settle rule in session 39; stability only
// accumulates under a real holder - the editor frame and the
// loading dialog are load-phase placeholders. FIX116 extends
// the hard deadline from +12 s to +20 s (the BGFX/Pico timing
// was never validated against the old constants) and - new -
// a lock declared before the deadline REOPENS if the player
// window loses the foreground inside the launch window: the
// late grab is chased once more instead of standing.
//
// Assertions: at a settle resolution, at the deadline, or at
// the hand-off tick (below), when the foreground is not the
// player HWND the machine orders the caller to raise the
// target. Eligibility inside the launch window is wide - the
// presumption is spawn shuffle, not user intent: game-process
// windows, known streamer windows, no window, companions and
// strangers alike may be asserted over UNLESS deliberate-use
// evidence is present (input provenance, below). The editor
// frame is the sole absolute refusal: its foreground is the
// exit detector's landing, under any circumstances. Each
// assertion is verified by read-back at +250 ms and +1 s
// against the HWND; an episode allows focusMaxAttempts
// attempts, spaced at least focusAssertSpacingMs apart. An
// editor foreground arriving while an assertion is in flight
// aborts the sequence (the retry must never fight the exit
// detector for its landing).
//
// THE HAND-OFF: the launcher exits completely at the hand-off
// (absence is the design's fix for the OpenXR/focus fights),
// and the first tick the session is live with the launcher
// observed gone is the hand-off moment. The caller passes it
// as the handoff input; on that tick the machine evaluates
// immediately - no settle, no floor - because the foreground
// at that instant belongs to whatever the launcher's exit
// left in front, and a table that comes up behind it comes
// up unfocused. This is the old one-shot push, folded in: to
// the player HWND now, and verified like every assertion.
//
// Deliberate-use evidence (the provenance test the guard in
// guard.go shares): desktop keyboard/mouse input does not
// advance on gamepad input (GetLastInputInfo), so input that
// lands within a second before the current holder took the
// foreground - or any Alt/Win/mouse-button edge around it -
// marks the holder as VISITED, not stolen: the machine does
// not assert over it, watches for a change, and at the
// deadline reports it as the reason. No evidence (a streamer
// surface, a companion's self-raise, silence) asserts.

import "fmt"

// vdWindowClass is Virtual Desktop's window class
// ("CabinetWClass", pid = Virtual Desktop's own process in
// the field inventories): a holder that may be asserted over
// without ceremony - the player is in the headset, not at
// that window deliberately in any way this duty needs to
// respect.
const vdWindowClass = "CabinetWClass"

// loadDialogClass is the Win32 class of VPX's loading dialog
// (the standard "#32770" dialog class, the game pid's own
// window): a load-phase placeholder like the editor frame -
// its stability is a lull, not a settle.
const loadDialogClass = "#32770"

const (
	// How long the foreground must sit unchanged before a
	// settle resolution: the startup shuffle (dialog -> SDL ->
	// PinMAME's own grab ~6 s in on the field rig) has to be
	// OVER, or the act lands on a foreground that is about to
	// move again.
	focusSettleMs = 2800
	// No resolution before runtime-up + this, however stable
	// things look (session 39's editor lull).
	focusResolveFloorMs = 8000
	// The launch window's hard end, runtime-up + this
	// (FIX116: extended from the activation era's 12 s; the
	// deadline is also the reopen window's edge).
	focusDeadlineMs = 20000
	// How long the player HWND must hold the foreground
	// continuously before the lock is declared.
	focusDwellMs = 2000
	// Read-backs after an assertion: an early one (the change
	// applied - or the dwell can start) and the verdict one.
	focusVerifyFirstMs  = 250
	focusVerifySecondMs = 1000
	// Attempts per episode (an episode is one holder being
	// worked on; a holder change starts a fresh episode).
	focusMaxAttempts = 3
	// Minimum spacing between assertions in an episode.
	focusAssertSpacingMs = 1000
	// Desktop input landing within this window before a
	// holder took the foreground counts as deliberate-use
	// evidence against asserting over it.
	focusIntentWindowMs = 1000
)

// seqAction is what one sequence tick decided - and what the
// caller logs or does about it.
type seqAction int

const (
	seqNone          seqAction = iota
	seqAssert                  // raise the player target now (leaf call), then report via noteAssert
	seqLogLocked               // FocusLocked reached (also the re-lock after a reopen)
	seqLogUnresolved           // FocusUnresolved reached; reason() names why
	seqLogReopen               // a locked sequence lost the player window inside the launch window and reopened
	seqLogNoTarget             // an assertion was ordered but the caller had no target to raise
)

// seqResult is one tick's full report: the action, and whether
// the caller must record a focus touch with the exit detector
// this tick (the hand-off tick itself, or an assertion - the
// detector's arming counts excursions only from facts after
// our last foreground touch).
type seqResult struct {
	action   seqAction
	notePush bool
}

// focusInputs is one tick of sequence facts beyond the window
// snapshot: the session's contract state and whether this
// tick is the hand-off tick (session live, supervising
// launcher observed gone - main.go computes it exactly as
// the retired one-shot push's trigger).
type focusInputs struct {
	ws      windowState
	state   string // "loading" or "live"
	handoff bool
}

// focusSequence is the per-session launch focus machine. A
// new sessionID resets everything.
type focusSequence struct {
	sessionID int
	phase     int // 0 tracking, 1 verifying an assertion, 2 locked (watching for reopen), 3 done

	runtimeUp int64 // the anchor: first tick the runtime stamp was observed (0 = not yet)

	fgHWND    uintptr // foreground identity at the last tick (handle + class + pid)
	fgClass   string
	fgPID     int
	fgSinceMs int64 // when the current foreground identity began

	playerSinceMs int64 // when the player HWND took the foreground (0 = it does not hold it now)
	verified      bool  // an assertion of ours verified in the current player hold
	deliberate    bool  // this holder was judged deliberate-use once (latched per holder)

	handoffSeen bool // the hand-off tick has been consumed

	attempts     int     // assertions ordered in the current episode
	episodeHWND  uintptr // the holder the current episode is working on
	lastAssertMs int64
	assertAtMs   int64
	verifyAtMs   int64
	verifyStage  int  // 1 = first read-back pending, 2 = verdict read-back pending
	finalAttempt bool // the in-flight episode was ordered at the deadline: its failure resolves the sequence

	beforeDesc     string // the holder's description when the last assertion was ordered (the logs' "was")
	noTargetLogged bool
	reasonText     string // the FocusUnresolved reason, once resolved
	lockedClass    string // the player window's class at the lock (the lock log line)
}

func (s *focusSequence) reset(sessionID int) {
	*s = focusSequence{sessionID: sessionID}
}

// done reports whether the sequence has reached its terminal
// state (locked past the launch window, or unresolved): the
// live-session guard owns the foreground from then on.
func (s *focusSequence) done() bool { return s.phase == 3 }

// reason names why the sequence resolved without a lock - the
// FocusUnresolved log line's tail.
func (s *focusSequence) reason() string { return s.reasonText }

// before names the holder the last assertion answered - the
// assertion log line's "was".
func (s *focusSequence) before() string { return s.beforeDesc }

// playerClass names the player window's class at the lock -
// the lock log line's subject.
func (s *focusSequence) playerClass() string { return s.lockedClass }

// lullHolder reports whether the foreground holder is a
// load-phase placeholder whose stability must not count
// toward the settle: the editor frame or the loading dialog,
// both the game pid's own windows (session 39).
func focusLullHolder(ws windowState) bool {
	return ws.fgIsEditor || (ws.fgIsGame && ws.fgClass == loadDialogClass)
}

// deliberateEvidence reports whether the current holder's
// tenure carries deliberate-use evidence: an Alt/Win/mouse
// edge on this tick, or desktop input that landed within
// focusIntentWindowMs before the holder took the foreground
// (or since - input while it holds is use of it). The leaf's
// input age is measured at THIS tick; the holder took the
// foreground at fgSinceMs, so the input's landing time is
// nowMs-inputAgeMs and the comparison is against fgSinceMs.
// An unknown age (-1) is no evidence.
func deliberateEvidence(nowMs, fgSinceMs int64, ws windowState) bool {
	if ws.altWinEdge {
		return true
	}
	if ws.inputAgeMs < 0 {
		return false
	}
	landedMs := nowMs - ws.inputAgeMs
	return landedMs >= fgSinceMs-focusIntentWindowMs
}

// anchoredPastFloor reports whether the sequence's clock
// allows a settle resolution: the anchor exists and the
// resolve floor has passed.
func (s *focusSequence) pastFloor(nowMs int64) bool {
	return s.runtimeUp != 0 && nowMs-s.runtimeUp >= focusResolveFloorMs
}

// pastDeadline reports whether the launch window has closed.
func (s *focusSequence) pastDeadline(nowMs int64) bool {
	return s.runtimeUp != 0 && nowMs-s.runtimeUp >= focusDeadlineMs
}

// orderAssert records an assertion against the current holder
// and returns the tick's result.
func (s *focusSequence) orderAssert(nowMs int64, ws windowState) seqResult {
	s.attempts++
	s.episodeHWND = ws.fgHWND
	s.lastAssertMs = nowMs
	s.assertAtMs = nowMs
	s.verifyAtMs = nowMs + focusVerifyFirstMs
	s.verifyStage = 1
	s.beforeDesc = holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)
	s.phase = 1
	return seqResult{action: seqAssert, notePush: true}
}

// resolveUnresolved ends the sequence without a lock, with
// the reason the log line carries.
func (s *focusSequence) resolveUnresolved(reason string) seqResult {
	s.phase = 3
	s.reasonText = reason
	return seqResult{action: seqLogUnresolved}
}

// tick advances the sequence by one watchdog tick. The caller
// feeds it every tick of an active session while the focus
// switch is on, with the session's runtime-stamp tick
// (runtimeUpMs, 0 while the runtime has not stamped) and the
// tick's facts.
func (s *focusSequence) tick(nowMs int64, sessionID int, runtimeUpMs int64, in focusInputs) seqResult {
	ws := in.ws
	if sessionID != s.sessionID {
		s.reset(sessionID)
	}
	if s.phase == 3 {
		return seqResult{}
	}
	if s.runtimeUp == 0 && runtimeUpMs != 0 {
		s.runtimeUp = runtimeUpMs
	}

	// Foreground identity tracking: a change restarts the
	// settle clock, the dwell clock, and - when the HOLDER
	// changed - the assertion episode.
	fgChanged := ws.fgHWND != s.fgHWND || ws.fgClass != s.fgClass || ws.fgPID != s.fgPID
	if fgChanged {
		s.fgHWND, s.fgClass, s.fgPID = ws.fgHWND, ws.fgClass, ws.fgPID
		s.fgSinceMs = nowMs
		if ws.fgHWND != s.episodeHWND {
			s.attempts = 0
			s.noTargetLogged = false
			s.finalAttempt = false
			s.deliberate = false
		}
	}
	if ws.fgIsPlayer {
		if s.playerSinceMs == 0 {
			s.playerSinceMs = nowMs
		}
	} else {
		s.playerSinceMs = 0
		s.verified = false
	}
	if focusLullHolder(ws) && s.phase == 0 {
		// No stability accumulates under a placeholder: the
		// settle clock restarts from this tick, so a settle
		// can only ever complete under the real holder that
		// follows the lull.
		s.fgSinceMs = nowMs
	}

	// Locked: watch for the reopen (or the landing that ends
	// the story) until the launch window closes.
	if s.phase == 2 {
		switch {
		case ws.fgIsPlayer:
			if s.pastDeadline(nowMs) || s.runtimeUp == 0 {
				s.phase = 3
			}
			return seqResult{}
		case ws.fgIsEditor:
			// The exit landing: the closer owns it, and the
			// sequence's work is done either way.
			s.phase = 3
			return seqResult{}
		case s.pastDeadline(nowMs):
			s.phase = 3
			return seqResult{}
		default:
			// A late grab inside the launch window: reopen
			// and work the new holder like any other.
			s.phase = 0
			s.fgSinceMs = nowMs
			return seqResult{action: seqLogReopen}
		}
	}

	// An editor foreground while an assertion is in flight
	// aborts the sequence: that foreground is the exit
	// landing's (or the player's deliberate visit to it), and
	// the retry must never fight the exit detector for it.
	if ws.fgIsEditor && s.phase == 1 {
		return s.resolveUnresolved("the editor holds the foreground")
	}

	// Verifying an assertion.
	if s.phase == 1 {
		if nowMs < s.verifyAtMs {
			return seqResult{}
		}
		if ws.fgIsPlayer {
			// The assertion stuck. Back to tracking: the
			// dwell (and the lock check below) takes it from
			// here.
			s.verified = true
			s.phase = 0
		} else if s.verifyStage == 1 {
			s.verifyAtMs = s.assertAtMs + focusVerifySecondMs
			s.verifyStage = 2
			return seqResult{}
		} else {
			// The verdict read-back failed.
			if s.finalAttempt || s.attempts >= focusMaxAttempts {
				// The attempt budget is spent and the
				// foreground would not move: that IS the
				// resolution (the old activator's honest-
				// failure point), named now, not at the
				// deadline. Attempts spent without a verify
				// ever running (no-target collapses) do not
				// land here - they never entered this phase.
				return s.resolveUnresolved(fmt.Sprintf("the foreground would not move after %d attempts (held by %s)", s.attempts, s.beforeDesc))
			}
			// Retry at once: the verdict read-back lands a
			// full spacing after the failed assertion.
			return s.orderAssert(nowMs, ws)
		}
	}

	// Tracking (phase 0).

	// The lock: the player HWND holding the foreground
	// through the dwell, behind a verified assertion of ours
	// or past the resolve floor (a holder who was never
	// disturbed needs no assertion to be believed).
	if ws.fgIsPlayer && s.playerSinceMs != 0 && nowMs-s.playerSinceMs >= focusDwellMs &&
		(s.verified || s.pastFloor(nowMs)) {
		s.phase = 2
		s.lockedClass = ws.playerClass
		if s.runtimeUp == 0 {
			// Locked on a verified hand-off assertion with no
			// runtime anchor: there is no launch window to
			// reopen inside, so the lock is final here.
			s.phase = 3
		}
		return seqResult{action: seqLogLocked}
	}

	// The hand-off tick: evaluate immediately (see the
	// header). The caller records the push-guard tick
	// (notePush) whether or not an assertion is ordered -
	// the foreground at this moment may be our placement
	// either way.
	if in.handoff && !s.handoffSeen {
		s.handoffSeen = true
		res := seqResult{notePush: true}
		if !ws.fgIsPlayer && !ws.fgIsEditor && ws.playerHWND != 0 &&
			!deliberateEvidence(nowMs, s.fgSinceMs, ws) && s.attempts < focusMaxAttempts {
			r := s.orderAssert(nowMs, ws)
			r.notePush = true
			return r
		}
		return res
	}

	if ws.fgIsPlayer || ws.fgIsEditor {
		// The player holding it is the dwell's business
		// (above); the editor holding it is a lull - or, at
		// the deadline, the resolution.
		if ws.fgIsEditor && s.pastDeadline(nowMs) {
			return s.resolveUnresolved("the editor holds the foreground")
		}
		return seqResult{}
	}

	// The deadline resolves on whatever holds the foreground.
	if s.pastDeadline(nowMs) {
		switch {
		case ws.playerHWND == 0:
			return s.resolveUnresolved("the player window never appeared")
		case s.deliberate || deliberateEvidence(nowMs, s.fgSinceMs, ws):
			return s.resolveUnresolved(fmt.Sprintf("%s holds the foreground and the desktop shows deliberate use", holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)))
		case s.attempts >= focusMaxAttempts && s.episodeHWND == ws.fgHWND:
			return s.resolveUnresolved(fmt.Sprintf("the foreground would not move after %d attempts (held by %s)", s.attempts, holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)))
		case s.attempts < focusMaxAttempts:
			// One last-chance assertion; its failure resolves
			// the sequence in the verify branch above.
			s.finalAttempt = true
			return s.orderAssert(nowMs, ws)
		default:
			return s.resolveUnresolved(fmt.Sprintf("%s holds the foreground at the deadline", holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)))
		}
	}

	// The settle resolution: a real holder, stable through
	// the settle constant, past the resolve floor.
	if s.pastFloor(nowMs) && nowMs-s.fgSinceMs >= focusSettleMs && !focusLullHolder(ws) {
		if deliberateEvidence(nowMs, s.fgSinceMs, ws) {
			// Visited, not stolen: watch it, and remember the
			// judgement - the deadline reads the latch, not
			// just that tick's provenance. The deadline
			// names it if it never moves.
			s.deliberate = true
			return seqResult{}
		}
		if s.attempts >= focusMaxAttempts && s.episodeHWND == ws.fgHWND {
			return seqResult{} // the episode is spent; the deadline names it
		}
		if s.lastAssertMs != 0 && nowMs-s.lastAssertMs < focusAssertSpacingMs {
			return seqResult{}
		}
		if ws.playerHWND == 0 {
			// Nothing to raise yet: the target may still
			// appear (the ranks resolve per snapshot). The
			// deadline names its absence if it never does.
			return seqResult{}
		}
		return s.orderAssert(nowMs, ws)
	}
	return seqResult{}
}

// noteAssert reports the caller's assertion attempt back: the
// leaf either had the target to raise (attempted) or the
// target vanished between the snapshot and the call. On an
// attempt the verify clock is already running (orderAssert
// set it). A no-target attempt counts as a spent attempt
// against the episode - the verify phase collapses back to
// tracking - and is reported once per episode so the caller
// can log it.
func (s *focusSequence) noteAssert(nowMs int64, attempted bool) seqAction {
	if s.phase != 1 {
		return seqNone
	}
	if attempted {
		return seqNone
	}
	s.phase = 0
	if s.noTargetLogged {
		return seqNone
	}
	s.noTargetLogged = true
	return seqLogNoTarget
}
