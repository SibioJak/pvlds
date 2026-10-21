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
##               contract, ensure the watchdog, spawn VPX detached.
##               The CALLER then quits the launcher completely:
##               absence is the fix (no resident mode, ever).
##   Exit        disarm() - the player who wants out stays out; the
##               watchdog reads armed=false and stands down.
##
## The watchdog is a separate tiny native process (watchdog/ in the
## repo). It is located beside the launcher executable first, then via
## the PVLDS_WATCHDOG_PATH environment override, then in the repo's
## watchdog/build/ for editor runs.

const WATCHDOG_EXE_BASE: String = "pvlds_watchdog"
const WATCHDOG_LOCK_NAME: String = "pvlds_watchdog.lock"


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
	for suffix: String in suffixes:
		var dev: String = dev_dir.path_join(WATCHDOG_EXE_BASE + suffix)
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
	c.focus_herding = config.focus_herding if config != null else true
	c.launcher_path = LaunchService.launcher_path()
	c.launcher_args = LaunchService.launcher_args()
	c.launcher_pid = OS.get_process_id()
	c.last_checkin_unix = int(Time.get_unix_time_from_system())
	if c.session_state == "playing" or c.session_state == "launching":
		c.session_state = "returned"
	c.game_pid = 0
	c.save_to_disk()
	ensure_watchdog()
	return c


## Play. On success (result["ok"]) the caller must quit the launcher
## immediately - VPX owns the machine now.
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
	c.focus_herding = config.focus_herding
	c.session_id += 1
	c.session_state = "launching"
	c.game_exe_path = plan.exe_path
	c.game_pid = 0
	c.game_started_unix = int(Time.get_unix_time_from_system())
	c.launcher_path = LaunchService.launcher_path()
	c.launcher_args = LaunchService.launcher_args()
	c.launcher_pid = OS.get_process_id()
	c.last_checkin_unix = int(Time.get_unix_time_from_system())
	c.save_to_disk()
	ensure_watchdog()
	var pid: int = OS.create_process(plan.exe_path, plan.args)
	if pid < 0:
		c.session_state = "idle"
		c.save_to_disk()
		return {"ok": false, "error": "Could not start %s" % plan.exe_path, "plan": plan}
	c.game_pid = pid
	c.session_state = "playing"
	c.save_to_disk()
	return {"ok": true, "error": "", "plan": plan, "pid": pid}


## Exit to desktop: disarm, then the caller quits. The watchdog sees
## armed=false on its next poll and stands down for good.
func disarm() -> void:
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	c.armed = false
	c.session_state = "idle"
	c.game_pid = 0
	c.save_to_disk()
