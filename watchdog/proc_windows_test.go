//go:build windows

package main

import "testing"

// FIX148: the Windows face of the plain creation shape —
// the game spawn's creation flags are ZERO. No
// DETACHED_PROCESS, no CREATE_NEW_PROCESS_GROUP: the plain
// birth the FIX147 neutral spawner proved. If this test
// fails, someone re-armed the detached shape for game
// spawns; the detached leaves (startDetachedInDir) serve
// the PINemHi watcher and the launcher relaunch only.
func TestGameSpawnCreationFlagsAreZero(t *testing.T) {
	if got := gameSpawnCreationFlags(); got != 0 {
		t.Fatalf("game spawn creation flags = %#x, want 0 (plain birth, FIX148)", got)
	}
}
