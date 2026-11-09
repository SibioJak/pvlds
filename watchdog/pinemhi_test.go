package main

import "testing"

// PINEMHI2 Part B: the watcher-management decisions. The law in
// one table: off never acts; un-owned + running adopts; un-owned
// + not running starts; any settled state never re-decides; and
// only a started watcher under management is ever closed.

func TestPinemhiDecide(t *testing.T) {
	cases := []struct {
		name    string
		manage  bool
		state   string
		running bool
		want    pinemhiAction
	}{
		{"off, not running", false, "", false, pinemhiNone},
		{"off, running", false, "", true, pinemhiNone},
		{"off, already started", false, "started", false, pinemhiNone},
		{"on, cold", true, "", false, pinemhiStart},
		{"on, already running", true, "", true, pinemhiAdopt},
		{"on, we started it, still running", true, "started", true, pinemhiNone},
		{"on, we started it, died (clear path re-decides)", true, "started", false, pinemhiNone},
		{"on, adopted, running", true, "adopted", true, pinemhiNone},
		{"on, adopted, died", true, "adopted", false, pinemhiNone},
	}
	for _, tc := range cases {
		if got := pinemhiDecide(tc.manage, tc.state, tc.running); got != tc.want {
			t.Errorf("%s: pinemhiDecide(manage=%v, state=%q, running=%v) = %d, want %d",
				tc.name, tc.manage, tc.state, tc.running, got, tc.want)
		}
	}
}

func TestPinemhiShouldClose(t *testing.T) {
	cases := []struct {
		name   string
		manage bool
		state  string
		want   bool
	}{
		{"off, started", false, "started", false},
		{"off, adopted", false, "adopted", false},
		{"off, none", false, "", false},
		{"on, started - ours, close it", true, "started", true},
		{"on, adopted - never ours to close", true, "adopted", false},
		{"on, none - nothing was started", true, "", false},
	}
	for _, tc := range cases {
		if got := pinemhiShouldClose(tc.manage, tc.state); got != tc.want {
			t.Errorf("%s: pinemhiShouldClose(manage=%v, state=%q) = %v, want %v",
				tc.name, tc.manage, tc.state, got, tc.want)
		}
	}
}

// The NC seam is the negative control's whole mechanism: with
// PVLDS_PINEMHI_NC=closeadopted the close decision ignores the
// ownership state, so an adopted watcher would be closed - the
// adoption smoke leg must fail by name under it. Pin the seam's
// behaviour here so it can never silently stop breaking the law.
func TestPinemhiShouldCloseNCSeam(t *testing.T) {
	t.Setenv("PVLDS_PINEMHI_NC", "closeadopted")
	if !pinemhiShouldClose(true, "adopted") {
		t.Error("NC closeadopted: an adopted watcher must read as closable (that is the break)")
	}
	if pinemhiShouldClose(false, "adopted") {
		t.Error("NC closeadopted: management off must still never close")
	}
}

// WATCHERLIFE: the session/tail tracker. The watcher is wanted
// inside a session and through the extraction tail that follows
// it - and nowhere else: not at boot, not at idle, and the tail
// is not extended by idling. A session inside the tail cancels
// it outright.
func TestPinemhiLifetime(t *testing.T) {
	const tail = 90
	var l pinemhiLifetime
	// Boot / idle: never wanted, no matter how long the app sits.
	for now := int64(0); now < 10000; now += 37 {
		if l.wanted(false, now, tail) {
			t.Fatalf("idle at %d: wanted = true, want false (the watcher never exists at idle)", now)
		}
	}
	// A session starts: wanted from its first tick.
	if !l.wanted(true, 20000, tail) {
		t.Fatal("session start: wanted = false, want true")
	}
	// The session runs: wanted throughout.
	for now := int64(20001); now < 21000; now += 41 {
		if !l.wanted(true, now, tail) {
			t.Fatalf("in session at %d: wanted = false, want true", now)
		}
	}
	// VPX exits at 21000: the tail runs to 21090 - wanted through
	// it, not one tick past it.
	if !l.wanted(false, 21000, tail) {
		t.Fatal("first tick after the session: wanted = false, want true (the tail starts)")
	}
	if !l.wanted(false, 21089, tail) {
		t.Fatal("inside the tail: wanted = false, want true")
	}
	if l.wanted(false, 21090, tail) {
		t.Fatal("tail end: wanted = true, want false (the watcher closes here)")
	}
	if l.wanted(false, 99999, tail) {
		t.Fatal("long past the tail: wanted = true, want false")
	}
}

func TestPinemhiLifetimeSessionInsideTail(t *testing.T) {
	const tail = 90
	var l pinemhiLifetime
	// Session 1 runs and ends at 1000; the tail would end at 1090.
	l.wanted(true, 900, tail)
	l.wanted(false, 1000, tail)
	// Session 2 starts at 1050, inside the tail: wanted, and the
	// tail is CANCELLED - session 2's own end starts a fresh one.
	if !l.wanted(true, 1050, tail) {
		t.Fatal("second session inside the tail: wanted = false, want true")
	}
	if !l.wanted(false, 1095, tail) {
		t.Fatal("past the first tail's end but inside session 2's tail: wanted = false, want true")
	}
	if !l.wanted(false, 1184, tail) {
		t.Fatal("inside session 2's tail (ends 1185): wanted = false, want true")
	}
	if l.wanted(false, 1185, tail) {
		t.Fatal("session 2's tail end: wanted = true, want false")
	}
}

func TestPinemhiLifetimeZeroTail(t *testing.T) {
	// A zero tail (the bench seam's floor) ends the life on the
	// very tick the session ends - no tick of grace.
	var l pinemhiLifetime
	l.wanted(true, 500, 0)
	if l.wanted(false, 500, 0) {
		t.Fatal("zero tail: wanted = true on the session's end tick, want false")
	}
}

// WATCHERFIX: the failed-start latch. A failed start logs once per
// spell; the spell is keyed on manage/folder, so a settings toggle
// or a folder change re-arms it, and steady values never do.
func TestPinemhiStartLatch(t *testing.T) {
	var l pinemhiStartLatch
	l.sync(true, `D:\vPinball\Pinemhi`)
	if !l.mayStart() {
		t.Fatal("fresh spell: mayStart = false, want true")
	}
	l.recordFailure()
	if l.mayStart() {
		t.Fatal("after a failed start: mayStart = true, want false (latched)")
	}
	// Steady ticks with the same values: the spell holds.
	for i := 0; i < 10; i++ {
		l.sync(true, `D:\vPinball\Pinemhi`)
	}
	if l.mayStart() {
		t.Fatal("same manage/folder across ticks: latch released, want held")
	}
	// A folder change is a new spell.
	l.sync(true, `E:\elsewhere\Pinemhi`)
	if !l.mayStart() {
		t.Fatal("folder change: mayStart = false, want true (new spell)")
	}
	l.recordFailure()
	// Toggling manage off and back on is a new spell.
	l.sync(false, `E:\elsewhere\Pinemhi`)
	l.sync(true, `E:\elsewhere\Pinemhi`)
	if !l.mayStart() {
		t.Fatal("manage off->on: mayStart = false, want true (new spell)")
	}
	// And a failure in the new spell latches again.
	l.recordFailure()
	l.sync(true, `E:\elsewhere\Pinemhi`)
	if l.mayStart() {
		t.Fatal("second spell failure: mayStart = true, want false (latched again)")
	}
}
