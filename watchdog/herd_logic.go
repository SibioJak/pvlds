package main

// Focus herding: the decision core (platform-free, unit-tested on
// Linux; the user32 foreground plumbing is the Windows leaf in
// herd_windows.go). The watchdog's window duty (design section 3
// amendment) returns foreground focus to the game window when a
// transient window steals it during the launch settle or mid-game.
//
// The yield bound (M2 corrected fix round, after Chris's
// error-dialog fight): herding serves the player's intent, it never
// overrides it. If the SAME foreign window is back in front after 3
// re-assertion attempts against it, the player is there deliberately
// - working in that window - and herding stands down for the rest of
// the session. Deliberate use wins; the next session starts fresh.

// herdingAllowed is the session-state gate on the whole duty:
// herding runs ONLY while the session is loading (the
// spawn-settle phase it was built for - the launcher resident,
// VPX coming up, transient windows stealing focus from a game
// that is not yet the foreground's owner). Once the session is
// live, the launcher has handed off and the game owns the
// foreground story; on Chris's VR rig the player window is not
// even a desktop window, so the only anchor herding could find
// there is the editor frame - and in the 2026-10-23 sessions it
// actively forced the EDITOR to the foreground mid-play, which
// is also the exact signal the exit detector (closer.go) reads.
// Herding in a live session is therefore not just useless but
// signal poison: it never runs there, no exceptions. The desk's
// focus_herding switch remains the player's outer gate on top of
// this one.
func herdingAllowed(focusHerding bool, sessionState string) bool {
	return focusHerding && sessionState == "loading"
}

// focusPushOutcome is the result of the watchdog's ONE-SHOT
// focus handoff (main.go): at the hand-off moment - the
// session live, the supervising launcher observed gone - the
// watchdog pushes the foreground to the game process exactly
// once, so the table does not come up behind whatever the
// launcher's exit left in front (the field failure: a table up
// with no sound and no controller until the player alt-tabbed
// to it). The push itself is a platform leaf
// (pushFocusToGame); this is only its verdict vocabulary. It
// is NOT herding: herding is a repeated, loading-only duty;
// the handoff is a single deliberate act at a single moment,
// and it also runs in live sessions, where herding never does.
type focusPushOutcome int

const (
	focusPushHanded   focusPushOutcome = iota // the game process holds the foreground now, by our push
	focusPushAlready                          // the game process already held the foreground; nothing to do
	focusPushDeclined                         // no target window, or Windows would not give the foreground up
)

type herdDecision int

const (
	herdNone    herdDecision = iota
	herdAssert               // re-assert foreground to the game window now
	herdYielded              // the yield tripped on this tick (log it once)
)

const (
	// A thief window must hold foreground this long before herding
	// acts: brief alt-tab previews and load flicker are not theft.
	herdGraceMs = 2000
	// Minimum spacing between re-assertion attempts.
	herdMinIntervalMs = 3000
	// Failed re-assertions against one foreign window before the
	// yield: the window "survived" three attempts = deliberate use.
	herdMaxFails = 3
)

type herdBrain struct {
	sessionID int

	lastFg         uintptr // foreground window at the previous tick
	lastFgChangeMs int64   // when lastFg last changed
	lastAssertMs   int64   // when the last re-assertion went out
	hasAsserted    bool    // false until the first assert of the session (the rate limit only spaces real asserts)

	foreign        uintptr // the foreign window being counted against
	foreignFails   int     // times it was back in front after an assert
	assertedTarget uintptr // foreign window the last assert answered; 0 once consumed

	yielded bool
}

// reset starts a fresh session: counters and the yield clear.
func (b *herdBrain) reset(sessionID int) {
	*b = herdBrain{sessionID: sessionID}
}

// decide advances herding by one tick. fg is the current foreground
// window (0 = unknown / no game window to protect, in which case the
// brain just watches); fgIsGame says fg is the game window.
func (b *herdBrain) decide(nowMs int64, fg uintptr, fgIsGame bool) herdDecision {
	if fg == 0 {
		return herdNone
	}
	if fg != b.lastFg {
		b.lastFg = fg
		b.lastFgChangeMs = nowMs
		if fgIsGame {
			// The game is in front: nothing to herd. The asserted
			// target and the foreign tracking deliberately SURVIVE
			// this observation - the fight signature is the same
			// foreign window coming back AFTER the game held
			// foreground, and that can only be counted if the
			// memory crosses this branch.
			return herdNone
		}
		if b.assertedTarget != 0 && fg == b.assertedTarget {
			// We asserted against this window and it is in front
			// again: the re-assertion failed to stick.
			b.assertedTarget = 0
			b.foreignFails++
			if b.foreignFails >= herdMaxFails && !b.yielded {
				b.yielded = true
				return herdYielded
			}
			return herdNone
		}
		if fg != b.foreign {
			// A different foreign window: start counting against
			// it. Deliberateness is judged per window.
			b.foreign = fg
			b.foreignFails = 0
			b.assertedTarget = 0
		}
		return herdNone
	}
	// Foreground unchanged this tick.
	if fgIsGame || b.yielded {
		return herdNone
	}
	if nowMs-b.lastFgChangeMs < herdGraceMs {
		return herdNone
	}
	if b.hasAsserted && nowMs-b.lastAssertMs < herdMinIntervalMs {
		return herdNone
	}
	b.lastAssertMs = nowMs
	b.hasAsserted = true
	b.assertedTarget = fg
	return herdAssert
}
