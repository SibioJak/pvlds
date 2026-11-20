package main

import (
	"testing"
	"time"
)

// FIX149 pins for the B2S sighting tracker's continuous-
// presence clock - the fact the hand-off gate reads through
// the contract's b2s_present_since_unix stamp. The law:
// presence is CONTINUOUS or it is nothing - any absence
// (and any session change) restarts the clock, and the
// stability crossing is reported once per presence run.

func TestB2SightingPresentSince(t *testing.T) {
	var tr b2sSighting
	t0 := time.Unix(1_700_000_000, 0)

	// Nothing observed yet: no stamp.
	if got := tr.presentSinceUnix(); got != 0 {
		t.Fatalf("unobserved tracker stamped %d, want 0", got)
	}
	// First observation of the session speaks (the log line)
	// and, being absent, stamps nothing.
	if !tr.observe(7, false, t0) {
		t.Fatal("the first observation of a session must report changed")
	}
	if got := tr.presentSinceUnix(); got != 0 {
		t.Fatalf("absent observation stamped %d, want 0", got)
	}
	// A repeat of the same fact is silent.
	if tr.observe(7, false, t0.Add(time.Second)) {
		t.Fatal("an unchanged fact must not report changed")
	}
	// Presence begins: the stamp is the moment it began.
	t1 := t0.Add(3 * time.Second)
	if !tr.observe(7, true, t1) {
		t.Fatal("absent -> present must report changed")
	}
	if got := tr.presentSinceUnix(); got != t1.Unix() {
		t.Fatalf("presence stamped %d, want %d", got, t1.Unix())
	}
	// Continued presence does not move the stamp.
	if tr.observe(7, true, t1.Add(2*time.Second)) {
		t.Fatal("continued presence must not report changed")
	}
	if got := tr.presentSinceUnix(); got != t1.Unix() {
		t.Fatalf("continued presence moved the stamp to %d, want %d", got, t1.Unix())
	}
	// A flicker out and back restarts the clock at the
	// return, not the first arrival.
	t2 := t1.Add(4 * time.Second)
	if !tr.observe(7, false, t2) {
		t.Fatal("present -> absent must report changed")
	}
	if got := tr.presentSinceUnix(); got != 0 {
		t.Fatalf("absent flicker kept the stamp %d, want 0", got)
	}
	t3 := t2.Add(time.Second)
	if !tr.observe(7, true, t3) {
		t.Fatal("absent -> present (return) must report changed")
	}
	if got := tr.presentSinceUnix(); got != t3.Unix() {
		t.Fatalf("returned presence stamped %d, want the return %d", got, t3.Unix())
	}
	// A new session restarts everything, even mid-presence.
	if !tr.observe(8, true, t3.Add(time.Second)) {
		t.Fatal("a session change must report changed")
	}
	if got := tr.presentSinceUnix(); got != t3.Add(time.Second).Unix() {
		t.Fatalf("new session stamped %d, want its own first presence %d", got, t3.Add(time.Second).Unix())
	}
}

func TestB2SightingNoteStable(t *testing.T) {
	var tr b2sSighting
	t0 := time.Unix(1_700_000_000, 0)
	threshold := 5 * time.Second

	// Absent: never stable.
	tr.observe(7, false, t0)
	if tr.noteStable(t0.Add(time.Hour), threshold) {
		t.Fatal("an absent server cannot be stable")
	}
	// Present but short of the threshold: not yet.
	tr.observe(7, true, t0)
	if tr.noteStable(t0.Add(threshold-time.Second), threshold) {
		t.Fatal("presence short of the threshold reported stable")
	}
	// At the threshold: reported, once.
	if !tr.noteStable(t0.Add(threshold), threshold) {
		t.Fatal("presence at the threshold must report stable")
	}
	if tr.noteStable(t0.Add(threshold+time.Second), threshold) {
		t.Fatal("the stability crossing must be reported only once per run")
	}
	// A flicker restarts the run: the crossing must be
	// earned again and reported again.
	tr.observe(7, false, t0.Add(10*time.Second))
	tr.observe(7, true, t0.Add(11*time.Second))
	if tr.noteStable(t0.Add(11*time.Second+threshold-time.Second), threshold) {
		t.Fatal("the restarted run reported stable early")
	}
	if !tr.noteStable(t0.Add(11*time.Second+threshold), threshold) {
		t.Fatal("the restarted run must report its own crossing")
	}
}
