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
// /proc exe links on Linux). Logging only - nothing decides
// on this fact.

import "strings"

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
type b2sSighting struct {
	sessionID int
	known     bool // an observation has been folded in for this session
	present   bool
}

func (t *b2sSighting) observe(sessionID int, present bool) (changed bool) {
	if sessionID != t.sessionID {
		t.sessionID = sessionID
		t.known = false
	}
	if t.known && t.present == present {
		return false
	}
	t.known = true
	t.present = present
	return true
}
