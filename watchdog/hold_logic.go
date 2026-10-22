package main

// Hold-to-exit: the decision logic (platform-free, unit-tested on
// Linux; the button feed is a platform leaf - hold_windows.go reads
// real XInput, hold_other.go reads the smokes' stub feed).
//
// Why this exists: Chris's proposal, echoing VpxLauncher's UX. A
// TAP of his gamepad exit button is VPX's own business and lands
// him in the VPX editor, as it always has. A HOLD of the same
// button means "I am done" - and a deliberate gesture held for a
// second and a half cannot be a window-state misread, which is the
// failure class the session-close duty (closer.go) has to defend
// against with its arming and sustaining. The hold is therefore
// the primary return path: while a session is live, the watchdog
// polls the gamepad (see main.go's hold watch), and a continuous
// hold of the configured button past the threshold fires the same
// orderly close the closer sends (FrontEndControls CLOSE_APP,
// escalating to WM_CLOSE, never a hard kill). The ordinary
// process-death machinery then relaunches the launcher.
//
// The hold's only gate is the live session itself: no player-
// window requirement at fire time. A hold that begins during play
// normally completes after VPX has already acted on the tap half
// of the gesture and dropped to the editor - the player window is
// GONE by the time the close goes out, and that is the design, not
// a race. (The ladder's WM_CLOSE step is in any case refused by
// VP's editor while a player is open - WinEditor::OnClose - so
// the escalation can only land in a state where closing is safe.)
//
// MODE NOTE (the arbitration round): the mapping above is the
// hold-ONLY mode (the closer switch off). With the closer switch
// ALSO on, this duty is fed inactive and the exit arbitrator
// (arbiter.go) owns the gesture with the INVERTED mapping Chris
// settled: a tap returns to the room (the arbitrator fires the
// close at the editor landing), a hold bails to the editor and
// disarms. See the mode table at the dispatch in main.go.
//
// This file owns: the XInput button name/mask table (the config's
// hold_exit_button string resolves through it on both sides of the
// contract), the hold brain (press timing, once-per-hold, release
// re-arm), and the escalation ladder's timing, shared with the
// closer's constants.

// xinputButtonMasks is the standard XInput button set by the
// names the config and the desk picker use. The values are the
// XINPUT_GAMEPAD_* bit constants (Microsoft's xinput.h).
var xinputButtonMasks = map[string]uint16{
	"dpad_up":        0x0001,
	"dpad_down":      0x0002,
	"dpad_left":      0x0004,
	"dpad_right":     0x0008,
	"start":          0x0010,
	"back":           0x0020,
	"left_thumb":     0x0040, // L3
	"right_thumb":    0x0080, // R3
	"left_shoulder":  0x0100, // LB
	"right_shoulder": 0x0200, // RB
	"a":              0x1000,
	"b":              0x2000,
	"x":              0x4000,
	"y":              0x8000,
}

// defaultHoldButton is the contract/config default when the key is
// absent or unresolvable: D-pad Right, Chris's recorded VPX
// ExitGame binding ("right directional" - see the desk picker and
// the round report).
const defaultHoldButton = "dpad_right"

// holdButtonMask resolves a configured button name to its XInput
// bit mask. Unknown names report ok=false; the duty is inert for
// them (and the watchdog logs why, once per session).
func holdButtonMask(name string) (uint16, bool) {
	m, ok := xinputButtonMasks[name]
	return m, ok
}

const (
	// How long the exit button must be held, continuously, before
	// the close fires. Chris's call after a session sizes this;
	// the retune is this one constant.
	holdThresholdMs = 1500
	// The button feed's poll cadence in the watchdog's hold
	// watch (main.go): fine enough that the threshold crossing is
	// felt at the threshold, not a tick later.
	holdPollIntervalMs = 50
)

// holdAction is what one hold-duty tick decided.
type holdAction int

const (
	holdNone    holdAction = iota
	holdFEC                // send the FrontEndControls CLOSE_APP now
	holdWMClose            // escalate: send WM_CLOSE now
	holdGiveUp             // nothing landed; log it and leave VPX alone
)

// holdDuty advances hold-to-exit one poll at a time. Session
// changes reset everything. The duty is only ever FED while its
// gate holds (caller passes active=false otherwise: session not
// live, feature off, game dead, or button name unresolvable), and
// an inactive tick resets the gesture and the ladder alike - the
// session it belonged to is over.
type holdDuty struct {
	sessionID   int
	heldSinceMs int64 // first poll of the current continuous hold; 0 = not holding
	fired       bool  // the current hold has produced its one fire
	stage       int   // 0 idle, 1 FEC sent, 2 WM_CLOSE sent, 3 gave up
	actionAtMs  int64 // when the current stage's action went out
}

func (d *holdDuty) tick(nowMs int64, sessionID int, active bool, pressed bool) holdAction {
	if sessionID != d.sessionID {
		*d = holdDuty{sessionID: sessionID}
	}
	if !active {
		d.heldSinceMs = 0
		d.fired = false
		d.stage = 0
		return holdNone
	}
	// The escalation ladder runs on its own clock once a fire has
	// gone out, independent of the button: the gesture is complete
	// and VPX is (or is not) closing. It is checked before the
	// gesture so a re-hold after give-up can restart the ladder
	// in the same tick the brain fires below.
	switch d.stage {
	case 1:
		if nowMs-d.actionAtMs >= fecGraceMs {
			d.stage = 2
			d.actionAtMs = nowMs
			return holdWMClose
		}
	case 2:
		if nowMs-d.actionAtMs >= closeGiveUpMs {
			d.stage = 3
			return holdGiveUp
		}
	}
	// The gesture itself: track the continuous hold.
	if !pressed {
		// Full release re-arms the brain. (The ladder above is
		// untouched: a close already requested still escalates.)
		d.heldSinceMs = 0
		d.fired = false
		return holdNone
	}
	if d.fired {
		return holdNone // one fire per hold, however long it runs
	}
	if d.heldSinceMs == 0 {
		d.heldSinceMs = nowMs
		return holdNone
	}
	if nowMs-d.heldSinceMs >= holdThresholdMs {
		d.fired = true
		// A fresh deliberate hold restarts the ladder even after
		// a give-up: the player is asking again.
		d.stage = 1
		d.actionAtMs = nowMs
		return holdFEC
	}
	return holdNone
}
