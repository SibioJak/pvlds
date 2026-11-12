package main

// Which process IS the session's game (FIX113, 2026-11-12).
//
// The law: the game is the pid the launcher launched, named
// in the contract's game_pid — never "some other process
// running the same exe". The field failure this closes
// (pvlds-fix113/droscoe_watchdog.log): a player's table ended,
// and the session duties kept running against a SECOND,
// long-lived VPX process — the user's editor, open all
// morning — which the watchdog then inventoried as "the
// game", focus-pushed, and eventually sent CLOSE_APP and a
// WM_CLOSE to. The editor was closed by the watchdog. The
// adoption came from one place: gameAlive's fallback, which
// treated ANY live process of the game's exe as the session's
// game when the contract's pid was dead.
//
// Exe discovery survives for exactly one window: the launcher
// spawns the watchdog (armed, game_pid still 0) BEFORE it
// spawns the game, so on the first ticks there is no pid to
// trust yet and discovery is the only way to learn it. Once a
// pid stands in the contract — alive or dead — discovery is
// never consulted again for that session.
//
// resolveSessionGamePID is the pure decision; gameAlive
// (main.go) supplies the live facts.

// resolveSessionGamePID decides the session's game pid and its
// liveness.
//
//	contractPID > 0: the contract's pid IS the game. alive is
//	  its own liveness; discovered is ignored entirely — a
//	  dead launched pid means the game is dead, full stop,
//	  however many same-exe processes are running.
//	contractPID == 0: no pid yet — the first discovered pid
//	  other than the watchdog itself stands in, alive.
func resolveSessionGamePID(contractPID int, contractAlive bool, discovered []int, selfPID int) (alive bool, pid int) {
	if contractPID > 0 {
		return contractAlive, contractPID
	}
	for _, p := range discovered {
		if p > 0 && p != selfPID {
			return true, p
		}
	}
	return false, 0
}
