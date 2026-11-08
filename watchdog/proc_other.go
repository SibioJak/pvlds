//go:build !windows && !linux

package main

// PINemHi exit-close leaves off Windows/Linux: no watcher runs
// here, so there is nothing to close gracefully and nothing to
// terminate. The decisions (pinemhi.go) are platform-free and
// unit-tested on Linux; the real leaves are proc_windows.go
// (WM_CLOSE + TerminateProcess) and proc_linux.go (SIGTERM).

func terminateProcess(_ int) bool { return false }

func closeProcessWindows(_ int) bool { return false }
