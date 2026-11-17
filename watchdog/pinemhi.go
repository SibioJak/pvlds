package main

// PINemHi watcher management (PINEMHI2 Part B): the watchdog
// carries the "we started it / adopted it" facts because the
// launcher exits at every table hand-off - only this resident
// process spans a whole PVLDS session.
//
// THE LAW (APPRUN, Chris's ruling 2026-11-17, replacing
// WATCHERLIFE 2026-11-08): with management ON, the watcher
// starts - or is adopted, if one is already running - when the
// FIRST table session starts, and then stays up for the WHOLE
// APP RUN: across tables, in the room, at the desk. There is
// no extraction tail and no table-exit close. At TRUE APP EXIT
// the watcher is closed - started OR adopted alike: management
// ON means the app owns the watcher's lifetime for that run.
// Management OFF still means the watcher is never touched.
//
// Why the law changed (field evidence, 2026-11-16/17): under
// the session-bound law, a Sorcerer score (~4M) played through
// the app was never extracted by PINemHi; the same table with
// an always-up watcher (started by hand before the app,
// adopted by it) logged fine (2,252,640). The session-bound
// lifetime breaks extraction; an app-run-long watcher does
// not. And the old adopt-never-close rule let an adopted
// watcher outlive the app and eat keystrokes at the desktop
// (PINemHi registers its hotkeys system-wide) - the very harm
// the 2026-11-08 law was written to stop, arriving by the
// other door. Inside the app nobody is typing prose, so the
// only close the law needs is the app-exit one - and it now
// covers adopted watchers too.
//
// TRUE APP EXIT, as this process can know it: the deferred
// close below is registered right after the single-instance
// lock is held, so it fires on every stand-down path - and
// every stand-down path means the app is gone. Disarm is
// written only by a launcher that quits in the same breath
// (room Exit, window close, hold exit - launch_service.gd:
// "Exit is the only disarm, and it quits the app in the same
// breath"); the hold-exit death path pairs with the resident
// launcher's own exit; the loop cap retires a launcher that
// cannot stay alive; the stale watch requires the launcher
// process dead AND a day without check-in; and a contract
// file gone for good is a run whose bookkeeping has vanished
// (main.go debounces that read - the launcher's save is
// remove+rename, and one field poll landed in the gap on
// 2026-11-14 and closed a watcher mid-run; a save gap never
// survives the debounce, a deleted contract always does).
// The desk sojourns (boot desk, in-room SETUP) never disarm
// and never stand this process down - the run latch below is
// what carries the watcher across them, and across watchdog
// generations: the ownership facts live in the contract, so
// a fresh watchdog reads started/adopted with a live pid and
// simply leaves the watcher up until its own stand-down.
//
// The exit close verifies before it closes: the recorded pid
// must BE the watcher (present among the pids of the watcher
// exe in the contract's folder). A stale record - a crashed
// run's leftover whose pid the OS has since handed to a
// stranger - is skipped and logged, never closed. When the
// contract names no folder there is nothing to verify
// against, and the recorded pid is taken on faith, as before.
//
// The DECISIONS are pure and unit-tested (pinemhi_test.go);
// the tick duty and the exit close in main.go / below are the
// thin platform shell around them.

import (
	"os"
	"path/filepath"
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
	pinemhiAdopt               // a watcher is already running: adopt it (the app closes it at exit, like its own)
)

// pinemhiDecide is the start/adopt decision. It only ever acts
// from the un-owned state: once the contract carries "started"
// or "adopted", the run's fact is settled and no tick
// re-decides it (a watcher that later dies is handled by the
// clear-and-re-decide path in the tick duty, which returns the
// state to "" first).
func pinemhiDecide(manage bool, state string, running bool) pinemhiAction {
	if !manage || state != "" {
		return pinemhiNone
	}
	if running {
		return pinemhiAdopt
	}
	return pinemhiStart
}

// pinemhiRunLatch is the APPRUN lifetime: fed the contract's
// sessionActive each tick, it answers the only question the
// duty asks - should the watcher be up on this tick? Before
// the run's first session: no. From that session on: yes, for
// the rest of the run - across table exits, room idles and
// desk sojourns alike. There is no clock in it: nothing about
// the watcher's life is timed any more. Pure; unit-tested
// (pinemhi_test.go). The latch itself is per-watchdog-process;
// the run's longer memory is the contract's ownership state,
// which is why a fresh watchdog generation does not need the
// latch's history - a settled state in the contract means the
// watcher is already up and owned by the run.
type pinemhiRunLatch struct {
	latched bool // a session has made the watcher wanted in this run
}

// wanted reports whether the watcher should exist on this
// tick: inside the run's first session, and on every tick
// after it, wanted; before it, not.
func (l *pinemhiRunLatch) wanted(sessionActive bool) bool {
	if sessionActive {
		l.latched = true
	}
	return l.latched
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

// pinemhiShouldClose is the TRUE-exit decision (APPRUN): under
// management the app closes the watcher it ran with - one it
// started OR one it adopted; management owns the lifetime for
// the run either way. Off, or no watcher on record, closes
// nothing.
func pinemhiShouldClose(manage bool, state string) bool {
	return manage && (state == "started" || state == "adopted")
}

// pinemhiCloseAtSessionEnd is the negative control's whole
// mechanism - and, under APPRUN, a decision that must ALWAYS
// answer false: nothing closes when a table session ends; the
// watcher lives for the app run. The NC seam
// (PVLDS_PINEMHI_NC=closeearly) deliberately breaks the law:
// it answers true for an adopted watcher, the tick duty closes
// it at session end, and the integration smoke's no-early-close
// leg must fail by name under it. (The retired closeadopted
// seam broke the OLD law, under which adopted was unclosable
// even at exit; under APPRUN that is the law itself, so the
// seam moved to the law's new load-bearing wall.)
func pinemhiCloseAtSessionEnd(manage bool, state string) bool {
	if os.Getenv("PVLDS_PINEMHI_NC") == "closeearly" {
		return manage && state == "adopted"
	}
	return false
}

// pinemhiRecordVerified reports whether the contract's
// recorded watcher pid IS the watcher: present among the pids
// currently running the watcher exe (exePids, from
// findPIDsByExe on the contract folder's watcher exe). The
// exit close acts only on a verified record - a stale pid the
// OS has reused for a stranger process is not the watcher,
// however official the record looks. Pure; unit-tested.
func pinemhiRecordVerified(pid int, exePids []int) bool {
	if pid <= 0 {
		return false
	}
	for _, p := range exePids {
		if p == pid {
			return true
		}
	}
	return false
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

// closePinemhiProcess closes ONE watcher process: graceful
// first - the watcher's windows are asked to close - with a
// brief grace, then a terminate if it is still alive. `why`
// names the close in the log ("exit close" at TRUE exit, or
// the NC seam's "session over"); each step is logged in plain
// words.
func closePinemhiProcess(pid int, why string) {
	logf("watchdog: pinemhi: %s - closing the watcher (pid %d)", why, pid)
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

// closePinemhiWatcher is the deferred TRUE-exit duty,
// registered in main() immediately after the single-instance
// lock is held so every return path out of main passes through
// it - and every return path is a stand-down, which under
// APPRUN means the app is gone (see the header). It re-reads
// the contract at exit time (the on-disk facts are the run's
// truth, not any tick's snapshot), closes what
// pinemhiShouldClose allows - a started OR adopted watcher,
// under management - and only when the recorded pid verifies
// as the watcher itself (pinemhiRecordVerified). A record
// whose pid no longer verifies is left alone and logged: it
// names a dead watcher or a stranger, and neither is this
// process's to close.
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
		logf("watchdog: pinemhi: exit close - ownership says %s but no pid is recorded; nothing to close", c.PinemhiWatcherState)
		return
	}
	if !processAlive(pid) {
		logf("watchdog: pinemhi: exit close - the watcher (pid %d, %s) is already gone", pid, c.PinemhiWatcherState)
		return
	}
	if exe := pinemhiExePath(c.PinemhiFolder); exe != "" {
		if !pinemhiRecordVerified(pid, findPIDsByExe(exe)) {
			logf("watchdog: pinemhi: exit close - pid %d is alive but is not the watcher in %s; leaving it alone (stale record)", pid, c.PinemhiFolder)
			return
		}
	}
	closePinemhiProcess(pid, "exit close")
}
