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

// spawnSetsid maps the FIX145 spawn flavour's one
// platform-free decision (diag.go's spawnDetached) onto the
// Linux start: the detached flavours are born in their own
// session (Setsid - startDetached's shape); the console
// flavour gets no Setsid, so the child stays in the helper's
// session and process group like a shell's child stays in
// the shell's.
func spawnSetsid(detached bool) bool { return detached }

// startDetachedInDirAndWait is the FIX143 spawn mode's leaf:
// the same detached start as startDetachedInDir, but the
// caller BLOCKS until the child exits — the helper process
// supervises the game, living exactly as long as it does, so
// the launcher (the helper's parent) can judge the game's
// life by its own child's. onStart, when given, is called
// with the child's pid immediately after the start lands.
func startDetachedInDirAndWait(path string, args []string, dir string, onStart func(pid int)) (int, error) {
	return startSpawnInDirAndWait(path, args, dir, true, onStart)
}

// startSpawnInDirAndWait is startDetachedInDirAndWait with
// the FIX145 spawn flavour's creation shape: detached=true
// is the FIX143 leaf above, byte for byte; detached=false is
// the console flavour - the same supervised start without
// Setsid (spawnSetsid).
func startSpawnInDirAndWait(path string, args []string, dir string, detached bool, onStart func(pid int)) (int, error) {
	cmd := exec.Command(path, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: spawnSetsid(detached)}
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
