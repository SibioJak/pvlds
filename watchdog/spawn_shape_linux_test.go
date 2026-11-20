//go:build linux

package main

import "testing"

// FIX148: the Linux face of the plain creation shape — the
// game is never born in its own session. (The Windows face
// is pinned in proc_windows_test.go.)
func TestGameSpawnSetsidIsFalse(t *testing.T) {
	if gameSpawnSetsid() {
		t.Fatal("the game spawn must not Setsid - the plain birth is the FIX148 shape")
	}
}
