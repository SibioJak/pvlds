//go:build !windows

package main

import "time"

// Focus herding is a Windows user32 duty (design section 3). On
// every other platform it is deliberately a no-op; the DECISIONS
// (herd_logic.go) are unit-tested here, and the wait / relaunch /
// disarm / loop-cap logic in main.go is platform-free and fully
// exercised here.
func herdTick(_ int, _ int, _ time.Time) {}
