class_name SdlBootstrap
extends RefCounted

## FIX115 (1.1.5): the controller grab, and the one bounce
## that removes it.
##
## The conviction (field, droscoe, Issue #1): while
## LaunchPin runs, DirectInput-class controllers (his
## arcade stick) are dead in every other program — VPX
## launched from the app hears nothing, Windows' own
## controller test page hears nothing — while LaunchPin
## itself hears every press. App closed, everyone hears
## the stick again. The mechanism (research dossier,
## ~/workspace/pvlds-padgrab/RESEARCH.md): Godot 4.7's
## controller support on Windows is embedded SDL 3, whose
## DirectInput driver opens every joystick EXCLUSIVE for
## the life of the process, starving the other
## DirectInput readers (VPX, joy.cpl). True XInput pads
## ride SDL's XInput backend, which never locks — why
## most pads never met this. SDL's own cure is the hint
## SDL_JOYSTICK_DIRECTINPUT=0, which retires the
## DirectInput backend for the process; SDL then reads
## controllers through its shared backends. (Upstream
## SDL fixed the grab itself on 2026-11-08, SDL#16277;
## the engine's vendored SDL 3.2.28 predates it.)
##
## The hint must be in the process environment BEFORE
## SDL initialises, and GDScript only runs after engine
## init — so the fix is delivered as a bootstrap bounce,
## at the earliest app entry (Main._init): on Windows,
## if the variable is unset, set it, relaunch this same
## executable with the same arguments, and let the caller
## quit. The child is born with the variable in place and
## never grabs. One bounce per cold start, invisible: the
## parent exits before any window or boot logic runs.
##
## The law, point by point:
## - Any value already set wins, untouched. A user's own
##   setting is respected verbatim — and a bounced child
##   always sees the variable, which is what makes the
##   bounce loop-proof by construction.
## - A set that does not stick (read back after setting)
##   proceeds WITHOUT bouncing rather than risk a spin.
## - A failed relaunch proceeds without the hint: the
##   pre-1.1.5 behaviour beats a process that can only
##   restart itself forever.
## - Arguments pass through exactly: the engine args and
##   the user args, in the split the engine reported
##   (engine args, "--", user args), so --setup and every
##   --pvlds-smoke-* mode arrive at the child verbatim.
## - Editor runs never bounce (the shipped process is
##   the patient; OS.get_executable_path() in the editor
##   is the editor, not the game). Non-Windows platforms
##   see no behaviour change at all.
## - The watchdog contract is untouched: the watchdog
##   binary does not change, and when the watchdog
##   relaunches the app the variable is either inherited
##   down the chain (app -> watchdog -> app) or
##   re-established by this same one bounce.
##
## Bench seams (the house NC pattern; nothing in
## production sets them): PVLDS_BOOTSTRAP_FORCE=1 lets
## the Linux export exercise this path (this box has no
## Windows/SDL-DirectInput surface to test against), and
## PVLDS_BOOTSTRAP_NC=failspawn forces the
## failed-relaunch branch.

const HINT_VAR: String = "SDL_JOYSTICK_DIRECTINPUT"


## Returns true when this process has relaunched itself
## and must now quit (the caller in Main._init/_ready
## owns the quit — _init has no tree yet). False means
## proceed: not Windows, editor run, variable already
## set, or a graceful degradation described above.
static func maybe_bounce() -> bool:
	if OS.has_feature("editor"):
		return false
	if not OS.has_feature("windows") and OS.get_environment("PVLDS_BOOTSTRAP_FORCE") != "1":
		return false
	if OS.has_environment(HINT_VAR):
		return false
	OS.set_environment(HINT_VAR, "0")
	if OS.get_environment(HINT_VAR) != "0":
		return false
	var args: PackedStringArray = PackedStringArray()
	args.append_array(OS.get_cmdline_args())
	args.append("--")
	args.append_array(OS.get_cmdline_user_args())
	var pid: int = -1
	if OS.get_environment("PVLDS_BOOTSTRAP_NC") != "failspawn":
		pid = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		print("PVLDS bootstrap: relaunch failed; proceeding without ", HINT_VAR)
		return false
	print("PVLDS bootstrap: ", HINT_VAR, " was unset; set to 0 and relaunched (pid ", pid, "); this process exits")
	return true
