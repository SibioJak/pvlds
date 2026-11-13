package main

// The player target: ONE resolver that names THE window which
// owns input for the session's VPX build, shared by every
// focus duty (loading herding, the launch focus sequence, the
// live-session guard). Platform-free decision logic, unit-
// tested on Linux; the platform leaves only enumerate the game
// pid's windows into windowObs snapshots (handles included)
// and feed them here.
//
// Why this exists (FIX116, from the focus investigation): the
// three pre-FIX116 focus mechanisms each carried their own
// target rule, and all three were wrong for the BGFX build in
// the field (droscoe, Pico 4): FIX113 taught the sighting and
// runtime gates the BGFX "VPPlayer" player window, but the
// hand-off push targeted a visible SDL_app else the EDITOR,
// and the activation leaf knew only SDL_app - the launched
// pid owned neither class, so no code path ever raised his
// player window after hand-off, and his table came up with
// dead controls until he alt-tabbed. One resolver, ranked:
//
//  1. a VISIBLE SDL_app window - the GL build's input window;
//  2. a VISIBLE VPPlayer window at or above the sighting area
//     floor - the BGFX build's input window (the same shape
//     the runtime gate's second signature trusts);
//  3. a hidden SDL_app - the pre-FIX116 activation fallback
//     (VPX's SDL window exists hidden before it flips
//     visible), kept but ranked last of the named classes;
//  4. a class-independent candidate in the sighting gate's
//     sense: a substantial non-editor window that has
//     PERSISTED as the same handle across two consecutive
//     snapshots and is not a known helper/runtime class -
//     used only while ranks 1-3 are absent, and logged by
//     class when used, so the next unknown build self-names.
//
// Hard exclusions at every rank: the editor frame ("VPinball"
// - raising it mid-play was the herding-era poison, and its
// foreground is the exit detector's signal), the loading
// dialog ("#32770"), and the editor canvas ("CVFrame" - the
// sighting gate's false friend; it is editor furniture, not
// the player). Rank 4 additionally excludes the known helper
// and runtime-surface classes: a PinMAME window, a B2S
// window, a render surface or a tooltip holding the
// foreground is focus DRIFT to be corrected (the guard's
// game-family case), never the target itself.
//
// The resolver is stateful per session only for rank 4's
// persistence: the candidate handle and its consecutive-
// snapshot streak. Ranks 1-3 resolve statelessly from the
// current snapshot, and a better rank displaces a worse one
// the snapshot it appears in (a recreated player window -
// same class and pid, new handle - therefore re-resolves and
// the target-bookkeeping log names the change).

// Rank labels: the target-bookkeeping log line's wording, and
// the resolver tests' vocabulary.
const (
	targetWhyVisibleSDL   = "visible SDL window"
	targetWhyVisibleVP    = "visible VPPlayer window"
	targetWhyHiddenSDL    = "hidden SDL window (fallback)"
	targetWhyClassFree    = "class-independent candidate"
	targetWhyNone         = ""
	targetCandidateStreak = 2 // consecutive snapshots a rank-4 candidate handle must persist
)

// rank4ExcludedClasses are the classes that can never be the
// rank-4 class-independent candidate: the hard exclusions
// above plus the game family's helpers and runtime surfaces.
// (Ranks 1-3 name their classes exactly, so this list is only
// consulted for rank 4.)
var rank4ExcludedClasses = map[string]bool{
	editorWindowClass:     true, // the editor frame
	loadDialogClass:       true, // the loading dialog
	"CVFrame":             true, // the editor canvas
	"MAME":                true, // PinMAME's window
	"VPINMAMEEVENTWND":    true, // PinMAME's event window
	"DIEmWin":             true, // the runtime's DirectInput helper
	"SharpGLRenderWindow": true, // a render surface
	"NVOpenGLPbuffer":     true, // a render surface
	"IME":                 true,
	"MSCTFIME UI":         true,
	"tooltips_class32":    true,
}

// rank4Candidate reports whether one observation could be the
// rank-4 candidate: substantial, not an excluded class, and
// not a B2S companion window (its class carries the B2S
// prefix). Visibility is NOT required - the headset-bound
// player window has no desktop visibility (sighting.go's
// field law) - persistence is the guard instead.
func rank4Candidate(w windowObs) bool {
	if w.hwnd == 0 || w.area() < playerWindowMinArea {
		return false
	}
	if rank4ExcludedClasses[w.class] {
		return false
	}
	if len(w.class) >= len(b2sWindowClassPrefix) && w.class[:len(b2sWindowClassPrefix)] == b2sWindowClassPrefix {
		return false
	}
	return true
}

// targetResolver is the per-session resolver state: only
// rank 4's persistence bookkeeping. One instance lives in
// each platform leaf (beside playerSight / runtimeSeen) and
// is fed that leaf's snapshot each tick.
type targetResolver struct {
	sessionID int
	candHWND  uintptr // the rank-4 candidate handle being persisted
	candClass string
	streak    int // consecutive snapshots holding candHWND as a candidate
}

// resolve folds one snapshot of the game pid's window set in
// and returns the player target: its handle, its class, and
// the rank label that chose it (targetWhyNone + zero handle
// when the set holds no target at all).
func (r *targetResolver) resolve(sessionID int, obs []windowObs) (uintptr, string, string) {
	if sessionID != r.sessionID {
		r.sessionID = sessionID
		r.candHWND = 0
		r.candClass = ""
		r.streak = 0
	}
	var visSDL, visVP, hidSDL windowObs
	var haveVisSDL, haveVisVP, haveHidSDL bool
	var cand windowObs
	haveCand := false
	for _, w := range obs {
		if w.hwnd == 0 {
			continue
		}
		switch {
		case w.class == sdlWindowClass && w.visible:
			if !haveVisSDL {
				visSDL, haveVisSDL = w, true
			}
		case w.class == playerWindowClass && w.visible && w.area() >= playerWindowMinArea:
			if !haveVisVP {
				visVP, haveVisVP = w, true
			}
		case w.class == sdlWindowClass && !w.visible:
			if !haveHidSDL {
				hidSDL, haveHidSDL = w, true
			}
		}
		if !haveCand && rank4Candidate(w) {
			cand, haveCand = w, true
		}
	}
	// Rank-4 persistence bookkeeping runs every snapshot,
	// whatever rank wins: the streak must be honest when the
	// named classes vanish mid-load.
	if haveCand {
		if cand.hwnd == r.candHWND {
			r.streak++
		} else {
			r.candHWND = cand.hwnd
			r.candClass = cand.class
			r.streak = 1
		}
	} else {
		r.candHWND = 0
		r.candClass = ""
		r.streak = 0
	}
	switch {
	case haveVisSDL:
		return visSDL.hwnd, visSDL.class, targetWhyVisibleSDL
	case haveVisVP:
		return visVP.hwnd, visVP.class, targetWhyVisibleVP
	case haveHidSDL:
		return hidSDL.hwnd, hidSDL.class, targetWhyHiddenSDL
	case haveCand && r.streak >= targetCandidateStreak:
		return cand.hwnd, cand.class, targetWhyClassFree
	}
	return 0, "", targetWhyNone
}
