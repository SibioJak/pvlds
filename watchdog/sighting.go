package main

import "sync"

// Player-window sighting: the shared rule that decides whether
// the game process's PLAYER window counts as present, and whether
// it has been seen at all this session. The decision logic lives
// here (platform-free, unit-tested); the platform leaves
// (herd_windows.go / window_linux.go) only enumerate windows into
// windowObs snapshots and feed them through this gate.
//
// Why this exists (field forensics, Chris's rig, 2026-10-22): the
// old rule required a visible window of the game pid with Win32
// class exactly "VPPlayer". On his rig that test NEVER matched
// across whole sessions of live play - the contract's
// game_window_seen_unix stayed 0 - so the closer never armed and
// the exit arbitrator never opened: both exit gestures were inert
// while herding (pid-based, class-agnostic) found the game's
// window fine. Whatever class his VPX build's player window
// actually carries, it is not the one the vpinball source names.
//
// The new rule is class-INDEPENDENT, with one hard exception
// carried over from the faf0673 mid-load-kill lesson: the editor
// frame (class "VPinball") is up from app start, so it must NEVER
// count as the player. Everything else about a window is fair
// evidence:
//
//   - a "VPPlayer"-class window is the player, immediately (the
//     classic path, unchanged);
//   - any other visible window of the game pid whose class is NOT
//     the editor class and whose size is substantial (at least
//     ~320x240) is a player CANDIDATE; it counts as present only
//     once it has persisted across playerSightingStreak
//     consecutive poll observations, so a splash or helper window
//     flashing up during a load cannot stamp a sighting;
//   - the editor class never counts, at any size, ever.
//
// "Seen" latches per session (it stamps the contract's
// game_window_seen and arms the closer/arbitrator); "present" is
// per-observation and drops the moment no candidate is up, which
// is what lets the editor landing register as an exit.

// windowObs is one visible top-level window of the game process,
// as a platform leaf observed it.
type windowObs struct {
	class  string
	width  int64
	height int64
}

func (w windowObs) area() int64 { return w.width * w.height }

const (
	// The editor frame's Win32 class (closer.go has the vpinball
	// source citations). Excluded from candidacy unconditionally.
	editorWindowClass = "VPinball"
	// The player window's class in the vpinball source. Still the
	// fast path where a build actually uses it.
	playerWindowClass = "VPPlayer"
	// A non-editor window smaller than this is a tooltip, a
	// splash fragment, a helper - not a playfield.
	playerWindowMinArea = 320 * 240
	// Consecutive polls a class-independent candidate must
	// survive before it counts. The watchdog polls every ~400ms,
	// so this is under a second of persistence.
	playerSightingStreak = 2
)

// Sighting rules, named for the watchdog log: when a sighting
// stamps, the log says which rule stamped it - the field evidence
// that settles what Chris's player window really is.
const (
	sightRuleClassic   = "VPPlayer class"
	sightRuleClassFree = "class-independent"
)

// classifyPlayerCandidate decides whether one observation holds a
// player-window candidate, and by which rule. The classic class
// wins whenever it is present; otherwise any substantial
// non-editor window qualifies by the class-independent rule.
func classifyPlayerCandidate(obs []windowObs) (bool, string) {
	classFree := false
	for _, w := range obs {
		switch {
		case w.class == playerWindowClass:
			return true, sightRuleClassic
		case w.class != editorWindowClass && w.area() >= playerWindowMinArea:
			classFree = true
		}
	}
	if classFree {
		return true, sightRuleClassFree
	}
	return false, ""
}

// playerSighting is the per-session persistence gate over
// classifyPlayerCandidate. Safe for concurrent use: the main loop
// and the hold watch both take window snapshots.
type playerSighting struct {
	mu        sync.Mutex
	sessionID int
	streak    int    // consecutive observations holding a class-independent candidate
	sighted   bool   // latched: a sighting has stamped this session
	rule      string // the rule that stamped it
}

// observe folds one poll observation in and reports the filtered
// presence for THIS observation, plus whether this very
// observation is the one that stamped the session's sighting.
func (s *playerSighting) observe(sessionID int, candidate bool, rule string) (present bool, justSighted bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sessionID != s.sessionID {
		s.sessionID = sessionID
		s.streak = 0
		s.sighted = false
		s.rule = ""
	}
	if !candidate {
		s.streak = 0
		return false, false
	}
	if rule == sightRuleClassic {
		present = true
	} else {
		s.streak++
		present = s.streak >= playerSightingStreak
	}
	if present && !s.sighted {
		s.sighted = true
		s.rule = rule
		justSighted = true
	}
	return present, justSighted
}

// hasSighted reports the session's latched sighting and the rule
// that stamped it, without folding a new observation in. The
// contract stamp (main.go) reads this: the sighting it records is
// exactly the gate's, never a second, divergent test.
func (s *playerSighting) hasSighted(sessionID int) (bool, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sessionID != s.sessionID || !s.sighted {
		return false, ""
	}
	return true, s.rule
}
