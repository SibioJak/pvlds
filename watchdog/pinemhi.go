package main

// PINemHi watcher management (PINEMHI2 Part B): the watchdog
// carries the "we started it / adopted it" facts because the
// launcher exits at every table hand-off - only this resident
// process spans a whole PVLDS session.
//
// THE LAW (WATCHERLIFE, Chris's ruling 2026-11-08, a field
// defect): the managed watcher exists ONLY while a play session
// is live or in its extraction tail. It is never running while
// the app idles - not in the room, not on the desk, not at boot.
// The defect: with PVLDS open on the desk, the watcher's GLOBAL
// hotkeys (PINemHi registers them system-wide, by its own
// design) stayed live during ordinary desktop file work and a
// stray keystroke tripped a challenge start. PINemHi's hotkeys
// are not PVLDS's to change - the watcher's LIFETIME is the only
// lever, and it now belongs to the session:
//   - management is a toggle in the launcher config, mirrored
//     into the contract as pinemhi_manage, default OFF. Off =
//     the watcher process is never touched.
//   - the watcher starts when a table session starts (the
//     contract's session lifecycle: loading/live) if it is not
//     already running, and is left alone across table hand-offs
//     inside that life,
//   - when the session ends, the watcher stays up for the
//     extraction tail (pinemhiTailSeconds) - it extracts the
//     score from nvram at/after game end, and an exit that raced
//     extraction once left an empty personal file - then a
//     PVLDS-started watcher is closed and ownership cleared.
//     A new session starting inside the tail keeps it up: no
//     close/reopen churn.
//   - at TRUE app exit during a session or tail, the deferred
//     close below still closes a PVLDS-started watcher: every
//     watchdog stand-down path returns from main(), and the
//     deferred close is registered right after the single-
//     instance lock is held, so disarm, contract-gone, stale
//     watch and the loop cap all pass through it.
// ADOPT-DON'T-DUPLICATE: a watcher already running when a
// session starts is adopted - used, and NEVER closed by PVLDS.
// Only a watcher PVLDS started is closed by PVLDS. The tail-end
// close clears an adopted watcher's ownership RECORD only; the
// process itself is left running, always.
// The ownership facts (pid + state) live in the contract, so
// a watchdog killed mid-session leaves them behind: the next
// watchdog reads state="started" with a live pid and does not
// stack a second watcher. (At idle, though, that leftover now
// reads as end-of-life and is closed - the watcher may not
// squat outside a session just because its watchdog died.)
//
// The DECISIONS are pure and unit-tested (pinemhi_test.go);
// the tick duty and the exit close in main.go / below are the
// thin platform shell around them.

import (
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// pinemhiExeName is the watcher binary's file name inside the
// PINemHi folder (the launcher mirrors the resolved folder into
// the contract; the exe name itself is PINemHi's own).
const pinemhiExeName = "pinemhi_rom_monitor.exe"

// pinemhiAction is what one duty tick decided.
type pinemhiAction int

const (
	pinemhiNone  pinemhiAction = iota
	pinemhiStart               // no watcher running: start it, own it
	pinemhiAdopt               // a watcher is already running: adopt it, never close it
)

// pinemhiDecide is the start/adopt decision. It only ever acts
// from the un-owned state: once the contract carries "started"
// or "adopted", the session's fact is settled and no tick
// re-decides it (a started watcher that later dies is handled
// by the clear-and-re-decide path in the tick duty, which
// returns the state to "" first).
func pinemhiDecide(manage bool, state string, running bool) pinemhiAction {
	if !manage || state != "" {
		return pinemhiNone
	}
	if running {
		return pinemhiAdopt
	}
	return pinemhiStart
}

// pinemhiTailSeconds is the extraction tail: how long the
// watcher stays up after the session's last active tick. The
// watcher extracts the score from nvram at/after game end, and
// the field record holds one empty personal file from an exit
// that raced extraction - so the close waits. 90 s: the brief's
// floor was 60 ("when in doubt, longer"); no dossier holds a
// measured extraction lag, and the successful field submissions
// all completed while the watcher simply stayed up. The cost
// side is bounded: hotkey exposure ends a minute and a half
// after the table, not after hours of desk idling.
const pinemhiTailSeconds int64 = 90

// pinemhiTail resolves the tail length. The bench seam
// (PVLDS_PINEMHI_TAIL_SECONDS, same family as PVLDS_PINEMHI_NC)
// lets the smoke run the tail legs in seconds; production never
// sets it and always gets the constant.
func pinemhiTail() int64 {
	if v := os.Getenv("PVLDS_PINEMHI_TAIL_SECONDS"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil && n >= 0 {
			return n
		}
	}
	return pinemhiTailSeconds
}

// pinemhiLifetime is the session/tail tracker: fed the
// contract's sessionActive and the tick's clock, it answers the
// only question the duty asks - should the watcher be up on this
// tick? Pure; unit-tested (pinemhi_test.go).
type pinemhiLifetime struct {
	inSession bool  // the previous tick saw a live session
	tailUntil int64 // unix seconds the tail runs to; 0 = no tail
}

// wanted reports whether the watcher should exist on this tick:
// inside a session, always; on the first inactive tick after a
// session, the tail starts; inside the tail, still wanted; past
// it, not. A session starting inside the tail cancels the tail
// (the watcher simply stays up - no close/reopen churn).
func (l *pinemhiLifetime) wanted(sessionActive bool, now int64, tail int64) bool {
	if sessionActive {
		l.inSession = true
		l.tailUntil = 0
		return true
	}
	if l.inSession {
		l.inSession = false
		l.tailUntil = now + tail
	}
	return l.tailUntil != 0 && now < l.tailUntil
}

// pinemhiStartLatch is the failed-start latch (WATCHERFIX). Field
// evidence (2026-11-08): an unstartable watcher (its exe demanded
// elevation) was retried on every 400 ms tick for six minutes -
// hundreds of identical "could not start" log lines. The law now:
// a failed start logs ONCE per spell and latches; no further start
// is attempted until the spell ends. The spell is keyed on the
// contract's manage/folder values: sync() re-arms the latch when
// either changes (a settings toggle or a folder edit is a new
// spell), and a new watchdog process starts with a fresh latch by
// construction. Adoption checks are NOT latched - the duty may
// keep noticing a watcher that appears by other means; only the
// failed START is silenced.
type pinemhiStartLatch struct {
	manage bool   // the spell's key: the manage value it belongs to
	folder string // the spell's key: the folder value it belongs to
	failed bool   // a start has failed inside this spell
}

// sync aligns the latch with the contract's current manage/folder
// values. Any change ends the spell: the failure is forgotten and
// the next start decision may attempt (and log) once more.
func (l *pinemhiStartLatch) sync(manage bool, folder string) {
	if l.manage != manage || l.folder != folder {
		l.manage = manage
		l.folder = folder
		l.failed = false
	}
}

// mayStart reports whether a start attempt is allowed in this
// spell (false once a start has failed and latched).
func (l *pinemhiStartLatch) mayStart() bool { return !l.failed }

// recordFailure latches the spell after a failed start.
func (l *pinemhiStartLatch) recordFailure() { l.failed = true }

// pinemhiShouldClose is the exit decision: PVLDS closes only a
// watcher it started, and only when management is on. The NC
// seam (PVLDS_PINEMHI_NC=closeadopted) deliberately breaks the
// law - it ignores the ownership state, so an adopted watcher
// gets closed too - and the integration smoke's adoption leg
// must fail by name under it.
func pinemhiShouldClose(manage bool, state string) bool {
	if os.Getenv("PVLDS_PINEMHI_NC") == "closeadopted" {
		return manage
	}
	return manage && state == "started"
}

// pinemhiExePath resolves the watcher exe inside the mirrored
// folder ("" when no folder was mirrored).
func pinemhiExePath(folder string) string {
	if folder == "" {
		return ""
	}
	return filepath.Join(folder, pinemhiExeName)
}

func pinemhiFileExists(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// closePinemhiProcess closes ONE watcher process PVLDS started:
// graceful first - the watcher's windows are asked to close -
// with a brief grace, then a terminate if it is still alive.
// `why` names the close in the log ("exit close" at TRUE exit,
// "session over" at the tail's end); each step is logged in
// plain words.
func closePinemhiProcess(pid int, why string) {
	logf("watchdog: pinemhi: %s - closing the watcher PVLDS started (pid %d)", why, pid)
	if closeProcessWindows(pid) {
		logf("watchdog: pinemhi: %s - asked the watcher's windows to close (pid %d)", why, pid)
	}
	// Brief grace for the graceful close to land (~1.5s max).
	for i := 0; i < 10; i++ {
		if !processAlive(pid) {
			logf("watchdog: pinemhi: %s - watcher pid %d closed gracefully", why, pid)
			return
		}
		time.Sleep(150 * time.Millisecond)
	}
	logf("watchdog: pinemhi: %s - watcher pid %d still alive after the grace; terminating it", why, pid)
	if terminateProcess(pid) {
		logf("watchdog: pinemhi: %s - watcher pid %d terminated", why, pid)
	} else {
		logf("watchdog: pinemhi: %s - could not terminate watcher pid %d; leaving it", why, pid)
	}
}

// closePinemhiWatcher is the deferred TRUE-exit duty, registered
// in main() immediately after the single-instance lock is held
// so every return path out of main passes through it. It
// re-reads the contract at exit time (the on-disk facts are the
// session's truth, not any tick's snapshot), and closes only
// what pinemhiShouldClose allows: the watcher PVLDS started.
// Under WATCHERLIFE this fires only when the exit lands inside
// a session or its tail - at idle the tail-end close has
// already run and cleared the ownership, so this is a no-op.
func closePinemhiWatcher() {
	c, err := readContract()
	if err != nil {
		return // no contract to read: nothing was ever mirrored, nothing to close
	}
	if !pinemhiShouldClose(c.PinemhiManage, c.PinemhiWatcherState) {
		return
	}
	pid := c.PinemhiWatcherPID
	if pid <= 0 {
		logf("watchdog: pinemhi: exit close - ownership says started but no pid is recorded; nothing to close")
		return
	}
	if !processAlive(pid) {
		logf("watchdog: pinemhi: exit close - the watcher PVLDS started (pid %d) is already gone", pid)
		return
	}
	closePinemhiProcess(pid, "exit close")
}
