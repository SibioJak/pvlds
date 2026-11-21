package main

// The cold spawn (FIX152): the watchdog fires a pending
// launch order itself, once the launcher is dead and the
// quiet has passed.
//
// Why: the field evidence of the B2S hunt. Every living
// launch had NO VR-session teardown in flight when VPX
// started (the editor, the command line, the FIX147
// spawner, the control where the app was closed seconds
// before the spawner ran). Every dying LaunchPin launch
// overlapped the spawn with the app's own teardown -
// 1.1.30's app died mid-load; FIX151's step-aside died
// at +0s with VPX's runtime arriving at +2s. Session
// 327 was the clean dead cell (step-aside + herd=off +
// no watcher start): the server blipped at +2s and died
// at +3s. So the product road no longer spawns from the
// app at all: a Play press writes the launch ORDER into
// the contract (spawn_pending + game_args + game_cwd,
// launch_service.gd) and the app quits unspawned. This
// machine is the firing side:
//
//	pending seen -> wait for the launcher's death ->
//	wait the settle delay -> fire the pvlds-spawn
//	supervised birth (this binary's own spawn mode -
//	the FIX148 shape verbatim) -> land the game's pid
//	in the contract and clear the marker.
//
// Every stage logs in plain lines, so a field log tells
// the cold-spawn story in its own words; the standing
// promotion (a loading session whose supervising
// launcher is gone) remains the bookkeeping that takes
// the session live once the game is up.
//
// Abandonment is a first-class outcome: a disarm, a
// superseding session, a consumed state, or the
// contract going away before the firing means NO spawn
// ever happens for the order, and the log says so. A
// hold-exit fired inside the pending window cancels
// the launch outright: the standing hold detector
// cannot fire there (its accrual needs a live, sighted
// game), so this machine feeds its own detector the
// same law - baseline-release arming, the same 1500 ms
// threshold - minus the game gates; a fire stamps the
// contract's hold_exit_fired_unix and disarms by the
// gesture, exactly the shape the gesture takes
// everywhere else, and the caller stands down.

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// defaultSpawnDelaySec is the cold spawn's settle delay
// when pvlds_diag.txt states no usable spawn_delay_sec:
// five seconds of quiet between the launcher's death
// and the spawn.
const defaultSpawnDelaySec = 5

// spawnReportTimeout mirrors the launcher's own report
// window (launch_service.gd's SPAWN_REPORT_TIMEOUT_MSEC):
// how long the firing side waits for the spawn helper
// to report the game's pid before the spawn is a
// failure.
const spawnReportTimeout = 10 * time.Second

// spawnPidFileName is the pid file the spawn helper
// reports through - the launcher's SPAWN_PID_FILE_NAME,
// in the contract's folder, deleted before every spawn
// and read once. A per-launch fact, never a record.
const spawnPidFileName = "pvlds_spawn_pid.txt"

// pendingStuckSec bounds a pending order whose launcher
// never dies. The cold app quits in the same breath as
// the order, so a live launcher past this bound is a
// wedge, not a wait: the order is cleared (logged) and
// the session's standing laws - the never-materialised
// relaunch - take the player from there. The bound
// mirrors pendingTimeoutSec's scale deliberately.
const pendingStuckSec = 120

// coldSpawnDelay decides the settle delay one diag read
// carries: the stated value when one stood there, the
// default otherwise. Pure; unit-tested.
func coldSpawnDelay(d diagState) (delay time.Duration, fromDiag bool) {
	if d.spawnDelaySet {
		return time.Duration(d.spawnDelaySec) * time.Second, true
	}
	return defaultSpawnDelaySec * time.Second, false
}

// coldSpawnOutcome is what one tick of the machine did,
// for the main loop's flow: the game duties key off it.
type coldSpawnOutcome int

const (
	// coldNone: no pending session is being tracked;
	// the tick's ordinary duties run untouched.
	coldNone coldSpawnOutcome = iota
	// coldWaiting: an order stands and the firing has
	// not happened; the session has no game yet, and
	// the game duties must stay inert this tick.
	coldWaiting
	// coldResolved: the order resolved this tick (the
	// spawn fired and landed, or a stuck order was
	// cleared); ordinary duties resume on the fresh
	// contract from the next tick.
	coldResolved
	// coldFailed: the spawn failed; the failure is
	// written into the contract and the caller
	// relaunches the launcher so it surfaces.
	coldFailed
	// coldStoodDown: a hold-exit inside the window
	// cancelled the launch and disarmed by the
	// gesture; the caller stands down.
	coldStoodDown
)

// coldSpawnState is the machine's memory across ticks:
// one pending session at a time, latched at the first
// tick the order is observed.
type coldSpawnState struct {
	sessionID      int // the pending session being tracked; 0 = none
	delay          time.Duration
	delayFromDiag  bool
	firstSeenAt    time.Time // the latch tick (the stuck bound's clock)
	launcherDeadAt time.Time // first tick the launcher read dead; zero = not yet
	helperPID      int       // the spawn helper in flight; 0 = not started
	helperStartAt  time.Time // the helper's start (the report window's clock)
	det            holdDetector
}

func (s *coldSpawnState) tracking() bool { return s.sessionID != 0 }

func (s *coldSpawnState) reset() { *s = coldSpawnState{} }

// noteAbandoned logs the end of a tracked order that
// never fired, in cold-spawn words, and clears the
// tracking. The stand-down paths (disarm, contract
// gone) call it before their own lines so the order's
// fate is never left implicit.
func (s *coldSpawnState) noteAbandoned(why string) {
	if !s.tracking() {
		return
	}
	logf("watchdog: session %d: cold spawn: abandoned - %s; never spawned", s.sessionID, why)
	s.reset()
}

// tick advances the machine one main-loop tick against
// the freshly read contract. cdir is the contract's
// folder (the diag file's and the pid file's home).
func (s *coldSpawnState) tick(c *Contract, cdir string, now time.Time) coldSpawnOutcome {
	pending := c.Armed && c.SessionState == "loading" && c.SpawnPending
	if s.tracking() && (!pending || c.SessionID != s.sessionID) {
		// The tracked order stopped being the standing
		// pending session without our firing: a new
		// session superseded it, or this session was
		// consumed (a boot's check-in), or the marker
		// was cleared under it. (A disarm never reaches
		// here - the loop's disarm stand-down logs the
		// abandonment itself.)
		switch {
		case pending:
			s.noteAbandoned(fmt.Sprintf("superseded by session %d", c.SessionID))
		case c.SessionID == s.sessionID && c.SessionState != "loading":
			s.noteAbandoned(fmt.Sprintf("the session ended before the spawn (state %q)", c.SessionState))
		case c.SessionID == s.sessionID:
			s.noteAbandoned("the pending marker was cleared before the spawn")
		default:
			s.noteAbandoned(fmt.Sprintf("superseded by session %d", c.SessionID))
		}
	}
	if !pending {
		return coldNone
	}
	if !s.tracking() {
		d := readDiag(cdir)
		s.sessionID = c.SessionID
		s.delay, s.delayFromDiag = coldSpawnDelay(d)
		s.firstSeenAt = now
		s.det = holdDetector{}
		src := "the default"
		if s.delayFromDiag {
			src = "pvlds_diag.txt"
		}
		logf("watchdog: session %d: cold spawn: pending - the launch order stands; waiting for the launcher to exit, then %ds of quiet before spawning (delay: %s)", c.SessionID, int(s.delay/time.Second), src)
	}
	// Hold-exit inside the window: the deliberate
	// shut-it-down gesture cancels a launch that has
	// not happened yet. The machine's own detector,
	// fed the standing law minus the game gates (the
	// game is not born to be alive or sighted).
	if s.det.observe(now.UnixMilli(), holdSample{sessionID: c.SessionID, phase: "loading", alive: true, sighted: true, enabled: c.HoldExitEnabled, pressed: holdButtonPressed()}) {
		writeContractMerged(func(mc *Contract) {
			if mc.SessionID == c.SessionID && mc.SpawnPending {
				if mc.HoldExitFiredUnix == 0 {
					mc.HoldExitFiredUnix = now.Unix()
				}
				mc.Armed = false
				mc.DisarmReason = "hold exit"
				mc.SessionState = "idle"
				mc.SpawnPending = false
				mc.GamePID = 0
			}
		})
		logf("watchdog: session %d: cold spawn: hold-exit fired during the pending window - disarming (hold exit); never spawned", c.SessionID)
		s.reset()
		return coldStoodDown
	}
	// A helper in flight: judge its report.
	if s.helperPID > 0 {
		return s.pollHelper(c, cdir, now)
	}
	// Watch for the launcher's death; the quiet runs
	// from its first observation.
	if s.launcherDeadAt.IsZero() {
		if c.LauncherPID > 0 && !processAlive(c.LauncherPID) {
			s.launcherDeadAt = now
			logf("watchdog: session %d: cold spawn: launcher dead - the quiet clock is running", c.SessionID)
		} else {
			if now.Sub(s.firstSeenAt) > pendingStuckSec*time.Second {
				writeContractMerged(func(mc *Contract) {
					if mc.SessionID == c.SessionID && mc.SpawnPending {
						mc.SpawnPending = false
					}
				})
				logf("watchdog: session %d: cold spawn: abandoned - the launcher (pid %d) is still alive after %ds; the order is cleared and the session's standing laws take it from here", c.SessionID, c.LauncherPID, pendingStuckSec)
				s.reset()
				return coldResolved
			}
			return coldWaiting
		}
	}
	if now.Sub(s.launcherDeadAt) < s.delay {
		return coldWaiting
	}
	// The quiet has passed: fire the spawn.
	logf("watchdog: session %d: cold spawn: quiet elapsed - spawning %s", c.SessionID, filepath.Base(c.GameExePath))
	return s.startHelper(c, cdir, now)
}

// startHelper fires the supervised birth: this binary's
// own spawn mode, started detached, with the spec the
// launcher left (its cwd, its argv). The report comes
// back through the pid file, judged by pollHelper on
// the following ticks - exactly the launcher's own
// spawn_game discipline, with this process in the
// launcher's seat.
func (s *coldSpawnState) startHelper(c *Contract, cdir string, now time.Time) coldSpawnOutcome {
	self, err := os.Executable()
	if err != nil {
		return s.fail(c, now, fmt.Sprintf("the watchdog cannot name its own executable: %v", err))
	}
	cwd := c.GameCwd
	if cwd == "" {
		cwd = filepath.Dir(c.GameExePath)
	}
	pidFile := filepath.Join(cdir, spawnPidFileName)
	os.Remove(pidFile) // a stale report is a per-launch fact, never a record
	// FIX154: raise the name window BEFORE the birth
	// (namewindow.go). The B2S name scrape runs when
	// VPX's script initialises - seconds into the load
	// this spawn is about to start - and reads the
	// table's name off a desktop window that must
	// already exist. A spec naming no table file gets
	// no window, logged in the feed's own words; the
	// launch goes ahead either way.
	if title, ok := nameWindowTitleForArgs(c.GameArgs); ok {
		raiseNameWindow(c.SessionID, title, now)
	} else {
		logf("watchdog: session %d: name window: the launch spec names no table file - no window raised", c.SessionID)
	}
	args := []string{spawnModeArg, cwd, pidFile, c.GameExePath}
	args = append(args, c.GameArgs...)
	helperPID, err := startDetached(self, args)
	if err != nil {
		return s.fail(c, now, fmt.Sprintf("the spawn helper could not be started: %v", err))
	}
	s.helperPID = helperPID
	s.helperStartAt = now
	return coldWaiting
}

// pollHelper judges an in-flight spawn helper by its
// pid-file report, its life, and the report window -
// the launcher's three failure shapes, in its words.
func (s *coldSpawnState) pollHelper(c *Contract, cdir string, now time.Time) coldSpawnOutcome {
	pidFile := filepath.Join(cdir, spawnPidFileName)
	if data, err := os.ReadFile(pidFile); err == nil {
		if pid, perr := strconv.Atoi(strings.TrimSpace(string(data))); perr == nil && pid > 0 {
			os.Remove(pidFile)
			sid := c.SessionID
			writeContractMerged(func(mc *Contract) {
				if mc.SessionID == sid && mc.SpawnPending {
					mc.GamePID = pid
					mc.SpawnPending = false
					// The game's start is the spawn,
					// not the arm: the session's
					// materialisation clocks (the
					// never-materialised law) measure
					// from the true start.
					mc.GameStartedUnix = now.Unix()
				}
			})
			logf("watchdog: session %d: cold spawn: spawned (game pid %d)", sid, pid)
			s.reset()
			return coldResolved
		}
	}
	if !processAlive(s.helperPID) {
		return s.fail(c, now, "the spawn helper exited without starting the game")
	}
	if now.Sub(s.helperStartAt) > spawnReportTimeout {
		// The launcher's spawn_game kills its shim on
		// this same timeout; the helper is this
		// process's child and gets the same stop.
		terminateProcess(s.helperPID)
		return s.fail(c, now, "the spawn helper never reported the game's pid")
	}
	return coldWaiting
}

// fail lands a spawn failure: the session is marked
// failed in the contract, the failure is logged
// plainly, and the caller relaunches the launcher so
// the failure surfaces (the standing machinery - a
// failed session is never left at a bare desktop).
func (s *coldSpawnState) fail(c *Contract, now time.Time, why string) coldSpawnOutcome {
	sid := c.SessionID
	writeContractMerged(func(mc *Contract) {
		if mc.SessionID == sid && mc.SpawnPending {
			mc.SessionState = "failed"
			mc.SpawnPending = false
			mc.GamePID = 0
		}
	})
	logf("watchdog: session %d: cold spawn: the spawn failed (%s); marking the session failed and relaunching the launcher", sid, why)
	s.reset()
	return coldFailed
}
