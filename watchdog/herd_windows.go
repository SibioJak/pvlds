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
	procGetWindowTextW        = user32.NewProc("GetWindowTextW")
	procRegisterWindowMsgW    = user32.NewProc("RegisterWindowMessageW")
	procSendMessageTimeoutW   = user32.NewProc("SendMessageTimeoutW")
	procPostMessageW          = user32.NewProc("PostMessageW")
	procAttachThreadInput     = user32.NewProc("AttachThreadInput")
	procGetGUIThreadInfo      = user32.NewProc("GetGUIThreadInfo")
	procSetActiveWindow       = user32.NewProc("SetActiveWindow")
	procSetFocus              = user32.NewProc("SetFocus")
	procSwitchToThisWindow    = user32.NewProc("SwitchToThisWindow")
	procGetLastInputInfo      = user32.NewProc("GetLastInputInfo")
	procGetAsyncKeyState      = user32.NewProc("GetAsyncKeyState")
	procGetCurrentThreadID    = kernel32.NewProc("GetCurrentThreadId")
	procGetTickCount          = kernel32.NewProc("GetTickCount")
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

// playerTargetState is this leaf's player-target resolver
// (target.go): the one ranked choice of THE window that owns
// input for the session's build, fed this leaf's snapshot
// each tick exactly as the two gates above are fed theirs.
var playerTargetState targetResolver

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
			hwnd:    hwnd,
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
// (runtime.go) has latched for this session, and which
// signature stamped it - the resident launcher's hand-off
// cue, stamped into the contract by main.go exactly as the
// sighting stamp is.
func gameRuntimeExists(gamePID int, sessionID int) (bool, string) {
	if gamePID <= 0 {
		return false, ""
	}
	return runtimeSeen.hasSeen(sessionID), runtimeSeen.ruleFor(sessionID)
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
//
//   - The focus duties (focus.go / guard.go), which read the
//     wider foreground facts (class, owner, title, process,
//     input provenance) and the resolved player target from
//     the same snapshot.
//
//   - The foreground-change log (fgwatch.go), which reads the
//     foreground window's identity (the handle itself) from
//     the same snapshot: in a live session every identity
//     change is written to the log, the mid-play input-loss
//     forensics the window-SET inventory lines cannot see.
func gameWindowState(gamePID int, sessionID int) windowState {
	ws := windowState{inputAgeMs: -1}
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
	// The SDL fact (fgIsSDL's target bookkeeping): a visible
	// SDL window of the game pid if it has one, else any SDL
	// window it has.
	for _, w := range windows {
		if w.obs.class != sdlWindowClass {
			continue
		}
		if w.obs.visible {
			ws.sdlHWND = w.hwnd
			break
		}
		if ws.sdlHWND == 0 {
			ws.sdlHWND = w.hwnd
		}
	}
	candidate, rule := classifyPlayerCandidate(obs)
	playerSight.observe(sessionID, candidate, rule)
	runtimeSeen.observe(sessionID, classifyRuntime(obs), classifyVPPlayer(obs))
	// The player target (target.go): the ONE ranked resolver
	// every focus duty raises and verifies against.
	ws.playerHWND, ws.playerClass, ws.playerWhy = playerTargetState.resolve(sessionID, obs)
	// The foreground facts: who holds it (class + owner +
	// title + process), and the window-level identities the
	// duties key on - the editor frame and the player target,
	// both by handle equality.
	if fg, _, _ := procGetForegroundWindow.Call(); fg != 0 {
		var fgPID uint32
		procGetWindowThreadProcID.Call(fg, uintptr(unsafe.Pointer(&fgPID)))
		ws.fgHWND = fg
		ws.fgClass = windowClassName(fg)
		ws.fgPID = int(fgPID)
		ws.fgIsGame = ws.fgPID == gamePID
		if ws.editorHWND != 0 && fg == ws.editorHWND {
			ws.fgIsEditor = true
		}
		ws.fgIsSDL = ws.fgIsGame && ws.fgClass == sdlWindowClass
		ws.fgIsPlayer = ws.playerHWND != 0 && fg == ws.playerHWND
		ws.fgTitle = windowTitle(fg)
		ws.fgProcName = processBaseName(ws.fgPID)
	}
	// Input provenance (focus.go / guard.go): the age of the
	// last DESKTOP input - gamepad input does not advance
	// GetLastInputInfo's clock, which is exactly the
	// discrimination the deliberate-use tests need - and
	// whether an Alt/Win/mouse-button key is down now or was
	// at the previous snapshot (a deliberate foreground move's
	// fingerprints).
	ws.inputAgeMs = lastInputAgeMs()
	ws.altWinEdge = altWinEdgeSample()
	// The FIX117 focus snapshot: the player window's THREAD
	// focus (readPlayerThreadFocus) - the state VPX's SDL
	// layer gates joystick input on, which the foreground
	// facts above cannot see - and the machinery window, the
	// activation-cycle nudge's excursion target.
	ws.focusRead, ws.playerFocusHWND, ws.playerFocusClass = readPlayerThreadFocus(ws.playerHWND)
	ws.focusIsPlayer = ws.focusRead == focusReadOK && ws.playerHWND != 0 && ws.playerFocusHWND == ws.playerHWND
	ws.machineryHWND = pickMachineryWindow(windows, ws.playerHWND, ws.editorHWND)
	return ws
}

// guiThreadInfo mirrors GUITHREADINFO for GetGUIThreadInfo:
// the per-thread window state of another thread - in
// particular hwndFocus, the window that thread's keyboard
// input actually goes to.
type guiThreadInfo struct {
	cbSize        uint32
	flags         uint32
	hwndActive    uintptr
	hwndFocus     uintptr
	hwndCapture   uintptr
	hwndMenuOwner uintptr
	hwndMoveSize  uintptr
	hwndCaret     uintptr
	rcCaret       rect
}

// readPlayerThreadFocus reads the player window's thread
// focus via GetGUIThreadInfo - the FIX117 reader (closer.go's
// focus snapshot). The zero focus window is a REAL reading
// (focusReadOK with a zero handle): the thread has no focus
// window, which is precisely the born-foreground state the
// delivery exists for. No player window reads unknown; a
// failed call reads failed, and every consumer degrades to
// 1.1.6 behaviour on either.
func readPlayerThreadFocus(playerHWND uintptr) (int, uintptr, string) {
	if playerHWND == 0 {
		return focusReadUnknown, 0, ""
	}
	threadID, _, _ := procGetWindowThreadProcID.Call(playerHWND, 0)
	if threadID == 0 {
		return focusReadFailed, 0, ""
	}
	info := guiThreadInfo{cbSize: uint32(unsafe.Sizeof(guiThreadInfo{}))}
	r, _, _ := procGetGUIThreadInfo.Call(threadID, uintptr(unsafe.Pointer(&info)))
	if r == 0 {
		return focusReadFailed, 0, ""
	}
	class := ""
	if info.hwndFocus != 0 {
		class = windowClassName(info.hwndFocus)
	}
	return focusReadOK, info.hwndFocus, class
}

// pickMachineryWindow chooses the activation-cycle nudge's
// excursion target (focus.go's rung 3): a game-family window
// of the game pid that is neither the player target nor the
// editor - a visible PinMAME window preferred (the field's
// machinery shape), any substantial other game window as the
// fallback, helper surfaces never.
func pickMachineryWindow(windows []obsWindow, playerHWND, editorHWND uintptr) uintptr {
	var fallback uintptr
	for _, w := range windows {
		if w.hwnd == 0 || w.hwnd == playerHWND || w.hwnd == editorHWND {
			continue
		}
		switch w.obs.class {
		case "MAME":
			if w.obs.visible {
				return w.hwnd
			}
			if fallback == 0 {
				fallback = w.hwnd
			}
		case editorWindowClass, loadDialogClass, "CVFrame", "IME", "MSCTFIME UI", "tooltips_class32":
			// Editor furniture and input helpers: never an
			// excursion target.
		default:
			if w.obs.area() > 0 && fallback == 0 {
				fallback = w.hwnd
			}
		}
	}
	return fallback
}

// windowTitle reads a window's title text ("" when it has
// none or cannot be read).
func windowTitle(hwnd uintptr) string {
	buf := make([]uint16, 512)
	n, _, _ := procGetWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if n == 0 {
		return ""
	}
	return syscall.UTF16ToString(buf[:n])
}

// procNameCache memoizes process basenames by pid: the
// foreground owner's identity is read every tick, and a pid's
// image does not change under it. Main-loop only.
var procNameCache = map[int]string{}

// processBaseName returns the image basename of a process
// ("pinemhi_rom_monitor.exe"), "" when it cannot be read.
func processBaseName(pid int) string {
	if pid <= 0 {
		return ""
	}
	if name, ok := procNameCache[pid]; ok {
		return name
	}
	name := ""
	if path := processImagePath(pid); path != "" {
		if idx := strings.LastIndexAny(path, `\/`); idx >= 0 {
			name = path[idx+1:]
		} else {
			name = path
		}
	}
	procNameCache[pid] = name
	return name
}

// lastInputInfo mirrors LASTINPUTINFO for GetLastInputInfo.
type lastInputInfo struct {
	cbSize uint32
	dwTime uint32
}

// lastInputAgeMs returns how long ago the last desktop
// keyboard/mouse input landed, in milliseconds (-1 when the
// read fails). The arithmetic is on GetTickCount's wrapping
// 32-bit clock, exactly as the API intends.
func lastInputAgeMs() int64 {
	var li lastInputInfo
	li.cbSize = uint32(unsafe.Sizeof(li))
	r, _, _ := procGetLastInputInfo.Call(uintptr(unsafe.Pointer(&li)))
	if r == 0 {
		return -1
	}
	now, _, _ := procGetTickCount.Call()
	return int64(uint32(now) - li.dwTime)
}

// The virtual-key codes the deliberate-move sample watches:
// either Alt, either Windows key, and the mouse buttons.
var altWinKeys = []uintptr{0x12, 0x5B, 0x5C, 0x01, 0x02, 0x04} // VK_MENU, VK_LWIN, VK_RWIN, VK_LBUTTON, VK_RBUTTON, VK_MBUTTON

var altWinPrevDown bool

// altWinEdgeSample reports whether any watched key is down at
// this snapshot or was down at the previous one.
func altWinEdgeSample() bool {
	down := false
	for _, vk := range altWinKeys {
		if r, _, _ := procGetAsyncKeyState.Call(vk); r&0x8000 != 0 {
			down = true
			break
		}
	}
	edge := down || altWinPrevDown
	altWinPrevDown = down
	return edge
}

// noteForegroundOwner logs the foreground owner's top-level
// windows (class, title, size, visibility) on a foreground
// change: the game pid's set is inventoried elsewhere, but a
// CHANGE of owner - a companion window's pop, a streamer's
// surface - is exactly the moment the owner's own window set
// names it (FIX116 logging; the pre-FIX116 log recorded the
// game pid's windows only, so a thief's identity stopped at
// its class).
func noteForegroundOwner(sessionID int, ws windowState) {
	if ws.fgPID <= 0 {
		return
	}
	parts := make([]string, 0, 8)
	for _, hwnd := range allTopWindows(ws.fgPID) {
		var rc rect
		procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&rc)))
		vis := "hidden"
		if r, _, _ := procIsWindowVisible.Call(hwnd); r != 0 {
			vis = "visible"
		}
		parts = append(parts, fmt.Sprintf("class %q title %q %dx%d %s",
			windowClassName(hwnd), windowTitle(hwnd),
			int64(rc.Right-rc.Left), int64(rc.Bottom-rc.Top), vis))
	}
	set := strings.Join(parts, "; ")
	if set == "" {
		set = "(none)"
	}
	proc := ws.fgProcName
	if proc == "" {
		proc = "-"
	}
	logf("watchdog: session %d: foreground owner pid %d (%s) windows: %s", sessionID, ws.fgPID, proc, set)
}

var herdState herdBrain

// herdTick performs one herding duty tick: read the foreground, ask
// the brain, act on its decision. FIX116: the brain's assertion
// target is the resolved player HWND (target.go) whenever the
// snapshot resolved one - herding now herds to the window that
// owns input, not merely the largest visible window; the
// largest-visible anchor remains only as the fallback for the
// early load, before any target exists.
func herdTick(gamePID int, sessionID int, now time.Time, targetHWND uintptr) {
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
		target := targetHWND
		if target == 0 {
			target = gameWindow(gamePID)
		}
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
// resized. Returns SetForegroundWindow's own verdict (FIX116:
// the focus duties log it - the pre-FIX116 leaves discarded it,
// so a refused raise was indistinguishable from a landed one);
// whether the foreground actually MOVED is still the caller's
// read-back, a tick later.
func raiseForeground(target uintptr, fg uintptr) bool {
	fgThread, _, _ := procGetWindowThreadProcID.Call(fg, 0)
	myThread, _, _ := procGetCurrentThreadID.Call()
	attached := false
	if fgThread != 0 && fgThread != myThread {
		r, _, _ := procAttachThreadInput.Call(myThread, fgThread, 1)
		attached = r != 0
	}
	procBringWindowToTop.Call(target)
	r, _, _ := procSetForegroundWindow.Call(target)
	if attached {
		procAttachThreadInput.Call(myThread, fgThread, 0)
	}
	return r != 0
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

// activatePlayerWindow is the focus duties' Windows leaf
// (focus.go / guard.go own the decisions; main.go owns the
// moments and the logging): raise the session's resolved
// player target (target.go) - the ONE window that owns input
// for this build, SDL_app on GL, VPPlayer on BGFX, a
// persisted candidate elsewhere. There is NO editor fallback,
// under any circumstances: the editor window is the one
// target these duties must never raise. attempted=false says
// there was no target to raise (the caller stands the attempt
// down); ok is SetForegroundWindow's own verdict - whether
// the foreground actually moved is the caller's read-back
// against the HWND, a tick later. (This leaf and
// pushFocusToGame, the retired one-shot handoff, are the
// FIX116 replacement for the SDL-only activation leaf:
// same call shape, a target that finally knows the BGFX
// build's window.)
func activatePlayerWindow(gamePID int, targetHWND uintptr) (attempted bool, ok bool) {
	if gamePID <= 0 || targetHWND == 0 {
		return false, false
	}
	fg, _, _ := procGetForegroundWindow.Call()
	return true, raiseForeground(targetHWND, fg)
}

// deliverPlayerFocus is the FIX117 focus-delivery leaf
// (focus.go owns the decisions and the moments; main.go owns
// the logging): deliver keyboard focus INTO the player
// window's thread - the inner switch the foreground value
// cannot prove. The ladder rung (from the contract) chooses
// the act:
//
//	rung 1: the full-family delivery - attach our thread to
//	  the current foreground thread (raiseForeground's dance)
//	  AND to the TARGET window's thread, then inside the
//	  merged queue family BringWindowToTop +
//	  SetForegroundWindow + SetActiveWindow + SetFocus.
//	  AttachThreadInput's documented purpose is enabling
//	  exactly this cross-thread SetFocus: the player thread's
//	  focus window becomes the player window, WM_SETFOCUS
//	  fires into VPX's pump, and SDL's keyboard-focus flag -
//	  the gate its joystick delivery checks - is set by the
//	  app's own message flow, not by a lie told to it.
//	rung 2: SwitchToThisWindow(player, TRUE) - the shell's
//	  own switch call, TRUE meaning switched "using the
//	  Alt/Ctl+Tab key sequence": the closest programmatic
//	  relative of the player's manual cure, in one call.
//	rung 3: the activation-cycle nudge - raise the machinery
//	  window (machineryHWND: a game-family window, never the
//	  editor) for a beat, then rung 1's delivery, so the
//	  player thread receives a real deactivate -> activate
//	  pair instead of inheriting a static foreground. The
//	  excursion lives entirely inside this call and happens
//	  only when the sequence orders a delivery, which is
//	  launch-window only.
//
// attempted=false says there was no target to deliver to;
// ok is SetForegroundWindow's verdict on rungs 1/3 (rung 2's
// call returns nothing, so a made call reports ok). Whether
// the focus actually LANDED is the reader's next ticks - the
// sequence spends its budget against those readings, not
// against this verdict.
func deliverPlayerFocus(gamePID int, targetHWND uintptr, rung int, machineryHWND uintptr) (attempted bool, ok bool) {
	if gamePID <= 0 || targetHWND == 0 {
		return false, false
	}
	if rung == 2 {
		procSwitchToThisWindow.Call(targetHWND, 1)
		return true, true
	}
	fg, _, _ := procGetForegroundWindow.Call()
	if rung == 3 && machineryHWND != 0 && machineryHWND != targetHWND {
		var mPID uint32
		procGetWindowThreadProcID.Call(machineryHWND, uintptr(unsafe.Pointer(&mPID)))
		if int(mPID) == gamePID {
			raiseForeground(machineryHWND, fg)
			time.Sleep(150 * time.Millisecond)
			fg = machineryHWND
		}
	}
	return true, deliverFocusForeground(targetHWND, fg)
}

// deliverFocusForeground performs rung 1's call sequence:
// attach (current foreground thread, then the target's
// thread), raise, activate, focus, detach in reverse order.
func deliverFocusForeground(target uintptr, fg uintptr) bool {
	targetThread, _, _ := procGetWindowThreadProcID.Call(target, 0)
	fgThread, _, _ := procGetWindowThreadProcID.Call(fg, 0)
	myThread, _, _ := procGetCurrentThreadID.Call()
	attachedFG := false
	if fgThread != 0 && fgThread != myThread && fgThread != targetThread {
		r, _, _ := procAttachThreadInput.Call(myThread, fgThread, 1)
		attachedFG = r != 0
	}
	attachedTarget := false
	if targetThread != 0 && targetThread != myThread {
		r, _, _ := procAttachThreadInput.Call(myThread, targetThread, 1)
		attachedTarget = r != 0
	}
	procBringWindowToTop.Call(target)
	r, _, _ := procSetForegroundWindow.Call(target)
	procSetActiveWindow.Call(target)
	procSetFocus.Call(target)
	if attachedTarget {
		procAttachThreadInput.Call(myThread, targetThread, 0)
	}
	if attachedFG {
		procAttachThreadInput.Call(myThread, fgThread, 0)
	}
	return r != 0
}

// The message probe's messages (FIX117, diagnostic only):
// WM_ACTIVATE with WA_ACTIVE, then WM_SETFOCUS - the pair
// that makes SDL set its keyboard-focus flag without any real
// Windows state moving.
const (
	wmActivateMsg = 0x0006 // WM_ACTIVATE
	wmSetFocusMsg = 0x0007 // WM_SETFOCUS
	waActiveMsg   = 1      // WA_ACTIVE
)

// probePlayerFocus is the FIX117 diagnostic probe leaf: post
// the activation message pair to the player window. It lies
// to the app about real state on purpose - its one job is to
// convict or kill the SDL-gate mechanism in a single field
// session if the ladder stalls - and it is reachable only
// under the contract's probe flag, never as standing
// behaviour (focus.go carries the law).
func probePlayerFocus(gamePID int, targetHWND uintptr) (attempted bool) {
	if gamePID <= 0 || targetHWND == 0 {
		return false
	}
	procPostMessageW.Call(targetHWND, wmActivateMsg, waActiveMsg, 0)
	procPostMessageW.Call(targetHWND, wmSetFocusMsg, 0, 0)
	return true
}
