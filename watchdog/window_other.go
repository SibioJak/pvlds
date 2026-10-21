//go:build !windows && !linux

package main

// gameWindowExists on platforms with no window concept wired up
// (the host build for completeness on e.g. macOS): no window is
// ever reported, so a resident launcher's hand-off falls to its
// XR-session and cap cues. The shipping build is Windows; the
// logic-exercising build is Linux; both have real implementations.
func gameWindowExists(_ int) bool { return false }
