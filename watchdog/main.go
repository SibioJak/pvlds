// PVLDS watchdog: the tiny resident process that makes the hand-off
// round trip work (design sections 3/5/6 in
// ~/workspace/vpx-vr-launcher/design.md).
//
// The launcher exits completely when a table launches - absence is
// the fix for the OpenXR/focus fights. Something has to notice when
// VPX dies and bring the launcher back. That is all this process is:
//
//   - poll the session contract JSON the launcher writes,
//   - while a session is loading or live, watch the game process
//     (and, on Windows, herd foreground focus back to the game
//     window during the LOADING phase only - yielding to
//     deliberate use - and, in a live session, run the exit
//     detector: when the table exit lands in the VPX editor, the
//     editor takes and holds the foreground, and the watchdog
//     closes VPX orderly so the return trip can finish; see
//     closer.go). The close duty is unconditional, and D-pad
//     right is a plain BACK button — in play a TAP is VPX's own
//     Exit Game binding and lands in the editor, which this
//     duty then closes promptly; in the room the same press
//     quits the app (the launcher's side). The one ruled
//     exception (HOLD-EXIT, 2026-11-09): a continuous 1.5 s
//     HOLD of D-pad right during a session is the deliberate
//     shut-everything-down gesture — the hold watch below
//     (hold_logic.go) fires the same close ladder at VPX and
//     stamps the contract's hold_exit_fired_unix, on which the
//     works stand down instead of returning to the room,
//   - stamp the contract when the game's player window is first
//     sighted (runtime.go's sibling, sighting.go - the exit
//     detector arms on it) and again when the game's table
//     RUNTIME first exists (runtime.go): the runtime stamp is
//     the resident launcher's hand-off cue, because the
//     sighting stamps off the editor's own canvas seconds
//     before a real load finishes,
//   - run the launch focus sequence (focus.go, FIX116): from
//     spawn through the hand-off, put the foreground on the
//     game's resolved PLAYER window (target.go) - the window
//     that owns input, SDL_app on GL builds, VPPlayer on BGFX
//     builds - verified by read-back against the window's
//     handle, until it verifiably holds (FocusLocked) or the
//     log says why not (FocusUnresolved). The sequence folds
//     in the hand-off assertion at the moment the supervising
//     launcher is observed gone. It replaces the two one-shot
//     mechanisms that preceded it: a process-level push that
//     certified success while the wrong window held the
//     foreground, and an SDL-only activation that could never
//     raise a BGFX build's player window at all. FIX117 adds
//     focus DELIVERY inside the sequence: the foreground lock
//     proves the outer switch, but the player THREAD's
//     keyboard focus - the inner switch VPX's SDL layer gates
//     joystick input on - was never read or worked (the
//     watchdog made no SetFocus, SetActiveWindow or
//     GetGUIThreadInfo call at all). The sequence now reads
//     the player thread's focus, logs its every change, and
//     at the delivery moments - the hand-off tick, behind a
//     verified assertion, and at the lock's own resolution -
//     delivers focus into the player window by the contract's
//     ladder rung, or probes it with the activation message
//     pair under the diagnostic probe flag. The lock keeps
//     its 1.1.6 criteria: the focus requirement ships
//     log-only in this build (investigation:
//     ~/workspace/pvlds-actuation/INVESTIGATION.md; build
//     record: ~/workspace/pvlds-fix117/STATUS.md),
//   - and once the sequence has ended in a live session, run
//     the focus guard (guard.go): take the foreground back
//     ONLY from known bystander windows that raise themselves
//     (the PINemHi LeaderBoard board is the field case) and
//     from the game's own window family - never from the
//     editor, never against desktop-input evidence that the
//     user put a window there, and never past three silent
//     reclamations per window. Both duties live under the
//     focus_herding switch, which now gates the whole focus
//     family (FIX116),
//   - in a live session, log EVERY foreground identity change
//     (fgwatch.go): the mid-play input-loss forensics. The
//     window inventory lines print only on window-SET changes
//     and the set is static mid-play, so a foreground flicker
//     used to leave no trace in this log at all. Logging only -
//     nothing decides on it,
//   - when the game dies: in "live" (the launcher already exited)
//     relaunch it exactly once; in "loading" the launcher is still
//     resident and owns the failure, so the session is marked
//     "failed" instead and this process never relaunches for it
//     (if the supervising launcher itself is gone, a loading
//     session is promoted to live - nobody is left to show a
//     failure, and the player must not be stranded),
//   - stand down forever when the contract says armed=false (the
//     player's Exit), when the contract file disappears, or when
//     the launcher hasn't checked in across 24 hours (stale watch).
//
// A relaunch loop cap keeps a broken launcher from resurrecting
// forever: if a relaunched launcher dies within 20s without arming
// a new session, that is a strike; 3 strikes disarm the contract
// and the watchdog exits.
//
// Usage: pvlds_watchdog [contract-path]
// Default contract path: pvlds_watchdog_contract.json beside the
// watchdog executable. The launcher passes the real path explicitly.
//
// Logs to pvlds_watchdog.log beside the contract. Stdlib only.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Contract struct {
	Version int  `json:"version"`
	Armed   bool `json:"armed"`
	// DisarmReason names who dismissed the session ("room Exit",
	// "window close", "watchdog loop cap", ...), written by the
	// disarmer alongside armed=false and read into the stand-down
	// log line. Absent in contracts written before the field
	// existed: the empty string falls back to the legacy generic.
	DisarmReason string `json:"disarm_reason"`
	FocusHerding bool   `json:"focus_herding"`
	// FocusActuationRung and FocusActuationProbe are FIX117's
	// actuation controls (focus.go): the rung selects HOW the
	// focus delivery is performed (1 attachment-family, 2 the
	// shell switch call, 3 the activation-cycle nudge) and the
	// probe flag swaps every delivery for the diagnostic
	// message pair. They ride ONLY this additive read - the
	// parse below is field-by-field and never fails on a
	// contract that lacks them, so an older app's contract
	// keeps the defaults (rung 1, probe off).
	FocusActuationRung  int  `json:"focus_actuation_rung"`
	FocusActuationProbe bool `json:"focus_actuation_probe"`
	// PINemHi watcher management (PINEMHI2 Part B; pinemhi.go
	// carries the law). PinemhiManage + PinemhiFolder are
	// mirrored by the launcher from its config on every
	// check-in / launch write, like FocusHerding above.
	// PinemhiWatcherPID + PinemhiWatcherState are owned by
	// THIS process: "" = un-owned, "started" = PVLDS started
	// the watcher (and closes it when the session's life ends,
	// or at true exit inside that life), "adopted" = a watcher
	// was already running (used, never closed). All
	// four ride every merged write so neither side's writes
	// ever drop the other's facts. Absent in contracts written
	// before the fields existed: manage=false, state="" -
	// today's behaviour exactly.
	PinemhiManage       bool   `json:"pinemhi_manage"`
	PinemhiFolder       string `json:"pinemhi_folder"`
	PinemhiWatcherPID   int    `json:"pinemhi_watcher_pid"`
	PinemhiWatcherState string `json:"pinemhi_watcher_state"`
	// Hold-to-exit (HOLD-EXIT round; hold_logic.go carries the
	// law). HoldExitEnabled is mirrored by the launcher from its
	// config on every check-in / launch write, like FocusHerding
	// above; absent in older contracts, where encoding/json
	// leaves it false — the launcher's own default is ON, and a
	// contract the current launcher writes always carries it, so
	// absence only ever describes a pre-HOLD-EXIT writer.
	// HoldExitFiredUnix is owned by THIS process: stamped once
	// when a session's hold fires, it is the app-exit signal —
	// a resident launcher reading it for its own session exits
	// through its own Exit path, and the watchdog's death paths
	// read the same fact (via the detector's latch) to stand
	// down instead of relaunching. The button is fixed to
	// D-pad right; hold_exit_button from older builds is not
	// read. The close duty itself stays unconditional — the
	// hold is an ADDITIONAL, separately gated exit, not a
	// switch on the closer.
	HoldExitEnabled    bool   `json:"hold_exit_enabled"`
	HoldExitFiredUnix  int64  `json:"hold_exit_fired_unix"`
	SessionID          int    `json:"session_id"`
	SessionState       string `json:"session_state"`
	GameExePath        string `json:"game_exe_path"`
	GamePID            int    `json:"game_pid"`
	GameStartedUnix    int64  `json:"game_started_unix"`
	GameWindowSeenUnix int64  `json:"game_window_seen_unix"`
	// RuntimeSeenUnix is stamped (once per session) when the
	// game's table RUNTIME first exists (runtime.go) - the
	// resident launcher's hand-off cue. Absent/0 in contracts
	// written before the field existed; the launcher treats 0
	// as "not yet" and its load cap still bounds the wait.
	RuntimeSeenUnix int64    `json:"runtime_seen_unix"`
	LauncherPath    string   `json:"launcher_path"`
	LauncherArgs    []string `json:"launcher_args"`
	LauncherPID     int      `json:"launcher_pid"`
	LastCheckinUnix int64    `json:"last_checkin_unix"`
	UpdatedUnix     int64    `json:"updated_unix"`
}

const (
	tickInterval      = 400 * time.Millisecond
	pendingTimeoutSec = 120   // session armed but the game never appeared
	healthyWindowSec  = 20    // a relaunched launcher living this long is healthy
	maxStrikes        = 3     // fast-death strikes before disarm + exit
	staleTimeoutSec   = 86400 // 24h without a launcher check-in
	settleWindowSec   = 30    // herding is most active right after spawn
)

var (
	contractPath string
	logPath      string
	lockPath     string
	logFile      *os.File
	logMu        sync.Mutex // guards logFile writes
)

func logf(format string, args ...interface{}) {
	line := fmt.Sprintf("%s %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
	logMu.Lock()
	defer logMu.Unlock()
	if logFile != nil {
		logFile.WriteString(line)
		logFile.Sync()
	}
}

// normalizeState maps the schema-v1 session spellings onto the v2
// machine (loading = launcher resident, live = launcher exited), so
// a contract written by either build generation is understood.
func normalizeState(s string) string {
	switch s {
	case "launching":
		return "loading"
	case "playing":
		return "live"
	}
	return s
}

func readContract() (*Contract, error) {
	data, err := os.ReadFile(contractPath)
	if err != nil {
		return nil, err
	}
	var c Contract
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, err
	}
	c.SessionState = normalizeState(c.SessionState)
	return &c, nil
}

// writeContractMerged re-reads the contract, applies mutate, and
// writes it back atomically (temp + rename). If the launcher's
// identity fields changed between the read and the write (its
// check-in landed mid-merge - seen in the M2 e2e, where the
// watchdog's post-relaunch write briefly rolled launcher_pid back
// to the previous process), the merge restarts once on the fresh
// read so launcher-owned fields are never carried backwards.
func writeContractMerged(mutate func(*Contract)) {
	c, err := readContract()
	if err != nil {
		return
	}
	if fresh, ferr := readContract(); ferr == nil &&
		(fresh.LauncherPID != c.LauncherPID || fresh.LastCheckinUnix != c.LastCheckinUnix) {
		c = fresh
	}
	mutate(c)
	c.UpdatedUnix = time.Now().Unix()
	data, err := json.MarshalIndent(c, "", "\t")
	if err != nil {
		return
	}
	tmp := contractPath + ".wdog.tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return
	}
	os.Rename(tmp, contractPath)
}

// holdWatchState is the shared state between the watchdog's
// main loop and the hold watch goroutine: the main loop
// publishes the standing context (session, phase, alive,
// sighted, toggle) every tick; the goroutine polls the button
// leaf at holdPollIntervalMs — only while a session is active,
// never when no session is live — feeds the detector, and
// latches the fire here for the main loop to act on (the
// contract writes and close sends stay on the main loop, where
// every other contract write and close send already lives).
type holdWatchState struct {
	mu       sync.Mutex
	ctx      holdSample
	fired    bool
	firedFor int
}

func (w *holdWatchState) publish(s holdSample) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.ctx = s
}

func (w *holdWatchState) firedForSession(sessionID int) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.fired && w.firedFor == sessionID
}

// run is the hold watch goroutine: one detector, fed at the
// poll cadence off the published context.
func (w *holdWatchState) run() {
	det := &holdDetector{}
	for {
		time.Sleep(holdPollIntervalMs * time.Millisecond)
		w.mu.Lock()
		ctx := w.ctx
		w.mu.Unlock()
		pressed := false
		if ctx.phase == "loading" || ctx.phase == "live" {
			pressed = holdButtonPressed()
		}
		ctx.pressed = pressed
		if det.observe(time.Now().UnixMilli(), ctx) {
			w.mu.Lock()
			w.fired = true
			w.firedFor = ctx.sessionID
			w.mu.Unlock()
		}
	}
}

// holdLadder is the main loop's escalation state for a fired
// hold: the same orderly ladder the closer drives (FEC, grace,
// WM_CLOSE, give up — closer.go's timing constants), advanced
// on main ticks while the game stays alive. Stage 0 = not
// started for this session.
type holdLadder struct {
	sessionID  int
	stage      int // 1 FEC sent, 2 WM_CLOSE sent, 3 gave up
	actionAtMs int64
}

// gameAlive reports the session's game pid and its liveness.
// The decision law lives in gamepid.go: a pid standing in the
// contract is the session's game, alive or dead, and exe
// discovery runs only while the contract carries no pid yet.
func gameAlive(c *Contract) (bool, int) {
	contractAlive := c.GamePID > 0 && processAlive(c.GamePID)
	var discovered []int
	if c.GamePID == 0 && c.GameExePath != "" {
		discovered = findPIDsByExe(c.GameExePath)
	}
	return resolveSessionGamePID(c.GamePID, contractAlive, discovered, os.Getpid())
}

func launcherAlive(c *Contract, extraPID int) bool {
	if extraPID > 0 && processAlive(extraPID) {
		return true
	}
	return c.LauncherPID > 0 && processAlive(c.LauncherPID)
}

// FIX117's player-thread focus feed (fgwatch.go): the
// tracker that logs the player window's thread focus the
// moment it changes - the before/after picture of every
// delivery, and the state that decides droscoe's next report
// with or without any delivery firing.
var sessionFocusTracker playerFocusTracker

func main() {
	exe, _ := os.Executable()
	dir := filepath.Dir(exe)
	contractPath = filepath.Join(dir, "pvlds_watchdog_contract.json")
	if len(os.Args) > 1 && os.Args[1] != "" {
		contractPath = os.Args[1]
	}
	cdir := filepath.Dir(contractPath)
	logPath = filepath.Join(cdir, "pvlds_watchdog.log")
	lockPath = filepath.Join(cdir, "pvlds_watchdog.lock")

	if lf, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); err == nil {
		logFile = lf
		defer logFile.Close()
		if info, err := logFile.Stat(); err == nil && info.Size() > 1<<20 {
			logFile.Truncate(0)
		}
	}

	// Single instance: a live lock means another watchdog already
	// owns the watch. The running one polls the contract file, so
	// the caller's fresh contract reaches it without a twin.
	if data, err := os.ReadFile(lockPath); err == nil {
		var pid int
		if _, serr := fmt.Sscanf(string(data), "%d", &pid); serr == nil && pid > 0 && pid != os.Getpid() && processAlive(pid) {
			logf("watchdog: another instance (pid %d) is on duty; exiting", pid)
			return
		}
	}
	os.WriteFile(lockPath, []byte(fmt.Sprintf("%d", os.Getpid())), 0644)
	defer os.Remove(lockPath)
	// PINemHi exit close (pinemhi.go): registered once the lock
	// is held - i.e. this process IS the session's watchdog -
	// and deferred past every return below, so disarm, contract
	// gone, stale watch and the loop cap all count as TRUE exit
	// and close a watcher PVLDS started. (The twin-instance
	// return above never reaches here: a twin owns nothing.)
	defer closePinemhiWatcher()
	logf("watchdog: on duty (pid %d), contract %s", os.Getpid(), contractPath)

	// The hold watch (hold_logic.go): polls the button on its
	// own goroutine at 50 ms — the 400 ms main tick would smear
	// the 1.5 s threshold — and only while a session is active.
	holdW := &holdWatchState{}
	go holdW.run()
	var sessionHold holdLadder

	var (
		sawGameAlive      bool
		awaitingOutcome   bool
		relaunchedPID     int
		relaunchedAt      int64
		sessionAtRelaunch int
		strikes           int
		sessionCloser     closer
		sessionFGTracker  fgTracker
		sessionFocus      focusSequence     // the launch focus sequence (focus.go)
		sessionGuard      focusGuard        // the live-session focus guard (guard.go)
		focusHeaderLog    int               // the session the header line has been logged for
		focusTargetLog    int               // the session the target bookkeeping belongs to
		focusTargetHWND   uintptr           // the target last named in the log for focusTargetLog
		actRuntimeSession int               // the session actRuntimeMs belongs to
		actRuntimeMs      int64             // first tick the session's runtime stamp was observed (the focus sequence's anchor)
		pinemhiMissingLog bool              // the manage-on-but-no-exe line has been logged this duty spell (no retry spam)
		pinemhiLatch      pinemhiStartLatch // WATCHERFIX: a failed watcher start logs once per spell, then latches
		pinemhiLife       pinemhiLifetime   // WATCHERLIFE: the session/tail tracker - the watcher is up only inside a session or its extraction tail
	)

	relaunch := func(c *Contract, why string) {
		if c.LauncherPath == "" {
			logf("watchdog: cannot relaunch (%s) - no launcher path in contract", why)
			awaitingOutcome = false
			return
		}
		pid, err := startDetached(c.LauncherPath, c.LauncherArgs)
		if err != nil {
			logf("watchdog: relaunch failed (%s): %v", why, err)
			awaitingOutcome = false
			return
		}
		logf("watchdog: relaunched launcher pid %d (%s)", pid, why)
		// Mark the session consumed so nothing re-fires on it.
		writeContractMerged(func(mc *Contract) {
			if mc.SessionState == "live" || mc.SessionState == "loading" {
				mc.SessionState = "returned"
			}
			mc.GamePID = 0
		})
		awaitingOutcome = true
		relaunchedPID = pid
		relaunchedAt = time.Now().Unix()
		sessionAtRelaunch = c.SessionID
		sawGameAlive = false
	}

	for {
		time.Sleep(tickInterval)
		c, err := readContract()
		if err != nil {
			if os.IsNotExist(err) {
				logf("watchdog: contract file gone; standing down")
				return
			}
			continue // mid-write or transient: retry next tick
		}
		if !c.Armed {
			reason := c.DisarmReason
			if reason == "" {
				reason = "player Exit"
			}
			logf("watchdog: contract disarmed (%s); standing down", reason)
			return
		}
		now := time.Now().Unix()
		sessionActive := c.SessionState == "loading" || c.SessionState == "live"
		alive, gpid := gameAlive(c)
		if alive && gpid > 0 && gpid != c.GamePID {
			c.GamePID = gpid
		}
		// Publish this tick's context to the hold watch. The
		// sighting read is the gate's latch (fed by the window
		// snapshots below and on earlier ticks — a tick of lag
		// at worst, against a 1.5 s threshold).
		holdPhase := ""
		if sessionActive {
			holdPhase = c.SessionState
		}
		holdSighted := false
		if sessionActive && alive && c.GamePID > 0 {
			holdSighted, _ = gameWindowExists(c.GamePID, c.SessionID)
		}
		holdW.publish(holdSample{sessionID: c.SessionID, phase: holdPhase, alive: alive, sighted: holdSighted, enabled: c.HoldExitEnabled})
		// ---- relaunch outcome tracking -------------------------
		if awaitingOutcome {
			switch {
			case c.SessionID > sessionAtRelaunch:
				logf("watchdog: relaunched launcher armed session %d; outcome good", c.SessionID)
				strikes = 0
				awaitingOutcome = false
			case !launcherAlive(c, relaunchedPID):
				if now-relaunchedAt <= healthyWindowSec {
					strikes++
					logf("watchdog: relaunched launcher died within %ds (strike %d/%d)", healthyWindowSec, strikes, maxStrikes)
					if strikes >= maxStrikes {
						logf("watchdog: loop cap tripped; disarming and standing down")
						writeContractMerged(func(mc *Contract) { mc.Armed = false; mc.DisarmReason = "watchdog loop cap" })
						return
					}
					relaunch(c, "retry after fast launcher death")
					continue
				}
				// Lived past the healthy window, then exited on its
				// own without launching or disarming: not a strike.
				awaitingOutcome = false
				strikes = 0
			case now-relaunchedAt > healthyWindowSec:
				strikes = 0 // survived the window: the launcher is healthy
				awaitingOutcome = false
			}
		}

		// ---- session tracking ----------------------------------
		if sessionActive {
			if alive {
				if !sawGameAlive {
					sawGameAlive = true
					logf("watchdog: game process live (pid %d), session %d", gpid, c.SessionID)
				}
				// This tick's window/foreground snapshot
				// (platform leaf): computing it advances the
				// sighting gate (sighting.go), logs the window
				// inventory on change, and yields the facts
				// the stamp below and the exit detector read.
				ws := gameWindowState(c.GamePID, c.SessionID)
				// The FIX117 ladder setting, clamped here so
				// every consumer (the session header line, the
				// sequence's inputs) reads the value that will
				// actually be used: anything outside 1..3 is 1.
				actuationRung := c.FocusActuationRung
				if actuationRung < 1 || actuationRung > 3 {
					actuationRung = 1
				}
				// Session header (FIX116 logging): the first
				// tick a session is observed with its game
				// alive names the session, the game, and the
				// focus_herding value AS RECEIVED - "the switch
				// was on" used to be untestable from a field
				// log, and two field cases turned on it.
				if focusHeaderLog != c.SessionID {
					focusHeaderLog = c.SessionID
					herdingWord := "off"
					if c.FocusHerding {
						herdingWord = "on"
					}
					logf("watchdog: session %d: %s (pid %d); focus herding %s (as received)", c.SessionID, filepath.Base(c.GameExePath), c.GamePID, herdingWord)
					// FIX117: a non-default actuation setting
					// names itself in the header - a field log
					// proves which act produced (or didn't
					// produce) the delivery lines below. The
					// defaults (rung 1, probe off) stay silent.
					if c.FocusHerding && c.FocusActuationProbe {
						logf("watchdog: session %d: focus actuation: message probe (diagnostic)", c.SessionID)
					} else if c.FocusHerding && actuationRung != 1 {
						logf("watchdog: session %d: focus actuation: rung %d", c.SessionID, actuationRung)
					}
				}
				// Target bookkeeping (FIX116 logging): the
				// resolved player target (target.go) is logged
				// when it appears, changes, or is lost, with
				// the rank that chose it - so a field log names
				// the window every focus duty will raise,
				// before any of them act.
				if focusTargetLog != c.SessionID {
					focusTargetLog = c.SessionID
					focusTargetHWND = 0
				}
				if ws.playerHWND != focusTargetHWND {
					if ws.playerHWND != 0 {
						logf("watchdog: session %d: focus target: %q window (hwnd %#x) - %s", c.SessionID, ws.playerClass, ws.playerHWND, ws.playerWhy)
					} else if focusTargetHWND != 0 {
						logf("watchdog: session %d: focus target lost - the player window is gone", c.SessionID)
					}
					focusTargetHWND = ws.playerHWND
				}
				// The hand-off cue for the resident launcher: a
				// player sighting has stamped for this session
				// (sighting.go - the editor frame is up from app
				// start and must never stamp this). Stamped once
				// per session; the log names the sighting rule.
				if c.GameWindowSeenUnix == 0 {
					if sighted, rule := gameWindowExists(c.GamePID, c.SessionID); sighted {
						logf("watchdog: game window up (pid %d), session %d (sighting: %s)", c.GamePID, c.SessionID, rule)
						writeContractMerged(func(mc *Contract) {
							if mc.GameWindowSeenUnix == 0 && (mc.SessionState == "loading" || mc.SessionState == "live") {
								mc.GameWindowSeenUnix = time.Now().Unix()
							}
						})
					}
				}
				// The resident launcher's hand-off cue: the
				// game's table RUNTIME exists (runtime.go).
				// The sighting above stamps seconds earlier -
				// off the editor's own canvas - while a real
				// load is still running, so the launcher waits
				// for THIS stamp before it leaves the room.
				// Stamped once per session, sighting-style.
				if c.RuntimeSeenUnix == 0 {
					if runtimeUp, runtimeRule := gameRuntimeExists(c.GamePID, c.SessionID); runtimeUp {
						if runtimeRule == runtimeRuleVPPlayer {
							logf("watchdog: game runtime up (pid %d), session %d (signature: %s)", c.GamePID, c.SessionID, runtimeRule)
						} else {
							logf("watchdog: game runtime up (pid %d), session %d", c.GamePID, c.SessionID)
						}
						writeContractMerged(func(mc *Contract) {
							if mc.RuntimeSeenUnix == 0 && (mc.SessionState == "loading" || mc.SessionState == "live") {
								mc.RuntimeSeenUnix = time.Now().Unix()
							}
						})
					}
				}
				// A loading session whose supervising launcher has
				// died is unsupervised: promote it to live, so the
				// game's death still brings a launcher back instead
				// of stranding the player at a desktop.
				promoted := false
				if c.SessionState == "loading" && c.LauncherPID > 0 && !processAlive(c.LauncherPID) {
					logf("watchdog: supervising launcher gone during load, session %d; promoting to live", c.SessionID)
					writeContractMerged(func(mc *Contract) {
						if mc.SessionState == "loading" {
							mc.SessionState = "live"
						}
					})
					promoted = true
				}
				// The focus sequence's anchor: the first tick
				// this watchdog observes the session's runtime
				// stamp (tracked in either session state - the
				// stamp lands during loading, while the
				// sequence's resolutions land near the
				// hand-off and after).
				if actRuntimeSession != c.SessionID {
					actRuntimeSession = c.SessionID
					actRuntimeMs = 0
				}
				if actRuntimeMs == 0 {
					if runtimeUp, _ := gameRuntimeExists(c.GamePID, c.SessionID); runtimeUp {
						actRuntimeMs = time.Now().UnixMilli()
					}
				}
				// The hand-off tick (focus.go): the first tick
				// the session is live with the supervising
				// launcher observed gone. The sequence
				// evaluates it immediately - the foreground at
				// that moment belongs to whatever the
				// launcher's exit left in front.
				handoff := (c.SessionState == "live" || promoted) && c.LauncherPID > 0 && !processAlive(c.LauncherPID)
				// The launch focus sequence (focus.go): fed
				// every tick of the session while the
				// focus_herding switch is on (the switch gates
				// the whole focus family, FIX116). It asserts
				// to the resolved player HWND only, verifies
				// by read-back, and ends the launch in a
				// logged FocusLocked or FocusUnresolved. An
				// assertion it orders - and the hand-off tick
				// itself - is recorded with the exit detector
				// (notePush: the detector counts excursions
				// from facts after our last foreground touch),
				// and it runs BEFORE the detector's tick
				// below, so the record precedes the reading.
				if c.FocusHerding {
					nowMs := time.Now().UnixMilli()
					// The player-thread focus feed (fgwatch.go):
					// the player window's thread focus, logged
					// the moment it changes - the before/after
					// picture of every delivery below, and the
					// evidence that settles the next field
					// report whether or not any delivery
					// fires. A failed reader reports once per
					// session, and only while a target stands.
					if changed, failed := sessionFocusTracker.observe(c.SessionID, ws); failed {
						logf("watchdog: session %d: player thread focus: the focus reader is unavailable this session - focus duties run as in 1.1.6", c.SessionID)
					} else if changed {
						logf("watchdog: session %d: player thread focus: %s", c.SessionID, playerFocusDesc(ws))
					}
					res := sessionFocus.tick(nowMs, c.SessionID, actRuntimeMs, focusInputs{ws: ws, state: c.SessionState, handoff: handoff, actuationRung: actuationRung, actuationProbe: c.FocusActuationProbe})
					if res.notePush {
						sessionCloser.notePush(c.SessionID, nowMs)
					}
					switch res.action {
					case seqAssert:
						attempted, ok := activatePlayerWindow(c.GamePID, ws.playerHWND)
						if attempted {
							sessionCloser.notePush(c.SessionID, nowMs)
						}
						verdict := "refused"
						if ok {
							verdict = "accepted"
						}
						if sessionFocus.beforeIsGameFamily() {
							logf("watchdog: session %d: focus sequence: asserted the player window (foreground was %s - game window, not the player window - asserting; SetForegroundWindow %s)", c.SessionID, sessionFocus.before(), verdict)
						} else {
							logf("watchdog: session %d: focus sequence: asserted the player window (foreground was %s; SetForegroundWindow %s)", c.SessionID, sessionFocus.before(), verdict)
						}
						if sessionFocus.noteAssert(nowMs, attempted) == seqLogNoTarget {
							logf("watchdog: session %d: focus sequence: no player window to assert (standing down this attempt)", c.SessionID)
						}
					case seqDeliverFocus:
						// The FIX117 delivery: the rung leaf
						// performs the act; the line names the
						// rung and where the focus sat, so a
						// field log shows which act was used
						// and what it was working against.
						attempted, ok := deliverPlayerFocus(c.GamePID, ws.playerHWND, sessionFocus.deliverRung(), ws.machineryHWND)
						sessionFocus.noteDeliver(attempted)
						if attempted {
							verdict := "refused"
							if ok {
								verdict = "accepted"
							}
							logf("watchdog: session %d: focus sequence: delivered focus to the player window (rung %d; focus was %s; leaf %s)", c.SessionID, sessionFocus.deliverRung(), sessionFocus.focusDesc(), verdict)
						} else {
							logf("watchdog: session %d: focus sequence: no player window to deliver focus to (standing down this attempt)", c.SessionID)
						}
					case seqProbe:
						// The FIX117 message probe (diagnostic
						// only, the contract's probe flag): the
						// line says "probe" outright so it can
						// never be mistaken for a real delivery.
						attempted := probePlayerFocus(c.GamePID, ws.playerHWND)
						sessionFocus.noteDeliver(attempted)
						if attempted {
							logf("watchdog: session %d: focus sequence: probe - posted activation messages to the player window (focus was %s; diagnostic only)", c.SessionID, sessionFocus.focusDesc())
						} else {
							logf("watchdog: session %d: focus sequence: probe - no player window to probe (standing down this attempt)", c.SessionID)
						}
					case seqLogFocusNotDelivered:
						logf("watchdog: session %d: focus not delivered - the player window holds the foreground, but its thread focus stayed on %s after %d deliveries", c.SessionID, playerFocusDesc(ws), focusMaxAttempts)
					case seqLogLocked:
						logf("watchdog: session %d: focus locked - the player window (%q) holds the foreground", c.SessionID, sessionFocus.playerClass())
					case seqLogUnresolved:
						logf("watchdog: session %d: focus unresolved - %s", c.SessionID, sessionFocus.reason())
					case seqLogReopen:
						logf("watchdog: session %d: focus sequence reopened - the player window lost the foreground inside the launch window", c.SessionID)
					}
				}
				// Focus herding serves the loading phase's
				// spawn settle ONLY (herdingAllowed): once the
				// session is live it never runs - on the VR rig
				// its only anchor there is the editor frame,
				// which it was caught forcing to the foreground
				// mid-play, polluting the exit detector's
				// signal below. Its assertion target is the
				// resolved player HWND when one exists.
				if herdingAllowed(c.FocusHerding, c.SessionState) {
					herdTick(c.GamePID, c.SessionID, time.Now(), ws.playerHWND)
				}
				// Foreground-change forensics (fgwatch.go):
				// in a live session, log every change of
				// foreground identity, from this tick's
				// snapshot - the blind-spot fix for the
				// mid-play input-loss reports (pad and
				// keyboard dead in bursts while the table
				// rendered fine; the inventory lines print
				// only when the game's window SET changes,
				// and the set is static mid-play, so a
				// foreground flicker left no trace). The
				// tracker is fed live ticks only; the load's
				// shuffle stays the inventory lines' story.
				// Logging only: no behavior reads it. FIX116:
				// a change also logs the new owner's window
				// inventory (noteForegroundOwner) - a thief's
				// identity used to stop at its class.
				if c.SessionState == "live" {
					if ch, changed := sessionFGTracker.observe(c.SessionID, ws); changed {
						logf("watchdog: session %d: foreground changed: %s -> %s", c.SessionID, ch.oldSide(), ch.newSide())
						noteForegroundOwner(c.SessionID, ws)
					}
				}
				// The live-session focus guard (guard.go):
				// once the launch sequence has ended and the
				// session is live, take the foreground back
				// only from known bystanders and the game's
				// own window family - never the editor, never
				// against deliberate-use evidence, never past
				// the per-window cap - under the same switch.
				// It pauses while either close ladder is in
				// flight. A reclamation is recorded with the
				// exit detector exactly like the sequence's
				// assertions, and it likewise runs BEFORE the
				// detector's tick below.
				if c.FocusHerding && c.SessionState == "live" && sessionFocus.done() {
					nowMs := time.Now().UnixMilli()
					closerBusy := sessionCloser.stage == 1 || sessionCloser.stage == 2 ||
						sessionHold.stage == 1 || sessionHold.stage == 2
					gres := sessionGuard.tick(nowMs, c.SessionID, ws, closerBusy)
					switch gres.action {
					case guardAssert:
						attempted, _ := activatePlayerWindow(c.GamePID, ws.playerHWND)
						if attempted {
							sessionCloser.notePush(c.SessionID, nowMs)
							logf("watchdog: session %d: focus guard: %s", c.SessionID, gres.detail)
						}
					case guardLog:
						logf("watchdog: session %d: focus guard: %s", c.SessionID, gres.detail)
					}
				}
				// Session-close duty (closer.go) - the only exit
				// path in play, and unconditional: the exit
				// detector watches the foreground (in a live,
				// sighted session that has seen play take the
				// foreground away from the editor, the editor
				// holding the foreground for the sustain means
				// the table exit landed there) and asks VPX to
				// close - orderly, escalating, never a kill.
				// The decision is shared logic; the sends are
				// platform leaves. When VPX dies, the ordinary
				// death path below relaunches the launcher.
				sightedNow, _ := gameWindowExists(c.GamePID, c.SessionID)
				act, armedNow := sessionCloser.tick(time.Now().UnixMilli(), c.SessionID, c.SessionState, true, sightedNow, ws)
				if armedNow {
					logf("watchdog: session %d: exit detector armed", c.SessionID)
				}
				switch act {
				case closeFEC:
					ack := sendFrontEndControlsClose(c.GamePID)
					logf("watchdog: session %d: editor has held the foreground for %dms - table exit; sent PinSim::FrontEndControls CLOSE_APP (acknowledged: %v)", c.SessionID, editorForegroundSustainMs, ack)
				case closeWMClose:
					ok := sendEditorClose(ws.editorHWND)
					logf("watchdog: session %d: VPX still open after the FrontEndControls request; sent WM_CLOSE to the editor window (posted: %v)", c.SessionID, ok)
				case closeGiveUp:
					logf("watchdog: session %d: VPX did not close after FrontEndControls + WM_CLOSE; leaving VPX alone", c.SessionID)
				}
				// Hold-exit (HOLD-EXIT): the hold watch has
				// fired for this session — the player held
				// D-pad right through the threshold, the
				// deliberate shut-everything-down gesture.
				// Stamp the contract (the app-exit signal a
				// resident launcher consumes) and drive the
				// same orderly ladder at VPX. When VPX dies,
				// the death path below reads the fired latch
				// and stands the works down instead of
				// relaunching; if the ladder gives up, the
				// session simply continues — the player is
				// never left with a dead watch.
				if holdW.firedForSession(c.SessionID) {
					nowMs := time.Now().UnixMilli()
					if sessionHold.sessionID != c.SessionID {
						sessionHold = holdLadder{sessionID: c.SessionID, stage: 1, actionAtMs: nowMs}
						writeContractMerged(func(mc *Contract) {
							if mc.SessionID == c.SessionID && mc.HoldExitFiredUnix == 0 {
								mc.HoldExitFiredUnix = time.Now().Unix()
							}
						})
						ack := sendFrontEndControlsClose(c.GamePID)
						logf("watchdog: session %d: hold-exit fired (D-pad right held %dms) - signal stamped in the contract; sent PinSim::FrontEndControls CLOSE_APP (acknowledged: %v)", c.SessionID, holdExitThresholdMs, ack)
					} else if sessionHold.stage == 1 && nowMs-sessionHold.actionAtMs >= fecGraceMs {
						sessionHold.stage = 2
						sessionHold.actionAtMs = nowMs
						ok := sendEditorClose(ws.editorHWND)
						logf("watchdog: session %d: hold-exit: VPX still open after the FrontEndControls request; sent WM_CLOSE to the editor window (posted: %v)", c.SessionID, ok)
					} else if sessionHold.stage == 2 && nowMs-sessionHold.actionAtMs >= closeGiveUpMs {
						sessionHold.stage = 3
						logf("watchdog: session %d: hold-exit: VPX did not close after FrontEndControls + WM_CLOSE; leaving VPX alone (the session continues)", c.SessionID)
					}
				}
			} else if sawGameAlive {
				sawGameAlive = false
				if holdW.firedForSession(c.SessionID) {
					// HOLD-EXIT: VPX died under a fired hold —
					// the works stand down, no return trip. The
					// disarm names the gesture; the deferred
					// PINemHi close at this process's exit is
					// the watcher's end, as for any true exit.
					logf("watchdog: game process died, session %d; the hold-exit was fired - disarming (hold exit) and standing down", c.SessionID)
					writeContractMerged(func(mc *Contract) {
						mc.Armed = false
						mc.DisarmReason = "hold exit"
						mc.SessionState = "idle"
						mc.GamePID = 0
					})
					return
				}
				if c.SessionState == "loading" && c.LauncherPID > 0 && processAlive(c.LauncherPID) {
					// Died during the load, and the resident launcher
					// is right there to show the failure. Terminal:
					// mark it failed and NEVER relaunch for it.
					logf("watchdog: game died during load, session %d; marking failed (launcher resident)", c.SessionID)
					writeContractMerged(func(mc *Contract) {
						if mc.SessionState == "loading" {
							mc.SessionState = "failed"
							mc.GamePID = 0
						}
					})
				} else {
					logf("watchdog: game process died, session %d; relaunching launcher", c.SessionID)
					relaunch(c, "game exited")
					continue
				}
			} else if c.GameStartedUnix > 0 && now-c.GameStartedUnix > pendingTimeoutSec && !launcherAlive(c, 0) {
				// The launcher spawned... something that never
				// appeared, and the launcher is gone too. Bring the
				// player back rather than stranding them at a desktop.
				logf("watchdog: session %d never materialised in %ds; relaunching launcher", c.SessionID, pendingTimeoutSec)
				relaunch(c, "session never materialised")
				continue
			}
		} else {
			sawGameAlive = false
		}

		// ---- PINemHi watcher duty (pinemhi.go) ------------------
		// WATCHERLIFE: the watcher lives only while a table
		// session is live or in its extraction tail. The lifetime
		// tracker is fed every tick; the start/adopt duty below
		// runs only while the watcher is wanted, and the first
		// unwanted tick past the tail is the end of its life.
		// Off means this block does nothing at all.
		// WATCHERFIX: the failed-start latch follows the contract's
		// manage/folder values - a change to either is a new spell.
		pinemhiLatch.sync(c.PinemhiManage, c.PinemhiFolder)
		pinemhiWanted := pinemhiLife.wanted(sessionActive, now, pinemhiTail())
		if c.PinemhiManage && pinemhiWanted && c.PinemhiWatcherState == "" {
			exe := pinemhiExePath(c.PinemhiFolder)
			if !pinemhiFileExists(exe) {
				if !pinemhiMissingLog {
					pinemhiMissingLog = true
					if exe == "" {
						logf("watchdog: pinemhi: management is on but no PINemHi folder is in the contract; leaving the watcher alone")
					} else {
						logf("watchdog: pinemhi: management is on but %s is not there; leaving the watcher alone", exe)
					}
				}
			} else {
				pinemhiMissingLog = false
				pids := findPIDsByExe(exe)
				running := len(pids) > 0
				switch pinemhiDecide(c.PinemhiManage, c.PinemhiWatcherState, running) {
				case pinemhiAdopt:
					pid := pids[0]
					logf("watchdog: pinemhi: watcher already running (pid %d); adopted - PVLDS will not close it", pid)
					writeContractMerged(func(mc *Contract) {
						if mc.PinemhiWatcherState == "" {
							mc.PinemhiWatcherState = "adopted"
							mc.PinemhiWatcherPID = pid
						}
					})
				case pinemhiStart:
					// WATCHERFIX: the watcher starts INSIDE its own
					// folder (it resolves pinemhi.ini relative to its
					// working directory), and a failed start latches
					// for the spell - logged once, never retried per
					// tick. A latched spell stays quiet here; the
					// adopt check above still runs every tick.
					if !pinemhiLatch.mayStart() {
						// latched: a start already failed this spell
					} else if pid, serr := startDetachedInDir(exe, nil, c.PinemhiFolder); serr != nil {
						pinemhiLatch.recordFailure()
						logf("watchdog: pinemhi: could not start the watcher at %s: %v", exe, serr)
					} else {
						logf("watchdog: pinemhi: started the watcher (pid %d) for the session; PVLDS will close it after the session's extraction tail", pid)
						writeContractMerged(func(mc *Contract) {
							if mc.PinemhiWatcherState == "" {
								mc.PinemhiWatcherState = "started"
								mc.PinemhiWatcherPID = pid
							}
						})
					}
				}
			}
		}
		if c.PinemhiManage && !pinemhiWanted {
			// End of life: the session is over and the extraction
			// tail has run. A watcher PVLDS started is closed and
			// its ownership cleared; an adopted watcher is NEVER
			// closed - only its ownership record is cleared, so
			// the contract never claims a watcher outside a
			// session. A leftover "started" from a watchdog that
			// died without its exit close lands here too, on an
			// early idle tick.
			switch c.PinemhiWatcherState {
			case "started":
				if c.PinemhiWatcherPID > 0 && processAlive(c.PinemhiWatcherPID) {
					closePinemhiProcess(c.PinemhiWatcherPID, "session over")
				} else {
					logf("watchdog: pinemhi: session over; the watcher PVLDS started is already gone - clearing ownership")
				}
				writeContractMerged(func(mc *Contract) {
					if mc.PinemhiWatcherState == "started" {
						mc.PinemhiWatcherState = ""
						mc.PinemhiWatcherPID = 0
					}
				})
			case "adopted":
				logf("watchdog: pinemhi: session over; clearing the adopted watcher's record (pid %d stays running - it was never PVLDS's to close)", c.PinemhiWatcherPID)
				writeContractMerged(func(mc *Contract) {
					if mc.PinemhiWatcherState == "adopted" {
						mc.PinemhiWatcherState = ""
						mc.PinemhiWatcherPID = 0
					}
				})
			}
		}
		// A watcher PVLDS started that died on its own inside its
		// life: clear the ownership so the duty above re-decides
		// next tick (it will start a fresh one - a session or its
		// tail is still running). Outside that life the end-of-
		// life block above has already cleared the record.
		if pinemhiWanted && c.PinemhiWatcherState == "started" && c.PinemhiWatcherPID > 0 && !processAlive(c.PinemhiWatcherPID) {
			logf("watchdog: pinemhi: the watcher PVLDS started (pid %d) is gone; clearing ownership", c.PinemhiWatcherPID)
			writeContractMerged(func(mc *Contract) {
				if mc.PinemhiWatcherState == "started" {
					mc.PinemhiWatcherState = ""
					mc.PinemhiWatcherPID = 0
				}
			})
		}

		// ---- stale watch ----------------------------------------
		if !alive && !launcherAlive(c, relaunchedPID) && c.LastCheckinUnix > 0 && now-c.LastCheckinUnix > staleTimeoutSec {
			logf("watchdog: no launcher check-in for %ds; stale watch, standing down", now-c.LastCheckinUnix)
			return
		}
	}
}
