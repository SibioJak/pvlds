package main

// FIX145 diag seams: the parser's tolerance law, the spawn
// flavour's detach decision (the creation-flags difference
// the brief's NC names - the platform leaves map this one
// decision onto their flags), the herd-hold window, and the
// B2S sighting's name match + change tracker.

import "testing"

func TestParseDiagSettings(t *testing.T) {
	d := parseDiagSettings("")
	if d.Spawn != diagSpawnHelper || d.Herd != diagHerdOn {
		t.Fatalf("empty text must be the defaults, got %+v", d)
	}
	d = parseDiagSettings("spawn=console\nherd=held\n")
	if d.Spawn != diagSpawnConsole || d.Herd != diagHerdHeld {
		t.Fatalf("a full file must parse, got %+v", d)
	}
	d = parseDiagSettings("# a comment\n\n  Spawn = PLAIN \nHERD=on\n")
	if d.Spawn != diagSpawnPlain || d.Herd != diagHerdOn {
		t.Fatalf("case/whitespace must be tolerated, got %+v", d)
	}
	d = parseDiagSettings("spawn=bogus\nherd=sideways\nunknown=key\nnoequals\n")
	if d.Spawn != diagSpawnHelper || d.Herd != diagHerdOn {
		t.Fatalf("unknown values must degrade per-seam to defaults, got %+v", d)
	}
	d = parseDiagSettings("spawn=console\nspawn=helper\n")
	if d.Spawn != diagSpawnHelper {
		t.Fatalf("the last line wins, got %+v", d)
	}
}

func TestSpawnDetachedDecision(t *testing.T) {
	// The brief's NC in decision form: the console flavour's
	// creation shape MUST differ from the default's.
	if !spawnDetached(diagSpawnHelper) {
		t.Fatal("helper must spawn detached (the 1.1.31 shape)")
	}
	if !spawnDetached(diagSpawnPlain) {
		t.Fatal("plain is the app's road; if the helper is ever invoked under it, it keeps the detached shape")
	}
	if spawnDetached(diagSpawnConsole) {
		t.Fatal("console must NOT spawn detached - that difference is the seam")
	}
}

func TestHerdHoldWindow(t *testing.T) {
	held := diagSettings{Spawn: diagSpawnHelper, Herd: diagHerdHeld}
	on := diagSettings{Spawn: diagSpawnHelper, Herd: diagHerdOn}
	var h herdHold
	h.noteSession(7)
	if !h.active(held, 7, 1000) {
		t.Fatal("held must be in force from session start (before any lock)")
	}
	if h.active(on, 7, 1000) {
		t.Fatal("herd=on must never hold")
	}
	if h.active(held, 8, 1000) {
		t.Fatal("a different session must not read held")
	}
	h.noteLock(7, 5000)
	if !h.active(held, 7, 5000+herdHoldAfterLockMs-1) {
		t.Fatal("held must still be in force inside the post-lock tail")
	}
	if h.active(held, 7, 5000+herdHoldAfterLockMs) {
		t.Fatal("held must lift at focus lock + 20s")
	}
	// A fresh session starts a fresh window, lock forgotten.
	h.noteSession(9)
	if !h.active(held, 9, 5000+herdHoldAfterLockMs) {
		t.Fatal("a new session's hold starts at its own start, lock or no")
	}
}

func TestB2SSighting(t *testing.T) {
	if !isB2SServerName("B2SBackglassServerEXE") || !isB2SServerName("B2SBackglassServerEXE.exe") ||
		!isB2SServerName("b2sbackglassserverexe.EXE") {
		t.Fatal("the server's name must match in both spellings, any case")
	}
	if isB2SServerName("B2SBackglassServer") || isB2SServerName("VPinballX_GL64.exe") || isB2SServerName("") {
		t.Fatal("other names must not match")
	}
	var s b2sSighting
	if !s.observe(3, false) {
		t.Fatal("a session's first observation must speak (the absent fact is the field answer)")
	}
	if s.observe(3, false) {
		t.Fatal("an unchanged fact must stay silent")
	}
	if !s.observe(3, true) {
		t.Fatal("a change must speak")
	}
	if s.observe(3, true) {
		t.Fatal("a settled fact must stay silent")
	}
	if !s.observe(4, true) {
		t.Fatal("a new session's first observation must speak even when the fact matches the last session's")
	}
}
