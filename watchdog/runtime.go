package main

import (
	"strings"
	"sync"
)

// Table-runtime sighting: the shared rule that decides whether
// the game process's TABLE RUNTIME counts as up - the resident
// launcher's TRUE hand-off cue. The decision logic lives here
// (platform-free, unit-tested); the platform leaves feed it the
// same windowObs snapshots they feed the sighting gate
// (sighting.go).
//
// Why this exists (field forensics, Chris's rig, 2026-10-23):
// the hand-off cue used to be the player sighting, which stamps
// ~1s after spawn - off "CVFrame", VPX's EDITOR canvas window,
// present from app start. Real table loads take ~8s. The
// launcher exiting on the sighting left a 2-3s desktop gap in
// VR (the launcher's XR session gone, VPX's not yet up) and an
// unsettled foreground: one table won the focus lottery, the
// next came up with no sound and no controller until the player
// alt-tabbed to it. The runtime's own windows are the honest
// "the table is real now" evidence: in both field sessions the
// window set grew PinMAME, the B2S server, render surfaces and
// an SDL window that flips visible exactly when the player
// comes up, seconds after the editor canvas existed.
//
// The signature (pinned to those two sessions' inventories):
//   - "MAME" / "VPINMAMEEVENTWND": PinMAME, up while a ROM
//     table's runtime lives;
//   - "HwndWrapper[...]" (prefix): the B2S backglass server's
//     .NET windows;
//   - "SharpGLRenderWindow" / "NVOpenGLPbuffer": render
//     surfaces the runtime creates;
//   - "DIEmWin": the DirectInput helper the runtime spawns;
//   - "SDL_app" VISIBLE: VPX's SDL window exists (hidden) from
//     early on, but in both sessions it flipped
//     hidden -> visible exactly when the player came up - so
//     only the visible form counts.
//
// Never evidence: "CVFrame" (the editor canvas, the old cue's
// false friend), "VPinball" (the editor frame itself), the
// "#32770" loading dialog, and the editor's furniture
// (ComboLBox, IME, tooltips). No streak/persistence: these are
// process-lifetime runtime windows, not flashes, and the
// launcher adds its own settle on top of the stamp.
//
// "Seen" latches per session and stamps the contract's
// runtime_seen (sighting-style): the launcher polls it as its
// hand-off cue, replacing the sighting in that one role. The
// sighting stamp keeps its other roles (the exit detector's
// arming precondition, closer.go).

// runtimeWindowClasses is the class-exact half of the signature.
var runtimeWindowClasses = map[string]bool{
	"MAME":                true,
	"VPINMAMEEVENTWND":    true,
	"SharpGLRenderWindow": true,
	"NVOpenGLPbuffer":     true,
	"DIEmWin":             true,
}

// sdlWindowClass is VPX's SDL window class: runtime evidence
// only in its VISIBLE form (see the file header).
const sdlWindowClass = "SDL_app"

// b2sWindowClassPrefix opens every B2S server window class
// ("HwndWrapper[DefaultDomain;;<guid>]").
const b2sWindowClassPrefix = "HwndWrapper"

// isRuntimeWindow decides whether ONE observation is a
// table-runtime window.
func isRuntimeWindow(w windowObs) bool {
	if runtimeWindowClasses[w.class] {
		return true
	}
	if strings.HasPrefix(w.class, b2sWindowClassPrefix) {
		return true
	}
	return w.class == sdlWindowClass && w.visible
}

// classifyRuntime reports whether an observation set holds any
// table-runtime window.
func classifyRuntime(obs []windowObs) bool {
	for _, w := range obs {
		if isRuntimeWindow(w) {
			return true
		}
	}
	return false
}

// runtimeGate is the per-session latch over classifyRuntime:
// once a session's runtime has been seen it has been seen (the
// stamp the contract carries). Safe for concurrent use.
type runtimeGate struct {
	mu        sync.Mutex
	sessionID int
	seen      bool
}

// observe folds one poll observation in and reports whether the
// session's runtime counts as seen (latched), plus whether THIS
// observation is the one that first saw it.
func (g *runtimeGate) observe(sessionID int, present bool) (seen bool, justSeen bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if sessionID != g.sessionID {
		g.sessionID = sessionID
		g.seen = false
	}
	if present && !g.seen {
		g.seen = true
		justSeen = true
	}
	return g.seen, justSeen
}

// hasSeen reports the session's latched runtime sighting
// without folding a new observation in - the contract stamp in
// main.go reads this, exactly as the sighting stamp reads its
// gate.
func (g *runtimeGate) hasSeen(sessionID int) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	return sessionID == g.sessionID && g.seen
}
