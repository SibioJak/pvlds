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
// FIX113 (2026-11-12) — a SECOND signature, for VPX builds
// whose player exposes none of the above (the 10.8.1 BGFX dev
// build in the field evidence, pvlds-fix113/droscoe_
// watchdog.log: five sessions, the player pid owning ONLY
// IME + MSCTFIME UI + a "VPPlayer" window 1920x1080 visible,
// so the classic signature never fired and the resident
// launcher sat at "Loading..." forever). On those builds the
// VPPlayer player window IS the render surface: there is no
// separate runtime window to wait for. The law (from the
// field forensics above): a raw VPPlayer sighting is NOT
// runtime evidence — the sighting gate stamps it ~1s after
// spawn, and a stamp there would reopen the exact 2-3s VR
// desktop gap this gate exists to close. So the second
// signature is VPPlayer + PERSISTENCE: a VPPlayer-class,
// visible, full-area window of the session pid appearing in
// runtimeVPPlayerStreak consecutive polls before it counts.
// GL behaviour cannot change: the GL build's player window
// never carries the VPPlayer class at all (sighting.go's
// field forensics — that absence is why the sighting gate is
// class-independent), so this signature simply never counts
// there and the classic signature stamps exactly as before.
// The streak only wins on builds whose player exposes the
// VPPlayer window and nothing else.
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

// isVPPlayerRuntimeWindow decides whether ONE observation is
// the player window in its FIX113 runtime form: the VPPlayer
// class the sighting gate uses, VISIBLE, and at least the
// player area floor. The class alone is never evidence — the
// sighting gate stamps that shape ~1s after spawn (see the
// header); only the streak in runtimeGate turns it into
// runtime evidence.
func isVPPlayerRuntimeWindow(w windowObs) bool {
	return w.class == playerWindowClass && w.visible &&
		w.area() >= playerWindowMinArea
}

// classifyVPPlayer reports whether an observation set holds
// the player window in its runtime form.
func classifyVPPlayer(obs []windowObs) bool {
	for _, w := range obs {
		if isVPPlayerRuntimeWindow(w) {
			return true
		}
	}
	return false
}

// Which signature stamped a session's runtime. The classic
// signature keeps the legacy stamp line byte-identical; the
// VPPlayer-persistence stamp names itself in the log.
const (
	runtimeRuleClassic  = "classic"
	runtimeRuleVPPlayer = "VPPlayer persistence"
)

// runtimeVPPlayerStreak is the consecutive-poll persistence a
// VPPlayer-only runtime must show before the gate stamps —
// long enough that a just-started player (sighting shape,
// ~1s after spawn) can never complete it, short enough that a
// BGFX-build load still hands off in a few seconds. Polls are
// the main loop's 400 ms tick: 8 polls ≈ 3.2 s, and the
// launcher's own 1.5 s settle rides on top of the stamp.
const runtimeVPPlayerStreak = 8

// runtimeGate is the per-session latch over the two
// signatures: once a session's runtime has been seen it has
// been seen (the stamp the contract carries), and the first
// signature to fire owns the stamp. Safe for concurrent use.
type runtimeGate struct {
	mu        sync.Mutex
	sessionID int
	seen      bool
	rule      string
	streak    int
}

// observe folds one poll observation in and reports whether
// the session's runtime counts as seen (latched), plus whether
// THIS observation is the one that first saw it. classic
// stamps immediately, exactly as before; vpPlayer counts a
// streak and stamps when it reaches runtimeVPPlayerStreak; a
// poll carrying neither signature resets the streak. A poll
// carrying both stamps classic.
func (g *runtimeGate) observe(sessionID int, classic bool, vpPlayer bool) (seen bool, justSeen bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if sessionID != g.sessionID {
		g.sessionID = sessionID
		g.seen = false
		g.rule = ""
		g.streak = 0
	}
	if g.seen {
		return true, false
	}
	switch {
	case classic:
		g.seen = true
		g.rule = runtimeRuleClassic
		justSeen = true
	case vpPlayer:
		g.streak++
		if g.streak >= runtimeVPPlayerStreak {
			g.seen = true
			g.rule = runtimeRuleVPPlayer
			justSeen = true
		}
	default:
		g.streak = 0
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

// ruleFor reports which signature stamped the session's
// runtime ("" while unseen).
func (g *runtimeGate) ruleFor(sessionID int) string {
	g.mu.Lock()
	defer g.mu.Unlock()
	if sessionID != g.sessionID || !g.seen {
		return ""
	}
	return g.rule
}
