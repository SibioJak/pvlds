package main

// Session activation: ONE aimed activation of the game's SDL
// window after the table runtime settles (platform-free decision
// logic, unit-tested on Linux; the foreground facts and the push
// itself are platform leaves - herd_windows.go / window_linux.go).
//
// Why this exists (field forensics, Chris's rig, watchdog-6 log
// session 35 = Godzilla on ef8fa86, 2026-10-23): the one-shot
// focus handoff (main.go) never fired - "game already holds the
// foreground" - because at PROCESS level the game held the
// foreground all session: editor -> loading dialog -> SDL_app ->
// MAME, every window the game pid's own. Yet the table had no
// gamepad AND no sound until the player alt-tabbed (his standing
// law: no controller => no sound; alt-tab cures both). The
// foreground's last internal move before play was PinMAME's
// "MAME" window taking it ~6s after the runtime came up; the
// game's SDL_app window - the one that owns input - never
// regained it during play. In the good Getaway session the
// foreground settled on SDL_app by itself.
//
// Diagnosis: the missing activation is WINDOW-level, not
// process-level. Alt-tab works because it lands activation on a
// specific window through a genuine deactivate/activate cycle.
// So this duty does exactly one deliberate thing: after the
// runtime is up and the startup foreground shuffle settles,
// put the foreground on the game's SDL window - once, verified,
// then never again. It is NOT herding: herding was a repeated
// duty and is loading-only now; this is a single act inside a
// bounded window (it gives up at runtime-up +
// activationDeadlineMs), and it never runs before the settle.
//
// The sequence, per session, fed live ticks only:
//
//   SETTLE: watch the foreground's identity (class + owner -
//   who holds it, not which handle). When it has been unchanged
//   for activationSettleMs, resolve - but never before
//   runtime-up + activationResolveFloorMs, and stability only
//   accumulates under a REAL holder: the editor frame and the
//   loading dialog are load-phase placeholders, and time spent
//   on them is a lull, not a settle. If it never settles, the
//   deadline resolves on whatever the foreground is then.
//
// Why the floor and the lull rule (field forensics,
// watchdog-7 log sessions 36-39, 2026-10-23): the shuffle
// finishes by ~+7s after runtime-up in every observed session,
// but the bare settle rule can be fooled earlier. In session
// 39 the foreground sat stable on the EDITOR for the full
// settle constant mid-load; the sequence resolved at
// runtime+2s ("the editor holds the foreground; standing
// down") and went home - and only then did VPX's real final
// moves land (SDL at +3s, PinMAME's grab at +6s, held through
// dead play). In session 36 the foreground kept changing, the
// sequence stayed alive, caught PinMAME holding, pushed the
// SDL window, and the table worked. Pass/fail was whether the
// sequence's patience outlasted the shuffle; the floor makes
// the patience structural.
//
//   RESOLVE (at settle or at the deadline):
//     - the foreground IS the editor window (class "VPinball",
//       the game pid's frame - the fact the exit detector reads,
//       closer.go): hands off, stand down. That foreground
//       belongs to the exit story, under any circumstances.
//     - the foreground is already the SDL window: nothing to
//       do - log "activation not needed" and stand down.
//     - eligible holders: any window of the game process,
//       Virtual Desktop's window, or no window at all (the
//       desktop). ACT (below).
//     - an unrelated third process holds it: the player put it
//       there or another app did; stand down silently-ish (one
//       log line) - never steal from a stranger.
//
//   ACT: the caller foregrounds the game pid's SDL window via
//   the leaf (activateSDLWindow: the visible SDL window if one
//   exists, else any SDL window of the pid; no SDL window at
//   all = stand down, logged). The caller reports the attempt
//   back through notePushAttempted, and - only when a push was
//   actually attempted - also records it with the exit
//   detector (closer.notePush): the detector's excursion and
//   sustain accounting starts from facts after our own last
//   foreground touch, the same rule the ef8 focus push follows.
//   VERIFY by read-back activationVerifyMs later: if the
//   foreground is the SDL window, the act stuck - log it, with
//   the class that held the foreground before. If not, push
//   once more and verify again; a second miss logs honestly
//   ("did not stick after retry") and stands down.
//
//   An editor foreground during SETTLE is just a lull (see
//   above) - the sequence waits it out. But once a push is in
//   flight (ordered, awaiting its report or its verify), an
//   editor foreground aborts the sequence (same stand-down):
//   a landing mid-sequence owns the foreground, and the retry
//   must never fight the exit detector for it. Safety over
//   eagerness, and the log line says why.

// vdWindowClass is Virtual Desktop's window class
// ("CabinetWClass", pid = Virtual Desktop's own process in the
// field inventories): an eligible pre-activation holder - the
// player is in the headset, not at that window deliberately in
// any way this duty needs to respect.
const vdWindowClass = "CabinetWClass"

// loadDialogClass is the Win32 class of VPX's loading dialog
// (the standard "#32770" dialog class, the game pid's own
// window): a load-phase placeholder like the editor frame -
// its stability is a lull, not a settle.
const loadDialogClass = "#32770"

const (
	// How long the foreground must sit unchanged after the
	// runtime stamps before the sequence resolves: the startup
	// shuffle (dialog -> SDL -> PinMAME's own grab ~6s in on
	// the field rig) has to be OVER, or the act lands on a
	// foreground that is about to move again.
	activationSettleMs = 2800
	// The sequence may not resolve before runtime-up + this,
	// however stable things look: every field session's
	// shuffle ran to ~+7s, and a stable editor mid-load is a
	// lull that fooled the bare settle rule in session 39.
	activationResolveFloorMs = 8000
	// The sequence gives up waiting at runtime-up + this: past
	// it, whatever owns the foreground owns it, and a late grab
	// (+20s, say) is not ours to chase.
	activationDeadlineMs = 12000
	// Read-back delay after a push: long enough for Windows to
	// have applied (or refused) the foreground change.
	activationVerifyMs = 1000
	// Total pushes per sequence: the act plus one retry.
	activationMaxPushes = 2
)

// actAction is what one activation tick decided - and what the
// caller logs or does about it.
type actAction int

const (
	actNone          actAction = iota
	actPushNow                 // foreground the SDL window now (leaf call), then report via notePushAttempted
	actLogNotNeeded            // the SDL window already holds the foreground; sequence over
	actLogStuck                // verify passed: the act held (beforeClass names the prior holder)
	actLogFailed               // verify failed after the retry; sequence over
	actLogNoTarget             // a push was ordered but the game has no SDL window; sequence over
	actLogEditor               // the editor holds the foreground; hands off, sequence over
	actLogThirdParty           // an unrelated process holds the foreground; sequence over
)

// activator is the per-session activation state machine. A new
// sessionID resets everything; the sequence runs at most once
// per session. runtimeUpMs anchors the deadline: the caller
// passes the tick it first observed the session's runtime stamp
// (0 = not up yet, the machine idles).
type activator struct {
	sessionID  int
	phase      int // 0 waiting/settle-tracking, 1 awaiting push report, 2 verifying, 3 done
	runtimeUp  int64
	fgClass    string // foreground identity at the last tick
	fgPID      int
	fgSinceMs  int64  // when the current foreground identity began
	before     string // the holder's class when the act was ordered
	verifyAtMs int64
	pushes     int
}

func (a *activator) reset(sessionID int) {
	*a = activator{sessionID: sessionID}
}

// beforeClass names the class that held the foreground when the
// act was ordered - the "was" in the outcome log lines.
func (a *activator) beforeClass() string { return a.before }

// eligible reports whether a foreground holder may be acted
// over: the game process itself, Virtual Desktop, or nobody
// (no foreground window / the desktop). The editor and the SDL
// window are resolved before this is consulted; a stranger's
// window is the only refusal left.
func eligible(ws windowState) bool {
	return ws.fgIsGame || ws.fgClass == vdWindowClass || ws.fgPID == 0
}

// lullHolder reports whether the foreground holder is a
// load-phase placeholder whose stability must not count
// toward the settle: the editor frame or the loading dialog,
// both the game pid's own windows. While either holds, the
// sequence stays pending and the stability clock does not
// accumulate (session 39: a stable editor mid-load read as a
// settle and the sequence went home before the shuffle's real
// final moves).
func lullHolder(ws windowState) bool {
	return ws.fgIsEditor || (ws.fgIsGame && ws.fgClass == loadDialogClass)
}

// resolve decides a settled (or deadline-reached) foreground.
func (a *activator) resolve(ws windowState) actAction {
	switch {
	case ws.fgIsEditor:
		a.phase = 3
		return actLogEditor
	case ws.fgIsSDL:
		a.phase = 3
		return actLogNotNeeded
	case eligible(ws):
		a.before = ws.fgClass
		a.pushes = 1
		a.phase = 1
		return actPushNow
	default:
		a.phase = 3
		return actLogThirdParty
	}
}

// tick advances the sequence by one watchdog tick. The caller
// feeds it live sessions only, with the tick's foreground facts
// (windowState) and the session's runtime-stamp tick
// (runtimeUpMs, 0 while the runtime has not stamped).
func (a *activator) tick(nowMs int64, sessionID int, runtimeUpMs int64, ws windowState) actAction {
	if sessionID != a.sessionID {
		a.reset(sessionID)
	}
	if a.phase == 3 || runtimeUpMs == 0 {
		return actNone
	}
	if a.runtimeUp == 0 {
		a.runtimeUp = runtimeUpMs
		a.fgClass, a.fgPID = ws.fgClass, ws.fgPID
		a.fgSinceMs = nowMs
		return actNone
	}
	// The editor holding the foreground ends the sequence
	// once a push is in flight (phases 1-2): that foreground
	// is the exit landing's (or the player's deliberate visit
	// to it), and nothing here may fight the exit detector
	// for it. During settle-tracking (phase 0) the editor is
	// merely a lull holder - the branch below waits it out.
	if ws.fgIsEditor && a.phase != 0 {
		a.phase = 3
		return actLogEditor
	}
	switch a.phase {
	case 0: // settle-tracking
		if ws.fgClass != a.fgClass || ws.fgPID != a.fgPID {
			a.fgClass, a.fgPID = ws.fgClass, ws.fgPID
			a.fgSinceMs = nowMs
		}
		if lullHolder(ws) {
			// No accumulation under a placeholder: the
			// stability clock restarts from this tick, so a
			// settle can only ever complete under the real
			// holder that follows the lull.
			a.fgSinceMs = nowMs
		}
		settled := nowMs-a.fgSinceMs >= activationSettleMs && nowMs-a.runtimeUp >= activationResolveFloorMs
		if settled || nowMs-a.runtimeUp >= activationDeadlineMs {
			return a.resolve(ws)
		}
	case 2: // verifying the last push
		if nowMs < a.verifyAtMs {
			return actNone
		}
		if ws.fgIsSDL {
			a.phase = 3
			return actLogStuck
		}
		if a.pushes < activationMaxPushes {
			a.pushes++
			a.phase = 1
			return actPushNow
		}
		a.phase = 3
		return actLogFailed
	}
	// Phase 1 (awaiting the push report) produces nothing on
	// ticks: the caller reports synchronously via
	// notePushAttempted in the same pass that acted.
	return actNone
}

// notePushAttempted reports the caller's push attempt back: the
// leaf either had an SDL window to raise (attempted) or did not
// (no target - the sequence stands down, logged by the caller
// from the returned action). On an attempt, the verify clock
// starts.
func (a *activator) notePushAttempted(nowMs int64, attempted bool) actAction {
	if a.phase != 1 {
		return actNone
	}
	if !attempted {
		a.phase = 3
		return actLogNoTarget
	}
	a.phase = 2
	a.verifyAtMs = nowMs + activationVerifyMs
	return actNone
}
