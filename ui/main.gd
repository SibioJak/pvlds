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
##   --pvlds-shot-slide P
##                       room boot; force the ALL filter, flip a
##                       page on the bumpers, and capture P at the
##                       page slide's far point (the old wall at
##                       full yaw, a frame before the swap)
##   --pvlds-smoke-placard
##                       room boot; force XR on, open setup with a
##                       message, assert the placard contract (room
##                       stays up, wall inert, BACK restores), then
##                       assert the flat path is the legacy one,
##                       print the verdict, quit
##   --pvlds-smoke-setup-panel
##                       room boot; force the room's XR flag on,
##                       open SETUP through the rail, assert the
##                       in-room panel contract (a real 3D surface,
##                       modal focus, scan + stub-download legs
##                       land on it), B and D-pad Right act as
##                       BACK, BACK lands on the SETUP stop, and
##                       the flat path is still the desk, print
##                       the verdict, quit
##   --pvlds-shot-setup-panel P
##                       room boot; force the room's XR flag on,
##                       open the SETUP panel, save a screenshot
##                       of it to P once its textures land, quit
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
var _smoke_setup_panel: bool = false ## --pvlds-smoke-setup-panel: drive the in-room SETUP panel contract once the room is up
var _setup_panel_smoke_phase: int = 0
var _setup_panel_smoke_wait: int = 0
var _setup_panel_smoke_failures: int = 0
var _setup_panel_smoke_deadline_msec: int = 0
var _setup_panel_smoke_wall_before: Array[ClickableQuad] = [] ## the wall's quad instances before the panel's scan (the deferral snapshot)
var _setup_panel_smoke_tex_before: Dictionary = {} ## ClickableQuad -> the texture it wore before the scan (the cross-talk snapshot)
var _setup_panel_smoke_scan_seen: bool = false ## the scan's landing message has been seen; texture assertions wait a few frames for the landing renders to settle
var _shot_setup_panel_path: String = "" ## --pvlds-shot-setup-panel P: capture the open SETUP panel
var _shot_setup_panel_phase: int = -1
var _shot_setup_panel_frames: int = 0
var _shot_setup_panel_after_scan: bool = false ## --pvlds-shot-setup-panel-scan: run the panel's scan first, capture the post-scan room (Chris's stray framing)
var _shot_setup_panel_scan_fired: bool = false
var _shot_setup_panel_scanned: bool = false
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
var _nav_bumpers_started: bool = false ## the bumper leg runs async (it waits out each page slide); kicked off once
var _nav_bumpers_done: bool = false ## the bumper leg (async) has reported
var _nav_y_started: bool = false ## the A/Y-swap leg runs async (it rides real launch waits); kicked off once
var _nav_y_done: bool = false ## the A/Y-swap leg (async) has reported
var _nav_rail_started: bool = false ## the rail-focus leg runs async (it waits out each rebuild); kicked off once
var _nav_rail_done: bool = false ## the rail-focus leg (async) has reported
var _nav_fav_started: bool = false ## the X-favorites leg runs async (feeds + re-renders); kicked off once
var _nav_fav_done: bool = false ## the X-favorites leg (async) has reported
var _shot_slide_path: String = "" ## --pvlds-shot-slide P: capture the wall at the page slide's far point
var _shot_slide_phase: int = -1
var _shot_slide_frames: int = 0
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
var _shot_flicker_prefix: String = "" ## --pvlds-shot-flicker PREFIX: the power-on flicker's QA hook (needs the harness's bulb fixture folder)
var _shot_flicker_phase: int = -1
var _shot_flicker_frames: int = 0
var _shot_flicker_panel: ClickableQuad = null ## the bulb-bearing fixture card (layers leg)
var _shot_flicker_panel2: ClickableQuad = null ## a title-card panel (brightness fallback leg)
var _shot_flicker_since: int = 0
var _shot_flicker_counts: Array[int] = [] ## amber pixel counts across the layers cascade: [base, mid, lit]
var _shot_flicker_burst: Array[Image] = [] ## frames grabbed across the layers cascade, counted after settle (readbacks lag state under software rendering; the burst spans the lag)
var _shot_flicker_t0: int = 0 ## when the layers cascade was first seen
var _shot_flicker_next_grab: int = 0 ## next burst grab time
var _shot_flicker_min_b: float = 1.0 ## darkest face brightness seen during the fallback cascade
var _shot_flicker_min_mean: float = -1.0 ## darkest rendered mean luminance inside the fallback card's rect during its cascade
var _shot_flicker_problems: Array[String] = []
var _shot_flicker_stage: int = 0 ## sub-state inside the current phase
var _shot_flicker_game: GameEntry = null ## the bulb-bearing fixture game
var _shot_flicker_saw_partial: bool = false ## a frame with some-but-not-all layers lit was observed
var _shot_flicker_fixtures: Dictionary = {} ## fix-round legs: fixture title prefix -> {"game": GameEntry, "panel": ClickableQuad}
var _shot_flicker_spill: int = -1 ## fix round: cascade-driven amber change OUTSIDE the face across the burst (max-min), -1 until measured
var _shot_flicker_blend_alphas: Array[float] = [] ## pair-strobe leg: the pair layer's alpha, sampled every frame of its live cascade
var _shot_flicker_probe_wait: int = 0 ## pair-strobe leg: frames waited since parking the cascade clock for a rendered probe
var _shot_flicker_off_img: Image = null ## pair-strobe leg: the pair card rendered at cascade t=0 (pure Off), popped geometry
var _shot_flicker_on_img: Image = null ## pair-strobe leg: the pair card rendered at cascade end (pure On), popped geometry
var _shot_flicker_dip_win: Vector2 = Vector2.ZERO ## pair-strobe leg: the Specter schedule's dip window [dip_end, on_t]
var _shot_flicker_live_missed: bool = false ## pair-strobe leg: the live cascade finished before a poll saw phase 1 (one giant post-extraction frame) - the sweep and the rendered fit carry the leg instead
var _shot_flicker_flasher_idx: int = -1 ## flasher leg: the performing set's flasher layer index (-1 until the cascade builds it)
var _shot_flicker_armed: bool = false ## fix-round legs: the current leg's focus has been set
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
	var shot_slide_idx: int = user_args.find("--pvlds-shot-slide")
	if shot_slide_idx >= 0 and shot_slide_idx + 1 < user_args.size():
		_shot_slide_path = user_args[shot_slide_idx + 1]
		_shot_slide_phase = 0
	var shot_flicker_idx: int = user_args.find("--pvlds-shot-flicker")
	if shot_flicker_idx >= 0 and shot_flicker_idx + 1 < user_args.size():
		_shot_flicker_prefix = user_args[shot_flicker_idx + 1]
		_shot_flicker_phase = 0
	if user_args.has("--pvlds-smoke-placard"):
		_smoke_placard = true
	if user_args.has("--pvlds-smoke-setup-panel"):
		_smoke_setup_panel = true
	var shot_sp_idx: int = user_args.find("--pvlds-shot-setup-panel")
	if shot_sp_idx >= 0 and shot_sp_idx + 1 < user_args.size():
		_shot_setup_panel_path = user_args[shot_sp_idx + 1]
		_shot_setup_panel_phase = 0
	if user_args.has("--pvlds-shot-setup-panel-scan"):
		_shot_setup_panel_after_scan = true
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
	elif (_smoke_launch_game != "" or _smoke_lockout or _smoke_dpadexit or _smoke_nav or _shot_pop_prefix != "" or _shot_flicker_prefix != "" or _smoke_setup_panel or _shot_setup_panel_path != "") and not configured:
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
	if _smoke_setup_panel:
		_drive_setup_panel_smoke()
	if _shot_setup_panel_phase >= 0:
		_drive_shot_setup_panel()
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
	if _shot_slide_phase >= 0:
		_drive_shot_slide()
	if _shot_flicker_phase >= 0:
		_drive_shot_flicker()
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
	if _room != null and _room.is_setup_panel_up():
		_room.set_setup_panel_message(_scan_progress_text())
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
	# The room eats from the same landing (the SETUP panel): the
	# wall adopts the new scan - a panel-started scan must change
	# the room it was started from. While the panel stands, the
	# room DEFERS that adoption to the panel's close (see
	# RoomView.adopt_library) - behind the panel only the
	# panel's own health numbers and message line move. During
	# a load wait the wait owns the room; no adoption then
	# (the wait's settle path rebuilds nothing).
	if _room != null and _scanner != null:
		if not _launch_pending:
			_room.adopt_library(_scanner)
		var done_msg: String
		if _scanner.missing_b2s_files.is_empty():
			done_msg = "Scan done - %d tables, none missing a backglass" % _scanner.total_files
		else:
			done_msg = "Scan done - %d tables, %d missing a backglass" % [
				_scanner.total_files, _scanner.missing_b2s_files.size()]
		_room.apply_setup_panel_scan(_setup_panel_health(), done_msg)
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


## The room SETUP panel's SCAN LIBRARY: the same threaded scan
## the desk's Save & Scan runs - start_scan is the one path.
## Progress paints into the panel from _process; the landing
## feeds the panel in _finish_scan.
func _on_setup_panel_scan_requested() -> void:
	if start_scan():
		if _room != null:
			_room.set_setup_panel_scanning(true)
	elif _room != null:
		_room.set_setup_panel_message("A scan is already running - one moment.")


## The SETUP panel's health numbers from the last completed
## scan - the desk summary's facts, minus the prose.
func _setup_panel_health() -> Dictionary:
	if _scanner == null:
		return {}
	return {
		"files": _scanner.total_files,
		"games": _scanner.games.size(),
		"matched": _scanner.matched_files,
		"game_matched": _scanner.game_matched_files,
		"db_ok": _last_db_ok,
		"db_kind": _last_db_kind,
		"missing": _scanner.missing_b2s_files.size(),
	}


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
		var tc: Dictionary = s.match_tier_counts
		lines.append("Match routes: %d by download slug, %d by title, %d by cleaned title, %d unmatched (file name only)." % [
			int(tc.get("slug", 0)), int(tc.get("name", 0)), int(tc.get("scrubbed", 0)), int(tc.get("local", 0))])
	else:
		lines.append("No database loaded - every game is identified from its file name alone.")
	# Panel art counts a game when art is PROVEN: a side image on
	# disk, a backglass on disk (the scan's art_covered_games
	# floor), an extracted cache entry, or an "ok" in the outcome
	# index for any of its sources (side image, backglass, or the
	# image inside the .vpx). Per game, whichever proof is
	# strongest - never twice.
	var art_have: int = 0
	for g: GameEntry in s.games:
		if g.art_path != "" or g.art_source_path.get_extension().to_lower() == "directb2s":
			art_have += 1
			continue
		for src: String in g.art_sources():
			if ArtProvider.is_cached(src) or ArtProvider.outcome_for_source(src) == ArtProvider.STATUS_OK:
				art_have += 1
				break
	lines.append("Panel art: %d of %d games have art (side image, backglass, or image inside the .vpx); the rest get title cards." % [
		art_have, s.games.size()])
	var cov: Vector2i = ArtWarmer.cache_coverage(s.games)
	if cov.y > 0:
		lines.append("Art cache: %d of %d art images are extracted and ready instantly; the rest pre-extract in the background while you browse." % [cov.x, cov.y])
	var health: Dictionary = ArtWarmer.art_health(s.games)
	if int(health["total"]) > 0:
		lines.append("Backglass health (from the art cache's outcome index): %d extracted OK, %d no image in file, %d failed to read or parse, %d not tried yet." % [
			int(health["ok"]), int(health["no_image"]), int(health["failed"]), int(health["untried"])])
	var ehealth: Dictionary = ArtWarmer.embedded_health(s.games)
	if int(ehealth["total"]) > 0:
		lines.append("Embedded art health (images inside the .vpx files, from the art cache's outcome index): %d extracted OK, %d no image in file, %d in a legacy format, %d failed to read or parse, %d not tried yet." % [
			int(ehealth["ok"]), int(ehealth["no_image"]), int(ehealth["legacy"]), int(ehealth["failed"]), int(ehealth["untried"])])
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
		_room.setup_panel_scan_requested.connect(_on_setup_panel_scan_requested)
		_room.launch_requested.connect(_on_launch_requested)
		_room.exit_requested.connect(_on_exit_requested)
		_room.art_prefetch_requested.connect(_on_art_prefetch)
	else:
		_room.adopt_library(_scanner)
		# Entering the room (e.g. Enter the Room on the desk while a
		# placard stood in the headset) never leaves a stale placard.
		_room.clear_setup_placard()
		_room.clear_setup_panel()
	# The SETUP panel's health rows start from the last scan's
	# numbers, whichever route built the room.
	_room.set_setup_health(_setup_panel_health())
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
		if _room != null:
			var marquee_lines: Array[String] = _room.marquee_text()
			if marquee_lines.size() == 2:
				print("PVLDS SHOT LAUNCH MARQUEE top=\"%s\" bottom=\"%s\"" % [marquee_lines[0], marquee_lines[1]])
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
## sits POP_OUT_DISTANCE off the wall at the room's full-pop
## scale for its art, its neighbour untouched, the pop target
## is the focused card), saves PREFIX_popped.png, prints the
## verdict, quits.
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
			# The scale contract is the room's own full-pop
			# seam: uniform POP_OUT_SCALE for a card with no
			# art aspect, the true-aspect grow for one with
			# (the sizing round changed the contract on
			# purpose - Chris's "sizing to proper size").
			var full: Vector2 = _room.panel_full_pop_scale(_shot_pop_panel)
			if absf(_shot_pop_panel.scale.x - full.x) > 0.01 or absf(_shot_pop_panel.scale.y - full.y) > 0.01:
				problems.append("scale %.3f/%.3f, want %.3f/%.3f" % [_shot_pop_panel.scale.x, _shot_pop_panel.scale.y, full.x, full.y])
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


## Amber-ish pixel count inside a panel's screen rect - the
## flicker shot's visible-evidence measure (the fixture bulbs
## are amber; the unlit glass and the room are not).
func _flicker_amber_count(q: ClickableQuad) -> int:
	return _flicker_amber_count_img(q, get_viewport().get_texture().get_image())


## The count over a GIVEN frame (the burst analysis counts
## frames it grabbed earlier; the panel's rect is read live,
## valid while the panel stands popped and focused).
func _flicker_amber_count_img(q: ClickableQuad, img: Image) -> int:
	# The viewport's ACTIVE camera: the desk camera's rects are
	# only ever read relatively (the nav clearance legs); pixel
	# sampling needs the projection the frame was rendered with.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var rect: Rect2 = _nav_screen_rect(q, cam)
	var x0: int = clampi(int(rect.position.x), 0, img.get_width() - 1)
	var y0: int = clampi(int(rect.position.y), 0, img.get_height() - 1)
	var x1: int = clampi(int(rect.end.x), 0, img.get_width())
	var y1: int = clampi(int(rect.end.y), 0, img.get_height())
	var n: int = 0
	var y: int = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			if _flicker_is_amber(img.get_pixel(x, y)):
				n += 1
			x += 2
		y += 2
	return n


## The amber centroid inside a panel's screen rect, as
## fractions of the rect (0..1 across, 0..1 down), or
## (-1, -1) when the rect holds no amber. The pair legs'
## registration measure: WHERE the lit amber sits testifies
## which image's space the layer was composed in.
func _flicker_amber_centroid_img(q: ClickableQuad, img: Image) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(-1, -1)
	var rect: Rect2 = _nav_screen_rect(q, cam)
	var x0: int = clampi(int(rect.position.x), 0, img.get_width() - 1)
	var y0: int = clampi(int(rect.position.y), 0, img.get_height() - 1)
	var x1: int = clampi(int(rect.end.x), 0, img.get_width())
	var y1: int = clampi(int(rect.end.y), 0, img.get_height())
	var sx: float = 0.0
	var sy: float = 0.0
	var n: int = 0
	var y: int = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			if _flicker_is_amber(img.get_pixel(x, y)):
				sx += float(x)
				sy += float(y)
				n += 1
			x += 2
		y += 2
	if n == 0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2(-1, -1)
	return Vector2((sx / float(n) - rect.position.x) / rect.size.x,
		(sy / float(n) - rect.position.y) / rect.size.y)


## The amber test itself, shared by the in-rect count and
## the spill measure below.
func _flicker_is_amber(px: Color) -> bool:
	return px.r > 0.72 and px.g > 0.42 and px.g < 0.92 and px.b < 0.45 and px.r > px.b + 0.3


## Flasher-red pixel count inside a panel's screen rect over
## a GIVEN frame - the flasher leg's visible-evidence measure
## (the fixture's flasher paints a bold semi-transparent red
## band across the glass; nothing else on the card is red -
## the base is navy, the lamps are amber, whose green channel
## keeps it out of this test).
func _flicker_red_count_img(q: ClickableQuad, img: Image) -> int:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var rect: Rect2 = _nav_screen_rect(q, cam)
	var x0: int = clampi(int(rect.position.x), 0, img.get_width() - 1)
	var y0: int = clampi(int(rect.position.y), 0, img.get_height() - 1)
	var x1: int = clampi(int(rect.end.x), 0, img.get_width())
	var y1: int = clampi(int(rect.end.y), 0, img.get_height())
	var n: int = 0
	var y: int = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			var px: Color = img.get_pixel(x, y)
			if px.r > 0.55 and px.g < 0.32 and px.b < 0.32:
				n += 1
			x += 2
		y += 2
	return n


## Amber pixels in the band AROUND a panel's screen rect -
## the spill measure. The band holds neighbouring cards and
## room, whose own amber content is constant across the
## burst, so the burst's max-min difference isolates what
## the performer's layers add out there. Post-fix the layers
## are clipped to the face, so the difference must be zero;
## pre-fix the cover transform parks two bulbs' worth of lit
## glass in the band (the build's own pre-fix shot measured
## lit amber 44 px left of the face).
func _flicker_spill_band_count(q: ClickableQuad, img: Image) -> int:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var rect: Rect2 = _nav_screen_rect(q, cam)
	# The face's own bounds, with a 1 px tolerance for edge
	# anti-aliasing (and the layer quads' 5 mm forward offset,
	# a sub-pixel projection growth at room distance). An
	# earlier cut shrank the inner rect by several px, which
	# counted the face's own lit edge ring as "spill" - the
	# measure was wrong, not the clipping: the burst's newly
	# lit amber sits entirely inside the face rect.
	var inner: Rect2 = rect.grow(-1.0)
	var outer: Rect2 = rect.grow(90.0)
	var x0: int = clampi(int(outer.position.x), 0, img.get_width() - 1)
	var y0: int = clampi(int(outer.position.y), 0, img.get_height() - 1)
	var x1: int = clampi(int(outer.end.x), 0, img.get_width())
	var y1: int = clampi(int(outer.end.y), 0, img.get_height())
	var n: int = 0
	var y: int = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			if not inner.has_point(Vector2(x, y)) and _flicker_is_amber(img.get_pixel(x, y)):
				n += 1
			x += 2
		y += 2
	return n


## Mean luminance inside a panel's screen rect - the
## fallback leg's rendered evidence (a surging face darkens
## the whole rect measurably, whatever its art).
func _flicker_rect_mean(q: ClickableQuad) -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return -1.0
	var rect: Rect2 = _nav_screen_rect(q, cam)
	var img: Image = get_viewport().get_texture().get_image()
	var x0: int = clampi(int(rect.position.x), 0, img.get_width() - 1)
	var y0: int = clampi(int(rect.position.y), 0, img.get_height() - 1)
	var x1: int = clampi(int(rect.end.x), 0, img.get_width())
	var y1: int = clampi(int(rect.end.y), 0, img.get_height())
	if x1 <= x0 or y1 <= y0:
		return -1.0
	var sum: float = 0.0
	var n: int = 0
	var y: int = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			var px: Color = img.get_pixel(x, y)
			sum += px.r * 0.3 + px.g * 0.5 + px.b * 0.2
			n += 1
			x += 3
		y += 3
	return sum / float(maxi(1, n))


## Least-squares blend fit of a frame against two endpoint
## frames over a panel's screen rect (the pair-strobe leg):
## returns (alpha, relative residual). Alpha says where the
## frame sits on the Off->On line - 0 pure Off, 1 pure On,
## anything between a blend of the two pictures. The
## residual says whether the blend model explains the frame
## at all, relative to the endpoints' own distance: a frame
## whose geometry moved (mid-pop, mid-slide) fits nothing
## and must not be judged by its alpha.
func _flicker_blend_fit(q: ClickableQuad, img: Image, off: Image, on: Image) -> Vector2:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or off == null or on == null or img.get_size() != off.get_size() or img.get_size() != on.get_size():
		return Vector2(-1.0, 1.0)
	var rect: Rect2 = _nav_screen_rect(q, cam)
	var x0: int = clampi(int(rect.position.x), 0, img.get_width() - 1)
	var y0: int = clampi(int(rect.position.y), 0, img.get_height() - 1)
	var x1: int = clampi(int(rect.end.x), 0, img.get_width())
	var y1: int = clampi(int(rect.end.y), 0, img.get_height())
	var num: float = 0.0
	var den: float = 0.0
	var y: int = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			var oc: Color = off.get_pixel(x, y)
			var nc: Color = on.get_pixel(x, y)
			var fc: Color = img.get_pixel(x, y)
			var d: float = (nc.r + nc.g + nc.b) - (oc.r + oc.g + oc.b)
			var v: float = (fc.r + fc.g + fc.b) - (oc.r + oc.g + oc.b)
			num += v * d
			den += d * d
			x += 2
		y += 2
	if den <= 0.0001:
		return Vector2(-1.0, 1.0)
	var alpha: float = num / den
	var res: float = 0.0
	var cnt: int = 0
	y = y0
	while y < y1:
		var x: int = x0
		while x < x1:
			var oc2: Color = off.get_pixel(x, y)
			var nc2: Color = on.get_pixel(x, y)
			var fc2: Color = img.get_pixel(x, y)
			var osum: float = oc2.r + oc2.g + oc2.b
			var d2: float = (nc2.r + nc2.g + nc2.b) - osum
			var pred: float = osum + alpha * d2
			var diff: float = (fc2.r + fc2.g + fc2.b) - pred
			res += diff * diff
			cnt += 1
			x += 2
		y += 2
	if cnt == 0:
		return Vector2(-1.0, 1.0)
	var rel: float = sqrt(res / float(cnt)) / sqrt(den / float(cnt))
	return Vector2(alpha, rel)



func _flicker_finish() -> void:
	_shot_flicker_phase = -1
	if _shot_flicker_problems.is_empty():
		print("PVLDS FLICKER SHOT: PASS counts=", _shot_flicker_counts, " min_brightness=", snappedf(_shot_flicker_min_b, 0.01), " spill=", _shot_flicker_spill)
		get_tree().quit(0)
	else:
		printerr("PVLDS FLICKER SHOT: FAIL - ", "; ".join(PackedStringArray(_shot_flicker_problems)))
		get_tree().quit(1)


## --pvlds-shot-flicker PREFIX: the power-on flicker's QA
## hook (the flicker round). Needs the harness's bulb-bearing
## fixture folder (its config names the folder beside the
## dummy library): a "Flicker Wide" table whose .directb2s
## carries five visible amber bulbs over a dark glass (one
## straddling the name strip, one wholly beneath it). Legs:
## (1) a fast focus pass never starts a power-on (the settle
## debounce); (2) settled focus on the fixture card runs the
## LAYER cascade - sampled frames go dark -> partial -> lit
## with strictly rising amber counts, five layer quads (the
## sub-strip bulb skipped), ZERO cascade-driven amber
## outside the face (the fix round's spill measure), and
## the popped card stands at its art's true aspect within
## the cap; (3) a title card runs the brightness fallback
## on the same trigger (face dips dark, ends at full);
## (4) the fix round's pop gates - a wide embedded card and
## a tall playfield card pop at the uniform 1.08, a glass-
## shaped card at its true aspect within the cap; (5) the
## wart - a game whose backglass hides its base behind a
## corrupt designated element wears that base as its face
## (phase 0 proves pixel equality with the layer set's
## base) and cascades on it; (6) the warmer's second
## phase - a never-focused B2S card's first focus cascades
## immediately; (7) opening the detail view mid-cascade
## cancels cleanly; (8) the adversarial pair (fix round
## 2) - halves of different aspects, no plain image: the
## card rests on the dark Off glass (phase 0 measures the
## face's pixels) and its one full-frame layer lights it
## in the Off glass's own space, the lit amber's centroid
## left of center where the On image put it; (9) pair +
## plain - a plain backglass with a decoy pair riding in
## the same file: both halves ignored, the card cascades
## on the plain image's two bulbs; (10) the pair-strobe
## leg - a content-differing pair (Flicker Specter: the On
## half shifted +15 px and redrawn bright, its seeded
## schedule carrying a dip): the pair layer's alpha is
## {0, 1} ONLY, proven three ways - live per-frame samples,
## a deterministic sweep of the cascade clock, and
## rendered blend fits against the Off/On endpoint frames
## including a frame rendered with the clock parked inside
## the dip window. Leg (2) carries the counter-guard: a
## bulb layer's dip still measures 0.12. (11) the flasher
## leg - a glass with two RomIDType-1 lamps and one giant
## RomIDType-2 solenoid snippet (a red band the base does
## not carry): the set extracts with the kinds the file
## declares, the flasher renders mid-cascade, and the
## settled card is lamps only - the flasher fully released
## (parked alpha probes + rendered strike/settled frames).
## Saves PREFIX_base/mid/lit.png plus pair/flasher frames.
func _drive_shot_flicker() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _shot_flicker_since > 90000 and _shot_flicker_phase > 0:
		_shot_flicker_problems.append("timed out in phase %d" % _shot_flicker_phase)
		_flicker_finish()
		return
	match _shot_flicker_phase:
		0:
			if _room == null or not _room.visible or not _room.wall_ready or _scanner == null:
				return
			if _shot_flicker_stage == 0:
				_room._handle_rail("filter:all")
				# Park the harness pointer in a corner: the
				# room's pop target prefers the pointer's hover
				# over pad focus, and a pointer left sitting on
				# a popped card holds the performance there
				# against every focus change below (the fix
				# round's fuller wall put a card under it).
				get_viewport().warp_mouse(Vector2(4, 4))
				_shot_flicker_stage = 1
				return
			if _shot_flicker_game == null:
				for g: GameEntry in _scanner.games:
					if g.title.begins_with("Flicker Wide"):
						_shot_flicker_game = g
					for pre: String in ["Flicker Backdrop Wide", "Flicker Playfield Tall", "Flicker Glass Pop", "Flicker Wart", "Flicker Warmed", "Flicker Pair", "Flicker Pair Plain", "Flicker Specter", "Flicker Flasher"]:
						# "Flicker Pair" is a prefix of "Flicker
						# Pair Plain" - the plain game must not
						# claim the pair's slot.
						if pre == "Flicker Pair" and g.title.begins_with("Flicker Pair Plain"):
							continue
						if g.title.begins_with(pre):
							_shot_flicker_fixtures[pre] = {"game": g}
			if _shot_flicker_game == null:
				if not _scan_active:
					_shot_flicker_problems.append("the Flicker Wide fixture game is not in the library (the harness config names its folder)")
					_flicker_finish()
				return
			for p: ClickableQuad in _room._panels:
				if p.payload == _shot_flicker_game.game_id:
					_shot_flicker_panel = p
				elif p.payload == "dg-cinder-peak":
					_shot_flicker_panel2 = p
				for pre2: String in _shot_flicker_fixtures.keys():
					var fx0: Dictionary = _shot_flicker_fixtures[pre2] as Dictionary
					if p.payload == (fx0["game"] as GameEntry).game_id:
						fx0["panel"] = p
			if _shot_flicker_panel == null or _shot_flicker_panel2 == null:
				var payloads: Array = []
				for p2: ClickableQuad in _room._panels:
					payloads.append(p2.payload)
				_shot_flicker_problems.append("fixture/title panels not on the wall (flicker=%s title=%s) panels=%s" % [_shot_flicker_panel != null, _shot_flicker_panel2 != null, str(payloads)])
				_flicker_finish()
				return
			for pre3: String in _shot_flicker_fixtures.keys():
				if not (_shot_flicker_fixtures[pre3] as Dictionary).has("panel"):
					_shot_flicker_problems.append("fixture %s is not on the wall" % pre3)
					_flicker_finish()
					return
			# The wart must be CONSTRUCTED as the deep-fixed
			# wart before any leg trusts it: a backglass in
			# hand whose designated DMD image is corrupt, and
			# - the fix - a face that IS its own backglass
			# extraction, pixel for pixel the layer set's
			# base (the blob fallback's find, shared by both
			# readers now). (Under the split readers this
			# check ran the other way: the flat reader failed
			# the file, so the face had to NOT be its
			# extraction while its lamps composited over a
			# stranger's face.)
			var wart0: Dictionary = _shot_flicker_fixtures.get("Flicker Wart", {}) as Dictionary
			if not wart0.is_empty():
				var wg0: GameEntry = wart0["game"] as GameEntry
				wg0.ensure_art()
				if wg0.flicker_source() == "":
					_shot_flicker_problems.append("the wart fixture game has no flicker source - the wart is not constructed")
					_flicker_finish()
					return
				if wg0.art_path != ArtProvider.cache_path_for(wg0.flicker_source()):
					_shot_flicker_problems.append("the wart fixture's face is not its backglass extraction - the deep fix did not land")
					_flicker_finish()
					return
				var wdata: Dictionary = wg0.ensure_flicker()
				var wface: Image = Image.new()
				var wbase: Image = Image.new()
				if wdata.is_empty() or wface.load(wg0.art_path) != OK or wbase.load(str(wdata.get("base_path", ""))) != OK or wface.get_data() != wbase.get_data():
					_shot_flicker_problems.append("the wart fixture's face and its layer base are not the same image")
					_flicker_finish()
					return
			# The pair fixtures, constructed: the adversarial
			# pair must rest on its OFF glass and the pair+
			# plain on its plain image - measured on the face
			# cache's own pixels: the 1000x800 glass fitted
			# (512x410), dark navy (blue clearly over red, red
			# low), and NO amber anywhere. A face wearing the
			# lit On half, the decoy On (solid amber), or the
			# decoy Off (dark red, red over blue) fails here,
			# before any rendered leg runs.
			for pre4: String in ["Flicker Pair", "Flicker Pair Plain"]:
				var pf0: Dictionary = _shot_flicker_fixtures.get(pre4, {}) as Dictionary
				if pf0.is_empty():
					continue
				var pg0: GameEntry = pf0["game"] as GameEntry
				pg0.ensure_art()
				if pg0.art_path != ArtProvider.cache_path_for(pg0.flicker_source()):
					_shot_flicker_problems.append("the %s fixture's face is not its backglass extraction" % pre4)
					_flicker_finish()
					return
				var pimg: Image = Image.new()
				if pimg.load(pg0.art_path) != OK or pimg.get_size() != Vector2i(512, 410):
					_shot_flicker_problems.append("the %s fixture's face is not its 1000x800 glass fitted (512x410)" % pre4)
					_flicker_finish()
					return
				var pmean: Vector3 = Vector3.ZERO
				var pcount: int = 0
				var pamber: int = 0
				var pyy: int = 0
				while pyy < pimg.get_height():
					var pxx: int = 0
					while pxx < pimg.get_width():
						var pc: Color = pimg.get_pixel(pxx, pyy)
						pmean += Vector3(pc.r, pc.g, pc.b)
						pcount += 1
						if _flicker_is_amber(pc):
							pamber += 1
						pxx += 4
					pyy += 4
				pmean /= float(maxi(1, pcount))
				if pamber > 0 or pmean.z < pmean.x + 0.03 or pmean.x > 0.12:
					_shot_flicker_problems.append("the %s fixture does not rest dark (mean %s, amber px %d) - it is wearing a lit or decoy image" % [pre4, str(pmean), pamber])
					_flicker_finish()
					return
			var data: Dictionary = _shot_flicker_game.ensure_flicker()
			if (data.get("layers", []) as Array).is_empty():
				_shot_flicker_problems.append("the fixture game's layer set did not extract")
				_flicker_finish()
				return
			_room._set_focused(_shot_flicker_panel)
			_shot_flicker_frames = 0
			_shot_flicker_since = now
			_shot_flicker_phase = 1
		1:
			# Debounce leg: a ~90 ms rest on the fixture card
			# (well inside the settle window, and time-based -
			# a frame count would straddle the window at
			# software-render frame rates), then focus moves
			# on. The passed card may never perform (the card
			# focus lands on may - it gets its own settle;
			# that is the next legs' business, and phase 2's
			# focus change restores it).
			_shot_flicker_frames += 1
			if _room.power_panel() == _shot_flicker_panel:
				_shot_flicker_problems.append("a fast focus pass started a power-on on the passed card (debounce failed)")
				_flicker_finish()
				return
			if now - _shot_flicker_since > 90 and _shot_flicker_frames >= 1:
				_room._set_focused(_shot_flicker_panel2)
			if now - _shot_flicker_since > 450:
				_shot_flicker_counts.clear()
				_shot_flicker_saw_partial = false
				_room._set_focused(_shot_flicker_panel)
				_shot_flicker_since = now
				_shot_flicker_phase = 2
		2:
			# Layers leg: grab a BURST of frames on a wall-
			# clock cadence across the cascade and past its
			# settle, then count them all once the pressure
			# is off. Rendered readbacks lag the room's state
			# by several frames under software rendering, so
			# no single triggered sample can be trusted to
			# land mid-cascade - but a burst spanning the
			# lag must contain the dark -> partial -> lit arc
			# if the effect truly renders as a cascade.
			var ph: int = _room.power_phase()
			if ph == 1 or (ph == 2 and _shot_flicker_t0 > 0 and now < _shot_flicker_t0 + 1900):
				if ph == 1:
					var lit_n: int = 0
					for li: int in range(_room.power_layer_count()):
						if _room.power_layer_alpha(li) > 0.5:
							lit_n += 1
					if lit_n > 0 and lit_n < _room.power_layer_count():
						_shot_flicker_saw_partial = true
					if _shot_flicker_t0 == 0:
						_shot_flicker_t0 = now
						_shot_flicker_next_grab = now
				if _shot_flicker_t0 > 0 and now >= _shot_flicker_next_grab:
					_shot_flicker_burst.append(get_viewport().get_texture().get_image())
					_shot_flicker_next_grab = now + 130
			elif ph == 2 and _shot_flicker_t0 > 0:
				var series: Array[int] = []
				for fimg: Image in _shot_flicker_burst:
					series.append(_flicker_amber_count_img(_shot_flicker_panel, fimg))
				var base_c: int = series[0] if series.size() > 0 else -1
				var lit_c: int = series[series.size() - 1] if series.size() > 0 else -1
				var mid_c: int = -1
				var mid_idx: int = -1
				for si: int in range(series.size()):
					if series[si] > base_c and series[si] < lit_c and (mid_idx < 0 or abs(series[si] - (base_c + lit_c) / 2) < abs(mid_c - (base_c + lit_c) / 2)):
						mid_c = series[si]
						mid_idx = si
				_shot_flicker_counts = [base_c, mid_c, lit_c]
				# Spill: amber in the band around the face,
				# differenced across the burst (the band's own
				# constant content cancels). Zero is the only
				# passing value - the layers are clipped to
				# the face on every edge now.
				var band: Array[int] = []
				for fimg2: Image in _shot_flicker_burst:
					band.append(_flicker_spill_band_count(_shot_flicker_panel, fimg2))
				if not band.is_empty():
					var bmin: int = band[0]
					var bmax: int = band[0]
					for bv: int in band:
						bmin = mini(bmin, bv)
						bmax = maxi(bmax, bv)
					_shot_flicker_spill = bmax - bmin
					if _shot_flicker_spill != 0:
						_shot_flicker_problems.append("lamp layers spill outside the face (burst band counts %s)" % str(band))
				if not _shot_flicker_burst.is_empty():
					_shot_flicker_burst[0].save_png(_shot_flicker_prefix + "_base.png")
					_shot_flicker_burst[_shot_flicker_burst.size() - 1].save_png(_shot_flicker_prefix + "_lit.png")
				if mid_idx >= 0:
					_shot_flicker_burst[mid_idx].save_png(_shot_flicker_prefix + "_mid.png")
				if _room.power_mode() != 1:
					_shot_flicker_problems.append("the B2S-backed card did not use its lamp layers (mode %d)" % _room.power_mode())
				if _room.power_layer_count() != 5:
					_shot_flicker_problems.append("layer quads %d, want 5 (sixth bulb lives under the name strip)" % _room.power_layer_count())
				if not _shot_flicker_saw_partial:
					_shot_flicker_problems.append("no partial-lit state observed - the cascade read as a switch, not a cascade")
				if base_c < 0 or lit_c < base_c + 100:
					_shot_flicker_problems.append("the lit card is not visibly brighter than the unlit base (base %d, lit %d)" % [base_c, lit_c])
				if mid_c <= base_c or mid_c >= lit_c:
					_shot_flicker_problems.append("no rendered partial frame between dark and lit (series %s)" % str(series))
				var asp: float = _room.panel_art_aspect(_shot_flicker_panel)
				if absf(asp - 1.25) > 0.03:
					_shot_flicker_problems.append("fixture art aspect %.3f, want 1.25" % asp)
				var full: Vector2 = _room.panel_full_pop_scale(_shot_flicker_panel)
				if absf(_shot_flicker_panel.scale.x - full.x) > 0.02 or absf(_shot_flicker_panel.scale.y - full.y) > 0.02:
					_shot_flicker_problems.append("popped scale %s, want %s (true-aspect pop)" % [str(_shot_flicker_panel.scale), str(full)])
				# Bulb-dip guard (pair-strobe round): the pair
				# fix must not overreach - a BULB layer's dip
				# is still 0.12. Probe the live schedule
				# deterministically: park the cascade clock
				# inside a dipped layer's dip window, apply,
				# and read the material alpha back.
				var guard_probed: bool = false
				for gi: int in range(_room._power_schedule.size()):
					var gs: Array = _room._power_schedule[gi] as Array
					if float(gs[2]) > float(gs[1]):
						_room._power_t = (float(gs[1]) + float(gs[2])) * 0.5
						_room._apply_power()
						var ga: float = _room.power_layer_alpha(gi)
						if absf(ga - 0.12) > 0.02:
							_shot_flicker_problems.append("a bulb layer's dip reads %.2f, want 0.12 - the pair strobe overreached" % ga)
						guard_probed = true
						break
				if not guard_probed:
					_shot_flicker_problems.append("the bulb fixture's schedule has no dipped layer - the 0.12 guard has nothing to probe")
				_room._power_t = RoomView.POWER_CASCADE_SEC
				_room._apply_power()
				_shot_flicker_min_b = 1.0
				_shot_flicker_min_mean = -1.0
				_room._set_focused(_shot_flicker_panel2)
				_shot_flicker_since = now
				_shot_flicker_phase = 3
			elif now - _shot_flicker_since > 10000:
				_shot_flicker_problems.append("the layers cascade never ran")
				_flicker_finish()
		3:
			# Fallback leg: the title card surges its face.
			# Evidence is twofold - the face-brightness state
			# AND the rendered mean luminance in the card's
			# rect (the surge darkens the whole face, so the
			# mean must dip against its resting value).
			var ph2: int = _room.power_phase()
			if ph2 == 1 and _room.power_panel() == _shot_flicker_panel2:
				_shot_flicker_min_b = minf(_shot_flicker_min_b, _shot_flicker_panel2.face_brightness())
				var m: float = _flicker_rect_mean(_shot_flicker_panel2)
				if m >= 0.0 and (_shot_flicker_min_mean < 0.0 or m < _shot_flicker_min_mean):
					_shot_flicker_min_mean = m
			elif ph2 == 2 and _room.power_panel() == _shot_flicker_panel2:
				# The honest denominator: the same card, in the
				# same popped geometry, at full brightness.
				var end_mean: float = _flicker_rect_mean(_shot_flicker_panel2)
				if _room.power_mode() != 0:
					_shot_flicker_problems.append("the title card did not use the brightness fallback (mode %d)" % _room.power_mode())
				if _shot_flicker_min_b > 0.85:
					_shot_flicker_problems.append("the fallback's face never dipped (min brightness %.2f)" % _shot_flicker_min_b)
				if _shot_flicker_min_mean < 0.0 or end_mean <= 0.0 or _shot_flicker_min_mean > end_mean * 0.8:
					_shot_flicker_problems.append("the fallback's rendered face never darkened (min mean %.3f, settled mean %.3f)" % [_shot_flicker_min_mean, end_mean])
				if absf(_shot_flicker_panel2.face_brightness() - 1.0) > 0.001:
					_shot_flicker_problems.append("the fallback did not end at full brightness (%.3f)" % _shot_flicker_panel2.face_brightness())
				_shot_flicker_stage = 0
				_shot_flicker_armed = false
				_shot_flicker_since = now
				_shot_flicker_phase = 4
			elif now - _shot_flicker_since > 10000:
				_shot_flicker_problems.append("the fallback cascade never ran")
				_flicker_finish()
		4:
			# Fix-round pop gates: settle on each pop subject
			# in turn and read its scale. The wide embedded
			# card and the tall playfield card are NOT glass
			# shapes - both must pop at the uniform 1.08 (no
			# neighbour swallowed, no shrink). The glass-
			# shaped card keeps its true-aspect grow, bounded
			# by the cap.
			var order: Array[String] = ["Flicker Backdrop Wide", "Flicker Playfield Tall", "Flicker Glass Pop"]
			var fx4: Dictionary = _shot_flicker_fixtures[order[_shot_flicker_stage]] as Dictionary
			var panel4: ClickableQuad = fx4["panel"] as ClickableQuad
			if not _shot_flicker_armed:
				_room._set_focused(panel4)
				_shot_flicker_since = now
				_shot_flicker_armed = true
				return
			if now - _shot_flicker_since < 700:
				return
			var full4: Vector2 = _room.panel_full_pop_scale(panel4)
			var asp4: float = _room.panel_art_aspect(panel4)
			if order[_shot_flicker_stage] == "Flicker Glass Pop":
				if absf(asp4 - 1.2) > 0.03:
					_shot_flicker_problems.append("glass fixture aspect %.3f, want 1.2 (the fixture is not what it claims)" % asp4)
				if full4.x <= RoomView.POP_OUT_SCALE or full4.x > RoomView.POP_FULL_X_MAX + 0.001 or absf(full4.y - RoomView.POP_OUT_SCALE) > 0.001:
					_shot_flicker_problems.append("glass pop %s: want x in (1.08, cap %.2f], y = 1.08" % [str(full4), RoomView.POP_FULL_X_MAX])
			else:
				if order[_shot_flicker_stage] == "Flicker Backdrop Wide" and asp4 < 1.6:
					_shot_flicker_problems.append("wide fixture aspect %.3f, want ~1.71 (the fixture is not what it claims)" % asp4)
				if order[_shot_flicker_stage] == "Flicker Playfield Tall" and (asp4 < 0.45 or asp4 > 0.55):
					_shot_flicker_problems.append("tall fixture aspect %.3f, want ~0.5 (the fixture is not what it claims)" % asp4)
				if full4 != Vector2(RoomView.POP_OUT_SCALE, RoomView.POP_OUT_SCALE):
					_shot_flicker_problems.append("%s pops at %s, want the uniform 1.08 (aspect %.3f is no glass's shape)" % [order[_shot_flicker_stage], str(full4), asp4])
			if absf(panel4.scale.x - full4.x) > 0.02 or absf(panel4.scale.y - full4.y) > 0.02:
				_shot_flicker_problems.append("%s settled scale %s, want %s" % [order[_shot_flicker_stage], str(panel4.scale), str(full4)])
			_shot_flicker_stage += 1
			_shot_flicker_armed = false
			_shot_flicker_since = now
			if _shot_flicker_stage >= order.size():
				_shot_flicker_stage = 0
				_room._set_focused(_shot_flicker_panel2)
				_shot_flicker_phase = 5
		5:
			# Wart leg: the wart game's face IS its own base
			# now (phase 0 proved pixel equality with the
			# layer set's base), and its lamps must cascade
			# over it here in the room. First settle may
			# surge while the set is cold: wait for the set
			# to land, settle again, and the second visit
			# must run the layers.
			var fx5: Dictionary = _shot_flicker_fixtures["Flicker Wart"] as Dictionary
			var g5: GameEntry = fx5["game"] as GameEntry
			var panel5: ClickableQuad = fx5["panel"] as ClickableQuad
			if _shot_flicker_stage == 0:
				if not _shot_flicker_armed:
					_room._set_focused(panel5)
					_shot_flicker_since = now
					_shot_flicker_armed = true
					return
				if _room.power_panel() == panel5:
					_room._set_focused(_shot_flicker_panel2)
					_shot_flicker_armed = false
					_shot_flicker_stage = 1
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 10000:
					_shot_flicker_problems.append("the wart leg's first power-on never started")
					_flicker_finish()
			elif _shot_flicker_stage == 1:
				if ArtProvider.has_flicker_layers(g5.flicker_source()):
					_shot_flicker_stage = 2
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 30000:
					_shot_flicker_problems.append("the wart game's layers were never extracted - the kick never fired")
					_flicker_finish()
			elif _shot_flicker_stage == 2:
				if not _shot_flicker_armed:
					_room._set_focused(panel5)
					_shot_flicker_since = now
					_shot_flicker_armed = true
					return
				if _room.power_panel() == panel5:
					if _room.power_mode() != 1:
						_shot_flicker_problems.append("the wart game surged on its second visit too (mode %d) - its lamps never cascade" % _room.power_mode())
					elif _room.power_layer_count() <= 0:
						_shot_flicker_problems.append("the wart game claims layers mode with no layer quads")
					_shot_flicker_armed = false
					_shot_flicker_stage = 0
					_shot_flicker_since = now
					_shot_flicker_phase = 6
				elif now - _shot_flicker_since > 10000:
					_shot_flicker_problems.append("the wart leg's second power-on never started")
					_flicker_finish()
		6:
			# Warmer leg: nobody has focused the Warmed card
			# in this run - if its layer set is waiting, only
			# the warmer's second phase can have put it there.
			# Its FIRST focus must then cascade immediately,
			# no settle-kick, no surge.
			var fx6: Dictionary = _shot_flicker_fixtures["Flicker Warmed"] as Dictionary
			var g6: GameEntry = fx6["game"] as GameEntry
			var panel6: ClickableQuad = fx6["panel"] as ClickableQuad
			if not ArtProvider.has_flicker_layers(g6.flicker_source()):
				if now - _shot_flicker_since > 90000:
					_shot_flicker_problems.append("the warmer never prefetched the Warmed fixture's layers")
					_flicker_finish()
				return
			if not _shot_flicker_armed:
				_room._set_focused(panel6)
				_shot_flicker_since = now
				_shot_flicker_armed = true
				return
			if _room.power_panel() == panel6:
				if _room.power_mode() != 1:
					_shot_flicker_problems.append("the warmed card's first focus surged instead of cascading (mode %d)" % _room.power_mode())
				elif _room.power_layer_count() != 5:
					_shot_flicker_problems.append("the warmed card built %d layer quads, want 5" % _room.power_layer_count())
				_shot_flicker_armed = false
				_shot_flicker_stage = 0
				_shot_flicker_since = now
				_room._set_focused(_shot_flicker_panel)
				_shot_flicker_phase = 7
			elif now - _shot_flicker_since > 10000:
				_shot_flicker_problems.append("the warmed leg's power-on never started")
				_flicker_finish()
		7:
			# Cancel leg: detail opens mid-cascade; the
			# performer restores in the same breath.
			if _room.power_phase() == 1 and _room.power_layer_count() > 0:
				_room._open_detail(_shot_flicker_game)
				_shot_flicker_stage = 2
				_shot_flicker_since = now
			elif _shot_flicker_stage == 2 and now - _shot_flicker_since > 120:
				if _room.power_phase() != 0 or _room.power_layer_count() != 0:
					_shot_flicker_problems.append("opening detail did not cancel the cascade (phase %d, layers %d)" % [_room.power_phase(), _room.power_layer_count()])
				if absf(_shot_flicker_panel.face_brightness() - 1.0) > 0.001:
					_shot_flicker_problems.append("the cancelled card's face did not restore to full brightness")
				_shot_flicker_stage = 0
				_shot_flicker_armed = false
				_shot_flicker_since = now
				_shot_flicker_phase = 8
			elif _shot_flicker_stage != 2 and now - _shot_flicker_since > 10000:
				_shot_flicker_problems.append("the cancel leg's cascade never started")
				_flicker_finish()
		8:
			# Pair leg (fix round 2): close the detail view
			# the cancel leg left open (its close rebuilds
			# the wall - the fixture panels are re-resolved
			# by payload), settle on the adversarial pair,
			# and burst-sample its cascade. The card rests
			# on the dark Off glass (phase 0 measured it);
			# its one layer must light the On image IN THE
			# OFF GLASS'S SPACE: amber rising from ~none to
			# a left-of-center mass (the On image's amber is
			# its left half, mapped through the Off cover),
			# and nothing outside the face.
			var fx8: Dictionary = _shot_flicker_fixtures["Flicker Pair"] as Dictionary
			var g8: GameEntry = fx8["game"] as GameEntry
			if _shot_flicker_stage == 0:
				if not _shot_flicker_armed:
					# The detail's own escape: hides the view
					# AND emits closed (the room's handler
					# then rebuilds the wall). Calling the
					# handler alone leaves the view standing
					# over the wall - the pair cards performed
					# behind it, occluded.
					_room._detail.handle_escape()
					_shot_flicker_armed = true
					_shot_flicker_since = now
					return
				var fx9r: Dictionary = _shot_flicker_fixtures["Flicker Pair Plain"] as Dictionary
				var p8: ClickableQuad = null
				var p9: ClickableQuad = null
				for p: ClickableQuad in _room._panels:
					if p.payload == g8.game_id:
						p8 = p
					elif p.payload == (fx9r["game"] as GameEntry).game_id:
						p9 = p
				if p8 == null or p9 == null:
					if now - _shot_flicker_since > 15000:
						_shot_flicker_problems.append("the pair fixtures fell off the wall after the detail close")
						_flicker_finish()
					return
				fx8["panel"] = p8
				fx9r["panel"] = p9
				if (g8.ensure_flicker().get("layers", []) as Array).is_empty():
					_shot_flicker_problems.append("the pair fixture's layer set did not extract")
					_flicker_finish()
					return
				_shot_flicker_burst.clear()
				_shot_flicker_t0 = 0
				_room._set_focused(p8)
				_shot_flicker_stage = 1
				_shot_flicker_since = now
			elif _shot_flicker_stage == 1:
				var panel8: ClickableQuad = fx8["panel"] as ClickableQuad
				var ph8: int = _room.power_phase()
				if _room.power_panel() == panel8 and ph8 == 1 and _shot_flicker_t0 == 0:
					_shot_flicker_t0 = now
					_shot_flicker_next_grab = now
				if _shot_flicker_t0 > 0 and now >= _shot_flicker_next_grab and ph8 > 0:
					_shot_flicker_burst.append(get_viewport().get_texture().get_image())
					_shot_flicker_next_grab = now + 130
				if _shot_flicker_t0 > 0 and ph8 == 2 and now > _shot_flicker_t0 + 1900:
					if _room.power_panel() != panel8 or _room.power_mode() != 1:
						_shot_flicker_problems.append("the pair card did not cascade on its layer (mode %d)" % _room.power_mode())
					if _room.power_layer_count() != 1:
						_shot_flicker_problems.append("the pair card built %d layer quads, want its one full-frame layer" % _room.power_layer_count())
					var series8: Array[int] = []
					for fimg8: Image in _shot_flicker_burst:
						series8.append(_flicker_amber_count_img(panel8, fimg8))
					var base8: int = series8[0] if series8.size() > 0 else -1
					var lit8: int = series8[series8.size() - 1] if series8.size() > 0 else -1
					if base8 < 0 or lit8 < base8 + 500:
						_shot_flicker_problems.append("the pair's lit frame is not visibly lit over its dark rest (series %s)" % str(series8))
					if not _shot_flicker_burst.is_empty():
						var cen8: Vector2 = _flicker_amber_centroid_img(panel8, _shot_flicker_burst[_shot_flicker_burst.size() - 1])
						if cen8.x < 0.10 or cen8.x > 0.42:
							_shot_flicker_problems.append("the pair's lit amber centroid sits at x %.2f of the face - the On layer is not composed in the Off glass's space (want 0.10..0.42)" % cen8.x)
						var band8: Array[int] = []
						for fimg8b: Image in _shot_flicker_burst:
							band8.append(_flicker_spill_band_count(panel8, fimg8b))
						var bmin8: int = band8[0]
						var bmax8: int = band8[0]
						for bv8: int in band8:
							bmin8 = mini(bmin8, bv8)
							bmax8 = maxi(bmax8, bv8)
						if bmax8 - bmin8 != 0:
							_shot_flicker_problems.append("the pair's layer spills outside the face (burst band counts %s)" % str(band8))
						_shot_flicker_burst[0].save_png(_shot_flicker_prefix + "_pair_base.png")
						_shot_flicker_burst[_shot_flicker_burst.size() - 1].save_png(_shot_flicker_prefix + "_pair_lit.png")
					_shot_flicker_stage = 0
					_shot_flicker_armed = false
					_shot_flicker_burst.clear()
					_shot_flicker_t0 = 0
					_shot_flicker_since = now
					_shot_flicker_phase = 9
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the pair card's cascade never ran")
					_flicker_finish()
		9:
			# Pair+plain leg: settle on the pair+plain
			# card. The decoy pair is ignored, so the
			# cascade is the plain glass's TWO bulbs, up
			# at the top of the glass - one full-frame
			# layer, or amber centered in the face, would
			# convict the pair path at once.
			var fx9: Dictionary = _shot_flicker_fixtures["Flicker Pair Plain"] as Dictionary
			var g9: GameEntry = fx9["game"] as GameEntry
			var panel9: ClickableQuad = fx9["panel"] as ClickableQuad
			if _shot_flicker_stage == 0:
				if (g9.ensure_flicker().get("layers", []) as Array).is_empty():
					_shot_flicker_problems.append("the pair+plain fixture's layer set did not extract")
					_flicker_finish()
					return
				_shot_flicker_burst.clear()
				_shot_flicker_t0 = 0
				_room._set_focused(panel9)
				_shot_flicker_stage = 1
				_shot_flicker_since = now
			elif _shot_flicker_stage == 1:
				var ph9: int = _room.power_phase()
				if _room.power_panel() == panel9 and ph9 == 1 and _shot_flicker_t0 == 0:
					_shot_flicker_t0 = now
					_shot_flicker_next_grab = now
				if _shot_flicker_t0 > 0 and now >= _shot_flicker_next_grab and ph9 > 0:
					_shot_flicker_burst.append(get_viewport().get_texture().get_image())
					_shot_flicker_next_grab = now + 130
				if _shot_flicker_t0 > 0 and ph9 == 2 and now > _shot_flicker_t0 + 1900:
					if _room.power_panel() != panel9 or _room.power_mode() != 1:
						_shot_flicker_problems.append("the pair+plain card did not cascade on its bulbs (mode %d)" % _room.power_mode())
					if _room.power_layer_count() != 2:
						_shot_flicker_problems.append("the pair+plain card built %d layer quads, want the plain glass's 2 bulbs" % _room.power_layer_count())
					var series9: Array[int] = []
					for fimg9: Image in _shot_flicker_burst:
						series9.append(_flicker_amber_count_img(panel9, fimg9))
					var base9: int = series9[0] if series9.size() > 0 else -1
					var lit9: int = series9[series9.size() - 1] if series9.size() > 0 else -1
					if base9 < 0 or lit9 < base9 + 100:
						_shot_flicker_problems.append("the pair+plain's lit frame is not visibly lit over its rest (series %s)" % str(series9))
					if not _shot_flicker_burst.is_empty():
						var cen9: Vector2 = _flicker_amber_centroid_img(panel9, _shot_flicker_burst[_shot_flicker_burst.size() - 1])
						if cen9.y < 0.0 or cen9.y > 0.38:
							_shot_flicker_problems.append("the pair+plain's lit amber centroid sits at y %.2f of the face - want the plain glass's top bulbs (0..0.38)" % cen9.y)
						_shot_flicker_burst[_shot_flicker_burst.size() - 1].save_png(_shot_flicker_prefix + "_pairplain_lit.png")
					_shot_flicker_stage = 0
					_shot_flicker_armed = false
					_shot_flicker_burst.clear()
					_shot_flicker_t0 = 0
					_shot_flicker_since = now
					_shot_flicker_phase = 10
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the pair+plain card's cascade never ran")
					_flicker_finish()
		10:
			# Pair-strobe leg: the content-differing pair
			# (Flicker Specter). Its On half is the Off
			# scene shifted +15 px and redrawn bright, so
			# ANY fractional alpha doubles outlines - the
			# ghost twin as a measurable quantity. Stages:
			# 0 arm + focus; 1 the live cascade (burst
			# frames plus the layer's alpha sampled every
			# frame); 2 park the cascade clock at t=0 and
			# render the pure-Off endpoint in the popped
			# geometry; 3 park at cascade end for the
			# pure-On endpoint, run the deterministic alpha
			# sweep, then park INSIDE the dip window; 4
			# fit the dip frame and the burst against the
			# endpoints - every well-explained frame must
			# sit at alpha 0 or 1.
			var fx10: Dictionary = _shot_flicker_fixtures["Flicker Specter"] as Dictionary
			var g10: GameEntry = fx10["game"] as GameEntry
			var panel10: ClickableQuad = fx10["panel"] as ClickableQuad
			if not is_instance_valid(panel10):
				# A scan landing mid-run adopts the library
				# and rebuilds the wall, freeing every panel
				# phase 0 collected (the rebuilds land at
				# unpredictable times - this leg runs last,
				# so it is the one that meets the stale
				# reference). Re-resolve this leg's panel
				# from the room's live wall by payload, the
				# way phase 0 collected it.
				panel10 = null
				for p10: ClickableQuad in _room._panels:
					if p10.payload == g10.game_id:
						panel10 = p10
						break
				if panel10 != null:
					fx10["panel"] = panel10
			if _shot_flicker_stage == 0:
				if panel10 == null:
					_shot_flicker_problems.append("the Specter panel is not on the wall - the blend leg has no card")
					_flicker_finish()
					return
				var data10: Dictionary = g10.ensure_flicker()
				if (data10.get("layers", []) as Array).is_empty():
					_shot_flicker_problems.append("the Specter fixture's layer set did not extract")
					_flicker_finish()
					return
				if not bool(data10.get("pair", false)):
					_shot_flicker_problems.append("the Specter fixture's layer set is not a pair set - the blend leg has no subject")
					_flicker_finish()
					return
				# Do NOT focus yet: the extraction above ran
				# synchronously on this thread, and the
				# room's next _process would swallow the
				# whole settle + cascade in one giant delta
				# frame - unobservable. A few idle frames
				# first (stage 5), then focus.
				_shot_flicker_probe_wait = 0
				_shot_flicker_stage = 5
				_shot_flicker_since = now
			elif _shot_flicker_stage == 5:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 6:
					_shot_flicker_burst.clear()
					_shot_flicker_blend_alphas.clear()
					_shot_flicker_live_missed = false
					_shot_flicker_t0 = 0
					_room._set_focused(panel10)
					_shot_flicker_stage = 1
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the blend leg's warm wait never elapsed")
					_flicker_finish()
			elif _shot_flicker_stage == 1:
				var ph10: int = _room.power_phase()
				if _shot_flicker_probe_wait != now / 1000:
					_shot_flicker_probe_wait = now / 1000
				if _room.power_panel() == panel10 and ph10 == 1:
					if _shot_flicker_t0 == 0:
						_shot_flicker_t0 = now
						_shot_flicker_next_grab = now
					if _room.power_layer_count() == 1:
						_shot_flicker_blend_alphas.append(_room.power_layer_alpha(0))
				if _shot_flicker_t0 == 0 and _room.power_panel() == panel10 and ph10 == 2:
					# The cascade completed between polls
					# anyway: proceed on the deterministic
					# evidence (sweep + rendered fits).
					_shot_flicker_t0 = now - 2000
					_shot_flicker_live_missed = true
				if _shot_flicker_t0 > 0 and now >= _shot_flicker_next_grab and ph10 > 0:
					_shot_flicker_burst.append(get_viewport().get_texture().get_image())
					_shot_flicker_next_grab = now + 130
				if _shot_flicker_t0 > 0 and ph10 == 2 and now > _shot_flicker_t0 + 1900:
					if _room.power_panel() != panel10 or _room.power_mode() != 1:
						_shot_flicker_problems.append("the Specter card did not cascade on its pair layer (mode %d)" % _room.power_mode())
					if _room.power_layer_count() != 1:
						_shot_flicker_problems.append("the Specter card built %d layer quads, want its one full-frame layer" % _room.power_layer_count())
					for av: float in _shot_flicker_blend_alphas:
						if av > 0.02 and av < 0.98:
							_shot_flicker_problems.append("the pair layer's live alpha took %.2f mid-cascade - a blend frame exists" % av)
							break
					if _shot_flicker_blend_alphas.is_empty() and not _shot_flicker_live_missed:
						_shot_flicker_problems.append("the blend leg sampled no live alphas - the cascade was never observed")
					if _room._power_schedule.size() == 1:
						var ss: Array = _room._power_schedule[0] as Array
						_shot_flicker_dip_win = Vector2(float(ss[1]), float(ss[2]))
					if _shot_flicker_dip_win.y <= _shot_flicker_dip_win.x:
						_shot_flicker_problems.append("the Specter schedule has no dip window %s - the blend leg cannot convict" % str(_shot_flicker_dip_win))
						_flicker_finish()
						return
					_room._power_t = 0.0
					_room._apply_power()
					_shot_flicker_probe_wait = 0
					_shot_flicker_stage = 2
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the Specter card's cascade never ran")
					_flicker_finish()
			elif _shot_flicker_stage == 2:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 10:
					_shot_flicker_off_img = get_viewport().get_texture().get_image()
					_room._power_t = RoomView.POWER_CASCADE_SEC
					_room._apply_power()
					_shot_flicker_probe_wait = 0
					_shot_flicker_stage = 3
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the blend leg's Off endpoint never rendered")
					_flicker_finish()
			elif _shot_flicker_stage == 3:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 10:
					_shot_flicker_on_img = get_viewport().get_texture().get_image()
					# The deterministic sweep: probe the
					# whole cascade in 4 ms steps through
					# the room's own apply - no sampling
					# luck involved.
					var bad_t: float = -1.0
					var bad_a: float = -1.0
					var probe: float = 0.0
					while probe <= RoomView.POWER_CASCADE_SEC:
						_room._power_t = probe
						_room._apply_power()
						var pa: float = _room.power_layer_alpha(0)
						if pa > 0.02 and pa < 0.98:
							bad_t = probe
							bad_a = pa
							break
						probe += 0.004
					if bad_t >= 0.0:
						_shot_flicker_problems.append("the pair layer takes alpha %.2f at cascade t=%.3f - pair alphas must be {0, 1} only" % [bad_a, bad_t])
					_room._power_t = (_shot_flicker_dip_win.x + _shot_flicker_dip_win.y) * 0.5
					_room._apply_power()
					_shot_flicker_probe_wait = 0
					_shot_flicker_stage = 4
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the blend leg's On endpoint never rendered")
					_flicker_finish()
			elif _shot_flicker_stage == 4:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 10:
					var dip_img: Image = get_viewport().get_texture().get_image()
					var dfit: Vector2 = _flicker_blend_fit(panel10, dip_img, _shot_flicker_off_img, _shot_flicker_on_img)
					if dfit.y > 0.35:
						_shot_flicker_problems.append("the dip-probe frame does not fit the endpoint blend model (residual %.2f) - the leg cannot judge it" % dfit.y)
					elif dfit.x > 0.06 and dfit.x < 0.94:
						_shot_flicker_problems.append("the rendered dip frame blends the pair (fitted alpha %.2f) - the ghost twin" % dfit.x)
					# The live burst, judged the same way:
					# well-explained frames must sit at an
					# endpoint.
					var judged: int = 0
					for bimg: Image in _shot_flicker_burst:
						var bfit: Vector2 = _flicker_blend_fit(panel10, bimg, _shot_flicker_off_img, _shot_flicker_on_img)
						if bfit.y <= 0.35:
							judged += 1
							if bfit.x > 0.06 and bfit.x < 0.94:
								_shot_flicker_problems.append("a burst frame blends the pair (fitted alpha %.2f, residual %.2f)" % [bfit.x, bfit.y])
								break
					if judged == 0:
						_shot_flicker_problems.append("no burst frame fit the endpoint blend model - the burst judged nothing")
					if _shot_flicker_off_img != null:
						_shot_flicker_off_img.save_png(_shot_flicker_prefix + "_ghost_off.png")
					dip_img.save_png(_shot_flicker_prefix + "_ghost_dip.png")
					if _shot_flicker_on_img != null:
						_shot_flicker_on_img.save_png(_shot_flicker_prefix + "_ghost_on.png")
					_room._power_t = RoomView.POWER_CASCADE_SEC
					_room._apply_power()
					_shot_flicker_stage = 0
					_shot_flicker_armed = false
					_shot_flicker_since = now
					_shot_flicker_phase = 11
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the blend leg's dip frame never rendered")
					_flicker_finish()
		11:
			# Flasher leg (flasher-release round): the
			# Flicker Flasher glass carries two small
			# RomIDType-1 lamps and one giant RomIDType-2
			# solenoid snippet - a bold semi-transparent
			# red band across the whole glass, content the
			# navy base does not carry. The card must
			# cascade all three layers, the flasher
			# VISIBLE mid-cascade, and settle to lamps
			# only: flasher fully released, lamps held
			# lit. Proven by the layer alphas with the
			# cascade clock parked (at the strike, inside
			# the release fade, at the end) and by
			# rendered frames - the red band present in
			# the parked strike frame, absent from the
			# settled frame, whose amber says the lamps
			# stayed. Stages: 0 verify the extracted set
			# (kinds by the file's own RomIDType), 5 idle
			# frames then focus, 1 the live cascade and
			# the parked alpha probes, 2 the rendered
			# strike frame, 3 the rendered settled frame.
			if not _shot_flicker_fixtures.has("Flicker Flasher"):
				_shot_flicker_problems.append("the Flicker Flasher fixture game is not in the library - the flasher leg has no subject")
				_flicker_finish()
				return
			var fx11: Dictionary = _shot_flicker_fixtures["Flicker Flasher"] as Dictionary
			var g11: GameEntry = fx11["game"] as GameEntry
			var panel11: ClickableQuad = fx11.get("panel", null) as ClickableQuad
			if not is_instance_valid(panel11):
				# Same stale-panel exposure as the blend
				# leg (a scan landing mid-run rebuilds the
				# wall): re-resolve from the live wall.
				panel11 = null
				for p11: ClickableQuad in _room._panels:
					if p11.payload == g11.game_id:
						panel11 = p11
						break
				if panel11 != null:
					fx11["panel"] = panel11
			if _shot_flicker_stage == 0:
				if panel11 == null:
					_shot_flicker_problems.append("the Flasher panel is not on the wall - the flasher leg has no card")
					_flicker_finish()
					return
				var data11: Dictionary = g11.ensure_flicker()
				var layers11: Array = data11.get("layers", []) as Array
				var n_flash11: int = 0
				var n_lamp11: int = 0
				var giant11: bool = false
				var bsz11: Vector2i = data11.get("base_size", Vector2i.ZERO) as Vector2i
				for item11: Variant in layers11:
					var ld11: Dictionary = item11 as Dictionary
					if str(ld11.get("kind", "")) == ArtProvider.LAYER_KIND_FLASHER:
						n_flash11 += 1
						var r11: Rect2 = ld11["rect"] as Rect2
						giant11 = r11.size.x > float(bsz11.x) * 0.95 and r11.size.y > float(bsz11.y) * 0.95
					else:
						n_lamp11 += 1
				if bool(data11.get("pair", false)) or layers11.size() != 3 or n_flash11 != 1 or n_lamp11 != 2 or not giant11:
					_shot_flicker_problems.append("the flasher fixture extracted wrong (pair %s, layers %d, flashers %d, lamps %d, giant %s) - want a bulb set of one full-glass flasher over two lamps" % [str(data11.get("pair", false)), layers11.size(), n_flash11, n_lamp11, str(giant11)])
					_flicker_finish()
					return
				# Idle frames before focusing, the blend
				# leg's lesson: a synchronous extraction on
				# this thread must not swallow the settle +
				# cascade into one giant delta frame.
				_shot_flicker_probe_wait = 0
				_shot_flicker_stage = 5
				_shot_flicker_since = now
			elif _shot_flicker_stage == 5:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 6:
					_shot_flicker_flasher_idx = -1
					_room._set_focused(panel11)
					_shot_flicker_stage = 1
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the flasher leg's warm wait never elapsed")
					_flicker_finish()
			elif _shot_flicker_stage == 1:
				var ph11: int = _room.power_phase()
				if _room.power_panel() == panel11 and ph11 > 0 and _shot_flicker_flasher_idx < 0:
					for li11: int in range(_room.power_layer_count()):
						if _room.power_layer_is_flasher(li11):
							_shot_flicker_flasher_idx = li11
							break
				if _room.power_panel() == panel11 and ph11 == 2:
					if _room.power_layer_count() != 3:
						_shot_flicker_problems.append("the flasher card built %d layer quads, want 3 (two lamps + the giant flasher)" % _room.power_layer_count())
					if _shot_flicker_flasher_idx < 0:
						_shot_flicker_problems.append("the flasher card's layers carry no flasher - the room never learned the kind")
						_flicker_finish()
						return
					var sched11: Array = _room._power_schedule[_shot_flicker_flasher_idx] as Array
					var rel11: float = float(sched11[3]) if sched11.size() > 3 else -1.0
					if rel11 < 0.0:
						_shot_flicker_problems.append("the flasher's schedule carries no release - it would hold like a lamp")
						_flicker_finish()
						return
					# Parked alpha probes, deterministic:
					# struck just after its catch, mid-fade
					# inside its release, gone at the
					# cascade's end while the lamps hold.
					_room._power_t = float(sched11[0]) + 0.05
					_room._apply_power()
					var struck11: float = _room.power_layer_alpha(_shot_flicker_flasher_idx)
					if struck11 < 0.9:
						_shot_flicker_problems.append("parked at its strike the flasher reads alpha %.2f, want it lit" % struck11)
					_room._power_t = rel11 + RoomView.POWER_FLASHER_FADE_SEC * 0.5
					_room._apply_power()
					var midfade11: float = _room.power_layer_alpha(_shot_flicker_flasher_idx)
					if midfade11 < 0.05 or midfade11 > 0.95:
						_shot_flicker_problems.append("parked mid-release the flasher reads alpha %.2f - the release is not a fade in flight" % midfade11)
					_room._power_t = RoomView.POWER_CASCADE_SEC
					_room._apply_power()
					var settled11: float = _room.power_layer_alpha(_shot_flicker_flasher_idx)
					if settled11 != 0.0:
						_shot_flicker_problems.append("the flasher is still lit at the cascade's end (alpha %.2f) - it never released" % settled11)
					for li11b: int in range(_room.power_layer_count()):
						if li11b != _shot_flicker_flasher_idx and _room.power_layer_alpha(li11b) != 1.0:
							_shot_flicker_problems.append("a lamp is not held lit at the cascade's end (layer %d alpha %.2f)" % [li11b, _room.power_layer_alpha(li11b)])
					# The rendered strike frame: park the
					# clock back at the strike, let it draw.
					_room._power_t = float(sched11[0]) + 0.05
					_room._apply_power()
					_shot_flicker_probe_wait = 0
					_shot_flicker_stage = 2
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the flasher card's cascade never ran")
					_flicker_finish()
			elif _shot_flicker_stage == 2:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 10:
					var on_img11: Image = get_viewport().get_texture().get_image()
					var red_on11: int = _flicker_red_count_img(panel11, on_img11)
					if red_on11 < 150:
						_shot_flicker_problems.append("the parked strike frame shows no flasher (red px %d) - the giant never rendered" % red_on11)
					on_img11.save_png(_shot_flicker_prefix + "_flasher_on.png")
					_room._power_t = RoomView.POWER_CASCADE_SEC
					_room._apply_power()
					_shot_flicker_probe_wait = 0
					_shot_flicker_stage = 3
					_shot_flicker_since = now
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the flasher leg's strike frame never rendered")
					_flicker_finish()
			elif _shot_flicker_stage == 3:
				_shot_flicker_probe_wait += 1
				if _shot_flicker_probe_wait >= 10:
					var settled_img11: Image = get_viewport().get_texture().get_image()
					var red_off11: int = _flicker_red_count_img(panel11, settled_img11)
					if red_off11 > 10:
						_shot_flicker_problems.append("the settled card still shows the flasher (red px %d) - the ghost stack is still held" % red_off11)
					var amber_set11: int = _flicker_amber_count_img(panel11, settled_img11)
					if amber_set11 < 100:
						_shot_flicker_problems.append("the settled card's lamps are not lit (amber px %d) - the release took the lamps with it" % amber_set11)
					settled_img11.save_png(_shot_flicker_prefix + "_flasher_settled.png")
					_flicker_finish()
				elif now - _shot_flicker_since > 20000:
					_shot_flicker_problems.append("the flasher leg's settled frame never rendered")
					_flicker_finish()


func _save_shot_png(path: String) -> Error:
	var img: Image = get_viewport().get_texture().get_image()
	return img.save_png(path)


## --pvlds-shot-slide P: the page slide's QA hook (the bumper
## feel round). Boots the room, forces the ALL filter through
## the room's own rail handler (the harness library needs its
## stub pages for a flip to exist), lets the wall settle, then
## flips a page through the room's bumper path and captures P
## on the first frame the wall's yaw passes 60% of the slide's
## far point - the old page at full glide, a frame or two
## before the swap. Prints the verdict, quits.
func _drive_shot_slide() -> void:
	match _shot_slide_phase:
		0:
			if _room == null or not _room.visible or not _room.wall_ready:
				return
			_room._handle_rail("filter:all")
			_shot_slide_phase = 1
		1:
			if _room == null or not _room.wall_ready:
				return
			_shot_slide_frames += 1
			if _shot_slide_frames < 8:
				return
			if _room.page_count() < 2:
				printerr("PVLDS SLIDE SHOT: FAIL - the library spans one page, nothing to flip")
				get_tree().quit(1)
				return
			_room._bumper_page(1)
			_shot_slide_phase = 2
		2:
			_shot_slide_frames += 1
			var yaw: float = absf(_room.page_slide_yaw_deg())
			if yaw >= RoomView.PAGE_SLIDE_YAW_DEG * 0.6:
				var path: String = _shot_slide_path
				_shot_slide_phase = -1
				var err: Error = _save_shot_png(path)
				print("PVLDS SLIDE SHOT: ", path, " err=", err, " yaw=", snappedf(yaw, 0.01))
				get_tree().quit(0 if err == OK else 1)
			elif not _room.page_slide_active():
				printerr("PVLDS SLIDE SHOT: FAIL - the slide ended before the capture frame (peak yaw %.2f)" % yaw)
				get_tree().quit(1)
			elif _shot_slide_frames > 3600:
				printerr("PVLDS SLIDE SHOT: FAIL - the slide never engaged")
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


# --------------------------------------------- setup panel smoke

## --pvlds-smoke-setup-panel: the in-room SETUP panel contract.
## The old failure this guards: a smoke once proved a FLAG (the
## desk object existed, its visible flag set) while no surface
## ever reached the player's eyes. So this driver proves the
## SURFACE: SETUP through the rail raises a visible 3D panel in
## the room (not a CanvasLayer), its rows present, focus
## confined to its three buttons, the wall inert behind it -
## then drives its operations for real: SCAN runs Main's scan
## and the landing lands on the panel ONLY (health + message;
## the wall behind keeps its instances and textures, the
## room adopts the scan when the panel closes - the
## after-scan strays contract), and the download runs against
## the harness's local stub database (PVLDS_VPSDB_URL) with
## its verdict on the message line. B and D-pad Right both act
## as BACK (never exit), BACK lands focus on the rail's SETUP
## stop, and the flat route still opens the desk.
func _drive_setup_panel_smoke() -> void:
	match _setup_panel_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_room._xr_enabled = true
				_room._activate(_room.rail_quad("desk"))
				_setup_panel_smoke_wait = 0
				_setup_panel_smoke_phase = 1
			else:
				_setup_panel_smoke_wait += 1
				if _setup_panel_smoke_wait > 3600:
					_setup_panel_smoke_fail("the room never came up")
					_finish_setup_panel_smoke()
		1:
			_setup_panel_smoke_wait += 1
			var face: ClickableQuad = _room.setup_panel_face_quad() if _room != null else null
			var dressed: bool = face != null and face.current_texture() != null \
				and face.current_texture().get_size() == Vector2(1024, 546)
			if _setup_panel_smoke_wait >= 3 and dressed:
				_setup_panel_surface_assertions()
				_setup_panel_smoke_wait = 0
				_setup_panel_smoke_phase = 2
			elif _setup_panel_smoke_wait > 1200:
				_setup_panel_smoke_fail("the panel's face never rendered")
				_finish_setup_panel_smoke()
		2:
			# Snapshot the wall as it stands behind the open
			# panel: instances and textures. The scan leg's
			# verdict (phase 3) is that NONE of it moved - the
			# after-scan strays were wall quads re-dressed in
			# the panel's textures and bare highlight frames,
			# so identity, not resemblance, is the standard.
			_setup_panel_smoke_snapshot_wall()
			_setup_panel_smoke_scan_seen = false
			# The scan leg: fire SCAN through the real funnel.
			_room._activate(_room.setup_panel_scan_quad())
			_setup_panel_smoke_deadline_msec = Time.get_ticks_msec() + 30000
			_setup_panel_smoke_phase = 3
		3:
			if _room.setup_panel_message().begins_with("Scan done") and not _setup_panel_smoke_scan_seen:
				# The landing's renders are still in flight for
				# a few frames; the stray hunt below reads
				# textures, so it waits for them to settle.
				_setup_panel_smoke_scan_seen = true
				_setup_panel_smoke_wait = 0
			elif _setup_panel_smoke_scan_seen:
				_setup_panel_smoke_wait += 1
			if _setup_panel_smoke_scan_seen and _setup_panel_smoke_wait >= 10:
				_setup_panel_expect(not _scan_active, "scan leg: the scan has landed")
				var health: Dictionary = _room.setup_panel_health()
				_setup_panel_expect(int(health.get("files", -1)) == _scanner.total_files,
					"scan leg: the panel's health counts the new scan's tables")
				_setup_panel_expect(int(health.get("missing", -1)) == _scanner.missing_b2s_files.size(),
					"scan leg: the panel's missing-backglass count matches the scan")
				_setup_panel_expect(_room.setup_panel_message().contains(str(_scanner.total_files)),
					"scan leg: the message line states the outcome in words")
				# The deferral (Chris's after-scan strays,
				# 2026-10-25): behind the standing panel the
				# room does NOT adopt the scan - it is held for
				# the panel's close, and the wall the player
				# left is the wall still standing there.
				_setup_panel_expect(_room._pending_library == _scanner,
					"scan leg: the room holds the new scan for the panel's close (no adoption behind the panel)")
				_setup_panel_expect(_room._scanner != _scanner,
					"scan leg: the wall still runs on the library it had when the panel opened")
				_setup_panel_expect(_setup_panel_smoke_wall_untouched(),
					"scan leg: every wall quad kept its instance and its texture through the landing (no strays, no crossed textures)")
				_setup_panel_expect(_setup_panel_smoke_panel_holders() == 1,
					"scan leg: exactly one SETUP panel stands (no duplicate header behind it)")
				_setup_panel_expect(not _setup_panel_smoke_orphan_highlight(),
					"scan leg: no highlight frame shows without a visible quad behind it (no invisible highlighted buttons)")
				_setup_panel_expect(_room.setup_panel_face_quad().current_texture() != null
					and _room.setup_panel_face_quad().current_texture().get_size() == Vector2(1024, 546),
					"scan leg: the panel's face wears its own texture (not a wall texture)")
				_setup_panel_expect(_room.setup_panel_scan_quad().current_texture() != null
					and _room.setup_panel_scan_quad().current_texture().get_size() == Vector2(512, 124),
					"scan leg: SCAN LIBRARY wears its own button face")
				_setup_panel_expect(_room.setup_panel_download_quad().current_texture() != null
					and _room.setup_panel_download_quad().current_texture().get_size() == Vector2(512, 124),
					"scan leg: DOWNLOAD VPS DATABASE wears its own button face")
				_setup_panel_expect(_room.setup_panel_back_quad().current_texture() != null
					and _room.setup_panel_back_quad().current_texture().get_size() == Vector2(512, 164),
					"scan leg: BACK wears its own button face")
				_setup_panel_expect(_room.is_setup_panel_up(), "scan leg: the panel stands through its scan")
				_setup_panel_expect(not _room._setup_scanning, "scan leg: the working state cleared")
				var f: ClickableQuad = _room.focused_quad()
				_setup_panel_expect(f == _room.setup_panel_scan_quad() or f == _room.setup_panel_download_quad() or f == _room.setup_panel_back_quad(),
					"scan leg: focus stayed on the panel through the landing")
				# The download leg: the harness's stub database
				# over local HTTP (PVLDS_VPSDB_URL).
				_room._activate(_room.setup_panel_download_quad())
				_setup_panel_smoke_deadline_msec = Time.get_ticks_msec() + 60000
				_setup_panel_smoke_phase = 4
			elif not _setup_panel_smoke_scan_seen and Time.get_ticks_msec() > _setup_panel_smoke_deadline_msec:
				_setup_panel_smoke_fail("scan leg: the scan never landed on the panel")
				_finish_setup_panel_smoke()
		4:
			var msg: String = _room.setup_panel_message()
			if msg.contains("downloaded"):
				_setup_panel_expect(FileAccess.file_exists(VpsDatabase.CACHE_PATH),
					"download leg: the cache file exists - the next scan resolves to it")
				var cache_len: int = -1
				var cf: FileAccess = FileAccess.open(VpsDatabase.CACHE_PATH, FileAccess.READ)
				if cf != null:
					cache_len = int(cf.get_length())
					cf.close()
				_setup_panel_expect(cache_len > 1000000,
					"download leg: the stored database is the stub's full payload")
				_setup_panel_expect(msg.contains("next scan"),
					"download leg: the message line states the outcome in words")
				_setup_panel_expect(_room._setup_downloader != null and not _room._setup_downloader.is_downloading(),
					"download leg: the downloader is idle at the verdict")
				# The download's landing is panel-only too:
				# it shares the scan's refresh shape, so it
				# proves it did not touch the wall either.
				_setup_panel_expect(_setup_panel_smoke_wall_untouched(),
					"download leg: the wall is still untouched behind the panel (no rebuild, no crossed textures)")
				_setup_panel_expect(not _setup_panel_smoke_orphan_highlight(),
					"download leg: no highlight frame shows without a visible quad behind it")
				_setup_panel_expect(_setup_panel_smoke_panel_holders() == 1,
					"download leg: exactly one SETUP panel stands")
				_setup_panel_smoke_inject(JOY_BUTTON_B, true)
				_setup_panel_smoke_wait = 0
				_setup_panel_smoke_phase = 5
			elif msg.contains("failed") or msg.contains("Could not") or msg.contains("does not look"):
				_setup_panel_smoke_fail("download leg: the download failed on the panel: " + msg)
				_finish_setup_panel_smoke()
			elif Time.get_ticks_msec() > _setup_panel_smoke_deadline_msec:
				_setup_panel_smoke_fail("download leg: the download never landed on the panel")
				_finish_setup_panel_smoke()
		5:
			_setup_panel_smoke_wait += 1
			if _setup_panel_smoke_wait >= 4:
				_setup_panel_smoke_inject(JOY_BUTTON_B, false)
				_setup_panel_expect(not _room.is_setup_panel_up(), "B: the panel closes")
				_setup_panel_expect(_room._focused == _room.rail_quad("desk"),
					"B: focus lands on the rail's SETUP stop")
				var live: bool = true
				for q: ClickableQuad in _room._panels:
					if not q.pick_enabled:
						live = false
				_setup_panel_expect(live, "B: the wall's controls are live again")
				_setup_panel_expect(_room.visible, "B: the room is still up (no exit)")
				# The close contract (Chris, 2026-10-25):
				# exiting setup lands on the Table Select
				# wall - the held scan adopted ONCE at close,
				# the wall a fresh build from it, no panel
				# holder left standing, and the visible
				# scene is cards + rail and nothing else.
				_setup_panel_expect(_room._scanner == _scanner,
					"B: closing the panel adopts the held scan (the room now runs on the new library)")
				_setup_panel_expect(_room._pending_library == null,
					"B: no scan is left held after the close")
				_setup_panel_expect(_room.setup_panel_holder() == null and _setup_panel_smoke_panel_holders() == 0,
					"B: no SETUP panel is left standing (no leftover panel arrangement)")
				var rebuilt: bool = not _room._panels.is_empty() and not _setup_panel_smoke_wall_before.is_empty() \
					and _room._panels[0] != _setup_panel_smoke_wall_before[0]
				_setup_panel_expect(rebuilt,
					"B: the wall is a fresh build from the new scan (rebuilt once, at close - not the pre-scan wall)")
				var wall_scene: bool = _room._mode == "wall" and not _room._panels.is_empty()
				for q2: ClickableQuad in _room._panels:
					if not q2.is_visible_in_tree():
						wall_scene = false
				for k2: Variant in _room._rail_quads.keys():
					var rq2: ClickableQuad = _room._rail_quads[k2] as ClickableQuad
					if rq2 != null and not rq2.is_visible_in_tree():
						wall_scene = false
				_setup_panel_expect(wall_scene,
					"B: the visible scene is the Table Select wall (cards + rail visible, panel gone)")
				# Reopen and leave by D-pad Right instead.
				_room._activate(_room.rail_quad("desk"))
				_setup_panel_smoke_wait = 0
				_setup_panel_smoke_phase = 6
		6:
			_setup_panel_smoke_wait += 1
			if _setup_panel_smoke_wait >= 3:
				_setup_panel_expect(_room.is_setup_panel_up(), "reopen: the panel stands again")
				_setup_panel_smoke_inject(JOY_BUTTON_DPAD_RIGHT, true)
				_setup_panel_smoke_wait = 0
				_setup_panel_smoke_phase = 7
		7:
			_setup_panel_smoke_wait += 1
			if _setup_panel_smoke_wait >= 4:
				_setup_panel_smoke_inject(JOY_BUTTON_DPAD_RIGHT, false)
				_setup_panel_expect(not _room.is_setup_panel_up(), "D-pad Right: the panel closes (BACK, not exit)")
				_setup_panel_expect(_room.visible, "D-pad Right: the room is still up (no exit)")
				_setup_panel_expect(_room._focused == _room.rail_quad("desk"),
					"D-pad Right: focus lands on the rail's SETUP stop")
				# Legacy leg: no XR - SETUP opens the desk.
				_room._xr_enabled = false
				_room._activate(_room.rail_quad("desk"))
				_setup_panel_smoke_wait = 0
				_setup_panel_smoke_phase = 8
		8:
			_setup_panel_smoke_wait += 1
			if _setup_panel_smoke_wait >= 3:
				_setup_panel_expect(not _room.visible, "flat setup: the room hides for the desk, as before")
				_setup_panel_expect(_desk != null and _desk.visible, "flat setup: the desk shows")
				_finish_setup_panel_smoke()


## The deferral snapshot: every wall quad (cards, their
## Launch buttons, the banner, the rail) with the texture it
## wears as the panel's scan starts.
func _setup_panel_smoke_snapshot_wall() -> void:
	_setup_panel_smoke_wall_before.clear()
	_setup_panel_smoke_tex_before.clear()
	var quads: Array[ClickableQuad] = []
	quads.append_array(_room._panels)
	quads.append_array(_room._panel_launches)
	if _room._banner_quad != null:
		quads.append(_room._banner_quad)
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null:
			quads.append(rq)
	_setup_panel_smoke_wall_before = quads
	for q: ClickableQuad in quads:
		_setup_panel_smoke_tex_before[q] = q.current_texture()


## True while every snapshotted wall quad is still the room's
## quad, wearing the texture it wore in the snapshot.
func _setup_panel_smoke_wall_untouched() -> bool:
	var now: Array[ClickableQuad] = []
	now.append_array(_room._panels)
	now.append_array(_room._panel_launches)
	if _room._banner_quad != null:
		now.append(_room._banner_quad)
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null:
			now.append(rq)
	if now.size() != _setup_panel_smoke_wall_before.size():
		return false
	for i: int in range(now.size()):
		if now[i] != _setup_panel_smoke_wall_before[i]:
			return false
		if now[i].current_texture() != _setup_panel_smoke_tex_before.get(now[i], null):
			return false
	return true


## How many SETUP panel holders stand in the room's tree.
func _setup_panel_smoke_panel_holders() -> int:
	var n: int = 0
	for child: Node in _room.get_children():
		if child.name == "SetupPanel":
			n += 1
	return n


## True when any quad's highlight frame is flagged showing
## while its quad's face cannot be seen (not visible in the
## tree, or faded to nothing): the invisible highlighted
## button, as a scene fact.
func _setup_panel_smoke_orphan_highlight() -> bool:
	var quads: Array[ClickableQuad] = []
	quads.append_array(_room._panels)
	quads.append_array(_room._panel_launches)
	if _room._banner_quad != null:
		quads.append(_room._banner_quad)
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null:
			quads.append(rq)
	if _room.setup_panel_face_quad() != null:
		quads.append(_room.setup_panel_face_quad())
	if _room.setup_panel_scan_quad() != null:
		quads.append(_room.setup_panel_scan_quad())
	if _room.setup_panel_download_quad() != null:
		quads.append(_room.setup_panel_download_quad())
	if _room.setup_panel_back_quad() != null:
		quads.append(_room.setup_panel_back_quad())
	for q: ClickableQuad in quads:
		if q.highlight_visible() and (not q.is_visible_in_tree() or q.content_alpha() <= 0.01):
			return true
	return false


func _setup_panel_surface_assertions() -> void:
	_setup_panel_expect(_room.is_setup_panel_up(), "XR setup: the panel is up")
	var holder: Node3D = _room.setup_panel_holder()
	_setup_panel_expect(holder != null, "XR setup: the panel holder exists")
	_setup_panel_expect(holder != null and holder.get_parent() == _room,
		"XR setup: the panel lives in the room's own tree (a 3D surface, not a CanvasLayer)")
	_setup_panel_expect(holder != null and holder.visible, "XR setup: the panel holder is visible")
	_setup_panel_expect(_room.setup_panel_face_quad() != null, "XR setup: the panel has its face (health + message)")
	_setup_panel_expect(_room.setup_panel_scan_quad() != null, "XR setup: the panel has SCAN LIBRARY")
	_setup_panel_expect(_room.setup_panel_download_quad() != null, "XR setup: the panel has DOWNLOAD VPS DATABASE")
	_setup_panel_expect(_room.setup_panel_back_quad() != null, "XR setup: the panel has BACK")
	_setup_panel_expect(_room.visible, "XR setup: the room stays visible")
	_setup_panel_expect(not _room.is_setup_placard_up(), "XR setup: no placard - the desktop route is retired")
	_setup_panel_expect(_desk == null or not _desk.visible, "XR setup: the desk never opens - no desktop trip")
	var health: Dictionary = _room.setup_panel_health()
	_setup_panel_expect(int(health.get("files", -1)) == _scanner.total_files,
		"XR setup: the panel opens knowing the last scan's numbers")
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
	_setup_panel_expect(inert, "XR setup: every wall/rail control is inert behind the panel")
	_setup_panel_expect(_room.setup_panel_scan_quad().pick_enabled
		and _room.setup_panel_download_quad().pick_enabled
		and _room.setup_panel_back_quad().pick_enabled,
		"XR setup: the panel's own buttons are live")
	_setup_panel_expect(_room._focusables.size() == 3
		and _room._focusables.has(_room.setup_panel_scan_quad())
		and _room._focusables.has(_room.setup_panel_download_quad())
		and _room._focusables.has(_room.setup_panel_back_quad()),
		"XR setup: focus navigation is confined to the panel's three buttons")
	_setup_panel_expect(_room._focused == _room.setup_panel_scan_quad(),
		"XR setup: focus opens on SCAN LIBRARY")
	# Confinement under travel: TAB around the stops and
	# focus never leaves the panel.
	for i: int in range(4):
		_room._cycle_focus(1)
		_setup_panel_expect(_room._focusables.has(_room._focused),
			"XR setup: TAB travel stays on the panel (stop %d)" % (i + 1))
	# Refusal: a wall card handed to the funnel does nothing.
	if not _room._panels.is_empty():
		_room._activate(_room._panels[0])
		_setup_panel_expect(_room._mode == "wall" and _room.is_setup_panel_up(),
			"XR setup: a wall activation behind the panel is refused")


func _setup_panel_smoke_inject(button: JoyButton, pressed: bool) -> void:
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _setup_panel_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - setup panel smoke: ", label)
	else:
		_setup_panel_smoke_fail(label)


func _setup_panel_smoke_fail(label: String) -> void:
	_setup_panel_smoke_failures += 1
	printerr("  FAIL - setup panel smoke: ", label)


func _finish_setup_panel_smoke() -> void:
	if _setup_panel_smoke_failures == 0:
		print("PVLDS SETUP PANEL SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS SETUP PANEL SMOKE: FAIL (%d)" % _setup_panel_smoke_failures)
		get_tree().quit(1)


## --pvlds-shot-setup-panel P: open the SETUP panel in the
## room (the room's XR flag forced - the surface the headset
## gets) and capture it once its textures land: the
## clean/CLEAR QA picture.
func _drive_shot_setup_panel() -> void:
	match _shot_setup_panel_phase:
		0:
			if _room == null or not _room.visible or not _room.wall_ready:
				return
			_room._xr_enabled = true
			_room._activate(_room.rail_quad("desk"))
			_shot_setup_panel_phase = 1
		1:
			if _room == null or not _room.is_setup_panel_up():
				return
			_shot_setup_panel_frames += 1
			var face: ClickableQuad = _room.setup_panel_face_quad()
			var dressed: bool = face != null and face.current_texture() != null \
				and face.current_texture().get_size() == Vector2(1024, 546)
			if _shot_setup_panel_after_scan and not _shot_setup_panel_scanned:
				# The after-scan variant (the after-scan strays'
				# framing): fire SCAN through the panel, wait
				# for its landing, then let the room settle
				# before the capture below.
				if dressed and not _shot_setup_panel_scan_fired:
					_shot_setup_panel_scan_fired = true
					_room._activate(_room.setup_panel_scan_quad())
				if _shot_setup_panel_scan_fired and _room.setup_panel_message().begins_with("Scan done"):
					_shot_setup_panel_scanned = true
					_shot_setup_panel_frames = 0
				if _shot_setup_panel_frames > 3600:
					printerr("PVLDS SETUP PANEL SHOT: FAIL - the after-scan capture never landed")
					get_tree().quit(1)
				return
			if _shot_setup_panel_frames >= 12 and dressed:
				var path: String = _shot_setup_panel_path
				_shot_setup_panel_phase = -1
				var err: Error = _save_shot_png(path)
				print("PVLDS SETUP PANEL SHOT: ", path, " err=", err)
				get_tree().quit(0 if err == OK else 1)
			elif _shot_setup_panel_frames > 3600:
				printerr("PVLDS SETUP PANEL SHOT: FAIL - the panel never dressed")
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
##          view. The leg runs async: each flip now rides the
##          page slide (the feel round), so the leg waits out
##          each glide and asserts the settle - and on the
##          first flip, the choreography itself: no swap at
##          the press, the swap lands mid-glide, the wall
##          returns to exact rest, and on the first frame after
##          the swap every rail quad wears a real (non-
##          placeholder) texture - the bar never pops;
##   leg 6: the cards-only focus contract (Chris's ruling,
##          2026-10-24): the wall-mode focusable set holds no
##          Launch button, a DOWN walk down one column visits
##          exactly its three row panels in order, and the
##          A/Y assignment (Chris's swap ruling, 2026-10-26:
##          A starts, Y informs): A on the pad launches the
##          focused card's default build through the Launch
##          button's own path, Y opens its More Info - Y inert
##          on a rail stop and in the detail view, A inert as a
##          launcher everywhere but a wall card. The leg also
##          carries the marquee-leak assertions (2026-10-26):
##          no marquee stands while the detail view is open or
##          during a launch begun from it; a wall launch
##          raises it as always. The launch half runs async
##          against the harness's never-window stub with a
##          zero-length life: the spawn lands in the load wait
##          and the dead pid settles it FAILED, browsing resumes.
##   leg 7: a rail activation keeps focus on the bar (Chris's
##          field report, 2026-10-25): A on a filter stop or
##          the sort stop rebuilds the wall, and focus is still
##          that stop once the rebuild settles - pad path and
##          pointer path alike;
##   leg 8: X flags favorites (Chris's proposal, 2026-10-25):
##          X on a focused card toggles the favorite in the
##          store and the persisted file, the card's face
##          re-renders in place carrying the mark (the panel
##          face's FAVORITE chip; the art face's star badge,
##          pixel-proven through the factory), X is inert on a
##          rail stop and in the load wait, and X-ing OFF
##          inside the FAVORITES filter removes the card with
##          the stated landing - the panel that took its slot,
##          or the ALL fallback's first panel when the set
##          empties.
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
				_nav_leg_cards_only()
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
			if _nav_bumpers_done:
				_nav_smoke_wait = 0
				_nav_smoke_phase = 5
				return
			_nav_smoke_wait += 1
			if _nav_smoke_wait > 7200:
				_nav_smoke_fail("the bumper leg never finished")
				_finish_nav_smoke()
			elif not _nav_bumpers_started and _room != null and _room.wall_ready and _nav_smoke_wait >= 4:
				_nav_bumpers_started = true
				_nav_leg_bumpers_async()
		5:
			if _nav_y_done:
				_nav_smoke_wait = 0
				_nav_smoke_phase = 6
				return
			_nav_smoke_wait += 1
			if _nav_smoke_wait > 7200:
				_nav_smoke_fail("the A/Y-swap leg never finished")
				_finish_nav_smoke()
			elif not _nav_y_started and _room != null and _room.wall_ready and _nav_smoke_wait >= 4:
				_nav_y_started = true
				_nav_leg_ay_swap_async()
		6:
			if _nav_rail_done:
				_nav_smoke_wait = 0
				_nav_smoke_phase = 7
				return
			_nav_smoke_wait += 1
			if _nav_smoke_wait > 7200:
				_nav_smoke_fail("the rail-focus leg never finished")
				_finish_nav_smoke()
			elif not _nav_rail_started and _room != null and _room.wall_ready and _nav_smoke_wait >= 4:
				_nav_rail_started = true
				_nav_leg_rail_focus_async()
		7:
			if _nav_fav_done:
				_finish_nav_smoke()
				return
			_nav_smoke_wait += 1
			if _nav_smoke_wait > 7200:
				_nav_smoke_fail("the X-favorites leg never finished")
				_finish_nav_smoke()
			elif not _nav_fav_started and _room != null and _room.wall_ready and _nav_smoke_wait >= 4:
				_nav_fav_started = true
				_nav_leg_favorites_async()


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


## Leg 6a (the cards-only focus contract): the wall-mode
## focusable set holds NO Launch button - focus visits cards
## and rail stops only - and a DOWN walk down one column
## visits exactly that column's three row panels in order
## before the next DOWN lands on the rail. (The launch half
## of the leg is async; see _nav_leg_y_launch_async.)
func _nav_leg_cards_only() -> void:
	_room._refresh_focusables()
	for q: ClickableQuad in _room._focusables:
		_nav_expect(not _room._panel_launches.has(q),
			"cards-only: no Launch button is a focus stop")
	var stops: int = _room._panels.size()
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null and rq.pick_enabled:
			stops += 1
	_nav_expect(_room._focusables.size() == stops,
		"cards-only: the focus walk is exactly the %d cards + rail stops (got %d)" % [_room._panels.size(), _room._focusables.size()])
	# Column 1 (slots 1, 5, 9): DOWN walks the rows in order.
	_room._set_focused(_room._panels[1])
	for slot: int in [5, 9]:
		_room._move_focus(Vector2(0.0, 1.0))
		_nav_expect(_room.focused_quad() == _room._panels[slot],
			"cards-only: DOWN walks the column - slot %d next" % slot)
	_room._move_focus(Vector2(0.0, 1.0))
	_nav_expect(_nav_key_of(_room.focused_quad()) != "",
		"cards-only: DOWN from the bottom row lands on the rail, never a Launch button")


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


## Waits out the page slide a flip just started, then asserts
## the settle: the slide is over and the wall holder is back
## at EXACT rest - the focus rule's verdicts only mean
## anything on a settled wall.
func _nav_await_slide() -> void:
	var guard: int = 0
	while _room.page_slide_active() and guard < 2400:
		await get_tree().process_frame
		guard += 1
	_nav_expect(not _room.page_slide_active(), "slide: the wall settles after a flip")
	_nav_expect(_room.page_slide_yaw_deg() == 0.0,
		"slide: the wall returns to exact rest (yaw %.4f)" % _room.page_slide_yaw_deg())


## The slide's choreography proof, run on the bumper leg's
## first flip: the press itself does NOT swap the page (the
## swap waits for the far point); mid-glide the wall is off
## rest; in the first frame after the swap lands, every rail
## quad already wears a real (non-placeholder) texture - the
## bar never pops; and the wall settles at exact rest.
func _nav_flip_proof(step: int) -> void:
	var page_before: int = _room._page
	_room._bumper_page(step)
	_nav_expect(_room._page == page_before,
		"slide: the page does not swap at the press - it swaps at the far point")
	var peak: float = 0.0
	var swapped: bool = false
	var guard: int = 0
	while _room.page_slide_active() and guard < 2400:
		await get_tree().process_frame
		guard += 1
		peak = maxf(peak, absf(_room.page_slide_yaw_deg()))
		if not swapped and _room._page != page_before:
			swapped = true
			for k: Variant in _room._rail_quads.keys():
				var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
				var tx: Texture2D = null
				if rq != null:
					tx = rq.current_texture()
				_nav_expect(tx != null and tx.get_width() > 4,
					"rail: %s wears a real texture on the first frame after the flip" % str(k))
	_nav_expect(swapped, "slide: the page swapped during the glide")
	_nav_expect(peak > 1.0, "slide: the wall leaves rest mid-glide (peak yaw %.2f deg)" % peak)
	_nav_expect(not _room.page_slide_active(), "slide: the wall settles after the proof flip")
	_nav_expect(_room.page_slide_yaw_deg() == 0.0,
		"slide: the wall returns to exact rest after the proof flip")


## Leg 5: bumper page travel, driven through RoomView's
## _bumper_page - the same call the pad poll makes on a fresh
## shoulder edge - so the state gating (load wait, placard,
## detail view) is exercised exactly as the room enforces it.
## The harness library spans three pages on ALL (full, full,
## one-panel short), pinned by run_nav_smoke.sh's stub count.
## Async (the feel round): a flip rides the page slide, so
## each travel press is followed by a settle wait before its
## verdicts - the gating presses stay synchronous, since a
## gated press starts no slide at all.
func _nav_leg_bumpers_async() -> void:
	var pages: int = _room.page_count()
	_nav_expect(pages >= 3, "bumpers: the harness library spans at least 3 pages (got %d)" % pages)
	if pages < 2 or _room._visible_games.is_empty():
		_nav_bumpers_done = true
		return
	var filter0: String = _room._filter
	var sort0: String = _room._sort
	var last_page: int = pages - 1
	_nav_expect(_room._page == 0, "bumpers: the leg starts on page 1")
	# Travel, with focus keeping its grid slot. The first flip
	# carries the slide's choreography proof.
	_room._set_focused(_room._panels[5])
	await _nav_flip_proof(1)
	_nav_expect(_room._page == 1, "bumpers: RB advances to page 2")
	_nav_expect(_room.focused_quad() == _room._panels[5],
		"bumpers: focus keeps its grid slot across the flip")
	_room._bumper_page(1)
	await _nav_await_slide()
	_nav_expect(_room._page == last_page, "bumpers: RB advances to the last page")
	_nav_expect(_room.focused_quad() == _room._panels[_room._panels.size() - 1],
		"bumpers: the short last page clamps focus to its last panel")
	# Clamped at the far end: no wrap, focus instance untouched.
	var held: ClickableQuad = _room.focused_quad()
	_room._bumper_page(1)
	_nav_expect(_room._page == last_page, "bumpers: RB clamps on the last page (no wrap)")
	_nav_expect(_room.focused_quad() == held, "bumpers: a clamped RB leaves focus untouched")
	_room._bumper_page(-1)
	await _nav_await_slide()
	_nav_expect(_room._page == last_page - 1, "bumpers: LB retreats a page")
	_room._bumper_page(-1)
	await _nav_await_slide()
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
	await _nav_await_slide()
	_nav_expect(_room._page == 1 and _nav_key_of(_room.focused_quad()) == "sort",
		"bumpers: rail focus carries to the same stop across the flip")
	_room._bumper_page(-1)
	await _nav_await_slide()
	# No focus lands on the first panel.
	_room._set_focused(null)
	_room._bumper_page(1)
	await _nav_await_slide()
	_nav_expect(_room._page == 1 and _room.focused_quad() == _room._panels[0],
		"bumpers: no focus lands on the first panel")
	_room._bumper_page(-1)
	await _nav_await_slide()
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
	_nav_bumpers_done = true


## Feeds one synthetic gamepad press through the Input
## singleton (the dpadexit smoke's feed), so the room's own
## _process poll reads the edge - the shipping input path is
## what the Y leg exercises, not a direct call. Press, two
## frames, release, two frames: the release matters, because
## the room's edge tracking keys off the poll seeing the
## button up again before the next press can count.
func _nav_feed_button(btn: JoyButton) -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = 0
	press.button_index = btn
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	var rel: InputEventJoypadButton = InputEventJoypadButton.new()
	rel.device = 0
	rel.button_index = btn
	rel.pressed = false
	Input.parse_input_event(rel)
	await get_tree().process_frame
	await get_tree().process_frame


## Leg 6b (async - it rides real launch waits): the A/Y
## assignment (Chris's swap ruling, 2026-10-26) and the
## marquee leak. A on the pad launches the focused card's
## default build through the Launch button's own path; Y
## opens the card's More Info. The harness's stub VPX is the
## never-window build with a zero-length life: a spawn lands
## in the load wait (the room deaf, the focusable set
## empty), then the dead pid settles the launch FAILED after
## its grace - Main's own failure path, no hand-off,
## browsing resumes. Y on a rail stop and Y in the detail
## view must do nothing. The marquee assertions ride along:
## a launch begun from the detail view (the detail's own
## Play path, driven directly) must raise NO marquee - the
## year/designer letters stood behind the info card for the
## whole wait (field report, 2026-10-26) - while the wall
## launch below raises it as always.
func _nav_leg_ay_swap_async() -> void:
	var game: GameEntry = _room._visible_games[2]
	# Y on a rail stop is inert.
	_room._set_focused(_room.rail_quad("sort"))
	await _nav_feed_button(JOY_BUTTON_Y)
	_nav_expect(not _launch_pending and _room._mode == "wall",
		"A/Y: a rail-focused Y press opens nothing")
	_nav_expect(_nav_key_of(_room.focused_quad()) == "sort",
		"A/Y: focus stays on the rail stop after the inert press")
	# Y on a focused card opens More Info.
	_room._set_focused(_room._panels[2])
	await _nav_feed_button(JOY_BUTTON_Y)
	_nav_expect(_room._mode == "detail", "A/Y: a card-focused Y press opens More Info")
	_nav_expect(not _launch_pending, "A/Y: the Y press starts no launch")
	_nav_expect(_room.marquee_text().is_empty() and not _room._marquee_up,
		"marquee: no marquee stands while the detail view is open")
	# Y in the detail view is inert.
	await _nav_feed_button(JOY_BUTTON_Y)
	_nav_expect(not _launch_pending and _room._mode == "detail",
		"A/Y: a detail-view Y press does nothing")
	# A launch begun from the detail view, through the
	# detail's own Play path: the room enters the wait, the
	# detail carries its launching state, and NO marquee
	# rises behind the info card.
	var build: TableBuild = game.resolve_default_build(_state)
	_nav_expect(build != null, "marquee: the detail-leg game resolves a default build")
	_room._on_detail_play(game, build)
	var guard: int = 0
	while not _launch_pending and guard < 600:
		await get_tree().process_frame
		guard += 1
	_nav_expect(_launch_pending, "marquee: a detail-view Play starts a launch")
	_nav_expect(_room.is_launch_in_wait(), "marquee: the room is in the load wait")
	_nav_expect(_room.marquee_text().is_empty() and not _room._marquee_up,
		"marquee: no marquee stands during a detail-initiated launch")
	# The dead stub settles it as a failure; the room hands
	# the wait back to the detail view, which then closes
	# to the wall as usual.
	guard = 0
	while _launch_pending and guard < 3600:
		await get_tree().process_frame
		guard += 1
	_nav_expect(not _launch_pending, "marquee: the detail-initiated launch settles")
	_nav_expect(_room._mode == "detail",
		"marquee: the failed settle lands back on the detail view")
	# Close the way production does (the detail's own
	# escape: hide + the closed signal), not by calling the
	# room's handler directly - the handler alone leaves
	# the detail node's own open flag set, and the launch
	# path reads that flag.
	_room._detail.handle_escape()
	_nav_expect(_room._mode == "wall", "A/Y: the detail view closes back to the wall")
	# A on a focused card fires its default build - and a
	# wall-initiated launch raises the marquee as always.
	_room._set_focused(_room._panels[2])
	await _nav_feed_button(JOY_BUTTON_A)
	guard = 0
	while not _launch_pending and guard < 600:
		await get_tree().process_frame
		guard += 1
	_nav_expect(_launch_pending, "A/Y: a card-focused A press starts a launch")
	_nav_expect(_launch_game != null and _launch_game.game_id == game.game_id,
		"A/Y: the launch is the focused card's game")
	_nav_expect(_room.is_launch_in_wait(), "A/Y: the room is in the load wait")
	_nav_expect(_room.focusable_count() == 0, "A/Y: the wait's focusable set is empty")
	_nav_expect(not _room.marquee_text().is_empty(),
		"marquee: a wall-initiated launch raises the marquee again")
	# A second A inside the wait fires nothing.
	var session: int = _launch_session_id
	await _nav_feed_button(JOY_BUTTON_A)
	_nav_expect(_launch_pending and _launch_session_id == session,
		"A/Y: an A press inside the load wait fires nothing")
	# The dead stub settles the launch as a failure; browsing
	# resumes on the wall with the game marked FAILED.
	guard = 0
	while _launch_pending and guard < 3600:
		await get_tree().process_frame
		guard += 1
	_nav_expect(not _launch_pending, "A/Y: the dead-stub launch settles")
	_nav_expect(not _room.is_launch_in_wait() and _room._mode == "wall",
		"A/Y: the room browses again after the failed settle")
	_nav_expect(_room._failed_game_id == game.game_id,
		"A/Y: the settled failure marks the focused card's game FAILED")
	_nav_expect(_room.focusable_count() > 0, "A/Y: the focus walk is restored after the settle")
	_nav_y_done = true


## Waits for the wall's textures to settle after a rebuild
## (a filter/sort activation, a favorite-driven rebuild), so
## a leg's verdicts read the settled wall, then lets a few
## frames pass for good measure.
func _nav_await_ready() -> void:
	var guard: int = 0
	while _room != null and not _room.wall_ready and guard < 3600:
		await get_tree().process_frame
		guard += 1
	if guard >= 3600:
		_nav_smoke_fail("settle: the wall never became ready")
	for i: int in range(3):
		await get_tree().process_frame


## Leg 7: a rail activation keeps focus on the bar (Chris's
## field report, 2026-10-25: "When I click a filter, the
## active cursor jumps back up to top of windows... Needs to
## stay on filter bar."). Driven through the room's real
## input poll with synthetic pad presses: A on a focused
## filter stop changes the filter AND focus is still that
## stop once the rebuild settles; A on the sort stop cycles
## the sort with focus unmoved; and a POINTER activation of
## a filter (pad focus parked on a card) lands focus on the
## activated stop too.
func _nav_leg_rail_focus_async() -> void:
	# Pad path, filter: RECENTS (the Y leg opened a detail
	# view on the way, so recents is non-empty and the
	# empty-filter guard stays out of this leg).
	_room._set_focused(_room.rail_quad("filter:recents"))
	await _nav_feed_button(JOY_BUTTON_A)
	await _nav_await_ready()
	_nav_expect(_room._filter == "recents",
		"rail focus: A on RECENTS activates the recents filter")
	_nav_expect(_nav_key_of(_room.focused_quad()) == "filter:recents",
		"rail focus: focus stays on the activated filter stop (got '%s')" % _nav_key_of(_room.focused_quad()))
	# Pad path, back to ALL.
	_room._set_focused(_room.rail_quad("filter:all"))
	await _nav_feed_button(JOY_BUTTON_A)
	await _nav_await_ready()
	_nav_expect(_room._filter == "all", "rail focus: A on ALL restores the all filter")
	_nav_expect(_nav_key_of(_room.focused_quad()) == "filter:all",
		"rail focus: focus stays on ALL after the rebuild")
	# Pad path, sort: the cycle advances, focus stays on SORT.
	var sort0: String = _room._sort
	_room._set_focused(_room.rail_quad("sort"))
	await _nav_feed_button(JOY_BUTTON_A)
	await _nav_await_ready()
	_nav_expect(_room._sort != sort0, "rail focus: A on SORT cycles the sort")
	_nav_expect(_nav_key_of(_room.focused_quad()) == "sort",
		"rail focus: focus stays on SORT after the rebuild")
	# Cycle the sort home (four stops in the cycle) - focus
	# rides the same stop through every rebuild.
	for i: int in range(3):
		await _nav_feed_button(JOY_BUTTON_A)
		await _nav_await_ready()
	_nav_expect(_room._sort == sort0, "rail focus: the sort cycle returns home")
	_nav_expect(_nav_key_of(_room.focused_quad()) == "sort",
		"rail focus: focus is still on SORT after the full cycle")
	# Pointer path: pad focus parked on a card, the pointer
	# fires the VR filter stop - focus lands on the stop.
	_room._set_focused(_room._panels[0])
	_room._on_select(_room.rail_quad("filter:vr"))
	await _nav_await_ready()
	_nav_expect(_nav_key_of(_room.focused_quad()) == "filter:vr",
		"rail focus: a pointer filter activation lands focus on the activated stop")
	_room._on_select(_room.rail_quad("filter:all"))
	await _nav_await_ready()
	_nav_expect(_room._filter == "all" and _nav_key_of(_room.focused_quad()) == "filter:all",
		"rail focus: the pointer path home lands on ALL, focused")
	_nav_rail_done = true


## Whether a face spec's chips carry the given text.
func _nav_spec_has_chip(spec: Dictionary, text: String) -> bool:
	var chips: Variant = spec.get("chips", [])
	if chips is Array:
		var arr: Array = chips
		for item: Variant in arr:
			if item is Dictionary and str((item as Dictionary).get("text", "")) == text:
				return true
	return false


## Pixel-proves the art face's favorite star: renders the
## game's art spec (with a flat stand-in art texture, so the
## only star-coloured pixels anywhere are the badge's) and
## counts them in the badge's top-right corner.
func _nav_star_pixels(game: GameEntry, art_tex: Texture2D) -> int:
	var tex: Texture2D = await _factory.render_texture(
		RoomSpecs.art_spec(game, art_tex, _state), Vector2i(512, 640))
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return -1
	var star: Color = CardFace.FAVORITE_STAR_COLOR
	var count: int = 0
	for y: int in range(0, 110):
		for x: int in range(img.get_width() - 110, img.get_width()):
			var px: Color = img.get_pixel(x, y)
			if absf(px.r - star.r) < 0.04 and absf(px.g - star.g) < 0.04 and absf(px.b - star.b) < 0.04:
				count += 1
	return count


## Restores the favorites the X leg found on entry (the
## state file is shared with every other harness run) and
## leaves the room browsing ALL.
func _nav_restore_favorites(saved: Array) -> void:
	_state.favorites.clear()
	for k: Variant in saved:
		_state.favorites[str(k)] = true
	_state.save_to_disk()
	if _room != null and _room._filter != "all":
		_room._handle_rail("filter:all")


## Leg 8: X flags favorites (Chris's proposal, 2026-10-25).
## Driven through the real input poll: X on a focused card
## toggles the favorite in the store AND the persisted file,
## and the card's face re-renders in place carrying the mark
## (the panel face's FAVORITE chip in its spec; the art
## face's star badge, pixel-proven through the factory). X
## on a rail stop and X during the load wait are inert. The
## favorites-filter edge: X-ing OFF removes the card - focus
## lands on the panel that took its slot; X-ing off the last
## one empties the set, the guard falls back to ALL, and
## focus lands on its first panel.
func _nav_leg_favorites_async() -> void:
	var saved_favs: Array = _state.favorites.keys()
	# A clean slate for the edge cases: the FAVORITES wall
	# must hold exactly what this leg puts in it.
	_state.favorites.clear()
	_state.save_to_disk()
	_room._handle_rail("filter:all")
	await _nav_await_ready()
	var base: int = _room._page * RoomView.PAGE_SIZE
	var panel_idx: int = -1
	var art_idx: int = -1
	for i: int in range(_room._panels.size()):
		var g: GameEntry = _room._visible_games[base + i]
		if g.ensure_art() != "":
			if art_idx < 0:
				art_idx = i
		elif panel_idx < 0:
			panel_idx = i
	_nav_expect(panel_idx >= 0 and art_idx >= 0,
		"X: the wall offers both a panel-faced and an art-faced card")
	if panel_idx < 0 or art_idx < 0:
		_nav_restore_favorites(saved_favs)
		_nav_fav_done = true
		return
	var panel_game: GameEntry = _room._visible_games[base + panel_idx]
	var art_game: GameEntry = _room._visible_games[base + art_idx]
	# X on a rail stop is inert.
	_room._set_focused(_room.rail_quad("sort"))
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(_state.favorites.is_empty(),
		"X: a rail-focused X press flags nothing")
	# Panel card: X on - store, disk, spec chip, in-place face.
	_room._set_focused(_room._panels[panel_idx])
	var face_before: Texture2D = _room._panels[panel_idx].current_texture()
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(_state.is_favorite(panel_game.game_id),
		"X: the focused panel card's favorite is set in the store")
	var disk: StateStore = StateStore.new()
	disk.load_from_disk()
	_nav_expect(disk.is_favorite(panel_game.game_id),
		"X: the persisted state file agrees")
	_nav_expect(_nav_spec_has_chip(RoomSpecs.panel_spec(panel_game, _state), "FAVORITE"),
		"X: the panel spec carries the FAVORITE chip")
	var guard: int = 0
	while _room._panels[panel_idx].current_texture() == face_before and guard < 600:
		await get_tree().process_frame
		guard += 1
	_nav_expect(_room._panels[panel_idx].current_texture() != face_before,
		"X: the panel card's face re-renders in place")
	# X off again.
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(not _state.is_favorite(panel_game.game_id),
		"X: a second X press clears the favorite")
	_nav_expect(not _nav_spec_has_chip(RoomSpecs.panel_spec(panel_game, _state), "FAVORITE"),
		"X: the panel spec drops the chip with the favorite")
	# Art card: the star badge, pixel-proven through the
	# factory against a flat stand-in art texture.
	var flat: Texture2D = TextureFactory.make_solid(Color(0.2, 0.3, 0.5))
	var star_off: int = await _nav_star_pixels(art_game, flat)
	_nav_expect(star_off == 0,
		"X: the art face shows no star while the game is unfavorited (got %d)" % star_off)
	_room._set_focused(_room._panels[art_idx])
	var art_face_before: Texture2D = _room._panels[art_idx].current_texture()
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(_state.is_favorite(art_game.game_id),
		"X: the focused art card's favorite is set")
	var star_on: int = await _nav_star_pixels(art_game, flat)
	_nav_expect(star_on > 100,
		"X: the art face wears the star badge while favorited (got %d px)" % star_on)
	guard = 0
	while _room._panels[art_idx].current_texture() == art_face_before and guard < 600:
		await get_tree().process_frame
		guard += 1
	_nav_expect(_room._panels[art_idx].current_texture() != art_face_before,
		"X: the art card's face re-renders in place")
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(not _state.is_favorite(art_game.game_id),
		"X: the art card's favorite clears")
	var star_cleared: int = await _nav_star_pixels(art_game, flat)
	_nav_expect(star_cleared == 0,
		"X: clearing the art card's favorite clears its star (got %d)" % star_cleared)
	# The FAVORITES edge: stage two, walk the filter in,
	# then X them off one at a time.
	_room._set_focused(_room._panels[panel_idx])
	await _nav_feed_button(JOY_BUTTON_X)
	_room._set_focused(_room._panels[art_idx])
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(_state.favorites.size() == 2, "X edge: two favorites staged")
	_room._handle_rail("filter:favorites")
	await _nav_await_ready()
	_nav_expect(_room._filter == "favorites" and _room._visible_games.size() == 2,
		"X edge: the favorites wall holds exactly the two")
	var first_game: GameEntry = _room._visible_games[0]
	var second_game: GameEntry = _room._visible_games[1]
	_room._set_focused(_room._panels[0])
	await _nav_feed_button(JOY_BUTTON_X)
	await _nav_await_ready()
	_nav_expect(not _state.is_favorite(first_game.game_id) and _state.is_favorite(second_game.game_id),
		"X edge: the focused card's favorite cleared, the other stands")
	_nav_expect(_room._visible_games.size() == 1 and _room._visible_games[0] == second_game,
		"X edge: the wall now holds the remaining favorite")
	_nav_expect(_room.focused_quad() == _room._panels[0],
		"X edge: focus lands on the panel that took the slot")
	# Inert during the load wait, with a favorite at stake:
	# the press must not clear it on its way past.
	_room.begin_launch(second_game)
	await _nav_feed_button(JOY_BUTTON_X)
	_nav_expect(_state.is_favorite(second_game.game_id) and _room.is_launch_in_wait(),
		"X edge: an X press inside the load wait toggles nothing")
	_room.end_launch_failed(second_game, "nav smoke")
	await _nav_await_ready()
	# The last favorite goes off: the set empties, the
	# guard falls back to ALL, focus on its first panel.
	_room._set_focused(_room._panels[0])
	await _nav_feed_button(JOY_BUTTON_X)
	await _nav_await_ready()
	_nav_expect(_state.favorites.is_empty(), "X edge: the last favorite cleared")
	_nav_expect(_room._filter == "all",
		"X edge: the emptied favorites filter falls back to ALL")
	_nav_expect(not _room._panels.is_empty() and _room.focused_quad() == _room._panels[0],
		"X edge: focus lands on the ALL wall's first panel")
	_nav_restore_favorites(saved_favs)
	_nav_fav_done = true


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


## Base64 of an image's PNG bytes, wrapped at 76 characters
## with the CRLF stored as entities - the exact storage shape
## real designer .directb2s files use (the flicker fixtures
## ride it so the layer reader faces the real file, escapes
## and all).
func _b2s_wrap_b64(img: Image) -> String:
	var raw: String = Marshalls.raw_to_base64(img.save_png_to_buffer())
	var wrapped: String = ""
	var wi: int = 0
	while wi < raw.length():
		if wi > 0:
			wrapped += "&#xD;&#xA;"
		wrapped += raw.substr(wi, 76)
		wi += 76
	return wrapped


## One <Bulb> element in the real file's shape: placement
## rect in glass pixels, visibility, parent surface, and the
## lit snippet as the entity-wrapped Image attribute.
func _b2s_bulb_xml(parent_name: String, vis: String, x: int, y: int, w: int, h: int, img: Image) -> String:
	var par: String = (" Parent=\"%s\"" % parent_name) if parent_name != "" else ""
	return "<Bulb%s ID=\"7\" Name=\"Lamp\" RomID=\"3\" RomIDType=\"Lamp\" RomInverted=\"0\" InitialState=\"0\" DualMode=\"0\" Intensity=\"5\" LightColor=\"255, 200, 60\" DodgeColor=\"0, 0, 0\" Visible=\"%s\" LocX=\"%d\" LocY=\"%d\" Width=\"%d\" Height=\"%d\" IsImageSnippit=\"1\" Image=\"%s\" />" % [par, vis, x, y, w, h, _b2s_wrap_b64(img)]


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


func _write_bytes_file(path: String, bytes: PackedByteArray) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


## A minimal valid OLE/CFB compound file holding the given
## streams ({name, data}), built to the format's letter: 512-byte
## sectors, a FAT, a miniFAT for streams under the 4096-byte
## cutoff, the mini-stream container in the root entry, and a
## directory whose stream entries are right-sibling chained. This
## is the .vpx art round's fixture writer - the harness mirrors
## it in Python (make_vpx_art_fixtures.py) and the two are
## cross-checked, so the reader is never tested only against its
## own writer's habits.
func _cfb_file_bytes(streams: Array) -> PackedByteArray:
	const SECTOR: int = 512
	const MINI: int = 64
	const CUTOFF: int = 4096
	const END: int = 4294967294 # ENDOFCHAIN
	const FREES: int = 4294967295 # FREESECT
	const FATS: int = 4294967293 # FATSECT
	const NOSTREAM: int = 4294967295
	var datas: Array = []
	var is_mini: Array[bool] = []
	var mini_counts: Array[int] = []
	var reg_counts: Array[int] = []
	var mini_total: int = 0
	for s: Variant in streams:
		var data: PackedByteArray = (s as Dictionary)["data"] as PackedByteArray
		datas.append(data)
		var small: bool = data.size() < CUTOFF
		is_mini.append(small)
		if small:
			var mc: int = (data.size() + MINI - 1) / MINI
			mini_counts.append(mc)
			reg_counts.append(0)
			mini_total += mc
		else:
			mini_counts.append(0)
			reg_counts.append((data.size() + SECTOR - 1) / SECTOR)
	var container_sectors: int = (mini_total * MINI + SECTOR - 1) / SECTOR
	var minifat_sectors: int = (mini_total * 4 + SECTOR - 1) / SECTOR if mini_total > 0 else 0
	var dir_sectors: int = ((1 + streams.size()) * 128 + SECTOR - 1) / SECTOR
	var reg_total: int = 0
	for rc: int in reg_counts:
		reg_total += rc
	var base_sectors: int = dir_sectors + minifat_sectors + container_sectors + reg_total
	var fat_sectors: int = 1
	while (base_sectors + fat_sectors) * 4 > fat_sectors * SECTOR:
		fat_sectors += 1
	var total_sectors: int = base_sectors + fat_sectors
	var dir_start: int = 0
	var fat_start: int = dir_start + dir_sectors
	var minifat_start: int = fat_start + fat_sectors
	var container_start: int = minifat_start + minifat_sectors
	# FAT.
	var fat: Array[int] = []
	fat.resize(total_sectors)
	for i: int in range(total_sectors):
		fat[i] = FREES
	var chain_fill: Callable = func(start: int, count: int) -> void:
		for k: int in range(count):
			fat[start + k] = start + k + 1 if k < count - 1 else END
	chain_fill.call(dir_start, dir_sectors)
	for k2: int in range(fat_sectors):
		fat[fat_start + k2] = FATS
	if minifat_sectors > 0:
		chain_fill.call(minifat_start, minifat_sectors)
	if container_sectors > 0:
		chain_fill.call(container_start, container_sectors)
	var reg_starts: Array[int] = []
	var at_sector: int = container_start + container_sectors
	for idx: int in range(streams.size()):
		if is_mini[idx]:
			reg_starts.append(END)
		else:
			reg_starts.append(at_sector)
			chain_fill.call(at_sector, reg_counts[idx])
			at_sector += reg_counts[idx]
	# MiniFAT + each mini stream's first mini sector.
	var minifat: Array[int] = []
	minifat.resize(mini_total)
	for i2: int in range(mini_total):
		minifat[i2] = FREES
	var mini_starts: Array[int] = []
	var at_mini: int = 0
	for idx2: int in range(streams.size()):
		if is_mini[idx2]:
			mini_starts.append(at_mini)
			for k3: int in range(mini_counts[idx2]):
				minifat[at_mini + k3] = at_mini + k3 + 1 if k3 < mini_counts[idx2] - 1 else END
			at_mini += mini_counts[idx2]
		else:
			mini_starts.append(END)
	# Directory records.
	var dir_bytes: PackedByteArray = PackedByteArray()
	var mk_entry: Callable = func(entry_name: String, obj_type: int, right: int, child: int, start: int, size: int) -> PackedByteArray:
		var rec: PackedByteArray = PackedByteArray()
		rec.resize(128)
		var name_bytes: PackedByteArray = entry_name.to_utf16_buffer()
		for j: int in range(mini(name_bytes.size(), 62)):
			rec[j] = name_bytes[j]
		rec.encode_u16(64, name_bytes.size() + 2)
		rec[66] = obj_type
		rec[67] = 1
		rec.encode_u32(68, NOSTREAM)
		rec.encode_u32(72, right)
		rec.encode_u32(76, child)
		rec.encode_u32(116, start)
		rec.encode_u64(120, size)
		return rec
	dir_bytes.append_array(mk_entry.call("Root Entry", 5, NOSTREAM, 1 if not streams.is_empty() else NOSTREAM,
		container_start if container_sectors > 0 else END, mini_total * MINI) as PackedByteArray)
	for idx3: int in range(streams.size()):
		var right: int = idx3 + 2 if idx3 + 1 < streams.size() else NOSTREAM
		var start3: int = mini_starts[idx3] if is_mini[idx3] else reg_starts[idx3]
		dir_bytes.append_array(mk_entry.call(str((streams[idx3] as Dictionary)["name"]), 2, right, NOSTREAM,
			start3, (datas[idx3] as PackedByteArray).size()) as PackedByteArray)
	dir_bytes.resize(dir_sectors * SECTOR)
	# Header (the first 512 bytes, whatever the sector size).
	var header: PackedByteArray = PackedByteArray()
	header.resize(SECTOR)
	var sig: Array[int] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
	for si: int in range(8):
		header[si] = sig[si]
	header.encode_u16(24, 0x003E)
	header.encode_u16(26, 3)
	header.encode_u16(28, 0xFFFE)
	header.encode_u16(30, 9)
	header.encode_u16(32, 6)
	header.encode_u32(44, fat_sectors)
	header.encode_u32(48, dir_start)
	header.encode_u32(56, CUTOFF)
	header.encode_u32(60, minifat_start if minifat_sectors > 0 else END)
	header.encode_u32(64, minifat_sectors)
	header.encode_u32(68, END)
	header.encode_u32(72, 0)
	for fi: int in range(109):
		header.encode_u32(76 + fi * 4, fat_start + fi if fi < fat_sectors else FREES)
	# Assemble: header, then every sector in id order.
	var out: PackedByteArray = PackedByteArray()
	out.append_array(header)
	out.append_array(dir_bytes)
	for fs: int in range(fat_sectors):
		var fsec: PackedByteArray = PackedByteArray()
		fsec.resize(SECTOR)
		for e: int in range(SECTOR / 4):
			var fidx: int = fs * (SECTOR / 4) + e
			fsec.encode_u32(e * 4, fat[fidx] if fidx < total_sectors else FREES)
		out.append_array(fsec)
	for ms: int in range(minifat_sectors):
		var msec: PackedByteArray = PackedByteArray()
		msec.resize(SECTOR)
		for e2: int in range(SECTOR / 4):
			var midx: int = ms * (SECTOR / 4) + e2
			msec.encode_u32(e2 * 4, minifat[midx] if midx < mini_total else FREES)
		out.append_array(msec)
	if container_sectors > 0:
		var container: PackedByteArray = PackedByteArray()
		for idx4: int in range(streams.size()):
			if is_mini[idx4]:
				container.append_array(datas[idx4] as PackedByteArray)
				container.resize((mini_starts[idx4] + mini_counts[idx4]) * MINI)
		container.resize(container_sectors * SECTOR)
		out.append_array(container)
	for idx5: int in range(streams.size()):
		if not is_mini[idx5]:
			var data5: PackedByteArray = (datas[idx5] as PackedByteArray).duplicate()
			data5.resize(reg_counts[idx5] * SECTOR)
			out.append_array(data5)
	return out


## One BIFF record, framed the way BiffWriter frames it:
## [int32 size][4-char tag][payload], the size counting tag +
## payload - so a bare object header (BeginObject) is a record
## of size 4 with no payload at all, its fields following flat.
func _biff_record(tag: String, payload: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(4)
	out.encode_s32(0, 4 + payload.size())
	out.append_array(tag.to_ascii_buffer())
	out.append_array(payload)
	return out


func _biff_string_record(tag: String, value: String) -> PackedByteArray:
	var utf: PackedByteArray = value.to_utf8_buffer()
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(4)
	payload.encode_s32(0, utf.size())
	payload.append_array(utf)
	return _biff_record(tag, payload)


func _biff_int_record(tag: String, value: int) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(4)
	payload.encode_s32(0, value)
	return _biff_record(tag, payload)


## One GameStg Image<n> stream's bytes: a BIFF record sequence
## in Texture::Save's exact order - NAME, PATH, WDTH, HGHT, then
## LINK or the JPEG PinBinary object (NAME, PATH, SIZE, DATA,
## ENDB) or a legacy BITS record, then ALTV, MD5H, OPAQ, ENDB.
## This is the real .vpx layout the embedded extractor walks,
## written by hand here so the fixtures model the format VPX
## writes today, not the raw-stream shape the first embedded
## round imagined. data is the imported image file's bytes,
## stored verbatim in the DATA record (empty = no payload);
## extra holds additional records inserted before the payload
## (unknown-record tolerance probes, e.g. a legacy INME).
func _biff_texture_bytes(tex_name: String, w: int, h: int, data: PackedByteArray, link: bool = false, bits: bool = false, extra: Array = []) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.append_array(_biff_string_record("NAME", tex_name))
	out.append_array(_biff_string_record("PATH", "C:\\tables\\art\\" + tex_name + ".png"))
	out.append_array(_biff_int_record("WDTH", w))
	out.append_array(_biff_int_record("HGHT", h))
	for r: Variant in extra:
		out.append_array(r as PackedByteArray)
	if link:
		out.append_array(_biff_int_record("LINK", 1))
	elif bits:
		out.append_array(_biff_record("BITS", _zero_bytes(2048)))
	elif not data.is_empty():
		out.append_array(_biff_record("JPEG", PackedByteArray()))
		out.append_array(_biff_string_record("NAME", tex_name))
		out.append_array(_biff_string_record("PATH", "C:\\tables\\art\\" + tex_name + ".png"))
		out.append_array(_biff_int_record("SIZE", data.size()))
		out.append_array(_biff_record("DATA", data))
		out.append_array(_biff_record("ENDB", PackedByteArray()))
	out.append_array(_biff_record("ALTV", _zero_bytes(4)))
	out.append_array(_biff_record("MD5H", _zero_bytes(16)))
	out.append_array(_biff_int_record("OPAQ", 1))
	out.append_array(_biff_record("ENDB", PackedByteArray()))
	return out


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
	_expect(warmer.last_pass_items == 2, "the warm pass performed one flat extraction and one (bulb-less) layer extraction - phase two warms the flicker set too", failures)
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
	# file's flat art): a library of just those two performs no
	# FLAT extraction. The cached game's untried layer set is
	# phase two's one extraction; the no-image file is never
	# layer-queued at all (no base anywhere in it).
	var warmer3: ArtWarmer = ArtWarmer.new()
	var skip_games: Array[GameEntry] = [neg_entry, ok_entry]
	warmer3.warm_library(skip_games)
	waited = 0
	while not warmer3.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warmer3.is_idle() and warmer3.last_pass_items == 1
		and ArtProvider.flicker_outcome(b2s_ok) == ArtProvider.STATUS_NO_LAYERS
		and ArtProvider.flicker_outcome(b2s_neg) == "",
		"the warmer skips stamped negatives and cached flat art; the cached game's layers are phase two's one extraction", failures)
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
	# BackglassImage in dual files. The panel art is the OFF
	# half - the unlit glass at rest, in its own shape (400x500,
	# which fits the panel unfitted) - never the lit On half:
	# the On image is the flicker's one layer over this face,
	# and the two halves may disagree in shape entirely (here
	# 800x1000 against 400x500). (Pre-fix the flat reader
	# served the On image: 512x640, already lit, in the On
	# half's proportions.)
	var pair_off: Image = mk_img.call(400, 500) as Image
	var pair_on: Image = mk_img.call(800, 1000) as Image
	var b2s_pair: String = art_dir.path_join("Pair Table.directb2s")
	_expect(_write_text_file(b2s_pair, "<DirectB2SData><Images><BackglassOffImage Value=\"" + Marshalls.raw_to_base64(pair_off.save_png_to_buffer()) + "\" /><BackglassOnImage Value=\"" + Marshalls.raw_to_base64(pair_on.save_png_to_buffer()) + "\" /></Images></DirectB2SData>"),
		"on/off pair fixture written", failures)
	var pair_cache: String = ArtProvider.extract_directb2s_image(b2s_pair)
	var pair_img: Image = Image.new()
	_expect(pair_cache != "" and pair_img.load(pair_cache) == OK and pair_img.get_width() == 400 and pair_img.get_height() == 500,
		"the on/off pair variant extracts its Off image (400x500, the unlit glass at rest)", failures)
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

	# --- Flicker layers (flicker round): the B2S lamp layers
	# the power-on plays, preserved beside the flattened still.
	# Fixtures are built from the REAL .directb2s structure:
	# base image in <Images>, bulbs under <Illumination> with
	# entity-wrapped base64 snippets and glass-pixel rects.
	var fl_solid: Callable = func(w: int, h: int, c: Color) -> Image:
		var im: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		im.fill(c)
		return im
	var fl_glass: Image = fl_solid.call(1000, 800, Color(0.06, 0.08, 0.19)) as Image
	var amber_img: Image = fl_solid.call(300, 120, Color(1.0, 0.75, 0.16)) as Image
	var fl_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(fl_glass.save_png_to_buffer()) + "\" /></Images><Illumination>"
	fl_text += _b2s_bulb_xml("Backglass", "1", 60, 60, 300, 120, amber_img)
	fl_text += _b2s_bulb_xml("Backglass", "1", 420, 60, 300, 120, amber_img)
	fl_text += _b2s_bulb_xml("Backglass", "1", 60, 300, 300, 120, amber_img)
	fl_text += _b2s_bulb_xml("DMD", "1", 10, 10, 100, 50, amber_img)
	fl_text += _b2s_bulb_xml("Backglass", "0", 500, 500, 100, 100, amber_img)
	fl_text += "</Illumination></DirectB2SData>"
	var b2s_fl: String = art_dir.path_join("Layered Table.directb2s")
	_expect(_write_text_file(b2s_fl, fl_text), "layered fixture written", failures)
	var fl: Dictionary = ArtProvider.extract_flicker_layers(b2s_fl)
	_expect(str(fl["status"]) == ArtProvider.STATUS_OK and not bool(fl["pair"]),
		"a layered backglass extracts its layers (status ok, not a pair)", failures)
	_expect((fl["glass_size"] as Vector2i) == Vector2i(1000, 800) and (fl["base_size"] as Vector2i) == Vector2i(512, 410),
		"layer extraction reports the glass size and the fitted base size (1000x800 -> 512x410)", failures)
	var fl_layers: Array = fl["layers"] as Array
	_expect(fl_layers.size() == 3,
		"three glass bulbs become layers - the DMD-parent and Visible=0 bulbs are excluded (%d)" % fl_layers.size(), failures)
	var fl_expect: Array = [[30.72, 30.72, 153.6, 61.44], [215.04, 30.72, 153.6, 61.44], [30.72, 153.6, 153.6, 61.44]]
	var fl_rects_ok: bool = fl_layers.size() == 3
	for fe: Variant in fl_expect:
		var fea: Array = fe as Array
		var found: bool = false
		for fl_item: Variant in fl_layers:
			var rr: Rect2 = (fl_item as Dictionary)["rect"] as Rect2
			if absf(rr.position.x - float(fea[0])) < 0.2 and absf(rr.position.y - float(fea[1])) < 0.2 \
					and absf(rr.size.x - float(fea[2])) < 0.2 and absf(rr.size.y - float(fea[3])) < 0.2:
				found = true
		fl_rects_ok = fl_rects_ok and found
	_expect(fl_rects_ok, "layer rects are carried in fitted coordinates (glass px x 0.512)", failures)
	_expect(ArtProvider.has_flicker_layers(b2s_fl) and ArtProvider.flicker_outcome(b2s_fl) == ArtProvider.STATUS_OK,
		"the layer set reads back as a warm cache hit with an ok outcome", failures)
	var fl_meta_text: String = FileAccess.get_file_as_string(ArtProvider.layers_meta_path(b2s_fl))
	var fl2: Dictionary = ArtProvider.extract_flicker_layers(b2s_fl)
	_expect((fl2["layers"] as Array).size() == 3 and FileAccess.get_file_as_string(ArtProvider.layers_meta_path(b2s_fl)) == fl_meta_text,
		"a second extraction serves the sibling cache untouched (extracted once)", failures)
	var fl_entry: GameEntry = GameEntry.new()
	fl_entry.art_source_path = b2s_fl
	_expect(fl_entry.flicker_source() == b2s_fl and (fl_entry.ensure_flicker()["layers"] as Array).size() == 3,
		"GameEntry.ensure_flicker serves the layer set under the claim discipline", failures)
	var fl_side_entry: GameEntry = GameEntry.new()
	fl_side_entry.art_path = art_dir.path_join("side.png")
	_expect(fl_side_entry.flicker_source() == "" and fl_side_entry.ensure_flicker().is_empty(),
		"a side-image game has no flicker layers (the brightness fallback's country)", failures)
	# A full-glass-sized bulb image: the layer is its rect region.
	var full_glass: Image = fl_solid.call(400, 500, Color(1.0, 0.75, 0.16)) as Image
	var fg_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64((fl_solid.call(400, 500, Color(0.05, 0.05, 0.1)) as Image).save_png_to_buffer()) + "\" /></Images><Illumination>"
	fg_text += _b2s_bulb_xml("Backglass", "1", 100, 100, 200, 150, full_glass)
	fg_text += "</Illumination></DirectB2SData>"
	var b2s_fg: String = art_dir.path_join("Full Glass Bulb Table.directb2s")
	_expect(_write_text_file(b2s_fg, fg_text), "full-glass bulb fixture written", failures)
	var fg: Dictionary = ArtProvider.extract_flicker_layers(b2s_fg)
	var fg_layers: Array = fg["layers"] as Array
	var fg_img: Image = Image.new()
	_expect(fg_layers.size() == 1 and fg_img.load(str((fg_layers[0] as Dictionary)["path"])) == OK
		and fg_img.get_size() == Vector2i(200, 150),
		"a full-glass bulb image is cropped to its rect (200x150 layer)", failures)
	var fg_px: Color = fg_img.get_pixel(100, 75)
	_expect(fg_px.r > 0.9 and fg_px.g > 0.6 and fg_px.g < 0.85 and fg_px.b < 0.3,
		"the cropped layer carries the bulb's lit art (amber)", failures)
	# An on/off pair: base is the Off image, the one layer is the
	# full-frame On image.
	var pair_off2: Image = fl_solid.call(400, 500, Color(0.04, 0.04, 0.08)) as Image
	var pair_on2: Image = fl_solid.call(400, 500, Color(1.0, 0.75, 0.16)) as Image
	var b2s_fl_pair: String = art_dir.path_join("Flicker Pair Table.directb2s")
	_expect(_write_text_file(b2s_fl_pair, "<DirectB2SData><Images><BackglassOffImage Value=\"" + Marshalls.raw_to_base64(pair_off2.save_png_to_buffer()) + "\" /><BackglassOnImage Value=\"" + Marshalls.raw_to_base64(pair_on2.save_png_to_buffer()) + "\" /></Images></DirectB2SData>"),
		"pair fixture written", failures)
	var flp: Dictionary = ArtProvider.extract_flicker_layers(b2s_fl_pair)
	var flp_layers: Array = flp["layers"] as Array
	_expect(bool(flp["pair"]) and flp_layers.size() == 1 and ((flp_layers[0] as Dictionary)["rect"] as Rect2) == Rect2(0, 0, 400, 500),
		"an on/off pair yields base + one full-frame lit layer", failures)
	# The pair's halves in DIFFERENT shapes, solid colors so
	# the content itself testifies (flicker fix round 2): the
	# flat face is the Off image (400x500, dark), not the On
	# image resampled into anything; the layer set's base is
	# that same Off glass and its one layer covers it whole.
	var adv_off: Image = fl_solid.call(400, 500, Color(0.04, 0.04, 0.08)) as Image
	var adv_on: Image = fl_solid.call(800, 1000, Color(1.0, 0.75, 0.16)) as Image
	var b2s_adv_pair: String = art_dir.path_join("Adversarial Pair Table.directb2s")
	_expect(_write_text_file(b2s_adv_pair, "<DirectB2SData><Images><BackglassOffImage Value=\"" + Marshalls.raw_to_base64(adv_off.save_png_to_buffer()) + "\" /><BackglassOnImage Value=\"" + Marshalls.raw_to_base64(adv_on.save_png_to_buffer()) + "\" /></Images></DirectB2SData>"),
		"adversarial pair fixture written", failures)
	var adv_cache: String = ArtProvider.extract_directb2s_image(b2s_adv_pair)
	var adv_img: Image = Image.new()
	var adv_px: Color = Color(1, 1, 1)
	if adv_cache != "" and adv_img.load(adv_cache) == OK:
		adv_px = adv_img.get_pixel(200, 250)
	_expect(adv_img.get_size() == Vector2i(400, 500) and adv_px.r < 0.1 and adv_px.b > adv_px.r + 0.02,
		"an adversarial pair's face is its Off half (400x500, dark), not the On half in any shape", failures)
	var adv_fl: Dictionary = ArtProvider.extract_flicker_layers(b2s_adv_pair)
	var adv_fl_layers: Array = adv_fl["layers"] as Array
	_expect(bool(adv_fl["pair"]) and (adv_fl["base_size"] as Vector2i) == Vector2i(400, 500)
		and adv_fl_layers.size() == 1 and ((adv_fl_layers[0] as Dictionary)["rect"] as Rect2) == Rect2(0, 0, 400, 500),
		"an adversarial pair's layer set bases on the Off glass in its own space", failures)
	# Pair + plain - the triple divergence: a plain backglass
	# AND a decoy pair in one file. Both readers must ignore
	# the halves entirely: face and base are the plain image,
	# the layers are its bulbs, the set is not a pair. (The
	# v1 readers split three ways here - face from the plain
	# image, base from the decoy Off, layer from the decoy On.)
	var pp_plain: Image = fl_solid.call(400, 500, Color(0.06, 0.08, 0.19)) as Image
	var pp_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(pp_plain.save_png_to_buffer()) + "\" /><BackglassOffImage Value=\"" + Marshalls.raw_to_base64((fl_solid.call(300, 300, Color(0.35, 0.08, 0.08)) as Image).save_png_to_buffer()) + "\" /><BackglassOnImage Value=\"" + Marshalls.raw_to_base64((fl_solid.call(300, 300, Color(1.0, 0.75, 0.16)) as Image).save_png_to_buffer()) + "\" /></Images><Illumination>"
	pp_text += _b2s_bulb_xml("Backglass", "1", 60, 60, 300, 120, amber_img)
	pp_text += _b2s_bulb_xml("Backglass", "1", 60, 300, 300, 120, amber_img)
	pp_text += "</Illumination></DirectB2SData>"
	var b2s_pp: String = art_dir.path_join("Pair Plain Table.directb2s")
	_expect(_write_text_file(b2s_pp, pp_text), "pair+plain fixture written", failures)
	var pp_cache: String = ArtProvider.extract_directb2s_image(b2s_pp)
	var pp_img: Image = Image.new()
	var pp_px: Color = Color(1, 1, 1)
	if pp_cache != "" and pp_img.load(pp_cache) == OK:
		pp_px = pp_img.get_pixel(200, 250)
	_expect(pp_img.get_size() == Vector2i(400, 500) and pp_px.b > pp_px.r + 0.05,
		"pair+plain: the flat face is the plain image (navy), not either pair half", failures)
	var pp_fl: Dictionary = ArtProvider.extract_flicker_layers(b2s_pp)
	_expect(not bool(pp_fl["pair"]) and (pp_fl["layers"] as Array).size() == 2
		and (pp_fl["base_size"] as Vector2i) == Vector2i(400, 500),
		"pair+plain: the layer set is bulb-style over the plain image, the decoy pair ignored", failures)
	var pp_base: Image = Image.new()
	_expect(pp_cache != "" and pp_base.load(str(pp_fl["base_path"])) == OK and pp_base.get_data() == pp_img.get_data(),
		"pair+plain: the layer set's base and the flat face are the same image", failures)
	# Layer kinds (flasher-release round): the file's own
	# RomIDType classifies each layer - 2 is a solenoid
	# FLASHER (momentary on the machine; the room flashes
	# and releases it), anything else a LAMP. The pair's one
	# layer is a lamp by construction. The meta on disk
	# carries the kinds under the current layer generation,
	# so a kind-less cached set can never be served.
	_expect(str(((flp["layers"] as Array)[0] as Dictionary).get("kind", "")) == ArtProvider.LAYER_KIND_LAMP,
		"a pair set's one layer is a lamp (it holds)", failures)
	var kind_bulb: Callable = func(rom_type: String, x: int, y: int, w: int, h: int, img: Image) -> String:
		var rt: String = (" RomIDType=\"%s\"" % rom_type) if rom_type != "" else ""
		return "<Bulb Parent=\"Backglass\" ID=\"7\" Name=\"Lamp\" RomID=\"3\"%s RomInverted=\"0\" InitialState=\"0\" DualMode=\"0\" Intensity=\"5\" Visible=\"1\" LocX=\"%d\" LocY=\"%d\" Width=\"%d\" Height=\"%d\" IsImageSnippit=\"1\" Image=\"%s\" />" % [rt, x, y, w, h, _b2s_wrap_b64(img)]
	var kind_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(fl_glass.save_png_to_buffer()) + "\" /></Images><Illumination>"
	kind_text += kind_bulb.call("1", 60, 60, 300, 120, amber_img) as String
	kind_text += kind_bulb.call("2", 0, 0, 1000, 800, fl_solid.call(1000, 800, Color(1.0, 0.16, 0.16, 0.66)) as Image) as String
	kind_text += kind_bulb.call("", 420, 300, 300, 120, amber_img) as String
	kind_text += "</Illumination></DirectB2SData>"
	var b2s_kind: String = art_dir.path_join("Kind Table.directb2s")
	_expect(_write_text_file(b2s_kind, kind_text), "kind fixture written", failures)
	var kind_fl: Dictionary = ArtProvider.extract_flicker_layers(b2s_kind)
	var kind_layers: Array = kind_fl["layers"] as Array
	var kind_flashers: int = 0
	var kind_lamps: int = 0
	var kind_giant_is_flasher: bool = false
	for kind_item: Variant in kind_layers:
		var kd: Dictionary = kind_item as Dictionary
		var krect: Rect2 = kd["rect"] as Rect2
		if str(kd.get("kind", "")) == ArtProvider.LAYER_KIND_FLASHER:
			kind_flashers += 1
			# The flasher is the full-glass snippet (1000x800
			# in glass px, ~512x410 fitted); a small bulb
			# wearing the kind would fail here.
			kind_giant_is_flasher = krect.size.x > 480.0 and krect.size.y > 390.0
		else:
			kind_lamps += 1
	_expect(kind_layers.size() == 3 and kind_flashers == 1 and kind_lamps == 2 and kind_giant_is_flasher,
		"RomIDType classifies the layers: the type-2 full-glass bulb is the one flasher, the type-1 and untyped bulbs are lamps", failures)
	var kind_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(ArtProvider.layers_meta_path(b2s_kind)))
	var kind_meta_flashers: int = 0
	if kind_meta is Dictionary:
		for km_item: Variant in (kind_meta as Dictionary).get("layers", []):
			if str((km_item as Dictionary).get("kind", "")) == ArtProvider.LAYER_KIND_FLASHER:
				kind_meta_flashers += 1
	_expect(kind_meta is Dictionary and int((kind_meta as Dictionary).get("lv", 0)) == ArtProvider.LAYERS_VERSION
		and kind_meta_flashers == 1,
		"the layer meta carries the kinds under generation lv%d (one flasher of three)" % ArtProvider.LAYERS_VERSION, failures)
	# No illumination at all: a plain still, stamped no_layers.
	var b2s_fl_none: String = art_dir.path_join("Plain Table.directb2s")
	_expect(_write_text_file(b2s_fl_none, "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(pair_off2.save_png_to_buffer()) + "\" /></Images><Illumination></Illumination></DirectB2SData>"),
		"layerless fixture written", failures)
	_expect(str(ArtProvider.extract_flicker_layers(b2s_fl_none)["status"]) == ArtProvider.STATUS_NO_LAYERS
		and ArtProvider.flicker_outcome(b2s_fl_none) == ArtProvider.STATUS_NO_LAYERS
		and not ArtProvider.has_flicker_layers(b2s_fl_none),
		"a backglass without usable bulbs stamps no_layers (remembered, not retried)", failures)
	# A designated base that will not decode: failed, even with
	# healthy bulbs riding along.
	var bad_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(_zero_bytes(300)) + "\" /></Images><Illumination>"
	bad_text += _b2s_bulb_xml("Backglass", "1", 60, 60, 300, 120, amber_img)
	bad_text += "</Illumination></DirectB2SData>"
	var b2s_fl_bad: String = art_dir.path_join("Corrupt Layers Table.directb2s")
	_expect(_write_text_file(b2s_fl_bad, bad_text), "corrupt-base fixture written", failures)
	_expect(str(ArtProvider.extract_flicker_layers(b2s_fl_bad)["status"]) == ArtProvider.STATUS_FAILED
		and ArtProvider.is_flicker_negative(ArtProvider.flicker_outcome(b2s_fl_bad)),
		"an undecodable base stamps the layer extraction failed", failures)
	# The cap: 45 bulbs in rising sizes keeps the largest 40.
	var cap_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(fl_glass.save_png_to_buffer()) + "\" /></Images><Illumination>"
	for ci: int in range(45):
		var cw: int = 10 + ci
		cap_text += _b2s_bulb_xml("Backglass", "1", (ci % 9) * 110, (ci / 9) * 160, cw, 20, fl_solid.call(cw, 20, Color(1.0, 0.75, 0.16)) as Image)
	cap_text += "</Illumination></DirectB2SData>"
	var b2s_cap: String = art_dir.path_join("Many Bulbs Table.directb2s")
	_expect(_write_text_file(b2s_cap, cap_text), "cap fixture written", failures)
	var cap: Dictionary = ArtProvider.extract_flicker_layers(b2s_cap)
	var cap_layers: Array = cap["layers"] as Array
	var cap_min_w: float = 1e9
	for cap_item: Variant in cap_layers:
		cap_min_w = minf(cap_min_w, ((cap_item as Dictionary)["rect"] as Rect2).size.x)
	var cap_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(ArtProvider.layers_meta_path(b2s_cap)))
	_expect(cap_layers.size() == ArtProvider.LAYER_CAP and cap_min_w > 7.6
		and cap_meta is Dictionary and int((cap_meta as Dictionary).get("dropped", 0)) == 5,
		"45 bulbs cap at %d layers, the largest kept, the drop counted in the meta" % ArtProvider.LAYER_CAP, failures)
	# The library's median art aspect (sizing half (a)'s input).
	var med_paths: Array[String] = []
	for mi2: int in range(3):
		var mp: String = art_dir.path_join("median_%d.png" % mi2)
		var mdims: Array = [[512, 640], [400, 500], [300, 600]][mi2]
		(fl_solid.call(int(mdims[0]), int(mdims[1]), Color(0.2, 0.2, 0.2)) as Image).save_png(mp)
		med_paths.append(mp)
	var med_games: Array[GameEntry] = []
	for mp2: String in med_paths:
		var mg: GameEntry = GameEntry.new()
		mg.art_path = mp2
		med_games.append(mg)
	_expect(absf(ArtProvider.library_art_median_aspect(med_games) - 0.8) < 0.001,
		"the median art aspect comes from the library's own art (0.5, 0.8, 0.8 -> 0.8)", failures)
	_expect(ArtProvider.library_art_median_aspect([]) == 0.0,
		"no readable art, no median (the caller keeps its default proportions)", failures)
	# Prune: a layer set dies with its source. The keep set
	# names only the layered fixture's flat path, so the pair
	# fixture's set and outcome must go, and its own survive.
	var keep_map: Dictionary = {ArtProvider.cache_path_for(b2s_fl): true}
	ArtProvider.prune_cache(keep_map)
	_expect(ArtProvider.has_flicker_layers(b2s_fl),
		"prune keeps the layer set of a library source", failures)
	_expect(not FileAccess.file_exists(ArtProvider.layers_meta_path(b2s_fl_pair)) and ArtProvider.flicker_outcome(b2s_fl_pair) == "",
		"prune removes an orphaned layer set and its outcome", failures)

	# --- The wart, deep-fixed (flicker fix round 2) + warmer
	# phase two. The wart: a .directb2s whose designated
	# DMDImage is corrupt and whose real glass lives in a
	# non-designated blob (a ReelImage). Under the split
	# readers the flat path convicted the file at the
	# designated step and never reached its blob fallback -
	# flat FAILED, face fell through to another source -
	# while the layers reader, whose narrower designated
	# search saw nothing, fell back and found the base, so
	# the lamps composited over a stranger's face. One
	# finder now: a corrupt designated element does not
	# veto the fallback, the flat face IS the base the
	# lamps extract over (same image, pixel for pixel),
	# and the game wears its own glass.
	var wart_noise: Image = mk_img.call(600, 400) as Image
	var wart_text: String = "<DirectB2SData><Images><DMDImage Value=\"" + Marshalls.raw_to_base64(_zero_bytes(300)) + "\" /><ReelImage Value=\"" + Marshalls.raw_to_base64(wart_noise.save_png_to_buffer()) + "\" /></Images><Illumination>"
	wart_text += _b2s_bulb_xml("Backglass", "1", 0, 0, 600, 400, fl_solid.call(600, 400, Color(1.0, 0.75, 0.16)) as Image)
	wart_text += _b2s_bulb_xml("Backglass", "1", 20, 20, 100, 60, amber_img)
	wart_text += _b2s_bulb_xml("Backglass", "1", 200, 100, 120, 80, amber_img)
	wart_text += "</Illumination></DirectB2SData>"
	var b2s_wart: String = art_dir.path_join("Wart Table.directb2s")
	_expect(_write_text_file(b2s_wart, wart_text), "wart fixture written", failures)
	var wart_face: String = ArtProvider.extract_art_image(b2s_wart)
	_expect(wart_face == ArtProvider.cache_path_for(b2s_wart) and ArtProvider.outcome_for_source(b2s_wart) == ArtProvider.STATUS_OK,
		"wart: the flat extraction finds the base behind the corrupt designated DMD image", failures)
	var wart_layers: Dictionary = ArtProvider.extract_flicker_layers(b2s_wart)
	_expect(str(wart_layers["status"]) == ArtProvider.STATUS_OK and (wart_layers["layers"] as Array).size() == 3,
		"wart: the same file's layers extract over that base", failures)
	var wart_face_img: Image = Image.new()
	var wart_base_img: Image = Image.new()
	_expect(wart_face_img.load(wart_face) == OK and wart_base_img.load(str(wart_layers["base_path"])) == OK
		and wart_face_img.get_data() == wart_base_img.get_data(),
		"wart: the flat face and the layer set's base are the same image", failures)
	var wart_entry: GameEntry = GameEntry.new()
	wart_entry.art_source_path = b2s_wart
	_expect(wart_entry.ensure_art() == wart_face and wart_entry.flicker_source() == b2s_wart and not wart_entry.ensure_flicker().is_empty(),
		"wart: the entry's face is its own backglass and its layers serve", failures)
	# Warmer phase two: a bulb-bearing game is warmed flat
	# first, layers second, in ONE pass - polled, so the order
	# is observed, not assumed.
	var pf_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(fl_glass.save_png_to_buffer()) + "\" /></Images><Illumination>"
	pf_text += _b2s_bulb_xml("Backglass", "1", 60, 60, 300, 120, amber_img)
	pf_text += "</Illumination></DirectB2SData>"
	var b2s_pf: String = art_dir.path_join("Prefetch Table.directb2s")
	_expect(_write_text_file(b2s_pf, pf_text), "prefetch fixture written", failures)
	var pf_entry: GameEntry = GameEntry.new()
	pf_entry.art_source_path = b2s_pf
	var pf_warmer: ArtWarmer = ArtWarmer.new()
	pf_warmer.warm_library([pf_entry])
	var pf_flat_at: int = -1
	var pf_layer_at: int = -1
	var pf_waited: int = 0
	while pf_waited < 30000:
		if pf_flat_at < 0 and ArtProvider.is_cached(b2s_pf):
			pf_flat_at = pf_waited
		if pf_layer_at < 0 and ArtProvider.flicker_outcome(b2s_pf) != "":
			pf_layer_at = pf_waited
		if pf_flat_at >= 0 and pf_layer_at >= 0 and pf_warmer.is_idle():
			break
		OS.delay_msec(5)
		pf_waited += 5
	_expect(pf_flat_at >= 0 and pf_layer_at >= 0 and pf_flat_at <= pf_layer_at,
		"warmer phase two: the flat extraction lands before the layer outcome (flat %d ms, layers %d ms)" % [pf_flat_at, pf_layer_at], failures)
	_expect(pf_warmer.last_pass_items == 2 and ArtProvider.has_flicker_layers(b2s_pf),
		"warmer phase two: one pass performs the flat and the layer extraction, and the set waits warm", failures)
	# Once per game ever: a second pass over the same library
	# extracts nothing - both stamps stand.
	var pf_warmer2: ArtWarmer = ArtWarmer.new()
	pf_warmer2.warm_library([pf_entry])
	pf_waited = 0
	while not pf_warmer2.is_idle() and pf_waited < 20000:
		OS.delay_msec(20)
		pf_waited += 20
	_expect(pf_warmer2.is_idle() and pf_warmer2.last_pass_items == 0,
		"warmer phase two: stamped layer outcomes are never re-queued", failures)
	# The wart under the warmer: a fresh wart file warms
	# flat in the pass (the unified finder reads its base
	# through the blob fallback, where the split readers
	# stamped it FAILED) and its layers are prefetched in
	# the same pass.
	var b2s_wart2: String = art_dir.path_join("Wart Warm Table.directb2s")
	_expect(_write_text_file(b2s_wart2, wart_text), "wart warm fixture written", failures)
	var wart2_entry: GameEntry = GameEntry.new()
	wart2_entry.art_source_path = b2s_wart2
	var wart_warmer: ArtWarmer = ArtWarmer.new()
	wart_warmer.warm_library([wart2_entry])
	pf_waited = 0
	while not wart_warmer.is_idle() and pf_waited < 30000:
		OS.delay_msec(20)
		pf_waited += 20
	_expect(wart_warmer.is_idle() and ArtProvider.has_flicker_layers(b2s_wart2)
		and ArtProvider.outcome_for_source(b2s_wart2) == ArtProvider.STATUS_OK,
		"warmer phase two: the wart warms flat and layers in one pass", failures)

	# --- Embedded art: images extracted from inside .vpx files.
	# The fixtures are REAL compound files written by
	# _cfb_file_bytes whose GameStg Image<n> streams carry BIFF
	# record sequences written by _biff_texture_bytes in
	# Texture::Save's record order - the layout VPX actually
	# writes. (The first embedded round's fixtures held raw image
	# streams, a shape no real .vpx has, and its offset-0 reader
	# found art in only 11 of Chris's 81 real files; this
	# section's fixtures model the real format, and the harness
	# cross-checks the walker against real VPX files.) Order
	# proven here: sidecar > backglass > embedded > title card;
	# extraction is lazy, cached, and its outcomes are remembered
	# like every other source's.
	var solid_img: Callable = func(w: int, h: int) -> Image:
		var im: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		im.fill(Color(0.25, 0.4, 0.6))
		return im
	var chaff: PackedByteArray = PackedByteArray()
	while chaff.size() < 6000:
		chaff.append_array("not an image, just table data".to_utf8_buffer())
	var fx_glass: String = art_dir.path_join("Embedded Glass.vpx")
	_expect(_write_bytes_file(fx_glass, _cfb_file_bytes([
		{"name": "GameData", "data": chaff},
		{"name": "Image0", "data": _biff_texture_bytes("Playfield", 600, 600, (mk_img.call(600, 600) as Image).save_png_to_buffer())},
		{"name": "Image1", "data": _biff_texture_bytes("Backglass", 400, 500, (mk_img.call(400, 500) as Image).save_png_to_buffer(), false, false, [_biff_record("INME", _zero_bytes(4))])},
		{"name": "Image2", "data": _biff_texture_bytes("insertcoin", 64, 64, (mk_img.call(64, 64) as Image).save_png_to_buffer())},
	])), "embedded fixture: glass table written", failures)
	var fx_field: String = art_dir.path_join("Embedded Field.vpx")
	_expect(_write_bytes_file(fx_field, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("cabart", 900, 700, (mk_img.call(900, 700) as Image).save_png_to_buffer())},
		{"name": "Image1", "data": _biff_texture_bytes("Playfield", 500, 400, (mk_img.call(500, 400) as Image).save_png_to_buffer())},
	])), "embedded fixture: field table written", failures)
	var fx_big: String = art_dir.path_join("Embedded Largest.vpx")
	_expect(_write_bytes_file(fx_big, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("tex_a", 300, 300, (mk_img.call(300, 300) as Image).save_png_to_buffer())},
		{"name": "Image1", "data": _biff_texture_bytes("decal", 120, 120, (mk_img.call(120, 120) as Image).save_png_to_buffer())},
		{"name": "Image2", "data": _biff_texture_bytes("tex_b", 900, 700, (mk_img.call(900, 700) as Image).save_png_to_buffer())},
	])), "embedded fixture: largest table written", failures)
	var fx_mini: String = art_dir.path_join("Embedded Mini.vpx")
	_expect(_write_bytes_file(fx_mini, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("Playfield", 320, 240, (solid_img.call(320, 240) as Image).save_png_to_buffer())},
	])), "embedded fixture: mini-stream table written", failures)
	var fx_link: String = art_dir.path_join("Embedded Link.vpx")
	_expect(_write_bytes_file(fx_link, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("Playfield", 800, 600, PackedByteArray(), true)},
		{"name": "Image1", "data": _biff_texture_bytes("cabart", 900, 700, (mk_img.call(900, 700) as Image).save_png_to_buffer())},
		{"name": "Screenshot", "data": (mk_img.call(800, 600) as Image).save_png_to_buffer()},
	])), "embedded fixture: link table written", failures)
	var fx_shot: String = art_dir.path_join("Embedded Shot.vpx")
	_expect(_write_bytes_file(fx_shot, _cfb_file_bytes([
		{"name": "GameData", "data": chaff},
		{"name": "Screenshot", "data": (mk_img.call(500, 375) as Image).save_png_to_buffer()},
	])), "embedded fixture: screenshot-only table written", failures)
	var fx_bits: String = art_dir.path_join("Embedded Bits.vpx")
	_expect(_write_bytes_file(fx_bits, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("Playfield", 1024, 768, PackedByteArray(), false, true)},
		{"name": "Image1", "data": _biff_texture_bytes("glass lamps", 800, 600, PackedByteArray(), false, true)},
	])), "embedded fixture: BITS table written", failures)
	var fx_none: String = art_dir.path_join("Embedded Empty.vpx")
	_expect(_write_bytes_file(fx_none, _cfb_file_bytes([
		{"name": "GameData", "data": chaff},
		{"name": "Sound0", "data": _zero_bytes(6000)},
	])), "embedded fixture: imageless table written", failures)
	var fx_cold: String = art_dir.path_join("Embedded Cold.vpx")
	_expect(_write_bytes_file(fx_cold, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("Playfield", 300, 300, (mk_img.call(300, 300) as Image).save_png_to_buffer())},
	])), "embedded fixture: cold table written (never extracted in this section)", failures)
	var fx_bmp: String = art_dir.path_join("Embedded Bmp.vpx")
	_expect(_write_bytes_file(fx_bmp, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("Backdrop", 640, 480, _bmp_bytes(640, 480))},
	])), "embedded fixture: BMP table written", failures)
	var fx_biffbad: String = art_dir.path_join("Embedded BadBiff.vpx")
	var bad_biff: PackedByteArray = PackedByteArray()
	bad_biff.append_array(_biff_string_record("NAME", "Playfield"))
	var bad_rec: PackedByteArray = PackedByteArray()
	bad_rec.resize(4)
	bad_rec.encode_s32(0, 999999)
	bad_biff.append_array(bad_rec)
	bad_biff.append_array("WDTH".to_ascii_buffer())
	bad_biff.append_array(_zero_bytes(64))
	_expect(_write_bytes_file(fx_biffbad, _cfb_file_bytes([
		{"name": "Image0", "data": bad_biff},
	])), "embedded fixture: corrupt-BIFF table written", failures)
	var fx_corrupt: String = art_dir.path_join("Embedded Corrupt.vpx")
	_expect(_write_bytes_file(fx_corrupt, _zero_bytes(2048)), "embedded fixture: corrupt file written", failures)
	var glass_bytes: PackedByteArray = FileAccess.get_file_as_bytes(fx_glass)
	glass_bytes.resize(300)
	var fx_trunc: String = art_dir.path_join("Embedded Truncated.vpx")
	_expect(_write_bytes_file(fx_trunc, glass_bytes), "embedded fixture: truncated file written", failures)
	# The census surface first: the walker reports the records
	# it found - the textures' names and dimensions from inside
	# the streams (the stream names Image0/Image1/Image2 say
	# nothing at all).
	var glass_walk: Array = ArtProvider.inspect_vpx_images(fx_glass)
	_expect(glass_walk.size() == 3
		and str((glass_walk[0] as Dictionary)["name"]) == "Playfield" and str((glass_walk[0] as Dictionary)["kind"]) == "data"
		and str((glass_walk[1] as Dictionary)["name"]) == "Backglass" and int((glass_walk[1] as Dictionary)["width"]) == 400
		and int((glass_walk[1] as Dictionary)["height"]) == 500,
		"embedded: inspect reports the walked records (NAME and dims from inside the streams)", failures)
	# (a) A texture named for the backglass wins - over a LARGER
	# playfield texture that precedes it in the directory. The
	# glass texture also carries a legacy INME record ahead of
	# its payload object: unknown records are size-skipped.
	var emb_t0: int = Time.get_ticks_msec()
	var glass_cache: String = ArtProvider.extract_art_image(fx_glass)
	var emb_ms: int = Time.get_ticks_msec() - emb_t0
	print("  embedded extraction: glass fixture in ", emb_ms, " ms")
	var glass_img: Image = Image.new()
	_expect(glass_cache == ArtProvider.cache_path_for(fx_glass) and glass_img.load(glass_cache) == OK
		and glass_img.get_width() == 400 and glass_img.get_height() == 500,
		"embedded: the backglass-named DATA wins over the larger playfield (400x500, unscaled)", failures)
	_expect(ArtProvider.outcome_for_embedded(fx_glass) == ArtProvider.STATUS_OK,
		"embedded: a successful extraction records ok", failures)
	# (b) With no backglass name in the file, the playfield wins -
	# over a larger unnamed image.
	var field_cache: String = ArtProvider.extract_art_image(fx_field)
	var field_img: Image = Image.new()
	_expect(field_cache != "" and field_img.load(field_cache) == OK
		and field_img.get_width() == 500 and field_img.get_height() == 400,
		"embedded: the playfield wins over a larger unnamed image (500x400)", failures)
	# (c) No telling names at all: the largest image over the
	# sprite floor wins (the 120x120 decal is under it).
	var big_cache: String = ArtProvider.extract_art_image(fx_big)
	var big_img: Image = Image.new()
	_expect(big_cache != "" and big_img.load(big_cache) == OK
		and big_img.get_width() == 512 and big_img.get_height() == 398,
		"embedded: the largest-image fallback wins (900x700 -> 512x398)", failures)
	# A small texture's whole stream rides the mini-stream chain;
	# its DATA span is range-read out of the mini sectors.
	var mini_cache: String = ArtProvider.extract_art_image(fx_mini)
	var mini_img: Image = Image.new()
	_expect(mini_cache != "" and mini_img.load(mini_cache) == OK
		and mini_img.get_width() == 320 and mini_img.get_height() == 240,
		"embedded: a mini-stream texture's DATA extracts (320x240)", failures)
	# BMP bytes (an older import's original file) inside a
	# backdrop-named texture's DATA decode like any payload.
	var bmpv_cache: String = ArtProvider.extract_art_image(fx_bmp)
	var bmpv_img: Image = Image.new()
	_expect(bmpv_cache != "" and bmpv_img.load(bmpv_cache) == OK
		and bmpv_img.get_width() == 512 and bmpv_img.get_height() == 384,
		"embedded: BMP bytes in a backdrop texture's DATA extract (640x480 -> 512x384)", failures)
	# A LINK texture holds no payload in its own stream: its art
	# is the Screenshot stream's raw bytes. The larger unnamed
	# DATA texture beside it is the trap: only the LINK
	# candidate's playfield class outranks it - a reader that
	# ignored LINK and fell back to the bare Screenshot stream
	# (class 2, ranked by area) would serve the cab art instead.
	var link_cache: String = ArtProvider.extract_art_image(fx_link)
	var link_img: Image = Image.new()
	_expect(link_cache != "" and link_img.load(link_cache) == OK
		and link_img.get_width() == 512 and link_img.get_height() == 384
		and ArtProvider.outcome_for_embedded(fx_link) == ArtProvider.STATUS_OK,
		"embedded: a LINK texture resolves through the Screenshot stream (800x600 -> 512x384)", failures)
	# The Screenshot stream is a candidate in its own right: a
	# file with no image streams at all still serves from it.
	var shot_cache: String = ArtProvider.extract_art_image(fx_shot)
	var shot_img: Image = Image.new()
	_expect(shot_cache != "" and shot_img.load(shot_cache) == OK
		and shot_img.get_width() == 500 and shot_img.get_height() == 375,
		"embedded: a Screenshot stream alone still serves (500x375, unscaled)", failures)
	# BITS-only art (pre-10.8.1 BMP imports): the legacy stamp -
	# a census answer, not no_image and not failed.
	_expect(ArtProvider.extract_art_image(fx_bits) == "" and ArtProvider.outcome_for_embedded(fx_bits) == ArtProvider.STATUS_LEGACY,
		"embedded: a BITS-only table records legacy_format, not no_image", failures)
	var bits_walk: Array = ArtProvider.inspect_vpx_images(fx_bits)
	_expect(bits_walk.size() == 2 and str((bits_walk[0] as Dictionary)["kind"]) == "bits",
		"embedded: inspect reports BITS payloads as their own kind", failures)
	# No images inside: parsed, stamped no_image, title card.
	_expect(ArtProvider.extract_art_image(fx_none) == "" and ArtProvider.outcome_for_embedded(fx_none) == ArtProvider.STATUS_NO_IMAGE,
		"embedded: a table file with no image streams records no_image", failures)
	# Corrupt files: failed, remembered, and no crash (this test
	# reaching its next line is the proof) - a non-compound file,
	# a truncated compound file, and a compound file whose image
	# stream's BIFF records run off the stream's end.
	_expect(ArtProvider.extract_art_image(fx_corrupt) == "" and ArtProvider.outcome_for_embedded(fx_corrupt) == ArtProvider.STATUS_FAILED,
		"embedded: a non-compound file records failed", failures)
	_expect(ArtProvider.extract_art_image(fx_trunc) == "" and ArtProvider.outcome_for_embedded(fx_trunc) == ArtProvider.STATUS_FAILED,
		"embedded: a truncated compound file records failed, no crash", failures)
	_expect(ArtProvider.extract_art_image(fx_biffbad) == "" and ArtProvider.outcome_for_embedded(fx_biffbad) == ArtProvider.STATUS_FAILED,
		"embedded: a corrupt BIFF image stream records failed, no crash", failures)
	var dead_entry: GameEntry = GameEntry.new()
	dead_entry.art_source_path = fx_corrupt
	dead_entry.art_vpx_path = fx_corrupt
	_expect(dead_entry.ensure_art() == "", "embedded: a stamped-failed table gets the title card, no work", failures)
	# Extraction happens once: a second call a full second later is
	# a pure cache hit - the cache file's mtime cannot move.
	var big_mtime: int = int(FileAccess.get_modified_time(ArtProvider.cache_path_for(fx_big)))
	OS.delay_msec(1100)
	_expect(ArtProvider.extract_vpx_image(fx_big) == big_cache
		and int(FileAccess.get_modified_time(ArtProvider.cache_path_for(fx_big))) == big_mtime,
		"embedded: extraction happens once - the second call is a cache hit", failures)
	# The source order at panel level: a healthy backglass beats
	# the image inside the .vpx...
	var prio_entry: GameEntry = GameEntry.new()
	prio_entry.art_source_path = b2s_ok
	prio_entry.art_vpx_path = fx_glass
	_expect(prio_entry.ensure_art() == ArtProvider.cache_path_for(b2s_ok),
		"embedded: a healthy backglass still outranks the image inside the .vpx", failures)
	# ...and a backglass with no usable image falls THROUGH to it.
	var b2s_fall: String = art_dir.path_join("Fallthrough Table.directb2s")
	_expect(_write_text_file(b2s_fall, "<DirectB2SData><Images></Images></DirectB2SData>"),
		"embedded fixture: fallthrough backglass written", failures)
	var fall_entry: GameEntry = GameEntry.new()
	fall_entry.art_source_path = b2s_fall
	fall_entry.art_vpx_path = fx_glass
	_expect(fall_entry.ensure_art() == ArtProvider.cache_path_for(fx_glass),
		"embedded: a no-image backglass falls through to the image inside the .vpx", failures)
	# Cache coverage counts an embedded hit like any other source.
	var cov_side: GameEntry = GameEntry.new()
	cov_side.art_path = p1
	var cov_vpx_ok: GameEntry = GameEntry.new()
	cov_vpx_ok.art_source_path = fx_mini
	cov_vpx_ok.art_vpx_path = fx_mini
	var cov_vpx_cold: GameEntry = GameEntry.new()
	cov_vpx_cold.art_source_path = fx_cold
	cov_vpx_cold.art_vpx_path = fx_cold
	_expect(ArtWarmer.cache_coverage([cov_side, cov_vpx_ok, cov_vpx_cold]) == Vector2i(2, 3),
		"embedded: cache coverage counts side art and cached embedded art as ready", failures)
	# Embedded health: only games where the embedded source is in
	# play are counted (the priority entry's backglass serves, so
	# it is out; the fallthrough entry's backglass is stamped
	# negative, so it is in, untried).
	var eh_ok: GameEntry = GameEntry.new()
	eh_ok.art_source_path = fx_mini
	eh_ok.art_vpx_path = fx_mini
	var eh_none: GameEntry = GameEntry.new()
	eh_none.art_source_path = fx_none
	eh_none.art_vpx_path = fx_none
	var eh_legacy: GameEntry = GameEntry.new()
	eh_legacy.art_source_path = fx_bits
	eh_legacy.art_vpx_path = fx_bits
	var eh_fall: GameEntry = GameEntry.new()
	eh_fall.art_source_path = b2s_fall
	eh_fall.art_vpx_path = fx_cold
	var ehealth: Dictionary = ArtWarmer.embedded_health([eh_ok, eh_none, eh_legacy, eh_fall, prio_entry])
	_expect(int(ehealth["total"]) == 4 and int(ehealth["ok"]) == 1 and int(ehealth["no_image"]) == 1
		and int(ehealth["legacy"]) == 1 and int(ehealth["untried"]) == 1 and int(ehealth["failed"]) == 0,
		"embedded: health counts only games where the embedded source is in play (legacy bucket included)", failures)
	# Backglass health stays backglass-only: the .vpx-primary
	# entries above are not its subject.
	var bh_fall: GameEntry = GameEntry.new()
	bh_fall.art_source_path = b2s_fall
	var bhealth: Dictionary = ArtWarmer.art_health([ok_entry, bh_fall, eh_ok])
	_expect(int(bhealth["total"]) == 2 and int(bhealth["ok"]) == 1 and int(bhealth["no_image"]) == 1,
		"embedded: backglass health ignores .vpx-primary games", failures)
	# The warmer pre-extracts an embedded source in the background,
	# like any other - and a game's fallback joins the queue when
	# its backglass is already known-negative.
	var fx_warm: String = art_dir.path_join("Embedded Warm.vpx")
	_expect(_write_bytes_file(fx_warm, _cfb_file_bytes([
		{"name": "Image0", "data": _biff_texture_bytes("Playfield", 500, 400, (mk_img.call(500, 400) as Image).save_png_to_buffer())},
	])), "embedded fixture: warm table written", failures)
	var warm_vpx_entry: GameEntry = GameEntry.new()
	warm_vpx_entry.art_source_path = fx_warm
	warm_vpx_entry.art_vpx_path = fx_warm
	var warm4: ArtWarmer = ArtWarmer.new()
	warm4.warm_library([warm_vpx_entry])
	waited = 0
	while not warm4.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warm4.is_idle() and ArtProvider.is_cached(fx_warm),
		"embedded: the warmer pre-extracts a .vpx-primary game in the background", failures)
	# A fresh known-negative backglass for the nothing-twice pass:
	# its stamp must postdate warm4's pass, whose prune (a library
	# of one) correctly retired every other stamp.
	var b2s_fall2: String = art_dir.path_join("Fallthrough Warm Table.directb2s")
	_expect(_write_text_file(b2s_fall2, "<DirectB2SData><Images></Images></DirectB2SData>"),
		"embedded fixture: warm fallthrough backglass written", failures)
	_expect(ArtProvider.extract_directb2s_image(b2s_fall2) == "" and ArtProvider.outcome_for(b2s_fall2) == ArtProvider.STATUS_NO_IMAGE,
		"embedded fixture: warm fallthrough backglass stamps no_image", failures)
	var fall_warm_entry: GameEntry = GameEntry.new()
	fall_warm_entry.art_source_path = b2s_fall2
	fall_warm_entry.art_vpx_path = fx_warm
	var warm5: ArtWarmer = ArtWarmer.new()
	warm5.warm_library([fall_warm_entry])
	waited = 0
	while not warm5.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warm5.is_idle() and warm5.last_pass_items == 0,
		"embedded: a warm pass over stamped-known art extracts nothing twice", failures)
	# Scanner level: listing facts only. A side image wins the
	# face; a .vpx with nothing beside it becomes its own primary
	# source and is NOT counted as scan-covered (its art is
	# unproven until extraction), though the fallback path is
	# recorded on every game.
	var vpx_root_user: String = "user://core_test_vpxart"
	var vpx_root: String = ProjectSettings.globalize_path(vpx_root_user)
	_wipe_tree(vpx_root)
	var vpx_user_dir: DirAccess = DirAccess.open("user://")
	if vpx_user_dir != null and not vpx_user_dir.dir_exists("core_test_vpxart"):
		vpx_user_dir.make_dir("core_test_vpxart")
	var emb_path: String = vpx_root_user.path_join("Embedded Only (Testworks 2001).vpx")
	var side_vpx_path: String = vpx_root_user.path_join("Side Wins (Testworks 2002).vpx")
	var side_png_path: String = vpx_root_user.path_join("Side Wins (Testworks 2002).png")
	_expect(_write_bytes_file(emb_path, FileAccess.get_file_as_bytes(fx_glass)), "embedded fixture: scanner table written", failures)
	_expect(_write_bytes_file(side_vpx_path, FileAccess.get_file_as_bytes(fx_field)), "embedded fixture: sidecar table written", failures)
	_expect(_write_bytes_file(side_png_path, (mk_img.call(64, 64) as Image).save_png_to_buffer()), "embedded fixture: sidecar image written", failures)
	var vpx_scan: LibraryScanner = LibraryScanner.new()
	vpx_scan.scan([vpx_root_user], db)
	var emb_entry: GameEntry = null
	var side_entry: GameEntry = null
	for g2: GameEntry in vpx_scan.games:
		for b: TableBuild in g2.builds:
			if b.file_path == emb_path:
				emb_entry = g2
			if b.file_path == side_vpx_path:
				side_entry = g2
	_expect(emb_entry != null and emb_entry.art_source_path == emb_path and emb_entry.art_vpx_path == emb_path,
		"embedded: a backglass-less game takes its own .vpx as primary source", failures)
	_expect(side_entry != null and side_entry.art_path == side_png_path and side_entry.art_vpx_path == side_vpx_path,
		"embedded: a side image still outranks the embedded image (and the fallback is recorded)", failures)
	_expect(vpx_scan.art_covered_games == 1,
		"embedded: scan coverage counts only listing-proven art (the side image), not the unopened .vpx", failures)
	_expect(emb_entry != null and emb_entry.ensure_art() == ArtProvider.cache_path_for(emb_path),
		"embedded: a scanned game's panel extracts the image inside its .vpx", failures)
	_wipe_tree(vpx_root)
	# Pre-fix stamp migration: an embedded outcome stamped by
	# the offset-0 reader (a shared-"v" entry with no "ev")
	# still reads under the backglass gate, but counts as
	# untried under the BIFF gate - so the file is retried
	# exactly once under the new reader, and the retry's record
	# carries the embedded generation. (Placed last in this
	# section: the warm passes above prune the index down to
	# their own libraries, and this plant must postdate them.)
	var fx_retry: String = art_dir.path_join("Embedded Retried.vpx")
	_expect(_write_bytes_file(fx_retry, FileAccess.get_file_as_bytes(fx_glass)), "embedded fixture: retried table written", failures)
	var retry_key: String = ArtProvider.stamp_key_for(fx_retry)
	var idx_path2: String = "user://art_cache/art_index.json"
	var planted2: Dictionary = {}
	var idx_text2: String = FileAccess.get_file_as_string(idx_path2)
	if idx_text2 != "":
		var parsed_idx2: Variant = JSON.parse_string(idx_text2)
		if parsed_idx2 is Dictionary:
			planted2 = parsed_idx2 as Dictionary
	planted2[retry_key] = {"status": "no_image", "src": fx_retry, "v": ArtProvider.EXTRACTOR_VERSION}
	_expect(_write_text_file(idx_path2, JSON.stringify(planted2)), "embedded fixture: pre-fix no_image entry planted", failures)
	ArtProvider.reload_index()
	_expect(ArtProvider.outcome_for(fx_retry) == ArtProvider.STATUS_NO_IMAGE
		and ArtProvider.outcome_for_embedded(fx_retry) == "",
		"embedded: a pre-fix stamp still reads under the backglass gate but is untried under the BIFF gate", failures)
	_expect(ArtProvider.extract_art_image(fx_retry) != "" and ArtProvider.outcome_for_embedded(fx_retry) == ArtProvider.STATUS_OK,
		"embedded: the pre-fix file is retried once under the BIFF walker and extracts", failures)
	var after_idx2: Dictionary = {}
	var parsed_after2: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx_path2))
	if parsed_after2 is Dictionary:
		after_idx2 = parsed_after2 as Dictionary
	var after_entry2: Variant = after_idx2.get(retry_key, null)
	_expect(after_entry2 is Dictionary and int((after_entry2 as Dictionary).get("ev", 0)) == ArtProvider.VPX_READER_VERSION,
		"embedded: the retried entry is stamped with the embedded reader generation", failures)

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

	# --- Matcher: decorated file names. Its own fixture db in the
	# REAL database's shape - VPX table files carry download URLs,
	# never a fileName (the live VPS db names no table files; the
	# old fixture invented fileNames and two roads indexed a field
	# that does not exist, so they fired in tests and never in the
	# field). Six games: one whose VR build carries a vpuniverse
	# slug URL (its second build only a slugless vpforums link),
	# one with no slug at all, same-name twins whose slugs collide
	# on one key, a title legitimately ending in "Room", and an
	# edition-named game ("Bolt/DC") whose LUCI Premium file must
	# stay honestly unmatched. Fifteen files: the regression
	# identities, decorated shapes, Chris's real unmatched shapes
	# (PINEMHI tag, "w Room" suffix), an ambiguity that must stay
	# unmatched, and a plain unknown. The pre-slug ladder on this
	# fixture's shapes: 3 builds matched, 1 by game only, the rest
	# filename-only.
	var mt_root_user: String = "user://core_test_matcher"
	var mt_root: String = ProjectSettings.globalize_path(mt_root_user)
	_wipe_tree(mt_root)
	var mt_user_dir: DirAccess = DirAccess.open("user://")
	if mt_user_dir != null and not mt_user_dir.dir_exists("core_test_matcher"):
		mt_user_dir.make_dir("core_test_matcher")
	var mt_root_dir: DirAccess = DirAccess.open(mt_root_user)
	if mt_root_dir != null and not mt_root_dir.dir_exists("tables"):
		mt_root_dir.make_dir("tables")
	var mt_tables: String = mt_root_user.path_join("tables")
	var mt_db_data: Array = [
		{
			"id": "fx-quasar-queen", "name": "Quasar Queen", "manufacturer": "Starlite",
			"year": 1982, "designers": ["D. Zed"],
			"tableFiles": [
				{"id": "fx-qq-1", "version": "1.0", "tableFormat": "VPX", "authors": ["Zippy"], "createdAt": 1700000000, "features": ["VR"], "urls": [{"url": "https://vpuniverse.com/files/file/24896-quasar-queen-starlite-1982-zippy/"}]},
				{"id": "fx-qq-2", "version": "2.0", "tableFormat": "VPX", "authors": ["Zippy"], "createdAt": 1710000000, "features": [], "urls": [{"url": "https://www.vpforums.org/index.php?app=downloads&showfile=19031"}]},
			],
		},
		{
			"id": "fx-lunar-tide", "name": "Lunar Tide", "manufacturer": "Marlin",
			"year": 1975, "designers": ["K. Ito"],
			"tableFiles": [
				{"id": "fx-lt-1", "version": "1.0", "tableFormat": "VPX", "authors": ["Marlin Works"], "createdAt": 1700000000, "features": ["VR"], "urls": [{"url": "https://www.vpforums.org/index.php?app=downloads&showfile=18675"}]},
			],
		},
		{
			"id": "fx-star-voyage-a", "name": "Star Voyage", "manufacturer": "Marlin",
			"year": 1977, "designers": ["A. One"],
			"tableFiles": [
				{"id": "fx-sva-1", "version": "1.0", "tableFormat": "VPX", "authors": ["A. One"], "createdAt": 1700000000, "features": [], "urls": [{"url": "https://vpuniverse.com/files/file/11111-star-voyage-marlin-1977/"}]},
			],
		},
		{
			"id": "fx-star-voyage-b", "name": "Star Voyage", "manufacturer": "Orbital Works",
			"year": 1991, "designers": ["B. Two"],
			"tableFiles": [
				{"id": "fx-svb-1", "version": "1.0", "tableFormat": "VPX", "authors": ["B. Two"], "createdAt": 1700000000, "features": ["VR"], "urls": [{"url": "https://vpuniverse.com/files/file/22222-star-voyage-orbital-works-1991/"}]},
			],
		},
		{
			"id": "fx-panic-room", "name": "Panic Room", "manufacturer": "Marlin",
			"year": 1999, "designers": ["K. Ito"],
			"tableFiles": [
				{"id": "fx-pr-1", "version": "1.0", "tableFormat": "VPX", "authors": ["Marlin Works"], "createdAt": 1700000000, "features": ["VR"], "urls": [{"url": "https://vpuniverse.com/files/file/33333-panic-room-marlin-1999/"}]},
			],
		},
		{
			"id": "fx-bolt-dc", "name": "Bolt/DC", "manufacturer": "Volt",
			"year": 2012, "designers": [],
			"tableFiles": [
				{"id": "fx-bdc-1", "version": "1.0", "tableFormat": "VPX", "authors": ["Volt Team"], "createdAt": 1700000000, "features": [], "urls": [{"url": "https://vpuniverse.com/files/file/44444-bolt-dc-volt-2012/"}]},
			],
		},
	]
	_expect(_write_text_file(mt_root_user.path_join("vpsdb.json"), JSON.stringify(mt_db_data)), "matcher fixture: db written", failures)
	var mt_db: VpsDatabase = VpsDatabase.new()
	_expect(mt_db.load_db(mt_root_user.path_join("vpsdb.json")), "matcher fixture: db loads", failures)
	var mt_names: Array[String] = [
		"Quasar Queen (Starlite 1982).vpx",
		"Quasar Queen (Starlite 1982) v2.0.vpx",
		"Lunar Tide (Marlin 1975).vpx",
		"[VPW] Quasar Queen (Starlite 1982) v1.0 [Zippy].vpx",
		"Quasar Queen - Zippy (Starlite 1982) v2.0.vpx",
		"Lunar Tide FSS (Marlin 1975).vpx",
		"Lunar Tide (Marlin 1975) Zippy.vpx",
		"Star Voyage (Orbital 1991) FSS.vpx",
		"Star Voyage (Unknown 1980) FSS.vpx",
		"Nonexistent Table (Nobody 2001) v1.0.vpx",
		"Quasar Queen (Starlite 1982) v9.9.vpx",
		"Quasar Queen Mod PINEMHI.vpx",
		"Lunar Tide w Room.vpx",
		"Panic Room (Marlin 1999).vpx",
		"Bolt-DC LUCI Premium.vpx",
	]
	for mt_name: String in mt_names:
		_expect(_write_text_file(mt_tables.path_join(mt_name), "fixture"), "matcher fixture: file written (%s)" % mt_name, failures)
	var mt_folders: Array[String] = [mt_tables]
	var mt_scan: LibraryScanner = LibraryScanner.new()
	mt_scan.scan(mt_folders, mt_db)
	print("  matcher fixture distribution: ", mt_scan.match_tier_counts,
		" (builds ", mt_scan.matched_files, ", game-only ", mt_scan.game_matched_files, ")")
	_expect(mt_scan.total_files == 15, "matcher fixture: 15 files scanned", failures)
	_expect(mt_scan.matched_files == 11, "matcher fixture: 11 builds matched (pre-slug ladder on these shapes: 3)", failures)
	_expect(mt_scan.game_matched_files == 1, "matcher fixture: 1 by game only", failures)
	_expect(mt_scan.games.size() == 7, "matcher fixture: grouped into 7 games", failures)
	_expect(int(mt_scan.match_tier_counts.get("slug", 0)) == 7
		and int(mt_scan.match_tier_counts.get("name", 0)) == 1
		and int(mt_scan.match_tier_counts.get("scrubbed", 0)) == 4
		and int(mt_scan.match_tier_counts.get("local", 0)) == 3,
		"matcher fixture: tiers resolve slug 7 / name 1 / scrubbed 4 / local 3", failures)
	var mt_qq: GameEntry = mt_scan.game_by_id("fx-quasar-queen")
	_expect(mt_qq != null and mt_qq.builds.size() == 6, "matcher fixture: Quasar Queen groups its 6 files", failures)
	if mt_qq != null:
		# Regression identities: these resolved to these very builds
		# under the old ladder too - the road changed (the db's
		# download slug, not an invented fileName), the builds didn't.
		var reg1: TableBuild = mt_qq.build_by_path(mt_tables.path_join("Quasar Queen (Starlite 1982).vpx"))
		_expect(reg1 != null and reg1.table_file_id == "fx-qq-1" and reg1.match_tier == "slug",
			"regression: the plain file is still build fx-qq-1, now via its download slug", failures)
		var reg2: TableBuild = mt_qq.build_by_path(mt_tables.path_join("Quasar Queen (Starlite 1982) v2.0.vpx"))
		_expect(reg2 != null and reg2.table_file_id == "fx-qq-2" and reg2.match_tier == "slug",
			"regression: the v2.0 file still resolves to build fx-qq-2 (slug names the game, the ladder the build)", failures)
		var reg3: TableBuild = mt_qq.build_by_path(mt_tables.path_join("Quasar Queen (Starlite 1982) v9.9.vpx"))
		_expect(reg3 != null and not reg3.matched_db and reg3.version == "9.9" and reg3.match_tier == "slug",
			"regression: the unstated-in-db v9.9 is still game-only, never relabeled", failures)
		# New reach: decorations the old ladder filed as local.
		var dec1: TableBuild = mt_qq.build_by_path(mt_tables.path_join("[VPW] Quasar Queen (Starlite 1982) v1.0 [Zippy].vpx"))
		_expect(dec1 != null and dec1.table_file_id == "fx-qq-1" and dec1.match_tier == "slug" and dec1.has_vr_tag(),
			"bracketed decorations meet the download slug at the VR build fx-qq-1 (it can now appear in the VR view)", failures)
		var dec2: TableBuild = mt_qq.build_by_path(mt_tables.path_join("Quasar Queen - Zippy (Starlite 1982) v2.0.vpx"))
		_expect(dec2 != null and dec2.table_file_id == "fx-qq-2" and dec2.match_tier == "slug",
			"the ' - Author' tail scrubs off; the stated version picks build fx-qq-2", failures)
		# Chris's field shape: the PINEMHI tag is decoration now.
		var pin: TableBuild = mt_qq.build_by_path(mt_tables.path_join("Quasar Queen Mod PINEMHI.vpx"))
		_expect(pin != null and pin.table_file_id == "fx-qq-1" and pin.match_tier == "slug",
			"the PINEMHI tag scrubs away and the file meets the slug build fx-qq-1 (his 'Aerosmith Mod PINEMHI' shape)", failures)
	var mt_lt: GameEntry = mt_scan.game_by_id("fx-lunar-tide")
	_expect(mt_lt != null and mt_lt.builds.size() == 4, "matcher fixture: Lunar Tide groups its 4 files", failures)
	if mt_lt != null:
		var reg4: TableBuild = mt_lt.build_by_path(mt_tables.path_join("Lunar Tide (Marlin 1975).vpx"))
		_expect(reg4 != null and reg4.table_file_id == "fx-lt-1" and reg4.match_tier == "name",
			"regression: the plain Lunar Tide file still resolves by title to fx-lt-1 (its db entry has no slug)", failures)
		var dec3: TableBuild = mt_lt.build_by_path(mt_tables.path_join("Lunar Tide FSS (Marlin 1975).vpx"))
		_expect(dec3 != null and dec3.table_file_id == "fx-lt-1" and dec3.match_tier == "scrubbed",
			"a shouted feature tag mid-name scrubs to the game (no slug exists to claim it)", failures)
		var dec4: TableBuild = mt_lt.build_by_path(mt_tables.path_join("Lunar Tide (Marlin 1975) Zippy.vpx"))
		_expect(dec4 != null and dec4.table_file_id == "fx-lt-1" and dec4.match_tier == "scrubbed",
			"a trailing author name scrubs off the cleaned-title match", failures)
		var dec5: TableBuild = mt_lt.build_by_path(mt_tables.path_join("Lunar Tide w Room.vpx"))
		_expect(dec5 != null and dec5.table_file_id == "fx-lt-1" and dec5.match_tier == "scrubbed",
			"the trailing 'w Room' suffix drops and the file meets its game (his 'Apollo 13 w Room' shape)", failures)
	var mt_pr: GameEntry = mt_scan.game_by_id("fx-panic-room")
	_expect(mt_pr != null and mt_pr.builds.size() == 1, "matcher fixture: Panic Room holds its file", failures)
	if mt_pr != null:
		var roomy: TableBuild = mt_pr.builds[0]
		_expect(roomy.table_file_id == "fx-pr-1" and roomy.match_tier == "slug",
			"a title legitimately ending in 'Room' still matches - both sides shed the suffix identically", failures)
	var mt_svb: GameEntry = mt_scan.game_by_id("fx-star-voyage-b")
	_expect(mt_svb != null and mt_svb.builds.size() == 1, "matcher fixture: the Orbital Star Voyage holds the disambiguated file", failures)
	if mt_svb != null:
		var twin: TableBuild = mt_svb.builds[0]
		_expect(twin.table_file_id == "fx-svb-1" and twin.match_tier == "scrubbed",
			"same-name twins: their slugs collide on one key (ambiguous, falls through), so the (Orbital 1991) parens referee the cleaned-title match instead", failures)
	_expect(mt_scan.game_by_id("fx-star-voyage-a") == null,
		"same-name twins: nothing lands on the Marlin Star Voyage by accident", failures)
	_expect(mt_scan.game_by_id("fx-bolt-dc") == null,
		"the LUCI Premium edition file is NOT coin-flipped onto the base game - editions are not scrubbed away", failures)
	var mt_bolt: GameEntry = mt_scan.game_by_id("local:boltdclucipremium")
	_expect(mt_bolt != null and mt_bolt.title == "Bolt-DC LUCI Premium",
		"the edition file stays filename-only under its own name (his 'AC-DC LUCI Premium' shape)", failures)
	var mt_amb: GameEntry = mt_scan.game_by_id("local:starvoyageunknown1980fss")
	_expect(mt_amb != null and mt_amb.title == "Star Voyage",
		"the unrefereeable twin file stays filename-only - and shows a cleaned title", failures)
	# The seeded dummy library's own distribution, for the record:
	# the slug tier re-routes six files (three of them previously
	# exact/file by invented fileNames) to the same builds the
	# core assertions above already pinned as unchanged.
	_expect(int(scanner.match_tier_counts.get("slug", 0)) == 6
		and int(scanner.match_tier_counts.get("name", 0)) == 7,
		"dummy library tier distribution: slug 6 / name 7", failures)
	# Clean display titles (Part 2): the scrubber's display face.
	_expect(VpsDatabase.clean_display_title("Quasar Queen - Zippy (Starlite 1982) [VR Room] v1.0.4.vpx") == "Quasar Queen",
		"display title: author tail, tag block and version all scrub away", failures)
	_expect(VpsDatabase.clean_display_title("Mr. Do! (Pinnacle 1983).vpx") == "Mr. Do!",
		"display title: 'Mr.' is a title word, not the MR feature tag", failures)
	_expect(VpsDatabase.clean_display_title("Pharaoh's Ledger (Vantage 1979) JP v55 DT-FS-VR-MR Ext2k Conversion.vpx") == "Pharaoh's Ledger JP Ext2k Conversion",
		"display title: the shouted DT-FS-VR-MR chain scrubs; unknowable words stay", failures)
	_wipe_tree(mt_root)

	if failures.is_empty():
		print("CORE TEST: PASS")
		get_tree().quit(0)
	else:
		printerr("CORE TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)
