package main

// FIX145 diagnostic seams: the instrumented build's two
// switches, read from a plain-text file `pvlds_diag.txt`
// BESIDE THE CONTRACT (the app data folder). Absent file =
// all defaults = 1.1.31 behaviour, exactly. The seams exist
// to split the two suspects the FIX145 desk audit (FINDINGS.md
// in the round's dossier) could not convict from the desk:
//
//   - SPAWN: how the game process is created. `helper` is the
//     1.1.31 road (the watchdog binary's pvlds-spawn mode, the
//     game born DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
//     on Windows / Setsid on Linux). `console` is the same
//     supervised helper with NO detach flags at all - the
//     closest reproduction of a cmd.exe prompt launch our
//     chain can make. `plain` is the app-side
//     OS.create_process road (1.1.30's shape; the helper is
//     never invoked - the app owns that flavour, this file
//     only names it for the logs).
//   - HERD: what the watchdog's focus family may do during a
//     session's load window. `on` is 1.1.31 behaviour. `held`
//     holds BOTH focus herding (herdTick) and the activation
//     cycle (cyclePlayerActivation, the focus sequence's
//     delivery excursion) from session start until 20 s after
//     the session's focus lock - the audit's timeline showed
//     the cycle firing at T+8 s, inside the seconds the table
//     script runs. Exit detection and the PINemHi duties are
//     NOT held; the focus sequence's assertions and plain
//     deliveries are not held either - only the two named
//     acts.
//
// The file is re-read at every watchdog boot, at every
// session start, at every assisted spawn (the helper reads
// the copy beside the pid file it was handed - the same
// folder), and at every app-side spawn, so a field edit
// between launches takes effect on the next launch without
// restarting anything. Unknown keys and values are ignored
// per key: a typo degrades that one seam to its default,
// never to a broken launch.

import (
	"os"
	"path/filepath"
	"strings"
)

// diagFileName is the seam file's name, beside the contract.
const diagFileName = "pvlds_diag.txt"

// The seam vocabularies. Anything outside them reads as the
// default for that seam.
const (
	diagSpawnHelper  = "helper"
	diagSpawnConsole = "console"
	diagSpawnPlain   = "plain"

	diagHerdOn   = "on"
	diagHerdHeld = "held"
)

// diagSettings is one read of the seam file: the two
// flavours plus whether a file was there at all (the log
// lines name the source, so a field log distinguishes
// "defaults in force" from "the file said so").
type diagSettings struct {
	Spawn    string
	Herd     string
	FromFile bool
}

// defaultDiagSettings is the absent-file read: 1.1.31
// behaviour on both seams.
func defaultDiagSettings() diagSettings {
	return diagSettings{Spawn: diagSpawnHelper, Herd: diagHerdOn}
}

// parseDiagSettings parses the seam file's text: one
// `key=value` per line, `#` comments, blank lines and
// unknown keys ignored, keys and values case-insensitive
// and whitespace-trimmed. An unrecognized value leaves that
// seam at its default. Pure; unit-tested (diag_test.go).
func parseDiagSettings(text string) diagSettings {
	d := defaultDiagSettings()
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.ToLower(strings.TrimSpace(key))
		value = strings.ToLower(strings.TrimSpace(value))
		switch key {
		case "spawn":
			switch value {
			case diagSpawnHelper, diagSpawnConsole, diagSpawnPlain:
				d.Spawn = value
			}
		case "herd":
			switch value {
			case diagHerdOn, diagHerdHeld:
				d.Herd = value
			}
		}
	}
	return d
}

// loadDiagSettings reads the seam file in dir (the contract's
// folder). Any read failure - above all, the file simply not
// being there - is the defaults, with FromFile=false.
func loadDiagSettings(dir string) diagSettings {
	data, err := os.ReadFile(filepath.Join(dir, diagFileName))
	if err != nil {
		return defaultDiagSettings()
	}
	d := parseDiagSettings(string(data))
	d.FromFile = true
	return d
}

// source names where the settings came from, for the log
// lines: the file, or the defaults an absent file means.
func (d diagSettings) source() string {
	if d.FromFile {
		return diagFileName
	}
	return "defaults (no " + diagFileName + ")"
}

// spawnDetached reports whether an assisted spawn of this
// flavour is born detached (own process group / session, no
// console inheritance) - the 1.1.31 creation shape - or as a
// normal child (the console flavour). The platform leaves map
// this one decision onto their flags: Windows CreationFlags
// DETACHED_PROCESS|CREATE_NEW_PROCESS_GROUP vs 0, Linux
// Setsid vs none (proc_windows.go / proc_linux.go). Pure;
// unit-tested.
func spawnDetached(spawnFlavour string) bool {
	return spawnFlavour != diagSpawnConsole
}

// herdHoldAfterLockMs is the tail of the herd=held window:
// the hold runs from session start until this long after the
// session's focus lock.
const herdHoldAfterLockMs = 20000

// herdHold tracks one session's herd=held window. The zero
// value is ready; noteSession starts a session's window,
// noteLock stamps its focus lock, and active answers whether
// the hold is in force at a moment. A session whose sequence
// never locks holds for the rest of its loading phase - the
// only phase herding ever runs in (herdingAllowed), so the
// distinction never reaches behaviour. Platform-free;
// unit-tested.
type herdHold struct {
	sessionID int
	lockMs    int64 // 0 = no lock observed yet this session
}

// noteSession starts (or restarts) the window for a session.
func (h *herdHold) noteSession(sessionID int) {
	if h.sessionID != sessionID {
		h.sessionID = sessionID
		h.lockMs = 0
	}
}

// noteLock records the session's focus-lock moment.
func (h *herdHold) noteLock(sessionID int, nowMs int64) {
	h.noteSession(sessionID)
	if h.lockMs == 0 {
		h.lockMs = nowMs
	}
}

// active reports whether the hold is in force: the herd seam
// is `held`, the session matches, and either no lock has
// landed yet or we are still inside the post-lock tail.
func (h *herdHold) active(d diagSettings, sessionID int, nowMs int64) bool {
	if d.Herd != diagHerdHeld || sessionID != h.sessionID {
		return false
	}
	if h.lockMs == 0 {
		return true
	}
	return nowMs-h.lockMs < herdHoldAfterLockMs
}

// diagSuppressCycle is the main loop's per-tick word to the
// Windows focus-delivery leaf (herd_windows.go): while the
// herd hold is in force, a delivery that would perform the
// activation cycle performs the plain rung-1 delivery
// instead - the delivery still happens (the sequence's
// bookkeeping stays honest), the excursion does not. Set by
// main.go on every session tick before the focus sequence
// runs; read only inside deliverPlayerFocus, which only the
// main loop calls. The Linux/other leaves have no cycle to
// suppress and ignore it.
var diagSuppressCycle bool
