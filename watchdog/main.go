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
//     window - yielding to deliberate use - and, in a live
//     session whose table exit landed in the VPX editor, close
//     VPX orderly so the return trip can finish; see closer.go),
//   - while a session is live, poll the gamepad at ~50ms: a
//     deliberate HOLD of the configured exit button (~1.5s) is
//     the player's own "exit the whole thing" gesture and fires
//     the same orderly close (see hold_logic.go). With BOTH exit
//     switches on, the hold watch and the session-close duty
//     merge into the exit arbitrator instead (see arbiter.go
//     and the mode table at the dispatch): a TAP returns to the
//     room, a HOLD bails to the editor and disarms the watch,
//   - stamp the contract when the game's main window first exists
//     (the resident launcher reads it as its hand-off cue),
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
	DisarmReason        string `json:"disarm_reason"`
	FocusHerding        bool   `json:"focus_herding"`
	CloseVPXOnTableExit bool   `json:"close_vpx_on_table_exit"`
	// HoldExitEnabled is a pointer so an ABSENT key (a contract
	// written before hold-to-exit existed) can be told apart from
	// an explicit off: absence normalizes to the default ON in
	// readContract, and the schema stays v2.
	HoldExitEnabled    *bool    `json:"hold_exit_enabled"`
	HoldExitButton     string   `json:"hold_exit_button"`
	SessionID          int      `json:"session_id"`
	SessionState       string   `json:"session_state"`
	GameExePath        string   `json:"game_exe_path"`
	GamePID            int      `json:"game_pid"`
	GameStartedUnix    int64    `json:"game_started_unix"`
	GameWindowSeenUnix int64    `json:"game_window_seen_unix"`
	LauncherPath       string   `json:"launcher_path"`
	LauncherArgs       []string `json:"launcher_args"`
	LauncherPID        int      `json:"launcher_pid"`
	LastCheckinUnix    int64    `json:"last_checkin_unix"`
	UpdatedUnix        int64    `json:"updated_unix"`
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
	logMu        sync.Mutex // the main loop and the hold watch both log
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

// holdExitOn reports the effective hold-to-exit switch: the key
// defaults ON when absent (normalized in readContract, but answer
// safely for a hand-built Contract too).
func (c *Contract) holdExitOn() bool {
	return c.HoldExitEnabled == nil || *c.HoldExitEnabled
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
	// Hold-to-exit normalization (schema stays v2): a contract
	// that predates the feature has no keys; absence means the
	// defaults, never a wedge - and normalizing here means a
	// merged write (writeContractMerged) always emits real values
	// for the launcher's reader.
	if c.HoldExitEnabled == nil {
		on := true
		c.HoldExitEnabled = &on
	}
	if c.HoldExitButton == "" {
		c.HoldExitButton = defaultHoldButton
	}
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

func gameAlive(c *Contract) (bool, int) {
	if c.GamePID > 0 && processAlive(c.GamePID) {
		return true, c.GamePID
	}
	if c.GameExePath != "" {
		pids := findPIDsByExe(c.GameExePath)
		for _, pid := range pids {
			if pid != os.Getpid() {
				return true, pid
			}
		}
	}
	return false, 0
}

func launcherAlive(c *Contract, extraPID int) bool {
	if extraPID > 0 && processAlive(extraPID) {
		return true
	}
	return c.LauncherPID > 0 && processAlive(c.LauncherPID)
}

// ---- hold-to-exit watch ---------------------------------------
//
// The button is sampled on its own goroutine at ~50ms: the main
// loop's 400ms tick would smear the 1.5s hold threshold by up to a
// full tick, and the threshold IS the feel of the feature. The
// main loop publishes the session context once per tick; the
// watch reads it, polls the button feed (hold_windows.go /
// hold_other.go), feeds the shared brain (hold_logic.go), and
// delivers the close the brain orders - the closer's own orderly
// sends, serialized against them (closer_windows.go).

type holdContext struct {
	sessionID int
	live      bool // the contract's session is in the live state
	enabled   bool // hold_exit_enabled (absent = on)
	closerOn  bool // close_vpx_on_table_exit: with enabled, arbitration mode
	alive     bool // the game process is up inside an active session
	gamePID   int
	button    string
}

var (
	holdCtxMu sync.Mutex
	holdCtx   holdContext
)

func holdCtxUpdate(ctx holdContext) {
	holdCtxMu.Lock()
	holdCtx = ctx
	holdCtxMu.Unlock()
}

func holdCtxSnapshot() holdContext {
	holdCtxMu.Lock()
	defer holdCtxMu.Unlock()
	return holdCtx
}

// The arbitrator's button feed: the hold watch publishes one
// pressTracker snapshot per poll while arbitration mode is
// active; the main loop reads the latest for its session. A
// snapshot published for another session reads as empty (no
// press history) - a new session's arbitration starts clean.
var (
	btnSnapMu      sync.Mutex
	btnSnap        buttonSnapshot
	btnSnapSession int
)

func publishButtonSnapshot(sessionID int, snap buttonSnapshot) {
	btnSnapMu.Lock()
	btnSnap = snap
	btnSnapSession = sessionID
	btnSnapMu.Unlock()
}

func currentButtonSnapshot(sessionID int) buttonSnapshot {
	btnSnapMu.Lock()
	defer btnSnapMu.Unlock()
	if btnSnapSession != sessionID {
		return buttonSnapshot{}
	}
	return btnSnap
}

func holdWatchLoop() {
	var duty holdDuty
	var tracker pressTracker
	warnedSession := -1
	for {
		time.Sleep(holdPollIntervalMs * time.Millisecond)
		ctx := holdCtxSnapshot()
		mask, known := holdButtonMask(ctx.button)
		nowMs := time.Now().UnixMilli()
		// The mode split (the full table is at the dispatch in
		// main): with the closer switch ALSO on, the hold and the
		// closer merge into the exit arbitrator - this watch then
		// only TRACKS the button for the arbitrator, and the
		// plain hold duty is fed inactive so its old hold=close
		// can never fire. Hold-only mode feeds the duty as before.
		arbitrate := ctx.live && ctx.enabled && ctx.closerOn && ctx.alive && ctx.gamePID > 0
		holdOnly := ctx.live && ctx.enabled && !ctx.closerOn && ctx.alive && ctx.gamePID > 0
		if (arbitrate || holdOnly) && !known && warnedSession != ctx.sessionID {
			warnedSession = ctx.sessionID
			logf("watchdog: exit button %q is not a known XInput button name; the exit gestures are inert for session %d", ctx.button, ctx.sessionID)
		}
		if arbitrate {
			if known {
				publishButtonSnapshot(ctx.sessionID, tracker.observe(nowMs, ctx.sessionID, anyButtonPressed(mask)))
			} else {
				publishButtonSnapshot(ctx.sessionID, tracker.reset(ctx.sessionID))
			}
		}
		pressed := false
		if holdOnly && known {
			pressed = anyButtonPressed(mask)
		}
		switch duty.tick(nowMs, ctx.sessionID, holdOnly && known, pressed) {
		case holdFEC:
			ack := sendFrontEndControlsClose(ctx.gamePID)
			logf("watchdog: session %d: hold-to-exit fired (button %s held %dms); sent FrontEndControls CLOSE_APP (acknowledged: %v)", ctx.sessionID, ctx.button, holdThresholdMs, ack)
		case holdWMClose:
			ok := sendEditorClose(gameWindowState(ctx.gamePID, ctx.sessionID).editorHWND)
			logf("watchdog: session %d: hold-to-exit: VPX still open after the FrontEndControls request; sent WM_CLOSE to the editor window (posted: %v)", ctx.sessionID, ok)
		case holdGiveUp:
			logf("watchdog: session %d: hold-to-exit: VPX did not close after FrontEndControls + WM_CLOSE; leaving VPX alone", ctx.sessionID)
		}
	}
}

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
	logf("watchdog: on duty (pid %d), contract %s", os.Getpid(), contractPath)

	// The hold-to-exit watch runs for the watchdog's whole life;
	// it acts only while the published context says a session is
	// live with the feature on.
	go holdWatchLoop()

	var (
		sawGameAlive      bool
		awaitingOutcome   bool
		relaunchedPID     int
		relaunchedAt      int64
		sessionAtRelaunch int
		strikes           int
		sessionCloser     closer
		sessionArbiter    exitArbitrator
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
		// Publish the hold-to-exit context: live sessions only,
		// and only while the game is actually up in one.
		holdCtxUpdate(holdContext{
			sessionID: c.SessionID,
			live:      c.SessionState == "live",
			enabled:   c.holdExitOn(),
			closerOn:  c.CloseVPXOnTableExit,
			alive:     alive && sessionActive,
			gamePID:   c.GamePID,
			button:    c.HoldExitButton,
		})

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
				// A loading session whose supervising launcher has
				// died is unsupervised: promote it to live, so the
				// game's death still brings a launcher back instead
				// of stranding the player at a desktop.
				if c.SessionState == "loading" && c.LauncherPID > 0 && !processAlive(c.LauncherPID) {
					logf("watchdog: supervising launcher gone during load, session %d; promoting to live", c.SessionID)
					writeContractMerged(func(mc *Contract) {
						if mc.SessionState == "loading" {
							mc.SessionState = "live"
						}
					})
				}
				if c.FocusHerding {
					herdTick(c.GamePID, c.SessionID, time.Now())
				}
				// Exit-gesture dispatch - the mode table:
				//   closer on,  hold on   -> ARBITRATION
				//                            (arbiter.go): the editor
				//                            landing opens a window;
				//                            a tap (or a press-free
				//                            landing) resolves to the
				//                            orderly close + return,
				//                            a hold through the
				//                            threshold bails to the
				//                            editor and disarms.
				//   closer on,  hold off  -> the plain
				//                            session-close duty
				//                            (closer.go) below:
				//                            landing + sustain closes.
				//   closer off, hold on   -> hold-to-exit alone
				//                            (hold_logic.go, fed by
				//                            the hold watch): a hold
				//                            during play fires the
				//                            close; a tap is VPX's
				//                            own business (the editor).
				//   closer off, hold off  -> no exit closing at
				//                            all; the return rides
				//                            VPX's process death alone.
				// In arbitration mode neither plain duty decides:
				// the closer is not ticked and the hold watch only
				// tracks the button (see holdWatchLoop).
				if c.CloseVPXOnTableExit && c.holdExitOn() {
					// Exit arbitrator (arbiter.go): in a live
					// session whose table exit landed in the VPX
					// editor, decide tap vs hold from the button,
					// then ask VPX to close - orderly, escalating,
					// never a kill - or stand down entirely.
					switch sessionArbiter.tick(time.Now().UnixMilli(), c.SessionID, c.SessionState, true, gameWindowState(c.GamePID, c.SessionID), currentButtonSnapshot(c.SessionID)) {
					case arbCloseFEC:
						ack := sendFrontEndControlsClose(c.GamePID)
						logf("watchdog: session %d: exit arbitrator: tap out of the table; sent PinSim::FrontEndControls CLOSE_APP (acknowledged: %v)", c.SessionID, ack)
					case arbCloseWMClose:
						ok := sendEditorClose(gameWindowState(c.GamePID, c.SessionID).editorHWND)
						logf("watchdog: session %d: exit arbitrator: VPX still open after the FrontEndControls request; sent WM_CLOSE to the editor window (posted: %v)", c.SessionID, ok)
					case arbGiveUp:
						logf("watchdog: session %d: exit arbitrator: VPX did not close after FrontEndControls + WM_CLOSE; leaving VPX alone", c.SessionID)
					case arbBail:
						// The launcher is not running during play,
						// so the watchdog is the disarming actor
						// (the loop-cap disarm's pattern). VPX is
						// left open in the editor; this process
						// stands down for good.
						logf("watchdog: session %d: exit button held through the threshold at the table exit - hold to editor; disarming and standing down, VPX stays open in the editor", c.SessionID)
						writeContractMerged(func(mc *Contract) { mc.Armed = false; mc.DisarmReason = "hold to editor" })
						return
					}
				} else {
					// Session-close duty (closer.go): in a live session
					// whose table exit landed in the VPX editor, ask VPX
					// to close - orderly, escalating, never a kill. The
					// decision is shared logic; the sends are platform
					// leaves. When VPX dies, the ordinary death path
					// below relaunches the launcher.
					switch sessionCloser.tick(time.Now().UnixMilli(), c.SessionID, c.SessionState, c.CloseVPXOnTableExit, true, gameWindowState(c.GamePID, c.SessionID)) {
					case closeFEC:
						ack := sendFrontEndControlsClose(c.GamePID)
						logf("watchdog: session %d: table exit landed in the VPX editor; sent PinSim::FrontEndControls CLOSE_APP (acknowledged: %v)", c.SessionID, ack)
					case closeWMClose:
						ok := sendEditorClose(gameWindowState(c.GamePID, c.SessionID).editorHWND)
						logf("watchdog: session %d: VPX still open after the FrontEndControls request; sent WM_CLOSE to the editor window (posted: %v)", c.SessionID, ok)
					case closeGiveUp:
						logf("watchdog: session %d: VPX did not close after FrontEndControls + WM_CLOSE; leaving VPX alone", c.SessionID)
					}
				}
			} else if sawGameAlive {
				sawGameAlive = false
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

		// ---- stale watch ----------------------------------------
		if !alive && !launcherAlive(c, relaunchedPID) && c.LastCheckinUnix > 0 && now-c.LastCheckinUnix > staleTimeoutSec {
			logf("watchdog: no launcher check-in for %ds; stale watch, standing down", now-c.LastCheckinUnix)
			return
		}
	}
}
