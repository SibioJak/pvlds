//go:build !windows

package main

// Focus herding is a Windows user32 duty (design section 3). On
// every other platform it is deliberately a no-op; the wait /
// relaunch / disarm / loop-cap logic in main.go is platform-free
// and fully exercised here.
func herdTick(_ int, _ int64, _ int64) {}
