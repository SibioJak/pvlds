package main

import (
	"testing"
	"time"
)

// Change-detection pins for the B2S sighting tracker:
// the log speaks on a session's first observation and
// on every change of fact after it, and stays silent
// on repeats. (FIX149's continuous-presence clock legs
// stood here until FIX155 removed the hand-off gate,
// the clock's only consumer; the tracker's remaining
// clock is the first-sighting latch below.)

func TestB2SightingChanges(t *testing.T) {
	var tr b2sSighting
	t0 := time.Unix(1_700_000_000, 0)

	// The first observation of a session speaks.
	if !tr.observe(7, false, t0) {
		t.Fatal("the first observation of a session must report changed")
	}
	// A repeat of the same fact is silent.
	if tr.observe(7, false, t0.Add(time.Second)) {
		t.Fatal("an unchanged fact must not report changed")
	}
	// Every flip of the fact speaks, in both directions.
	if !tr.observe(7, true, t0.Add(2*time.Second)) {
		t.Fatal("absent -> present must report changed")
	}
	if tr.observe(7, true, t0.Add(3*time.Second)) {
		t.Fatal("continued presence must not report changed")
	}
	if !tr.observe(7, false, t0.Add(4*time.Second)) {
		t.Fatal("present -> absent must report changed")
	}
	// A session change speaks even when the fact is the
	// same - the new session's first observation is its
	// own line.
	if !tr.observe(8, false, t0.Add(5*time.Second)) {
		t.Fatal("a session change must report changed")
	}
}

// Pins for the LATCHING first-sighting fact - the fact
// FIX155's name window expiry reads in-process. The law: the
// stamp is the FIRST sighting of the session, it survives
// every absence after it (that is what makes it a latch,
// distinct from the present fact), and only a session
// change clears it.
func TestB2SightingSeen(t *testing.T) {
	var tr b2sSighting
	t0 := time.Unix(1_700_000_000, 0)

	// Nothing observed yet, then observed absent: no stamp.
	if got := tr.seenUnix(); got != 0 {
		t.Fatalf("unobserved tracker stamped seen %d, want 0", got)
	}
	tr.observe(7, false, t0)
	if got := tr.seenUnix(); got != 0 {
		t.Fatalf("absent observation stamped seen %d, want 0", got)
	}
	// The first sighting latches at its own moment.
	t1 := t0.Add(3 * time.Second)
	tr.observe(7, true, t1)
	if got := tr.seenUnix(); got != t1.Unix() {
		t.Fatalf("first sighting stamped seen %d, want %d", got, t1.Unix())
	}
	// Absence does NOT clear the latch (the whole point:
	// "seen, then gone" must read differently from "never
	// seen").
	tr.observe(7, false, t1.Add(time.Second))
	if got := tr.seenUnix(); got != t1.Unix() {
		t.Fatalf("absence cleared the latch to %d, want %d", got, t1.Unix())
	}
	// A return does not move the latch to the return.
	tr.observe(7, true, t1.Add(2*time.Second))
	if got := tr.seenUnix(); got != t1.Unix() {
		t.Fatalf("a return moved the latch to %d, want the first sighting %d", got, t1.Unix())
	}
	// A new session clears the latch: absent first, it
	// reads 0 again until the new session's own sighting.
	tr.observe(8, false, t1.Add(3*time.Second))
	if got := tr.seenUnix(); got != 0 {
		t.Fatalf("a new session kept the latch %d, want 0", got)
	}
	t2 := t1.Add(9 * time.Second)
	tr.observe(8, true, t2)
	if got := tr.seenUnix(); got != t2.Unix() {
		t.Fatalf("new session's sighting stamped %d, want %d", got, t2.Unix())
	}
}
