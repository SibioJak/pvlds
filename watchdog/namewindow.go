package main

// FIX154: the name window - the B2S table-name feed.
//
// Why this exists (convicted in the field 2026-11-21,
// the full record in the FIX154 dossier): a script-
// driven EM table's backglass lives or dies on the
// table FILENAME reaching the B2S server. The chain
// is: the table script names the table only by its
// B2S name (no filename); the B2S DLL inside VPX
// holds the filename in B2SData.TableFileName and
// passes it to B2SBackglassServerEXE as its first
// argument; the EXE loads "<filename>.directb2s".
// When the filename is EMPTY the EXE searches for a
// glass literally named ".directb2s", finds nothing,
// and ends inside its constructor - silently, because
// its startup-error dialog defaults off. That silent
// death was the eleven-round B2S hunt.
//
// The DLL's one fallback for an empty filename is a
// scrape: at startup it enumerates the desktop's
// visible top-level windows for one titled
// "Visual Pinball - [<filename stem>]" - the old VPX
// editor's title - and takes the bracketed name. On
// VPX 10.8 the editor's title is just "Visual
// Pinball", so the scrape never fires on a modern
// rig; and EM tables get no rescue from the second
// fallback (the game name) because their script
// chain deliberately clears it. Editor launches live
// (the name is supplied inside the editor's own
// process); any separate-process launch - every
// front end, LaunchPin included - hands the server
// an empty name.
//
// The fix is to hold the window the scrape reads:
// while a launch is in flight, the watchdog keeps
// ONE tiny window titled exactly "Visual Pinball -
// [<launched table's stem>]". FIX154 raised it
// inside the cold spawn, before the watchdog fired
// the birth itself. FIX155 moves the trigger to the
// resident road (the launcher spawns VPX itself and
// stays open): the contract is armed BEFORE the
// spawn and carries the table's path, so the
// watchdog raises the window on the first tick it
// observes the new loading session - within one
// 400 ms poll of the arm, seconds before VPX's
// script initialises and the scrape runs. The DLL
// scrapes the real name, the EXE receives it, and
// the exact-name glass loads. Field proof
// (2026-11-21): a command-prompt window with that
// title left open during a LaunchPin launch of Big
// Chief - table loaded, B2S active. No table, B2S,
// or VPX file is touched anywhere in this design.
//
// This file is the platform-free half: the stem /
// title derivation, the window's bookkeeping, and
// the acting helpers over the two platform leaves
// (namewindow_windows.go / namewindow_linux.go /
// namewindow_other.go), held in variables so the
// lifecycle is unit-tested against a recording fake
// on every platform.

import (
	"fmt"
	"path"
	"strings"
	"time"
)

// nameWindowCap bounds the window's life when no B2S
// sighting ever lands (a ROM table, a table with no
// backglass, a load that wedges): the window is a
// launch aid, not furniture. The scale deliberately
// mirrors pendingTimeoutSec, the standing
// never-materialised bound.
const nameWindowCap = 120 * time.Second

// The platform leaves, as variables so the lifecycle
// below is unit-tested against a recording fake (the
// b2sSighting pattern: decisions here, acts at the
// leaves).
var (
	nameWindowCreate  = createNameWindow
	nameWindowDestroy = destroyNameWindow
)

// (FIX154 derived the stem from the cold spawn's
// game_args argv; FIX155's contract carries the
// table's path itself, and tableFileStem below is
// the one derivation both roads' facts flow through.)

// tableFileStem derives the stem from one table file
// path. Both separator spellings are read on any host
// (the paths are Windows paths; the watchdog's tests
// run on Linux). Pure; unit-tested.
func tableFileStem(p string) (string, bool) {
	base := path.Base(strings.ReplaceAll(p, "\\", "/"))
	if len(base) <= len(".vpx") || !strings.HasSuffix(strings.ToLower(base), ".vpx") {
		return "", false
	}
	return base[:len(base)-len(".vpx")], true
}

// nameWindowTitle is the exact window title the B2S
// scrape accepts: the old editor's shape, bracketed
// stem and all. Pure; unit-tested.
func nameWindowTitle(stem string) string {
	return "Visual Pinball - [" + stem + "]"
}

// nameWindowTitleForPath is the resident trigger's
// one question: what should this launch's window be
// titled - and does the contract's table path name
// a table at all?
func nameWindowTitleForPath(tablePath string) (string, bool) {
	stem, ok := tableFileStem(tablePath)
	if !ok {
		return "", false
	}
	return nameWindowTitle(stem), true
}

// nameWindowState is the one window's bookkeeping:
// which session it serves, the handle WE created
// (the only handle ever destroyed), its title, and
// the moment it went up (the cap's clock).
type nameWindowState struct {
	sessionID int
	hwnd      uintptr
	title     string
	armedAt   time.Time
}

func (w *nameWindowState) up() bool { return w.hwnd != 0 }

// judge is the per-tick expiry judgement, fed the
// contract's session facts and the session's latched
// B2S sighting. It answers the drop reason, or ""
// for "stays up". The order matters: a newer session
// supersedes before any of the old session's facts
// are read against the window. Pure; unit-tested.
func (w *nameWindowState) judge(sessionID int, state string, b2sSeen bool, now time.Time) string {
	if !w.up() {
		return ""
	}
	switch {
	case sessionID != w.sessionID:
		return fmt.Sprintf("superseded by session %d", sessionID)
	case b2sSeen:
		// The name has been consumed: the scrape
		// precedes the EXE's spawn, so a sighted
		// server is proof the feed did its work.
		return "b2s sighted"
	case state != "loading" && state != "live":
		return fmt.Sprintf("the session left the launch (state %q)", state)
	case now.Sub(w.armedAt) >= nameWindowCap:
		return "no b2s sighting inside 120s - the cap"
	}
	return ""
}

// clear forgets the window and hands back what the
// caller must destroy - the recorded handle, never
// any other.
func (w *nameWindowState) clear() (hwnd uintptr, title string, sessionID int, ok bool) {
	if !w.up() {
		return 0, "", 0, false
	}
	hwnd, title, sessionID = w.hwnd, w.title, w.sessionID
	*w = nameWindowState{}
	return hwnd, title, sessionID, true
}

// sessionNameWindow is the duty's one window (the
// main loop and the cold-spawn machine are the same
// goroutine's work; the leaves' own threading is
// theirs).
var sessionNameWindow nameWindowState

// raiseNameWindow creates the session's name window
// and logs the up edge. One window at a time: a
// window still up comes down first, under the
// replacement's reason. A creation failure is logged
// and the launch goes ahead without the feed - the
// window is an assist, never a gate.
func raiseNameWindow(sessionID int, title string, now time.Time) {
	if sessionNameWindow.up() {
		dropNameWindow(fmt.Sprintf("replaced by session %d", sessionID))
	}
	hwnd := nameWindowCreate(title)
	if hwnd == 0 {
		logf("watchdog: session %d: name window: could not create the window titled %q - the launch goes ahead without the name feed", sessionID, title)
		return
	}
	sessionNameWindow = nameWindowState{sessionID: sessionID, hwnd: hwnd, title: title, armedAt: now}
	logf("watchdog: session %d: name window up: %s", sessionID, title)
}

// dropNameWindow destroys the window if one is up,
// logging the down edge with its reason. Silent when
// nothing is up, so every stand-down path can call
// it unconditionally.
func dropNameWindow(reason string) {
	hwnd, title, sid, ok := sessionNameWindow.clear()
	if !ok {
		return
	}
	nameWindowDestroy(hwnd)
	logf("watchdog: session %d: name window down: %s (%s)", sid, reason, title)
}

// judgeNameWindow runs the expiry judgement for one
// main-loop tick: the contract's session facts plus
// the session's latched B2S sighting (computed by
// the caller off the sighting tracker, so a previous
// session's latch is never read as this one's).
func judgeNameWindow(c *Contract, b2sSeen bool, now time.Time) {
	if reason := sessionNameWindow.judge(c.SessionID, c.SessionState, b2sSeen, now); reason != "" {
		dropNameWindow(reason)
	}
}

// nameFeedSession is the session the resident
// trigger below has already made its decision for
// (0 = none yet): one feed decision per session, so
// a session is never re-judged tick after tick.
var nameFeedSession int

// observeNameFeed is FIX155's resident trigger: the
// main loop feeds it every tick's contract, and the
// first tick that observes a NEW armed loading
// session carrying a table path raises that
// session's name window. The contract is armed
// before the spawn, so the raise lands within one
// poll of the arm - ahead of the game's birth, and
// seconds ahead of the script init that runs the
// scrape. A contract carrying no table path (an
// older launcher's session) gets no window and no
// log line; a path naming no .vpx file logs the
// feed's own line and the launch goes ahead - the
// feed is an assist, never a gate. (In FIX155's
// first phase a session still carrying the cold
// spawn's marker is skipped: that road raises its
// window at its own firing, exactly as FIX154 left
// it. The marker's removal retires the exception.)
func observeNameFeed(c *Contract, now time.Time) {
	if !c.Armed || c.SessionState != "loading" || c.SessionID == 0 || c.SessionID == nameFeedSession || c.SpawnPending {
		return
	}
	nameFeedSession = c.SessionID
	if c.GameTablePath == "" {
		return
	}
	title, ok := nameWindowTitleForPath(c.GameTablePath)
	if !ok {
		logf("watchdog: session %d: name window: the launch names no table file (%q) - no window raised", c.SessionID, c.GameTablePath)
		return
	}
	raiseNameWindow(c.SessionID, title, now)
}
