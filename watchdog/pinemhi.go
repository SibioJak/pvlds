package main

// PINemHi watcher management (PINEMHI2 Part B): the watchdog
// carries the "we started it / adopted it" facts because the
// launcher exits at every table hand-off - only this resident
// process spans a whole PVLDS session.
//
// THE LAW (Chris's quit reasons are the spec): a toggle in the
// launcher config, mirrored into the contract as pinemhi_manage,
// default OFF. Off = the watcher process is never touched.
// On = the watcher lives strictly inside PVLDS's open hours:
//   - started at session start if it is not already running,
//   - left alone across table hand-offs (nothing here keys on
//     session state at all - the duty runs on every tick),
//   - closed at TRUE exit only: every watchdog stand-down path
//     returns from main(), and the deferred close below is
//     registered right after the single-instance lock is held,
//     so disarm, contract-gone, stale watch and the loop cap
//     all pass through it.
// ADOPT-DON'T-DUPLICATE: a watcher already running when the
// duty first looks is adopted - used, and NEVER closed by
// PVLDS. Only a watcher PVLDS started is closed by PVLDS.
// The ownership facts (pid + state) live in the contract, so
// a watchdog killed mid-session leaves them behind: the next
// watchdog reads state="started" with a live pid and does not
// stack a second watcher.
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

// closePinemhiWatcher is the deferred TRUE-exit duty, registered
// in main() immediately after the single-instance lock is held
// so every return path out of main passes through it. It
// re-reads the contract at exit time (the on-disk facts are the
// session's truth, not any tick's snapshot), and closes only
// what pinemhiShouldClose allows: the watcher PVLDS started.
// The close is graceful first - the watcher's windows are asked
// to close - with a brief grace, then a terminate if it is
// still alive. Each step is logged in plain words.
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
	logf("watchdog: pinemhi: exit close - closing the watcher PVLDS started (pid %d)", pid)
	if closeProcessWindows(pid) {
		logf("watchdog: pinemhi: exit close - asked the watcher's windows to close (pid %d)", pid)
	}
	// Brief grace for the graceful close to land (~1.5s max).
	for i := 0; i < 10; i++ {
		if !processAlive(pid) {
			logf("watchdog: pinemhi: exit close - watcher pid %d closed gracefully", pid)
			return
		}
		time.Sleep(150 * time.Millisecond)
	}
	logf("watchdog: pinemhi: exit close - watcher pid %d still alive after the grace; terminating it", pid)
	if terminateProcess(pid) {
		logf("watchdog: pinemhi: exit close - watcher pid %d terminated", pid)
	} else {
		logf("watchdog: pinemhi: exit close - could not terminate watcher pid %d; leaving it", pid)
	}
}
