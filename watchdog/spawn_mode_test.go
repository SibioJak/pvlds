package main

// FIX143 spawn mode: the argument parse (pure) and, on Linux,
// the working-directory fact itself — a child started through
// startDetachedInDir in a named directory must observe THAT
// directory as its cwd. This is the watchdog half of the
// round's invariant: the launcher half (the fix143 smoke)
// proves the app actually spawns VPX through this door.

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestParseSpawnArgs(t *testing.T) {
	dir, pidFile, exe, rest, ok := parseSpawnArgs([]string{`D:\vPinball\VisualPinball`, `C:\Users\x\AppData\Roaming\Godot\app_userdata\PVLDS\pvlds_spawn_pid.txt`, `D:\vPinball\VisualPinball\VPinballX_GL64.exe`, "-play", `D:\tables\Lunar Shot.vpx`})
	if !ok {
		t.Fatal("a full spawn line must parse")
	}
	if dir != `D:\vPinball\VisualPinball` || exe != `D:\vPinball\VisualPinball\VPinballX_GL64.exe` {
		t.Fatalf("dir/exe split wrong: dir=%q exe=%q", dir, exe)
	}
	if pidFile == "" || !strings.HasSuffix(pidFile, "pvlds_spawn_pid.txt") {
		t.Fatalf("pid-file split wrong: %q", pidFile)
	}
	if len(rest) != 2 || rest[0] != "-play" || rest[1] != `D:\tables\Lunar Shot.vpx` {
		t.Fatalf("the exe's args must ride through untouched: %v", rest)
	}
	if _, _, _, _, ok := parseSpawnArgs([]string{"only-a-dir"}); ok {
		t.Fatal("a lone directory is not a spawn line")
	}
	if _, _, _, _, ok := parseSpawnArgs([]string{"a-dir", "a-pid-file"}); ok {
		t.Fatal("dir + pid-file without an exe is not a spawn line")
	}
	if _, _, _, _, ok := parseSpawnArgs(nil); ok {
		t.Fatal("no arguments is not a spawn line")
	}
	// An empty dir is a legal line: it keeps the inherited
	// directory (startDetachedInDir's own "" rule).
	if _, _, _, _, ok := parseSpawnArgs([]string{"", "a-pid-file", "/bin/true"}); !ok {
		t.Fatal("an empty working directory must still parse")
	}
}

func TestSupervisedSpawnReportsPidAndOutlivesTheChild(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("the supervised-spawn fact is exercised through /bin/sh on Linux; the Windows leaf shares the shape")
	}
	dir := t.TempDir()
	out := filepath.Join(dir, "cwd.txt")
	started := time.Now()
	reported := 0
	pid, err := startGameInDirAndWait("/bin/sh", []string{"-c", "pwd > " + out + "; sleep 1"}, dir, nil, func(p int) {
		reported = p
	})
	elapsed := time.Since(started)
	if err != nil {
		t.Fatalf("supervised spawn failed: %v", err)
	}
	if pid <= 0 || reported != pid {
		t.Fatalf("the on-start callback must report the child pid: pid=%d reported=%d", pid, reported)
	}
	if elapsed < 900*time.Millisecond {
		t.Fatalf("the supervised spawn returned after %v - it must wait out the child (sleep 1)", elapsed)
	}
	data, rerr := os.ReadFile(out)
	if rerr != nil {
		t.Fatalf("the child never wrote its cwd: %v", rerr)
	}
	if got := strings.TrimSpace(string(data)); got != dir {
		want, _ := filepath.EvalSymlinks(dir)
		if got != want {
			t.Fatalf("child cwd = %q, want %q", got, dir)
		}
	}
}

func TestSpawnModeChildSeesTheNamedDir(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("the cwd fact is exercised through /bin/sh on Linux; the Windows leaf shares the code path (cmd.Dir)")
	}
	dir := t.TempDir()
	out := filepath.Join(dir, "cwd.txt")
	pid, err := startDetachedInDir("/bin/sh", []string{"-c", "pwd > " + out}, dir)
	if err != nil {
		t.Fatalf("spawn failed: %v", err)
	}
	if pid <= 0 {
		t.Fatalf("spawn returned pid %d", pid)
	}
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if data, rerr := os.ReadFile(out); rerr == nil {
			got := strings.TrimSpace(string(data))
			want, _ := filepath.EvalSymlinks(dir)
			if got != want && got != dir {
				t.Fatalf("child cwd = %q, want %q", got, dir)
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("the spawned child never wrote its cwd")
}

// FIX148: the env scrub. The game's environment must lose
// SDL_JOYSTICK_DIRECTINPUT (the launcher's own SDL variable,
// inherited by every process the launcher bears) and keep
// everything else, byte for byte.
func TestScrubGameEnv(t *testing.T) {
	in := []string{"PATH=/usr/bin", "SDL_JOYSTICK_DIRECTINPUT=0", "OTHER=keep=me", "USER=x"}
	out, removed := scrubGameEnv(in)
	if !removed {
		t.Fatal("the scrub must report the removal")
	}
	if len(out) != 3 {
		t.Fatalf("scrubbed env = %v, want the other three entries untouched", out)
	}
	for _, e := range out {
		if strings.HasPrefix(e, "SDL_JOYSTICK_DIRECTINPUT=") {
			t.Fatalf("the scrubbed variable survived: %v", out)
		}
	}
	if out[0] != "PATH=/usr/bin" || out[1] != "OTHER=keep=me" || out[2] != "USER=x" {
		t.Fatalf("the surviving entries changed: %v", out)
	}
	// Case-insensitive key match (Windows environment keys
	// are case-insensitive).
	if _, removed := scrubGameEnv([]string{"sdl_joystick_directinput=0"}); !removed {
		t.Fatal("a differently-cased key must still scrub")
	}
	// Absent: nothing removed, env returned whole.
	out, removed = scrubGameEnv([]string{"PATH=/usr/bin"})
	if removed || len(out) != 1 || out[0] != "PATH=/usr/bin" {
		t.Fatalf("an env without the variable must pass through whole: %v removed=%v", out, removed)
	}
	// A key that merely starts with the name is not the variable.
	if _, removed := scrubGameEnv([]string{"SDL_JOYSTICK_DIRECTINPUT_EXTRA=1"}); removed {
		t.Fatal("a longer key sharing the prefix must not scrub")
	}
	// Empty env scrubs to empty, unremoved.
	if out, removed := scrubGameEnv(nil); removed || len(out) != 0 {
		t.Fatalf("nil env: got %v removed=%v", out, removed)
	}
}

// FIX148 end-to-end on Linux: a child started through the
// game leaf with a scrubbed env observes the scrubbed env.
func TestGameSpawnChildSeesScrubbedEnv(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("exercised through /bin/sh on Linux; the Windows leaf shares the shape")
	}
	dir := t.TempDir()
	out := filepath.Join(dir, "env.txt")
	env, removed := scrubGameEnv([]string{"SDL_JOYSTICK_DIRECTINPUT=0", "PVLDS_WITNESS=alive"})
	if !removed {
		t.Fatal("the test env must contain the scrubbed variable")
	}
	_, err := startGameInDirAndWait("/bin/sh", []string{"-c", "env > " + out}, dir, env, nil)
	if err != nil {
		t.Fatalf("game spawn failed: %v", err)
	}
	data, rerr := os.ReadFile(out)
	if rerr != nil {
		t.Fatalf("the child never wrote its env: %v", rerr)
	}
	got := string(data)
	if strings.Contains(got, "SDL_JOYSTICK_DIRECTINPUT") {
		t.Fatalf("the child saw the scrubbed variable:\n%s", got)
	}
	if !strings.Contains(got, "PVLDS_WITNESS=alive") {
		t.Fatalf("the child lost the rest of its environment:\n%s", got)
	}
}
