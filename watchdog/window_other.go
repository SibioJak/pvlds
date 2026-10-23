//go:build !windows && !linux

package main

// gameWindowExists on platforms with no window concept wired up
// (the host build for completeness on e.g. macOS): no sighting is
// ever reported, so a resident launcher's hand-off falls to its
// XR-session and cap cues. The shipping build is Windows; the
// logic-exercising build is Linux; both have real implementations.
func gameWindowExists(_ int, _ int) (bool, string) { return false, "" }

// gameRuntimeExists off Windows/Linux: no runtime is ever
// reported, so the contract's runtime stamp never lands here.
func gameRuntimeExists(_ int, _ int) bool { return false }

// pushFocusToGame off Windows/Linux: there is no foreground to
// hand over here.
func pushFocusToGame(_ int) focusPushOutcome { return focusPushDeclined }

// activateSDLWindow off Windows/Linux: no SDL window exists to
// raise, so the activation sequence stands down on its
// no-target path if it is ever fed here.
func activateSDLWindow(_ int) bool { return false }

// gameWindowState off Windows/Linux: no windows are ever reported,
// so the session-close duties never fire here.
func gameWindowState(_ int, _ int) windowState { return windowState{} }
