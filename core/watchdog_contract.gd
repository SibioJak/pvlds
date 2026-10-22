class_name WatchdogContract
extends RefCounted

## The session contract between the launcher and the watchdog process
## (design sections 3/5/6): one small JSON file in the app's user://
## directory. The launcher writes it; the watchdog polls it. Writes go
## to a temp file renamed over the real one, so a reader never sees a
## half-written contract.
##
## Fields:
##   version          schema version (2)
##   armed            false = the session was disarmed; watchdog stands down
##   disarm_reason    who disarmed, in plain words ("room Exit",
##                    "window close", "watchdog loop cap", ...),
##                    written by disarm() alongside armed=false and
##                    read by the watchdog into its stand-down log
##                    line - a silent dismissal cost five builds of
##                    field diagnosis, so every disarm now names its
##                    author. Absent in contracts written before the
##                    field existed; loads default it to "" and the
##                    watchdog falls back to the legacy generic.
##                    Cleared whenever a session (re)arms. Schema
##                    stays v2.
##   focus_herding    the config kill-switch, mirrored for the watchdog
##   (No close-duty or hold keys: the exit model was simplified
##   by the player's ruling, 2026-10-22 - the watchdog's
##   session-close duty is unconditional and there is no hold
##   gesture. Contracts written by older builds may still carry
##   close_vpx_on_table_exit / hold_exit_enabled /
##   hold_exit_button; both readers ignore them, and writes here
##   stop emitting them. Schema stays v2.)
##   session_id       increments on every launch; how the watchdog
##                    knows a NEW session was armed after a relaunch
##   session_state    idle | loading | live | returned | failed
##                    loading: VPX spawned, the launcher is STILL
##                    resident in the room while the table loads - if
##                    VPX dies now the session failed and the watchdog
##                    must NOT relaunch (the resident launcher shows
##                    the failure). live: the hand-off completed and
##                    the launcher has exited - VPX death now triggers
##                    the one relaunch. (Schema v1 called these
##                    "launching" / "playing"; loads normalize them.)
##   game_exe_path    the VPX executable of the live session
##   game_pid         VPX process id once spawned (0 = not yet / none)
##   game_started_unix
##   game_window_seen_unix  stamped by the watchdog when the game's
##                    PLAYER window first exists (the watchdog's
##                    sighting rule - the editor frame is up from
##                    app start and must not stamp this); the resident
##                    launcher reads it (+ a short settle) as its
##                    hand-off cue
##   launcher_path    what the watchdog relaunches
##   launcher_args    ...with these arguments
##   launcher_pid     pid of the launcher that last checked in
##   last_checkin_unix  bumped on every launcher boot and launch; the
##                    watchdog's 24h stale-watch timeout reads this
##   updated_unix

const CONTRACT_FILE_NAME: String = "pvlds_watchdog_contract.json"
const SCHEMA_VERSION: int = 2

var armed: bool = false
var disarm_reason: String = ""
var focus_herding: bool = true
var session_id: int = 0
var session_state: String = "idle"
var game_exe_path: String = ""
var game_pid: int = 0
var game_started_unix: int = 0
var game_window_seen_unix: int = 0
var launcher_path: String = ""
var launcher_args: Array[String] = []
var launcher_pid: int = 0
var last_checkin_unix: int = 0


## Schema v1 state spellings, mapped to the v2 machine. Both readers
## (the launcher and the watchdog) normalize on load, so a contract
## written by either build generation is understood by the other.
static func normalize_state(state: String) -> String:
	match state:
		"launching":
			return "loading"
		"playing":
			return "live"
	return state


static func contract_path() -> String:
	return "user://".path_join(CONTRACT_FILE_NAME)


static func contract_dir_absolute() -> String:
	return ProjectSettings.globalize_path("user://")


static func contract_path_absolute() -> String:
	return ProjectSettings.globalize_path(WatchdogContract.contract_path())


static func load_from_disk() -> WatchdogContract:
	var c: WatchdogContract = WatchdogContract.new()
	var path: String = WatchdogContract.contract_path()
	if not FileAccess.file_exists(path):
		return c
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return c
	var d: Dictionary = parsed
	c.armed = bool(d.get("armed", false))
	c.disarm_reason = str(d.get("disarm_reason", ""))
	c.focus_herding = bool(d.get("focus_herding", true))
	c.session_id = int(d.get("session_id", 0))
	c.session_state = str(d.get("session_state", "idle"))
	c.session_state = WatchdogContract.normalize_state(c.session_state)
	c.game_exe_path = str(d.get("game_exe_path", ""))
	c.game_pid = int(d.get("game_pid", 0))
	c.game_started_unix = int(d.get("game_started_unix", 0))
	c.game_window_seen_unix = int(d.get("game_window_seen_unix", 0))
	c.launcher_path = str(d.get("launcher_path", ""))
	c.launcher_pid = int(d.get("launcher_pid", 0))
	c.last_checkin_unix = int(d.get("last_checkin_unix", 0))
	c.launcher_args.clear()
	var la: Variant = d.get("launcher_args", [])
	if la is Array:
		var arr: Array = la
		for item: Variant in arr:
			c.launcher_args.append(str(item))
	return c


func to_dictionary() -> Dictionary:
	var d: Dictionary = {}
	d["version"] = SCHEMA_VERSION
	d["armed"] = armed
	d["disarm_reason"] = disarm_reason
	d["focus_herding"] = focus_herding
	d["session_id"] = session_id
	d["session_state"] = session_state
	d["game_exe_path"] = game_exe_path
	d["game_pid"] = game_pid
	d["game_started_unix"] = game_started_unix
	d["game_window_seen_unix"] = game_window_seen_unix
	d["launcher_path"] = launcher_path
	var la: Array = []
	for a: String in launcher_args:
		la.append(a)
	d["launcher_args"] = la
	d["launcher_pid"] = launcher_pid
	d["last_checkin_unix"] = last_checkin_unix
	d["updated_unix"] = int(Time.get_unix_time_from_system())
	return d


## Atomic-enough save: write a sibling temp file, rename it over.
func save_to_disk() -> bool:
	var path_abs: String = WatchdogContract.contract_path_absolute()
	var tmp_abs: String = path_abs + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_abs, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	if FileAccess.file_exists(path_abs):
		DirAccess.remove_absolute(path_abs)
	return DirAccess.rename_absolute(tmp_abs, path_abs) == OK
