class_name LaunchService
extends RefCounted

## The hand-off choreographer (design section 3). UI-independent: the
## faces ask for a launch or an exit; this class does the contract,
## the state, the spawns, and nothing else.
##
## Choreography:
##   boot        checkin() - arm the contract, stamp the launcher's
##               identity, make sure a watchdog is on duty.
##   Play        perform_launch() - persist state, write the session
##               contract (state "loading"), ensure the watchdog,
##               spawn VPX THROUGH the watchdog binary's
##               supervised spawn mode (FIX143: VPX must run with
##               its own folder as its working directory - Godot's
##               OS.create_process cannot set a child's, and the
##               inherited one is FIX142's rank-1 suspect for
##               script-started B2S dying under our launches;
##               FIX148: the helper's birth itself is plain -
##               no detach flags, SDL variable scrubbed).
##               The launcher then STAYS RESIDENT
##               in the room while the table loads (M2 fix round: the
##               instant-exit choreography left the player staring
##               at a desktop/void for VPX's whole ~20s load; the
##               competing launcher keeps its room up, and so do we).
##               The caller watches for the hand-off point and then
##               calls mark_live() and quits completely - absence
##               during PLAY is still the fix; only the load is
##               covered. If VPX dies during the load, the caller
##               calls fail_launch() and stays in the room.
##   Exit        disarm(reason) - the player who wants out stays
##               out; the watchdog reads armed=false and stands
##               down. Every caller names itself in the reason: a
##               silent disarm once dismissed whole sessions from
##               under a loading table, and the log line that finally
##               caught it could only say "player Exit".
##
## The watchdog is a separate tiny native process (watchdog/ in the
## repo). It is located beside the launcher executable first, then via
## the PVLDS_WATCHDOG_PATH environment override, then in the repo's
## watchdog/build/ for editor runs.

## RENAMES (1.1.1): the shipped watchdog carries the product
## name now - LaunchPinWatchdog.exe beside LaunchPin.exe. The
## dev-tree fallback in resolve_watchdog_path() still accepts
## the old build name inside watchdog/build/ (the Go build's
## output name is internal and unchanged).
const WATCHDOG_EXE_BASE: String = "LaunchPinWatchdog"
const WATCHDOG_DEV_EXE_BASE: String = "pvlds_watchdog"
const WATCHDOG_LOCK_NAME: String = "pvlds_watchdog.lock"
## FIX143: the watchdog binary's one-shot spawn mode word
## (watchdog/spawn_mode.go) - argv[1] where a normal run
## carries the contract path.
const SPAWN_MODE_ARG: String = "pvlds-spawn"


static func watchdog_lock_path_absolute() -> String:
	return WatchdogContract.contract_dir_absolute().path_join(WATCHDOG_LOCK_NAME)


static func launcher_path() -> String:
	return OS.get_executable_path()


static func launcher_args() -> Array[String]:
	var args: Array[String] = []
	if OS.has_feature("editor"):
		# Editor runs: relaunching reopens the project in the editor.
		# (The real hand-off is exercised by the exported build, whose
		# executable path needs no arguments at all.)
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	return args


static func resolve_watchdog_path() -> String:
	if OS.has_environment("PVLDS_WATCHDOG_PATH"):
		var env_path: String = OS.get_environment("PVLDS_WATCHDOG_PATH")
		if env_path != "" and FileAccess.file_exists(env_path):
			return env_path
	# Suffix order is platform-first: on Linux the Windows .exe also
	# sits in watchdog/build, and exec'ing it "succeeds" as a shell
	# script that dies on the MZ header (seen in the M2 boot smoke).
	# (Built with appends, not a ternary of literals - the ternary's
	# untyped Array cannot land in an Array[String].)
	var suffixes: Array[String] = []
	if OS.has_feature("windows"):
		suffixes.append(".exe")
		suffixes.append("")
	else:
		suffixes.append("")
		suffixes.append(".exe")
	var beside_dir: String = OS.get_executable_path().get_base_dir()
	for suffix: String in suffixes:
		var beside: String = beside_dir.path_join(WATCHDOG_EXE_BASE + suffix)
		if FileAccess.file_exists(beside):
			return beside
	var dev_dir: String = ProjectSettings.globalize_path("res://watchdog/build")
	# The dev tree holds the Go build under its own name (and
	# a staged copy under the shipped name, when one exists):
	# try the shipped name first, then the build's.
	for base: String in [WATCHDOG_EXE_BASE, WATCHDOG_DEV_EXE_BASE]:
		for suffix: String in suffixes:
			var dev: String = dev_dir.path_join(base + suffix)
			if FileAccess.file_exists(dev):
				return dev
	return ""


## The watchdog writes its own pid into the lock file when it starts;
## a lock whose pid is dead is stale and safe to replace.
static func is_watchdog_running() -> bool:
	var lock_abs: String = LaunchService.watchdog_lock_path_absolute()
	if not FileAccess.file_exists(lock_abs):
		return false
	var pid: int = FileAccess.get_file_as_string(lock_abs).strip_edges().to_int()
	if pid <= 0:
		return false
	return OS.is_process_running(pid)


func spawn_watchdog() -> int:
	var exe: String = LaunchService.resolve_watchdog_path()
	if exe == "":
		push_warning("PVLDS: watchdog executable not found; hand-off return will not be watched.")
		return -1
	var args: Array[String] = [WatchdogContract.contract_path_absolute()]
	return OS.create_process(exe, args)


## FIX143: the working directory a game spawn must carry -
## the VPX exe's own folder, the directory a plain VPX launch
## runs from. Pure; the fix143 smoke asserts the spawned
## child observes exactly this directory.
static func game_working_dir(exe_path: String) -> String:
	return exe_path.get_base_dir()


## The pid file the FIX143 spawn helper writes the game's
## pid into (beside the contract; the helper is told the path
## on its command line). Deleted before every spawn and read
## once - it is a per-launch fact, never a standing record.
const SPAWN_PID_FILE_NAME: String = "pvlds_spawn_pid.txt"
## How long perform_launch waits for the helper to report
## the game's pid. A healthy start reports in well under a
## second; the bound exists so a wedged helper fails the
## launch in words instead of hanging the Play press.
const SPAWN_REPORT_TIMEOUT_MSEC: int = 10000


static func spawn_pid_path_absolute() -> String:
	return WatchdogContract.contract_dir_absolute().path_join(SPAWN_PID_FILE_NAME)


## FIX143: spawn the game so it runs with game_working_dir()
## as its working directory. The spawn is assisted by the
## watchdog binary's spawn mode (watchdog/spawn_mode.go):
## its supervised start leaf starts VPX inside the VPX
## folder - and the helper then SUPERVISES, living exactly
## as long as the game does.
##
## Why the supervision: Main's load wait judges the load by
## OS.is_process_running on the pid perform_launch returns,
## and Godot's is_process_running only believes the
## launcher's OWN children - a live foreign pid reads dead
## (bench-convicted in this round: a spawn-and-exit helper
## left the load wait calling a live VPX dead inside its
## grace). So this returns TWO pids:
##   pid       the helper's - a true child of the launcher,
##             alive exactly while the game is. Main's load
##             wait reads it, as it read the game's before.
##   game_pid  the game's own, reported by the helper
##             through the pid file and polled for here (a
##             healthy start reports in well under a second).
##             perform_launch writes it into the contract,
##             where the resident watchdog's duties aim.
## A helper that dies without reporting, or never reports,
## fails the launch with the reason - like the old pid<0.
##
## Fallbacks, both loud: no watchdog exe resolves -> the
## plain OS.create_process spawn (the pre-FIX143 shape, cwd
## inherited; both pids the game's) with a warning, so a
## missing helper degrades to yesterday's behaviour instead
## of a dead Play button.
##
## NC seam: PVLDS_FIX143_NC=inherited forces the plain spawn
## (the pre-fix shape); the fix143 smoke's cwd leg must fail
## by name under it.
##
## FIX148: the helper's side of the spawn is now the plain
## recipe on every axis (watchdog/spawn_mode.go): no detach
## flags, and the game's environment scrubbed of the SDL
## variable the launcher sets for itself. The FIX145 diag
## seams are gone - nothing on either side consults
## pvlds_diag.txt any more, and this helper road is the one
## and only product spawn shape (the fix148 smoke pins it,
## diag file present and hostile included).
static func spawn_game(plan: LaunchPlan) -> Dictionary:
	if OS.get_environment("PVLDS_FIX143_NC") == "inherited":
		var nc_pid: int = OS.create_process(plan.exe_path, plan.args)
		if nc_pid < 0:
			return {"pid": -1, "game_pid": -1, "error": "the spawn returned no pid"}
		return {"pid": nc_pid, "game_pid": nc_pid, "error": ""}
	var helper: String = LaunchService.resolve_watchdog_path()
	if helper == "":
		push_warning("PVLDS: watchdog executable not found; spawning VPX without the working-directory fix (FIX143).")
		var plain_pid: int = OS.create_process(plan.exe_path, plan.args)
		if plain_pid < 0:
			return {"pid": -1, "game_pid": -1, "error": "the spawn returned no pid"}
		return {"pid": plain_pid, "game_pid": plain_pid, "error": ""}
	var pid_path: String = LaunchService.spawn_pid_path_absolute()
	if FileAccess.file_exists(pid_path):
		DirAccess.remove_absolute(pid_path)
	var shim_args: Array[String] = [SPAWN_MODE_ARG, LaunchService.game_working_dir(plan.exe_path), pid_path, plan.exe_path]
	shim_args.append_array(plan.args)
	var shim_pid: int = OS.create_process(helper, shim_args)
	if shim_pid < 0:
		return {"pid": -1, "game_pid": -1, "error": "the spawn helper could not be started"}
	var waited: int = 0
	while waited < SPAWN_REPORT_TIMEOUT_MSEC:
		if FileAccess.file_exists(pid_path):
			var game_pid: int = FileAccess.get_file_as_string(pid_path).strip_edges().to_int()
			if game_pid > 0:
				DirAccess.remove_absolute(pid_path)
				return {"pid": shim_pid, "game_pid": game_pid, "error": ""}
		if not OS.is_process_running(shim_pid):
			return {"pid": -1, "game_pid": -1, "error": "the spawn helper exited without starting the game"}
		OS.delay_msec(25)
		waited += 25
	OS.kill(shim_pid)
	return {"pid": -1, "game_pid": -1, "error": "the spawn helper never reported the game's pid"}


## Make sure a watchdog is on duty; returns true when one is running
## (already, or freshly spawned). When one is already running we do
## NOT spawn a twin - it polls the contract file, so the fresh
## contract written by checkin()/perform_launch() IS the hand-over.
func ensure_watchdog() -> bool:
	if LaunchService.is_watchdog_running():
		return true
	return spawn_watchdog() > 0


## Boot duty. A launcher boot is a fresh intent to play, so the
## contract is (re)armed - Exit is the only disarm, and it quits the
## app in the same breath; the next manual boot re-arms. A boot that
## finds a live session in the contract is the watchdog's relaunch:
## the session is consumed (state restore reads StateStore, not the
## contract), the watch goes back to idle.
func checkin(config: PvldsConfig) -> WatchdogContract:
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	c.armed = true
	c.disarm_reason = "" ## a fresh arm buries the last dismissal's reason
	c.focus_herding = config.focus_herding
	# FIX117: mirror the focus actuation controls the same way.
	c.focus_actuation_rung = config.focus_actuation_rung
	c.focus_actuation_probe = config.focus_actuation_probe
	# PINEMHI2 (Part B): mirror the watcher-management toggle +
	# the resolved folder for the watchdog. The watchdog-owned
	# pid/state are NOT touched here - they loaded from disk
	# with the contract and save back out as they were.
	c.pinemhi_manage = config.pinemhi_manage_watcher if config != null else false
	c.pinemhi_folder = PinemhiScores.resolve_folder(config) if config != null else ""
	# HOLD-EXIT: mirror the hold toggle the same way, and bury
	# the last session's fired stamp - a fresh arm starts clean.
	c.hold_exit_enabled = config.hold_exit_enabled if config != null else true
	c.hold_exit_fired_unix = 0
	c.launcher_path = LaunchService.launcher_path()
	c.launcher_args = LaunchService.launcher_args()
	c.launcher_pid = OS.get_process_id()
	c.last_checkin_unix = int(Time.get_unix_time_from_system())
	if c.session_state == "loading" or c.session_state == "live" or c.session_state == "failed":
		c.session_state = "returned"
	c.game_pid = 0
	c.game_window_seen_unix = 0
	c.runtime_seen_unix = 0
	# FIX149: a fresh arm buries the last session's B2S
	# presence stamp and gate verdict with the sightings.
	# FIX150: the latching seen stamp is buried with them.
	c.b2s_present_since_unix = 0
	c.b2s_seen_unix = 0
	c.handoff_gate = ""
	# FIX155: a boot consumes whatever session stood in
	# the contract - the consumed session's name feed
	# goes with it (a boot never inherits a table name).
	c.game_table_path = ""
	c.save_to_disk()
	ensure_watchdog()
	return c


## Play. On success (result["ok"]) VPX is spawned and loading; the
## session is in the "loading" state and the launcher stays resident
## until the hand-off (mark_live) or the failure (fail_launch).
## (FIX152's cold spawn - the contract as a launch order the
## watchdog fired after the launcher quit - was removed in
## FIX155: the direct spawn below is the only road again, and
## the B2S name feed rides the arm as game_table_path.)
func perform_launch(config: PvldsConfig, state: StateStore, game: GameEntry, build: TableBuild) -> Dictionary:
	var plan: LaunchPlan = LaunchPlan.build_plan(config, game, build)
	if not plan.valid:
		return {"ok": false, "error": plan.error, "plan": plan}
	if not FileAccess.file_exists(plan.exe_path):
		return {"ok": false, "error": "VPX executable not found: %s" % plan.exe_path, "plan": plan}
	# State first: if anything below fails, the player still lands
	# back at the table they tried to play.
	state.touch_recent(game.game_id)
	state.set_last_played(game.game_id, build.file_path)
	state.save_to_disk()
	# The session contract, written BEFORE the spawn: if VPX dies
	# instantly, the watchdog still knows a session existed.
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	c.armed = true
	c.disarm_reason = ""
	c.focus_herding = config.focus_herding
	# FIX117: the actuation mirror, same as checkin.
	c.focus_actuation_rung = config.focus_actuation_rung
	c.focus_actuation_probe = config.focus_actuation_probe
	# PINEMHI2 (Part B): the same mirror as checkin (the
	# watchdog-owned pid/state ride through untouched).
	c.pinemhi_manage = config.pinemhi_manage_watcher
	c.pinemhi_folder = PinemhiScores.resolve_folder(config)
	# HOLD-EXIT: the same mirror + a clean fired stamp for the
	# new session (checkin above does the same at boot).
	c.hold_exit_enabled = config.hold_exit_enabled
	c.hold_exit_fired_unix = 0
	c.session_id += 1
	c.session_state = "loading"
	c.game_exe_path = plan.exe_path
	# FIX155: the B2S name feed rides every arm - the
	# launched table's path, from which the watchdog
	# derives the stem for its name window (the contract
	# is saved below, before the spawn, so the window is
	# up before VPX's script initialises).
	c.game_table_path = plan.table_path
	c.game_pid = 0
	c.game_window_seen_unix = 0
	c.runtime_seen_unix = 0
	# FIX149: the new session starts with no B2S presence
	# and no gate verdict; the watchdog's sighting stamps
	# the presence when (and if) the server comes up.
	# FIX150: the seen latch starts unlatched too.
	c.b2s_present_since_unix = 0
	c.b2s_seen_unix = 0
	c.handoff_gate = ""
	c.game_started_unix = int(Time.get_unix_time_from_system())
	c.launcher_path = LaunchService.launcher_path()
	c.launcher_args = LaunchService.launcher_args()
	c.launcher_pid = OS.get_process_id()
	c.last_checkin_unix = int(Time.get_unix_time_from_system())
	c.save_to_disk()
	ensure_watchdog()
	# FIX143: the assisted spawn - VPX runs with its own
	# folder as its working directory (spawn_game above).
	# The contract takes the GAME's pid (the watchdog's
	# duties aim at it); the returned "pid" is the spawn
	# helper's - the child Main's load wait watches, alive
	# exactly while the game is.
	var spawned: Dictionary = LaunchService.spawn_game(plan)
	var pid: int = int(spawned.get("pid", -1))
	if pid < 0:
		c.session_state = "idle"
		c.save_to_disk()
		var why: String = str(spawned.get("error", ""))
		var err: String = "Could not start %s" % plan.exe_path
		if why != "":
			err += " (%s)" % why
		return {"ok": false, "error": err, "plan": plan}
	c.game_pid = int(spawned.get("game_pid", pid))
	c.save_to_disk()
	return {"ok": true, "error": "", "plan": plan, "pid": pid, "session_id": c.session_id}


## FIX149/FIX150: record the hand-off gate's standing word
## for the loading session ("armed" when Main's load wait
## starts - the gate arms on every launch - then "held"
## while the wait holds the exit). The watchdog logs the
## word's transitions into its own log; the release word
## rides mark_live's save instead (below), so the verdict
## and the state change land in one write. A session that
## is no longer loading takes no word.
func stamp_handoff_gate(word: String) -> void:
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	if c.session_state == "loading" and c.handoff_gate != word:
		c.handoff_gate = word
		c.save_to_disk()


## The hand-off point: the table is up and the launcher is about to
## exit. From here the watchdog's live rule owns the session - when
## VPX dies, it relaunches the launcher exactly once. FIX149: a
## gate verdict is stamped in the same save, so the watchdog's
## log can carry the release word beside the state change it
## rode in on. FIX150: the gate arms on every launch, so a
## success settle always carries a release word.
func mark_live(gate_verdict: String = "") -> void:
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	if c.session_state == "loading":
		c.session_state = "live"
		if gate_verdict != "":
			c.handoff_gate = gate_verdict
		c.save_to_disk()


## VPX died while it was still loading and the launcher is resident
## to say so. Terminal for this session: the watchdog reads "failed"
## as inactive and never relaunches for it.
func fail_launch() -> void:
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	if c.session_state == "loading":
		c.session_state = "failed"
		c.game_pid = 0
		c.save_to_disk()


## Exit to desktop: disarm, then the caller quits. The watchdog sees
## armed=false on its next poll and stands down for good. The caller
## names itself in `reason`; the name is printed here, written into
## the contract, and read back out by the watchdog's stand-down log
## line, so a dismissal always confesses who ordered it.
func disarm(reason: String) -> void:
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	c.armed = false
	c.disarm_reason = reason
	c.session_state = "idle"
	c.game_pid = 0
	c.save_to_disk()
	print("PVLDS DISARM: ", reason)
