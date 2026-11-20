package main

// Assisted game spawn mode (FIX143): the watchdog binary as
// the launcher's spawn helper.
//
// Why this exists: Godot's OS.create_process has no
// working-directory parameter, so a VPX spawned by the
// launcher inherits LAUNCHPIN's folder as its cwd instead of
// its own. FIX142 convicted that difference (rank-1 suspect)
// for script-started B2S dying under a LaunchPin launch while
// the same table lives under a plain VPX launch — and this
// project has convicted the same class once before: the
// PINemHi watcher resolves pinemhi.ini relative to its cwd,
// so the watchdog starts it inside its own folder
// (startDetachedInDir, WATCHERFIX in proc_windows.go /
// proc_linux.go).
//
// The shape is dictated by two facts about the launcher:
//   - perform_launch needs the spawn's outcome (and a pid)
//     synchronously, and
//   - Main's load wait judges the load by
//     OS.is_process_running on the pid perform_launch hands
//     it — and Godot's is_process_running only believes the
//     launcher's OWN children: a live foreign pid reads dead
//     (convicted on the bench, FIX143: a shim that spawned
//     the game and exited left Main calling a live VPX dead
//     inside its 1.5 s grace).
//
// So the helper SUPERVISES: the launcher spawns this binary
// (a true child) with the spawn mode as argv[1]:
//
//	pvlds-spawn <working-dir> <pid-file> <exe> [args...]
//
// The mode starts the exe in the named directory (FIX148:
// plainly - no detach flags, no new session - and with the
// game's environment scrubbed of SDL_JOYSTICK_DIRECTINPUT;
// see scrubGameEnv), writes the GAME's pid into <pid-file>
// (atomically — the launcher polls for it and puts that pid
// in the session contract, where the resident watchdog's
// duties aim), and then waits: the helper lives exactly as
// long as the game does, so the launcher's liveness read on
// the HELPER's pid tracks the game's life one-for-one. When
// the game exits, the helper exits. If the start itself
// fails, the helper writes no pid file and exits 1 with the
// reason on stderr — the launcher sees its child die with no
// pid file and fails the launch, like the old pid<0 path.
//
// The mode touches no lock and no contract, and is decided
// in main() before any of that machinery is set up, so a
// spawn can never disturb the resident watchdog's duties.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// spawnModeArg is the argv[1] word that selects the mode. It
// cannot collide with the normal invocation: there argv[1]
// is a contract file path.
const spawnModeArg = "pvlds-spawn"

// parseSpawnArgs splits the mode's arguments (argv[2:]) into
// the working directory, the pid-file path, the exe, and the
// exe's own argument list. ok=false when the shape is wrong
// (fewer than dir, pid-file and exe). Pure; unit-tested
// (spawn_mode_test.go).
func parseSpawnArgs(args []string) (dir string, pidFile string, exe string, rest []string, ok bool) {
	if len(args) < 3 {
		return "", "", "", nil, false
	}
	return args[0], args[1], args[2], args[3:], true
}

// writeSpawnPidFile records the spawned game's pid for the
// launcher: temp file + rename in the same directory, so the
// launcher's poll never reads a half-written pid.
func writeSpawnPidFile(pidFile string, pid int) error {
	tmp := pidFile + ".tmp"
	if err := os.WriteFile(tmp, []byte(fmt.Sprintf("%d\n", pid)), 0644); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Clean(pidFile))
}

// scrubbedEnvVar is the one variable the game's environment
// loses (FIX148). The launcher sets it for its own SDL
// (sdl_bootstrap.gd) and every process the launcher bears
// inherits it - including, until now, the game. Hand launches
// prove VPX plays correctly without it, and the FIX148 field
// evidence convicted the launcher's birth lineage, environment
// included, for script-started B2S dying in that lineage while
// the same table lives in any other. The app's own copy is
// untouched; only the game's is removed.
const scrubbedEnvVar = "SDL_JOYSTICK_DIRECTINPUT"

// scrubGameEnv returns env with every scrubbedEnvVar entry
// removed, plus whether anything was removed. The match is on
// the entry's key, case-insensitively (Windows environment
// keys are case-insensitive; the launcher sets the exact case
// above, so this only widens the net over the same variable).
// Pure; unit-tested (spawn_mode_test.go).
func scrubGameEnv(env []string) ([]string, bool) {
	out := make([]string, 0, len(env))
	removed := false
	for _, e := range env {
		key, _, _ := strings.Cut(e, "=")
		if strings.EqualFold(key, scrubbedEnvVar) {
			removed = true
			continue
		}
		out = append(out, e)
	}
	return out, removed
}

// logSpawnScrub records the scrub in the watchdog log beside
// the pid file (the contract's folder - the same log the
// resident watchdog writes), in that log's own line format.
// The variable is named, never valued. A log that cannot be
// opened is not a launch problem: the scrub itself already
// happened, so a failure here is silent.
func logSpawnScrub(pidFile string) {
	path := filepath.Join(filepath.Dir(pidFile), "pvlds_watchdog.log")
	lf, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer lf.Close()
	line := fmt.Sprintf("%s %s\n", time.Now().Format("2006-01-02 15:04:05"),
		fmt.Sprintf("watchdog: spawn: removed %s from the game's environment (FIX148)", scrubbedEnvVar))
	lf.WriteString(line)
	lf.Sync()
}

// runSpawnMode performs one assisted, supervised spawn. The
// return value is the process exit code: 0 when the game was
// started (and has since exited), 1 when the start failed,
// 2 on a malformed invocation.
//
// FIX148: the creation shape is the FIX147 neutral spawner's
// recipe on every axis this chain controls - plain (no
// detach flags, no new session; the platform leaves' game
// shape), the working directory the launcher named (the VPX
// folder), and the environment scrubbed by scrubGameEnv.
// The FIX145 diag seams are gone: nothing here consults
// pvlds_diag.txt, and there is exactly one spawn shape.
func runSpawnMode(args []string) int {
	dir, pidFile, exe, rest, ok := parseSpawnArgs(args)
	if !ok {
		fmt.Fprintln(os.Stderr, "pvlds-spawn: want <working-dir> <pid-file> <exe> [args...]")
		return 2
	}
	env, scrubbed := scrubGameEnv(os.Environ())
	if scrubbed {
		logSpawnScrub(pidFile)
	} else {
		env = nil // untouched inheritance, byte for byte
	}
	_, err := startGameInDirAndWait(exe, rest, dir, env, func(pid int) {
		if werr := writeSpawnPidFile(pidFile, pid); werr != nil {
			fmt.Fprintf(os.Stderr, "pvlds-spawn: could not write the pid file %s: %v\n", pidFile, werr)
		}
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "pvlds-spawn: could not start %s: %v\n", exe, err)
		return 1
	}
	return 0
}
