package main

import "testing"

// The player-target resolver (target.go), exercised on Linux:
// one ranked choice of THE window that owns input, over
// scripted window sets carrying the field inventories' own
// shapes - the GL set (an SDL window among the furniture),
// the BGFX set (droscoe's: a VPPlayer window and IME helpers,
// no SDL window at all - the set the pre-FIX116 actuators
// could not raise), and the sets that must resolve NO target.

func obsW(hwnd uintptr, class string, w, h int64, visible bool) windowObs {
	return windowObs{hwnd: hwnd, class: class, width: w, height: h, visible: visible}
}

const (
	hwSDLw  = uintptr(0xA1)
	hwVPw   = uintptr(0xA2)
	hwEditW = uintptr(0xE1)
	hwMAMEw = uintptr(0xB1)
	hwIMEw  = uintptr(0x11)
	hwCVFw  = uintptr(0xC1)
)

func TestTargetGLSetResolvesVisibleSDL(t *testing.T) {
	var r targetResolver
	set := []windowObs{
		obsW(hwEditW, editorWindowClass, 1280, 900, true),
		obsW(hwMAMEw, "MAME", 322, 242, false),
		obsW(hwSDLw, sdlWindowClass, 1920, 1080, true),
	}
	hwnd, class, why := r.resolve(1, set)
	if hwnd != hwSDLw || class != sdlWindowClass || why != targetWhyVisibleSDL {
		t.Fatalf("got (%#x, %q, %q), want the visible SDL window", hwnd, class, why)
	}
}

func TestTargetBGFXSetResolvesVisibleVPPlayer(t *testing.T) {
	// Droscoe's field inventory (FIX113's fixture): the
	// launched pid owns a VPPlayer window and IME helpers -
	// no SDL_app anywhere. The pre-FIX116 actuators found no
	// target in this set at all.
	var r targetResolver
	set := []windowObs{
		obsW(hwVPw, playerWindowClass, 1920, 1080, true),
		obsW(hwIMEw, "IME", 0, 0, false),
		obsW(0x12, "MSCTFIME UI", 0, 0, false),
	}
	hwnd, class, why := r.resolve(1, set)
	if hwnd != hwVPw || class != playerWindowClass || why != targetWhyVisibleVP {
		t.Fatalf("got (%#x, %q, %q), want the visible VPPlayer window", hwnd, class, why)
	}
}

func TestTargetRankOrder(t *testing.T) {
	// Visible SDL beats visible VPPlayer; visible VPPlayer
	// beats the hidden SDL fallback.
	var r targetResolver
	set := []windowObs{
		obsW(hwVPw, playerWindowClass, 1920, 1080, true),
		obsW(hwSDLw, sdlWindowClass, 800, 600, false),
	}
	if hwnd, _, why := r.resolve(1, set); hwnd != hwVPw || why != targetWhyVisibleVP {
		t.Fatalf("VP+hidden SDL: got (%#x, %q), want the visible VPPlayer", hwnd, why)
	}
	set = append(set, obsW(0xA3, sdlWindowClass, 1920, 1080, true))
	if hwnd, _, why := r.resolve(1, set); hwnd != 0xA3 || why != targetWhyVisibleSDL {
		t.Fatalf("VP+visible SDL: got (%#x, %q), want the visible SDL", hwnd, why)
	}
	// The hidden SDL fallback alone.
	var r2 targetResolver
	set = []windowObs{obsW(hwSDLw, sdlWindowClass, 800, 600, false)}
	if hwnd, _, why := r2.resolve(1, set); hwnd != hwSDLw || why != targetWhyHiddenSDL {
		t.Fatalf("hidden SDL alone: got (%#x, %q), want the hidden fallback", hwnd, why)
	}
}

func TestTargetNoTargetSets(t *testing.T) {
	sets := map[string][]windowObs{
		"editor only":   {obsW(hwEditW, editorWindowClass, 1280, 900, true)},
		"editor+dialog": {obsW(hwEditW, editorWindowClass, 1280, 900, true), obsW(0xD1, loadDialogClass, 400, 200, true)},
		"canvas only":   {obsW(hwCVFw, "CVFrame", 1401, 809, false)},
		"mame only":     {obsW(hwMAMEw, "MAME", 322, 242, true)},
		"empty":         {},
		"tiny vpplayer": {obsW(hwVPw, playerWindowClass, 100, 80, true)}, // below the area floor: not the runtime shape
	}
	for name, set := range sets {
		var r targetResolver
		if hwnd, _, why := r.resolve(1, set); hwnd != 0 || why != targetWhyNone {
			t.Fatalf("%s: got (%#x, %q), want no target", name, hwnd, why)
		}
	}
}

func TestTargetClassFreeCandidatePersists(t *testing.T) {
	// An unknown substantial class: not a target on first
	// sight, a target once the same handle persists, and
	// displaced the snapshot a named class appears.
	var r targetResolver
	set := []windowObs{obsW(0xF1, "WeirdPlayer", 1024, 768, false)}
	if hwnd, _, _ := r.resolve(1, set); hwnd != 0 {
		t.Fatalf("first sight: got %#x, want no target yet", hwnd)
	}
	hwnd, class, why := r.resolve(1, set)
	if hwnd != 0xF1 || class != "WeirdPlayer" || why != targetWhyClassFree {
		t.Fatalf("persisted: got (%#x, %q, %q), want the class-free candidate", hwnd, class, why)
	}
	set = append(set, obsW(hwSDLw, sdlWindowClass, 1920, 1080, true))
	if hwnd, _, why := r.resolve(1, set); hwnd != hwSDLw || why != targetWhyVisibleSDL {
		t.Fatalf("displaced: got (%#x, %q), want the visible SDL", hwnd, why)
	}
}

func TestTargetClassFreeExclusionsAndRecreation(t *testing.T) {
	// A helper class of candidate size never resolves, however
	// long it persists; and a recreated candidate (new handle)
	// restarts its persistence.
	var r targetResolver
	helpers := []windowObs{obsW(hwMAMEw, "MAME", 800, 600, true)}
	for i := 0; i < 4; i++ {
		if hwnd, _, _ := r.resolve(1, helpers); hwnd != 0 {
			t.Fatalf("helper set poll %d: got %#x, want no target", i, hwnd)
		}
	}
	var r2 targetResolver
	first := []windowObs{obsW(0xF1, "WeirdPlayer", 1024, 768, true)}
	second := []windowObs{obsW(0xF2, "WeirdPlayer", 1024, 768, true)}
	r2.resolve(1, first)
	if hwnd, _, _ := r2.resolve(1, second); hwnd != 0 {
		t.Fatalf("recreated handle: got %#x, want the persistence restarted", hwnd)
	}
	if hwnd, _, _ := r2.resolve(1, second); hwnd != 0xF2 {
		t.Fatalf("recreated handle persisted: got %#x, want 0xF2", hwnd)
	}
	// A new session restarts persistence too.
	if hwnd, _, _ := r2.resolve(2, second); hwnd != 0 {
		t.Fatalf("new session: got %#x, want the persistence restarted", hwnd)
	}
}
