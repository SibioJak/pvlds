package main

// pvlds_diag.txt (FIX151): the field diagnostic seam's
// second life. FIX145 introduced the file (spawn and herd
// seams) and FIX148 removed its readers when the spawn
// shape settled; FIX151 brings back exactly one key:
//
//	herd=off   for the session, the whole focus family
//	           stands down - no focus herding, no
//	           activation cycle, no focus sequence, no
//	           focus guard. Sightings, supervision, exit
//	           detection and the closer are untouched.
//
// (FIX152's spawn_delay_sec key stood here in
// 1.1.37–1.1.39: the cold spawn's settle delay. FIX155
// removed the cold spawn, and the key died with it -
// a diag file still carrying it is parsed past, like
// any unknown key.)
//
// The file lives beside the contract (the app data dir -
// the place the FIX145 protocol used and the place the
// FIX151 field protocol puts it). An absent file is the
// default: today's behaviour exactly. The state is read
// fresh at each session's first tick and latched for
// that session, so a file dropped in mid-run arms the
// NEXT session, never a half-changed one. A file that is
// present but unreadable or malformed changes nothing:
// a corrupt diag must never change behaviour.

import (
	"os"
	"path/filepath"
	"strings"
)

// diagState is what one read of pvlds_diag.txt decided.
type diagState struct {
	present bool // the file was there (its contents may still be junk)
	herdOff bool // it carries herd=off
}

// readDiag reads and parses the diag file in dir.
func readDiag(dir string) diagState {
	data, err := os.ReadFile(filepath.Join(dir, "pvlds_diag.txt"))
	if err != nil {
		return diagState{}
	}
	st := diagState{present: true}
	for _, line := range strings.Split(string(data), "\n") {
		k, v, ok := parseDiagLine(line)
		if !ok {
			continue
		}
		if k == "herd" && v == "off" {
			st.herdOff = true
		}
	}
	return st
}

// parseDiagLine splits one "key=value" line, tolerating
// whitespace, case, and # comments (whole-line and
// trailing). Anything malformed is not a setting.
func parseDiagLine(line string) (string, string, bool) {
	if i := strings.Index(line, "#"); i >= 0 {
		line = line[:i]
	}
	line = strings.TrimSpace(line)
	i := strings.Index(line, "=")
	if i < 0 {
		return "", "", false
	}
	k := strings.ToLower(strings.TrimSpace(line[:i]))
	v := strings.ToLower(strings.TrimSpace(line[i+1:]))
	if k == "" || v == "" {
		return "", "", false
	}
	return k, v, true
}
