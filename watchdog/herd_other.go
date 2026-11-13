//go:build !windows

package main

import "time"

// Focus herding is a Windows user32 duty (design section 3). On
// every other platform it is deliberately a no-op; the DECISIONS
// (herd_logic.go) are unit-tested here, and the wait / relaunch /
// disarm / loop-cap logic in main.go is platform-free and fully
// exercised here. (The Linux leaf's focus duties proper - the
// sequence's and guard's raises - live in window_linux.go's
// activatePlayerWindow; herding's own tick remains a no-op
// because the stub scripts foreground facts, not a real
// foreground to herd.)
func herdTick(_ int, _ int, _ time.Time, _ uintptr) {}
