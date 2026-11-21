package main

import (
	"os"
	"path/filepath"
	"testing"
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

// (FIX152's spawn_delay_sec pins stood here: the cold
// spawn's diag key, its parser legs and the delay
// decision. FIX155 removed the cold spawn and the key
// with it; a diag file still carrying the key parses
// past it - TestDiagJunkChangesNothing's law covers
// unknown keys.)
