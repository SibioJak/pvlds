package main

import "strings"

// The known-bystander registry (FIX116): the windows the
// live-session focus guard (guard.go) may take the foreground
// back from mid-play. Data, not code branches: an entry is a
// name plus a set of identity signals over the holder's facts
// (owning process's image basename, window class, window
// title), and a holder matches an entry only when at least
// TWO of its signals hit - a single generic signal (a class
// name, a common word in a title) can never match by
// accident.
//
// A bystander, for this registry, is a companion program's
// window that raises ITSELF while a table plays - the user
// did not summon it; it interrupts. Windows the user
// deliberately brings forward are protected by the guard's
// provenance veto, not by absence from this list; windows
// that match nothing here are logged and left alone in v1.
//
// v1 has one entry, seeded from field facts that are
// honestly incomplete: Chris's PINemHi LeaderBoard board -
// the "TOP 5 Personal Best" window that popped over his
// Tommy table after load (2026-11-12) - is a PINemHi-family
// program presenting a leaderboard. Its exact process name,
// class and title on his machine are NOT yet established
// (the pre-FIX116 watchdog recorded none of them; FIX116's
// fgwatch lines record all three, so the next field log
// names it and this entry can be tightened). The signals are
// therefore the family's own words, any two of which must
// agree: the process or title naming PINemHi, or the title
// naming the leaderboard / its TOP 5 board.

// stubBystanderPID is the foreground-owner pid the Linux stub
// leaf reports for its "board" token (window_linux.go) -
// declared here so the bench tests can build the board's
// facts on any platform.
const stubBystanderPID = 5150

type holderFacts struct {
	proc  string // owning process's image basename
	class string // Win32 window class
	title string // window title
}

// foldContains reports whether s contains sub, case-folded.
func foldContains(s, sub string) bool {
	return strings.Contains(strings.ToLower(s), strings.ToLower(sub))
}

type bystanderEntry struct {
	name    string
	signals []func(holderFacts) bool
}

var bystanderRegistry = []bystanderEntry{
	{
		name: "PINemHi LeaderBoard",
		signals: []func(holderFacts) bool{
			func(f holderFacts) bool { return foldContains(f.proc, "pinemhi") },
			func(f holderFacts) bool { return foldContains(f.title, "pinemhi") },
			func(f holderFacts) bool { return foldContains(f.title, "leaderboard") },
			func(f holderFacts) bool { return foldContains(f.title, "top 5") },
		},
	},
}

// bystanderSignalsNeeded is the registry's match rule: at
// least this many of an entry's signals must hit.
const bystanderSignalsNeeded = 2

// matchBystander reports whether the holder matches a
// registry entry, and the entry's name when it does.
func matchBystander(f holderFacts) (string, bool) {
	for _, e := range bystanderRegistry {
		hits := 0
		for _, sig := range e.signals {
			if sig(f) {
				hits++
			}
		}
		if hits >= bystanderSignalsNeeded {
			return e.name, true
		}
	}
	return "", false
}
