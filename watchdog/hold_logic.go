package main

// Hold-to-exit (HOLD-EXIT round): the decision logic — platform-
// free, unit-tested on Linux; the button feed is a platform leaf
// (hold_windows.go reads real XInput, hold_other.go reads the
// smokes' stub feed).
//
// The law (Chris, banked 2026-11-08, go 2026-11-09): while a table
// is playing, holding D-pad right continuously shuts the whole
// works down — VPX closes and PVLDS closes, no return to the
// room. A tap keeps its ordinary meaning (VPX's own Exit Game).
// This is the deliberate, single exception to "no hold gesture
// anywhere"; in the room the same button stays plain BACK and
// this detector is never fed there.
//
// The 2026-10-21 first try (bbbabcd) died in the field: a TAP
// still exited the whole works, and holding gave the same result.
// That build gated on the live session alone and had no
// witnessed-release arming. This build is designed against that
// failure with the machinery field-proven since:
//
//   - BASELINE-RELEASE ARMING: per session the detector starts
//     DISARMED and arms only after a poll observes the button
//     RELEASED while the session is active. A button already
//     held — from launch, from a previous moment's exit tap,
//     from anything — can never start or complete a hold until
//     it has been seen released first. (The room's own cure for
//     phantom BACK exits, carried to the watchdog.)
//   - ACCRUAL GATING: progress accrues only while the session is
//     active, the game process is alive, and the player window
//     has been SIGHTED (the table actually playing — the
//     sighting latch, sighting.go). Any release, any phase
//     change (loading -> live -> anything else), or any loss of
//     those facts resets progress to zero.
//   - ONCE PER SESSION: the fire latches; nothing re-fires.
//   - TOGGLE: the caller feeds enabled=false (the contract's
//     hold_exit_enabled) and the detector never arms.

// holdExitThresholdMs is how long D-pad right must be held,
// continuously, before the whole-works exit fires — the one-line
// retune (the original build's value).
const holdExitThresholdMs = 1500

// holdPollIntervalMs is the button feed's poll cadence in the
// watchdog's hold watch: fine enough that the threshold crossing
// is felt at the threshold, not a main-loop tick later.
const holdPollIntervalMs = 50

// dpadRightMask is the one button this gesture reads — fixed by
// the ruling, no picker: XINPUT_GAMEPAD_DPAD_RIGHT.
const dpadRightMask uint16 = 0x0008

// holdSample is one poll of the world, as the hold watch feeds
// it. Phase is the contract's session_state spelling for the
// standing session ("" when no session is active); a change of
// phase mid-hold resets progress (the brief's phase-change rule).
type holdSample struct {
	sessionID int
	phase     string // "loading" | "live" while a session is active; anything else = inactive
	alive     bool   // the game process is alive
	sighted   bool   // the player window has been sighted for this session
	enabled   bool   // hold_exit_enabled (contract)
	pressed   bool   // D-pad right reads held on this poll
}

// holdDetector is the hold brain. Feed it one sample per poll;
// it reports true exactly once per session: on the poll where a
// continuous, armed hold crosses the threshold.
type holdDetector struct {
	sessionID  int
	armed      bool  // a release has been witnessed this session
	phase      string
	heldSince  int64 // first poll of the current continuous hold; 0 = not holding
	fired      bool  // this session's one fire has gone out
}

// observe folds one poll in. nowMs is a monotonic millisecond
// clock (the caller's). Returns true only on the firing poll.
func (d *holdDetector) observe(nowMs int64, s holdSample) bool {
	if s.sessionID != d.sessionID {
		*d = holdDetector{sessionID: s.sessionID}
	}
	active := (s.phase == "loading" || s.phase == "live") && s.alive
	if !active || !s.enabled {
		// No session, a dead game, or the toggle off: no arming
		// observation, no progress. (Arming and the fired latch
		// survive a phase wobble inside the session only — here
		// the session itself is gone or the feature is off.)
		d.heldSince = 0
		d.phase = s.phase
		if !s.enabled {
			d.armed = false
		}
		return false
	}
	if s.phase != d.phase {
		// A phase change (loading -> live, live -> anything)
		// resets progress: the hold must be continuous inside
		// one phase of the session's life.
		d.heldSince = 0
		d.phase = s.phase
	}
	if !s.pressed {
		// The witnessed release: it arms the detector for this
		// session and resets any progress.
		d.armed = true
		d.heldSince = 0
		return false
	}
	// The button reads held.
	if !d.armed || !s.sighted || d.fired {
		// Unarmed (never seen released — the button was already
		// down when the session began), not yet playing, or
		// already fired: no progress can accrue.
		d.heldSince = 0
		return false
	}
	if d.heldSince == 0 {
		d.heldSince = nowMs
		return false
	}
	if nowMs-d.heldSince >= holdExitThresholdMs {
		d.fired = true
		d.heldSince = 0
		return true
	}
	return false
}

// firedFor reports whether the detector has fired for the given
// session (the main loop's death paths read it: a fired hold
// turns a game death into a full stand-down, never a relaunch).
func (d *holdDetector) firedFor(sessionID int) bool {
	return sessionID == d.sessionID && d.fired
}
