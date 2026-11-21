package main

// FIX154 invariant legs (namewindow.go): the title
// derivation and the window lifecycle, exercised
// against a recording fake leaf so the whole machine
// - raise, expiry judgement, one-at-a-time
// replacement - is asserted on every platform.

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

// nameWindowFake is the recording leaf: every create
// and destroy lands in events, in order, so a test
// can assert not just WHAT happened but the order
// (a replacement destroys before it creates).
type nameWindowFake struct {
	events  []string
	seq     uintptr
	failAll bool
}

func (f *nameWindowFake) create(title string) uintptr {
	if f.failAll {
		f.events = append(f.events, "create-failed:"+title)
		return 0
	}
	f.seq++
	f.events = append(f.events, "create:"+title)
	return 1000 + f.seq
}

func (f *nameWindowFake) destroy(hwnd uintptr) {
	f.events = append(f.events, fmt.Sprintf("destroy:%d", hwnd))
}

// swapNameWindowFake installs the fake leaf and a
// clean tracker for one test, restoring both after.
func swapNameWindowFake(t *testing.T) *nameWindowFake {
	t.Helper()
	f := &nameWindowFake{}
	oldCreate, oldDestroy := nameWindowCreate, nameWindowDestroy
	oldState := sessionNameWindow
	oldFeed := nameFeedSession
	nameWindowCreate, nameWindowDestroy = f.create, f.destroy
	sessionNameWindow = nameWindowState{}
	nameFeedSession = 0
	t.Cleanup(func() {
		nameWindowCreate, nameWindowDestroy = oldCreate, oldDestroy
		sessionNameWindow = oldState
		nameFeedSession = oldFeed
	})
	return f
}

func TestNameWindowTitleDerivation(t *testing.T) {
	// FIX155: the contract carries the table's path;
	// the derivation is path -> stem -> title (the
	// FIX154 legs derived from the cold spawn's argv -
	// the same cases, one feed earlier).
	cases := []struct {
		name string
		path string
		want string
		ok   bool
	}{
		{
			"the brief's exact case",
			`D:\vPinball\VisualPinball\Tables\Big Chief (Williams 1965)_Teisen_MOD.vpx`,
			"Visual Pinball - [Big Chief (Williams 1965)_Teisen_MOD]", true,
		},
		{
			"forward slashes",
			"D:/Tables/Forward.vpx",
			"Visual Pinball - [Forward]", true,
		},
		{
			"uppercase extension",
			`D:\Tables\Upper.VPX`,
			"Visual Pinball - [Upper]", true,
		},
		{
			"relative path",
			`Tables\Rel.vpx`,
			"Visual Pinball - [Rel]", true,
		},
		{
			"no table in the path",
			`D:\Tables\notes.txt`,
			"", false,
		},
		{
			"empty path",
			"",
			"", false,
		},
	}
	for _, tc := range cases {
		got, ok := nameWindowTitleForPath(tc.path)
		if ok != tc.ok || got != tc.want {
			t.Errorf("%s: nameWindowTitleForPath(%q) = (%q, %t), want (%q, %t)", tc.name, tc.path, got, ok, tc.want, tc.ok)
		}
	}
	if _, ok := tableFileStem(".vpx"); ok {
		t.Errorf("tableFileStem(%q): a bare extension is not a table", ".vpx")
	}
}

// FIX155 invariant leg: a resident launch contract -
// the table's name carried, no spawn fields anywhere
// in the decision - makes the watchdog raise the
// name window with the exact Big Chief title, once
// per session, and the standing expiry drops it on
// the B2S sighting and on session end.
func TestNameWindowResidentTrigger(t *testing.T) {
	f := swapNameWindowFake(t)
	t0 := time.Unix(1_700_000_000, 0)
	title := "Visual Pinball - [Big Chief (Williams 1965)_Teisen_MOD]"
	resident := &Contract{
		Armed:         true,
		SessionID:     7,
		SessionState:  "loading",
		GameTablePath: `D:\vPinball\VisualPinball\Tables\Big Chief (Williams 1965)_Teisen_MOD.vpx`,
	}

	// First observation of the loading session: the
	// window goes up with the exact title.
	observeNameFeed(resident, t0)
	if !sessionNameWindow.up() || sessionNameWindow.sessionID != 7 {
		t.Fatalf("after the first observation: tracker = %+v, want up for session 7", sessionNameWindow)
	}
	if len(f.events) != 1 || f.events[0] != "create:"+title {
		t.Fatalf("after the first observation: events = %v, want [create:%s]", f.events, title)
	}

	// The same session observed again: no second
	// window, no replacement churn.
	observeNameFeed(resident, t0.Add(time.Second))
	if len(f.events) != 1 {
		t.Fatalf("second observation of the session: events = %v, want no new events", f.events)
	}

	// The B2S sighting drops it (the standing expiry).
	judgeNameWindow(resident, true, t0.Add(2*time.Second))
	if sessionNameWindow.up() {
		t.Fatalf("after the sighting: tracker still up")
	}

	// A later session raises its own window, and the
	// session's end drops it.
	next := &Contract{Armed: true, SessionID: 8, SessionState: "loading", GameTablePath: `D:\Tables\Other.vpx`}
	observeNameFeed(next, t0)
	if !sessionNameWindow.up() || sessionNameWindow.sessionID != 8 {
		t.Fatalf("next session: tracker = %+v, want up for session 8", sessionNameWindow)
	}
	judgeNameWindow(&Contract{SessionID: 8, SessionState: "returned"}, false, t0.Add(time.Second))
	if sessionNameWindow.up() {
		t.Fatalf("after session end: tracker still up")
	}

	// A session carrying no table path (an older
	// launcher's contract) gets no window at all.
	observeNameFeed(&Contract{Armed: true, SessionID: 9, SessionState: "loading"}, t0)
	if sessionNameWindow.up() {
		t.Fatalf("nameless session: a window went up")
	}
	// A live-first observation (the watch began
	// mid-session) raises nothing - the scrape has
	// already run by then.
	observeNameFeed(&Contract{Armed: true, SessionID: 10, SessionState: "live", GameTablePath: `D:\Tables\Late.vpx`}, t0)
	if sessionNameWindow.up() {
		t.Fatalf("live-first session: a window went up")
	}
}

func TestNameWindowLifecycle(t *testing.T) {
	f := swapNameWindowFake(t)
	t0 := time.Unix(1_700_000_000, 0)
	title := "Visual Pinball - [Big Chief (Williams 1965)_Teisen_MOD]"
	loading := &Contract{SessionID: 5, SessionState: "loading"}

	// Raise: the leaf creates with the exact title,
	// the tracker is up for the session.
	raiseNameWindow(5, title, t0)
	if !sessionNameWindow.up() || sessionNameWindow.sessionID != 5 {
		t.Fatalf("after raise: tracker = %+v, want up for session 5", sessionNameWindow)
	}
	if len(f.events) != 1 || f.events[0] != "create:"+title {
		t.Fatalf("after raise: events = %v, want [create:%s]", f.events, title)
	}

	// Ordinary loading ticks: the window stays up.
	judgeNameWindow(loading, false, t0.Add(10*time.Second))
	judgeNameWindow(&Contract{SessionID: 5, SessionState: "live"}, false, t0.Add(30*time.Second))
	if !sessionNameWindow.up() || len(f.events) != 1 {
		t.Fatalf("across loading/live ticks: events = %v, want the window still up, untouched", f.events)
	}

	// The B2S sighting: the name has been consumed -
	// down it comes, by our recorded handle.
	judgeNameWindow(loading, true, t0.Add(40*time.Second))
	if sessionNameWindow.up() {
		t.Fatalf("after the sighting: tracker still up")
	}
	if len(f.events) != 2 || f.events[1] != "destroy:1001" {
		t.Fatalf("after the sighting: events = %v, want destroy of the raised handle", f.events)
	}

	// Session end: a state outside the launch drops
	// the window on the next judgement.
	raiseNameWindow(5, title, t0)
	judgeNameWindow(&Contract{SessionID: 5, SessionState: "returned"}, false, t0.Add(time.Second))
	if sessionNameWindow.up() || len(f.events) != 4 {
		t.Fatalf("after session end: events = %v, want create+destroy for the second raise", f.events)
	}

	// The cap: no sighting inside 120s and the window
	// comes down on its own - and not a tick early.
	raiseNameWindow(5, title, t0)
	judgeNameWindow(loading, false, t0.Add(119*time.Second))
	if !sessionNameWindow.up() {
		t.Fatalf("at 119s: the window came down before the cap")
	}
	judgeNameWindow(loading, false, t0.Add(120*time.Second))
	if sessionNameWindow.up() {
		t.Fatalf("at 120s: the cap did not drop the window")
	}

	// Supersede: a newer session's facts drop the old
	// session's window.
	raiseNameWindow(5, title, t0)
	judgeNameWindow(&Contract{SessionID: 6, SessionState: "loading"}, false, t0.Add(time.Second))
	if sessionNameWindow.up() {
		t.Fatalf("after supersede: the old session's window is still up")
	}

	// One at a time: a second raise destroys the
	// first window BEFORE creating its own.
	before := len(f.events)
	raiseNameWindow(5, title, t0)
	raiseNameWindow(6, "Visual Pinball - [Other]", t0)
	got := f.events[before:]
	want := []string{"create:" + title, "destroy:1005", "create:Visual Pinball - [Other]"}
	if len(got) != len(want) {
		t.Fatalf("replacement: events = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("replacement: events = %v, want %v", got, want)
		}
	}
	if sessionNameWindow.sessionID != 6 {
		t.Fatalf("replacement: tracker serves session %d, want 6", sessionNameWindow.sessionID)
	}

	// A drop with nothing up is silent, and a failed
	// creation leaves nothing up and nothing to drop.
	dropNameWindow("test cleanup")
	before = len(f.events)
	dropNameWindow("nothing up")
	if len(f.events) != before {
		t.Fatalf("drop with nothing up: events grew: %v", f.events[before:])
	}
	f.failAll = true
	raiseNameWindow(7, title, t0)
	if sessionNameWindow.up() {
		t.Fatalf("failed creation: tracker claims a window is up")
	}
}

func TestNameWindowJudgeReasons(t *testing.T) {
	t0 := time.Unix(1_700_000_000, 0)
	w := nameWindowState{sessionID: 5, hwnd: 42, title: "Visual Pinball - [X]", armedAt: t0}
	if r := w.judge(6, "loading", true, t0); !strings.HasPrefix(r, "superseded by session 6") {
		t.Errorf("supersede outranks the sighting: judge = %q", r)
	}
	if r := w.judge(5, "loading", true, t0); r != "b2s sighted" {
		t.Errorf("sighting: judge = %q", r)
	}
	if r := w.judge(5, "failed", false, t0); !strings.Contains(r, "left the launch") {
		t.Errorf("session end: judge = %q", r)
	}
	if r := w.judge(5, "live", false, t0.Add(120*time.Second)); !strings.Contains(r, "cap") {
		t.Errorf("cap: judge = %q", r)
	}
	if r := w.judge(5, "loading", false, t0.Add(60*time.Second)); r != "" {
		t.Errorf("mid-load: judge = %q, want stays up", r)
	}
	down := nameWindowState{}
	if r := down.judge(5, "failed", true, t0); r != "" {
		t.Errorf("nothing up: judge = %q, want silent", r)
	}
}
