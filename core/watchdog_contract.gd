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
##   launcher_version FIX118: the writing launcher's product
##                    version (AppInfo.PRODUCT_VERSION), stamped
##                    by to_dictionary() on every save - never
##                    loaded-and-carried, so the value always
##                    names the build that last wrote. The
##                    watchdog logs it in its session header
##                    beside its own version (the version-
##                    visibility rule: a field log identifies
##                    both halves of the pair). Absent in
##                    contracts written before the field
##                    existed; the watchdog's header says
##                    "unknown". Schema stays v2.
##   focus_herding    the config kill-switch, mirrored for the watchdog
##   pinemhi_manage   PINEMHI2 (Part B): the config's watcher-
##                    management toggle, mirrored for the watchdog
##                    exactly like focus_herding (checkin/launch)
##   pinemhi_folder   the resolved PINemHi folder, mirrored the
##                    same way - the watchdog finds the watcher
##                    exe (pinemhi_rom_monitor.exe) inside it
##   pinemhi_watcher_pid / pinemhi_watcher_state
##                    WATCHDOG-owned: the watcher process PVLDS
##                    is responsible for and how it came to be
##                    running ("" | "started" | "adopted"). The
##                    launcher never writes these; they ride
##                    through its load-then-save untouched
##                    because load/save carry them verbatim.
##                    Schema stays v2.
##   hold_exit_enabled  HOLD-EXIT: the config's hold-to-exit
##                    toggle, mirrored for the watchdog exactly
##                    like focus_herding (checkin/launch). The
##                    watchdog's session-close duty stays
##                    unconditional; this gates only the hold
##                    gesture. Absent in contracts written
##                    before the key existed: loads default it
##                    ON (the feature's own default).
##   hold_exit_fired_unix  HOLD-EXIT: WATCHDOG-owned: stamped
##                    once when a session's D-pad-right hold
##                    fires; it is the app-exit signal - a
##                    resident launcher that reads it for its
##                    own session exits through its own Exit
##                    path, and the watchdog reads the same
##                    firing to stand down (no relaunch) when
##                    VPX dies. The launcher never writes it,
##                    except to CLEAR it when a fresh session
##                    is armed (checkin / perform_launch). The
##                    button is fixed to D-pad right:
##                    hold_exit_button from older builds is
##                    still not read, and there is no
##                    close-duty key. Schema stays v2.
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
##   game_table_path  FIX155: the launched build's full .vpx
##                    path, written by the launcher on the
##                    launch arm (before the spawn) and
##                    cleared at check-in. It is the B2S
##                    name feed on the resident road: the
##                    watchdog derives the table's file
##                    stem from it and holds the FIX154
##                    name window ("Visual Pinball -
##                    [<stem>]") while the session loads,
##                    so the B2S DLL's editor-title scrape
##                    finds the filename a separate-process
##                    launch otherwise never hands it.
##                    Absent in contracts written before
##                    the field existed: loads default ""
##                    and no window is raised. Schema v2.
##   game_pid         VPX process id once spawned (0 = not yet / none)
##   game_started_unix
##   game_window_seen_unix  stamped by the watchdog when the game's
##                    PLAYER window first exists (the watchdog's
##                    sighting rule - the editor frame is up from
##                    app start and must not stamp this); feeds the
##                    watchdog's exit-detector arming and the
##                    launcher's dead-process grace
##   runtime_seen_unix  stamped by the watchdog when the game's
##                    table RUNTIME first exists (the watchdog's
##                    runtime rule - the runtime windows the load
##                    brings up once the table is real); the
##                    resident launcher reads it (+ a short settle)
##                    as its hand-off cue. The sighting above stamps
##                    seconds earlier, off the editor's own canvas,
##                    while the load is still running - handing off
##                    on it left a desktop gap in the headset and
##                    an unsettled foreground, so the cue moved to
##                    the runtime. Absent in contracts written
##                    before the field existed; loads default 0.
##   b2s_present_since_unix  FIX149: WATCHDOG-owned: the unix
##                    second the B2S backglass server's
##                    CONTINUOUS presence began (the watchdog's
##                    sighting tracker), or 0 while the server
##                    is absent. The resident launcher reads it
##                    during its load wait: the hand-off exit is
##                    held until this presence has held 5
##                    seconds (the hand-off gate - the server
##                    was dying in the same breath as the
##                    launcher's exit, mid-Run()). The launcher
##                    never writes it, except to CLEAR it when
##                    a fresh session is armed (checkin /
##                    perform_launch), like the sighting stamps
##                    above. Schema stays v2.
##   b2s_seen_unix    FIX150: WATCHDOG-owned: the unix second
##                    the B2S server was FIRST sighted this
##                    session, or 0 if it has not been sighted
##                    yet. A latch: absence never resets it
##                    within the session (only a fresh arm
##                    clears it, with the stamps above). The
##                    gate reads it for the never-sighted early
##                    release - the continuous stamp alone
##                    reads 0 both for "never seen" and for
##                    "seen, then gone", and only the first
##                    may release early. The launcher never
##                    writes it, except to CLEAR it on a fresh
##                    arm. Schema stays v2.
##   spawn_pending    FIX152: the cold spawn's marker, written
##                    by the LAUNCHER: true when the armed
##                    "loading" session is a launch ORDER, not
##                    a launched game - the launcher has quit
##                    (or is quitting) without spawning, and
##                    the watchdog is to fire the spawn itself
##                    once the launcher is dead and a settle
##                    delay of quiet has passed (the field
##                    evidence: every dying launch overlapped
##                    the spawn with the app's own VR-session
##                    teardown; every living one had no
##                    teardown in flight). The watchdog clears
##                    it in the write that lands the game's
##                    pid. Absent in contracts written before
##                    the field existed: loads default false -
##                    the resident spawn, today's behaviour
##                    for those builds' sessions. Schema
##                    stays v2.
##   game_args        FIX152: the launch spec's argv - the
##                    plan's fully resolved argument list
##                    (template expanded, {table} already
##                    substituted), written by the launcher
##                    alongside spawn_pending so the watchdog
##                    can fire the cold spawn verbatim. The
##                    watchdog never writes it; a fresh arm
##                    without the marker clears it. Absent in
##                    older contracts: loads default empty.
##                    Schema stays v2.
##   game_cwd         FIX152: the launch spec's working
##                    directory (the VPX folder - the FIX143
##                    cwd, named in the contract so the
##                    watchdog's spawn uses exactly the
##                    directory the launcher would have).
##                    Written and cleared with game_args.
##                    Schema stays v2.
##   handoff_gate     FIX149/FIX150: the hand-off gate's word
##                    for the session, written by the
##                    LAUNCHER: "" only before the load wait
##                    starts, "armed" when the load wait
##                    starts (FIX150: the gate arms on EVERY
##                    launch - FIX149 keyed it on a .directb2s
##                    filename match, which failed in the
##                    field and the gate never engaged),
##                    "held" while the exit is being held for
##                    the B2S server, then the release word
##                    ("released-stable" / "released-
##                    nosighting" / "released-cap") stamped
##                    by mark_live in the save that marks the
##                    session live. The watchdog never writes
##                    it; it logs its transitions into its own
##                    log (the disarm_reason pattern), so a
##                    field log carries the gate's word beside
##                    the sighting lines. Cleared when a fresh
##                    session is armed. Schema stays v2.
##   (focus_locked_unix stood here in 1.1.25–1.1.26: the
##   focus sequence's lock stamp, the warp hold's cue. FIX138
##   removed the field with the warp - nothing consumed it
##   once the hold was gone. Contracts carrying the key still
##   load; it is ignored. Schema stays v2.)
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
## FIX118: the writing launcher's version, read from disk for
## completeness; to_dictionary() re-stamps it from AppInfo on
## every save (see the field note above).
var launcher_version: String = ""
var focus_herding: bool = true
## FIX117: the focus actuation controls, mirrored for the
## watchdog exactly like focus_herding (checkin/launch).
var focus_actuation_rung: int = 1
var focus_actuation_probe: bool = false
var pinemhi_manage: bool = false
var pinemhi_folder: String = ""
var pinemhi_watcher_pid: int = 0
var pinemhi_watcher_state: String = ""
var hold_exit_enabled: bool = true
var hold_exit_fired_unix: int = 0
var session_id: int = 0
var session_state: String = "idle"
var game_exe_path: String = ""
var game_table_path: String = ""
var game_pid: int = 0
var game_started_unix: int = 0
var game_window_seen_unix: int = 0
var runtime_seen_unix: int = 0
var b2s_present_since_unix: int = 0
var b2s_seen_unix: int = 0
var spawn_pending: bool = false
var game_args: Array[String] = []
var game_cwd: String = ""
var handoff_gate: String = ""
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
	c.launcher_version = str(d.get("launcher_version", ""))
	c.focus_herding = bool(d.get("focus_herding", true))
	c.focus_actuation_rung = int(d.get("focus_actuation_rung", 1))
	c.focus_actuation_probe = bool(d.get("focus_actuation_probe", false))
	c.pinemhi_manage = bool(d.get("pinemhi_manage", false))
	c.pinemhi_folder = str(d.get("pinemhi_folder", ""))
	c.pinemhi_watcher_pid = int(d.get("pinemhi_watcher_pid", 0))
	c.pinemhi_watcher_state = str(d.get("pinemhi_watcher_state", ""))
	c.hold_exit_enabled = bool(d.get("hold_exit_enabled", true))
	c.hold_exit_fired_unix = int(d.get("hold_exit_fired_unix", 0))
	c.session_id = int(d.get("session_id", 0))
	c.session_state = str(d.get("session_state", "idle"))
	c.session_state = WatchdogContract.normalize_state(c.session_state)
	c.game_exe_path = str(d.get("game_exe_path", ""))
	c.game_table_path = str(d.get("game_table_path", ""))
	c.game_pid = int(d.get("game_pid", 0))
	c.game_started_unix = int(d.get("game_started_unix", 0))
	c.game_window_seen_unix = int(d.get("game_window_seen_unix", 0))
	c.runtime_seen_unix = int(d.get("runtime_seen_unix", 0))
	c.b2s_present_since_unix = int(d.get("b2s_present_since_unix", 0))
	c.b2s_seen_unix = int(d.get("b2s_seen_unix", 0))
	c.spawn_pending = bool(d.get("spawn_pending", false))
	c.game_cwd = str(d.get("game_cwd", ""))
	c.game_args.clear()
	var ga: Variant = d.get("game_args", [])
	if ga is Array:
		var garr: Array = ga
		for item: Variant in garr:
			c.game_args.append(str(item))
	c.handoff_gate = str(d.get("handoff_gate", ""))
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
	# FIX118: stamped fresh from AppInfo on every save - the
	# watchdog's session header quotes the writing build.
	d["launcher_version"] = AppInfo.PRODUCT_VERSION
	d["focus_herding"] = focus_herding
	d["focus_actuation_rung"] = focus_actuation_rung
	d["focus_actuation_probe"] = focus_actuation_probe
	d["pinemhi_manage"] = pinemhi_manage
	d["pinemhi_folder"] = pinemhi_folder
	d["pinemhi_watcher_pid"] = pinemhi_watcher_pid
	d["pinemhi_watcher_state"] = pinemhi_watcher_state
	d["hold_exit_enabled"] = hold_exit_enabled
	d["hold_exit_fired_unix"] = hold_exit_fired_unix
	d["session_id"] = session_id
	d["session_state"] = session_state
	d["game_exe_path"] = game_exe_path
	d["game_table_path"] = game_table_path
	d["game_pid"] = game_pid
	d["game_started_unix"] = game_started_unix
	d["game_window_seen_unix"] = game_window_seen_unix
	d["runtime_seen_unix"] = runtime_seen_unix
	d["b2s_present_since_unix"] = b2s_present_since_unix
	d["b2s_seen_unix"] = b2s_seen_unix
	d["spawn_pending"] = spawn_pending
	var gargs: Array = []
	for a: String in game_args:
		gargs.append(a)
	d["game_args"] = gargs
	d["game_cwd"] = game_cwd
	d["handoff_gate"] = handoff_gate
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
