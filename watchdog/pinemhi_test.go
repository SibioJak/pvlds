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
