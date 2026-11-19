//go:build !windows && !linux

package main

import "errors"

// PINemHi exit-close leaves off Windows/Linux: no watcher runs
// here, so there is nothing to close gracefully and nothing to
// terminate. The decisions (pinemhi.go) are platform-free and
// unit-tested on Linux; the real leaves are proc_windows.go
// (WM_CLOSE + TerminateProcess) and proc_linux.go (SIGTERM).

func terminateProcess(_ int) bool { return false }

func closeProcessWindows(_ int) bool { return false }

// startDetached / startDetachedInDir have no leaf off
// Windows/Linux (FIX143's spawn mode shares them): nothing
// starts from here.
func startDetached(_ string, _ []string) (int, error) {
	return 0, errors.New("startDetached: unsupported platform")
}

func startDetachedInDir(_ string, _ []string, _ string) (int, error) {
	return 0, errors.New("startDetachedInDir: unsupported platform")
}

func startDetachedInDirAndWait(_ string, _ []string, _ string, _ func(pid int)) (int, error) {
	return 0, errors.New("startDetachedInDirAndWait: unsupported platform")
}

func startSpawnInDirAndWait(_ string, _ []string, _ string, _ bool, _ func(pid int)) (int, error) {
	return 0, errors.New("startSpawnInDirAndWait: unsupported platform")
}

// processExistsByName has no leaf off Windows/Linux: no B2S
// server runs here, so the FIX145 sighting reads absent.
func processExistsByName(_ string) bool { return false }
