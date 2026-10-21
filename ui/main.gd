extends Node

## PVLDS entry point. Owns the pieces both faces share - config, state,
## database, scanner, texture factory - and routes between the two:
## the first-run desk pass (2D) and the room (3D / XR). Owns the M2
## hand-off endpoints too: LaunchService checkin on boot, the launch
## load wait + full exit at the hand-off point, disarm on Exit /
## window close.
##
## The load wait (M2 fix round): on Play the launcher no longer
## vanishes the instant VPX spawns. It stays in the room - panel
## showing LOADING - until the hand-off point: the watchdog reports
## VPX's main window up (+ a short settle), or the XR session starts
## changing hands, or a 45s cap passes. Only then does it mark the
## session "live" and exit completely. If VPX dies during the load,
## the session fails in place and browsing resumes.
##
## Dev hooks (user args, after "--"):
##   --pvlds-core-test   run the UI-free library test suite, print, quit
##   --pvlds-seed-dummy  boot straight into the room on the dummy library
##   --setup             force the desk pass even when configured
##   --pvlds-db-stats P  load the database at P, print counts, quit
##   --pvlds-shot P      boot, save a screenshot of wherever the boot
##                       lands (room once its textures settle, or the
##                       desk once a scan lands on it) to P, quit
##   --pvlds-smoke-launch GID
##                       seeded-dummy boot; when the scan lands, launch
##                       game GID's default build via LaunchService
##                       (config exe from env PVLDS_SMOKE_EXE, args
##                       template from PVLDS_SMOKE_ARGS), ride the
##                       real load wait, print the verdict, exit
##   --pvlds-shot-launch P
##                       seeded-dummy boot; once the room's wall is
##                       ready, launch a game (env overrides as
##                       above), screenshot the LOADING room to P
##                       ~1s into the wait, disarm, quit

var _config: PvldsConfig
var _state: StateStore
var _db: VpsDatabase
var _scanner: LibraryScanner
var _factory: TextureFactory
var _room: RoomView = null
var _desk: SetupDesk = null
var _xr_interface: XRInterface
var _xr_enabled: bool = false
var _xr_tried: bool = false
var _launch_service: LaunchService = null
var _intentional_launch_exit: bool = false ## quitting FOR a launch must not disarm the watchdog
var _smoke_launch_game: String = ""
var _smoke_verdict_pending: bool = false ## a smoke launch is riding the load wait; its settle prints the verdict and quits
var _shot_launch_path: String = ""
var _shot_launch_fired: bool = false
var _shot_launch_at_msec: int = 0

# The launch load wait. While _launch_pending, _process polls for
# the hand-off point and for VPX dying mid-load.
const LAUNCH_SETTLE_MSEC: int = 1500 ## window up + this long = hand off
const LAUNCH_CAP_MSEC: int = 45000 ## never hold the room hostage to a stuck load
const LAUNCH_DEAD_GRACE_MSEC: int = 1500 ## a dead spawn pid gets this long for the watchdog's by-path window report before the launch is called failed
var _launch_pending: bool = false
var _launch_game: GameEntry = null
var _launch_pid: int = 0
var _launch_session_id: int = 0
var _launch_started_msec: int = 0
var _launch_window_seen_msec: int = -1
var _launch_pid_dead_msec: int = -1
var _xr_session_ending: bool = false ## latched by the OpenXR session_ending signal when present

# Scan machinery. The scan (db load + folder walk + matching) runs on a
# WorkerThreadPool task - NEVER on the main thread, in any route. A
# real library scan takes seconds to minutes; run synchronously it
# froze the desk pass on Chris's first Save & Scan and froze the boot
# before the first frame once his config existed. The worker writes
# only _worker_* members and the ScanProgress counters; the main
# thread adopts the results after wait_for_task_completion().
var _scan_progress: ScanProgress = null
var _scan_task_id: int = -1
var _scan_active: bool = false
var _scan_folders: Array[String] = []
var _enter_room_after_scan: bool = false
var _seeded_dummy: bool = false ## --pvlds-seed-dummy route: sample db + dummy folders, deliberately
var _worker_db: VpsDatabase = null
var _worker_db_ok: bool = false
var _worker_db_path: String = ""
var _worker_db_kind: String = ""
var _worker_scanner: LibraryScanner = null
var _last_db_ok: bool = false
var _last_db_path: String = ""
var _last_db_kind: String = ""
var _scan_db_path: String = "" ## resolved on the main thread in start_scan()
var _scan_db_kind: String = "" ## "user" | "download" | "sample"
var _shot_path: String = ""
var _shot_frames: int = 0


func _ready() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.has("--pvlds-core-test"):
		_run_core_test()
		return
	var stats_idx: int = user_args.find("--pvlds-db-stats")
	if stats_idx >= 0 and stats_idx + 1 < user_args.size():
		_run_db_stats(user_args[stats_idx + 1])
		return
	var shot_idx: int = user_args.find("--pvlds-shot")
	if shot_idx >= 0 and shot_idx + 1 < user_args.size():
		_shot_path = user_args[shot_idx + 1]
	var smoke_idx: int = user_args.find("--pvlds-smoke-launch")
	if smoke_idx >= 0 and smoke_idx + 1 < user_args.size():
		_smoke_launch_game = user_args[smoke_idx + 1]
	var shot_launch_idx: int = user_args.find("--pvlds-shot-launch")
	if shot_launch_idx >= 0 and shot_launch_idx + 1 < user_args.size():
		_shot_launch_path = user_args[shot_launch_idx + 1]
	# NOTE: no XR here. Desk work never touches OpenXR - initializing
	# it at boot is what popped the "OpenXR was requested but failed
	# to start" alert on flat launches with no runtime up (M2 papercut
	# fix). XR initializes lazily in _enter_room via _ensure_xr().
	_factory = TextureFactory.new()
	add_child(_factory)
	_config = PvldsConfig.new()
	_state = StateStore.new()
	_state.load_from_disk()
	var configured: bool = _config.load_from_disk()
	if user_args.has("--pvlds-seed-dummy"):
		_seeded_dummy = true
		_seed_dummy_config()
		configured = true
	elif _smoke_launch_game != "" and not configured:
		# The smoke hook prefers a real installed config (its whole
		# point is integrating against one); seeding is only the
		# fallback. Seeding over a real config also breaks in exports,
		# where the seed's globalized res:// paths name no real files.
		_seeded_dummy = true
		_seed_dummy_config()
		configured = true
	if _smoke_launch_game != "" or _shot_launch_path != "":
		if OS.has_environment("PVLDS_SMOKE_EXE"):
			_config.vpx_exe_path = OS.get_environment("PVLDS_SMOKE_EXE")
		if OS.has_environment("PVLDS_SMOKE_ARGS"):
			_config.launch_args_template = OS.get_environment("PVLDS_SMOKE_ARGS")
	# M2 boot duty: check in with the watchdog contract and make sure
	# a watchdog is on duty (design section 3, step 1). A watchdog
	# relaunch of this very process lands here too - checkin consumes
	# the finished session; state restore does the rest.
	_launch_service = LaunchService.new()
	_launch_service.checkin(_config)
	if configured and _config.is_configured() and not user_args.has("--setup"):
		# Configured boot: present the desk as a live shell immediately
		# (first frame, progress ticking) and enter the room only when
		# the threaded scan lands. No scan runs before the first frame.
		# One exception: a scan that resolves to the bundled sample
		# database never auto-enters the room (see _finish_scan).
		_show_desk()
		_enter_room_after_scan = true
		if not start_scan():
			_enter_room_after_scan = false
	else:
		_show_desk()


## Lazy XR init: called only when the room is entered. If no runtime
## answers, the room runs flat (desk testing) and nothing has popped
## an alert - project.godot also sets xr/openxr/startup_alert=false
## so a failed initialize stays silent.
func _ensure_xr() -> void:
	if _xr_tried:
		return
	_xr_tried = true
	_xr_interface = XRServer.find_interface("OpenXR")
	if _xr_interface != null and _xr_interface.is_initialized():
		get_viewport().use_xr = true
		_xr_enabled = true
		# The launch load wait listens for the session changing hands:
		# VPX initializing its own session is the cleanest hand-off cue
		# there is. Guarded - a runtime without the signal just never
		# latches it, and the window/cap cues carry the wait.
		if _xr_interface.has_signal("session_ending"):
			_xr_interface.session_ending.connect(func() -> void: _xr_session_ending = true)
	else:
		get_viewport().use_xr = false


## True when our OpenXR session is on its way out (STOPPING or
## worse). Best-effort by construction: no interface, no method, or
## a flat run all answer false, and the other hand-off cues decide.
func _xr_session_exiting() -> bool:
	if _xr_session_ending:
		return true
	if _xr_interface != null and _xr_interface.has_method("get_session_state"):
		var s: int = int(_xr_interface.call("get_session_state"))
		return s >= 6 ## OpenXRInterface.SessionState: STOPPING=6, LOSS_PENDING=7, EXITING=8
	return false


func _seed_dummy_config() -> void:
	_config.vpx_exe_path = PvldsConfig.DEFAULT_EXE_NAME
	_config.launch_args_template = PvldsConfig.DEFAULT_LAUNCH_ARGS
	_config.vpsdb_path = ProjectSettings.globalize_path("res://data/vpsdb.json")
	_config.table_folders.clear()
	_config.table_folders.append(ProjectSettings.globalize_path("res://dummy_data/tables"))


## Starts the library scan on a worker thread. Returns false when a
## scan is already running or there is nothing to scan. Progress is
## painted by _process() polling the ScanProgress counters; results
## land in _finish_scan().
func start_scan() -> bool:
	if _scan_active:
		return false
	if _config == null or _config.table_folders.is_empty():
		return false
	_scan_folders.clear()
	for f: String in _config.table_folders:
		_scan_folders.append(f)
	# Database selection happens here, on the main thread: the user's
	# own path, else the downloaded VPS cache, else the bundled sample.
	var resolved: Array = VpsDatabase.resolve_path(_config.vpsdb_path)
	_scan_db_path = str(resolved[0])
	_scan_db_kind = str(resolved[1])
	_scan_progress = ScanProgress.new()
	_scan_progress.begin("loading_db", _scan_folders.size())
	_scan_active = true
	_scan_task_id = WorkerThreadPool.add_task(Callable(self, "_scan_worker"), false, "PVLDS library scan")
	return true


## Worker-thread body: db load + scan. Touches only _worker_* members,
## the snapshotted _scan_folders, and the thread-safe _scan_progress.
func _scan_worker() -> void:
	var db: VpsDatabase = VpsDatabase.new()
	var db_ok: bool = db.load_db(_scan_db_path)
	var scanner: LibraryScanner = LibraryScanner.new()
	scanner.scan(_scan_folders, db, _scan_progress)
	_worker_db = db
	_worker_db_ok = db_ok
	_worker_db_path = _scan_db_path
	_worker_db_kind = _scan_db_kind
	_worker_scanner = scanner


func _process(_delta: float) -> void:
	_poll_launch()
	if _shot_path != "" and _shot_ready():
		_shot_frames += 1
		if _shot_frames >= 8:
			var shot_path: String = _shot_path
			_shot_path = ""
			var img: Image = get_viewport().get_texture().get_image()
			var err: Error = img.save_png(shot_path)
			print("PVLDS SHOT: ", shot_path, " err=", err, " size=", img.get_size())
			get_tree().quit(0 if err == OK else 1)
			return
	if not _scan_active:
		return
	if _desk != null and _desk.visible:
		_desk.set_scan_progress(_scan_progress_text())
	if _scan_task_id >= 0 and WorkerThreadPool.is_task_completed(_scan_task_id):
		WorkerThreadPool.wait_for_task_completion(_scan_task_id)
		_scan_task_id = -1
		_scan_active = false
		_finish_scan()


## Dev-hook readiness for --pvlds-shot: the room once its wall
## textures settle, or the desk once a scan has landed on it
## (a sample-blocked boot ends on the desk - that is worth a picture).
func _shot_ready() -> bool:
	if _room != null and _room.visible and _room.wall_ready:
		return true
	if _desk != null and _desk.visible and not _scan_active and _scanner != null:
		return true
	return false


func _scan_progress_text() -> String:
	if _scan_progress == null:
		return "Scanning..."
	var s: Dictionary = _scan_progress.snapshot()
	var phase: String = str(s["phase"])
	if phase == "loading_db":
		return "Scanning... loading the VPS database."
	if phase == "collecting":
		return "Scanning... folder %d of %d, %d table files found so far." % [
			int(s["folders_done"]), int(s["folders_total"]), int(s["files_found"])]
	if phase == "matching":
		return "Scanning... identifying tables, %d of %d files." % [
			int(s["files_processed"]), int(s["files_found"])]
	return "Scanning..."


## Main thread, once the worker lands: adopt results, publish the
## summary to the desk, and enter the room if a route is waiting on it.
func _finish_scan() -> void:
	_db = _worker_db
	_scanner = _worker_scanner
	_last_db_ok = _worker_db_ok
	_last_db_path = _worker_db_path
	_last_db_kind = _worker_db_kind
	var summary: String = build_scan_summary()
	if _desk != null:
		_desk.apply_scan_summary(summary)
	if _smoke_launch_game != "":
		var gid: String = _smoke_launch_game
		_smoke_launch_game = ""
		_smoke_launch(gid)
		return
	if _enter_room_after_scan:
		_enter_room_after_scan = false
		if _last_db_kind == "sample" and not _seeded_dummy:
			# Sample data must never usher anyone into the room: the
			# room would be built on 10 invented games, and the remedy
			# (Download VPS database) lives on this desk. The summary
			# applied above already carries the loud sample warning;
			# stay here so the user actually sees it.
			_show_desk()
			return
		_enter_room()


## Human-readable summary of the last completed scan, for the desk pass.
func build_scan_summary() -> String:
	if _scanner == null:
		return ""
	var s: LibraryScanner = _scanner
	var lines: Array[String] = []
	if _last_db_kind == "sample":
		lines.append("!! SAMPLE DATABASE ACTIVE !!")
		lines.append("The bundled database is 10 invented games that exist to test PVLDS itself - it cannot identify real tables. Use 'Download VPS database' above to fetch the real VPS database; until then tables are identified from file names only (no VR tags, designers, or known builds).")
		lines.append("The room stays closed until a real database is in place - download it above, then Save & Scan.")
	lines.append("Scanned %d table files in %d folder(s): %d games (%d with multiple builds)." % [
		s.total_files, _config.table_folders.size(), s.games.size(), s.duplicate_group_count()])
	if _last_db_ok:
		lines.append("Database (%s): %d games known. Matched %d of %d builds exactly; %d more by game only." % [
			_last_db_path, _db.game_count(), s.matched_files, s.total_files, s.game_matched_files])
	else:
		lines.append("No database loaded - every game is identified from its file name alone.")
	lines.append("Panel art: %d of %d games have art (side image or backglass); the rest get title cards." % [
		s.art_covered_games, s.games.size()])
	var unknown: Array[String] = []
	for g: GameEntry in s.games:
		if g.game_id.begins_with("local:"):
			unknown.append(g.title)
	if unknown.is_empty():
		lines.append("Every game was identified.")
	else:
		lines.append("Not in the database (title read from the file name): %s." % ", ".join(unknown))
	return "\n".join(lines)


func _enter_room() -> void:
	if _scanner == null:
		# No results yet: queue the room behind the threaded scan
		# instead of scanning inline (that was the boot-freeze bug).
		_enter_room_after_scan = true
		start_scan()
		return
	if _desk != null:
		_desk.visible = false
	_ensure_xr()
	if _room == null:
		_room = RoomView.new()
		add_child(_room)
		_room.setup(_factory, _scanner, _state, _xr_enabled)
		_room.setup_requested.connect(_show_desk)
		_room.launch_requested.connect(_on_launch_requested)
		_room.exit_requested.connect(_on_exit_requested)
	else:
		_room.refresh_library()
	_room.visible = true


# ------------------------------------------------------- the hand-off

## Play, from the card's Launch button or the detail view. A good
## spawn starts the load wait: the launcher stays in the room (the
## panel says LOADING) until _poll_launch calls the hand-off. A bad
## spawn (bad exe path, dead template) is desk work - the player is
## sent there with the reason, as before.
func _on_launch_requested(game: GameEntry, build: TableBuild) -> void:
	if _launch_service == null or game == null or build == null:
		return
	if _launch_pending:
		return ## one load at a time; the room's buttons are dead too
	var result: Dictionary = _launch_service.perform_launch(_config, _state, game, build)
	if bool(result["ok"]):
		_launch_pending = true
		_launch_game = game
		_launch_pid = int(result.get("pid", -1))
		_launch_session_id = int(result.get("session_id", 0))
		_launch_started_msec = Time.get_ticks_msec()
		_launch_window_seen_msec = -1
		_launch_pid_dead_msec = -1
		print("PVLDS LAUNCH: %s -> build %s (pid %d); staying in the room while it loads" % [
			game.title, build.file_name, _launch_pid])
		if _room != null:
			_room.begin_launch(game)
	elif _smoke_verdict_pending:
		printerr("PVLDS SMOKE LAUNCH: FAIL - ", str(result["error"]))
		get_tree().quit(1)
	else:
		var msg: String = "Launch failed: %s" % str(result["error"])
		printerr("PVLDS LAUNCH: ", msg)
		_show_desk()
		if _desk != null:
			_desk.show_message(msg + " Fix the setup here, then re-enter the room.")


## The load wait's poll (every frame; the checks are cheap and the
## contract file is small). Hand-off cues, in the order they are
## judged: VPX dying mid-load (failure - unless the watchdog has
## already reported the game's window by exe path, in which case the
## spawn pid simply was not the whole story), the XR session
## changing hands, the watchdog's window report + settle, the cap.
func _poll_launch() -> void:
	if _shot_launch_path != "":
		_poll_shot_launch()
		return
	if not _launch_pending:
		return
	var now: int = Time.get_ticks_msec()
	var pid_alive: bool = _launch_pid > 0 and OS.is_process_running(_launch_pid)
	if not pid_alive:
		if _launch_pid_dead_msec < 0:
			_launch_pid_dead_msec = now
		if now - _launch_pid_dead_msec >= LAUNCH_DEAD_GRACE_MSEC:
			var seen: WatchdogContract = WatchdogContract.load_from_disk()
			if not (seen.session_id == _launch_session_id and seen.game_window_seen_unix > 0):
				_settle_launch(false, "VPX closed while the table was loading")
				return
	if _xr_enabled and _xr_session_exiting():
		_settle_launch(true, "the XR session changed hands")
		return
	var contract: WatchdogContract = WatchdogContract.load_from_disk()
	if contract.session_id == _launch_session_id and contract.game_window_seen_unix > 0:
		if _launch_window_seen_msec < 0:
			_launch_window_seen_msec = now
		elif now - _launch_window_seen_msec >= LAUNCH_SETTLE_MSEC:
			_settle_launch(true, "VPX's window is up")
			return
	if now - _launch_started_msec >= LAUNCH_CAP_MSEC:
		_settle_launch(true, "the load cap was reached")


## The wait resolves. Success: mark the session live and exit
## completely - absence during play is still the design. Failure:
## mark it failed, put the failure on the wall, keep browsing.
func _settle_launch(ok: bool, reason: String) -> void:
	if not _launch_pending:
		return
	_launch_pending = false
	var game: GameEntry = _launch_game
	_launch_game = null
	var elapsed: float = float(Time.get_ticks_msec() - _launch_started_msec) / 1000.0
	if ok:
		_launch_service.mark_live()
		print("PVLDS LAUNCH: hand-off complete (%s) after %.1fs; launcher exiting" % [reason, elapsed])
		_intentional_launch_exit = true
		if _smoke_verdict_pending:
			print("PVLDS SMOKE LAUNCH: handed off (%s) after %.1fs" % [reason, elapsed])
		get_tree().quit()
	else:
		_launch_service.fail_launch()
		printerr("PVLDS LAUNCH: failed - ", reason)
		if _smoke_verdict_pending:
			printerr("PVLDS SMOKE LAUNCH: FAIL - ", reason)
			get_tree().quit(1)
			return
		if _room != null and game != null:
			_room.end_launch_failed(game, reason)


## --pvlds-shot-launch: fire a real launch once the wall is ready,
## then capture the LOADING room ~1s into the wait and leave.
func _poll_shot_launch() -> void:
	if not _shot_launch_fired:
		if _room != null and _room.visible and _room.wall_ready:
			_fire_shot_launch()
		return
	if _launch_pending and Time.get_ticks_msec() - _shot_launch_at_msec >= 1000:
		var path: String = _shot_launch_path
		_shot_launch_path = ""
		var img: Image = get_viewport().get_texture().get_image()
		var err: Error = img.save_png(path)
		print("PVLDS SHOT LAUNCH: ", path, " err=", err, " size=", img.get_size())
		if _launch_service != null:
			_launch_service.disarm()
		get_tree().quit(0 if err == OK else 1)
	elif not _launch_pending and Time.get_ticks_msec() - _shot_launch_at_msec >= 3000:
		printerr("PVLDS SHOT LAUNCH: FAIL - the launch never entered its wait")
		get_tree().quit(1)


func _fire_shot_launch() -> void:
	_shot_launch_fired = true
	_shot_launch_at_msec = Time.get_ticks_msec()
	var game: GameEntry = null
	if _scanner != null:
		game = _scanner.game_by_id("dg-galaxy-corsair")
		if game == null and not _scanner.games.is_empty():
			game = _scanner.games[0]
	if game == null:
		printerr("PVLDS SHOT LAUNCH: FAIL - no game to launch")
		get_tree().quit(1)
		return
	var build: TableBuild = game.resolve_default_build(_state)
	_on_launch_requested(game, build)


## EXIT (room rail): disarm the watchdog first - the player who
## wants out stays out - then quit.
func _on_exit_requested() -> void:
	if _launch_service != null:
		_launch_service.disarm()
	get_tree().quit()


## A window close without a launch is also an exit-to-desktop:
## disarm, so no watchdog resurrects an app the player closed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _launch_service != null and not _intentional_launch_exit:
			_launch_service.disarm()
		get_tree().quit()


func _show_desk() -> void:
	if _room != null:
		_room.visible = false
	if _desk == null:
		_desk = SetupDesk.new()
		add_child(_desk)
		_desk.setup(_config)
		_desk.enter_room_requested.connect(_enter_room)
	_desk.visible = true


# ------------------------------------------------------------ dev hooks

## --pvlds-db-stats <path>: load a vpsdb.json and print headline
## counts. Used to sanity-proof the real VPS database in tests.
func _run_db_stats(path: String) -> void:
	var db: VpsDatabase = VpsDatabase.new()
	if not db.load_db(path):
		printerr("PVLDS DB STATS: failed to load ", path)
		get_tree().quit(1)
		return
	print("PVLDS DB STATS: ", path)
	print("  games: ", db.game_count())
	print("  VPX table files: ", db.vpx_table_file_count())
	print("  VR-tagged VPX table files: ", db.vr_tagged_vpx_file_count())
	get_tree().quit(0)


## --pvlds-smoke-launch <game_id>: the launcher-side integration
## smoke. Fires the real launch path (same entry as the card's
## Launch button) against the seeded dummy library with the config's
## exe pointed at a stub (env override), rides the real load wait,
## and lets _settle_launch print the verdict and quit: handed off
## (0) when the stub's window report lands, FAIL (1) if the stub
## dies mid-load. The harness reads the timing in the verdict line
## as proof the launcher stayed resident during the load.
func _smoke_launch(game_id: String) -> void:
	var game: GameEntry = _scanner.game_by_id(game_id) if _scanner != null else null
	if game == null:
		printerr("PVLDS SMOKE LAUNCH: FAIL - game not found: ", game_id)
		get_tree().quit(1)
		return
	_smoke_verdict_pending = true
	var build: TableBuild = game.resolve_default_build(_state)
	_on_launch_requested(game, build)


# ------------------------------------------------------------ core test

func _write_text_file(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func _expect(cond: bool, label: String, failures: Array[String]) -> void:
	if cond:
		print("  ok - ", label)
	else:
		failures.append(label)
		printerr("  FAIL - ", label)


func _run_core_test() -> void:
	print("PVLDS core test (UI-free)")
	var failures: Array[String] = []
	var dummy_tables: String = ProjectSettings.globalize_path("res://dummy_data/tables")
	var db: VpsDatabase = VpsDatabase.new()
	_expect(db.load_db("res://data/vpsdb.json"), "dummy database loads", failures)
	_expect(db.game_count() == 10, "database knows 10 games", failures)
	var scanner: LibraryScanner = LibraryScanner.new()
	var folders: Array[String] = [dummy_tables]
	scanner.scan(folders, db)
	_expect(scanner.total_files == 13, "13 .vpx files found (stray .ini ignored)", failures)
	_expect(scanner.games.size() == 10, "grouped into 10 games", failures)
	_expect(scanner.matched_files == 11, "11 builds matched exactly", failures)
	_expect(scanner.game_matched_files == 2, "2 builds matched by game only", failures)
	_expect(scanner.duplicate_group_count() == 2, "2 duplicate groups", failures)
	_expect(scanner.art_covered_games == 3, "3 games have art", failures)
	var gc: GameEntry = scanner.game_by_id("dg-galaxy-corsair")
	_expect(gc != null, "Galaxy Corsair present", failures)
	if gc != null:
		_expect(gc.builds.size() == 3, "Galaxy Corsair has 3 builds", failures)
		var cur: TableBuild = gc.current_build()
		_expect(cur != null and cur.version == "1.1.0", "Galaxy Corsair CURRENT is v1.1.0", failures)
		_expect(gc.is_vr_tagged(), "Galaxy Corsair is VR-tagged", failures)
		var mod: TableBuild = gc.build_by_path(dummy_tables.path_join("Galaxy Corsair (Northlight 1991) v0.9.9 MOD.vpx"))
		_expect(mod != null and not mod.matched_db, "the MOD build is local-only", failures)
	var vb: GameEntry = scanner.game_by_id("dg-vector-bloom")
	_expect(vb != null and vb.current_build() != null and vb.current_build().version == "1.3",
		"Vector Bloom CURRENT is the db-known v1.3, not the newer local file", failures)
	var pl: GameEntry = scanner.game_by_id("dg-pharaohs-ledger")
	_expect(pl != null and pl.ensure_art() != "", "Pharaoh's Ledger art extracted from .directb2s (on demand)", failures)
	var nh: GameEntry = scanner.game_by_id("dg-neon-harbor")
	_expect(nh != null and nh.art_path.ends_with(".png"), "Neon Harbor side-image art found", failures)

	# State round-trip (back up any real state file first, restore after).
	var state_file: String = StateStore.state_path()
	var backup: String = ""
	if FileAccess.file_exists(state_file):
		backup = FileAccess.get_file_as_string(state_file)
	var store: StateStore = StateStore.new()
	store.set_favorite("dg-galaxy-corsair", true)
	if gc != null:
		var old_build: TableBuild = gc.build_by_path(dummy_tables.path_join("Galaxy Corsair (Northlight 1991) v1.0.2.vpx"))
		_expect(old_build != null, "v1.0.2 build addressable by path", failures)
		if old_build != null:
			store.set_default_build("dg-galaxy-corsair", old_build.file_path)
	store.touch_recent("dg-low-orbit")
	store.touch_recent("dg-cinder-peak")
	store.save_to_disk()
	var store2: StateStore = StateStore.new()
	store2.load_from_disk()
	_expect(store2.is_favorite("dg-galaxy-corsair"), "favorite persisted", failures)
	if gc != null:
		var resolved: TableBuild = gc.resolve_default_build(store2)
		_expect(resolved != null and resolved.version == "1.0.2", "stored default build wins over CURRENT", failures)
	_expect(store2.recents.size() == 2 and store2.recents[0] == "dg-cinder-peak", "recents are most-recent-first", failures)

	# Last-played + room view state round-trip (the M2 return trip).
	store2.set_last_played("dg-cinder-peak", "/tables/Cinder Peak.vpx")
	store2.set_view_state("vr", "year", 3, "dg-cinder-peak")
	store2.save_to_disk()
	var store3: StateStore = StateStore.new()
	store3.load_from_disk()
	_expect(store3.last_played_game_id == "dg-cinder-peak" and store3.last_played_build_path == "/tables/Cinder Peak.vpx",
		"last-played persists across the exit/relaunch cycle", failures)
	_expect(store3.view_filter == "vr" and store3.view_sort == "year" and store3.view_page == 3 and store3.selected_game_id == "dg-cinder-peak",
		"room view state persists (filter/sort/page/selection)", failures)
	if backup != "":
		var f: FileAccess = FileAccess.open(state_file, FileAccess.WRITE)
		if f != null:
			f.store_string(backup)
			f.close()
	elif FileAccess.file_exists(state_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state_file))

	# Launch plan: template expansion, quoting, build choice.
	var lcfg: PvldsConfig = PvldsConfig.new()
	lcfg.vpx_exe_path = "C:/Visual Pinball/VPinball_GL64.exe"
	lcfg.launch_args_template = "-play \"{table}\""
	if gc != null:
		var def_build: TableBuild = gc.resolve_default_build(store3)
		var plan: LaunchPlan = LaunchPlan.build_plan(lcfg, gc, def_build)
		_expect(plan.valid and plan.args.size() == 2 and plan.args[0] == "-play" and plan.args[1] == def_build.file_path,
			"launch plan expands {table} to the default build's path", failures)
		var mod2: TableBuild = gc.build_by_path(dummy_tables.path_join("Galaxy Corsair (Northlight 1991) v0.9.9 MOD.vpx"))
		if mod2 != null:
			var once_plan: LaunchPlan = LaunchPlan.build_plan(lcfg, gc, mod2)
			_expect(once_plan.valid and once_plan.args[1] == mod2.file_path,
				"an explicit build (play-once) overrides the default in the plan", failures)
		var bad_plan: LaunchPlan = LaunchPlan.build_plan(lcfg, gc, null)
		_expect(not bad_plan.valid and bad_plan.error != "", "a plan with no build is invalid, with a reason", failures)
	var spaced: Array[String] = LaunchPlan.expand_template(
		"-Min -play \"{table}\" -flag \"two words\"", "C:/My Tables/Space Table (Maker 1999).vpx")
	_expect(spaced.size() == 5 and spaced[2] == "C:/My Tables/Space Table (Maker 1999).vpx" and spaced[4] == "two words",
		"quoted template segments with spaces stay single arguments", failures)
	var bare: Array[String] = LaunchPlan.expand_template("-play {table}", "C:/My Tables/Space Table.vpx")
	_expect(bare.size() == 2 and bare[1] == "C:/My Tables/Space Table.vpx",
		"an unquoted {table} is still one argument (arrays are not shell-split)", failures)

	# Watchdog contract round-trip (backed up + restored like state).
	var contract_file: String = WatchdogContract.contract_path_absolute()
	var contract_backup: String = ""
	if FileAccess.file_exists(contract_file):
		contract_backup = FileAccess.get_file_as_string(contract_file)
	var contract: WatchdogContract = WatchdogContract.new()
	contract.armed = true
	contract.session_id = 7
	contract.session_state = "live"
	contract.game_exe_path = "C:/Visual Pinball/VPinball_GL64.exe"
	contract.game_pid = 4242
	contract.game_window_seen_unix = 1234567
	contract.launcher_path = "C:/PVLDS/PVLDS.exe"
	contract.focus_herding = false
	_expect(contract.save_to_disk(), "watchdog contract saves", failures)
	var contract2: WatchdogContract = WatchdogContract.load_from_disk()
	_expect(contract2.armed and contract2.session_id == 7 and contract2.game_pid == 4242
		and contract2.session_state == "live" and contract2.game_window_seen_unix == 1234567
		and not contract2.focus_herding
		and contract2.launcher_path == "C:/PVLDS/PVLDS.exe",
		"watchdog contract round-trips (incl. the window-seen stamp)", failures)
	# Legacy schema-v1 state spellings normalize on load - a contract
	# written by the M2 build is understood by this one.
	_expect(_write_text_file(contract_file, "{\"session_state\": \"playing\"}"), "legacy contract written", failures)
	_expect(WatchdogContract.load_from_disk().session_state == "live",
		"legacy 'playing' loads as 'live'", failures)
	_expect(_write_text_file(contract_file, "{\"session_state\": \"launching\"}"), "legacy contract rewritten", failures)
	_expect(WatchdogContract.load_from_disk().session_state == "loading",
		"legacy 'launching' loads as 'loading'", failures)
	if contract_backup != "":
		var cf: FileAccess = FileAccess.open(contract_file, FileAccess.WRITE)
		if cf != null:
			cf.store_string(contract_backup)
			cf.close()
	elif FileAccess.file_exists(contract_file):
		DirAccess.remove_absolute(contract_file)

	# Config: the -exit default, the old-default migration, and the
	# desk warning's condition (backed up + restored like the rest).
	var config_file: String = PvldsConfig.user_path()
	var config_backup: String = ""
	if FileAccess.file_exists(config_file):
		config_backup = FileAccess.get_file_as_string(config_file)
	_expect(_write_text_file(config_file, JSON.stringify({"launch_args_template": PvldsConfig.OLD_DEFAULT_LAUNCH_ARGS})),
		"old-default config written", failures)
	var mig_cfg: PvldsConfig = PvldsConfig.new()
	_expect(mig_cfg.load_from_disk() and mig_cfg.launch_args_template == PvldsConfig.DEFAULT_LAUNCH_ARGS,
		"a saved old-default template migrates to the -exit default", failures)
	_expect(_write_text_file(config_file, JSON.stringify({"launch_args_template": "-play -minimized \"{table}\""})),
		"custom config written", failures)
	var custom_cfg: PvldsConfig = PvldsConfig.new()
	_expect(custom_cfg.load_from_disk() and custom_cfg.launch_args_template == "-play -minimized \"{table}\"",
		"a customized template is never rewritten by migration", failures)
	_expect(PvldsConfig.template_includes_exit("-play -exit \"{table}\""), "-exit passes the exit check", failures)
	_expect(not PvldsConfig.template_includes_exit("-play \"{table}\""), "no -exit fails the exit check", failures)
	_expect(PvldsConfig.template_includes_exit("-play /exit {table}"), "the /exit spelling passes the exit check", failures)
	if config_backup != "":
		_write_text_file(config_file, config_backup)
	elif FileAccess.file_exists(config_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_file))

	if failures.is_empty():
		print("CORE TEST: PASS")
		get_tree().quit(0)
	else:
		printerr("CORE TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)
