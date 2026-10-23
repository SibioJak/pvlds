//go:build windows

package main

// Focus herding (Windows leaf) - the watchdog's window duties
// (design section 3 amendment; M2 corrected fix round). The
// DECISIONS live in shared, unit-tested logic: herd_logic.go for
// herding (grace, rate limit, the yield to deliberate use) and
// closer.go for the session-close duty. This file is only the
// user32 plumbing: read the foreground, enumerate the game
// process's windows, and - when a decision says so - hand
// foreground back to the game's main window.
//
// Herding bounds, unchanged: it NEVER moves, resizes, or closes a
// window to do its job; the only calls are SetForegroundWindow /
// BringWindowToTop (with the AttachThreadInput dance Windows
// requires of a background process). Windows may still refuse;
// effectiveness is the player's verdict, with the focus_herding
// config kill-switch one toggle away.

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32                    = syscall.NewLazyDLL("user32.dll")
	procGetForegroundWindow   = user32.NewProc("GetForegroundWindow")
	procSetForegroundWindow   = user32.NewProc("SetForegroundWindow")
	procBringWindowToTop      = user32.NewProc("BringWindowToTop")
	procGetWindowThreadProcID = user32.NewProc("GetWindowThreadProcessId")
	procEnumWindows           = user32.NewProc("EnumWindows")
	procIsWindowVisible       = user32.NewProc("IsWindowVisible")
	procGetWindowRect         = user32.NewProc("GetWindowRect")
	procGetClassNameW         = user32.NewProc("GetClassNameW")
	procRegisterWindowMsgW    = user32.NewProc("RegisterWindowMessageW")
	procSendMessageTimeoutW   = user32.NewProc("SendMessageTimeoutW")
	procPostMessageW          = user32.NewProc("PostMessageW")
	procAttachThreadInput     = user32.NewProc("AttachThreadInput")
	procGetCurrentThreadID    = kernel32.NewProc("GetCurrentThreadId")
)

type rect struct {
	Left, Top, Right, Bottom int32
}

var (
	enumCollect   []uintptr
	enumTargetPID uint32
)

func enumCallback(hwnd uintptr, _ uintptr) uintptr {
	var pid uint32
	procGetWindowThreadProcID.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid != enumTargetPID {
		return 1
	}
	if r, _, _ := procIsWindowVisible.Call(hwnd); r == 0 {
		return 1
	}
	enumCollect = append(enumCollect, hwnd)
	return 1
}

var enumProc = syscall.NewCallback(enumCallback)

// visibleWindows lists the process's visible top-level windows.
func visibleWindows(gamePID int) []uintptr {
	enumCollect = enumCollect[:0]
	enumTargetPID = uint32(gamePID)
	procEnumWindows.Call(enumProc, 0)
	out := make([]uintptr, len(enumCollect))
	copy(out, enumCollect)
	return out
}

// gameWindow finds the game process's largest visible top-level
// window - the playfield window, not a helper.
func gameWindow(gamePID int) uintptr {
	var best uintptr
	var bestArea int64
	for _, hwnd := range visibleWindows(gamePID) {
		var rc rect
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		area := int64(rc.Right-rc.Left) * int64(rc.Bottom-rc.Top)
		if area > bestArea {
			bestArea = area
			best = hwnd
		}
	}
	return best
}

// playerSight is this leaf's sighting gate (sighting.go): the
// one filtered record of whether the game process's PLAYER
// window has been observed this session, and whether it counts
// as present right now.
var playerSight playerSighting

// runtimeSeen is this leaf's runtime gate (runtime.go): the
// filtered record of whether the game process's table RUNTIME
// has been observed this session - the stamp the resident
// launcher takes as its hand-off cue.
var runtimeSeen runtimeGate

// obsWindow pairs a window handle with its sighting observation.
type obsWindow struct {
	hwnd uintptr
	obs  windowObs
}

// The per-session window inventory state: the composition
// signature last logged for the session. One line per CHANGE,
// never per poll.
var (
	enumLogMu      sync.Mutex
	enumLogSession int
	enumLogSig     string
)

// enumerateGameWindows lists the game process's top-level
// windows - ALL of them, visible or not - as sighting
// observations, each carrying its visibility flag. (The
// unfiltered enumeration itself, allTopWindows, lives in
// closer_windows.go beside the FEC sender that also needs it.)
//
// Why unfiltered (field forensics, 2026-10-22): on Chris's VR
// rig the player renders into the headset, so its window has no
// desktop visibility, and the visible-only enumeration this
// function used to run listed exactly ONE window for the game
// process across whole sessions - the editor. The sighting
// starved no matter what the class rule said. Herding keeps its
// own visible-only enumeration (visibleWindows): its anchor is
// a window it must actually foreground, which only a visible
// window can be.
func enumerateGameWindows(gamePID int, sessionID int) []obsWindow {
	var out []obsWindow
	for _, hwnd := range allTopWindows(gamePID) {
		var rc rect
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		visible := false
		if r, _, _ := procIsWindowVisible.Call(hwnd); r != 0 {
			visible = true
		}
		out = append(out, obsWindow{hwnd: hwnd, obs: windowObs{
			class:   windowClassName(hwnd),
			width:   int64(rc.Right - rc.Left),
			height:  int64(rc.Bottom - rc.Top),
			visible: visible,
		}})
	}
	logWindowInventory(gamePID, sessionID, out)
	return out
}

// logWindowInventory writes the self-diagnosing inventory: the
// game pid's FULL window set (class, size, visible|hidden) the
// first time it is observed in a session and again whenever its
// composition changes - by class, size, or visibility - each
// line naming the current foreground window's class and owning
// pid. No per-poll spam: the line exists so the next field
// surprise is answered by the log, not by another instrumented
// build.
func logWindowInventory(gamePID int, sessionID int, windows []obsWindow) {
	parts := make([]string, 0, len(windows))
	for _, w := range windows {
		vis := "hidden"
		if w.obs.visible {
			vis = "visible"
		}
		parts = append(parts, fmt.Sprintf("class %q %dx%d %s", w.obs.class, w.obs.width, w.obs.height, vis))
	}
	sort.Strings(parts) // composition signature: enumeration order must not fake a change
	sig := strings.Join(parts, "; ")

	enumLogMu.Lock()
	defer enumLogMu.Unlock()
	if enumLogSession != sessionID {
		enumLogSession = sessionID
		enumLogSig = ""
	}
	if sig == enumLogSig || (sig == "" && enumLogSig == "") {
		return
	}
	enumLogSig = sig

	fgClass := ""
	var fgPID uint32
	if fg, _, _ := procGetForegroundWindow.Call(); fg != 0 {
		fgClass = windowClassName(fg)
		procGetWindowThreadProcID.Call(fg, uintptr(unsafe.Pointer(&fgPID)))
	}
	set := sig
	if set == "" {
		set = "(none)"
	}
	logf("watchdog: session %d: game pid %d windows: %s; foreground %q (pid %d)", sessionID, gamePID, set, fgClass, int(fgPID))
}

// gameWindowExists reports whether a player sighting has
// STAMPED for this session, and the rule that stamped it. The
// stamp reads the sighting gate's latch (sighting.go) - the
// definition the session-close duties arm on. (The resident
// launcher's hand-off cue used to be this stamp; it now waits
// for the RUNTIME stamp instead, gameRuntimeExists below -
// the sighting stamps off the editor's canvas seconds before
// a real load finishes. See runtime.go.)
func gameWindowExists(gamePID int, sessionID int) (bool, string) {
	if gamePID <= 0 {
		return false, ""
	}
	return playerSight.hasSighted(sessionID)
}

// gameRuntimeExists reports whether the table-runtime gate
// (runtime.go) has latched for this session - the resident
// launcher's hand-off cue, stamped into the contract by
// main.go exactly as the sighting stamp is.
func gameRuntimeExists(gamePID int, sessionID int) bool {
	if gamePID <= 0 {
		return false
	}
	return runtimeSeen.hasSeen(sessionID)
}

// windowClassName reads a window's Win32 class name - "VPPlayer"
// for the VPX player's SDL windows, "VPinball" for the editor
// frame (see closer.go for the vpinball source citations).
func windowClassName(hwnd uintptr) string {
	buf := make([]uint16, 256)
	n, _, _ := procGetClassNameW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if n == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}

// gameWindowState gathers this tick's facts for the session
// duties, over the UNFILTERED enumeration
// (enumerateGameWindows). Two consumers:
//
//   - The sighting gate (sighting.go), fed the full window set,
//     hidden windows included: the headset-bound player window
//     has no desktop visibility, and the gate must see it to
//     feed the exit detector's arming. The same snapshot feeds
//     the runtime gate (runtime.go), whose stamp is the
//     resident launcher's hand-off cue. (Both observations are
//     folded in here; the stamps read the gates' latches via
//     gameWindowExists / gameRuntimeExists.)
//
//   - The exit detector (closer.go), which reads the
//     FOREGROUND: computing it needs the editor frame first -
//     the largest VISIBLE "VPinball"-class window, exactly the
//     close target (the editor is a presented desktop frame in
//     practice, and the target wants the real frame, not a
//     hidden namesake) - and then whether the current
//     foreground window IS that frame. Field shape (sessions
//     25/26, 2026-10-23): the foreground cycles Virtual
//     Desktop, the loading dialog, the player, PinMAME during
//     load and play; it is the editor exactly when a table
//     exit lands.
func gameWindowState(gamePID int, sessionID int) windowState {
	var ws windowState
	if gamePID <= 0 {
		return ws
	}
	windows := enumerateGameWindows(gamePID, sessionID)
	obs := make([]windowObs, 0, len(windows))
	var bestEditorArea int64
	for _, w := range windows {
		obs = append(obs, w.obs)
		if w.obs.class == editorWindowClass && w.obs.visible {
			if area := w.obs.area(); area > bestEditorArea {
				bestEditorArea = area
				ws.editorHWND = w.hwnd
			}
		}
	}
	candidate, rule := classifyPlayerCandidate(obs)
	playerSight.observe(sessionID, candidate, rule)
	runtimeSeen.observe(sessionID, classifyRuntime(obs))
	if fg, _, _ := procGetForegroundWindow.Call(); fg != 0 && ws.editorHWND != 0 && fg == ws.editorHWND {
		ws.fgIsEditor = true
	}
	return ws
}

var herdState herdBrain

// herdTick performs one herding duty tick: read the foreground, ask
// the brain, act on its decision.
func herdTick(gamePID int, sessionID int, now time.Time) {
	if gamePID <= 0 {
		return
	}
	if herdState.sessionID != sessionID {
		herdState.reset(sessionID)
	}
	fg, _, _ := procGetForegroundWindow.Call()
	if fg == 0 {
		return
	}
	var fgPID uint32
	procGetWindowThreadProcID.Call(fg, uintptr(unsafe.Pointer(&fgPID)))
	if int(fgPID) == syscall.Getpid() {
		return // never chase our own (invisible) windows
	}
	fgIsGame := int(fgPID) == gamePID
	switch herdState.decide(now.UnixMilli(), fg, fgIsGame) {
	case herdAssert:
		target := gameWindow(gamePID)
		if target == 0 || target == fg {
			return
		}
		assertForeground(target, fg)
	case herdYielded:
		logf("watchdog: herding stands down for this session - the same window kept the foreground through %d re-assertions; deliberate use wins", herdMaxFails)
	}
}

// raiseForeground hands foreground activation to a window.
// Windows denies foreground theft to background processes unless
// the caller briefly shares the current foreground thread's input
// queue. Attach, assert, detach - windows are never moved or
// resized. Fire-and-forget: whether it stuck is the caller's next
// observation.
func raiseForeground(target uintptr, fg uintptr) {
	fgThread, _, _ := procGetWindowThreadProcID.Call(fg, 0)
	myThread, _, _ := procGetCurrentThreadID.Call()
	attached := false
	if fgThread != 0 && fgThread != myThread {
		r, _, _ := procAttachThreadInput.Call(myThread, fgThread, 1)
		attached = r != 0
	}
	procBringWindowToTop.Call(target)
	procSetForegroundWindow.Call(target)
	if attached {
		procAttachThreadInput.Call(myThread, fgThread, 0)
	}
}

// assertForeground is herding's raise: raiseForeground plus the
// log line the field reads herding by.
func assertForeground(target uintptr, fg uintptr) {
	raiseForeground(target, fg)
	logf("watchdog: focus herded back to the game window (was hwnd %#x)", fg)
}

// foregroundPID reports the process owning the current
// foreground window (0 = no foreground window).
func foregroundPID() int {
	fg, _, _ := procGetForegroundWindow.Call()
	if fg == 0 {
		return 0
	}
	var pid uint32
	procGetWindowThreadProcID.Call(fg, uintptr(unsafe.Pointer(&pid)))
	return int(pid)
}

// pushFocusToGame is the one-shot focus handoff's Windows leaf
// (main.go owns the moment and the logging; herd_logic.go owns
// the verdict vocabulary). The push buys PROCESS focus: the
// target is the game pid's visible SDL window if it has one
// (the player surface), else its editor frame - same process
// either way, and VPX's own window order takes the foreground
// from there. Skipped when the foreground already belongs to
// the game process. The verdict is verified synchronously:
// after the raise, the foreground's owner is re-read - a push
// Windows quietly ignored reports as declined, not handed.
func pushFocusToGame(gamePID int) focusPushOutcome {
	if gamePID <= 0 {
		return focusPushDeclined
	}
	if foregroundPID() == gamePID {
		return focusPushAlready
	}
	fg, _, _ := procGetForegroundWindow.Call()
	var sdl, editor uintptr
	for _, hwnd := range allTopWindows(gamePID) {
		if r, _, _ := procIsWindowVisible.Call(hwnd); r == 0 {
			continue
		}
		switch windowClassName(hwnd) {
		case sdlWindowClass:
			if sdl == 0 {
				sdl = hwnd
			}
		case editorWindowClass:
			if editor == 0 {
				editor = hwnd
			}
		}
	}
	target := sdl
	if target == 0 {
		target = editor
	}
	if target == 0 {
		return focusPushDeclined
	}
	raiseForeground(target, fg)
	if foregroundPID() == gamePID {
		return focusPushHanded
	}
	return focusPushDeclined
}
