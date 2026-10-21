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
##   --pvlds-smoke-placard
##                       room boot; force XR on, open setup with a
##                       message, assert the placard contract (room
##                       stays up, wall inert, BACK restores), then
##                       assert the flat path is the legacy one,
##                       print the verdict, quit
##   --pvlds-smoke-desk  desk boot (stays on the desk); flip the
##                       session switches through their real signals
##                       and assert the config FILE on disk changed
##                       with no Save & Scan, print the verdict, quit

var _config: PvldsConfig
var _state: StateStore
var _db: VpsDatabase
var _scanner: LibraryScanner
var _art_warmer: ArtWarmer
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
var _smoke_placard: bool = false ## --pvlds-smoke-placard: drive the setup-placard contract once the room is up
var _placard_smoke_phase: int = 0
var _placard_smoke_wait: int = 0
var _placard_smoke_failures: int = 0
var _smoke_desk: bool = false ## --pvlds-smoke-desk: drive the desk's live session switches, assert the config file follows
var _desk_smoke_phase: int = 0
var _desk_smoke_wait: int = 0
var _desk_smoke_failures: int = 0

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
var _art_bench: bool = false ## --pvlds-art-bench: dev measurement route (cold/warm page-fill timings)
var _bench_phase: int = -1
var _bench_t_room: int = 0
var _bench_t_mark: int = 0
var _bench_warm_started_msec: int = 0
var _bench_max_frame_msec: float = 0.0
var _bench_max_frame_warm_msec: float = 0.0


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
	if user_args.has("--pvlds-smoke-placard"):
		_smoke_placard = true
	if user_args.has("--pvlds-smoke-desk"):
		_smoke_desk = true
	if user_args.has("--pvlds-art-bench"):
		_art_bench = true
		_bench_phase = 0
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
	# The art warmer: background backglass pre-extraction so card
	# art is warm before it is browsed to (art-speed round).
	_art_warmer = ArtWarmer.new()
	_art_warmer.on_drained = _on_art_warm_drained
	if configured and _config.is_configured() and not user_args.has("--setup") and not _smoke_desk:
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
	if _smoke_placard:
		_drive_placard_smoke()
	if _smoke_desk:
		_drive_desk_smoke()
	if _art_bench:
		_drive_art_bench(_delta)
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
	# Scan landed: start warming the whole library's art in the
	# background (and re-arm on every later scan).
	if _art_warmer != null and _scanner != null:
		_art_warmer.warm_library(_scanner.games)
	if _smoke_launch_game != "":
		var gid: String = _smoke_launch_game
		_smoke_launch_game = ""
		_smoke_launch(gid)
		return
	if _enter_room_after_scan:
		_enter_room_after_scan = false
		if _last_db_kind == "sample" and not _seeded_dummy and not _art_bench:
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
	var cov: Vector2i = ArtWarmer.cache_coverage(s.games)
	if cov.y > 0:
		lines.append("Art cache: %d of %d art images are extracted and ready instantly; the rest pre-extract in the background while you browse." % [cov.x, cov.y])
	var health: Dictionary = ArtWarmer.art_health(s.games)
	if int(health["total"]) > 0:
		lines.append("Backglass health (from the art cache's outcome index): %d extracted OK, %d no image in file, %d failed to read or parse, %d not tried yet." % [
			int(health["ok"]), int(health["no_image"]), int(health["failed"]), int(health["untried"])])
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
	if _art_bench and _bench_t_room == 0:
		_bench_t_room = Time.get_ticks_msec()
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
		_room.setup_placard_dismissed.connect(_on_setup_placard_dismissed)
		_room.launch_requested.connect(_on_launch_requested)
		_room.exit_requested.connect(_on_exit_requested)
		_room.art_prefetch_requested.connect(_on_art_prefetch)
	else:
		_room.refresh_library()
		# Entering the room (e.g. Enter the Room on the desk while a
		# placard stood in the headset) never leaves a stale placard.
		_room.clear_setup_placard()
	_room.visible = true
	# Room entry with a cold cache (e.g. back from the desk without a
	# rescan): make sure a warm pass is queued.
	if _art_warmer != null and _scanner != null:
		_art_warmer.warm_library(_scanner.games)


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
		_show_desk(msg)
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


## Show the desk pass. Flat (no XR): the room hides and the desk
## takes the viewport, as always. XR live: the desk is a 2D form in
## this same viewport and cannot reach the headset, so hiding the
## room blacked out the player's view with no in-headset way back
## (field fault, 2026-10-21: SETUP in the room -> black screen).
## The room stays up and carries a placard instead - explanation
## plus a BACK that dismisses both - while the desk still opens on
## the monitor, where the setup work belongs. A caller with
## something to say (the launch-failure path) passes a message;
## it lands on the desk's stats area and on the placard alike.
func _show_desk(message: String = "") -> void:
	if _xr_enabled and _room != null:
		_room.show_setup_placard(message)
	elif _room != null:
		_room.visible = false
	if _desk == null:
		_desk = SetupDesk.new()
		add_child(_desk)
		_desk.setup(_config)
		_desk.enter_room_requested.connect(_enter_room)
	_desk.visible = true


## The placard's BACK: the player chose the room over the desk -
## close the desk (SETUP reopens it whenever it is needed).
func _on_setup_placard_dismissed() -> void:
	if _desk != null:
		_desk.visible = false


# -------------------------------------------------- placard smoke

## --pvlds-smoke-placard: drive _show_desk with the XR flag forced
## on (the flag is just a bool at this layer) and assert the
## placard contract end to end - room stays up, placard stands,
## wall inert, focus confined to BACK - then BACK restores the
## room and closes the desk. A second leg with the flag off
## asserts the legacy flat path is untouched.
func _drive_placard_smoke() -> void:
	match _placard_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_xr_enabled = true
				_show_desk("Smoke: a launch failure message")
				_placard_smoke_wait = 0
				_placard_smoke_phase = 1
			else:
				_placard_smoke_wait += 1
				if _placard_smoke_wait > 3600:
					_placard_smoke_fail("the room never came up")
					_finish_placard_smoke()
		1:
			_placard_smoke_wait += 1
			if _placard_smoke_wait >= 3:
				_placard_expect(_room.visible, "XR setup: the room stays visible")
				_placard_expect(_room.is_setup_placard_up(), "XR setup: the placard is up")
				_placard_expect(_room.setup_placard_message() == "Smoke: a launch failure message",
					"XR setup: the placard carries the caller's message")
				_placard_expect(_desk != null and _desk.visible, "XR setup: the desk still opens (for the monitor)")
				var inert: bool = true
				for q: ClickableQuad in _room._panels:
					if q.pick_enabled:
						inert = false
				for q: ClickableQuad in _room._panel_launches:
					if q.pick_enabled:
						inert = false
				for k: Variant in _room._rail_quads.keys():
					var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
					if rq != null and rq.pick_enabled:
						inert = false
				_placard_expect(inert, "XR setup: every wall/rail control is inert behind the placard")
				var back: ClickableQuad = _room.setup_placard_back_quad()
				_placard_expect(back != null, "XR setup: the placard has a BACK control")
				_placard_expect(_room._focusables.size() == 1 and _room._focusables[0] == back,
					"XR setup: focus navigation is confined to BACK")
				if back != null:
					_room._activate(back)
				_placard_smoke_wait = 0
				_placard_smoke_phase = 2
		2:
			_placard_smoke_wait += 1
			if _placard_smoke_wait >= 3:
				_placard_expect(not _room.is_setup_placard_up(), "BACK: the placard comes down")
				_placard_expect(_desk != null and not _desk.visible, "BACK: the desk closes with it")
				_placard_expect(_room.visible, "BACK: the room is still up")
				var live: bool = true
				for q: ClickableQuad in _room._panels:
					if not q.pick_enabled:
						live = false
				_placard_expect(live, "BACK: the wall's controls are live again")
				var desk_quad: ClickableQuad = _room._rail_quads.get("desk") as ClickableQuad
				var label_quad: ClickableQuad = _room._rail_quads.get("page_label") as ClickableQuad
				_placard_expect(desk_quad != null and desk_quad.pick_enabled, "BACK: the rail is live again (SETUP)")
				_placard_expect(label_quad != null and not label_quad.pick_enabled,
					"BACK: the page label stays non-pickable, as built")
				_placard_expect(_room._focusables.size() > 1, "BACK: focus navigation roams the room again")
				# Legacy leg: no XR - the desk replaces the room.
				_xr_enabled = false
				_show_desk()
				_placard_smoke_wait = 0
				_placard_smoke_phase = 3
		3:
			_placard_smoke_wait += 1
			if _placard_smoke_wait >= 3:
				_placard_expect(not _room.visible, "flat setup: the room hides for the desk, as before")
				_placard_expect(_desk != null and _desk.visible, "flat setup: the desk shows")
				_finish_placard_smoke()


func _placard_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - placard smoke: ", label)
	else:
		_placard_smoke_fail(label)


func _placard_smoke_fail(label: String) -> void:
	_placard_smoke_failures += 1
	printerr("  FAIL - placard smoke: ", label)


func _finish_placard_smoke() -> void:
	if _placard_smoke_failures == 0:
		print("PVLDS PLACARD SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS PLACARD SMOKE: FAIL (%d)" % _placard_smoke_failures)
		get_tree().quit(1)


# -------------------------------------------------- desk smoke

## --pvlds-smoke-desk: the desk's session switches are live
## settings - flipping one must rewrite the config file on disk
## immediately, with no Save & Scan. The boot route with this
## flag lands on the desk and stays there (no scan, no room).
## The driver flips two checkboxes through their real toggled
## signal and picks a hold button through the picker's real
## item_selected signal, then re-reads the config FILE with a
## fresh PvldsConfig and asserts what landed - plus that the
## fields a flip does not own (exe path, folders) survived.
func _drive_desk_smoke() -> void:
	match _desk_smoke_phase:
		0:
			if _desk != null:
				# The starting point, straight off the disk the
				# boot read (the harness's scratch config beside
				# the exported binary).
				var before: PvldsConfig = PvldsConfig.new()
				_desk_expect(before.load_from_disk(), "the scratch config loads")
				_desk_expect(before.close_vpx_on_table_exit, "the scratch config starts with close-on-exit on")
				_desk_expect(not before.focus_herding, "the scratch config starts with herding off")
				# Flip through the real controls and their signals.
				_desk._close_check.button_pressed = false
				_desk._herding_check.button_pressed = true
				var left_idx: int = PvldsConfig.HOLD_EXIT_BUTTONS.find("dpad_left")
				_desk._hold_button_picker.select(left_idx)
				_desk._hold_button_picker.item_selected.emit(left_idx)
				_desk_smoke_wait = 0
				_desk_smoke_phase = 1
			else:
				_desk_smoke_wait += 1
				if _desk_smoke_wait > 600:
					_desk_smoke_fail("the desk never came up")
					_finish_desk_smoke()
		1:
			_desk_smoke_wait += 1
			if _desk_smoke_wait >= 3:
				# In memory first: Main's own config is the truth
				# the contract mirrors at the next launch.
				_desk_expect(not _config.close_vpx_on_table_exit, "the close flip is in Main's config immediately")
				_desk_expect(_config.focus_herding, "the herding flip is in Main's config immediately")
				_desk_expect(_config.hold_exit_button == "dpad_left", "the button pick is in Main's config immediately")
				# Then the file itself - the whole point of the round.
				var after: PvldsConfig = PvldsConfig.new()
				_desk_expect(after.load_from_disk(), "the config file still loads after the flips")
				_desk_expect(not after.close_vpx_on_table_exit, "the config FILE has close-on-exit off, no Save & Scan pressed")
				_desk_expect(after.focus_herding, "the config FILE has herding on")
				_desk_expect(after.hold_exit_button == "dpad_left", "the config FILE has the picked hold button")
				_desk_expect(after.vpx_exe_path == _config.vpx_exe_path and after.table_folders == _config.table_folders,
					"fields the flips do not own (exe path, folders) are untouched on disk")
				_finish_desk_smoke()


func _desk_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - desk smoke: ", label)
	else:
		_desk_smoke_fail(label)


func _desk_smoke_fail(label: String) -> void:
	_desk_smoke_failures += 1
	printerr("  FAIL - desk smoke: ", label)


func _finish_desk_smoke() -> void:
	if _desk_smoke_failures == 0:
		print("PVLDS DESK SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS DESK SMOKE: FAIL (%d)" % _desk_smoke_failures)
		get_tree().quit(1)


# ------------------------------------------------------------ dev hooks

## --pvlds-db-stats <path>: load a vpsdb.json and print headline
## counts. Used to sanity-proof the real VPS database in tests.
## Dev route --pvlds-art-bench: drives the room through a cold page,
## a full-library warm, and a warm page, printing ARTBENCH timings.
## Wall-clock numbers from a fixture library - a harness, not a verdict.
func _drive_art_bench(delta: float) -> void:
	var frame_msec: float = delta * 1000.0
	if frame_msec > _bench_max_frame_msec:
		_bench_max_frame_msec = frame_msec
	if _art_warmer != null and not _art_warmer.is_idle() and frame_msec > _bench_max_frame_warm_msec:
		_bench_max_frame_warm_msec = frame_msec
	if _room == null or not _room.visible or _scanner == null:
		return
	match _bench_phase:
		0:
			if _room.wall_ready:
				print("ARTBENCH page0_fill_msec=", Time.get_ticks_msec() - _bench_t_room)
				_bench_flip_to(10)
				_bench_t_mark = Time.get_ticks_msec()
				_bench_phase = 1
		1:
			if _room.wall_ready:
				print("ARTBENCH cold_flip_page10_msec=", Time.get_ticks_msec() - _bench_t_mark)
				_bench_warm_started_msec = Time.get_ticks_msec()
				_bench_begin_warm()
				_bench_phase = 2
		2:
			if _bench_warm_done():
				print("ARTBENCH warm_full_library_msec=", _bench_warm_duration_msec())
				_bench_flip_to(12)
				_bench_t_mark = Time.get_ticks_msec()
				_bench_phase = 3
		3:
			if _room.wall_ready:
				print("ARTBENCH warm_flip_page12_msec=", Time.get_ticks_msec() - _bench_t_mark)
				print("ARTBENCH max_frame_msec=", snappedf(_bench_max_frame_msec, 0.1))
				print("ARTBENCH max_frame_during_warm_msec=", snappedf(_bench_max_frame_warm_msec, 0.1))
				print("ARTBENCH DONE")
				_bench_phase = -1
				get_tree().quit()


func _bench_flip_to(page: int) -> void:
	var guard: int = 0
	while int(_room.get("_page")) < page and guard < 64:
		_room._handle_rail("page_next")
		guard += 1


## The warmer auto-starts at scan finish; the bench just waits for
## its pass to drain and reports the warmer's own pass duration.
func _bench_begin_warm() -> void:
	pass


func _bench_warm_done() -> bool:
	return _art_warmer == null or _art_warmer.is_idle()


func _bench_warm_duration_msec() -> int:
	return _art_warmer.last_pass_msec if _art_warmer != null else 0


## Room prefetch: neighbouring pages' art jumps the warmer's queue.
func _on_art_prefetch(games: Array) -> void:
	if _art_warmer == null:
		return
	var typed: Array[GameEntry] = []
	for g: Variant in games:
		if g is GameEntry:
			var ge: GameEntry = g
			typed.append(ge)
	_art_warmer.prioritize(typed)


## A warm pass drained: refresh the desk's coverage line so the
## art-cache stat reads current when the player next visits it.
func _on_art_warm_drained() -> void:
	if _desk != null and _scanner != null:
		_desk.apply_scan_summary(build_scan_summary())


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


func _zero_bytes(n: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(n)
	return b


## A minimal valid 24-bit BMP (BITMAPFILEHEADER + BITMAPINFOHEADER
## + bottom-up BGR rows, rows padded to 4 bytes), hand-built the
## way an external tool writes one - Godot has no BMP writer, which
## is the point: old designer files carry bytes Godot never made.
func _bmp_bytes(w: int, h: int) -> PackedByteArray:
	var row_bytes: int = (w * 3 + 3) & ~3
	var data_size: int = row_bytes * h
	var total: int = 54 + data_size
	var b: PackedByteArray = PackedByteArray()
	b.resize(total)
	b[0] = 0x42 # 'B'
	b[1] = 0x4D # 'M'
	b.encode_s32(2, total)
	b.encode_s32(10, 54)
	b.encode_s32(14, 40)
	b.encode_s32(18, w)
	b.encode_s32(22, h)
	b.encode_s16(26, 1)
	b.encode_s16(28, 24)
	b.encode_s32(34, data_size)
	for i: int in range(54, total):
		b[i] = 0x80
	return b


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
	contract.close_vpx_on_table_exit = false
	contract.hold_exit_enabled = false
	contract.hold_exit_button = "start"
	_expect(contract.save_to_disk(), "watchdog contract saves", failures)
	var contract2: WatchdogContract = WatchdogContract.load_from_disk()
	_expect(contract2.armed and contract2.session_id == 7 and contract2.game_pid == 4242
		and contract2.session_state == "live" and contract2.game_window_seen_unix == 1234567
		and not contract2.focus_herding and not contract2.close_vpx_on_table_exit
		and not contract2.hold_exit_enabled and contract2.hold_exit_button == "start"
		and contract2.launcher_path == "C:/PVLDS/PVLDS.exe",
		"watchdog contract round-trips (incl. the window-seen stamp, the close-duty switch, and the hold-to-exit fields)", failures)
	# A contract written before the close duty existed has no
	# close_vpx_on_table_exit key; it loads with the duty ON (the
	# schema stays v2 - absence means default, never a wedge).
	_expect(_write_text_file(contract_file, "{\"session_state\": \"live\"}"), "pre-duty contract written", failures)
	var pre_duty: WatchdogContract = WatchdogContract.load_from_disk()
	_expect(pre_duty.close_vpx_on_table_exit,
		"a contract without the close-duty key defaults it to on", failures)
	# The same absence rule covers hold-to-exit: no keys, feature
	# ON, button D-pad Right (the recorded ExitGame binding).
	_expect(pre_duty.hold_exit_enabled and pre_duty.hold_exit_button == PvldsConfig.DEFAULT_HOLD_EXIT_BUTTON,
		"a contract without the hold-to-exit keys defaults them (on, dpad_right)", failures)
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

	# Config: the plain -play default and the bad-default repair
	# (backed up + restored like the rest). INVERTED from the fix
	# round that shipped "-exit": that flag is not VPX's (its parser
	# calls it a frontend no-op), so the round-trip now proves the
	# bad string is repaired and everything else is left alone.
	# Write where load_from_disk reads (existing_path): outside the
	# editor those differ from user_path() (beside-exe wins), and
	# writing anywhere else makes the loads below read a different
	# file than the test just wrote.
	var config_file: String = PvldsConfig.existing_path()
	var config_backup: String = ""
	if FileAccess.file_exists(config_file):
		config_backup = FileAccess.get_file_as_string(config_file)
	_expect(PvldsConfig.DEFAULT_LAUNCH_ARGS == "-play \"{table}\"",
		"the shipped default is plain -play (no -exit folklore)", failures)
	_expect(_write_text_file(config_file, JSON.stringify({"launch_args_template": PvldsConfig.BAD_DEFAULT_LAUNCH_ARGS})),
		"bad-default config written", failures)
	var mig_cfg: PvldsConfig = PvldsConfig.new()
	_expect(mig_cfg.load_from_disk() and mig_cfg.launch_args_template == PvldsConfig.DEFAULT_LAUNCH_ARGS,
		"a saved BAD-default template is repaired to the good default", failures)
	_expect(_write_text_file(config_file, JSON.stringify({"launch_args_template": "-play -minimized \"{table}\""})),
		"custom config written", failures)
	var custom_cfg: PvldsConfig = PvldsConfig.new()
	_expect(custom_cfg.load_from_disk() and custom_cfg.launch_args_template == "-play -minimized \"{table}\"",
		"a customized template is never rewritten by the repair", failures)
	_expect(_write_text_file(config_file, JSON.stringify({"launch_args_template": "-minimized -play -exit \"{table}\""})),
		"custom -exit-bearing config written", failures)
	var own_exit_cfg: PvldsConfig = PvldsConfig.new()
	_expect(own_exit_cfg.load_from_disk() and own_exit_cfg.launch_args_template == "-minimized -play -exit \"{table}\"",
		"a user's own -exit-bearing template (not byte-identical to the bad default) is preserved", failures)
	# The close-duty switch: defaults on, persists off.
	_expect(_write_text_file(config_file, JSON.stringify({"close_vpx_on_table_exit": false})),
		"close-duty-off config written", failures)
	var close_cfg: PvldsConfig = PvldsConfig.new()
	_expect(close_cfg.load_from_disk() and not close_cfg.close_vpx_on_table_exit,
		"the close-duty switch persists as off", failures)
	close_cfg.close_vpx_on_table_exit = true
	_expect(close_cfg.save_to_disk(), "config saves", failures)
	var close_cfg2: PvldsConfig = PvldsConfig.new()
	_expect(close_cfg2.load_from_disk() and close_cfg2.close_vpx_on_table_exit,
		"the close-duty switch round-trips through save", failures)
	# The hold-to-exit fields: defaults when absent (on, D-pad
	# Right), persistence when set, and a hand-typed unknown
	# button name degrades to the default, never to a dead
	# feature.
	_expect(_write_text_file(config_file, JSON.stringify({})),
		"empty config written", failures)
	var hold_def_cfg: PvldsConfig = PvldsConfig.new()
	_expect(hold_def_cfg.load_from_disk() and hold_def_cfg.hold_exit_enabled
		and hold_def_cfg.hold_exit_button == PvldsConfig.DEFAULT_HOLD_EXIT_BUTTON,
		"a config without the hold-to-exit keys defaults them (on, dpad_right)", failures)
	_expect(_write_text_file(config_file, JSON.stringify({"hold_exit_enabled": false, "hold_exit_button": "y"})),
		"hold-off config written", failures)
	var hold_cfg: PvldsConfig = PvldsConfig.new()
	_expect(hold_cfg.load_from_disk() and not hold_cfg.hold_exit_enabled and hold_cfg.hold_exit_button == "y",
		"the hold-to-exit fields persist as set (off, y)", failures)
	hold_cfg.hold_exit_enabled = true
	hold_cfg.hold_exit_button = "back"
	_expect(hold_cfg.save_to_disk(), "hold config saves", failures)
	var hold_cfg2: PvldsConfig = PvldsConfig.new()
	_expect(hold_cfg2.load_from_disk() and hold_cfg2.hold_exit_enabled and hold_cfg2.hold_exit_button == "back",
		"the hold-to-exit fields round-trip through save", failures)
	_expect(_write_text_file(config_file, JSON.stringify({"hold_exit_button": "paddle_9"})),
		"unknown-button config written", failures)
	var hold_clamp_cfg: PvldsConfig = PvldsConfig.new()
	_expect(hold_clamp_cfg.load_from_disk() and hold_clamp_cfg.hold_exit_button == PvldsConfig.DEFAULT_HOLD_EXIT_BUTTON,
		"an unknown hold button name loads as the default (dpad_right)", failures)
	if config_backup != "":
		_write_text_file(config_file, config_backup)
	elif FileAccess.file_exists(config_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_file))

	# --- Art cache (art-speed round): stamped invalidation, panel-
	# size storage, claim coordination, the background warmer.
	var art_dir: String = "user://core_test_art"
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir != null and not user_dir.dir_exists("core_test_art"):
		user_dir.make_dir("core_test_art")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1234
	var block: PackedByteArray = PackedByteArray()
	block.resize(65536)
	for i: int in range(block.size()):
		block[i] = rng.randi_range(0, 255)
	var mk_img: Callable = func(w: int, h: int) -> Image:
		var bytes: PackedByteArray = PackedByteArray()
		var need: int = w * h * 4
		while bytes.size() < need:
			bytes.append_array(block)
		bytes.resize(need)
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	var mk_b2s: Callable = func(path: String, w: int, h: int) -> bool:
		var im: Image = mk_img.call(w, h) as Image
		var text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(im.save_png_to_buffer()) + "\" /></Images></DirectB2SData>"
		return _write_text_file(path, text)
	var b2s_a: String = art_dir.path_join("Stamp Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_a, 800, 1000)), "stamp fixture A written", failures)
	var p1: String = ArtProvider.extract_directb2s_image(b2s_a)
	_expect(p1 != "" and p1 == ArtProvider.cache_path_for(b2s_a), "extraction lands at the stamped cache path", failures)
	_expect(ArtProvider.is_cached(b2s_a), "the stamped entry reads as cached", failures)
	var cached_img: Image = Image.new()
	_expect(cached_img.load(p1) == OK and cached_img.get_width() == 512 and cached_img.get_height() == 640,
		"the cached image is stored at panel size (800x1000 -> 512x640)", failures)
	_expect(bool(mk_b2s.call(b2s_a, 600, 700)), "stamp fixture A replaced (different image)", failures)
	var p2: String = ArtProvider.extract_directb2s_image(b2s_a)
	_expect(p2 != "" and p2 != p1, "a replaced backglass invalidates its cache entry (new stamp, new path)", failures)
	var cached_img2: Image = Image.new()
	_expect(cached_img2.load(p2) == OK and cached_img2.get_width() == 512 and cached_img2.get_height() == 597,
		"the replacement's art is what the new entry serves (600x700 -> 512x597)", failures)
	_expect(ArtProvider.claim_extract(b2s_a), "the first claim on a file succeeds", failures)
	_expect(not ArtProvider.claim_extract(b2s_a), "a second claim on the same file is refused (no double extraction)", failures)
	ArtProvider.release_extract(b2s_a)
	_expect(ArtProvider.claim_extract(b2s_a), "a released claim can be taken again", failures)
	ArtProvider.release_extract(b2s_a)
	# The warmer extracts an uncached file on its worker thread...
	var b2s_b: String = art_dir.path_join("Warm Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_b, 400, 500)), "warm fixture written", failures)
	var warm_entry: GameEntry = GameEntry.new()
	warm_entry.art_source_path = b2s_b
	var warm_games: Array[GameEntry] = [warm_entry]
	var warmer: ArtWarmer = ArtWarmer.new()
	warmer.warm_library(warm_games)
	var waited: int = 0
	while not warmer.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warmer.is_idle() and ArtProvider.is_cached(b2s_b), "the warmer pre-extracts the library in the background", failures)
	_expect(warmer.last_pass_items == 1, "the warm pass performed exactly one extraction", failures)
	_expect(ArtWarmer.cache_coverage(warm_games) == Vector2i(1, 1), "cache coverage reports have/want", failures)
	# ...but never duplicates a claimed (panel-owned) extraction:
	# the claimed file is skipped, and the priority path completes it.
	var b2s_c: String = art_dir.path_join("Claimed Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_c, 400, 500)), "claimed fixture written", failures)
	var claimed_entry: GameEntry = GameEntry.new()
	claimed_entry.art_source_path = b2s_c
	var claimed_games: Array[GameEntry] = [claimed_entry]
	_expect(ArtProvider.claim_extract(b2s_c), "panel claim taken for the coordination test", failures)
	var warmer2: ArtWarmer = ArtWarmer.new()
	warmer2.warm_library(claimed_games)
	waited = 0
	while not warmer2.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warmer2.is_idle() and not ArtProvider.is_cached(b2s_c),
		"the warmer skips a file a panel has claimed (never extracts twice)", failures)
	ArtProvider.release_extract(b2s_c)
	_expect(claimed_entry.ensure_art() != "" and ArtProvider.is_cached(b2s_c),
		"the priority path extracts the claimed file itself", failures)

	# --- Art outcomes (diagnostic round): stamped negatives, the
	# outcome index, format variants from the B2S server's reader,
	# the claim-stall fallback, and the desk's health counts.
	# A file with no image elements at all: extracted once, stamped
	# no_image, and never extracted again while the file stands.
	var b2s_neg: String = art_dir.path_join("No Image Table.directb2s")
	_expect(_write_text_file(b2s_neg, "<DirectB2SData><Images></Images><Illumination></Illumination></DirectB2SData>"),
		"no-image fixture written", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_neg) == "" and not ArtProvider.is_cached(b2s_neg),
		"a file with no image elements yields no art", failures)
	_expect(ArtProvider.outcome_for(b2s_neg) == ArtProvider.STATUS_NO_IMAGE,
		"the no-image outcome is recorded in the index", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_neg) == "" and ArtProvider.outcome_for(b2s_neg) == ArtProvider.STATUS_NO_IMAGE,
		"a stamped negative stays stamped (no silent re-extraction)", failures)
	var neg_entry: GameEntry = GameEntry.new()
	neg_entry.art_source_path = b2s_neg
	_expect(neg_entry.ensure_art() == "", "a panel for a stamped-negative game gets the title card, no work", failures)
	# An OK fixture the warmer test and the health counts share.
	var b2s_ok: String = art_dir.path_join("Healthy Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_ok, 400, 500)), "healthy fixture written", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_ok) != "" and ArtProvider.outcome_for(b2s_ok) == ArtProvider.STATUS_OK,
		"a healthy extraction records ok", failures)
	var ok_entry: GameEntry = GameEntry.new()
	ok_entry.art_source_path = b2s_ok
	# The warmer never re-queues a stamped negative (nor a cached
	# file): a library of just those two extracts NOTHING.
	var warmer3: ArtWarmer = ArtWarmer.new()
	var skip_games: Array[GameEntry] = [neg_entry, ok_entry]
	warmer3.warm_library(skip_games)
	waited = 0
	while not warmer3.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warmer3.is_idle() and warmer3.last_pass_items == 0,
		"the warmer skips stamped negatives and cached files entirely", failures)
	# A designated backglass element whose payload will not decode
	# is corruption: the failed class, not no_image.
	var b2s_bad: String = art_dir.path_join("Corrupt Table.directb2s")
	_expect(_write_text_file(b2s_bad, "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(_zero_bytes(300)) + "\" /></Images></DirectB2SData>"),
		"corrupt fixture written", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_bad) == "" and ArtProvider.outcome_for(b2s_bad) == ArtProvider.STATUS_FAILED,
		"an undecodable designated backglass records failed", failures)
	var bad_entry: GameEntry = GameEntry.new()
	bad_entry.art_source_path = b2s_bad
	# Variant 1 (B2S server reader): the on/off pair replaces
	# BackglassImage in dual files. The lit (On) half is the panel
	# art: 800x1000 fitted to 512x640, not the Off half's 400x500.
	var pair_off: Image = mk_img.call(400, 500) as Image
	var pair_on: Image = mk_img.call(800, 1000) as Image
	var b2s_pair: String = art_dir.path_join("Pair Table.directb2s")
	_expect(_write_text_file(b2s_pair, "<DirectB2SData><Images><BackglassOffImage Value=\"" + Marshalls.raw_to_base64(pair_off.save_png_to_buffer()) + "\" /><BackglassOnImage Value=\"" + Marshalls.raw_to_base64(pair_on.save_png_to_buffer()) + "\" /></Images></DirectB2SData>"),
		"on/off pair fixture written", failures)
	var pair_cache: String = ArtProvider.extract_directb2s_image(b2s_pair)
	var pair_img: Image = Image.new()
	_expect(pair_cache != "" and pair_img.load(pair_cache) == OK and pair_img.get_width() == 512 and pair_img.get_height() == 640,
		"the on/off pair variant extracts its On image (800x1000 -> 512x640)", failures)
	# Variant 2: a BMP-encoded backglass (older designer files) -
	# hand-built BMP bytes, the way an external tool writes them.
	var b2s_bmp: String = art_dir.path_join("Bmp Table.directb2s")
	_expect(_write_text_file(b2s_bmp, "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(_bmp_bytes(4, 3)) + "\" /></Images></DirectB2SData>"),
		"BMP fixture written", failures)
	var bmp_cache: String = ArtProvider.extract_directb2s_image(b2s_bmp)
	var bmp_img: Image = Image.new()
	_expect(bmp_cache != "" and bmp_img.load(bmp_cache) == OK and bmp_img.get_width() == 4 and bmp_img.get_height() == 3,
		"a BMP-encoded backglass extracts (4x3, unscaled)", failures)
	# Variant 3: the same XML carried as UTF-16LE with a BOM.
	var b2s_u16: String = art_dir.path_join("Utf16 Table.directb2s")
	var u16_xml: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64((mk_img.call(400, 500) as Image).save_png_to_buffer()) + "\" /></Images></DirectB2SData>"
	var u16_bytes: PackedByteArray = PackedByteArray()
	u16_bytes.append(0xFF)
	u16_bytes.append(0xFE)
	u16_bytes.append_array(u16_xml.to_utf16_buffer())
	var u16_file: FileAccess = FileAccess.open(b2s_u16, FileAccess.WRITE)
	_expect(u16_file != null, "UTF-16 fixture opened for writing", failures)
	if u16_file != null:
		u16_file.store_buffer(u16_bytes)
		u16_file.close()
	_expect(ArtProvider.extract_directb2s_image(b2s_u16) != "" and ArtProvider.outcome_for(b2s_u16) == ArtProvider.STATUS_OK,
		"a UTF-16LE backglass file extracts", failures)
	# Claim-stall fallback: a claim held by someone who never
	# finishes must not leave the panel waiting - after the bounded
	# wait the panel extracts the file itself.
	var b2s_stall: String = art_dir.path_join("Stalled Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_stall, 400, 500)), "stall fixture written", failures)
	_expect(ArtProvider.claim_extract(b2s_stall), "stall claim taken (a stuck holder)", failures)
	var stall_entry: GameEntry = GameEntry.new()
	stall_entry.art_source_path = b2s_stall
	var stall_t0: int = Time.get_ticks_msec()
	var stall_art: String = stall_entry.ensure_art()
	var stall_elapsed: int = Time.get_ticks_msec() - stall_t0
	ArtProvider.release_extract(b2s_stall)
	_expect(stall_art != "" and ArtProvider.is_cached(b2s_stall),
		"a stalled claim falls back to the panel extracting it itself", failures)
	_expect(stall_elapsed >= 2500 and stall_elapsed < 20000,
		"the stall fallback waited the bounded wait, not forever (%d ms)" % stall_elapsed, failures)
	# The desk's health breakdown, from the persisted index.
	var b2s_untried: String = art_dir.path_join("Untried Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_untried, 400, 500)), "untried fixture written", failures)
	var untried_entry: GameEntry = GameEntry.new()
	untried_entry.art_source_path = b2s_untried
	var health_games: Array[GameEntry] = [ok_entry, neg_entry, bad_entry, untried_entry]
	var health: Dictionary = ArtWarmer.art_health(health_games)
	_expect(int(health["total"]) == 4 and int(health["ok"]) == 1 and int(health["no_image"]) == 1
		and int(health["failed"]) == 1 and int(health["untried"]) == 1,
		"art health counts ok / no_image / failed / untried from the index", failures)
	# A replaced file is a new stamp: the negative outcome dies with
	# the old file version, and the new art extracts.
	_expect(bool(mk_b2s.call(b2s_neg, 400, 500)), "no-image fixture replaced with a real backglass", failures)
	_expect(ArtProvider.outcome_for(b2s_neg) == "", "replacing the file clears its stamped outcome (new stamp)", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_neg) != "" and ArtProvider.outcome_for(b2s_neg) == ArtProvider.STATUS_OK,
		"the replacement's art extracts and records ok", failures)

	if failures.is_empty():
		print("CORE TEST: PASS")
		get_tree().quit(0)
	else:
		printerr("CORE TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)
