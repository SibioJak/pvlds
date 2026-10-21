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

// startDetached starts the process in its own session so it
// survives the watchdog, and returns its pid without waiting.
func startDetached(path string, args []string) (int, error) {
	cmd := exec.Command(path, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	pid := cmd.Process.Pid
	go cmd.Wait()
	return pid, nil
}
