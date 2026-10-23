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
//     closer.go). The close duty is unconditional - there is no
//     hold gesture
//     and no exit switch (both were stricken by the player's
//     ruling, 2026-10-22): D-pad right is a plain BACK button -
//     in play it is VPX's own Exit Game binding and lands in the
//     editor, which this duty then closes promptly; in the room
//     the same press quits the app (the launcher's side),
//   - stamp the contract when the game's player window is first
//     sighted (runtime.go's sibling, sighting.go - the exit
//     detector arms on it) and again when the game's table
//     RUNTIME first exists (runtime.go): the runtime stamp is
//     the resident launcher's hand-off cue, because the
//     sighting stamps off the editor's own canvas seconds
//     before a real load finishes,
//   - at the hand-off (the session live, the supervising
//     launcher gone), hand the foreground to the game process
//     ONCE - a single deliberate push, not herding - so the
//     table does not come up unfocused (no sound, no
//     controller) behind whatever the launcher's exit left in
//     front,
//   - and once the table's runtime is up in a live session,
//     run ONE aimed activation (activation.go): when the
//     startup foreground shuffle settles, put the foreground
//     on the game's SDL window specifically - the process-level
//     push above stood down in the field while PinMAME's
//     window held the foreground and the SDL window, which
//     owns input, never did (no gamepad, no sound, until the
//     player alt-tabbed),
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
	// No close-duty or hold keys: the exit model was simplified
	// (2026-10-22) - the close duty is unconditional and there is
	// no hold gesture. Contracts written by older builds may
	// still carry close_vpx_on_table_exit / hold_exit_enabled /
	// hold_exit_button; encoding/json ignores unknown keys on
	// read, and merged writes here simply stop carrying them.
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

	var (
		sawGameAlive      bool
		awaitingOutcome   bool
		relaunchedPID     int
		relaunchedAt      int64
		sessionAtRelaunch int
		strikes           int
		sessionCloser     closer
		focusPushSession  int  // the session the one-shot focus handoff belongs to
		focusPushed       bool // the handoff has been attempted for focusPushSession
		sessionActivator  activator
		actRuntimeSession int   // the session actRuntimeMs belongs to
		actRuntimeMs      int64 // first tick the session's runtime stamp was observed (the activation deadline's anchor)
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
					if gameRuntimeExists(c.GamePID, c.SessionID) {
						logf("watchdog: game runtime up (pid %d), session %d", c.GamePID, c.SessionID)
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
				// One-shot focus handoff: the first tick the
				// session is live with the supervising launcher
				// observed gone is the hand-off moment, and the
				// foreground belongs to nobody in particular -
				// whatever the launcher's exit left in front.
				// A table that comes up behind that comes up
				// unfocused (no sound, no controller; the field
				// fix was the player alt-tabbing). So the
				// watchdog pushes the foreground to the game
				// process ONCE - a single deliberate push at
				// the one moment it is ours to give, not
				// herding (which never runs live). The attempt
				// is recorded with the exit detector either
				// way (notePush): excursions at or before this
				// tick may be the push's own placement, so
				// arming waits for a later one (closer.go).
				if focusPushSession != c.SessionID {
					focusPushSession = c.SessionID
					focusPushed = false
				}
				if !focusPushed && (c.SessionState == "live" || promoted) && c.LauncherPID > 0 && !processAlive(c.LauncherPID) {
					focusPushed = true
					sessionCloser.notePush(c.SessionID, time.Now().UnixMilli())
					switch pushFocusToGame(c.GamePID) {
					case focusPushHanded:
						logf("watchdog: session %d: handed focus to the game (one-shot)", c.SessionID)
					case focusPushAlready:
						logf("watchdog: session %d: game already holds the foreground", c.SessionID)
					default:
						logf("watchdog: session %d: focus push declined by Windows", c.SessionID)
					}
				}
				// The activation deadline's anchor: the first
				// tick this watchdog observes the session's
				// runtime stamp (tracked in either session
				// state - the stamp lands during loading,
				// while the sequence itself runs live, below).
				if actRuntimeSession != c.SessionID {
					actRuntimeSession = c.SessionID
					actRuntimeMs = 0
				}
				if actRuntimeMs == 0 && gameRuntimeExists(c.GamePID, c.SessionID) {
					actRuntimeMs = time.Now().UnixMilli()
				}
				// Focus herding serves the loading phase's
				// spawn settle ONLY (herdingAllowed): once the
				// session is live it never runs - on the VR rig
				// its only anchor there is the editor frame,
				// which it was caught forcing to the foreground
				// mid-play, polluting the exit detector's
				// signal below.
				if herdingAllowed(c.FocusHerding, c.SessionState) {
					herdTick(c.GamePID, c.SessionID, time.Now())
				}
				// Session activation (activation.go): once the
				// runtime is up and the session is live, ONE
				// aimed activation of the game's SDL window
				// after the startup foreground shuffle settles.
				// The ef8 focus push above works at PROCESS
				// level and stood down in the field ("game
				// already holds the foreground") while the
				// table had neither gamepad nor sound: the
				// foreground sat on PinMAME's window, and the
				// SDL window - the one that owns input - never
				// held it. This duty works at WINDOW level. A
				// push it orders is recorded with the exit
				// detector exactly like the focus push
				// (notePush: the detector counts excursions
				// from facts after our last foreground touch),
				// and it runs BEFORE the detector's tick below,
				// so the record precedes the reading.
				if c.SessionState == "live" {
					nowMs := time.Now().UnixMilli()
					switch act := sessionActivator.tick(nowMs, c.SessionID, actRuntimeMs, ws); act {
					case actPushNow:
						attempted := activateSDLWindow(c.GamePID)
						if attempted {
							sessionCloser.notePush(c.SessionID, nowMs)
						}
						if sessionActivator.notePushAttempted(nowMs, attempted) == actLogNoTarget {
							logf("watchdog: session %d: activation - the game has no SDL window to activate; standing down", c.SessionID)
						}
					case actLogNotNeeded:
						logf("watchdog: session %d: activation not needed - the SDL window already holds the foreground", c.SessionID)
					case actLogStuck:
						logf("watchdog: session %d: activation - foreground was %q; set to the game's SDL window (stuck)", c.SessionID, sessionActivator.beforeClass())
					case actLogFailed:
						logf("watchdog: session %d: activation - foreground was %q; set to the game's SDL window (did not stick after retry)", c.SessionID, sessionActivator.beforeClass())
					case actLogEditor:
						logf("watchdog: session %d: activation - the editor holds the foreground; standing down", c.SessionID)
					case actLogThirdParty:
						logf("watchdog: session %d: activation - foreground held by %q (another process); standing down", c.SessionID, ws.fgClass)
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
