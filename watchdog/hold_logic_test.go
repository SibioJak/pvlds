package main

import "testing"

// HOLD-EXIT: the brief's test census for the hold brain. Samples
// are fed at the real poll cadence (50 ms) over explicit clocks,
// so a "1.5 s hold" here is exactly the stream the watch reads.

const testSession = 7

func liveSample(pressed bool) holdSample {
	return holdSample{sessionID: testSession, phase: "live", alive: true, sighted: true, enabled: true, pressed: pressed}
}

// feed advances the detector over durMs of identical samples at
// the poll cadence, starting at *nowMs, and reports whether any
// poll fired.
func feed(d *holdDetector, nowMs *int64, durMs int64, s holdSample) bool {
	fired := false
	for t := int64(0); t < durMs; t += holdPollIntervalMs {
		*nowMs += holdPollIntervalMs
		if d.observe(*nowMs, s) {
			fired = true
		}
	}
	return fired
}

func armWithRelease(t *testing.T, d *holdDetector, nowMs *int64) {
	t.Helper()
	if feed(d, nowMs, 100, liveSample(false)) {
		t.Fatal("a release sample fired")
	}
	if !d.armed {
		t.Fatal("a witnessed release did not arm the detector")
	}
}

// A tap — a short press after a witnessed release — never fires.
func TestHoldTapNeverFires(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	if feed(d, &now, 300, liveSample(true)) {
		t.Fatal("a 300ms tap fired")
	}
	if feed(d, &now, 100, liveSample(false)) {
		t.Fatal("the tap's release fired")
	}
	if d.firedFor(testSession) {
		t.Fatal("the tap latched a fire")
	}
}

// A 1.4 s hold never fires; the threshold is the threshold.
func TestHoldBelowThresholdNeverFires(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	if feed(d, &now, 1400, liveSample(true)) {
		t.Fatal("a 1.4s hold fired")
	}
}

// A 1.5 s continuous hold fires, exactly once: continued holding,
// and a later re-press, produce no second fire.
func TestHoldFiresOnceAtThreshold(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	if feed(d, &now, 1450, liveSample(true)) {
		t.Fatal("fired before the threshold")
	}
	if !feed(d, &now, 200, liveSample(true)) {
		t.Fatal("a 1.5s continuous hold did not fire")
	}
	if feed(d, &now, 2000, liveSample(true)) {
		t.Fatal("a continued hold fired twice")
	}
	if feed(d, &now, 100, liveSample(false)) {
		t.Fatal("release after the fire fired")
	}
	if feed(d, &now, 2000, liveSample(true)) {
		t.Fatal("a re-press in the same session fired again")
	}
}

// Baseline-release arming: a hold that began before any witnessed
// release — the button was already down when the session started —
// never fires, however long it lasts. (The 2026-10-21 failure's
// cure.) After a real release, a fresh hold fires normally.
func TestHoldBeforeArmingNeverFires(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	if feed(d, &now, 3000, liveSample(true)) {
		t.Fatal("a hold begun before arming fired")
	}
	if d.armed {
		t.Fatal("the detector armed without a witnessed release")
	}
	armWithRelease(t, d, &now)
	if !feed(d, &now, 1600, liveSample(true)) {
		t.Fatal("a fresh hold after the witnessed release did not fire")
	}
}

// A release at 1.2 s resets progress: the next press starts from
// zero, not from 1.2 s.
func TestHoldReleaseResetsProgress(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	if feed(d, &now, 1200, liveSample(true)) {
		t.Fatal("fired at 1.2s")
	}
	feed(d, &now, 100, liveSample(false))
	if feed(d, &now, 1400, liveSample(true)) {
		t.Fatal("progress survived the release (fired at 1.4s of the second press)")
	}
	if !feed(d, &now, 200, liveSample(true)) {
		t.Fatal("the second press did not fire at its own 1.5s")
	}
}

// Phase loss mid-hold resets progress: the session leaving its
// active phase (or the game dying) zeroes the clock even while
// the button stays down.
func TestHoldPhaseLossResetsProgress(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	if feed(d, &now, 1200, liveSample(true)) {
		t.Fatal("fired at 1.2s")
	}
	dead := liveSample(true)
	dead.alive = false
	feed(d, &now, 200, dead)
	if feed(d, &now, 1400, liveSample(true)) {
		t.Fatal("progress survived the phase loss")
	}
	if !feed(d, &now, 200, liveSample(true)) {
		t.Fatal("the post-loss press did not fire at its own 1.5s")
	}
}

// A phase CHANGE inside the session (loading -> live) also
// resets progress.
func TestHoldPhaseChangeResetsProgress(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	loading := liveSample(false)
	loading.phase = "loading"
	feed(d, &now, 100, loading) // witnessed release, in loading
	loading.pressed = true
	if feed(d, &now, 1200, loading) {
		t.Fatal("fired at 1.2s of loading")
	}
	if feed(d, &now, 1400, liveSample(true)) {
		t.Fatal("progress survived the loading -> live change")
	}
	if !feed(d, &now, 200, liveSample(true)) {
		t.Fatal("the live press did not fire at its own 1.5s")
	}
}

// The sighting gate: before the player window is sighted (the
// table is not yet actually playing), holding accrues nothing.
func TestHoldUnsightedAccruesNothing(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	unsighted := liveSample(true)
	unsighted.sighted = false
	if feed(d, &now, 3000, unsighted) {
		t.Fatal("an unsighted hold fired")
	}
	if feed(d, &now, 1400, liveSample(true)) {
		t.Fatal("pre-sighting time counted toward the hold")
	}
	if !feed(d, &now, 200, liveSample(true)) {
		t.Fatal("the sighted hold did not fire at its own 1.5s")
	}
}

// Toggle off never arms: releases and holds alike are inert, and
// turning the toggle back on still needs a fresh witnessed
// release before any hold can accrue.
func TestHoldToggleOffNeverArms(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	off := liveSample(false)
	off.enabled = false
	feed(d, &now, 200, off)
	if d.armed {
		t.Fatal("the detector armed with the toggle off")
	}
	off.pressed = true
	if feed(d, &now, 3000, off) {
		t.Fatal("a hold fired with the toggle off")
	}
	// Toggle returns mid-session, button still down from before:
	// no witnessed release under the enabled watch, no fire.
	if feed(d, &now, 3000, liveSample(true)) {
		t.Fatal("a hold carried over the toggle's return fired without a witnessed release")
	}
	armWithRelease(t, d, &now)
	if !feed(d, &now, 1600, liveSample(true)) {
		t.Fatal("a fresh hold after re-arming did not fire")
	}
}

// A new session resets everything: the fired latch does not leak
// across sessions, and the new session starts disarmed.
func TestHoldNewSessionResets(t *testing.T) {
	d := &holdDetector{}
	now := int64(0)
	armWithRelease(t, d, &now)
	if !feed(d, &now, 1600, liveSample(true)) {
		t.Fatal("the first session's hold did not fire")
	}
	next := liveSample(true)
	next.sessionID = testSession + 1
	if feed(d, &now, 3000, next) {
		t.Fatal("the new session inherited the old session's arming/fire")
	}
	next.pressed = false
	feed(d, &now, 100, next)
	next.pressed = true
	if !feed(d, &now, 1600, next) {
		t.Fatal("the new session's own hold did not fire")
	}
}
