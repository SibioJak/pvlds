package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// FIX151: the diag seam's parser pins. The field protocol
// is a hand-written one-line file on a machine whose
// clipboard mangles pastes - the parser must be liberal
// about shape and strict about meaning: only an exact
// herd=off (after case/space/comment tolerance) stands
// the focus family down.

func writeDiag(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "pvlds_diag.txt"), []byte(body), 0644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestDiagAbsentIsDefault(t *testing.T) {
	st := readDiag(t.TempDir())
	if st.present || st.herdOff {
		t.Fatalf("absent file: got %+v, want the silent default", st)
	}
}

func TestDiagHerdOff(t *testing.T) {
	st := readDiag(writeDiag(t, "herd=off\n"))
	if !st.present || !st.herdOff {
		t.Fatalf("herd=off: got %+v, want present + herdOff", st)
	}
}

func TestDiagHerdOnIsNotOff(t *testing.T) {
	st := readDiag(writeDiag(t, "herd=on\n"))
	if !st.present || st.herdOff {
		t.Fatalf("herd=on: got %+v, want present + not off", st)
	}
}

func TestDiagToleratesShape(t *testing.T) {
	st := readDiag(writeDiag(t, "# a note\n  Herd = OFF   # the second cell\nspawn=plain\n\n"))
	if !st.present || !st.herdOff {
		t.Fatalf("tolerant parse: got %+v, want present + herdOff", st)
	}
}

func TestDiagJunkChangesNothing(t *testing.T) {
	st := readDiag(writeDiag(t, "herd\nhard=off\n=off\nherd=\n"))
	if !st.present || st.herdOff {
		t.Fatalf("junk: got %+v, want present + not off", st)
	}
}

func TestDiagLineSplits(t *testing.T) {
	if k, v, ok := parseDiagLine("herd=off"); !ok || k != "herd" || v != "off" {
		t.Fatalf("plain: %q %q %v", k, v, ok)
	}
	if _, _, ok := parseDiagLine("no equals here"); ok {
		t.Fatal("a line without = must not parse")
	}
	if _, _, ok := parseDiagLine("# herd=off"); ok {
		t.Fatal("a commented-out setting must not parse")
	}
}

// FIX152: the cold spawn's spawn_delay_sec pins - the
// same liberal-about-shape, strict-about-meaning law.
// A usable integer (0 included: no quiet at all) is a
// setting; junk, negative, empty and float values are
// NO setting, and the caller's default stands.

func TestDiagSpawnDelayParses(t *testing.T) {
	st := readDiag(writeDiag(t, "spawn_delay_sec=10\n"))
	if !st.present || !st.spawnDelaySet || st.spawnDelaySec != 10 {
		t.Fatalf("spawn_delay_sec=10: got %+v, want present + set + 10", st)
	}
	st = readDiag(writeDiag(t, "herd=off\n  Spawn_Delay_Sec = 0  # no quiet\n"))
	if !st.herdOff || !st.spawnDelaySet || st.spawnDelaySec != 0 {
		t.Fatalf("tolerant zero: got %+v, want herdOff + set + 0", st)
	}
}

func TestDiagSpawnDelayJunkIsNoSetting(t *testing.T) {
	for _, body := range []string{
		"spawn_delay_sec=soon\n",
		"spawn_delay_sec=-5\n",
		"spawn_delay_sec=\n",
		"spawn_delay_sec=2.5\n",
		"# spawn_delay_sec=3\n",
	} {
		st := readDiag(writeDiag(t, body))
		if st.spawnDelaySet {
			t.Fatalf("%q: got %+v, want no setting", body, st)
		}
	}
}

// The delay decision itself (coldspawn.go): a stated
// value wins verbatim; anything else is the default.
func TestColdSpawnDelayDecision(t *testing.T) {
	if d, from := coldSpawnDelay(diagState{}); d != defaultSpawnDelaySec*time.Second || from {
		t.Fatalf("absent: got %v/%v, want the default", d, from)
	}
	if d, from := coldSpawnDelay(diagState{spawnDelaySec: 2, spawnDelaySet: true}); d != 2*time.Second || !from {
		t.Fatalf("stated 2: got %v/%v, want 2s from diag", d, from)
	}
	if d, from := coldSpawnDelay(diagState{spawnDelaySec: 0, spawnDelaySet: true}); d != 0 || !from {
		t.Fatalf("stated 0: got %v/%v, want 0 from diag", d, from)
	}
}
