//go:build !windows && !linux

package main

// gameWindowExists on platforms with no window concept wired up
// (the host build for completeness on e.g. macOS): no sighting is
// ever reported, so a resident launcher's hand-off falls to its
// XR-session and cap cues. The shipping build is Windows; the
// logic-exercising build is Linux; both have real implementations.
func gameWindowExists(_ int, _ int) (bool, string) { return false, "" }

// gameWindowState off Windows/Linux: no windows are ever reported,
// so the session-close duties never fire here.
func gameWindowState(_ int, _ int) windowState { return windowState{} }
