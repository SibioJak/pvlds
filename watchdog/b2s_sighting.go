package main

// FIX145: the B2S server process sighting. FIX142/FIX143
// established that under a LaunchPin launch the B2S server's
// WINDOWS never exist (zero HwndWrapper in every inventory) -
// but whether the server PROCESS (B2SBackglassServerEXE) ever
// starts was answerable only by a Task Manager glance during
// a field launch. This sighting closes that gap with the
// instrument already running: on every session tick (the same
// cadence the window inventories are gathered at), the
// watchdog records whether a B2SBackglassServerEXE process
// exists, logging ONLY when the fact changes - the first
// observation of a session included, so a field log answers
// "never started" vs "started but windowless" by itself.
//
// The name match is on the process image's base name, with or
// without the .exe suffix, case-insensitive (the platform
// leaves own the enumeration: Toolhelp snapshot on Windows,
// /proc exe links on Linux). Born logging-only; FIX149 gives
// the fact one consumer - the hand-off gate reads the
// continuous-presence stamp this tracker feeds (the launcher
// holds its exit until the server has held steady), while
// the sighting lines themselves stay exactly as they were.

import (
	"strings"
	"time"
)

// b2sServerImageName is the B2S backglass server's image
// base name (the .exe form is the Windows process name).
const b2sServerImageName = "B2SBackglassServerEXE"

// isB2SServerName reports whether a process image base name
// is the B2S server's, in either spelling. Pure; unit-tested.
func isB2SServerName(base string) bool {
	return sameProcessName(base, b2sServerImageName)
}

// sameProcessName compares two process image base names the
// way the sighting needs: case-insensitive, with a trailing
// ".exe" on either side ignored (the Windows process carries
// the suffix; a Linux namesake binary need not). Pure;
// unit-tested.
func sameProcessName(a string, b string) bool {
	trim := func(s string) string {
		return strings.TrimSuffix(strings.ToLower(s), ".exe")
	}
	return trim(a) == trim(b)
}

// b2sSighting is the per-session change tracker over the
// process-exists fact: observe folds one tick's fact in and
// reports whether the log should speak (the first
// observation of a session, and every change after it).
//
// FIX149: the tracker also carries the CONTINUOUS-presence
// clock the hand-off gate reads: presentSince is the moment
// the current unbroken run of presence began, reset to zero
// whenever the fact goes absent (and on every session
// change). The watchdog mirrors it into the contract as
// b2s_present_since_unix (main.go) - the pid-file precedent:
// a fact the watchdog measures, stamped where the resident
// launcher already polls.
type b2sSighting struct {
	sessionID    int
	known        bool // an observation has been folded in for this session
	present      bool
	presentSince time.Time // start of the current continuous presence; zero while absent
	stableNoted  bool      // noteStable has reported this presence run's stability crossing
}

func (t *b2sSighting) observe(sessionID int, present bool, now time.Time) (changed bool) {
	if sessionID != t.sessionID {
		t.sessionID = sessionID
		t.known = false
		t.present = false
		t.presentSince = time.Time{}
		t.stableNoted = false
	}
	if t.known && t.present == present {
		return false
	}
	t.known = true
	t.present = present
	if present {
		t.presentSince = now
	} else {
		t.presentSince = time.Time{}
	}
	t.stableNoted = false
	return true
}

// presentSinceUnix is the contract stamp for the current
// fact: the unix second the server's continuous presence
// began, or 0 while it is absent (or not yet observed).
func (t *b2sSighting) presentSinceUnix() int64 {
	if !t.known || !t.present || t.presentSince.IsZero() {
		return 0
	}
	return t.presentSince.Unix()
}

// noteStable reports true exactly once per continuous
// presence run: the first time the run's length reaches
// threshold. The watchdog logs that crossing (the moment
// the hand-off gate's stability condition first holds).
// The comparison is made in whole unix seconds - the same
// arithmetic the launcher judges from the published stamp -
// so this log line never lands after the release it
// predicts.
func (t *b2sSighting) noteStable(now time.Time, threshold time.Duration) bool {
	if !t.known || !t.present || t.presentSince.IsZero() || t.stableNoted {
		return false
	}
	if now.Unix()-t.presentSince.Unix() < int64(threshold/time.Second) {
		return false
	}
	t.stableNoted = true
	return true
}
