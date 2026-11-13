package main

import (
	"strings"
	"testing"
)

// The live-session focus guard (guard.go), exercised on
// Linux: scripted foreground walks around the two reclaimable
// holder kinds - the known bystander (the PINemHi LeaderBoard
// board, Chris's field case) and the game's own window family
// - and the deliberate-use evidence that must veto a reclaim:
// desktop input that arrives with or during a holder's
// tenure, unknown provenance, and the per-window yield cap.

const (
	hwGSDL   = uintptr(0xA1)
	hwGBoard = uintptr(0xBD)
	hwGMAME  = uintptr(0xB1)
	hwGEdit  = uintptr(0xE1)
	hwGOther = uintptr(0xC3)
)

func guardWS(class string, pid int, hwnd uintptr, ageMs int64) windowState {
	ws := windowState{inputAgeMs: ageMs}
	ws.fgClass, ws.fgPID, ws.fgHWND = class, pid, hwnd
	ws.fgIsGame = pid == gamePID && pid != 0
	ws.fgIsEditor = ws.fgIsGame && class == editorWindowClass
	ws.fgIsSDL = ws.fgIsGame && class == sdlWindowClass
	ws.playerHWND = hwGSDL
	ws.playerClass = sdlWindowClass
	ws.fgIsPlayer = hwnd == hwGSDL
	return ws
}

func gPlayer() windowState { return guardWS(sdlWindowClass, gamePID, hwGSDL, 60000) }
func gEditor() windowState { return guardWS(editorWindowClass, gamePID, hwGEdit, 60000) }
func gMAME(age int64) windowState {
	return guardWS("MAME", gamePID, hwGMAME, age)
}
func gOther(age int64) windowState { return guardWS("OtherApp", 424242, hwGOther, age) }
func gBoard(age int64) windowState {
	ws := guardWS("PinemhiLeaderboard", stubBystanderPID, hwGBoard, age)
	ws.fgProcName = "PINemHi LeaderBoard.exe"
	ws.fgTitle = "PINemHi LeaderBoard - TOP 5 Personal Best"
	return ws
}

func TestGuardBystanderReclaim(t *testing.T) {
	// Chris's field case: mid-session the board pops over
	// the table with no desktop input anywhere near it. The
	// guard waits out the grace, then takes the foreground
	// back - naming the board.
	var g focusGuard
	if res := g.tick(1000, 1, gPlayer(), false); res.action != guardNone {
		t.Fatalf("player tick: got %v, want none", res.action)
	}
	if res := g.tick(1400, 1, gBoard(60000), false); res.action != guardNone {
		t.Fatalf("board's first tick: got %v, want the grace running", res.action)
	}
	res := g.tick(2400, 1, gBoard(60000), false)
	if res.action != guardAssert {
		t.Fatalf("after the grace: got %v, want the reclaim", res.action)
	}
	if !strings.Contains(res.detail, "reclaimed the foreground from") || !strings.Contains(res.detail, "PINemHi LeaderBoard") {
		t.Fatalf("detail = %q, want the reclaim naming the board", res.detail)
	}
	// The player back in front: healthy, silent.
	if res := g.tick(2800, 1, gPlayer(), false); res.action != guardNone {
		t.Fatalf("player again: got %v, want none", res.action)
	}
}

func TestGuardBystanderInputVetoes(t *testing.T) {
	// Desktop input arrives WHILE the board holds (the age
	// drops between ticks): the tenure is vetoed for good,
	// and no reclaim follows however long it stays.
	var g focusGuard
	g.tick(1000, 1, gPlayer(), false)
	g.tick(1400, 1, gBoard(60000), false)
	res := g.tick(1800, 1, gBoard(50), false)
	if res.action != guardLog || !strings.Contains(res.detail, "deliberate use") {
		t.Fatalf("input during tenure: got (%v, %q), want the veto log", res.action, res.detail)
	}
	if res := g.tick(4000, 1, gBoard(5000), false); res.action != guardNone {
		t.Fatalf("vetoed tenure past grace: got %v, want none", res.action)
	}
	// The board leaves and returns WITH fresh input at the
	// door: vetoed again, on the return's own evidence (the
	// player interval cleared the old latch).
	g.tick(4400, 1, gPlayer(), false)
	res = g.tick(4800, 1, gBoard(50), false)
	if res.action != guardLog || !strings.Contains(res.detail, "deliberate use") {
		t.Fatalf("fresh input at the door: got (%v, %q), want the veto log", res.action, res.detail)
	}
	if res := g.tick(6800, 1, gBoard(2050), false); res.action != guardNone {
		t.Fatalf("door-vetoed tenure past grace: got %v, want none", res.action)
	}
}

func TestGuardEdgeAndUnknownProvenanceVetoes(t *testing.T) {
	// An Alt/Win/mouse edge on the board's first tick: the
	// change was the player's own hand.
	var g focusGuard
	g.tick(1000, 1, gPlayer(), false)
	ws := gBoard(60000)
	ws.altWinEdge = true
	res := g.tick(1400, 1, ws, false)
	if res.action != guardLog || !strings.Contains(res.detail, "deliberate use") {
		t.Fatalf("edge at the door: got (%v, %q), want the veto log", res.action, res.detail)
	}
	if res := g.tick(3400, 1, gBoard(60000), false); res.action != guardNone {
		t.Fatalf("edge-vetoed tenure: got %v, want none", res.action)
	}
	// No provenance at all: unjudgeable, and ambiguity
	// resolves toward the user - never reclaimed over.
	var g2 focusGuard
	g2.tick(1000, 1, gPlayer(), false)
	res = g2.tick(1400, 1, gBoard(-1), false)
	if res.action != guardLog || !strings.Contains(res.detail, "cannot be judged") {
		t.Fatalf("unknown provenance: got (%v, %q), want the unjudgeable log", res.action, res.detail)
	}
	if res := g2.tick(3400, 1, gBoard(-1), false); res.action != guardNone {
		t.Fatalf("unjudgeable tenure: got %v, want none", res.action)
	}
}

func TestGuardUnknownAndEditorUntouched(t *testing.T) {
	// A genuinely unknown process: logged once ("not a known
	// companion"), never reclaimed. The editor: not even
	// logged - the exit detector owns it.
	var g focusGuard
	g.tick(1000, 1, gPlayer(), false)
	res := g.tick(1400, 1, gOther(60000), false)
	if res.action != guardLog || !strings.Contains(res.detail, "not a known companion window") {
		t.Fatalf("unknown holder: got (%v, %q), want the log-only line", res.action, res.detail)
	}
	if res := g.tick(3400, 1, gOther(60000), false); res.action != guardNone {
		t.Fatalf("unknown holder later: got %v, want silence", res.action)
	}
	g.tick(3800, 1, gPlayer(), false)
	if res := g.tick(4200, 1, gEditor(), false); res.action != guardNone {
		t.Fatalf("editor holder: got %v, want none", res.action)
	}
	if res := g.tick(6200, 1, gEditor(), false); res.action != guardNone {
		t.Fatalf("editor holder later: got %v, want none", res.action)
	}
}

func TestGuardGameFamilyReclaim(t *testing.T) {
	// The game's own non-player window (PinMAME) holding the
	// foreground cold is reclaimable like a bystander's.
	var g focusGuard
	g.tick(1000, 1, gPlayer(), false)
	g.tick(1400, 1, gMAME(60000), false)
	res := g.tick(2400, 1, gMAME(60000), false)
	if res.action != guardAssert || !strings.Contains(res.detail, "game's own window family") {
		t.Fatalf("got (%v, %q), want the family reclaim", res.action, res.detail)
	}
}

func TestGuardYieldCap(t *testing.T) {
	// The same window keeps coming back: three reclaims,
	// then the guard yields for the session - the player is
	// assumed to be keeping it there on purpose.
	var g focusGuard
	now := int64(1000)
	g.tick(now, 1, gPlayer(), false)
	for pop := 1; pop <= 3; pop++ {
		now += 400
		if res := g.tick(now, 1, gBoard(60000), false); res.action != guardNone {
			t.Fatalf("pop %d first tick: got %v, want the grace", pop, res.action)
		}
		now += 1000
		if res := g.tick(now, 1, gBoard(60000), false); res.action != guardAssert {
			t.Fatalf("pop %d: got %v, want reclaim %d", pop, res.action, pop)
		}
		now += 400
		g.tick(now, 1, gPlayer(), false)
	}
	now += 400
	g.tick(now, 1, gBoard(60000), false)
	now += 1000
	res := g.tick(now, 1, gBoard(60000), false)
	if res.action != guardLog || !strings.Contains(res.detail, "yielding for this session") {
		t.Fatalf("fourth pop: got (%v, %q), want the yield log", res.action, res.detail)
	}
	now += 1600
	if res := g.tick(now, 1, gBoard(60000), false); res.action != guardNone {
		t.Fatalf("after the yield: got %v, want silence", res.action)
	}
}

func TestGuardCloserBusyPausesGrace(t *testing.T) {
	// While a close ladder is in flight the guard stands
	// down, and the grace restarts when the ladder clears -
	// a reclaim mid-ladder could fight the exit detector.
	var g focusGuard
	g.tick(1000, 1, gPlayer(), false)
	g.tick(1400, 1, gBoard(60000), false)
	if res := g.tick(2000, 1, gBoard(60000), true); res.action != guardNone {
		t.Fatalf("busy tick: got %v, want none", res.action)
	}
	if res := g.tick(2600, 1, gBoard(60000), true); res.action != guardNone {
		t.Fatalf("busy tick 2: got %v, want none", res.action)
	}
	if res := g.tick(3000, 1, gBoard(60000), false); res.action != guardNone {
		t.Fatalf("just unbusy: got %v, want the grace restarted", res.action)
	}
	if res := g.tick(3600, 1, gBoard(60000), false); res.action != guardAssert {
		t.Fatalf("grace after the ladder: got %v, want the reclaim", res.action)
	}
}

func TestBystanderRegistrySignals(t *testing.T) {
	// The registry's two-signal law: one signal is never
	// enough, whatever it is.
	one := holderFacts{proc: "PINemHi LeaderBoard.exe", class: "X", title: "Scores"}
	if _, ok := matchBystander(one); ok {
		t.Fatal("one signal (process) matched; want no match")
	}
	one = holderFacts{proc: "other.exe", class: "X", title: "Just TOP 5 things"}
	if _, ok := matchBystander(one); ok {
		t.Fatal("one signal (title fragment) matched; want no match")
	}
	one = holderFacts{proc: "other.exe", class: "PinemhiLeaderboard", title: "Scores"}
	if _, ok := matchBystander(one); ok {
		t.Fatal("one signal (class-ish title) matched; want no match")
	}
	two := holderFacts{proc: "PINemHi LeaderBoard.exe", class: "PinemhiLeaderboard", title: "PINemHi LeaderBoard - TOP 5 Personal Best"}
	if name, ok := matchBystander(two); !ok || name != "PINemHi LeaderBoard" {
		t.Fatalf("the board's own facts: got (%q, %v), want the match", name, ok)
	}
}
