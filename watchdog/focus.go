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
//                    player window never appeared, a foreign
//                    holder with deliberate-use evidence holds
//                    it, or the foreground would not move
//                    after the attempt budget. The reason names
//                    the holder and the branch.
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
// evidence is present (input provenance, below). That veto
// never applies to the game's own window family: a game-pid
// holder that is not the player window is the game's internal
// shuffle, however fresh the desktop input beside it (field
// session 203 - the veto protected a late VPinMAME grab as if
// it were the user's choice, and the table came up dead). The
// editor frame is the sole absolute refusal: its foreground
// is the exit detector's landing, under any circumstances. Each
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
//
// FIX117 - FOCUS DELIVERY (the inner switch): the foreground
// is only half of what VPX's input runs on. SDL sets its
// keyboard-focus flag from window messages and discards
// joystick button-downs while the flag is clear, and a table
// BORN foreground under this launcher (droscoe's sessions
// 18/19: foreground right from the first tick, zero
// assertions, a clean FocusLocked) can hold the foreground
// value forever with its thread's focus never delivered -
// buttons dead, picture and sound perfect, cured permanently
// by one genuine alt-tab. So actuation is owed even when
// assertion is not: while the player window holds the
// foreground but the leaf's focus reader (closer.go's focus
// snapshot) positively reads the player THREAD's focus as
// somewhere else, the sequence orders a focus DELIVERY at
// the delivery moments - the hand-off tick, behind a verified
// assertion of ours, and at the settle moment - spaced and
// budgeted like assertions but spending none of their
// machinery (no verify phase: the reader's next ticks are
// the read-back, in the log). The ladder (which delivery the
// leaf performs - rung 1 full-family SetFocus, rung 2
// SwitchToThisWindow, rung 3 the activation-cycle nudge) and
// the diagnostic message probe ride the contract, set by the
// launcher from its config exactly like the focus switch
// itself; the probe replaces deliveries at the same moments
// under its own flag and is never combined with a rung. If
// the delivery budget ends with the foreground held and the
// focus still undelivered, the sequence logs exactly that
// ("focus not delivered") ONCE per focus episode - the lock
// itself keeps its 1.1.6 foreground criteria in this build:
// the focus-landed requirement ships log-only until a healthy
// GL session's focus reading is known (the reader in this
// build is what reveals it). A failed or absent reader orders
// nothing, ever: every delivery is gated on a positive
// "focus is elsewhere" reading, so the degradation is exact
// 1.1.6 behaviour.
//
// FIX118 - DELIVERY THAT FIRES BLIND: the field verdict on
// 1.1.7 (droscoe, BGFX/Pico 4, his sessions 20-24) convicted
// the GATE, not the techniques: on his rig the thread focus
// reads "the player window itself" from the first tick of
// every session, so the positive reading the deliveries
// above wait for never came - across five sessions no rung
// and no probe ever executed, while his buttons stayed dead
// until a genuine alt-tab. The readings cannot see his
// gate, so delivery must not wait for them: the hand-off
// now carries an unconditional obligation - the configured
// rung (or the probe, under its flag) is ordered exactly
// once per session from the first of the hand-off tick
// itself, the lock branch when the hand-off arrives with
// the lock already due, or a tracking backstop when the
// hand-off tick spent itself on an assertion - regardless
// of the focus reading's VALUE (on the player window,
// elsewhere, the zero window, a failed read). It draws from
// the same per-episode budget, and the triggered deliveries
// above behave exactly as 1.1.7 within what remains. One
// gate survives: the leaf must HAVE a reader (a snapshot
// whose focusRead is not unknown) - a leaf with no reader
// has no delivery to order with, and the degradation there
// stays exact 1.1.6 behaviour, as TestFocusHandoffTick pins.

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
	seqNone                 seqAction = iota
	seqAssert                         // raise the player target now (leaf call), then report via noteAssert
	seqLogLocked                      // FocusLocked reached (also the re-lock after a reopen)
	seqLogUnresolved                  // FocusUnresolved reached; reason() names why
	seqLogReopen                      // a locked sequence lost the player window inside the launch window and reopened
	seqLogNoTarget                    // an assertion was ordered but the caller had no target to raise
	seqDeliverFocus                   // FIX117: deliver focus into the player thread now (leaf call), rung per the contract
	seqProbe                          // FIX117: the diagnostic message probe (leaf call) - never combined with a rung
	seqLogFocusNotDelivered           // FIX117: the delivery budget ended, foreground held, focus undelivered (log-only)
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
	// FIX117 ladder, from the contract (mirrored by the
	// launcher from its config like the focus switch):
	// actuationRung is 1..3 (the caller clamps; an absent or
	// invalid value arrives as 1), actuationProbe replaces
	// deliveries with the diagnostic message probe.
	actuationRung  int
	actuationProbe bool
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

	attempts      int     // assertions ordered in the current episode
	episodeHWND   uintptr // the holder the current episode is working on
	lastAssertMs  int64
	assertAtMs    int64
	verifyAtMs    int64
	verifyStage   int  // 1 = first read-back pending, 2 = verdict read-back pending
	finalAttempt  bool // the in-flight assertion was ordered at the deadline: its failure resolves the sequence
	finalVerified bool // the deadline's assertion verified, but the player hold has still to survive

	beforeDesc       string // the holder's description when the last assertion was ordered (the logs' "was")
	beforeGameFamily bool   // the last assertion answered a game-family holder (the log line says so)
	noTargetLogged   bool
	reasonText       string // the FocusUnresolved reason, once resolved
	lockedClass      string // the player window's class at the lock (the lock log line)

	// FIX117 focus-delivery bookkeeping. A focus EPISODE is
	// one focus window being worked while the player window
	// holds the foreground: it keys on the focus HWND the
	// reader reports, and a change of that HWND - or the
	// focus landing, or the player losing the foreground -
	// starts a fresh episode with a fresh budget.
	deliverAttempts    int     // deliveries/probes ordered in the current focus episode
	deliverEpisodeHWND uintptr // the focus HWND the current episode is working on
	deliverEpisodeSet  bool    // deliverEpisodeHWND is meaningful (a zero focus HWND is a real episode)
	lastDeliverMs      int64   // when the last delivery/probe was ordered (the spacing clock)
	notDeliveredLogged bool    // the budget-end line has been written for this episode
	deliverRungUsed    int     // the ladder rung of the last delivery order (the log line)
	deliverWasProbe    bool    // the last order was the probe, not a rung
	focusDescText      string  // where the focus sat when the last delivery was ordered (the log line)

	// FIX118 unconditional hand-off delivery bookkeeping:
	// handoffDeliveryDone says the session's one blind
	// hand-off order has been placed (by whichever of its
	// three moments came first); deliverUnconditional says
	// the LAST order was that blind one (the log line names
	// it). Session-scoped, not episode-scoped: exactly once.
	handoffDeliveryDone  bool
	deliverUnconditional bool
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

// beforeIsGameFamily reports whether the last assertion
// answered a game-family holder - the assertion log line
// names that plainly ("game window, not the player window -
// asserting") so a field log reads without a translator.
func (s *focusSequence) beforeIsGameFamily() bool { return s.beforeGameFamily }

// playerClass names the player window's class at the lock -
// the lock log line's subject.
func (s *focusSequence) playerClass() string { return s.lockedClass }

// focusOwed reports whether a focus delivery is owed on this
// snapshot: the player window holds the foreground, a target
// stands, and the reader POSITIVELY reads the player thread's
// focus as somewhere else. Every clause is load-bearing: an
// unknown or failed reading owes nothing (the degradation to
// exact 1.1.6 behaviour), and a focus that already sits on
// the player window is the delivered state itself.
func focusOwed(ws windowState) bool {
	return ws.fgIsPlayer && ws.playerHWND != 0 &&
		ws.focusRead == focusReadOK && !ws.focusIsPlayer
}

// unconditionalDue reports whether the FIX118 blind hand-off
// order may be placed on this snapshot: the obligation stands
// (not yet placed this session), a player target stands, the
// per-episode budget has room, and the leaf HAS a reader -
// the one gate the blind order keeps (a reading's VALUE is
// never consulted here; a failed read still orders).
func (s *focusSequence) unconditionalDue(ws windowState) bool {
	return !s.handoffDeliveryDone && ws.playerHWND != 0 &&
		ws.focusRead != focusReadUnknown && s.deliverAttempts < focusMaxAttempts
}

// deliverRung names the ladder rung of the last delivery
// order - the delivery log line's wording.
func (s *focusSequence) deliverRung() int { return s.deliverRungUsed }

// deliverWasUnconditional reports whether the last delivery
// order was the FIX118 blind hand-off order - the delivery
// and probe log lines name it ("unconditional").
func (s *focusSequence) deliverWasUnconditional() bool { return s.deliverUnconditional }

// deliverWasProbeAction reports whether the last delivery
// order was the diagnostic probe rather than a ladder rung.
func (s *focusSequence) deliverWasProbeAction() bool { return s.deliverWasProbe }

// focusDesc names where the player thread's focus sat when
// the last delivery was ordered - the delivery log line's
// "was", in fgwatch.go's plain words.
func (s *focusSequence) focusDesc() string { return s.focusDescText }

// deliveryDue reports whether a delivery may be ordered on
// this tick in the tracking phase: the spacing clock has run,
// the episode budget stands, and a verified assertion of ours
// landed this player hold - the foreground is ours, the inner
// switch is the remaining half, and the dwell has still to
// run. (The other two delivery moments live elsewhere by
// construction: the hand-off tick in its own block, and the
// settle resolution inside the lock branch - a player-held
// foreground's settle IS its lock, and the lock branch works
// an owed focus before declaring.)
func (s *focusSequence) deliveryDue(nowMs int64, ws windowState) bool {
	if !focusOwed(ws) || s.deliverAttempts >= focusMaxAttempts {
		return false
	}
	if s.lastDeliverMs != 0 && nowMs-s.lastDeliverMs < focusAssertSpacingMs {
		return false
	}
	return s.verified
}

// orderDeliver records a focus delivery (or, under the probe
// flag, a probe) against the current focus episode and
// returns the tick's result. notePush rides a real delivery -
// every rung moves the foreground value, and the exit
// detector counts excursions from facts after our last
// foreground touch; the probe posts messages only and
// records none, so the tracking caller passes false for it
// (the hand-off caller records the hand-off tick itself, as
// it always has, whatever the order). unconditional marks
// the FIX118 blind hand-off order: it spends the session's
// one obligation (handoffDeliveryDone) alongside the
// episode budget every order spends.
func (s *focusSequence) orderDeliver(nowMs int64, ws windowState, in focusInputs, notePush bool, unconditional bool) seqResult {
	rung := in.actuationRung
	if rung < 1 || rung > 3 {
		rung = 1
	}
	s.deliverAttempts++
	s.lastDeliverMs = nowMs
	s.deliverRungUsed = rung
	s.deliverWasProbe = in.actuationProbe
	s.deliverUnconditional = unconditional
	if unconditional {
		s.handoffDeliveryDone = true
	}
	s.focusDescText = playerFocusDesc(ws)
	if in.actuationProbe {
		return seqResult{action: seqProbe, notePush: notePush}
	}
	return seqResult{action: seqDeliverFocus, notePush: notePush}
}

// noteDeliver reports the caller's delivery attempt back: the
// leaf either performed it (attempted) or had no target to
// deliver to (the window vanished between the snapshot and
// the call). A no-target attempt is not spent against the
// episode budget - nothing was delivered, so nothing was
// tried - but it DID consume its moment: the spacing clock
// keeps the order's stamp, so a flickering target is retried
// at the spacing, not every tick.
func (s *focusSequence) noteDeliver(attempted bool) {
	if attempted {
		return
	}
	if s.deliverAttempts > 0 {
		s.deliverAttempts--
	}
}

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

// sequenceDeliberateEvidence is the launch sequence's copy
// of the provenance veto - and its aim is narrower than the
// guard's: the veto exists for FOREIGN-process foregrounds
// (the user deliberately going elsewhere), so it never
// applies when the holder is the game's own window family
// (fgIsGame: any window of the game pid; the player window
// itself is handled before this is ever consulted). A
// game-family holder is the game's internal shuffle - the
// sequence asserts over it however fresh the desktop input
// beside it is. Session 203 is the field conviction: a late
// VPinMAME grab plus nearby desktop input resolved
// FocusUnresolved "deliberate use" and left a dead table.
func sequenceDeliberateEvidence(nowMs, fgSinceMs int64, ws windowState) bool {
	if ws.fgIsGame {
		return false
	}
	return deliberateEvidence(nowMs, fgSinceMs, ws)
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
	s.beforeGameFamily = ws.fgIsGame && !ws.fgIsPlayer
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
			s.deliberate = false
			// The deadline's final attempt is NOT reset by a
			// holder change past the deadline: there are no
			// fresh episodes there, and a flapping foreground
			// would otherwise re-arm assertions forever.
			if !s.pastDeadline(nowMs) {
				s.finalAttempt = false
			}
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
	// FIX117 focus-episode bookkeeping: the delivery budget
	// belongs to one focus window being worked while the
	// player window holds the foreground. A change of the
	// reported focus window starts a fresh episode; so does
	// the focus landing on the player window, or the player
	// losing the foreground - the next owed stretch is a new
	// episode with a new budget and a new budget-end line.
	if ws.focusRead == focusReadOK {
		switch {
		case !ws.fgIsPlayer || ws.focusIsPlayer:
			s.deliverAttempts = 0
			s.deliverEpisodeSet = false
			s.notDeliveredLogged = false
		case !s.deliverEpisodeSet || s.deliverEpisodeHWND != ws.playerFocusHWND:
			s.deliverAttempts = 0
			s.deliverEpisodeHWND = ws.playerFocusHWND
			s.deliverEpisodeSet = true
			s.notDeliveredLogged = false
		}
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
			if s.finalAttempt {
				s.finalVerified = true
			}
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
		// FIX117: a player-held foreground's settle resolution
		// IS this lock, so an owed focus is worked HERE, at
		// the resolution moment, before the lock is declared:
		// the budget-end line when the budget is spent, a
		// delivery when the spacing allows, and a deferral
		// while a delivery's spacing is still running (the
		// budget is the point of the resolution - declaring
		// on the next tick would spend one delivery and call
		// it done). The lock keeps its criteria above: these
		// ticks only ever DEFER it - bounded by the delivery
		// budget and spacing, and never past the launch
		// deadline, where the lock declares as 1.1.6's did -
		// and an undelivered focus never denies it (brief
		// §4: the focus-landed requirement ships log-only in
		// this build).
		if !s.pastDeadline(nowMs) {
			// FIX118: the blind hand-off order, when this tick
			// IS the hand-off tick (or follows it) arriving
			// with the lock already due - the resident
			// launcher leaves a long-held table, and this
			// branch runs before the hand-off block below, so
			// the obligation is worked here or the lock would
			// be declared over it.
			if (in.handoff || s.handoffSeen) && s.unconditionalDue(ws) {
				return s.orderDeliver(nowMs, ws, in, !in.actuationProbe, true)
			}
			if focusOwed(ws) {
				if s.deliverAttempts >= focusMaxAttempts {
					if !s.notDeliveredLogged {
						s.notDeliveredLogged = true
						return seqResult{action: seqLogFocusNotDelivered}
					}
				} else if s.lastDeliverMs == 0 || nowMs-s.lastDeliverMs >= focusAssertSpacingMs {
					return s.orderDeliver(nowMs, ws, in, !in.actuationProbe, false)
				} else {
					return seqResult{}
				}
			}
		}
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
			!sequenceDeliberateEvidence(nowMs, s.fgSinceMs, ws) && s.attempts < focusMaxAttempts {
			r := s.orderAssert(nowMs, ws)
			r.notePush = true
			return r
		}
		if ws.fgIsPlayer && s.unconditionalDue(ws) {
			// FIX118: the hand-off delivery fires BLIND. In
			// 1.1.7 this moment waited for a positive "focus
			// is elsewhere" reading (the born-foreground
			// shape, sessions 18/19); droscoe's sessions
			// 20-24 read the focus as already delivered from
			// the first tick while his buttons stayed dead,
			// so nothing ever fired. The readings cannot see
			// his gate: the configured rung (or the probe,
			// under its flag) is ordered now, readings
			// regardless; the reading itself is logged
			// before and after as ever. The tick itself is
			// recorded either way, as it always has been.
			r := s.orderDeliver(nowMs, ws, in, false, true)
			r.notePush = true
			return r
		}
		return res
	}

	// FIX118 backstop: the blind hand-off order, still owed
	// because the hand-off tick spent itself on an assertion
	// (or the foreground reached the player window by another
	// road): the first tracking tick with the player window
	// in front places it, readings regardless.
	if s.handoffSeen && ws.fgIsPlayer && s.unconditionalDue(ws) {
		return s.orderDeliver(nowMs, ws, in, !in.actuationProbe, true)
	}

	// FIX117 focus delivery in tracking: the player window
	// holds the foreground, the reader positively reads its
	// thread's focus elsewhere, and a delivery moment is due
	// (deliveryDue). The budget-end line comes first when the
	// budget is spent - log-only, once per focus episode,
	// never a lock blocker (the header carries the law).
	if focusOwed(ws) {
		if s.deliverAttempts >= focusMaxAttempts && !s.notDeliveredLogged {
			s.notDeliveredLogged = true
			return seqResult{action: seqLogFocusNotDelivered}
		}
		if s.deliveryDue(nowMs, ws) {
			return s.orderDeliver(nowMs, ws, in, !in.actuationProbe, false)
		}
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

	// The deadline's assertion verified but the player hold
	// broke anyway: that is the resolution - the sequence
	// does not keep re-asserting past the deadline.
	if s.finalVerified {
		return s.resolveUnresolved("the player window would not hold the foreground at the deadline")
	}

	// The deadline resolves on whatever holds the foreground.
	if s.pastDeadline(nowMs) {
		switch {
		case ws.playerHWND == 0:
			return s.resolveUnresolved("the player window never appeared")
		case s.deliberate || sequenceDeliberateEvidence(nowMs, s.fgSinceMs, ws):
			return s.resolveUnresolved(fmt.Sprintf("%s holds the foreground and the desktop shows deliberate use", holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)))
		case s.attempts >= focusMaxAttempts && s.episodeHWND == ws.fgHWND:
			return s.resolveUnresolved(fmt.Sprintf("the foreground would not move after %d attempts (held by %s)", s.attempts, holderDesc(ws.fgClass, ws.fgPID, ws.fgProcName, ws.fgTitle)))
		case s.attempts < focusMaxAttempts && !s.finalAttempt:
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
		if sequenceDeliberateEvidence(nowMs, s.fgSinceMs, ws) {
			// Visited, not stolen: watch it, and remember the
			// judgement - the deadline reads the latch, not
			// just that tick's provenance. The deadline
			// names it if it never moves. (Foreign holders
			// only: sequenceDeliberateEvidence never fires
			// on the game's own window family.)
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
