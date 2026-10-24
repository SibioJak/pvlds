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
##   --pvlds-shot-pop PREFIX
##                       room boot; save PREFIX_flush.png with
##                       every card flush, focus the middle card,
##                       assert its pop-out transform (offset,
##                       scale, neighbour untouched), save
##                       PREFIX_popped.png, print the verdict, quit
##   --pvlds-smoke-placard
##                       room boot; force XR on, open setup with a
##                       message, assert the placard contract (room
##                       stays up, wall inert, BACK restores), then
##                       assert the flat path is the legacy one,
##                       print the verdict, quit
##   --pvlds-smoke-desk  desk boot (stays on the desk); flip the
##                       session switch through its real signal and
##                       assert the config FILE on disk changed;
##                       also assert the stricken close/hold
##                       controls are absent from the desk
##   --pvlds-smoke-dpadexit
##                       room boot; inject a synthetic fresh
##                       D-pad Right press into the room's real
##                       poll - the app must exit through the rail
##                       EXIT path (disarm "room Exit" + quit).
##                       The harness asserts the exit + the
##                       contract from outside; if the press does
##                       nothing the driver prints FAIL and quits 1
##   --pvlds-smoke-dpadexit-held
##                       the baseline-arming leg: the button is
##                       pinned pressed from boot, before the room
##                       instance's first poll (the field phantom:
##                       a controller reconnecting to a relaunched
##                       room). The app must NOT exit while it sits
##                       pressed; after a release, a fresh press
##                       must exit through the same rail path
##   --pvlds-smoke-lockout
##                       room boot; fire a real launch (env
##                       overrides as --pvlds-smoke-launch), then
##                       attack the load wait - direct EXIT/SETUP
##                       activations, a synthetic gamepad A press,
##                       a window close - and assert the room stays
##                       deaf, the contract stays armed/loading,
##                       and the wait still settles at the hand-off
##                       with no Save & Scan, print the verdict, quit
##   --pvlds-smoke-quitwarm
##                       desk boot on a scratch library of large
##                       .directb2s files; once the post-scan warm
##                       has banked a few extractions and is still
##                       chewing, exit through the REAL rail path
##                       (_on_exit_requested) - the harness times
##                       how long the process takes to die. Mode
##                       "drain" (env PVLDS_QUITWARM_MODE=drain)
##                       instead lets the warm finish and reports
##                       the pass duration before exiting the same
##                       way. Guards the exit-hang fault: an
##                       unstoppable warm pass made quit wait out
##                       the whole queue.
##   --pvlds-smoke-nav   room boot; force the ALL filter, drop the
##                       desk camera to a seated eye, then assert
##                       the focus graph (sideways travel walks the
##                       control rail's own order end to end and
##                       never lands on a card; UP from the rail
##                       enters the grid, DOWN returns) and the
##                       wall's clearance geometry (every Launch
##                       button clear of its card's name strip;
##                       the bottom row - flush and popped - clear
##                       of the rail in screen space), print the
##                       verdict, quit
##   --pvlds-seated-cam  with --pvlds-shot: take the shot from a
##                       seated eye height (RoomView.SEATED_EYE_Y)
##                       instead of the standing desk eye

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
var _smoke_desk: bool = false ## --pvlds-smoke-desk: drive the desk's live session switch, assert the config file follows
var _smoke_dpadexit: bool = false ## --pvlds-smoke-dpadexit: a fresh D-pad Right in the room must exit the app
var _dpadexit_held_leg: bool = false ## --pvlds-smoke-dpadexit-held: the button is pinned from boot; no exit until a witnessed release, then a fresh press exits
var _dpadexit_smoke_phase: int = 0
var _dpadexit_smoke_wait: int = 0
var _desk_smoke_phase: int = 0
var _desk_smoke_wait: int = 0
var _desk_smoke_failures: int = 0
var _smoke_nav: bool = false ## --pvlds-smoke-nav: the focus graph + seated wall clearance contract
var _nav_smoke_phase: int = 0
var _nav_smoke_wait: int = 0
var _nav_smoke_failures: int = 0
var _nav_faces_done: bool = false ## the title-card face check (async render) has reported
var _nav_pop_panel: ClickableQuad = null ## bottom-row panel the nav smoke pops for the clearance re-check
var _seated_cam: bool = false ## --pvlds-seated-cam: shots/nav run from a seated eye height
var _smoke_lockout: bool = false ## --pvlds-smoke-lockout: attack the load wait's input lockout mid-flight
var _lockout_smoke_pending: bool = false ## a launch fired by the lockout smoke is in its wait; _settle_launch prints its verdict
var _smoke_quitwarm: bool = false ## --pvlds-smoke-quitwarm: exit mid-warm-pass through the real Exit path (mode via PVLDS_QUITWARM_MODE)
var _quitwarm_fired: bool = false
var _quitwarm_started_msec: int = 0
var _lockout_smoke_phase: int = 0
var _lockout_smoke_wait: int = 0
var _lockout_smoke_failures: int = 0
var _lockout_smoke_fired_msec: int = 0
var _lockout_exit_fired: bool = false
var _lockout_setup_fired: bool = false

# The launch load wait. While _launch_pending, _process polls for
# the hand-off point and for VPX dying mid-load.
const LAUNCH_SETTLE_MSEC: int = 1500 ## table runtime up + this long = hand off
const LAUNCH_CAP_MSEC: int = 45000 ## never hold the room hostage to a stuck load
const LAUNCH_DEAD_GRACE_MSEC: int = 1500 ## a dead spawn pid gets this long for the watchdog's by-path window report before the launch is called failed
var _launch_pending: bool = false
var _launch_game: GameEntry = null
var _launch_pid: int = 0
var _launch_session_id: int = 0
var _launch_started_msec: int = 0
var _launch_runtime_seen_msec: int = -1
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
var _shot_pop_prefix: String = "" ## --pvlds-shot-pop PREFIX: flush + popped room shots with transform assertions
var _shot_pop_phase: int = -1
var _shot_pop_frames: int = 0
var _shot_pop_panel: ClickableQuad = null
var _shot_pop_since_msec: int = 0
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
	var shot_pop_idx: int = user_args.find("--pvlds-shot-pop")
	if shot_pop_idx >= 0 and shot_pop_idx + 1 < user_args.size():
		_shot_pop_prefix = user_args[shot_pop_idx + 1]
		_shot_pop_phase = 0
	if user_args.has("--pvlds-smoke-placard"):
		_smoke_placard = true
	if user_args.has("--pvlds-smoke-desk"):
		_smoke_desk = true
	if user_args.has("--pvlds-smoke-dpadexit"):
		_smoke_dpadexit = true
	if user_args.has("--pvlds-smoke-dpadexit-held"):
		_smoke_dpadexit = true
		_dpadexit_held_leg = true
	if user_args.has("--pvlds-smoke-lockout"):
		_smoke_lockout = true
	if user_args.has("--pvlds-smoke-nav"):
		_smoke_nav = true
	if user_args.has("--pvlds-seated-cam"):
		_seated_cam = true
	if user_args.has("--pvlds-smoke-quitwarm"):
		_smoke_quitwarm = true
	if user_args.has("--pvlds-art-bench"):
		_art_bench = true
		_bench_phase = 0
	if _dpadexit_held_leg:
		# Held leg: pin D-pad Right pressed NOW, in _ready - before
		# the first frame, hence before the room instance's first
		# poll. The button reads held from that instance's birth,
		# exactly the phantom shape from the field report (a
		# controller reconnecting to a watchdog-relaunched room):
		# with the baseline-release arming, no exit may come of it.
		var pin: InputEventJoypadButton = InputEventJoypadButton.new()
		pin.device = 0
		pin.button_index = JOY_BUTTON_DPAD_RIGHT
		pin.pressed = true
		Input.parse_input_event(pin)
		print("  info - dpadexit smoke: held leg - D-pad Right pinned from boot")
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
	elif (_smoke_launch_game != "" or _smoke_lockout or _smoke_dpadexit or _smoke_nav or _shot_pop_prefix != "") and not configured:
		# The smoke hook prefers a real installed config (its whole
		# point is integrating against one); seeding is only the
		# fallback. Seeding over a real config also breaks in exports,
		# where the seed's globalized res:// paths name no real files.
		_seeded_dummy = true
		_seed_dummy_config()
		configured = true
	if _smoke_launch_game != "" or _shot_launch_path != "" or _smoke_lockout:
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
	if _smoke_dpadexit:
		_drive_dpadexit_smoke()
	if _smoke_lockout:
		_drive_lockout_smoke()
	if _smoke_nav:
		_drive_nav_smoke()
	if _smoke_quitwarm:
		_drive_quitwarm_smoke()
	if _art_bench:
		_drive_art_bench(_delta)
	if _shot_pop_phase >= 0:
		_drive_shot_pop()
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
	# The missing-backglass list (Chris's ask, 2026-10-23): every
	# completed scan regenerates missing_b2s.txt from the scanner's
	# own pairing record, so the file on disk is always the current
	# library's truth - and the desk shows the count beside the
	# scan's health lines.
	if _scanner != null:
		var b2s_err: Error = MissingB2sList.write_file(_scanner.missing_b2s_files)
		if b2s_err != OK:
			push_warning("PVLDS: missing_b2s.txt could not be written (error %d)" % b2s_err)
		if _desk != null:
			_desk.apply_missing_b2s(_scanner.missing_b2s_files.size())
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
	if _seated_cam:
		# Dev hooks only (--pvlds-seated-cam, --pvlds-smoke-nav):
		# the flat camera works from a seated player's eye height.
		_room.set_desk_camera_height(RoomView.SEATED_EYE_Y)
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
		_launch_runtime_seen_msec = -1
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
## changing hands, the watchdog's runtime report + settle, the cap.
## The settle cue is the RUNTIME stamp, not the window sighting:
## the sighting stamps off the editor's own canvas about a second
## after spawn, while a real table load takes several seconds
## more - handing off on it left a desktop gap in the headset
## between the room leaving and the table arriving. The sighting
## keeps its other jobs (the dead-pid grace above, the watchdog's
## exit-detector arming). Every backstop is unchanged: a table
## whose runtime never shows still rides the cap, the XR cue, or
## the failure path exactly as before.
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
	if contract.session_id == _launch_session_id and contract.runtime_seen_unix > 0:
		if _launch_runtime_seen_msec < 0:
			_launch_runtime_seen_msec = now
		elif now - _launch_runtime_seen_msec >= LAUNCH_SETTLE_MSEC:
			_settle_launch(true, "VPX's runtime is up")
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
		_request_art_warm_stop()
		if _smoke_verdict_pending:
			print("PVLDS SMOKE LAUNCH: handed off (%s) after %.1fs" % [reason, elapsed])
		if _lockout_smoke_pending:
			if _lockout_smoke_failures > 0:
				printerr("PVLDS LOCKOUT SMOKE: FAIL - %d assertion(s) failed; the hand-off itself completed (%s)" % [_lockout_smoke_failures, reason])
				get_tree().quit(1)
				return
			print("PVLDS LOCKOUT SMOKE: PASS - the wait stayed deaf, the window close was ignored, and the hand-off completed (%s)" % reason)
		get_tree().quit()
	else:
		_launch_service.fail_launch()
		printerr("PVLDS LAUNCH: failed - ", reason)
		if _smoke_verdict_pending:
			printerr("PVLDS SMOKE LAUNCH: FAIL - ", reason)
			get_tree().quit(1)
			return
		if _lockout_smoke_pending:
			printerr("PVLDS LOCKOUT SMOKE: FAIL - the load wait itself failed (%s), with %d prior assertion failure(s)" % [reason, _lockout_smoke_failures])
			get_tree().quit(1)
			return
		if _room != null and game != null:
			_room.end_launch_failed(game, reason)


## --pvlds-shot-launch: fire a real launch once the wall is ready,
## then capture the LOADING room ~1s into the wait and leave. The
## capture delay is retunable via PVLDS_SHOT_LAUNCH_DELAY_MS (the
## marquee QA loop shoots mid-fly-in and settled frames).
func _poll_shot_launch() -> void:
	if not _shot_launch_fired:
		if _room != null and _room.visible and _room.wall_ready:
			_fire_shot_launch()
		return
	var delay_ms: int = 1000
	var delay_env: String = OS.get_environment("PVLDS_SHOT_LAUNCH_DELAY_MS")
	if delay_env.is_valid_int():
		delay_ms = delay_env.to_int()
	if _launch_pending and Time.get_ticks_msec() - _shot_launch_at_msec >= delay_ms:
		var path: String = _shot_launch_path
		_shot_launch_path = ""
		var img: Image = get_viewport().get_texture().get_image()
		var err: Error = img.save_png(path)
		print("PVLDS SHOT LAUNCH: ", path, " err=", err, " size=", img.get_size())
		if _launch_service != null:
			_launch_service.disarm("shot-launch dev hook")
		get_tree().quit(0 if err == OK else 1)
	elif not _launch_pending and Time.get_ticks_msec() - _shot_launch_at_msec >= maxi(3000, delay_ms + 1500):
		printerr("PVLDS SHOT LAUNCH: FAIL - the launch never entered its wait")
		get_tree().quit(1)


## --pvlds-shot-pop PREFIX: the card pop-out's QA hook. Boots the
## room, clears focus and lets any pop settle, saves
## PREFIX_flush.png (every card flush), then focuses the middle
## card through the room's own focus path, waits for the pop to
## complete, asserts the transform evidence (the focused card
## sits POP_OUT_DISTANCE off the wall at POP_OUT_SCALE, its
## neighbour untouched, the pop target is the focused card),
## saves PREFIX_popped.png, prints the verdict, quits.
func _drive_shot_pop() -> void:
	match _shot_pop_phase:
		0:
			if _room == null or not _room.visible or not _room.wall_ready:
				return
			_room._set_focused(null)
			_shot_pop_frames += 1
			if _shot_pop_frames < 12:
				return
			if _room._panels.size() < 3:
				printerr("PVLDS POP SHOT: FAIL - the wall holds %d panels, need at least 3" % _room._panels.size())
				get_tree().quit(1)
				return
			var flush_err: Error = _save_shot_png(_shot_pop_prefix + "_flush.png")
			if flush_err != OK:
				printerr("PVLDS POP SHOT: FAIL - flush shot err=", flush_err)
				get_tree().quit(1)
				return
			var mid: int = _room._panels.size() / 2
			_shot_pop_panel = _room._panels[mid]
			_room._set_focused(_shot_pop_panel)
			_shot_pop_since_msec = Time.get_ticks_msec()
			_shot_pop_phase = 1
		1:
			var amt: float = _room.panel_pop_amount(_shot_pop_panel)
			var waited: int = Time.get_ticks_msec() - _shot_pop_since_msec
			if amt < 0.999 and waited < 3000:
				return
			var problems: Array[String] = []
			if amt < 0.999:
				problems.append("pop amount %.3f after %dms" % [amt, waited])
			var off: Vector3 = _room.panel_pop_offset(_shot_pop_panel)
			if absf(off.length() - RoomView.POP_OUT_DISTANCE) > 0.01:
				problems.append("offset length %.4f, want %.2f" % [off.length(), RoomView.POP_OUT_DISTANCE])
			if absf(_shot_pop_panel.scale.x - RoomView.POP_OUT_SCALE) > 0.01:
				problems.append("scale %.3f, want %.2f" % [_shot_pop_panel.scale.x, RoomView.POP_OUT_SCALE])
			if _room.pop_target() != _shot_pop_panel:
				problems.append("pop target is not the focused panel")
			var pidx: int = _room._panels.find(_shot_pop_panel)
			var neighbour: ClickableQuad = _room._panels[pidx - 1]
			if _room.panel_pop_amount(neighbour) != 0.0 or _room.panel_pop_offset(neighbour).length() > 0.001:
				problems.append("neighbour panel is not flush")
			var pop_err: Error = _save_shot_png(_shot_pop_prefix + "_popped.png")
			if pop_err != OK:
				problems.append("popped shot err=%d" % pop_err)
			if problems.is_empty():
				print("PVLDS POP SHOT: PASS amount=%.3f offset=%.4f scale=%.3f waited=%dms" % [amt, off.length(), _shot_pop_panel.scale.x, waited])
				get_tree().quit(0)
			else:
				printerr("PVLDS POP SHOT: FAIL - ", "; ".join(PackedStringArray(problems)))
				get_tree().quit(1)


func _save_shot_png(path: String) -> Error:
	var img: Image = get_viewport().get_texture().get_image()
	return img.save_png(path)


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


## Every deliberate quit stops the art warmer first. Its pass is a
## WorkerThreadPool task, and Godot waits for pool tasks during
## shutdown: an unstopped pass with a full queue (a fresh scan's
## worth of real multi-second extractions) turns an exit into a
## minutes-long hang (field fault, 2026-10-22). The pass abandons
## its queue at the next item boundary; items already extracted
## keep their cache entries and outcome stamps.
func _request_art_warm_stop() -> void:
	if _art_warmer != null:
		_art_warmer.request_stop()


## EXIT (room rail): disarm the watchdog first - the player who
## wants out stays out - then quit. The disarm names itself, as
## every disarm now does.
func _on_exit_requested() -> void:
	_request_art_warm_stop()
	if _launch_service != null:
		_launch_service.disarm("room Exit")
	get_tree().quit()


## A window close without a launch is also an exit-to-desktop:
## disarm, so no watchdog resurrects an app the player closed.
## DURING the load wait, though, a close is logged and ignored -
## no disarm, no quit. The environment can produce one mid-
## handoff (Virtual Desktop's session transfer when VPX takes
## the headset is the known suspect), and the environment must
## not be able to dismiss a session the player is waiting on.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		# Backstop for every quit route not named above (dev
		# hooks, smoke drivers): the tree is going down, so the
		# warm pass gets its stop before the pool wait begins.
		_request_art_warm_stop()
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _launch_pending:
			print("PVLDS: window close ignored during the load wait")
			return
		_request_art_warm_stop()
		if _launch_service != null and not _intentional_launch_exit:
			_launch_service.disarm("window close")
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


# -------------------------------------------------- lockout smoke

## --pvlds-smoke-lockout: fire a real launch (env overrides, as
## --pvlds-smoke-launch) and, DURING the load wait, attack the
## room the way the field failure did - and the way the fixed
## room must now refuse:
##   leg 1: hand the activation funnel the EXIT and SETUP quads
##          directly (the pad reaches _activate through the
##          focused quad; the funnel is where the refusal lives),
##          plus a synthetic gamepad A press through the input
##          singleton, the way the player's plunger press arrives;
##   leg 2: fire a window close at Main mid-wait (the VD session
##          transfer can produce one);
##   leg 3: a fresh D-pad Right press - the room's BACK-out -
##          which the deaf wait must swallow like everything else.
## The contract must stay armed/loading with no disarm reason,
## focus must be nowhere, and the wait must then settle normally
## at the hand-off - _settle_launch prints the verdict.
func _drive_lockout_smoke() -> void:
	match _lockout_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready and _scanner != null:
				_lockout_smoke_fire()
			else:
				_lockout_smoke_wait += 1
				if _lockout_smoke_wait > 3600:
					_lockout_expect(false, "the room never came up")
					_finish_lockout_smoke()
		1:
			if not _launch_pending:
				_lockout_expect(false, "the load wait settled before the attack could run")
				_finish_lockout_smoke()
				return
			_lockout_smoke_attack()
			_lockout_smoke_wait = 0
			_lockout_smoke_phase = 2
		2:
			_lockout_smoke_wait += 1
			if _lockout_smoke_wait >= 5:
				_lockout_smoke_after_pad()
				_lockout_smoke_wait = 0
				_lockout_smoke_phase = 4
		4:
			_lockout_smoke_wait += 1
			if _lockout_smoke_wait >= 5:
				_lockout_smoke_after_dpad()
				_lockout_smoke_phase = 3
		3:
			# The settle owns the verdict and the quit. Only a
			# wait that NEVER settles fails here.
			if _launch_pending and Time.get_ticks_msec() - _lockout_smoke_fired_msec > 60000:
				_lockout_expect(false, "the load wait never settled")
				_finish_lockout_smoke()


func _lockout_smoke_fire() -> void:
	var game: GameEntry = null
	if _scanner != null:
		game = _scanner.game_by_id("dg-galaxy-corsair")
		if game == null and not _scanner.games.is_empty():
			game = _scanner.games[0]
	if game == null:
		_lockout_expect(false, "no game to launch")
		_finish_lockout_smoke()
		return
	# Count the two signals whose firing would mean the room was
	# NOT deaf. Main's own handlers are connected as well; if EXIT
	# truly fired, Main would disarm + quit mid-attack and the
	# harness would see the wreckage instead of a verdict.
	_room.exit_requested.connect(func() -> void: _lockout_exit_fired = true)
	_room.setup_requested.connect(func() -> void: _lockout_setup_fired = true)
	_lockout_smoke_pending = true
	_lockout_smoke_fired_msec = Time.get_ticks_msec()
	var build: TableBuild = game.resolve_default_build(_state)
	_on_launch_requested(game, build)
	if not _launch_pending:
		_lockout_expect(false, "the launch never entered its wait")
		_finish_lockout_smoke()
		return
	_lockout_smoke_phase = 1


func _lockout_smoke_attack() -> void:
	# The room's side of the lockout: deaf, focusless, honest.
	_lockout_expect(_room.is_launch_in_wait(), "the room reports a launch in its wait")
	_lockout_expect(_room.focused_quad() == null, "no quad holds focus during the wait")
	_lockout_expect(_room.focusable_count() == 0, "the focusable set is empty during the wait")
	var exit_q: ClickableQuad = _room.rail_quad("exit")
	var desk_q: ClickableQuad = _room.rail_quad("desk")
	_lockout_expect(exit_q != null and not exit_q.pick_enabled, "the EXIT quad is pick-disabled during the wait")
	_lockout_expect(desk_q != null and not desk_q.pick_enabled, "the SETUP quad is pick-disabled during the wait")
	_lockout_expect(_room.launch_status_note().contains("controls are locked"),
		"the banner note says the controls are locked during the wait")
	# Leg 1a: the field attack, aimed at the funnel by hand.
	if exit_q != null:
		_room._activate(exit_q)
	if desk_q != null:
		_room._activate(desk_q)
	_lockout_expect(not _lockout_exit_fired, "activating EXIT during the wait fired nothing")
	_lockout_expect(not _lockout_setup_fired, "activating SETUP during the wait fired nothing")
	_lockout_expect(_launch_pending, "the launcher is still resident after the activation attempts")
	# Leg 1b: feed a gamepad A press (release follows in phase 2,
	# so the room's poll sees a genuinely held button across
	# frames - the player's plunger press, arriving mid-load).
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = 0
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)


func _lockout_smoke_after_pad() -> void:
	# Whether the synthetic press registered with the input
	# singleton at all - reported, not asserted: the direct
	# _activate leg above is the load-bearing refusal proof, and
	# this line keeps the report honest about the pad leg.
	print("  info - lockout smoke: synthetic A press visible to Input: ", Input.is_joy_button_pressed(0, JOY_BUTTON_A))
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = 0
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	Input.parse_input_event(release)
	_lockout_expect(not _lockout_exit_fired, "a gamepad A press during the wait fired no EXIT")
	_lockout_expect(not _lockout_setup_fired, "a gamepad A press during the wait fired no SETUP")
	_lockout_expect(_launch_pending, "the launcher is still resident after the A press")
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	_lockout_expect(c.armed, "the contract is still armed after the attack")
	_lockout_expect(c.session_state == "loading", "the session is still loading after the attack")
	_lockout_expect(c.disarm_reason == "", "no disarm reason was written by the attack")
	# Leg 2: a window close lands mid-wait. Logged and ignored:
	# no disarm, no quit, the session sails on to its hand-off.
	_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_lockout_expect(_launch_pending, "a window close during the wait did not end it")
	var c2: WatchdogContract = WatchdogContract.load_from_disk()
	_lockout_expect(c2.armed and c2.session_state == "loading" and c2.disarm_reason == "",
		"the contract is untouched by the window close")
	# Leg 3: a fresh D-pad Right press during the wait. In the
	# room that press is the BACK-out (exit the app) - and the
	# load wait is deaf, so even it must do nothing here. The
	# release + assertions land in _lockout_smoke_after_dpad,
	# frames later, so the room's poll has had its chance to
	# (not) act.
	var dpress: InputEventJoypadButton = InputEventJoypadButton.new()
	dpress.device = 0
	dpress.button_index = JOY_BUTTON_DPAD_RIGHT
	dpress.pressed = true
	Input.parse_input_event(dpress)


func _lockout_smoke_after_dpad() -> void:
	var drelease: InputEventJoypadButton = InputEventJoypadButton.new()
	drelease.device = 0
	drelease.button_index = JOY_BUTTON_DPAD_RIGHT
	drelease.pressed = false
	Input.parse_input_event(drelease)
	_lockout_expect(not _lockout_exit_fired, "a D-pad Right press during the wait fired no EXIT")
	_lockout_expect(_launch_pending, "the launcher is still resident after the D-pad Right press")
	var c: WatchdogContract = WatchdogContract.load_from_disk()
	_lockout_expect(c.armed and c.session_state == "loading" and c.disarm_reason == "",
		"the contract is untouched by the D-pad Right press")


func _lockout_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - lockout smoke: ", label)
	else:
		_lockout_smoke_failures += 1
		printerr("  FAIL - lockout smoke: ", label)


func _finish_lockout_smoke() -> void:
	_lockout_smoke_phase = 3
	_smoke_lockout = false
	printerr("PVLDS LOCKOUT SMOKE: FAIL - %d assertion(s) failed; aborted before the hand-off" % maxi(_lockout_smoke_failures, 1))
	get_tree().quit(1)


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
				# D-pad Right on the placard: the room's BACK-out
				# press must do NOTHING here - BACK is the only
				# way off the placard. Inject it and give the
				# room's poll frames to (not) act (phase 4).
				var dpress: InputEventJoypadButton = InputEventJoypadButton.new()
				dpress.device = 0
				dpress.button_index = JOY_BUTTON_DPAD_RIGHT
				dpress.pressed = true
				Input.parse_input_event(dpress)
				_placard_smoke_wait = 0
				_placard_smoke_phase = 4
		4:
			_placard_smoke_wait += 1
			if _placard_smoke_wait >= 5:
				var drelease: InputEventJoypadButton = InputEventJoypadButton.new()
				drelease.device = 0
				drelease.button_index = JOY_BUTTON_DPAD_RIGHT
				drelease.pressed = false
				Input.parse_input_event(drelease)
				_placard_expect(_room.is_setup_placard_up(), "D-pad Right on the placard: the placard stands")
				_placard_expect(_room.visible, "D-pad Right on the placard: the room is still up (no exit)")
				var back2: ClickableQuad = _room.setup_placard_back_quad()
				if back2 != null:
					_room._activate(back2)
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


# ---------------------------------------------------- nav smoke

## --pvlds-smoke-nav: the focus graph + wall clearance contract
## (Chris's field reports, 2026-10-24, from his seated headset
## view):
##   leg 1: sideways travel along the control rail walks the
##          rail's own order end to end, both directions, and
##          never lands on a wall card;
##   leg 2: UP from the rail enters the card grid; DOWN from
##          the grid's bottom row returns to the rail;
##   leg 3: from a seated eye, every Launch button clears its
##          card's name strip (panel-local arithmetic and the
##          screen projection agree), and the bottom row -
##          cards and buttons, flush and popped - clears the
##          rail in screen space;
##   leg 4: a title card's face still registers its content at
##          texture row 0 (the 71877f4 raise, undisturbed);
##   leg 5: the bumpers flip PAGES (Chris's clarification,
##          2026-10-24 - sections shift one page over, never
##          cycle filters): RB advances, LB retreats, both
##          clamp at the ends, focus keeps its place across a
##          flip (same grid slot / same rail stop / first panel
##          from no focus), and the bumpers are inert in the
##          load wait, on the SETUP placard, and in the detail
##          view.
## The driver forces the ALL filter through the room's own rail
## handler so the wall always holds a full bottom row. Leg 5
## needs more pages than the dummy library's ten games give, so
## the harness adds a scratch folder of stub tables beside it.
func _drive_nav_smoke() -> void:
	match _nav_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_room.set_desk_camera_height(RoomView.SEATED_EYE_Y)
				_room._handle_rail("filter:all")
				_nav_smoke_wait = 0
				_nav_smoke_phase = 1
			else:
				_nav_smoke_wait += 1
				if _nav_smoke_wait > 3600:
					_nav_smoke_fail("the room never came up")
					_finish_nav_smoke()
		1:
			_nav_smoke_wait += 1
			if _nav_smoke_wait > 3600:
				_nav_smoke_fail("the ALL-filter wall never settled")
				_finish_nav_smoke()
			elif _room != null and _room.wall_ready and _nav_smoke_wait >= 4:
				_nav_leg_rail_walk()
				_nav_leg_up_down()
				_nav_leg_clearance(false)
				_nav_check_faces()
				_nav_smoke_wait = 0
				_nav_smoke_phase = 2
		2:
			if not _nav_faces_done:
				return
			var panel: ClickableQuad = _nav_bottom_row_panel()
			if panel == null:
				_nav_smoke_fail("pop leg: the wall has no bottom-row panel to pop")
				_finish_nav_smoke()
				return
			_nav_pop_panel = panel
			_room._set_focused(panel)
			_nav_smoke_wait = 0
			_nav_smoke_phase = 3
		3:
			_nav_smoke_wait += 1
			var amt: float = _room.panel_pop_amount(_nav_pop_panel)
			if amt >= 0.999:
				_nav_leg_clearance(true)
				_nav_smoke_wait = 0
				_nav_smoke_phase = 4
			elif _nav_smoke_wait > 240:
				_nav_smoke_fail("pop leg: the bottom-row panel's pop never completed (amount %.3f)" % amt)
				_finish_nav_smoke()
		4:
			_nav_smoke_wait += 1
			if _nav_smoke_wait > 3600:
				_nav_smoke_fail("the bumper leg's wall never settled")
				_finish_nav_smoke()
			elif _room != null and _room.wall_ready and _nav_smoke_wait >= 4:
				_nav_leg_bumpers()
				_finish_nav_smoke()


func _nav_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - nav smoke: ", label)
	else:
		_nav_smoke_fail(label)


func _nav_smoke_fail(label: String) -> void:
	_nav_smoke_failures += 1
	printerr("  FAIL - nav smoke: ", label)


func _finish_nav_smoke() -> void:
	if _nav_smoke_failures == 0:
		print("PVLDS NAV SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS NAV SMOKE: FAIL (%d)" % _nav_smoke_failures)
		get_tree().quit(1)


## The rail key a quad answers to, or "" when it is not a rail
## quad (a wall panel, a Launch button, anything else).
func _nav_key_of(q: ClickableQuad) -> String:
	if q == null or _room == null:
		return ""
	for k: Variant in _room._rail_quads.keys():
		if _room._rail_quads[k] == q:
			return str(k)
	return ""


func _nav_leg_rail_walk() -> void:
	var order: Array[String] = [
		"filter:all", "filter:vr", "filter:favorites", "filter:recents",
		"sort", "page_prev", "page_next", "desk", "exit"]
	_room._set_focused(_room.rail_quad(order[0]))
	for i: int in range(1, order.size()):
		_room._move_focus(Vector2(1.0, 0.0))
		_nav_expect(_nav_key_of(_room.focused_quad()) == order[i],
			"rail walk right: step %d lands on %s (got '%s')" % [i, order[i], _nav_key_of(_room.focused_quad())])
	_room._move_focus(Vector2(1.0, 0.0))
	_nav_expect(_nav_key_of(_room.focused_quad()) == order[order.size() - 1],
		"rail walk right: the end of the rail holds focus")
	for i: int in range(order.size() - 2, -1, -1):
		_room._move_focus(Vector2(-1.0, 0.0))
		_nav_expect(_nav_key_of(_room.focused_quad()) == order[i],
			"rail walk left: step lands on %s (got '%s')" % [order[i], _nav_key_of(_room.focused_quad())])
	_room._move_focus(Vector2(-1.0, 0.0))
	_nav_expect(_nav_key_of(_room.focused_quad()) == order[0],
		"rail walk left: the start of the rail holds focus")


func _nav_leg_up_down() -> void:
	for key: String in ["sort", "filter:favorites", "desk"]:
		_room._set_focused(_room.rail_quad(key))
		_room._move_focus(Vector2(0.0, -1.0))
		var up: ClickableQuad = _room.focused_quad()
		_nav_expect(up != null and (_room._panels.has(up) or _room._panel_launches.has(up)),
			"up from %s enters the card grid" % key)
		var back: bool = false
		for press: int in range(3):
			_room._move_focus(Vector2(0.0, 1.0))
			var f: ClickableQuad = _room.focused_quad()
			if f != null and _nav_key_of(f) != "":
				back = true
				break
			_nav_expect(f != null and (_room._panels.has(f) or _room._panel_launches.has(f)),
				"down from the grid stays in the grid until the rail (from %s)" % key)
		_nav_expect(back, "down from the grid's bottom row returns to the rail (from %s)" % key)


func _nav_bottom_row_panel() -> ClickableQuad:
	if _room == null or _room._panels.is_empty():
		return null
	var rows: int = int(ceil(float(_room._panels.size()) / float(RoomView.PAGE_COLS)))
	var first_bottom: int = (rows - 1) * RoomView.PAGE_COLS
	var mid: int = mini(first_bottom + 1, _room._panels.size() - 1)
	return _room._panels[mid]


## A quad's screen-space rect from its collision box's corners,
## projected through the given camera.
func _nav_screen_rect(q: ClickableQuad, cam: Camera3D) -> Rect2:
	var size: Vector2 = Vector2.ZERO
	for child: Node in q.get_children():
		var cs: CollisionShape3D = child as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			var bs: BoxShape3D = cs.shape as BoxShape3D
			size = Vector2(bs.size.x, bs.size.y)
			break
	var half: Vector2 = size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, 0.0), Vector3(half.x, -half.y, 0.0),
		Vector3(-half.x, half.y, 0.0), Vector3(half.x, half.y, 0.0)]
	var rect: Rect2 = Rect2(cam.unproject_position(q.global_transform * corners[0]), Vector2.ZERO)
	for c: int in range(1, corners.size()):
		rect = rect.expand(cam.unproject_position(q.global_transform * corners[c]))
	return rect


func _nav_leg_clearance(popped_only: bool) -> void:
	var cam: Camera3D = _room._desk_camera
	if cam == null:
		_nav_smoke_fail("clearance: no desk camera")
		return
	var rail_rects: Array[Rect2] = []
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null:
			rail_rects.append(_nav_screen_rect(rq, cam))
	var rows: int = int(ceil(float(_room._panels.size()) / float(RoomView.PAGE_COLS)))
	var first_bottom: int = (rows - 1) * RoomView.PAGE_COLS
	for i: int in range(_room._panels.size()):
		var panel: ClickableQuad = _room._panels[i]
		var launch: ClickableQuad = _room._panel_launches[i] if i < _room._panel_launches.size() else null
		if not popped_only:
			# The name strip: panel-local arithmetic first (exact,
			# camera-free), then the projected midpoints agree.
			var strip_top: float = -RoomView.PANEL_SIZE.y * 0.5 \
				+ RoomView.PANEL_SIZE.y * (float(CardFace.ART_STRIP_HEIGHT_PX) / 640.0)
			if launch != null:
				var btn_bottom: float = launch.position.y - RoomView.PANEL_LAUNCH_SIZE.y * 0.5
				_nav_expect(btn_bottom >= strip_top + 0.01,
					"panel %d: Launch button clears the name strip in panel space (bottom %.4f, strip top %.4f)" % [i, btn_bottom, strip_top])
				var btn_mid: Vector2 = cam.unproject_position(
					launch.global_transform * Vector3(0.0, -RoomView.PANEL_LAUNCH_SIZE.y * 0.5, 0.0))
				var strip_mid: Vector2 = cam.unproject_position(
					panel.global_transform * Vector3(0.0, strip_top, 0.0))
				_nav_expect(btn_mid.y < strip_mid.y,
					"panel %d: Launch button projects above the name strip (%.1f over %.1f)" % [i, btn_mid.y, strip_mid.y])
		if i < first_bottom:
			continue
		if popped_only and panel != _nav_pop_panel:
			continue
		var targets: Array[ClickableQuad] = [panel]
		if launch != null:
			targets.append(launch)
		for t: ClickableQuad in targets:
			var rect: Rect2 = _nav_screen_rect(t, cam)
			for r: int in range(rail_rects.size()):
				_nav_expect(not rect.intersects(rail_rects[r]),
					"bottom row panel %d (%s) clears rail quad %d in screen space" % [i, t.action_id, r])


## Leg 4 (async - the face render awaits a frame): a title
## card's content still starts at the texture's top row.
func _nav_check_faces() -> void:
	_nav_faces_done = false
	if _scanner == null or _scanner.games.is_empty():
		_nav_smoke_fail("faces: no scanned games to render")
		_nav_faces_done = true
		return
	var game: GameEntry = _scanner.games[0]
	var tex: Texture2D = await _factory.render_texture(RoomSpecs.panel_spec(game, _state), Vector2i(512, 640))
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		_nav_smoke_fail("faces: the title-card render came back empty")
		_nav_faces_done = true
		return
	var bg: Color = RoomSpecs.CARD_BG
	var first_row: int = -1
	for y: int in range(img.get_height()):
		for x: int in range(0, img.get_width(), 8):
			var px: Color = img.get_pixel(x, y)
			if absf(px.r - bg.r) > 0.02 or absf(px.g - bg.g) > 0.02 or absf(px.b - bg.b) > 0.02:
				first_row = y
				break
		if first_row >= 0:
			break
	_nav_expect(first_row == 0, "faces: title card content registers at texture row 0 (got %d)" % first_row)
	_nav_faces_done = true


## Leg 5: bumper page travel, driven through RoomView's
## _bumper_page - the same call the pad poll makes on a fresh
## shoulder edge - so the state gating (load wait, placard,
## detail view) is exercised exactly as the room enforces it.
## The harness library spans three pages on ALL (full, full,
## one-panel short), pinned by run_nav_smoke.sh's stub count.
func _nav_leg_bumpers() -> void:
	var pages: int = _room.page_count()
	_nav_expect(pages >= 3, "bumpers: the harness library spans at least 3 pages (got %d)" % pages)
	if pages < 2 or _room._visible_games.is_empty():
		return
	var filter0: String = _room._filter
	var sort0: String = _room._sort
	var last_page: int = pages - 1
	_nav_expect(_room._page == 0, "bumpers: the leg starts on page 1")
	# Travel, with focus keeping its grid slot.
	_room._set_focused(_room._panels[5])
	_room._bumper_page(1)
	_nav_expect(_room._page == 1, "bumpers: RB advances to page 2")
	_nav_expect(_room.focused_quad() == _room._panels[5],
		"bumpers: focus keeps its grid slot across the flip")
	_room._bumper_page(1)
	_nav_expect(_room._page == last_page, "bumpers: RB advances to the last page")
	_nav_expect(_room.focused_quad() == _room._panels[_room._panels.size() - 1],
		"bumpers: the short last page clamps focus to its last panel")
	# Clamped at the far end: no wrap, focus instance untouched.
	var held: ClickableQuad = _room.focused_quad()
	_room._bumper_page(1)
	_nav_expect(_room._page == last_page, "bumpers: RB clamps on the last page (no wrap)")
	_nav_expect(_room.focused_quad() == held, "bumpers: a clamped RB leaves focus untouched")
	_room._bumper_page(-1)
	_nav_expect(_room._page == last_page - 1, "bumpers: LB retreats a page")
	_room._bumper_page(-1)
	_nav_expect(_room._page == 0, "bumpers: LB retreats to page 1")
	held = _room.focused_quad()
	_room._bumper_page(-1)
	_nav_expect(_room._page == 0, "bumpers: LB clamps on page 1 (no wrap)")
	_nav_expect(_room.focused_quad() == held, "bumpers: a clamped LB leaves focus untouched")
	_nav_expect(_room._filter == filter0 and _room._sort == sort0,
		"bumpers: page travel leaves filter and sort alone")
	# Focus on a rail stop carries to the same stop.
	_room._set_focused(_room.rail_quad("sort"))
	_room._bumper_page(1)
	_nav_expect(_room._page == 1 and _nav_key_of(_room.focused_quad()) == "sort",
		"bumpers: rail focus carries to the same stop across the flip")
	_room._bumper_page(-1)
	# No focus lands on the first panel.
	_room._set_focused(null)
	_room._bumper_page(1)
	_nav_expect(_room._page == 1 and _room.focused_quad() == _room._panels[0],
		"bumpers: no focus lands on the first panel")
	_room._bumper_page(-1)
	# Inert while the SETUP placard stands.
	_room.show_setup_placard("nav smoke")
	_room._bumper_page(1)
	_room._bumper_page(-1)
	_nav_expect(_room._page == 0, "bumpers: inert while the SETUP placard stands")
	_room.clear_setup_placard()
	# Inert in the detail view.
	var game: GameEntry = _room._visible_games[0]
	_room._open_detail(game)
	_room._bumper_page(1)
	_nav_expect(_room._mode == "detail" and _room._page == 0,
		"bumpers: inert in the detail view")
	_room._on_detail_closed()
	# Inert during the load wait. begin_launch is driven
	# directly: no launch was requested, so Main's hand-off
	# poll (which keys off a real spawn) never engages.
	_room.begin_launch(game)
	_room._bumper_page(1)
	_room._bumper_page(-1)
	_nav_expect(_room._page == 0 and _room.is_launch_in_wait(),
		"bumpers: inert during the load wait")
	_room.end_launch_failed(game, "nav smoke")
	_nav_expect(_room._page == 0 and _room._filter == filter0,
		"bumpers: the leg leaves the wall on page 1, filter untouched")


# -------------------------------------------------- desk smoke

## --pvlds-smoke-desk: the desk's session switch is a live
## setting - flipping it must rewrite the config file on disk
## immediately, with no Save & Scan. The boot route with this
## flag lands on the desk and stays there (no scan, no room).
## The driver asserts the stricken close/hold controls are
## absent, flips the herding checkbox through its real toggled
## signal, then re-reads the config FILE with a fresh
## PvldsConfig and asserts what landed - plus that the fields a
## flip does not own (exe path, folders) survived, and that the
## saved file carries none of the stricken keys.
func _drive_desk_smoke() -> void:
	match _desk_smoke_phase:
		0:
			if _desk != null:
				# The starting point, straight off the disk the
				# boot read (the harness's scratch config beside
				# the exported binary).
				var before: PvldsConfig = PvldsConfig.new()
				_desk_expect(before.load_from_disk(), "the scratch config loads")
				_desk_expect(not before.focus_herding, "the scratch config starts with herding off")
				# The stricken controls are ABSENT: no Close VPX
				# checkbox (the watchdog's close duty is
				# unconditional now), no Hold-to-exit checkbox,
				# no hold-button picker (there is no hold gesture).
				_desk_expect(_desk._close_check == null, "the desk has no Close VPX checkbox")
				_desk_expect(_desk._hold_check == null, "the desk has no Hold-to-exit checkbox")
				_desk_expect(_desk._hold_button_picker == null, "the desk has no hold-button picker")
				# Flip the one surviving switch through its real
				# control and signal.
				_desk._herding_check.button_pressed = true
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
				_desk_expect(_config.focus_herding, "the herding flip is in Main's config immediately")
				# Then the file itself - the whole point of the round.
				var after: PvldsConfig = PvldsConfig.new()
				_desk_expect(after.load_from_disk(), "the config file still loads after the flip")
				_desk_expect(after.focus_herding, "the config FILE has herding on, no Save & Scan pressed")
				_desk_expect(after.vpx_exe_path == _config.vpx_exe_path and after.table_folders == _config.table_folders,
					"fields the flip does not own (exe path, folders) are untouched on disk")
				# And the save is clean of the stricken keys: the
				# simplified exit model writes no close/hold fields.
				var raw: String = FileAccess.get_file_as_string(PvldsConfig.existing_path())
				_desk_expect(not raw.contains("close_vpx_on_table_exit"), "the saved config carries no close_vpx_on_table_exit key")
				_desk_expect(not raw.contains("hold_exit_enabled"), "the saved config carries no hold_exit_enabled key")
				_desk_expect(not raw.contains("hold_exit_button"), "the saved config carries no hold_exit_button key")
				# Missing-backglass row (this round): the count
				# line + Open list button beside the scan summary.
				# This boot never runs a scan, so the driver feeds
				# counts through the same apply_missing_b2s call
				# _finish_scan makes in a real boot, then presses
				# the REAL button - the emit runs the desk's
				# pressed -> handler -> OS.shell_open wiring end
				# to end (the open itself lands outside, on the
				# OS's default handler, unobservable headless;
				# reaching _finish_desk_smoke is the proof the
				# press ran clean).
				_desk_expect(_desk._b2s_button != null and _desk._b2s_button.text == "Open list",
					"the desk has an Open list button")
				_desk_expect(_desk._b2s_button != null and _desk._b2s_button.disabled,
					"the Open list button starts disabled (no scan yet)")
				_desk_expect(_desk._b2s_label != null and _desk._b2s_label.text.contains("not scanned yet"),
					"the missing-backglass line starts unscanned")
				_desk.apply_missing_b2s(3)
				_desk_expect(_desk._b2s_label.text.contains("3 table file(s)"),
					"the missing-backglass line shows the applied count")
				_desk_expect(not _desk._b2s_button.disabled,
					"the Open list button arms once a count lands")
				_desk.apply_missing_b2s(0)
				_desk_expect(_desk._b2s_label.text.contains("none - every table file"),
					"a zero count says none plainly")
				var smoke_paths: Array[String] = ["/tables/Alpha.vpx", "/tables/Beta.vpx", "/other/Gamma.vpx"]
				_desk_expect(MissingB2sList.write_file(smoke_paths, "2026-10-23") == OK
					and FileAccess.file_exists(MissingB2sList.FILE_PATH),
					"the list file exists at the path the button opens")
				_desk_expect(MissingB2sList.globalized_path().ends_with("missing_b2s.txt"),
					"the button's open path resolves to missing_b2s.txt")
				_desk.apply_missing_b2s(3)
				_desk._b2s_button.pressed.emit()
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


# -------------------------------------------------- dpadexit smoke

## --pvlds-smoke-dpadexit: the room half of the two-rule exit
## model. A FRESH D-pad Right press in the room (browsing) is the
## BACK-out: it must run the rail EXIT path - disarm ("room Exit")
## + quit - through the room's real gamepad poll, fed here by a
## synthetic InputEventJoypadButton (the lockout smoke's feed).
## Success quits the process from inside _on_exit_requested
## before this driver can print a verdict, so the PASS evidence
## lives outside: the harness sees exit code 0 and reads the
## disarm + its reason off the contract file. If the press does
## nothing, the driver survives to phase 2 and fails loudly.
## The held leg (--pvlds-smoke-dpadexit-held) drives the
## baseline-arming contract instead: the button was pinned in
## _ready, before the room instance's first poll, so no exit may
## fire while it sits pressed (the driver surviving the pinned
## stretch IS the assertion - a phantom exit kills the driver
## with the app, and the harness fails on the missing survival
## line); after the release, a fresh press must exit as usual.
func _drive_dpadexit_smoke() -> void:
	if _dpadexit_held_leg:
		_drive_dpadexit_held()
	else:
		_drive_dpadexit_fresh()


func _drive_dpadexit_fresh() -> void:
	match _dpadexit_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				var press: InputEventJoypadButton = InputEventJoypadButton.new()
				press.device = 0
				press.button_index = JOY_BUTTON_DPAD_RIGHT
				press.pressed = true
				Input.parse_input_event(press)
				print("  info - dpadexit smoke: fresh D-pad Right injected into the room")
				_dpadexit_smoke_wait = 0
				_dpadexit_smoke_phase = 1
			else:
				_dpadexit_smoke_wait += 1
				if _dpadexit_smoke_wait > 3600:
					printerr("PVLDS DPAD EXIT SMOKE: FAIL - the room never came up")
					get_tree().quit(1)
		1:
			_dpadexit_smoke_wait += 1
			if _dpadexit_smoke_wait == 2:
				var release: InputEventJoypadButton = InputEventJoypadButton.new()
				release.device = 0
				release.button_index = JOY_BUTTON_DPAD_RIGHT
				release.pressed = false
				Input.parse_input_event(release)
			if _dpadexit_smoke_wait > 30:
				printerr("PVLDS DPAD EXIT SMOKE: FAIL - a fresh D-pad Right press in the room did not exit the app")
				get_tree().quit(1)


func _drive_dpadexit_held() -> void:
	match _dpadexit_smoke_phase:
		0:
			# Room up: start counting the pinned stretch. The
			# button has read pressed since before this instance
			# existed - if the exit were going to fire on it, it
			# fires in the first polls after the room comes up.
			if _room != null and _room.visible and _room.wall_ready:
				_dpadexit_smoke_wait = 0
				_dpadexit_smoke_phase = 1
			else:
				_dpadexit_smoke_wait += 1
				if _dpadexit_smoke_wait > 3600:
					printerr("PVLDS DPAD EXIT SMOKE: FAIL - the room never came up (held leg)")
					get_tree().quit(1)
		1:
			_dpadexit_smoke_wait += 1
			if _dpadexit_smoke_wait >= 90:
				# Survived 90 frames pinned. (A phantom exit would
				# have killed the process - and this driver - long
				# before this print; the harness asserts the line.)
				print("  info - dpadexit smoke: held leg survived 90 frames pinned - releasing")
				var release: InputEventJoypadButton = InputEventJoypadButton.new()
				release.device = 0
				release.button_index = JOY_BUTTON_DPAD_RIGHT
				release.pressed = false
				Input.parse_input_event(release)
				_dpadexit_smoke_wait = 0
				_dpadexit_smoke_phase = 2
		2:
			_dpadexit_smoke_wait += 1
			if _dpadexit_smoke_wait >= 10:
				# Released polls witnessed: a fresh press now must
				# exit through the rail path, arming or not.
				var press: InputEventJoypadButton = InputEventJoypadButton.new()
				press.device = 0
				press.button_index = JOY_BUTTON_DPAD_RIGHT
				press.pressed = true
				Input.parse_input_event(press)
				print("  info - dpadexit smoke: held leg - fresh D-pad Right injected after the release")
				_dpadexit_smoke_wait = 0
				_dpadexit_smoke_phase = 3
		3:
			_dpadexit_smoke_wait += 1
			if _dpadexit_smoke_wait == 2:
				var release2: InputEventJoypadButton = InputEventJoypadButton.new()
				release2.device = 0
				release2.button_index = JOY_BUTTON_DPAD_RIGHT
				release2.pressed = false
				Input.parse_input_event(release2)
			if _dpadexit_smoke_wait > 30:
				printerr("PVLDS DPAD EXIT SMOKE: FAIL - after a witnessed release, a fresh D-pad Right press did not exit the app (held leg)")
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


## --pvlds-smoke-quitwarm: the exit-hang harness driver. Mode
## "quit" (default): once the post-scan warm has banked a few
## extractions and is still chewing, drop a marker file (env
## PVLDS_QUITWARM_MARKER - the shell times from its appearance,
## immune to stdout buffering) and exit through the REAL rail
## path, _on_exit_requested - the exact handler the room's EXIT
## fires. Mode "drain" (PVLDS_QUITWARM_MODE=drain): let the warm
## finish, report the pass's wall duration, exit the same way.
func _drive_quitwarm_smoke() -> void:
	if _quitwarm_fired or _scan_active or _scanner == null or _art_warmer == null:
		return
	if _quitwarm_started_msec == 0:
		_quitwarm_started_msec = Time.get_ticks_msec()
	var elapsed: int = Time.get_ticks_msec() - _quitwarm_started_msec
	var total: int = 0
	var cached: int = 0
	for g: GameEntry in _scanner.games:
		if g.art_source_path == "":
			continue
		total += 1
		if ArtProvider.is_cached(g.art_source_path):
			cached += 1
	if OS.get_environment("PVLDS_QUITWARM_MODE") == "drain":
		if total > 0 and cached == total and _art_warmer.is_idle():
			_quitwarm_fired = true
			print("PVLDS QUITWARM: drained pass_msec=%d cached=%d of %d" % [_art_warmer.last_pass_msec, cached, total])
			_on_exit_requested()
		elif elapsed > 300000:
			_quitwarm_fired = true
			printerr("PVLDS QUITWARM: FAIL - the warm did not drain in 300s (cached %d of %d)" % [cached, total])
			get_tree().quit(1)
		return
	if cached >= 3 and not _art_warmer.is_idle():
		_quitwarm_fired = true
		print("PVLDS QUITWARM: quit requested (cached=%d of %d)" % [cached, total])
		var marker: String = OS.get_environment("PVLDS_QUITWARM_MARKER")
		if marker != "":
			var mf: FileAccess = FileAccess.open(marker, FileAccess.WRITE)
			if mf != null:
				mf.store_string("quit requested: cached=%d of %d\n" % [cached, total])
				mf.close()
		_on_exit_requested()
	elif elapsed > 180000:
		_quitwarm_fired = true
		printerr("PVLDS QUITWARM: FAIL - the warm never got under way (cached %d of %d)" % [cached, total])
		get_tree().quit(1)


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


## Recursive delete of a core-test fixture tree (absolute OS
## path). Missing paths are a no-op, so a test can wipe before
## building its fixtures and again when it is done with them.
func _wipe_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for sub: String in dir.get_directories():
		_wipe_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


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

	# Missing-backglass record (this round): pairing truth from the
	# same dummy listing. Only Pharaoh's Ledger carries a .directb2s
	# beside its .vpx - a side image is NOT a backglass and does not
	# clear a file here.
	_expect(scanner.missing_b2s_files.size() == 12, "dummy library: 12 of 13 files have no .directb2s beside them", failures)
	_expect(not scanner.missing_b2s_files.has(dummy_tables.path_join("Pharaoh's Ledger (Vantage 1979) JP v55 DT-FS-VR-MR Ext2k Conversion.vpx")),
		"the one dummy file with a backglass is not in the missing list", failures)
	_expect(scanner.missing_b2s_files.has(dummy_tables.path_join("Neon Harbor (Copperline 1989).vpx")),
		"a side image does not clear a file from the missing list", failures)

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
	contract.runtime_seen_unix = 2345678
	contract.launcher_path = "C:/PVLDS/PVLDS.exe"
	contract.focus_herding = false
	contract.disarm_reason = "room Exit"
	_expect(contract.save_to_disk(), "watchdog contract saves", failures)
	var contract2: WatchdogContract = WatchdogContract.load_from_disk()
	_expect(contract2.armed and contract2.session_id == 7 and contract2.game_pid == 4242
		and contract2.session_state == "live" and contract2.game_window_seen_unix == 1234567
		and contract2.runtime_seen_unix == 2345678
		and not contract2.focus_herding
		and contract2.launcher_path == "C:/PVLDS/PVLDS.exe",
		"watchdog contract round-trips (incl. the window-seen and runtime stamps)", failures)
	_expect(contract2.disarm_reason == "room Exit",
		"the disarm reason round-trips with the contract", failures)
	# The simplified exit model writes NO close-duty or hold keys
	# (the close duty is unconditional; hold was stricken) - and a
	# contract that still CARRIES the old keys (written by an older
	# build) loads without a murmur: both readers ignore them.
	var written: Dictionary = contract.to_dictionary()
	_expect(not written.has("close_vpx_on_table_exit") and not written.has("hold_exit_enabled")
		and not written.has("hold_exit_button"),
		"the written contract carries no close-duty or hold keys", failures)
	_expect(_write_text_file(contract_file, "{\"session_state\": \"live\", \"close_vpx_on_table_exit\": false, \"hold_exit_enabled\": false, \"hold_exit_button\": \"y\"}"),
		"legacy contract with the stricken keys written", failures)
	var legacy_keys: WatchdogContract = WatchdogContract.load_from_disk()
	_expect(legacy_keys.session_state == "live",
		"a contract carrying the stricken keys loads (they are ignored)", failures)
	# And the disarm reason: no key, empty string - the watchdog
	# falls back to its legacy generic in the stand-down line.
	_expect(legacy_keys.disarm_reason == "",
		"a contract without the disarm-reason key loads it empty", failures)
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
	# The stricken exit-model keys: a config that still CARRIES
	# them (written by an older build) loads cleanly - they are
	# simply not read - and the next save writes a file without
	# them. There are no close-duty or hold settings any more:
	# the watchdog's close is unconditional and hold is gone.
	_expect(_write_text_file(config_file, JSON.stringify({
		"close_vpx_on_table_exit": false,
		"hold_exit_enabled": false,
		"hold_exit_button": "y",
		"focus_herding": false,
	})), "legacy config with the stricken keys written", failures)
	var legacy_cfg: PvldsConfig = PvldsConfig.new()
	_expect(legacy_cfg.load_from_disk() and not legacy_cfg.focus_herding,
		"a config carrying the stricken keys loads (they are ignored)", failures)
	_expect(legacy_cfg.save_to_disk(), "legacy config saves", failures)
	var saved_raw: String = FileAccess.get_file_as_string(config_file)
	_expect(not saved_raw.contains("close_vpx_on_table_exit") and not saved_raw.contains("hold_exit_enabled")
		and not saved_raw.contains("hold_exit_button"),
		"the saved config carries none of the stricken keys", failures)
	var resaved_cfg: PvldsConfig = PvldsConfig.new()
	_expect(resaved_cfg.load_from_disk() and not resaved_cfg.focus_herding,
		"the cleaned config round-trips through save", failures)
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
	# The stop request (exit-hang round): a pass abandoned at an
	# item boundary leaves the rest of its queue unextracted, keeps
	# what it finished, and does not poison the next pass. Forty
	# fixtures make a pass that measurably outlasts the request.
	var count_cached: Callable = func(games: Array[GameEntry]) -> int:
		var n: int = 0
		for ge: GameEntry in games:
			if ge.art_source_path != "" and ArtProvider.is_cached(ge.art_source_path):
				n += 1
		return n
	var stop_entries: Array[GameEntry] = []
	for si: int in range(40):
		var sp: String = art_dir.path_join("Stop Table %02d.directb2s" % si)
		_expect(bool(mk_b2s.call(sp, 400, 500)), "stop fixture %02d written" % si, failures)
		var sentry: GameEntry = GameEntry.new()
		sentry.art_source_path = sp
		stop_entries.append(sentry)
	var stop_warmer: ArtWarmer = ArtWarmer.new()
	stop_warmer.warm_library(stop_entries)
	var swait: int = 0
	while int(count_cached.call(stop_entries)) == 0 and swait < 10000:
		OS.delay_msec(10)
		swait += 10
	stop_warmer.request_stop()
	swait = 0
	while not stop_warmer.is_idle() and swait < 30000:
		OS.delay_msec(20)
		swait += 20
	var stopped_cached: int = int(count_cached.call(stop_entries))
	_expect(stop_warmer.is_idle(), "a stopped warm pass goes idle", failures)
	_expect(stopped_cached > 0 and stopped_cached < stop_entries.size(),
		"the stop abandoned the queue mid-pass (%d of %d extracted)" % [stopped_cached, stop_entries.size()], failures)
	# A later warm (the next boot, in the field) finishes the job:
	# the stop flag must not leak into it.
	stop_warmer.warm_library(stop_entries)
	swait = 0
	while not stop_warmer.is_idle() and swait < 60000:
		OS.delay_msec(20)
		swait += 20
	_expect(int(count_cached.call(stop_entries)) == stop_entries.size(),
		"a fresh warm after a stop completes the queue", failures)
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
	# Extractor v2 (this round): the entity-escaped payload. Real
	# designer files wrap the base64 at 76 characters and store each
	# wrap's CRLF inside the attribute as &#xD;&#xA; - a real XML
	# parser decodes them automatically; the v1 raw-text reader fed
	# the escapes to the strict base64 decoder, which refused the
	# whole blob, and the file stamped failed (255 of Chris's 281
	# backglasses). This fixture is exactly that shape, with every
	# '+' additionally escaped as the decimal reference &#43; to
	# exercise the general numeric path.
	_expect(ArtProvider._xml_unescape("a&#xD;&#xA;b&#43;c&amp;d") == "a\r\nb+c&d",
		"the unescape decodes hex, decimal, and named references (amp last)", failures)
	var esc_img: Image = mk_img.call(400, 500) as Image
	var esc_raw: String = Marshalls.raw_to_base64(esc_img.save_png_to_buffer())
	var esc_wrapped: String = ""
	var esc_i: int = 0
	while esc_i < esc_raw.length():
		if esc_i > 0:
			esc_wrapped += "&#xD;&#xA;"
		esc_wrapped += esc_raw.substr(esc_i, 76).replace("+", "&#43;")
		esc_i += 76
	var b2s_esc: String = art_dir.path_join("Escaped Table.directb2s")
	_expect(_write_text_file(b2s_esc, "<DirectB2SData><Images><BackglassImage Value=\"" + esc_wrapped + "\" /></Images></DirectB2SData>"),
		"entity-escaped fixture written", failures)
	var esc_cache: String = ArtProvider.extract_directb2s_image(b2s_esc)
	var esc_out: Image = Image.new()
	_expect(esc_cache != "" and esc_out.load(esc_cache) == OK and esc_out.get_width() == 400 and esc_out.get_height() == 500
		and ArtProvider.outcome_for(b2s_esc) == ArtProvider.STATUS_OK,
		"an entity-escaped backglass extracts under the v2 reader (400x500, unscaled)", failures)
	# Extractor-version migration: an index entry written by the
	# old reader (no "v" field = v1) counts as untried under v2, so
	# a file v1 stamped failed gets its one retry - and the retry's
	# record carries the new version, so it settles.
	var b2s_mig: String = art_dir.path_join("Migrated Table.directb2s")
	_expect(bool(mk_b2s.call(b2s_mig, 400, 500)), "migration fixture written", failures)
	var mig_key: String = ArtProvider.stamp_key_for(b2s_mig)
	var idx_path: String = "user://art_cache/art_index.json"
	var planted: Dictionary = {}
	var idx_text: String = FileAccess.get_file_as_string(idx_path)
	if idx_text != "":
		var parsed_idx: Variant = JSON.parse_string(idx_text)
		if parsed_idx is Dictionary:
			planted = parsed_idx as Dictionary
	planted[mig_key] = {"status": "failed", "src": b2s_mig}
	_expect(_write_text_file(idx_path, JSON.stringify(planted)), "v1 failed entry planted", failures)
	ArtProvider.reload_index()
	_expect(ArtProvider.outcome_for(b2s_mig) == "", "a v1 failed entry reads as untried under extractor v2", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_mig) != "" and ArtProvider.outcome_for(b2s_mig) == ArtProvider.STATUS_OK,
		"the migrated file extracts on retry and records ok", failures)
	var after_idx: Dictionary = {}
	var parsed_after: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx_path))
	if parsed_after is Dictionary:
		after_idx = parsed_after as Dictionary
	var after_entry: Variant = after_idx.get(mig_key, null)
	_expect(after_entry is Dictionary and int((after_entry as Dictionary).get("v", 0)) == ArtProvider.EXTRACTOR_VERSION,
		"the retried entry is stamped with the current extractor version", failures)

	# --- Missing-backglass list (this round): the scanner's
	# pairing record rendered and written as Chris's go-download
	# list. The fixture is built so file-name order and folder-path
	# order DISAGREE (Mango sits in the path-first folder), pinning
	# the sort to names, and one game (Duo) has two builds of which
	# only one lacks a backglass - the list is per-FILE truth.
	var b2s_root_user: String = "user://core_test_b2s"
	var b2s_root: String = ProjectSettings.globalize_path(b2s_root_user)
	_wipe_tree(b2s_root)
	var b2s_user_dir: DirAccess = DirAccess.open("user://")
	_expect(b2s_user_dir != null, "b2s fixture: user dir opens", failures)
	if b2s_user_dir != null and not b2s_user_dir.dir_exists("core_test_b2s"):
		b2s_user_dir.make_dir("core_test_b2s")
	var b2s_root_dir: DirAccess = DirAccess.open(b2s_root_user)
	_expect(b2s_root_dir != null, "b2s fixture: root created", failures)
	if b2s_root_dir != null:
		var fx_subs: Array[String] = ["aaa_tables", "zzz_tables", "solo"]
		for sub_name: String in fx_subs:
			if not b2s_root_dir.dir_exists(sub_name):
				b2s_root_dir.make_dir(sub_name)
	var fx_aaa: String = b2s_root_user.path_join("aaa_tables")
	var fx_zzz: String = b2s_root_user.path_join("zzz_tables")
	var fx_solo: String = b2s_root_user.path_join("solo")
	var mango_path: String = fx_aaa.path_join("Mango Table (Maker 1980).vpx")
	var zebra_path: String = fx_aaa.path_join("Zebra Table (Maker 2000).vpx")
	var apple_path: String = fx_zzz.path_join("Apple Table (Maker 1990).vpx")
	var duo10_path: String = fx_zzz.path_join("Duo Game (Maker 1995) v1.0.vpx")
	var duo11_path: String = fx_zzz.path_join("Duo Game (Maker 1995) v1.1.vpx")
	_expect(_write_text_file(mango_path, "fixture"), "b2s fixture: Mango written (no backglass)", failures)
	_expect(_write_text_file(zebra_path, "fixture"), "b2s fixture: Zebra written", failures)
	_expect(_write_text_file(fx_aaa.path_join("Zebra Table (Maker 2000).directb2s"), "fixture"), "b2s fixture: Zebra backglass written", failures)
	_expect(_write_text_file(apple_path, "fixture"), "b2s fixture: Apple written (no backglass yet)", failures)
	_expect(_write_text_file(duo10_path, "fixture"), "b2s fixture: Duo v1.0 written", failures)
	_expect(_write_text_file(fx_zzz.path_join("Duo Game (Maker 1995) v1.0.directb2s"), "fixture"), "b2s fixture: Duo v1.0 backglass written", failures)
	_expect(_write_text_file(duo11_path, "fixture"), "b2s fixture: Duo v1.1 written (no backglass)", failures)
	_expect(_write_text_file(fx_solo.path_join("Solo Table (Maker 1977).vpx"), "fixture"), "b2s fixture: Solo written", failures)
	_expect(_write_text_file(fx_solo.path_join("Solo Table (Maker 1977).directb2s"), "fixture"), "b2s fixture: Solo backglass written", failures)
	var fx_folders: Array[String] = [fx_aaa, fx_zzz]
	var fx_scan: LibraryScanner = LibraryScanner.new()
	fx_scan.scan(fx_folders, db)
	_expect(fx_scan.total_files == 5, "b2s fixture: 5 table files scanned", failures)
	_expect(fx_scan.missing_b2s_files.size() == 3, "b2s fixture: exactly 3 files are missing a backglass", failures)
	_expect(fx_scan.missing_b2s_files.has(apple_path) and fx_scan.missing_b2s_files.has(duo11_path)
		and fx_scan.missing_b2s_files.has(mango_path), "b2s fixture: the missing set is Apple, Duo v1.1, Mango", failures)
	_expect(not fx_scan.missing_b2s_files.has(zebra_path) and not fx_scan.missing_b2s_files.has(duo10_path),
		"b2s fixture: backglassed files are not listed", failures)
	var duo_entry: GameEntry = null
	for g: GameEntry in fx_scan.games:
		for b: TableBuild in g.builds:
			if b.file_path == duo11_path:
				duo_entry = g
	_expect(duo_entry != null and duo_entry.builds.size() == 2,
		"b2s fixture: the Duo builds group as one game, and the list still names only the b2s-less build", failures)
	var expected_list: String = "PVLDS - table files with no backglass file (.directb2s)\nScan date: 2026-10-23\nMissing: 3\n\n"
	expected_list += "Apple Table (Maker 1990).vpx  (folder: %s)\n" % fx_zzz
	expected_list += "Duo Game (Maker 1995) v1.1.vpx  (folder: %s)\n" % fx_zzz
	expected_list += "Mango Table (Maker 1980).vpx  (folder: %s)\n" % fx_aaa
	_expect(MissingB2sList.render(fx_scan.missing_b2s_files, "2026-10-23") == expected_list,
		"the rendered list: header with count + date, file-name sort across folders, per-file lines", failures)
	# The written file (the real list path is backed up + restored,
	# like the state and contract round-trips above).
	var list_file: String = MissingB2sList.FILE_PATH
	var list_backup: String = ""
	if FileAccess.file_exists(list_file):
		list_backup = FileAccess.get_file_as_string(list_file)
	_expect(MissingB2sList.write_file(fx_scan.missing_b2s_files, "2026-10-23") == OK, "the list file writes", failures)
	_expect(FileAccess.get_file_as_string(list_file) == expected_list, "the written file matches the render byte for byte", failures)
	# Zero-missing library: the file states it plainly.
	var solo_folders: Array[String] = [fx_solo]
	var solo_scan: LibraryScanner = LibraryScanner.new()
	solo_scan.scan(solo_folders, db)
	_expect(solo_scan.missing_b2s_files.is_empty(), "b2s fixture: a fully-backglassed library scans zero missing", failures)
	var zero_render: String = MissingB2sList.render(solo_scan.missing_b2s_files, "2026-10-23")
	_expect(zero_render.contains("Missing: 0") and zero_render.contains("None missing - every table file has a .directb2s beside it."),
		"the zero list states none missing plainly", failures)
	# Regeneration: add Apple's backglass, rescan, rewrite - the
	# entry is gone from the file, not just from the record.
	_expect(_write_text_file(fx_zzz.path_join("Apple Table (Maker 1990).directb2s"), "fixture"), "b2s fixture: Apple backglass added", failures)
	var fx_rescan: LibraryScanner = LibraryScanner.new()
	fx_rescan.scan(fx_folders, db)
	_expect(fx_rescan.missing_b2s_files.size() == 2 and not fx_rescan.missing_b2s_files.has(apple_path),
		"after adding the backglass and rescanning, the record drops the entry", failures)
	_expect(MissingB2sList.write_file(fx_rescan.missing_b2s_files, "2026-10-23") == OK, "the list regenerates on rescan", failures)
	var regen_text: String = FileAccess.get_file_as_string(list_file)
	_expect(regen_text.contains("Missing: 2") and not regen_text.contains("Apple Table"),
		"the regenerated file drops the cleared entry", failures)
	if list_backup != "":
		_write_text_file(list_file, list_backup)
	elif FileAccess.file_exists(list_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(list_file))
	_wipe_tree(b2s_root)

	if failures.is_empty():
		print("CORE TEST: PASS")
		get_tree().quit(0)
	else:
		printerr("CORE TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)
