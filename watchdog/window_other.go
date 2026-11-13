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
func gameRuntimeExists(_ int, _ int) (bool, string) { return false, "" }

// activatePlayerWindow off Windows/Linux: no player window
// exists to raise, so the focus duties stand their attempts
// down if they are ever fed here.
func activatePlayerWindow(_ int, _ uintptr) (bool, bool) { return false, false }

// noteForegroundOwner off Windows/Linux: no owner inventory
// exists to log.
func noteForegroundOwner(_ int, _ windowState) {}

// gameWindowState off Windows/Linux: no windows are ever reported,
// so the session-close duties never fire here. The input age
// reads unknown (-1), as the focus duties' contract requires
// of a leaf that cannot know it.
func gameWindowState(_ int, _ int) windowState { return windowState{inputAgeMs: -1} }
