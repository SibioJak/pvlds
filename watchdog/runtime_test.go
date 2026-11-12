package main

import "testing"

// The runtime signature is pinned to the field inventories of
// sessions 25/26 (Chris's rig, 2026-10-23): the windows that
// exist only once a table's runtime is genuinely up, and the
// look-alikes that must never stamp it (the editor canvas the
// old hand-off cue stamped off, the editor frame, the loading
// dialog, the editor's furniture).

func TestRuntimeSignatureClasses(t *testing.T) {
	runtimeClasses := []string{"MAME", "VPINMAMEEVENTWND", "SharpGLRenderWindow", "NVOpenGLPbuffer", "DIEmWin"}
	for _, class := range runtimeClasses {
		for _, visible := range []bool{true, false} {
			// Render/runtime windows count regardless of
			// desktop visibility - the headset-bound runtime
			// hides most of what it owns.
			if !classifyRuntime([]windowObs{{class: class, width: 100, height: 100, visible: visible}}) {
				t.Errorf("class %q visible=%v: want runtime", class, visible)
			}
		}
	}
}

func TestRuntimeSignatureB2SPrefix(t *testing.T) {
	// The B2S server's windows all carry the .NET wrapper class
	// shape from the field inventories; any class opening with
	// the wrapper prefix counts (the suffix is a per-window
	// GUID, never a stable string to match exactly).
	if !classifyRuntime([]windowObs{{class: "HwndWrapper[DefaultDomain;;3e9af7ee-6456-4c31-8ac2-f179fa2713cb]", width: 460, height: 115, visible: true}}) {
		t.Error("a B2S HwndWrapper window: want runtime")
	}
	if !classifyRuntime([]windowObs{{class: "HwndWrapper[DefaultDomain;;499e3f83-c81f-4e72-9c25-4ddf9f3bd9b9]", width: 0, height: 0, visible: false}}) {
		t.Error("a hidden 0x0 B2S wrapper window: want runtime")
	}
}

func TestRuntimeSignatureSDLVisibleOnly(t *testing.T) {
	// SDL_app exists hidden from early in the load (session 25:
	// hidden at +3s) and flips visible exactly when the player
	// comes up - only the visible form is runtime evidence.
	if classifyRuntime([]windowObs{{class: "SDL_app", width: 1, height: 1, visible: false}}) {
		t.Error("hidden SDL_app: want NOT runtime")
	}
	if !classifyRuntime([]windowObs{{class: "SDL_app", width: 1, height: 1, visible: true}}) {
		t.Error("visible SDL_app: want runtime")
	}
}

func TestRuntimeSignatureNeverEvidence(t *testing.T) {
	never := []windowObs{
		{class: "CVFrame", width: 1401, height: 809, visible: false}, // the editor canvas - the old cue's false friend
		{class: "CVFrame", width: 1401, height: 809, visible: true},
		{class: "VPinball", width: 1167, height: 634, visible: true}, // the editor frame
		{class: "VPPlayer", width: 400, height: 300, visible: true},  // the sighting's window, not the runtime's
		{class: "#32770", width: 265, height: 111, visible: true},    // the loading dialog
		{class: "ComboLBox", width: 220, height: 241, visible: false},
		{class: "IME", width: 0, height: 0, visible: false},
		{class: "MSCTFIME UI", width: 0, height: 0, visible: false},
		{class: "tooltips_class32", width: 0, height: 0, visible: false},
		{class: "", width: 500, height: 500, visible: true},
	}
	for _, w := range never {
		if classifyRuntime([]windowObs{w}) {
			t.Errorf("class %q visible=%v: want NOT runtime", w.class, w.visible)
		}
	}
	if classifyRuntime(nil) {
		t.Error("empty set: want NOT runtime")
	}
}

func TestRuntimeGateLatchAndSessions(t *testing.T) {
	var g runtimeGate
	if seen, just := g.observe(1, false, false); seen || just {
		t.Fatalf("no runtime observed: seen=%v just=%v, want false/false", seen, just)
	}
	if seen, just := g.observe(1, true, false); !seen || !just {
		t.Fatalf("first runtime observation: seen=%v just=%v, want true/true", seen, just)
	}
	if g.ruleFor(1) != runtimeRuleClassic {
		t.Errorf("ruleFor(1) = %q, want %q", g.ruleFor(1), runtimeRuleClassic)
	}
	// Latched: later observations report seen but never re-stamp.
	if seen, just := g.observe(1, false, false); !seen || just {
		t.Fatalf("latched after the runtime goes quiet: seen=%v just=%v, want true/false", seen, just)
	}
	if !g.hasSeen(1) {
		t.Error("hasSeen(1) = false after the stamp")
	}
	// A new session starts unstamped.
	if g.hasSeen(2) {
		t.Error("hasSeen(2) = true for a fresh session")
	}
	if seen, just := g.observe(2, true, false); !seen || !just {
		t.Fatalf("new session's first runtime observation: seen=%v just=%v, want true/true", seen, just)
	}
}

// ── FIX113: the VPPlayer-persistence signature ──────────────────
//
// Fixtures are the field inventories from
// pvlds-fix113/droscoe_watchdog.log: the BGFX-build player pid
// owns exactly three windows in every session - IME and
// MSCTFIME UI (0x0, hidden) and the VPPlayer player window
// (1920x1080, visible). Nothing else ever appears.

var droscoeObs = []windowObs{
	{class: "IME", width: 0, height: 0, visible: false},
	{class: "MSCTFIME UI", width: 0, height: 0, visible: false},
	{class: "VPPlayer", width: 1920, height: 1080, visible: true},
}

func TestVPPlayerRuntimeClassification(t *testing.T) {
	// The droscoe set: no classic evidence (the defect), but
	// the player window is in its runtime form.
	if classifyRuntime(droscoeObs) {
		t.Error("droscoe set: classic signature must stay silent (that silence is the defect)")
	}
	if !classifyVPPlayer(droscoeObs) {
		t.Error("droscoe set: want VPPlayer runtime form")
	}
	// The window must be VISIBLE and substantial: the hidden
	// or small forms are the just-started player, not runtime
	// evidence.
	if classifyVPPlayer([]windowObs{{class: "VPPlayer", width: 1920, height: 1080, visible: false}}) {
		t.Error("hidden VPPlayer: want NOT runtime form")
	}
	if classifyVPPlayer([]windowObs{{class: "VPPlayer", width: 319, height: 240, visible: true}}) {
		t.Error("undersized VPPlayer: want NOT runtime form")
	}
	if !classifyVPPlayer([]windowObs{{class: "VPPlayer", width: 320, height: 240, visible: true}}) {
		t.Error("VPPlayer at the area floor, visible: want runtime form")
	}
	// And the classic signature still refuses the class alone
	// (TestRuntimeSignatureNeverEvidence pins the same window).
	if classifyVPPlayer(nil) {
		t.Error("empty set: want NOT VPPlayer runtime form")
	}
}

func TestRuntimeGateVPPlayerStreak(t *testing.T) {
	var g runtimeGate
	classic, vp := classifyRuntime(droscoeObs), classifyVPPlayer(droscoeObs)
	// The raw sighting shape must NOT stamp: polls before the
	// streak completes report unseen - a stamp here reopens
	// the 2-3s desktop gap the runtime gate exists to close.
	for i := 1; i < runtimeVPPlayerStreak; i++ {
		if seen, just := g.observe(7, classic, vp); seen || just {
			t.Fatalf("poll %d of %d: seen=%v just=%v, want false/false (no stamp before persistence)",
				i, runtimeVPPlayerStreak, seen, just)
		}
	}
	if seen, just := g.observe(7, classic, vp); !seen || !just {
		t.Fatalf("poll %d: seen=%v just=%v, want true/true (the streak completes)",
			runtimeVPPlayerStreak, seen, just)
	}
	if g.ruleFor(7) != runtimeRuleVPPlayer {
		t.Errorf("ruleFor(7) = %q, want %q", g.ruleFor(7), runtimeRuleVPPlayer)
	}
	// Latched, and the rule sticks.
	if seen, just := g.observe(7, false, false); !seen || just {
		t.Fatalf("latched: seen=%v just=%v, want true/false", seen, just)
	}
	if g.ruleFor(7) != runtimeRuleVPPlayer {
		t.Errorf("ruleFor(7) after latch = %q, want %q", g.ruleFor(7), runtimeRuleVPPlayer)
	}
}

func TestRuntimeGateVPPlayerFlickerResets(t *testing.T) {
	var g runtimeGate
	feed := func(classic, vp bool) (bool, bool) { return g.observe(3, classic, vp) }
	// Half a streak, then a poll with neither signature: the
	// count restarts from zero.
	for i := 0; i < runtimeVPPlayerStreak/2; i++ {
		feed(false, true)
	}
	feed(false, false)
	for i := 1; i < runtimeVPPlayerStreak; i++ {
		if seen, _ := feed(false, true); seen {
			t.Fatalf("poll %d after the reset: stamped early - the flicker did not reset the streak", i)
		}
	}
	if seen, just := feed(false, true); !seen || !just {
		t.Fatalf("full streak after the reset: seen=%v just=%v, want true/true", seen, just)
	}
	// A new session starts with a clean streak.
	var g2 runtimeGate
	g2.observe(1, false, true)
	if seen, _ := g2.observe(2, false, true); seen {
		t.Error("streak leaked across sessions")
	}
}

func TestRuntimeGateClassicPriority(t *testing.T) {
	// A poll carrying BOTH signatures stamps classic.
	var g runtimeGate
	if seen, just := g.observe(5, true, true); !seen || !just {
		t.Fatalf("both signatures: seen=%v just=%v, want true/true", seen, just)
	}
	if g.ruleFor(5) != runtimeRuleClassic {
		t.Errorf("ruleFor(5) = %q, want %q", g.ruleFor(5), runtimeRuleClassic)
	}
	// Classic evidence arriving mid-streak stamps at once.
	var g2 runtimeGate
	for i := 0; i < 3; i++ {
		g2.observe(6, false, true)
	}
	if seen, just := g2.observe(6, true, false); !seen || !just {
		t.Fatalf("classic mid-streak: seen=%v just=%v, want true/true", seen, just)
	}
	if g2.ruleFor(6) != runtimeRuleClassic {
		t.Errorf("ruleFor(6) = %q, want %q", g2.ruleFor(6), runtimeRuleClassic)
	}
}

// The GL session's shape, from the sessions 25/26 inventories
// the classic signature is pinned to: the editor set first,
// then the load set (editor canvas + the SDL device window,
// created early and INVISIBLE), then the runtime set - the
// SDL window visible, PinMAME up, the B2S wrapper and the GL
// render surface present. The gate must stamp exactly at the
// runtime set, by the classic rule - the same observation it
// stamped at before FIX113.
func TestRuntimeGateGLSessionShape(t *testing.T) {
	editorSet := []windowObs{
		{class: "VPinball", width: 1167, height: 634, visible: true},
		{class: "CVFrame", width: 1401, height: 809, visible: false},
		{class: "#32770", width: 265, height: 111, visible: true},
		{class: "IME", width: 0, height: 0, visible: false},
	}
	loadSet := []windowObs{
		{class: "VPinball", width: 1167, height: 634, visible: true},
		{class: "CVFrame", width: 1401, height: 809, visible: false},
		{class: "#32770", width: 265, height: 111, visible: true},
		{class: "SDL_app", width: 1920, height: 1080, visible: false},
		{class: "IME", width: 0, height: 0, visible: false},
	}
	runtimeSet := []windowObs{
		{class: "VPinball", width: 1167, height: 634, visible: true},
		{class: "CVFrame", width: 1401, height: 809, visible: false},
		{class: "SDL_app", width: 1920, height: 1080, visible: true},
		{class: "MAME", width: 320, height: 240, visible: false},
		{class: "HwndWrapper[DefaultDomain;;3e9af7ee-6456-4c31-8ac2-f179fa2713cb]", width: 460, height: 115, visible: true},
		{class: "SharpGLRenderWindow", width: 307, height: 77, visible: false},
		{class: "DIEmWin", width: 0, height: 0, visible: false},
	}
	var g runtimeGate
	feed := func(obs []windowObs) (bool, bool) {
		return g.observe(9, classifyRuntime(obs), classifyVPPlayer(obs))
	}
	// Well past the VPPlayer streak's length in each pre-runtime
	// phase: no stamp, ever - the GL build exposes no
	// VPPlayer-class window, so the second signature cannot
	// count here.
	for i := 0; i < runtimeVPPlayerStreak+2; i++ {
		if seen, _ := feed(editorSet); seen {
			t.Fatalf("editor set, poll %d: stamped - GL behaviour changed", i)
		}
		if seen, _ := feed(loadSet); seen {
			t.Fatalf("load set, poll %d: stamped - GL behaviour changed", i)
		}
	}
	if seen, just := feed(runtimeSet); !seen || !just {
		t.Fatalf("runtime set: seen=%v just=%v, want true/true at the classic observation", seen, just)
	}
	if g.ruleFor(9) != runtimeRuleClassic {
		t.Errorf("ruleFor(9) = %q, want %q", g.ruleFor(9), runtimeRuleClassic)
	}
}
