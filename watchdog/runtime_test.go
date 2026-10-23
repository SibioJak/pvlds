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
	if seen, just := g.observe(1, false); seen || just {
		t.Fatalf("no runtime observed: seen=%v just=%v, want false/false", seen, just)
	}
	if seen, just := g.observe(1, true); !seen || !just {
		t.Fatalf("first runtime observation: seen=%v just=%v, want true/true", seen, just)
	}
	// Latched: later observations report seen but never re-stamp.
	if seen, just := g.observe(1, false); !seen || just {
		t.Fatalf("latched after the runtime goes quiet: seen=%v just=%v, want true/false", seen, just)
	}
	if !g.hasSeen(1) {
		t.Error("hasSeen(1) = false after the stamp")
	}
	// A new session starts unstamped.
	if g.hasSeen(2) {
		t.Error("hasSeen(2) = true for a fresh session")
	}
	if seen, just := g.observe(2, true); !seen || !just {
		t.Fatalf("new session's first runtime observation: seen=%v just=%v, want true/true", seen, just)
	}
}
