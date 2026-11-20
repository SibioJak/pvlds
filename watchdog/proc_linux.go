package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

func processAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}

// findPIDsByExe matches /proc/*/exe symlinks against the target
// path; the scan folders' files are what the launcher spawned, so
// exact path equality is the normal case.
func findPIDsByExe(exePath string) []int {
	var out []int
	target, err := filepath.EvalSymlinks(exePath)
	if err != nil {
		target = exePath
	}
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return out
	}
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid == os.Getpid() {
			continue
		}
		link, err := os.Readlink(filepath.Join("/proc", e.Name(), "exe"))
		if err != nil {
			continue
		}
		link = strings.TrimSuffix(link, " (deleted)")
		if link == target {
			out = append(out, pid)
		}
	}
	return out
}

// terminateProcess is the hard stop behind the PINemHi exit
// close's grace (pinemhi.go): SIGTERM, which a well-behaved
// watcher (and the smoke's stub) traps as its stop signal.
func terminateProcess(pid int) bool {
	if pid <= 0 {
		return false
	}
	return syscall.Kill(pid, syscall.SIGTERM) == nil
}

// closeProcessWindows has no window messaging to send on Linux:
// the graceful step reports false and the exit close proceeds
// to its grace + terminate, which is what the stub traps.
func closeProcessWindows(_ int) bool { return false }

// startDetached starts the process in its own session so it
// survives the watchdog, and returns its pid without waiting.
func startDetached(path string, args []string) (int, error) {
	return startDetachedInDir(path, args, "")
}

// startDetachedInDir is startDetached with the child's working
// directory set ("" keeps the inherited one). WATCHERFIX: the
// PINemHi watcher resolves pinemhi.ini relative to its working
// directory, so its start must name its own folder; the launcher
// relaunch keeps startDetached (inherited dir) exactly as before.
func startDetachedInDir(path string, args []string, dir string) (int, error) {
	cmd := exec.Command(path, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	go cmd.Wait()
	return pid, nil
}

// gameSpawnSetsid pins the FIX148 game-spawn session shape:
// the game is NOT born in its own session — no Setsid, the
// plain birth the FIX147 neutral spawner proved (the child
// stays in the helper's session and process group, like a
// shell's child stays in the shell's). Setsid survives only
// in startDetachedInDir, whose callers (the PINemHi watcher
// start, the launcher relaunch) are not game spawns and keep
// their shape. Unit-tested (spawn_mode_test.go).
func gameSpawnSetsid() bool { return false }

// startGameInDirAndWait is the spawn mode's leaf (FIX143's
// supervised shape, FIX148's creation shape): a plain start
// in the named directory — gameSpawnSetsid, no new session —
// with env as the child's environment when non-nil (nil
// keeps the inherited one untouched; the spawn mode passes a
// scrubbed copy, see scrubGameEnv in spawn_mode.go). The
// caller BLOCKS until the child exits — the helper process
// supervises the game, living exactly as long as it does, so
// the launcher (the helper's parent) can judge the game's
// life by its own child's. onStart, when given, is called
// with the child's pid immediately after the start lands.
func startGameInDirAndWait(path string, args []string, dir string, env []string, onStart func(pid int)) (int, error) {
	cmd := exec.Command(path, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	if env != nil {
		cmd.Env = env
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: gameSpawnSetsid()}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	if onStart != nil {
		onStart(pid)
	}
	_ = cmd.Wait() // the exit code is the game's own; the supervision is the service
	return pid, nil
}

// processExistsByName reports whether any live process's
// image base name matches name (case-insensitive, a trailing
// ".exe" on either side ignored - see b2s_sighting.go), via
// the /proc exe symlinks - the same source findPIDsByExe
// reads. The FIX145 B2S server sighting's Linux leaf.
func processExistsByName(name string) bool {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return false
	}
	for _, e := range entries {
		if _, err := strconv.Atoi(e.Name()); err != nil {
			continue
		}
		link, err := os.Readlink(filepath.Join("/proc", e.Name(), "exe"))
		if err != nil {
			continue
		}
		link = strings.TrimSuffix(link, " (deleted)")
		if sameProcessName(filepath.Base(link), name) {
			return true
		}
	}
	return false
}
