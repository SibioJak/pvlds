// PVLDS watchdog: the tiny resident process that makes the hand-off
// round trip work (design sections 3/5/6 in
// ~/workspace/vpx-vr-launcher/design.md).
//
// The launcher exits completely when a table launches - absence is
// the fix for the OpenXR/focus fights. Something has to notice when
// VPX dies and bring the launcher back. That is all this process is:
//
//   - poll the session contract JSON the launcher writes,
//   - while a session is live, watch the game process (and, on
//     Windows, herd foreground focus back to the game window),
//   - when the game dies (exit or crash - same handling), relaunch
//     the launcher exactly once per death,
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
	"time"
)

type Contract struct {
	Version         int      `json:"version"`
	Armed           bool     `json:"armed"`
	FocusHerding    bool     `json:"focus_herding"`
	SessionID       int      `json:"session_id"`
	SessionState    string   `json:"session_state"`
	GameExePath     string   `json:"game_exe_path"`
	GamePID         int      `json:"game_pid"`
	GameStartedUnix int64    `json:"game_started_unix"`
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
)

func logf(format string, args ...interface{}) {
	line := fmt.Sprintf("%s %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
	if logFile != nil {
		logFile.WriteString(line)
		logFile.Sync()
	}
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
		sawGameAlive     bool
		gameSeenAt       int64
		awaitingOutcome  bool
		relaunchedPID    int
		relaunchedAt     int64
		sessionAtRelaunch int
		strikes          int
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
			if mc.SessionState == "playing" || mc.SessionState == "launching" {
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
			logf("watchdog: contract disarmed (player Exit); standing down")
			return
		}
		now := time.Now().Unix()
		sessionActive := c.SessionState == "launching" || c.SessionState == "playing"
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
						writeContractMerged(func(mc *Contract) { mc.Armed = false })
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
					gameSeenAt = now
					logf("watchdog: game process live (pid %d), session %d", gpid, c.SessionID)
				}
				if c.FocusHerding {
					herdTick(c.GamePID, gameSeenAt, now)
				}
			} else if sawGameAlive {
				logf("watchdog: game process died, session %d; relaunching launcher", c.SessionID)
				sawGameAlive = false
				relaunch(c, "game exited")
				continue
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
