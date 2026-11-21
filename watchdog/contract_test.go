package main

// FIX155 invariant legs for the contract mirror: the
// hunt-stack fields (FIX152's cold-spawn order,
// FIX149/150's hand-off gate and its sighting feed)
// are gone from the writers, and a stale contract
// still carrying them is inert - parsed without them,
// never written back with them, and above all never
// acted on: this process contains no VPX-spawn path
// a contract could order.

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// Leg: a contract carrying a stale spawn_pending (a
// 1.1.37-1.1.39 cold-spawn order that never fired)
// is ignored - no birth, and no name window either:
// the feed keys on game_table_path alone, never on
// the retired spec fields the order carried.
func TestStaleSpawnOrderIsIgnored(t *testing.T) {
	f := swapNameWindowFake(t)
	stale := []byte(`{
		"version": 2,
		"armed": true,
		"session_id": 11,
		"session_state": "loading",
		"game_exe_path": "D:\\vPinball\\VisualPinball\\VPinballX_GL64.exe",
		"spawn_pending": true,
		"game_args": ["-play", "D:\\vPinball\\VisualPinball\\Tables\\Big Chief (Williams 1965)_Teisen_MOD.vpx"],
		"game_cwd": "D:\\vPinball\\VisualPinball",
		"handoff_gate": "held",
		"b2s_present_since_unix": 1700000000,
		"b2s_seen_unix": 1700000000
	}`)
	var c Contract
	if err := json.Unmarshal(stale, &c); err != nil {
		t.Fatalf("a stale contract must parse: %v", err)
	}
	if !c.Armed || c.SessionID != 11 || c.SessionState != "loading" {
		t.Fatalf("the standing fields must survive the parse: %+v", c)
	}
	// The name feed's trigger reads the contract and
	// finds no table path - the retired game_args is
	// not a name feed, so nothing is raised.
	observeNameFeed(&c, time.Unix(1_700_000_000, 0))
	if sessionNameWindow.up() || len(f.events) != 0 {
		t.Fatalf("the stale order raised something: events = %v, tracker = %+v", f.events, sessionNameWindow)
	}
	// And a merged write of the parsed contract drops
	// the retired keys for good.
	out, err := json.Marshal(&c)
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"spawn_pending", "game_args", "game_cwd", "handoff_gate", "b2s_present_since_unix", "b2s_seen_unix"} {
		if strings.Contains(string(out), `"`+key+`"`) {
			t.Fatalf("the re-written contract still carries %q: %s", key, out)
		}
	}
}

// Leg: the contract round-trip from the new writers
// carries no handoff_gate and no spawn fields - and
// the standing fields, game_table_path included,
// survive the trip intact.
func TestContractRoundTripCarriesNoRetiredFields(t *testing.T) {
	c := &Contract{
		Version:       2,
		Armed:         true,
		SessionID:     12,
		SessionState:  "loading",
		GameExePath:   `D:\vPinball\VisualPinball\VPinballX_GL64.exe`,
		GameTablePath: `D:\vPinball\VisualPinball\Tables\Big Chief (Williams 1965)_Teisen_MOD.vpx`,
		GamePID:       4242,
		LauncherPath:  `C:\PVLDS\LaunchPin.exe`,
	}
	out, err := json.Marshal(c)
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"spawn_pending", "game_args", "game_cwd", "handoff_gate", "b2s_present_since_unix", "b2s_seen_unix"} {
		if strings.Contains(string(out), `"`+key+`"`) {
			t.Fatalf("the written contract carries %q: %s", key, out)
		}
	}
	var back Contract
	if err := json.Unmarshal(out, &back); err != nil {
		t.Fatal(err)
	}
	if back.SessionID != 12 || back.SessionState != "loading" || back.GamePID != 4242 ||
		back.GameTablePath != c.GameTablePath || back.GameExePath != c.GameExePath {
		t.Fatalf("the round-trip lost standing fields: %+v", back)
	}
}
