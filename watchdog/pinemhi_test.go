package main

import "testing"

// PINEMHI2 Part B: the watcher-management decisions under
// APPRUN (2026-11-17). The law in one table: off never acts;
// un-owned + running adopts; un-owned + not running starts;
// any settled state never re-decides; nothing ever closes at
// a session's end; and at true exit a watcher under
// management is closed whether PVLDS started it or adopted
// it - the app owned its lifetime for the run either way.

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
		{"on, started - ours, close it at exit", true, "started", true},
		{"on, adopted - the run owned its lifetime, close it at exit", true, "adopted", true},
		{"on, none - nothing was started", true, "", false},
	}
	for _, tc := range cases {
		if got := pinemhiShouldClose(tc.manage, tc.state); got != tc.want {
			t.Errorf("%s: pinemhiShouldClose(manage=%v, state=%q) = %v, want %v",
				tc.name, tc.manage, tc.state, got, tc.want)
		}
	}
}

// APPRUN's load-bearing wall: NOTHING closes at a session's
// end. The decision answers false for every input - and the
// NC seam is the negative control's whole mechanism: with
// PVLDS_PINEMHI_NC=closeearly it answers true for an adopted
// watcher, the tick duty closes that watcher at session end,
// and the integration smoke's no-early-close leg must fail by
// name under it. Pin both halves here so the seam can never
// silently stop breaking the law - or start.
func TestPinemhiCloseAtSessionEnd(t *testing.T) {
	for _, tc := range []struct {
		manage bool
		state  string
	}{
		{false, "started"}, {false, "adopted"}, {false, ""},
		{true, "started"}, {true, "adopted"}, {true, ""},
	} {
		if pinemhiCloseAtSessionEnd(tc.manage, tc.state) {
			t.Errorf("no seam: pinemhiCloseAtSessionEnd(manage=%v, state=%q) = true, want false (nothing closes at session end)", tc.manage, tc.state)
		}
	}
	t.Setenv("PVLDS_PINEMHI_NC", "closeearly")
	if !pinemhiCloseAtSessionEnd(true, "adopted") {
		t.Error("NC closeearly: an adopted watcher must read as session-end-closable (that is the break)")
	}
	if pinemhiCloseAtSessionEnd(true, "started") {
		t.Error("NC closeearly: the seam targets adopted watchers only - a started one must stay unclosable at session end")
	}
	if pinemhiCloseAtSessionEnd(false, "adopted") {
		t.Error("NC closeearly: management off must still never close")
	}
}

// The retired seam value must be inert now: closeadopted
// broke the OLD law (adopted unclosable even at exit); under
// APPRUN adopted closes at exit by law, so the old value
// arming anything would be a seam nobody owns.
func TestPinemhiCloseEarlyIgnoresRetiredSeam(t *testing.T) {
	t.Setenv("PVLDS_PINEMHI_NC", "closeadopted")
	if pinemhiCloseAtSessionEnd(true, "adopted") {
		t.Error("retired seam value closeadopted must not arm the session-end close")
	}
}

// APPRUN: the run latch. Before the run's first session the
// watcher is not wanted, no matter how long the app sits at
// the desk or in the room. From that session on it is wanted
// on every tick for the rest of the run - across table exits,
// idle gaps and desk sojourns, with no clock and no tail.
func TestPinemhiRunLatch(t *testing.T) {
	var l pinemhiRunLatch
	// Boot / desk / idle room: never wanted.
	for i := 0; i < 1000; i++ {
		if l.wanted(false) {
			t.Fatalf("idle tick %d: wanted = true, want false (no session has run yet)", i)
		}
	}
	// The first session starts: wanted from its first tick.
	if !l.wanted(true) {
		t.Fatal("first session: wanted = false, want true")
	}
	// The table exits; the app idles on. Wanted forever.
	for i := 0; i < 1000; i++ {
		if !l.wanted(false) {
			t.Fatalf("post-session idle tick %d: wanted = false, want true (the run latch holds)", i)
		}
	}
	// Later sessions change nothing.
	if !l.wanted(true) {
		t.Fatal("second session: wanted = false, want true")
	}
	if !l.wanted(false) {
		t.Fatal("after the second session: wanted = false, want true")
	}
}

// The exit close's identity check: the recorded pid must be
// among the watcher exe's own pids. A pid the OS reused for a
// stranger - or a dead watcher, whose pid appears nowhere -
// does not verify, and pid 0 never does.
func TestPinemhiRecordVerified(t *testing.T) {
	cases := []struct {
		name string
		pid  int
		exe  []int
		want bool
	}{
		{"the watcher itself", 4240, []int{4240, 99}, true},
		{"only the watcher running", 4240, []int{4240}, true},
		{"a stranger holds the pid now", 4240, []int{99, 100}, false},
		{"no watcher running at all", 4240, nil, false},
		{"no pid recorded", 0, []int{4240}, false},
		{"negative pid", -3, []int{-3}, false},
	}
	for _, tc := range cases {
		if got := pinemhiRecordVerified(tc.pid, tc.exe); got != tc.want {
			t.Errorf("%s: pinemhiRecordVerified(pid=%d, exe=%v) = %v, want %v",
				tc.name, tc.pid, tc.exe, got, tc.want)
		}
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
