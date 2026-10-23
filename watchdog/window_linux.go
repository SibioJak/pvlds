package main

import (
	"os"
	"strconv"
	"strings"
)

// The Linux watchdog build exists to exercise the platform-free
// session logic in this repo's smokes - it never ships anywhere
// (the shipping watchdog is the Windows build, whose window
// facts are a real user32 enumeration). The stub contract below
// is how the shared DECISION logic (closer.go, sighting.go)
// gets exercised end to end here.
//
// gameWindowPresentOnMaps is the existence signal for the stub's
// player window: a process that has opened a display and created
// its window carries an X client library (libX11 / libxcb)
// mapped; a process still in its early load does not. The smokes'
// stub VPX is built to exactly that contract: a plain first stage
// that exec()s (same pid) into an X-linked second stage when its
// "window" phase begins - the same shape as a real binary pulling
// its display stack in as it comes up, and the reason a single
// X-linked stub would be useless here (it would map libX11 from
// birth).
func gameWindowPresentOnMaps(gamePID int) bool {
	if gamePID <= 0 {
		return false
	}
	maps, err := os.ReadFile("/proc/" + strconv.Itoa(gamePID) + "/maps")
	if err != nil {
		return false
	}
	s := string(maps)
	return strings.Contains(s, "libX11") || strings.Contains(s, "libxcb")
}

// stubEditorMarker is the smoke stub's "I am sitting in the editor
// now" signal: a file in the temp dir named by pid. There is no
// real VPX on Linux to enumerate; the stub contract is how the
// session-close DECISION logic (closer.go) gets exercised end to
// end here, the same spirit as the maps contract above.
func stubEditorMarker(gamePID int) string {
	return "/tmp/pvlds-stub-editor-" + strconv.Itoa(gamePID)
}

// stubPlayerClass names the Win32 class the stub's player window
// "carries" for the sighting rule: the contents of a marker file
// the smoke writes for the stub's pid (e.g. "SDL_app" rehearses a
// player window of some class the classic rule would miss). No
// marker = the stub plays a classic "VPPlayer" window.
func stubPlayerClass(gamePID int) string {
	b, err := os.ReadFile("/tmp/pvlds-stub-playerclass-" + strconv.Itoa(gamePID))
	if err != nil {
		return playerWindowClass
	}
	if s := strings.TrimSpace(string(b)); s != "" {
		return s
	}
	return playerWindowClass
}

// stubPlayerHiddenMarker is the smoke stub's "my player window
// is hidden" signal: while the marker stands, the stub's player
// observation carries visible=false - present in the unfiltered
// window set the sighting gate reads, absent from the visible
// set herding would use. It mirrors the Windows field fault of
// 2026-10-22: the player rendering into a VR headset holds a
// window with no desktop visibility at all.
func stubPlayerHiddenMarker(gamePID int) string {
	return "/tmp/pvlds-stub-player-hidden-" + strconv.Itoa(gamePID)
}

// stubForegroundMarker scripts the FOREGROUND fact the exit
// detector (closer.go) reads: the file's contents name who
// holds the foreground - "editor" (the game pid's editor
// frame) or "other" (anything else: the player, Virtual
// Desktop, a dialog). The stub writes it through its phases
// the way the real rig behaves (editor at the spawn instant,
// away during play, editor again when the table exit lands -
// the field shape from sessions 25/26, 2026-10-23), with env
// knobs for the shapes a scenario needs to force (see
// stub_vpx_window.c). An absent file reads as "other": the
// foreground is simply not known to be the editor, which is
// the detector's safe default.
func stubForegroundMarker(gamePID int) string {
	return "/tmp/pvlds-stub-foreground-" + strconv.Itoa(gamePID)
}

// stubRuntimeMarker is the smoke stub's "my table runtime is
// up" signal: while the file stands, this leaf's snapshot
// carries a runtime-class observation (a SharpGLRenderWindow -
// one of the field runtime classes, runtime.go), so the
// runtime gate and its contract stamp get exercised exactly
// as the sighting gate is through its markers. The stub's
// stage 2 raises it on its runtime schedule
// (STUB_RUNTIME_AFTER_S - see stub_vpx_window.c): at window-up
// by default (the runtime arrives with play, as on the real
// rig), seconds later when a scenario models a slow runtime,
// or never.
func stubRuntimeMarker(gamePID int) string {
	return "/tmp/pvlds-stub-runtime-" + strconv.Itoa(gamePID)
}

// stubFGHWND derives the synthetic foreground-window identity
// this leaf reports (windowState.fgHWND, fgwatch.go's change
// identity). There is no real handle to mirror; what the
// mirror CAN know of a holder is its class + owning pid, so
// the identity is a deterministic hash of exactly that pair -
// the same holder facts carry the same identity whichever
// token or phase produced them (stage 1's "other" and stage
// 2's scripted holder are one identity when their class and
// pid agree), and different holders differ. No window at all
// (empty class, pid 0) keeps identity 0 - fgwatch's "none".
func stubFGHWND(class string, pid int) uintptr {
	if class == "" && pid == 0 {
		return 0
	}
	h := uint32(2166136261) // FNV-1a over the class, then the pid
	for i := 0; i < len(class); i++ {
		h ^= uint32(class[i])
		h *= 16777619
	}
	h ^= uint32(pid)
	h *= 16777619
	if h == 0 {
		h = 1 // a real holder never carries the no-window identity
	}
	return uintptr(h)
}

// stubFGStubbornMarker is the stubborn-foreground signal for
// the activation sequence's smokes (activation.go): while the
// file stands, this leaf's activateSDLWindow reports an attempt
// but the foreground does not move - the mirror of a holder
// (or Windows) refusing the raise, so the sequence's verify
// and single retry run their course. The stub raises it under
// STUB_FG_STUBBORN (see stub_vpx_window.c).
func stubFGStubbornMarker(gamePID int) string {
	return "/tmp/pvlds-stub-fg-stubborn-" + strconv.Itoa(gamePID)
}

// playerSight is this leaf's sighting gate (sighting.go) - the
// same shared gate the Windows leaf feeds, so the smokes exercise
// the shipped rule, persistence included.
var playerSight playerSighting

// runtimeSeen is this leaf's runtime gate (runtime.go) - the
// same shared gate the Windows leaf feeds.
var runtimeSeen runtimeGate

// gameWindowExists on Linux: whether a player sighting has
// STAMPED for this session, and the rule that stamped it - the
// sighting gate's latch, exactly as the Windows leaf reports it.
func gameWindowExists(gamePID int, sessionID int) (bool, string) {
	if gamePID <= 0 {
		return false, ""
	}
	return playerSight.hasSighted(sessionID)
}

// gameRuntimeExists on Linux: whether the runtime gate has
// latched for this session - the same latch the Windows leaf
// reports, fed by the stub's runtime marker (gameWindowState).
func gameRuntimeExists(gamePID int, sessionID int) bool {
	if gamePID <= 0 {
		return false
	}
	return runtimeSeen.hasSeen(sessionID)
}

// pushFocusToGame on Linux: there is no foreground to raise
// here; the mirror reports the verdict the scripted facts
// imply, so main.go's one-shot handoff (its trigger, its
// exactly-once bookkeeping, its logging, and notePush into the
// exit detector) runs end to end in the smokes. The foreground
// marker names the editor - the game process's own window -
// as the foreground holder, which is the Windows leaf's
// "already holds" case; anything else reads as a successful
// push (nothing on this platform can decline it).
func pushFocusToGame(gamePID int) focusPushOutcome {
	if gamePID <= 0 {
		return focusPushDeclined
	}
	if b, err := os.ReadFile(stubForegroundMarker(gamePID)); err == nil && strings.TrimSpace(string(b)) == "editor" {
		return focusPushAlready
	}
	return focusPushHanded
}

// stubVirtualDesktopPID is the foreground-owner pid the "vd"
// marker token reports: Virtual Desktop's own process in the
// field inventories (watchdog-6 log, sessions 25/26/35), used
// verbatim so the smokes' facts carry the field's shape.
const stubVirtualDesktopPID = 9932

// stubThirdPartyPID is the foreground-owner pid the "third"
// marker token reports: some unrelated process - never the
// game, never Virtual Desktop.
const stubThirdPartyPID = 424242

// gameWindowState on Linux (smoke build only) gathers the same
// facts the Windows leaf does. The sighting gate is fed
// sighting observations: the editor marker is a "VPinball"-
// class observation, VISIBLE (the editor is a presented frame
// wherever the facts matter; and while the marker stands, the
// player is gone - the stub's exit-to-editor state); the maps
// signal is a player-window observation carrying the stub's
// declared class at the stub window's real size (400x300),
// with visible=false while the hidden marker stands - the
// unfiltered gate must count it anyway (see
// stubPlayerHiddenMarker). While the runtime marker stands
// (stubRuntimeMarker), the player branch additionally carries
// a runtime-class observation, feeding the runtime gate whose
// stamp is the launcher's hand-off cue. The stub drops the
// editor marker in two situations the smokes keep distinct by
// session shape: its table-exit-to-editor moment (after a
// player phase), and - with STUB_EDITOR_FIRST_S - from birth,
// modelling VPX's startup order (editor frame first, player
// window only after the table loads), which is the state the
// detector's sighting half exists for.
//
// The foreground facts come from the foreground marker
// (stubForegroundMarker), whose contents are a holder TOKEN:
//
//	"editor"  the game pid's editor frame (fgIsEditor)
//	"sdl"     the game pid's SDL window (fgIsSDL)
//	"mame"    PinMAME's window, game pid - session 35's thief
//	"vd"      Virtual Desktop's window (CabinetWClass)
//	"third"   an unrelated process's window
//	"none"    no foreground window at all
//	"other"   (or an absent file) the stub's player window,
//	          carrying its declared class (stubPlayerClass)
//
// While the editor marker stands, the foreground is reported
// as the editor regardless of the token: the stub is IN its
// editor state then, and on the real rig that state is the
// editor holding the foreground - the invariant the exit
// detector is built on. (It also keeps this leaf's own
// activateSDLWindow token write, landing a moment before the
// stub's editor phase begins, from forging a player
// foreground the rig could never show.) No editor handle
// exists off Windows; the foreground identity (fgHWND) is
// synthesized from the holder's class + pid instead - see
// stubFGHWND.
func gameWindowState(gamePID int, sessionID int) windowState {
	var ws windowState
	if gamePID <= 0 {
		return ws
	}
	var obs []windowObs
	editorUp := false
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		editorUp = true
		obs = append(obs, windowObs{class: editorWindowClass, width: 1280, height: 900, visible: true})
	} else if gameWindowPresentOnMaps(gamePID) {
		visible := true
		if _, err := os.Stat(stubPlayerHiddenMarker(gamePID)); err == nil {
			visible = false
		}
		obs = append(obs, windowObs{class: stubPlayerClass(gamePID), width: 400, height: 300, visible: visible})
		if _, err := os.Stat(stubRuntimeMarker(gamePID)); err == nil {
			obs = append(obs, windowObs{class: "SharpGLRenderWindow", width: 307, height: 77, visible: false})
		}
	}
	candidate, rule := classifyPlayerCandidate(obs)
	playerSight.observe(sessionID, candidate, rule)
	runtimeSeen.observe(sessionID, classifyRuntime(obs))
	if editorUp {
		ws.fgIsEditor = true
		ws.fgClass = editorWindowClass
		ws.fgPID = gamePID
		ws.fgIsGame = true
		ws.fgHWND = stubFGHWND(ws.fgClass, ws.fgPID)
		return ws
	}
	token := "other"
	if b, err := os.ReadFile(stubForegroundMarker(gamePID)); err == nil {
		if s := strings.TrimSpace(string(b)); s != "" {
			token = s
		}
	}
	switch token {
	case "editor":
		ws.fgIsEditor = true
		ws.fgClass = editorWindowClass
		ws.fgPID = gamePID
		ws.fgIsGame = true
	case "sdl":
		ws.fgClass = sdlWindowClass
		ws.fgPID = gamePID
		ws.fgIsGame = true
		ws.fgIsSDL = true
	case "mame":
		ws.fgClass = "MAME"
		ws.fgPID = gamePID
		ws.fgIsGame = true
	case "vd":
		ws.fgClass = vdWindowClass
		ws.fgPID = stubVirtualDesktopPID
	case "third":
		ws.fgClass = "OtherApp"
		ws.fgPID = stubThirdPartyPID
	case "none":
		// No foreground window: the zero facts say exactly that.
	default: // "other": the stub's player window holds it
		ws.fgClass = stubPlayerClass(gamePID)
		ws.fgPID = gamePID
		ws.fgIsGame = true
		ws.fgIsSDL = ws.fgClass == sdlWindowClass
	}
	ws.fgHWND = stubFGHWND(ws.fgClass, ws.fgPID)
	return ws
}

// activateSDLWindow on Linux: the activation sequence's push,
// mirrored through the foreground marker - a successful
// attempt moves the scripted foreground to the game's SDL
// window ("sdl"), which the next gameWindowState reads back
// as fgIsSDL for the sequence's verify. Two honest failures:
// the game has no SDL window to raise - reported while the
// stub is in its editor state (the player, and its SDL
// window, are gone) or has no window phase at all - and the
// stubborn case (stubFGStubbornMarker), where the attempt is
// reported but the foreground does not move, so verify and
// the single retry run their course.
func activateSDLWindow(gamePID int) bool {
	if gamePID <= 0 {
		return false
	}
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		return false
	}
	if !gameWindowPresentOnMaps(gamePID) {
		return false
	}
	if _, err := os.Stat(stubFGStubbornMarker(gamePID)); err == nil {
		return true
	}
	os.WriteFile(stubForegroundMarker(gamePID), []byte("sdl\n"), 0644)
	return true
}
