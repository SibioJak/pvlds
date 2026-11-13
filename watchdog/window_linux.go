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
// the focus sequence's smokes (focus.go): while the file
// stands, this leaf's activatePlayerWindow reports an attempt
// whose SetForegroundWindow verdict is refusal and the
// foreground does not move - the mirror of a holder (or
// Windows) refusing the raise, so the sequence's verify and
// retries run their course. The stub raises it under
// STUB_FG_STUBBORN (see stub_vpx_window.c).
func stubFGStubbornMarker(gamePID int) string {
	return "/tmp/pvlds-stub-fg-stubborn-" + strconv.Itoa(gamePID)
}

// playerSight is this leaf's sighting gate (sighting.go) - the
// same shared gate the Windows leaf feeds, so the smokes exercise
// the shipped rule, persistence included.
var playerSight playerSighting

// playerTargetState is this leaf's player-target resolver
// (target.go) - the same shared resolver the Windows leaf
// feeds, over this leaf's synthesized-handle observations.
var playerTargetState targetResolver

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
// latched for this session, and which signature stamped it -
// the same latch the Windows leaf reports, fed by the stub's
// window set (gameWindowState).
func gameRuntimeExists(gamePID int, sessionID int) (bool, string) {
	if gamePID <= 0 {
		return false, ""
	}
	return runtimeSeen.hasSeen(sessionID), runtimeSeen.ruleFor(sessionID)
}

// stubFGFactsMarker is the scripted identity file for the
// "board" foreground token: lines of key=value naming the
// bystander window's proc=, class= and title= - the facts the
// Windows leaf reads off a real window (GetWindowText, the
// process image) and the focus guard matches its registry
// against (bystanders.go). The smoke writes it beside the
// stub (the stub C owns it under STUB_BOARD_FACTS; a scenario
// may also write it directly). Absent fields fall back to the
// PINemHi-shaped defaults in stubBoardFacts.
func stubFGFactsMarker(gamePID int) string {
	return "/tmp/pvlds-stub-fgfacts-" + strconv.Itoa(gamePID)
}

// stubInputMarker scripts the INPUT PROVENANCE facts the
// focus duties read (windowState.inputAgeMs / altWinEdge):
// its contents are "<age-ms>" - how long ago the last desktop
// input landed - optionally followed by " edge" (an Alt/Win/
// mouse-button key down). The stub C writes it under
// STUB_INPUT_SEQ (an age@sec script mirroring STUB_FG_SEQ);
// a scenario may also write it directly. An absent file reads
// as the age being unknown (-1): the launch sequence treats
// unknown as no deliberate-use evidence (assertions proceed),
// the guard treats it as ambiguity and never reclaims - the
// asymmetry is the design's (focus.go / guard.go).
func stubInputMarker(gamePID int) string {
	return "/tmp/pvlds-stub-input-" + strconv.Itoa(gamePID)
}

// stubBoardFacts reads the "board" token's scripted identity
// (stubFGFactsMarker), with PINemHi-shaped defaults.
func stubBoardFacts(gamePID int) (proc, class, title string) {
	proc, class, title = "PINemHi LeaderBoard.exe", "PinemhiLeaderboard", "PINemHi LeaderBoard"
	b, err := os.ReadFile(stubFGFactsMarker(gamePID))
	if err != nil {
		return proc, class, title
	}
	for _, line := range strings.Split(string(b), "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok {
			continue
		}
		switch k {
		case "proc":
			proc = v
		case "class":
			class = v
		case "title":
			title = v
		}
	}
	return proc, class, title
}

// stubInputFacts reads the scripted input-provenance facts
// (stubInputMarker): the desktop-input age in ms (-1 =
// unknown) and whether an Alt/Win/mouse edge is scripted.
func stubInputFacts(gamePID int) (ageMs int64, edge bool) {
	ageMs = -1
	b, err := os.ReadFile(stubInputMarker(gamePID))
	if err != nil {
		return ageMs, false
	}
	for _, f := range strings.Fields(string(b)) {
		if f == "edge" {
			edge = true
			continue
		}
		if n, err := strconv.ParseInt(f, 10, 64); err == nil {
			ageMs = n
		}
	}
	return ageMs, edge
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

// stubExplorerPID is the foreground-owner pid the "switcher"
// marker token reports: explorer.exe in the field inventories
// (sessions 202/204/205), used verbatim like
// stubVirtualDesktopPID above.
const stubExplorerPID = 11576

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
//	"board"   a known-bystander window (FIX116): its class,
//	          process and title come from the facts file
//	          (stubFGFactsMarker), its pid is the bystander
//	          pid - the focus guard's PINemHi shape
//	"switcher" the Windows Task Switching window (FIX116
//	          pass 2): explorer's alt-tab picker island
//	          window - class XamlExplorerHostIslandWindow,
//	          pid stubExplorerPID, title "Task Switching" -
//	          the focus guard's deliberate-switch evidence
//	"none"    no foreground window at all
//	"player"  the stub's player window, carrying its declared
//	          class (stubPlayerClass) - what this leaf's own
//	          raise writes when an assertion lands
//	"other"   (or an absent file) the same as "player"
//
// The window observations carry synthesized handles
// (stubFGHWND over class + pid) so the shared player-target
// resolver (target.go) ranks them exactly as the Windows leaf
// ranks real handles, and fgIsPlayer is the same handle
// equality the shipped build computes. The input-provenance
// facts come from the input marker (stubInputMarker).
//
// While the editor marker stands, the foreground is reported
// as the editor regardless of the token: the stub is IN its
// editor state then, and on the real rig that state is the
// editor holding the foreground - the invariant the exit
// detector is built on. (It also keeps this leaf's own
// activatePlayerWindow token write, landing a moment before
// the stub's editor phase begins, from forging a player
// foreground the rig could never show.) No editor handle
// exists off Windows; the foreground identity (fgHWND) is
// synthesized from the holder's class + pid instead - see
// stubFGHWND.
func gameWindowState(gamePID int, sessionID int) windowState {
	ws := windowState{inputAgeMs: -1}
	if gamePID <= 0 {
		return ws
	}
	var obs []windowObs
	editorUp := false
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		editorUp = true
		obs = append(obs, windowObs{hwnd: stubFGHWND(editorWindowClass, gamePID), class: editorWindowClass, width: 1280, height: 900, visible: true})
	} else if gameWindowPresentOnMaps(gamePID) {
		visible := true
		if _, err := os.Stat(stubPlayerHiddenMarker(gamePID)); err == nil {
			visible = false
		}
		class := stubPlayerClass(gamePID)
		obs = append(obs, windowObs{hwnd: stubFGHWND(class, gamePID), class: class, width: 400, height: 300, visible: visible})
		if _, err := os.Stat(stubRuntimeMarker(gamePID)); err == nil {
			obs = append(obs, windowObs{hwnd: stubFGHWND("SharpGLRenderWindow", gamePID), class: "SharpGLRenderWindow", width: 307, height: 77, visible: false})
		}
	}
	candidate, rule := classifyPlayerCandidate(obs)
	playerSight.observe(sessionID, candidate, rule)
	runtimeSeen.observe(sessionID, classifyRuntime(obs), classifyVPPlayer(obs))
	ws.playerHWND, ws.playerClass, ws.playerWhy = playerTargetState.resolve(sessionID, obs)
	ws.inputAgeMs, ws.altWinEdge = stubInputFacts(gamePID)
	if editorUp {
		ws.fgIsEditor = true
		ws.fgClass = editorWindowClass
		ws.fgPID = gamePID
		ws.fgIsGame = true
		ws.fgHWND = stubFGHWND(ws.fgClass, ws.fgPID)
		stubFocusFacts(gamePID, &ws)
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
	case "board":
		ws.fgProcName, ws.fgClass, ws.fgTitle = stubBoardFacts(gamePID)
		ws.fgPID = stubBystanderPID
	case "switcher":
		ws.fgClass = taskSwitcherClass
		ws.fgPID = stubExplorerPID
		ws.fgProcName = "explorer.exe"
		ws.fgTitle = taskSwitcherTitle
	case "none":
		// No foreground window: the zero facts say exactly that.
	default: // "player" / "other": the stub's player window holds it
		ws.fgClass = stubPlayerClass(gamePID)
		ws.fgPID = gamePID
		ws.fgIsGame = true
		ws.fgIsSDL = ws.fgClass == sdlWindowClass
	}
	ws.fgHWND = stubFGHWND(ws.fgClass, ws.fgPID)
	ws.fgIsPlayer = ws.playerHWND != 0 && ws.fgHWND == ws.playerHWND
	stubFocusFacts(gamePID, &ws)
	stubActiveFacts(gamePID, &ws)
	return ws
}

// activatePlayerWindow on Linux: the focus duties' raise,
// mirrored through the foreground marker - a successful
// attempt moves the scripted foreground to the player window
// ("player"), which the next gameWindowState reads back as
// fgIsPlayer for the sequence's verify. Honest failures: no
// target, or the game has no player window to raise -
// reported while the stub is in its editor state (the player
// is gone) or has no window phase at all (attempted=false) -
// and the stubborn case (stubFGStubbornMarker), where the
// attempt is real but its verdict is refusal and the
// foreground does not move, so verify and the retries run
// their course (attempted=true, ok=false).
func activatePlayerWindow(gamePID int, targetHWND uintptr) (attempted bool, ok bool) {
	if gamePID <= 0 || targetHWND == 0 {
		return false, false
	}
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		return false, false
	}
	if !gameWindowPresentOnMaps(gamePID) {
		return false, false
	}
	if _, err := os.Stat(stubFGStubbornMarker(gamePID)); err == nil {
		return true, false
	}
	os.WriteFile(stubForegroundMarker(gamePID), []byte("player\n"), 0644)
	return true, true
}

// stubFocusMarker scripts the PLAYER THREAD FOCUS facts the
// FIX117 duties read (windowState's focus snapshot): the
// contents name where the player window's thread focus sits -
// "player" (on the player window), "mame" (on a MAME window
// of the game pid), "none" (the thread has no focus window),
// "stuck" (like "mame", but a delivery does not move it - the
// budget-exhaustion shape), "fail" (the reader fails). An
// absent file is the healthy mirror: focus follows the
// foreground holder. A delivery (deliverPlayerFocus below)
// rewrites "mame"/"none" to "player"; the probe rewrites
// nothing - the stub cannot model SDL's message flag, so a
// probe's effect is deliberately not scripted here.
func stubFocusMarker(gamePID int) string {
	return "/tmp/pvlds-stub-focus-" + strconv.Itoa(gamePID)
}

// stubFocusFacts folds the scripted focus facts (stubFocus-
// Marker) into the snapshot, and names the machinery mirror:
// a MAME sibling window of the game pid whenever a player
// window stands (rung 3's excursion target).
func stubFocusFacts(gamePID int, ws *windowState) {
	if ws.playerHWND != 0 {
		ws.machineryHWND = stubFGHWND("MAME", gamePID)
	}
	b, err := os.ReadFile(stubFocusMarker(gamePID))
	if err != nil {
		// The healthy mirror: the focus sits on whoever
		// holds the foreground.
		ws.focusRead = focusReadOK
		ws.playerFocusHWND = ws.fgHWND
		ws.playerFocusClass = ws.fgClass
		ws.focusIsPlayer = ws.fgIsPlayer
		return
	}
	switch strings.TrimSpace(string(b)) {
	case "fail":
		ws.focusRead = focusReadFailed
	case "player":
		ws.focusRead = focusReadOK
		ws.playerFocusHWND = ws.playerHWND
		ws.playerFocusClass = ws.playerClass
		ws.focusIsPlayer = ws.playerHWND != 0
	case "none":
		ws.focusRead = focusReadOK
		ws.playerFocusHWND = 0
		ws.playerFocusClass = ""
	case "mame", "stuck":
		ws.focusRead = focusReadOK
		ws.playerFocusHWND = stubFGHWND("MAME", gamePID)
		ws.playerFocusClass = "MAME"
	default:
		ws.focusRead = focusReadOK
		ws.playerFocusHWND = ws.fgHWND
		ws.playerFocusClass = ws.fgClass
		ws.focusIsPlayer = ws.fgIsPlayer
	}
}

// stubActiveMarker scripts the PLAYER THREAD ACTIVE-WINDOW
// facts (FIX118): the sibling of stubFocusMarker, with the
// same vocabulary ("player" / "mame" / "none"). An absent
// file is the healthy mirror: the thread's active window IS
// its focus window - the two halves of the one
// GetGUIThreadInfo reading agree, as they do on a healthy
// real thread. The marker's whole purpose is the divergence
// (scenario 48): a thread whose active window differs from
// its focus window, logged in plain words.
func stubActiveMarker(gamePID int) string {
	return "/tmp/pvlds-stub-active-" + strconv.Itoa(gamePID)
}

// stubActiveFacts folds the scripted active-window facts
// (stubActiveMarker) into the snapshot. It runs after
// stubFocusFacts: with no positive focus reading there is no
// active reading either (the one shared read state), and
// with no active marker the active window mirrors whatever
// the focus facts settled on.
func stubActiveFacts(gamePID int, ws *windowState) {
	if ws.focusRead != focusReadOK {
		return
	}
	b, err := os.ReadFile(stubActiveMarker(gamePID))
	if err != nil {
		ws.playerActiveHWND = ws.playerFocusHWND
		ws.playerActiveClass = ws.playerFocusClass
		ws.activeIsPlayer = ws.focusIsPlayer
		return
	}
	switch strings.TrimSpace(string(b)) {
	case "player":
		ws.playerActiveHWND = ws.playerHWND
		ws.playerActiveClass = ws.playerClass
		ws.activeIsPlayer = ws.playerHWND != 0
	case "none":
		ws.playerActiveHWND = 0
		ws.playerActiveClass = ""
		ws.activeIsPlayer = false
	case "mame":
		ws.playerActiveHWND = stubFGHWND("MAME", gamePID)
		ws.playerActiveClass = "MAME"
		ws.activeIsPlayer = false
	default:
		ws.playerActiveHWND = ws.playerFocusHWND
		ws.playerActiveClass = ws.playerFocusClass
		ws.activeIsPlayer = ws.focusIsPlayer
	}
}

// deliverPlayerFocus on Linux mirrors the focus marker: a
// real delivery moves the scripted focus to the player
// window (the next gameWindowState reads it as delivered),
// except under the "stuck" marker, where the attempt is real
// but the focus does not move - the budget-exhaustion shape.
// Honest stand-downs mirror activatePlayerWindow's: no
// target, the editor state (the player is gone), or no
// window phase at all. The rung makes no difference here -
// the stub scripts the focus state, not the act.
func deliverPlayerFocus(gamePID int, targetHWND uintptr, _ int, _ uintptr) (attempted bool, ok bool) {
	if gamePID <= 0 || targetHWND == 0 {
		return false, false
	}
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		return false, false
	}
	if !gameWindowPresentOnMaps(gamePID) {
		return false, false
	}
	if b, err := os.ReadFile(stubFocusMarker(gamePID)); err == nil && strings.TrimSpace(string(b)) == "stuck" {
		return true, false
	}
	os.WriteFile(stubFocusMarker(gamePID), []byte("player\n"), 0644)
	return true, true
}

// probePlayerFocus on Linux mirrors the probe's stand-downs
// and nothing else: the stub cannot model SDL's message flag,
// so a probe never moves the scripted focus - the smoke sees
// the probe lines and their count, and that is all a probe
// may claim here either.
func probePlayerFocus(gamePID int, targetHWND uintptr) (attempted bool) {
	if gamePID <= 0 || targetHWND == 0 {
		return false
	}
	if _, err := os.Stat(stubEditorMarker(gamePID)); err == nil {
		return false
	}
	return gameWindowPresentOnMaps(gamePID)
}

// noteForegroundOwner on Linux: the bench's only scripted
// foreign owner is the "board" bystander; when it holds the
// foreground, its facts file is the owner's window inventory,
// logged in the Windows line's shape. Other owners have no
// scripted set here and stay silent (the Windows leaf logs
// the real enumeration).
func noteForegroundOwner(sessionID int, ws windowState) {
	if ws.fgPID != stubBystanderPID {
		return
	}
	proc, class, title := stubBoardFactsFromWS(ws)
	logf("watchdog: session %d: foreground owner pid %d (%s) windows: class %q title %q (stub-scripted)", sessionID, ws.fgPID, proc, class, title)
}

// stubBoardFactsFromWS is noteForegroundOwner's fact source:
// the snapshot already carries the board token's facts.
func stubBoardFactsFromWS(ws windowState) (proc, class, title string) {
	return ws.fgProcName, ws.fgClass, ws.fgTitle
}
