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
##   --pvlds-smoke-letters
##                       room boot on the harness's letter
##                       fixtures (real VPS db records + real
##                       title shapes); assert the alphabet
##                       strip contract: presence/greying, the
##                       strip as its own focus country, letter
##                       jumps (page + focus landing, the quiet
##                       title-sort switch), the THE net (a file
##                       whose own title has "The", a file
##                       missing it whose canonical db title
##                       has it, an unmatched "The ..." file -
##                       "Theatre" is not a member), the "#"
##                       net, and exiting a net by letter.
##                       Env PVLDS_LJ_NC=nostrip disables the
##                       index's leading-The strip: the
##                       canonical-The legs must fail by name.
##   --pvlds-seated-cam  with --pvlds-shot: take the shot from a
##                       seated eye height (RoomView.SEATED_EYE_Y)
##                       instead of the standing desk eye

var _config: PvldsConfig
var _state: StateStore
var _db: VpsDatabase
var _scanner: LibraryScanner
var _art_warmer: ArtWarmer
var _shot_fetcher: ShotFetcher ## the author-shot fetcher (graduation): one pass per scan landing, cached or recorded for good
var _factory: TextureFactory
var _room: RoomView = null
var _desk: SetupDesk = null
var _xr_interface: XRInterface
var _xr_enabled: bool = false
var _xr_tried: bool = false
var _launch_service: LaunchService = null
var _intentional_launch_exit: bool = false ## quitting FOR a launch must not disarm the watchdog
# WoVP read side (the Tournament Room round): Main owns the
# client, the identity the key resolves to, and the standing
# boards the room renders. The key itself lives only in the
# config - never in these vars, never in a print.
var _wovp_client: WovpClient = null
var _wovp_user_id: String = "" ## whose key is saved (validate's answer, or the cache's when its key hash matches)
var _wovp_user_name: String = ""
var _wovp_identity_key_hash: int = 0 ## the hash of the key _wovp_user_id was resolved for
var _wovp_identity_state: String = "untested" ## "untested" | "ok" | "failed" - this session's last validation outcome
var _wovp_identity_note: String = "" ## the last validation failure's words
var _wovp_challenges: Array = [] ## the standing boards (Array of WovpChallenge): live, or the disk cache's at boot
var _wovp_fetched_at: int = 0 ## when the standing boards landed (0 = never this device)
var _wovp_boards_live: bool = false ## the standing boards came from a fetch this session
var _wovp_fetch_error: String = "" ## the last fetch's failure in words, while it stands
var _wovp_validating_for: String = "" ## who a running validation answers to: "fetch" | "room" | "desk"
var _wovp_validating_key_hash: int = 0 ## the hash of the key a running validation is about (a desk test may name a key that is not the saved one)
var _smoke_tournament: bool = false ## --pvlds-smoke-tournament: drive the Tournament Room contract once the room is up
var _tournament_smoke_phase: int = 0
var _tournament_smoke_wait: int = 0
var _tournament_smoke_failures: int = 0
var _tournament_smoke_deadline_msec: int = 0
var _tournament_validate_count_seen: int = 0 ## the stub's validate count when the panel length legs begin (their no-send witness)
var _tournament_smoke_mode: String = "full" ## PVLDS_WOVP_SMOKE_MODE: full | nokey | failfetch | errbody | errempty | cache | layout - which harness boot this is
var _layout_probe_results: Dictionary = {} ## layout mode: panel index -> RoomView.board_layout_probe result, filled async
var _layout_probes_in_flight: bool = false
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
var _shot_slide_path: String = "" ## --pvlds-shot-slide P: capture the drum mid-swing
var _shot_slide_phase: int = -1
var _shot_slide_frames: int = 0
var _shot_slide_yaw0: float = -1.0 ## the swing's full travel (deviation at the flip's first frame); the capture fires at 60% travelled
var _nav_pop_panel: ClickableQuad = null ## bottom-row panel the nav smoke pops for the clearance re-check
var _smoke_letters: bool = false ## --pvlds-smoke-letters: the alphabet strip + letter-jump contract
var _letters_smoke_phase: int = 0
var _letters_smoke_wait: int = 0
var _letters_smoke_failures: int = 0
var _letters_step: int = 0 ## the focus-fix legs' sub-state (strip visual grab, pager turns)
var _letters_focus_key: String = "" ## the strip slot the entry walk landed on
var _smoke_bootfocus: bool = false ## --pvlds-smoke-bootfocus: the boot-focused (last-played) card renders fully with NO input
var _bootfocus_phase: int = 0
var _bootfocus_wait: int = 0
var _bootfocus_failures: int = 0
var _bootfocus_game: String = "" ## env PVLDS_BOOTFOCUS_GAME: the seeded last-played game id the boot must focus
var _smoke_jumpbench: bool = false ## --pvlds-smoke-jumpbench: pick-latency timings at field scale (360-game fixture library)
var _jumpbench_phase: int = 0
var _jumpbench_wait: int = 0
var _jumpbench_t0: int = 0
var _jumpbench_frames: int = 0
var _jumpbench_label: String = ""
var _jumpbench_after: int = -1 ## the phase entered when the in-flight measurement settles
var _jumpbench_failures: int = 0
var _jumpbench_boot_msec: int = 0
var _seated_cam: bool = false ## --pvlds-seated-cam: shots/nav run from a seated eye height
var _smoke_lockout: bool = false ## --pvlds-smoke-lockout: attack the load wait's input lockout mid-flight
var _lockout_smoke_pending: bool = false ## a launch fired by the lockout smoke is in its wait; _settle_launch prints its verdict
var _smoke_quitwarm: bool = false ## --pvlds-smoke-quitwarm: exit mid-warm-pass through the real Exit path (mode via PVLDS_QUITWARM_MODE)
var _quitwarm_fired: bool = false
var _quitwarm_started_msec: int = 0
## The drain deadline is a per-item budget, not a wall clock
## (half-2 round): the old flat 300 s was set when a pass was
## flat-only, and phase 2 (c35d2b9) legitimately doubled the
## per-file work - each fixture is read and decoded twice,
## flat then layers - so the honest pass outgrew the number
## and the smoke false-failed at c35d2b9. Measured on this
## box: ~5 s per ~14 MB file on a good night (148.9 s for
## 30), >10 s per file under load in the c35d2b9 run. 20 s
## per item is ~2x the worst observed per-item cost, so a
## healthy pass cannot trip it at any library size, while a
## HUNG pass (no progress at all - the fault this smoke
## exists to catch) still trips it in bounded time. The
## harness's shell timeout scales with the same formula.
const QUITWARM_PER_ITEM_BUDGET_MSEC: int = 20000
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
var _shot_mimic_prefix: String = "" ## --pvlds-shot-mimic PREFIX: the power-on mimic's QA hook (the swap round) - fixture assertion suite by default, real-table stills under PVLDS_MIMIC_REAL=1
var _shot_mimic_phase: int = -1
var _shot_mimic_stage: int = 0 ## sub-state inside the current phase
var _shot_mimic_since: int = 0
var _shot_mimic_wait: int = 0
var _shot_mimic_problems: Array[String] = []
var _shot_mimic_nc: String = "" ## PVLDS_MIMIC_NC: the harness's negative control ("grade" | "pair")
var _shot_mimic_real: bool = false ## PVLDS_MIMIC_REAL=1: the real-table stills boot
var _shot_mimic_wide: GameEntry = null ## the bulb-bearing fixture game (full mimic leg)
var _shot_mimic_wide_panel: ClickableQuad = null
var _shot_mimic_panel2: ClickableQuad = null ## the Cinder Peak panel (debounce partner, plain-face uniformity leg)
var _shot_mimic_title_panel: ClickableQuad = null ## a true title-card panel when one stands on the wall
var _shot_mimic_partner: ClickableQuad = null ## the debounce leg's fast-pass partner: any other panel on the wide card's page
var _shot_mimic_flip_tried: bool = false ## the wide fixture stood on page two (13 fixture titles, 12 slots): the driver flipped once to find it
var _shot_mimic_on_page2: bool = false ## the wide legs ran on page two; leg 4 flips back before resolving its subjects
var _shot_mimic_fixtures: Dictionary = {} ## fixture title prefix -> {"game": GameEntry, "panel": ClickableQuad}
var _shot_mimic_base_children: int = 0 ## the wide panel's child count at rest (the one-overlay assertion's baseline)
var _shot_mimic_saw_power: bool = false ## debounce leg: a power-on was seen during the fast pass
var _shot_mimic_parks: Array = [] ## the current leg's parked probes: [[cascade_t, grab_key], ...]
var _shot_mimic_park: int = 0
var _shot_mimic_grabs: Dictionary = {} ## grab_key -> Image (parked frames of the current leg)
var _shot_mimic_rest_img: Image = null ## the current leg's rest grab (the restore identity comparison)
var _shot_mimic_quick: Array = [] ## leg 4's subjects: [label, panel, want_mode]
var _shot_mimic_quick_i: int = 0
var _shot_mimic_subjects: Array = [] ## real boot: [{key, game, panel}] in judging order
var _shot_mimic_idx: int = 0
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
	var shot_mimic_idx: int = user_args.find("--pvlds-shot-mimic")
	if shot_mimic_idx >= 0 and shot_mimic_idx + 1 < user_args.size():
		_shot_mimic_prefix = user_args[shot_mimic_idx + 1]
		_shot_mimic_phase = 0
		_shot_mimic_nc = OS.get_environment("PVLDS_MIMIC_NC")
		_shot_mimic_real = OS.get_environment("PVLDS_MIMIC_REAL") == "1"
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
	if user_args.has("--pvlds-smoke-tournament"):
		_smoke_tournament = true
		_tournament_smoke_mode = OS.get_environment("PVLDS_WOVP_SMOKE_MODE")
		if _tournament_smoke_mode == "":
			_tournament_smoke_mode = "full"
		# The honesty negative control (harness env): send
		# Studio's client id instead of PVLDS's own, so the
		# smoke's client-id leg fails by name. Set here,
		# before any request can be made.
		if OS.get_environment("PVLDS_WOVP_NC") == "clientid":
			WovpClient.debug_client_id_override = "vpin-studio"
	if user_args.has("--pvlds-smoke-letters"):
		_smoke_letters = true
	if user_args.has("--pvlds-smoke-grad"):
		_smoke_grad = true
		# The negative control (harness env): the index stops
		# stripping a leading "The", so every canonical-The
		# game files under T and the driver's canonical-The
		# legs fail by name. Set here, before any room exists.
		LetterIndex.debug_disable_the_strip = OS.get_environment("PVLDS_LJ_NC") == "nostrip"
	if user_args.has("--pvlds-smoke-bootfocus"):
		_smoke_bootfocus = true
		_bootfocus_game = OS.get_environment("PVLDS_BOOTFOCUS_GAME")
	if user_args.has("--pvlds-smoke-jumpbench"):
		_smoke_jumpbench = true
		_jumpbench_boot_msec = Time.get_ticks_msec()
	# The focus-fix round's negative-control seam (harness
	# env): "visual" starves the strip quads of visual-state
	# refreshes (fault 1), "pager" drops the page-travel focus
	# landing (fault 2). Set here, before any room exists.
	RoomView.debug_focus_nc = OS.get_environment("PVLDS_FOCUS_NC")
	# The board-layout negative-control seam (PVLDS_BOARD_NC=
	# oldlayout): restores the pre-TR3 board presentation so
	# the tournament smoke's layout legs fail against it.
	RoomSpecs.board_nc_old = OS.get_environment("PVLDS_BOARD_NC") == "oldlayout"
	# The pick-latency bench seam (PVLDS_BENCH): the room's
	# fills print their phase timings + render counts.
	RoomView.debug_bench = OS.has_environment("PVLDS_BENCH")
	# The graduation's world-lock negative-control seam
	# (PVLDS_BG_NC=drum): parents the background stack to the
	# drum so the graduation smoke's lock leg fails by name.
	RoomView.debug_bg_nc = OS.get_environment("PVLDS_BG_NC")
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
	elif (_smoke_launch_game != "" or _smoke_lockout or _smoke_dpadexit or _smoke_nav or _smoke_letters or _smoke_bootfocus or _smoke_jumpbench or _shot_pop_prefix != "" or _shot_mimic_prefix != "" or _smoke_setup_panel or _shot_setup_panel_path != "" or _smoke_tournament) and not configured:
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
	# The author-shot fetcher: at each scan landing it walks the
	# library once and brings every tableFile imgUrl home to the
	# shot cache (the card faces' primary source). A landed shot
	# tells the room, which swaps the standing card's fallback
	# face for the shot in place.
	_shot_fetcher = ShotFetcher.new()
	add_child(_shot_fetcher)
	_shot_fetcher.shot_arrived.connect(_on_shot_arrived)
	# The WoVP client (read side only) + the last-good boards
	# off the disk cache, so an offline boot still shows the
	# boards with their stamp. The cached identity is trusted
	# only when the cache's key hash matches the key now
	# saved - a swapped key never inherits another player's
	# highlighted rows.
	_wovp_client = WovpClient.new()
	add_child(_wovp_client)
	_wovp_client.validation_finished.connect(_on_wovp_validation_finished)
	_wovp_client.challenges_finished.connect(_on_wovp_challenges_finished)
	var wovp_cache: Dictionary = WovpClient.load_cache()
	if bool(wovp_cache.get("ok", false)):
		_wovp_challenges = wovp_cache.get("challenges", [])
		_wovp_fetched_at = int(wovp_cache.get("fetched_at", 0))
		if int(wovp_cache.get("key_hash", 0)) == _wovp_key_hash() and _wovp_key_hash() != 0:
			_wovp_user_id = str(wovp_cache.get("user_id", ""))
			_wovp_user_name = str(wovp_cache.get("user_name", ""))
			_wovp_identity_key_hash = _wovp_key_hash()
			_wovp_identity_state = "ok"
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
	if _smoke_letters:
		_drive_letters_smoke()
	if _smoke_grad:
		_drive_grad_smoke()
	if _smoke_tournament:
		_drive_tournament_smoke()
	if _smoke_bootfocus:
		_drive_bootfocus_smoke()
	if _smoke_jumpbench:
		_drive_jumpbench_smoke()
	if _smoke_quitwarm:
		_drive_quitwarm_smoke()
	if _art_bench:
		_drive_art_bench(_delta)
	if _shot_pop_phase >= 0:
		_drive_shot_pop()
	if _shot_slide_phase >= 0:
		_drive_shot_slide()
	if _shot_mimic_phase >= 0:
		_drive_shot_mimic()
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


## Whether this run may fetch author shots: real runs always;
## dev/harness runs (any --pvlds-* user arg) only when the
## environment opts in with PVLDS_SHOT_MODE=on (the graduation
## harness serves the shots from a local stub via
## PVLDS_SHOT_BASE and says so).
func _shots_may_fetch() -> bool:
	if OS.get_environment("PVLDS_SHOT_MODE") == "on":
		return true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--pvlds-"):
			return false
	return true


## A shot landed for a game: the room swaps its standing
## card's face if the card is on the drum's window.
func _on_shot_arrived(game: GameEntry) -> void:
	if _room != null:
		_room.refresh_shot_faces(game)


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
	# ...and fetch the library's author shots (the card faces'
	# primary source) on the same landing. Hermetic runs (any
	# --pvlds-* dev arg: smokes, shots, core test) never touch
	# the network for shots unless PVLDS_SHOT_MODE=on arms it -
	# the graduation smoke points PVLDS_SHOT_BASE at a local
	# stub and opts in explicitly.
	if _shot_fetcher != null and _scanner != null and _shots_may_fetch():
		_shot_fetcher.fetch_library(_scanner.games)
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
## scan - the desk summary's facts, minus the prose. The
## WoVP line rides along even before any scan (the spec
## reads "no scan yet" off the missing counts, not an empty
## dictionary).
func _setup_panel_health() -> Dictionary:
	if _scanner == null:
		return {"wovp_line": _wovp_health_line()}
	return {
		"files": _scanner.total_files,
		"games": _scanner.games.size(),
		"matched": _scanner.matched_files,
		"game_matched": _scanner.game_matched_files,
		"db_ok": _last_db_ok,
		"db_kind": _last_db_kind,
		"missing": _scanner.missing_b2s_files.size(),
		"wovp_line": _wovp_health_line(),
	}


# ------------------------------------------------------------- WoVP

## The key's identity hash - the ONLY trace of the key any
## state keeps. The key itself lives in the config alone.
func _wovp_key_hash() -> int:
	if _config == null or _config.wovp_api_key == "":
		return 0
	return _config.wovp_api_key.hash()


## The SETUP panel face's WoVP line: the key's standing in
## plain words - whose it is once a test has resolved it.
func _wovp_health_line() -> String:
	if _config == null or _config.wovp_api_key == "":
		return "WoVP: no key saved. Copy your key, then press PASTE KEY below - or add it on the desktop desk."
	match _wovp_identity_state:
		"ok":
			return "WoVP: key saved - it belongs to %s." % _wovp_user_name
		"failed":
			return "WoVP: key saved, but its last test failed (%s)." % _wovp_identity_note
	return "WoVP: a key is saved (not tested yet - press TEST KEY below)."


func _refresh_setup_panel_health() -> void:
	if _room != null:
		_room.set_setup_health(_setup_panel_health())


## Push the standing WoVP truth to the room (its banner,
## boards, and state panels render exactly this).
func _push_wovp_data() -> void:
	if _room == null:
		return
	_room.set_wovp_data({
		"has_key": _config != null and _config.wovp_api_key != "",
		"user_id": _wovp_user_id,
		"challenges": _wovp_challenges,
		"fetched_at": _wovp_fetched_at,
		"live": _wovp_boards_live,
		"fetch_error": _wovp_fetch_error,
	})
	_resolve_unowned_shots()


## A challenge whose table he does not own still gets its
## art (the Tournament redesign): the db's author screenshot
## for the challenge's exact table file, fetched through the
## same ShotFetcher the library uses and worn by the
## synthetic entry's face chain. No db art: the card wears
## its generated title face - never another table's art.
func _resolve_unowned_shots() -> void:
	if _db == null or _shot_fetcher == null or _room == null:
		return
	var want: Array[GameEntry] = []
	for rv: Variant in _room.tournament_rows():
		var row: Dictionary = rv as Dictionary
		if str(row.get("kind", "")) != "challenge" or bool(row.get("owned", false)):
			continue
		var game: GameEntry = row.get("game") as GameEntry
		var ch: WovpChallenge = row.get("challenge") as WovpChallenge
		if game == null or ch == null:
			continue
		if game.shot_url == "":
			game.shot_url = _db_shot_url_for(ch)
		if game.shot_url != "" and not ArtProvider.shot_is_cached(game.shot_url) \
				and not ArtProvider.is_negative_outcome(ArtProvider.shot_outcome(game.shot_url)):
			want.append(game)
	if not want.is_empty():
		_shot_fetcher.fetch_library(want)


## The db's image for one challenge: its exact table file's
## screenshot first, then the game record's own image, then
## any of the game's table files.
func _db_shot_url_for(ch: WovpChallenge) -> String:
	for tfv: Variant in _db.table_files_of(ch.table_external_id):
		var tf: Dictionary = tfv as Dictionary
		if str(tf.get("id", "")) == ch.version_external_id:
			var u: String = str(tf.get("imgUrl", ""))
			if u != "":
				return u
	var gd: Dictionary = _db.game_dict(ch.table_external_id)
	var gu: String = str(gd.get("imgUrl", ""))
	if gu != "":
		return gu
	for tfv: Variant in _db.table_files_of(ch.table_external_id):
		var u2: String = str((tfv as Dictionary).get("imgUrl", ""))
		if u2 != "":
			return u2
	return ""


## Fetch the boards: resolve the key's identity first when
## it is unknown (or belongs to a different key), then the
## challenges. Entering the Tournament Room, REFRESH, and a
## key save all land here.
func _wovp_fetch_boards() -> void:
	if _config == null or _config.wovp_api_key == "" or _wovp_client == null:
		_push_wovp_data()
		return
	if _wovp_client.is_busy():
		return
	if _wovp_user_id == "" or _wovp_identity_key_hash != _wovp_key_hash():
		_wovp_validating_for = "fetch"
		_wovp_validating_key_hash = _wovp_key_hash()
		_wovp_client.validate_key(_config.wovp_api_key)
	else:
		_wovp_client.fetch_challenges(_config.wovp_api_key)


func _on_wovp_validation_finished(ok: bool, message: String, user_id: String, display_name: String) -> void:
	var who: String = _wovp_validating_for
	_wovp_validating_for = ""
	# Identity bookkeeping belongs to the SAVED key alone: a
	# desk test of an unsaved paste answers the desk and
	# changes nothing here.
	var about_saved_key: bool = _wovp_validating_key_hash != 0 and _wovp_validating_key_hash == _wovp_key_hash()
	_wovp_validating_key_hash = 0
	if ok and about_saved_key:
		_wovp_user_id = user_id
		_wovp_user_name = display_name
		_wovp_identity_key_hash = _wovp_key_hash()
		_wovp_identity_state = "ok"
		_wovp_identity_note = ""
	elif not ok and about_saved_key:
		_wovp_identity_state = "failed"
		_wovp_identity_note = message
	match who:
		"fetch":
			if ok:
				_wovp_client.fetch_challenges(_config.wovp_api_key)
			else:
				_wovp_fetch_error = message
				_push_wovp_data()
		"room":
			if _room != null:
				_room.set_setup_panel_message("That key belongs to %s." % display_name if ok else message)
		"desk":
			if _desk != null:
				_desk.set_wovp_status("That key belongs to %s." % display_name if ok else message)
	if ok:
		# A resolved identity can change which rows are HIS
		# on boards already standing (the cache's, at boot).
		_push_wovp_data()
	_refresh_setup_panel_health()


func _on_wovp_challenges_finished(ok: bool, message: String, challenges: Array, raw_body: String) -> void:
	if ok:
		_wovp_challenges = challenges
		_wovp_fetched_at = int(Time.get_unix_time_from_system())
		_wovp_boards_live = true
		_wovp_fetch_error = ""
		WovpClient.save_cache(raw_body, _wovp_user_id, _wovp_user_name, _wovp_fetched_at, _wovp_key_hash())
	else:
		# The last good boards stand, with their stamp - the
		# failure rides the banner, never a silent freeze.
		_wovp_fetch_error = message
	_push_wovp_data()


## The room SETUP panel's PASTE KEY: the clipboard's key,
## saved to the config here (the room never holds config).
## A save also fetches, so the Tournament Room is warm when
## he walks back to it.
## A SETUP display dial turned in the room: the room already
## applied the value; Main's half is persistence - the
## standing values ride into the config file so the dials
## survive the next boot.
func _on_display_settings_changed() -> void:
	if _config == null or _room == null:
		return
	_config.wing_enabled = _room.wing_enabled()
	_config.starfield_mode = _room.starfield_mode()
	_config.save_to_disk()


func _on_room_wovp_key_pasted(api_key: String) -> void:
	if _config == null:
		return
	_config.wovp_api_key = api_key.strip_edges()
	if _config.save_to_disk():
		_wovp_identity_state = "untested"
		if _room != null:
			var length_note: String = WovpClient.key_length_note(_config.wovp_api_key)
			if length_note == "":
				_room.set_setup_panel_message("WoVP key saved. Press TEST KEY to check whose it is.")
			else:
				_room.set_setup_panel_message("WoVP key saved. " + length_note)
		_refresh_setup_panel_health()
		_wovp_fetch_boards()
	elif _room != null:
		_room.set_setup_panel_message("That key could NOT be saved - the config file is not writable.")


## The room SETUP panel's TEST KEY: validate the SAVED key
## and name whose it is on the panel's message line. A
## wrong-length saved key is answered here, in words, and
## nothing is sent - WoVP's answer to that shape is
## already known (the client refuses it too, as backstop).
func _on_room_wovp_key_test() -> void:
	if _config == null or _config.wovp_api_key == "":
		if _room != null:
			_room.set_setup_panel_message("No WoVP key saved yet - paste one first (PASTE KEY).")
		return
	var length_note: String = WovpClient.key_length_note(_config.wovp_api_key)
	if length_note != "":
		if _room != null:
			_room.set_setup_panel_message(length_note)
		return
	if _wovp_client != null and not _wovp_client.is_busy():
		_wovp_validating_for = "room"
		_wovp_validating_key_hash = _wovp_key_hash()
		_wovp_client.validate_key(_config.wovp_api_key)


## The desk's Save key landed: warm the boards for the room.
func _on_desk_wovp_key_saved() -> void:
	_wovp_identity_state = "untested" if _wovp_identity_key_hash != _wovp_key_hash() else _wovp_identity_state
	_refresh_setup_panel_health()
	_wovp_fetch_boards()


## The desk's Test key: validate the FIELD's text (what he
## pasted, saved or not) and answer on the desk's status
## line.
func _on_desk_wovp_test_requested(api_key: String) -> void:
	if _wovp_client != null and not _wovp_client.is_busy():
		_wovp_validating_for = "desk"
		_wovp_validating_key_hash = api_key.hash() if api_key != "" else 0
		_wovp_client.validate_key(api_key)
	elif _desk != null:
		_desk.set_wovp_status("Another WoVP request is already running - one moment.")


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
		_room.tournament_refresh_requested.connect(_wovp_fetch_boards)
		_room.wovp_key_pasted.connect(_on_room_wovp_key_pasted)
		_room.wovp_key_test_requested.connect(_on_room_wovp_key_test)
		_room.display_settings_changed.connect(_on_display_settings_changed)
		_room.set_wing_enabled(_config.wing_enabled)
		_room.set_starfield_mode(_config.starfield_mode)
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
	# The Tournament Room's standing data (the cache's boards
	# at boot) reaches the room here.
	_push_wovp_data()
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
## The mimic shot's visible-evidence measure: mean colour and
## per-quadrant mean luminance over a screen rect of a grabbed
## frame (stride 2 - statistics, not pixels; the identity legs
## use _mimic_max_diff for the pixel claim).
func _mimic_region_stats(img: Image, rect: Rect2i) -> Dictionary:
	var sum: Color = Color(0, 0, 0, 0)
	var quads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var quad_n: Array[int] = [0, 0, 0, 0]
	var n: int = 0
	var mid: Vector2 = Vector2(rect.get_center())
	var x: int = rect.position.x
	while x < rect.position.x + rect.size.x:
		var y: int = rect.position.y
		while y < rect.position.y + rect.size.y:
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var px: Color = img.get_pixel(x, y)
				sum += px
				var lum: float = 0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b
				var qi: int = (1 if float(x) >= mid.x else 0) + (2 if float(y) >= mid.y else 0)
				quads[qi] += lum
				quad_n[qi] += 1
				n += 1
			y += 2
		x += 2
	if n == 0:
		return {"mean": Color(0, 0, 0), "luma": 0.0, "quads": quads}
	for qi2: int in range(4):
		if quad_n[qi2] > 0:
			quads[qi2] /= float(quad_n[qi2])
	return {"mean": sum / float(n), "luma": 0.2126 * (sum.r / float(n)) + 0.7152 * (sum.g / float(n)) + 0.0722 * (sum.b / float(n)), "quads": quads}


## The largest per-channel difference between two grabbed
## frames over a rect, in 0-255 steps (stride 2).
func _mimic_max_diff(a: Image, b: Image, rect: Rect2i) -> int:
	var worst: int = 0
	var x: int = rect.position.x
	while x < rect.position.x + rect.size.x:
		var y: int = rect.position.y
		while y < rect.position.y + rect.size.y:
			if x >= 0 and y >= 0 and x < a.get_width() and y < a.get_height() and x < b.get_width() and y < b.get_height():
				var pa: Color = a.get_pixel(x, y)
				var pb: Color = b.get_pixel(x, y)
				worst = maxi(worst, int(round(maxf(absf(pa.r - pb.r), maxf(absf(pa.g - pb.g), absf(pa.b - pb.b))) * 255.0)))
			y += 2
		x += 2
	return worst


## The performing panel's art area as a screen rect: the
## panel's projected corners (the crop the prototype printed
## as MIMIC_CROP), cut to the face above the name strip and
## inset so edge filtering never pollutes a statistic.
func _mimic_art_screen_rect(panel: ClickableQuad) -> Rect2i:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return Rect2i()
	var half: Vector2 = _room._panel_size * 0.5
	var pts: Array[Vector2] = []
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		pts.append(cam.unproject_position(panel.global_transform * Vector3(c.x, c.y, 0.0)))
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p: Vector2 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	# The stats window is the face's top 396 rows (of 640):
	# the whole art area would include the Launch button
	# standing over the card's lower third.
	var art_h: float = (mx.y - mn.y) * (396.0 / 640.0)
	var r: Rect2 = Rect2(mn, Vector2(mx.x - mn.x, art_h))
	r = r.grow_individual(-r.size.x * 0.05, -r.size.y * 0.05, -r.size.x * 0.05, -r.size.y * 0.05)
	return Rect2i(int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y))


## The shader's soft shoulder, mirrored (the reference grade
## below must be an independent statement of the same math).
func _mimic_shoulder(c: float) -> float:
	var knee: float = 0.92
	var cap: float = 0.99
	if c <= knee:
		return c
	var span: float = cap - knee
	return knee + span * (1.0 - exp(-(c - knee) / span))


## One pixel of the settled reference grade: the mimic
## shader's math at power 1, sweep complete (front = 1
## across the whole glass there).
func _mimic_ref_grade_pixel(src: Color) -> Color:
	var lum: float = 0.2126 * src.r + 0.7152 * src.g + 0.0722 * src.b
	var mx: float = maxf(src.r, maxf(src.g, src.b))
	var mn: float = minf(src.r, minf(src.g, src.b))
	var sat: float = (mx - mn) / mx if mx > 0.001 else 0.0
	var head: float = clampf((1.0 - lum) / 0.35, 0.15, 1.0)
	var drive: float = head * (0.78 * pow(lum, 0.75) + 0.70 * sat * (0.25 + 0.75 * lum))
	var glow: float = 0.40 * head * smoothstep(0.70, 1.0, lum)
	var act: float = clampf(drive + glow, 0.0, 1.0)
	var out: Color = Color()
	for ch: int in range(3):
		var s: float = src[ch]
		var g: float = s * (1.0 + drive) + s * glow
		out[ch] = lerpf(s, _mimic_shoulder(g), act)
	out.a = 1.0
	return out


## Reference statistics for a face image AS THE FACE DRAWS
## IT: the art cover-fit into the 512x640 face frame (the
## rule CardFace and the retired layers both used), sampled
## over the visible art window (the face above the strip).
## grade=true applies the settled reference grade per pixel
## (the mimic's settled claim); grade=false reads the plain
## face (the rest claim, and a pair On's settled claim).
func _mimic_ref_stats(art: Image, grade: bool) -> Dictionary:
	var face: Vector2 = Vector2(512.0, 640.0)
	var win_h: float = 396.0 ## the stats window (see _mimic_art_screen_rect): the face's top rows, above the Launch button
	var aw: float = float(art.get_width())
	var ah: float = float(art.get_height())
	var cover: float = maxf(face.x / aw, face.y / ah)
	var ox: float = (face.x - aw * cover) * 0.5
	var oy: float = (face.y - ah * cover) * 0.5
	var sum: Color = Color(0, 0, 0, 0)
	var quads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var quad_n: Array[int] = [0, 0, 0, 0]
	var n: int = 0
	var y: int = 0
	while y < int(win_h):
		var x: int = 0
		while x < int(face.x):
			var ax: int = clampi(int((float(x) - ox) / cover), 0, art.get_width() - 1)
			var ay: int = clampi(int((float(y) - oy) / cover), 0, art.get_height() - 1)
			var px: Color = art.get_pixel(ax, ay)
			if grade:
				px = _mimic_ref_grade_pixel(px)
			sum += px
			var lum: float = 0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b
			var qi: int = (1 if float(x) >= face.x * 0.5 else 0) + (2 if float(y) >= win_h * 0.5 else 0)
			quads[qi] += lum
			quad_n[qi] += 1
			n += 1
			x += 4
		y += 4
	for qi2: int in range(4):
		if quad_n[qi2] > 0:
			quads[qi2] /= float(quad_n[qi2])
	return {"mean": sum / float(n), "luma": 0.2126 * (sum.r / float(n)) + 0.7152 * (sum.g / float(n)) + 0.0722 * (sum.b / float(n)), "quads": quads}


func _mimic_finish() -> void:
	_shot_mimic_phase = -2
	if _shot_mimic_problems.is_empty():
		print("PVLDS MIMIC SHOT: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS MIMIC SHOT: FAIL - ", "; ".join(PackedStringArray(_shot_mimic_problems)))
		get_tree().quit(1)


## --pvlds-shot-mimic PREFIX: the power-on mimic's QA hook
## (the swap round). Two boots share this driver:
##  * the fixture boot (default): the harness's fixture
##    folder beside the dummy library. The fixture FILES
##    survive the swap (they are real .directb2s shapes);
##    what they exercise changed entirely. Legs: (1) the
##    settle debounce - a fast focus pass never starts a
##    power-on; (2) the wide bulb fixture's full mimic leg -
##    rest identity at power 0 across a restore, the sag dip
##    present at 0.34 s, the diagonal sweep (TL lifted
##    before BR mid-sweep), settled = the grade (against a
##    reference grade of the face computed here), exactly
##    ONE overlay quad on the performing panel, restore
##    returns the plain face; (3) the Specter pair leg -
##    rest is the Off face, settled is the author's On
##    image, restore returns to Off; (4) quick uniformity
##    legs - the plain pair (mode 3) and the flasher,
##    animation, wart and warmed fixtures and title faces
##    (mode 2) all take the same performance and settle;
##    (5) opening detail mid-cascade cancels cleanly;
##    (6) the structural assertion: after every focus above,
##    no layer cache exists on disk - the snippet stack is
##    gone, not dormant. Parked probes freeze the room's
##    cascade clock the prototype's way (phase pinned to 2,
##    the driver the only writer of _power_t).
##    Negative controls (harness env PVLDS_MIMIC_NC):
##    "grade" pins the cascade clock at 0 through leg 2, so
##    its settled-grade assertion must fail by name; "pair"
##    pins it at the crossfade's start through leg 3, so
##    its settled-On assertion must fail by name.
##  * the real boot (env PVLDS_MIMIC_REAL=1): the harness's
##    three-table library of REAL .directb2s files (Taxi,
##    Goonies, Bride). Assertions stop at mode 2 + started:
##    the driver parks the clock at the envelope's named
##    instants and saves PREFIX_<key>_<still>.png stills
##    plus a MIMIC_CROP line per subject; the harness's
##    Python post-check verifies the settled frames against
##    an independent reference grade of each real face.
## Resolve the subjects standing on the wall's CURRENT page
## (panels are rebuilt per page; a subject not standing here
## keeps whatever reference it had - callers re-resolve after
## every flip).
func _mimic_resolve_panels() -> void:
	for p: ClickableQuad in _room._panels:
		if _shot_mimic_wide != null and p.payload == _shot_mimic_wide.game_id:
			_shot_mimic_wide_panel = p
		elif p.payload == "dg-cinder-peak":
			_shot_mimic_panel2 = p
		for pre2: String in _shot_mimic_fixtures.keys():
			var fx0: Dictionary = _shot_mimic_fixtures[pre2] as Dictionary
			if p.payload == (fx0["game"] as GameEntry).game_id:
				fx0["panel"] = p
		if _shot_mimic_title_panel == null:
			var tg: GameEntry = _scanner.game_by_id(p.payload)
			if tg != null and not tg.has_art_available():
				_shot_mimic_title_panel = p


func _drive_shot_mimic() -> void:
	var now: int = Time.get_ticks_msec()
	if _shot_mimic_real:
		_drive_shot_mimic_real(now)
		return
	if now - _shot_mimic_since > 120000 and _shot_mimic_phase > 0:
		_shot_mimic_problems.append("timed out in phase %d" % _shot_mimic_phase)
		_mimic_finish()
		return
	match _shot_mimic_phase:
		0:
			if _room == null or not _room.visible or not _room.wall_ready or _scanner == null:
				return
			if _shot_mimic_stage == 0:
				_room._handle_rail("filter:all")
				get_viewport().warp_mouse(Vector2(512, 764)) ## parked over the furniture: on the drum a corner park can sit on a top-band card, and hover would drive the centre away from the legs' focused fixture (the nav driver's lesson)
				_shot_mimic_stage = 1
				_shot_mimic_since = now
				return
			if _shot_mimic_wide == null:
				for g: GameEntry in _scanner.games:
					if g.title.begins_with("Flicker Wide"):
						_shot_mimic_wide = g
					for pre: String in ["Flicker Specter", "Flicker Pair", "Flicker Flasher", "Flicker Anim", "Flicker Wart", "Flicker Warmed"]:
						if pre == "Flicker Pair" and g.title.begins_with("Flicker Pair Plain"):
							continue
						if g.title.begins_with(pre):
							_shot_mimic_fixtures[pre] = {"game": g}
			if _shot_mimic_wide == null:
				if not _scan_active:
					_shot_mimic_problems.append("the Flicker Wide fixture game is not in the library (the harness config names its folder)")
					_mimic_finish()
				return
			if _shot_mimic_stage == 3:
				# Returning from the page flip: wait for the
				# slide and the rebuild to land, then resolve.
				if _room.page_slide_active() or not _room.wall_ready:
					return
				_shot_mimic_stage = 2
			_mimic_resolve_panels()
			if _shot_mimic_wide_panel == null:
				if not _shot_mimic_flip_tried:
					# Thirteen fixture titles chase twelve
					# slots: the wide card may stand on page
					# two. Flip once and look again.
					_shot_mimic_flip_tried = true
					_shot_mimic_on_page2 = true
					_room._bumper_page(1)
					_shot_mimic_stage = 3
					return
				_shot_mimic_problems.append("the wide fixture panel is not on either page")
				_mimic_finish()
				return
			# The debounce partner: any other panel standing
			# on the wide card's page.
			if _shot_mimic_partner == null:
				for p2: ClickableQuad in _room._panels:
					if p2 != _shot_mimic_wide_panel:
						_shot_mimic_partner = p2
						break
			_shot_mimic_base_children = _shot_mimic_wide_panel.get_child_count()
			_shot_mimic_phase = 1
			_shot_mimic_stage = 0
			_shot_mimic_since = now
		1:
			# Debounce leg: a ~90 ms rest on the wide card
			# (well inside the settle window, and time-based -
			# a frame count would straddle the window at
			# software-render frame rates), then focus moves
			# on. The passed card may never perform; the card
			# focus lands on may (it gets its own settle -
			# leg 2's focus change restores it).
			match _shot_mimic_stage:
				0:
					_room._set_focused(_shot_mimic_wide_panel)
					_shot_mimic_stage = 1
					_shot_mimic_wait = 0
					_shot_mimic_since = now
				1:
					_shot_mimic_wait += 1
					if _room.power_panel() == _shot_mimic_wide_panel:
						_shot_mimic_problems.append("debounce leg: a fast focus pass started a power-on on the passed card (the settle debounce is broken)")
						_mimic_finish()
						return
					if now - _shot_mimic_since > 90 and _shot_mimic_wait >= 1:
						_room._set_focused(_shot_mimic_partner)
						_shot_mimic_stage = 2
						_shot_mimic_since = now
				2:
					if _room.power_panel() == _shot_mimic_wide_panel:
						_shot_mimic_problems.append("debounce leg: a fast focus pass started a power-on on the passed card (the settle debounce is broken)")
						_mimic_finish()
						return
					if now - _shot_mimic_since > 350:
						_room._set_focused(null)
						_shot_mimic_phase = 2
						_shot_mimic_stage = 0
						_shot_mimic_since = now
		2:
			_drive_mimic_wide_leg(now)
		3:
			_drive_mimic_pair_leg(now)
		4:
			_drive_mimic_quick_leg(now)
		5:
			# Detail-cancel leg: open detail mid-cascade; the
			# performer restores in the same breath. The
			# subject is the Specter pair (a page-one card;
			# the wide card may stand on page two).
			var dfx: Dictionary = _shot_mimic_fixtures.get("Flicker Specter", {}) as Dictionary
			var dpanel: ClickableQuad = dfx.get("panel", null) as ClickableQuad
			match _shot_mimic_stage:
				0:
					_room._set_focused(dpanel)
					_shot_mimic_stage = 1
					_shot_mimic_since = now
				1:
					if _room.power_panel() == dpanel and _room.power_phase() == 1:
						_room._open_detail(dfx["game"] as GameEntry)
						_shot_mimic_stage = 2
						_shot_mimic_since = now
					elif now - _shot_mimic_since > 15000:
						_shot_mimic_problems.append("detail-cancel leg: the cascade never started")
						_mimic_finish()
				2:
					if now - _shot_mimic_since > 150:
						if _room.power_phase() != 0 or _room.power_overlay_count() != 0:
							_shot_mimic_problems.append("detail-cancel leg: opening detail did not cancel the power-on (phase %d, overlays %d)" % [_room.power_phase(), _room.power_overlay_count()])
						_room._detail.handle_escape()
						_room._on_detail_closed()
						_shot_mimic_stage = 3
						_shot_mimic_since = now
				3:
					if _room.wall_ready and now - _shot_mimic_since > 300:
						_shot_mimic_phase = 6
						_shot_mimic_since = now
		6:
			# The structural assertion: the whole suite above
			# focused B2S cards repeatedly - if any snippet
			# machinery survived, its cache would exist.
			if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://art_cache/layers")):
				_shot_mimic_problems.append("no-layer-machinery assertion: user://art_cache/layers exists after the suite's focuses - the snippet stack is dormant, not gone")
			_mimic_finish()


## Leg 2's sub-driver (see _drive_shot_mimic's doc): the wide
## fixture's full mimic leg, on parked probes.
func _drive_mimic_wide_leg(now: int) -> void:
	var panel: ClickableQuad = _shot_mimic_wide_panel
	match _shot_mimic_stage:
		0:
			_room._set_focused(panel)
			_shot_mimic_stage = 1
			_shot_mimic_since = now
		1:
			if _shot_mimic_nc == "grade":
				# Negative control: the cascade clock is
				# pinned at 0, so the performance can never
				# settle - the settled-grade leg MUST fail.
				if _room.power_panel() == panel:
					_room._power_t = 0.0
				if now - _shot_mimic_since > 12000:
					_shot_mimic_problems.append("settled = grade leg failed: the cascade never settled (power pinned at 0)")
					_mimic_finish()
				return
			if _room.power_panel() == panel and _room.power_phase() >= 1:
				if _room.power_mode() != 2 or _room.power_is_pair():
					_shot_mimic_problems.append("wide leg: the bulb fixture did not take the mimic grade (mode %d)" % _room.power_mode())
					_mimic_finish()
					return
				# Freeze the room's clock (the prototype's
				# trick): from here the driver's pins are the
				# only writer of the cascade time.
				_room._power_phase = 2
				_shot_mimic_parks = [[0.0, "rest"], [0.27, "catch3"], [0.34, "sag"], [0.44, "mid"], [1.05, "settled"]]
				_shot_mimic_park = 0
				_shot_mimic_stage = 2
				_shot_mimic_wait = 0
			elif now - _shot_mimic_since > 20000:
				_shot_mimic_problems.append("wide leg: the power-on never started")
				_mimic_finish()
		2:
			var pk: Array = _shot_mimic_parks[_shot_mimic_park] as Array
			_room._power_t = float(pk[0])
			_room._apply_power()
			_shot_mimic_wait += 1
			if _room.power_overlay_count() != 1:
				_shot_mimic_problems.append("wide leg: the performance stands on %d overlay quads, want exactly 1" % _room.power_overlay_count())
				_mimic_finish()
				return
			if panel.get_child_count() != _shot_mimic_base_children + 1:
				_shot_mimic_problems.append("wide leg: the performing panel carries %d children, want baseline+1 (one overlay, no layer quads)" % panel.get_child_count())
				_mimic_finish()
				return
			if _shot_mimic_wait >= 5:
				var img: Image = get_viewport().get_texture().get_image()
				_shot_mimic_grabs[str(pk[1])] = img
				_shot_mimic_park += 1
				_shot_mimic_wait = 0
				if _shot_mimic_park >= _shot_mimic_parks.size():
					_shot_mimic_stage = 3
		3:
			# Judge the parked frames.
			var rect: Rect2i = _mimic_art_screen_rect(panel)
			var rest: Dictionary = _mimic_region_stats(_shot_mimic_grabs["rest"] as Image, rect)
			var catch3: Dictionary = _mimic_region_stats(_shot_mimic_grabs["catch3"] as Image, rect)
			var sag: Dictionary = _mimic_region_stats(_shot_mimic_grabs["sag"] as Image, rect)
			var mid: Dictionary = _mimic_region_stats(_shot_mimic_grabs["mid"] as Image, rect)
			var settled: Dictionary = _mimic_region_stats(_shot_mimic_grabs["settled"] as Image, rect)
			var art_path: String = _shot_mimic_wide.ensure_art()
			var art_img: Image = Image.new()
			if art_path == "" or art_img.load(art_path) != OK:
				_shot_mimic_problems.append("wide leg: the fixture's face art is unreadable for the reference grade")
				_mimic_finish()
				return
			var ref_rest: Dictionary = _mimic_ref_stats(art_img, false)
			var ref_settled: Dictionary = _mimic_ref_stats(art_img, true)
			if absf(float(rest["luma"]) - float(ref_rest["luma"])) > 0.02:
				_shot_mimic_problems.append("rest identity leg: the power-0 frame's art luma %.3f is not the face's %.3f" % [float(rest["luma"]), float(ref_rest["luma"])])
			var sq0: Array = sag["quads"] as Array
			var cq0: Array = catch3["quads"] as Array
			var rq0: Array = rest["quads"] as Array
			var stq0: Array = settled["quads"] as Array
			var sag_lift: float = float(sq0[0]) - float(rq0[0])
			var catch_lift: float = float(cq0[0]) - float(rq0[0])
			var settled_lift: float = float(stq0[0]) - float(rq0[0])
			if not (sag_lift < catch_lift + 0.002 and sag_lift < settled_lift - 0.002):
				_shot_mimic_problems.append("sag leg: no dip at 0.34s in the TL quadrant (lifts: catch3 %+.3f, sag %+.3f, settled %+.3f)" % [catch_lift, sag_lift, settled_lift])
			var rq: Array = rest["quads"] as Array
			var mq: Array = mid["quads"] as Array
			var tl_lift: float = float(mq[0]) - float(rq[0])
			var br_lift: float = float(mq[3]) - float(rq[3])
			if not (tl_lift > br_lift + 0.003):
				_shot_mimic_problems.append("sweep leg: the diagonal front is not TL-first at 0.44s (TL lift %.3f, BR lift %.3f)" % [tl_lift, br_lift])
			if absf(float(settled["luma"]) - float(ref_settled["luma"])) > 0.02:
				_shot_mimic_problems.append("settled = grade leg failed: settled art luma %.3f, reference grade %.3f" % [float(settled["luma"]), float(ref_settled["luma"])])
			var sq: Array = settled["quads"] as Array
			var refq: Array = ref_settled["quads"] as Array
			for qi: int in range(4):
				if absf(float(sq[qi]) - float(refq[qi])) > 0.035:
					_shot_mimic_problems.append("settled = grade leg failed: quadrant %d luma %.3f, reference %.3f" % [qi, float(sq[qi]), float(refq[qi])])
			_shot_mimic_rest_img = _shot_mimic_grabs["rest"] as Image
			# GRADUATION AMENDMENT: the flat wall's
			# performer followed the pad focus, so clearing
			# focus restored it. On the drum the performer
			# follows the CENTRE (the focus law): clearing
			# focus leaves the centre - and the performance
			# - standing. Focusing the partner moves the
			# centre, and the restore fires as shipped.
			_room._set_focused(_shot_mimic_partner)
			_shot_mimic_stage = 4
			_shot_mimic_since = now
		4:
			# The wide performance has restored once the
			# performer is no longer this panel (the
			# partner, now centred, may start its own -
			# stage 5's refocus restores that in turn).
			if _room.power_panel() != panel:
				_room._set_focused(panel)
				_shot_mimic_stage = 5
				_shot_mimic_since = now
			elif now - _shot_mimic_since > 10000:
				_shot_mimic_problems.append("wide leg: restore after the parked probes never completed")
				_mimic_finish()
		5:
			if _room.power_panel() == panel and _room.power_phase() >= 1:
				_room._power_phase = 2
				_room._power_t = 0.0
				_room._apply_power()
				_shot_mimic_stage = 6
				_shot_mimic_wait = 0
			elif now - _shot_mimic_since > 20000:
				_shot_mimic_problems.append("wide leg: the second visit never started its power-on")
				_mimic_finish()
		6:
			_shot_mimic_wait += 1
			if _shot_mimic_wait >= 5:
				var img2: Image = get_viewport().get_texture().get_image()
				var rect2: Rect2i = _mimic_art_screen_rect(panel)
				var d: int = _mimic_max_diff(_shot_mimic_rest_img, img2, rect2)
				if d > 3:
					_shot_mimic_problems.append("restore leg: the face after restore differs from the first rest frame by %d/255 - the restore left residue" % d)
				_room._set_focused(null)
				_shot_mimic_phase = 3
				_shot_mimic_stage = 90
				_shot_mimic_since = now


## Leg 3's sub-driver: the Specter pair leg, on parked probes.
func _drive_mimic_pair_leg(now: int) -> void:
	if _shot_mimic_stage == 90:
		# Entry: the wide legs may have run on page two -
		# flip home and re-resolve (the page-one panel
		# objects died with that wall).
		if _shot_mimic_on_page2:
			_room._bumper_page(-1)
			_shot_mimic_on_page2 = false
			_shot_mimic_stage = 91
		else:
			_shot_mimic_stage = 0
		_shot_mimic_since = now
		return
	if _shot_mimic_stage == 91:
		if not _room.page_slide_active() and _room.wall_ready:
			_mimic_resolve_panels()
			_shot_mimic_stage = 0
			_shot_mimic_since = now
		return
	var fx: Dictionary = _shot_mimic_fixtures.get("Flicker Specter", {}) as Dictionary
	if fx.is_empty():
		_shot_mimic_problems.append("pair leg: the Specter fixture is missing")
		_mimic_finish()
		return
	var game: GameEntry = fx["game"] as GameEntry
	var panel: ClickableQuad = fx["panel"] as ClickableQuad
	match _shot_mimic_stage:
		0:
			_room._set_focused(panel)
			_shot_mimic_stage = 1
			_shot_mimic_since = now
		1:
			if _shot_mimic_nc == "pair":
				# Negative control: the clock is pinned at
				# the crossfade's first instant, so the pair
				# can never settle onto its On image - the
				# settled-On leg MUST fail.
				if _room.power_panel() == panel:
					_room._power_t = RoomView.PAIR_MIX_T0
				if now - _shot_mimic_since > 12000:
					_shot_mimic_problems.append("pair settled = On leg failed: the cascade never settled (crossfade pinned at its start)")
					_mimic_finish()
				return
			if _room.power_panel() == panel and _room.power_phase() >= 1:
				if _room.power_mode() != 3 or not _room.power_is_pair():
					_shot_mimic_problems.append("pair leg: the Specter card did not take the pair crossfade (mode %d)" % _room.power_mode())
					_mimic_finish()
					return
				if game.pair_on_art() == "":
					_shot_mimic_problems.append("pair leg: the Specter game serves no pair On half - its extraction never cached one")
					_mimic_finish()
					return
				_room._power_phase = 2
				_shot_mimic_parks = [[0.0, "rest"], [1.05, "settled"]]
				_shot_mimic_park = 0
				_shot_mimic_stage = 2
				_shot_mimic_wait = 0
			elif now - _shot_mimic_since > 20000:
				_shot_mimic_problems.append("pair leg: the power-on never started")
				_mimic_finish()
		2:
			var pk: Array = _shot_mimic_parks[_shot_mimic_park] as Array
			_room._power_t = float(pk[0])
			_room._apply_power()
			_shot_mimic_wait += 1
			if _room.power_overlay_count() != 1:
				_shot_mimic_problems.append("pair leg: the performance stands on %d overlay quads, want exactly 1" % _room.power_overlay_count())
				_mimic_finish()
				return
			if _shot_mimic_wait >= 5:
				_shot_mimic_grabs[str(pk[1])] = get_viewport().get_texture().get_image()
				_shot_mimic_park += 1
				_shot_mimic_wait = 0
				if _shot_mimic_park >= _shot_mimic_parks.size():
					_shot_mimic_stage = 3
		3:
			var rect: Rect2i = _mimic_art_screen_rect(panel)
			var rest: Dictionary = _mimic_region_stats(_shot_mimic_grabs["rest"] as Image, rect)
			var settled: Dictionary = _mimic_region_stats(_shot_mimic_grabs["settled"] as Image, rect)
			var off_img: Image = Image.new()
			var on_img: Image = Image.new()
			if off_img.load(game.ensure_art()) != OK or on_img.load(game.pair_on_art()) != OK:
				_shot_mimic_problems.append("pair leg: the pair's halves are unreadable for the reference check")
				_mimic_finish()
				return
			var ref_off: Dictionary = _mimic_ref_stats(off_img, false)
			if absf(float(rest["luma"]) - float(ref_off["luma"])) > 0.02:
				_shot_mimic_problems.append("pair rest leg: the resting art luma %.3f is not the Off face's %.3f" % [float(rest["luma"]), float(ref_off["luma"])])
			# The On reference rides the overlay's own window:
			# the fitted On cover-fit into the art rect (not
			# the whole face frame).
			var on_mean: Color = _mimic_on_window_mean(on_img)
			var sm: Color = settled["mean"] as Color
			if absf(sm.r - on_mean.r) > 0.05 or absf(sm.g - on_mean.g) > 0.05 or absf(sm.b - on_mean.b) > 0.05:
				_shot_mimic_problems.append("pair settled = On leg failed: settled art colour (%.3f, %.3f, %.3f), the On image's window (%.3f, %.3f, %.3f)" % [sm.r, sm.g, sm.b, on_mean.r, on_mean.g, on_mean.b])
			if absf(float(settled["luma"]) - float(rest["luma"])) < 0.04:
				_shot_mimic_problems.append("pair settled = On leg failed: the settled frame barely differs from the Off rest (luma %.3f vs %.3f) - no crossfade happened" % [float(settled["luma"]), float(rest["luma"])])
			_shot_mimic_rest_img = _shot_mimic_grabs["rest"] as Image
			_room._set_focused(null)
			_shot_mimic_stage = 4
			_shot_mimic_since = now
		4:
			if _room.power_phase() == 0 and _room.power_overlay_count() == 0:
				_room._set_focused(panel)
				_shot_mimic_stage = 5
				_shot_mimic_since = now
			elif now - _shot_mimic_since > 10000:
				_shot_mimic_problems.append("pair leg: restore never completed")
				_mimic_finish()
		5:
			if _room.power_panel() == panel and _room.power_phase() >= 1:
				_room._power_phase = 2
				_room._power_t = 0.0
				_room._apply_power()
				_shot_mimic_stage = 6
				_shot_mimic_wait = 0
			elif now - _shot_mimic_since > 20000:
				_shot_mimic_problems.append("pair leg: the second visit never started its power-on")
				_mimic_finish()
		6:
			_shot_mimic_wait += 1
			if _shot_mimic_wait >= 5:
				var img2: Image = get_viewport().get_texture().get_image()
				var d: int = _mimic_max_diff(_shot_mimic_rest_img, img2, _mimic_art_screen_rect(panel))
				if d > 3:
					_shot_mimic_problems.append("pair restore leg: focus loss did not return the card to its Off face (max diff %d/255)" % d)
				_room._set_focused(null)
				_shot_mimic_phase = 4
				_shot_mimic_stage = 90
				_shot_mimic_since = now


## The mean colour of a pair On image through the overlay's
## own window: the fitted On cover-fit into the face's art
## rect (512 x (640 - strip)), centred - the same rule
## RoomView._build_power_overlay windows it with.
func _mimic_on_window_mean(on_img: Image) -> Color:
	var art: Vector2 = Vector2(512.0, 640.0 - float(CardFace.ART_STRIP_HEIGHT_PX))
	var ow: float = float(on_img.get_width())
	var oh: float = float(on_img.get_height())
	var cover: float = maxf(art.x / ow, art.y / oh)
	var win: Vector2 = art / cover
	var org: Vector2 = (Vector2(ow, oh) - win) * 0.5
	# The stats window is the face's top 396 rows; in the
	# overlay window's own space that is its top 396/548.
	win.y *= 396.0 / art.y
	var sum: Color = Color(0, 0, 0, 0)
	var n: int = 0
	var gy: int = 0
	while gy < 24:
		var gx: int = 0
		while gx < 24:
			var px: int = clampi(int(org.x + win.x * (float(gx) + 0.5) / 24.0), 0, on_img.get_width() - 1)
			var py: int = clampi(int(org.y + win.y * (float(gy) + 0.5) / 24.0), 0, on_img.get_height() - 1)
			sum += on_img.get_pixel(px, py)
			n += 1
			gx += 1
		gy += 1
	return sum / float(n)


## Leg 4's subject list: [name, panel, want_mode].
func _mimic_quick_subjects() -> Array:
	var out: Array = []
	var pair_fx: Dictionary = _shot_mimic_fixtures.get("Flicker Pair", {}) as Dictionary
	if not pair_fx.is_empty() and pair_fx.get("panel") != null:
		out.append(["Flicker Pair", pair_fx["panel"], 3])
	for pre: String in ["Flicker Flasher", "Flicker Anim", "Flicker Wart", "Flicker Warmed"]:
		var fx: Dictionary = _shot_mimic_fixtures.get(pre, {}) as Dictionary
		if not fx.is_empty() and fx.get("panel") != null:
			out.append([pre, fx["panel"], 2])
	if _shot_mimic_panel2 != null:
		out.append(["Cinder Peak (plain face)", _shot_mimic_panel2, 2])
	if _shot_mimic_title_panel != null:
		out.append(["title card", _shot_mimic_title_panel, 2])
	return out


## Leg 4's sub-driver: every remaining face class takes the
## same performance and settles on it.
func _drive_mimic_quick_leg(now: int) -> void:
	if _shot_mimic_stage == 90:
		# Entry: the wide legs may have run on page two -
		# flip home and re-resolve this leg's subjects on
		# page one before building the list.
		if _shot_mimic_on_page2:
			_room._bumper_page(-1)
			_shot_mimic_on_page2 = false
			_shot_mimic_stage = 91
		else:
			_mimic_resolve_panels()
			_shot_mimic_quick = _mimic_quick_subjects()
			_shot_mimic_quick_i = 0
			_shot_mimic_stage = 0
		_shot_mimic_since = now
		return
	if _shot_mimic_stage == 91:
		if not _room.page_slide_active() and _room.wall_ready:
			_mimic_resolve_panels()
			_shot_mimic_quick = _mimic_quick_subjects()
			_shot_mimic_quick_i = 0
			_shot_mimic_stage = 0
			_shot_mimic_since = now
		return
	if _shot_mimic_quick_i >= _shot_mimic_quick.size():
		_shot_mimic_phase = 5
		_shot_mimic_stage = 0
		_shot_mimic_since = now
		return
	var item: Array = _shot_mimic_quick[_shot_mimic_quick_i] as Array
	var label: String = str(item[0])
	var panel: ClickableQuad = item[1] as ClickableQuad
	var want_mode: int = int(item[2])
	match _shot_mimic_stage:
		0:
			_room._set_focused(panel)
			_shot_mimic_stage = 1
			_shot_mimic_since = now
		1:
			if _room.power_panel() == panel and _room.power_phase() == 2:
				if _room.power_mode() != want_mode:
					_shot_mimic_problems.append("uniformity leg: %s settled in mode %d, want %d" % [label, _room.power_mode(), want_mode])
				if _room.power_overlay_count() != 1:
					_shot_mimic_problems.append("uniformity leg: %s settled on %d overlay quads, want 1" % [label, _room.power_overlay_count()])
				_room._set_focused(null)
				_shot_mimic_stage = 2
				_shot_mimic_since = now
			elif now - _shot_mimic_since > 25000:
				_shot_mimic_problems.append("uniformity leg: %s never settled (phase %d)" % [label, _room.power_phase()])
				_mimic_finish()
		2:
			if _room.power_phase() == 0:
				_shot_mimic_quick_i += 1
				_shot_mimic_stage = 0
				_shot_mimic_since = now
			elif now - _shot_mimic_since > 10000:
				_shot_mimic_problems.append("uniformity leg: %s never restored" % label)
				_mimic_finish()


## The real boot's driver (PVLDS_MIMIC_REAL=1): the
## prototype's, carried into production - three real tables,
## parked stills at the envelope's named instants, a
## MIMIC_CROP line per subject for the harness's post-check.
## The clip frames are the prototype's judging artifact; the
## production suite keeps stills only (the post-check reads
## numbers, not movies).
func _drive_shot_mimic_real(now: int) -> void:
	if _shot_mimic_phase == 0:
		if _room == null or not _room.visible or not _room.wall_ready or _scanner == null:
			return
		if _shot_mimic_stage == 0:
			_room._handle_rail("filter:all")
			get_viewport().warp_mouse(Vector2(512, 764)) ## parked over the furniture: on the drum a corner park can sit on a top-band card, and hover would drive the centre away from the legs' focused fixture (the nav driver's lesson)
			_shot_mimic_stage = 1
			_shot_mimic_since = now
			return
		if _shot_mimic_stage == 1:
			var specs: Array = [["taxi", "Taxi"], ["goonies", "Goonies"], ["bride", "Bride"]]
			var by_key: Dictionary = {}
			for g: GameEntry in _scanner.games:
				for sp: Array in specs:
					if g.title.contains(str(sp[1])):
						by_key[str(sp[0])] = g
			_shot_mimic_subjects.clear()
			for sp2: Array in specs:
				if by_key.has(str(sp2[0])):
					_shot_mimic_subjects.append({"key": str(sp2[0]), "game": by_key[str(sp2[0])]})
			_shot_mimic_stage = 2
			_shot_mimic_since = now
			return
		var missing: bool = _shot_mimic_subjects.size() < 3
		for s: Dictionary in _shot_mimic_subjects:
			if not s.has("panel"):
				for p: ClickableQuad in _room._panels:
					if p.payload == (s["game"] as GameEntry).game_id:
						s["panel"] = p
			if not s.has("panel"):
				missing = true
		if missing:
			if not _scan_active and now - _shot_mimic_since > 20000:
				_shot_mimic_problems.append("real subjects missing from the wall (registered %d of 3)" % _shot_mimic_subjects.size())
				_mimic_finish()
			return
		_shot_mimic_phase = 1
		_shot_mimic_idx = 0
		_shot_mimic_stage = 0
		_shot_mimic_since = now
		return
	if _shot_mimic_phase != 1:
		return
	if now - _shot_mimic_since > 300000:
		_shot_mimic_problems.append("real driver timed out on subject %d stage %d" % [_shot_mimic_idx, _shot_mimic_stage])
		_mimic_finish()
		return
	var subj: Dictionary = _shot_mimic_subjects[_shot_mimic_idx] as Dictionary
	var panel: ClickableQuad = subj["panel"] as ClickableQuad
	var key: String = str(subj["key"])
	match _shot_mimic_stage:
		0:
			_room._set_focused(panel)
			_shot_mimic_stage = 1
			_shot_mimic_wait = 0
			_shot_mimic_since = now
		1:
			if _room.power_panel() == panel and _room.power_phase() >= 1:
				if _room.power_mode() != 2:
					_shot_mimic_problems.append("%s did not take the mimic grade (mode %d) - its stills would lie" % [key, _room.power_mode()])
					_mimic_finish()
					return
				_room._power_phase = 2
				_shot_mimic_stage = 2
				_shot_mimic_park = 0
				_shot_mimic_wait = 0
			elif now - _shot_mimic_since > 20000:
				_shot_mimic_problems.append("%s never started its power-on" % key)
				_mimic_finish()
		2:
			var stills: Array = [["rest", 0.0], ["sag", 0.34], ["mid", 0.44], ["settled", 1.05]]
			var pk: Array = stills[_shot_mimic_park] as Array
			_room._power_t = float(pk[1])
			_room._apply_power()
			_shot_mimic_wait += 1
			if _shot_mimic_wait >= 5:
				var img: Image = get_viewport().get_texture().get_image()
				img.save_png(_shot_mimic_prefix + "_" + key + "_" + str(pk[0]) + ".png")
				if str(pk[0]) == "settled":
					_mimic_print_crop(key, panel)
				_shot_mimic_park += 1
				_shot_mimic_wait = 0
				if _shot_mimic_park >= stills.size():
					_room._set_focused(null)
					_shot_mimic_stage = 3
					_shot_mimic_wait = 0
		3:
			_shot_mimic_wait += 1
			if _shot_mimic_wait >= 12:
				_shot_mimic_idx += 1
				_shot_mimic_stage = 0
				_shot_mimic_wait = 0
				_shot_mimic_since = now
				if _shot_mimic_idx >= _shot_mimic_subjects.size():
					_mimic_finish()


func _mimic_print_crop(key: String, panel: ClickableQuad) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var half: Vector2 = _room._panel_size * 0.5
	var pts: Array[Vector2] = []
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		pts.append(cam.unproject_position(panel.global_transform * Vector3(c.x, c.y, 0.0)))
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p: Vector2 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var pad: Vector2 = (mx - mn) * 0.10
	mn -= pad
	mx += pad
	var vp: Vector2 = get_viewport().get_visible_rect().size
	mn.x = clampf(mn.x, 0.0, vp.x)
	mn.y = clampf(mn.y, 0.0, vp.y)
	mx.x = clampf(mx.x, 0.0, vp.x)
	mx.y = clampf(mx.y, 0.0, vp.y)
	print("MIMIC_CROP %s %d %d %d %d" % [key, int(mn.x), int(mn.y), int(mx.x - mn.x), int(mx.y - mn.y)])
	# The art area's own projected corners (TL TR BR BL): the
	# post-check masks to this polygon - the bounding crop
	# above also catches the focus frame and the room around
	# the perspective-tilted card, which are not the face and
	# must not be graded by the reference.
	var art_bot: float = half.y * (1.0 - 2.0 * float(_room._panel_face_px.y - CardFace.ART_STRIP_HEIGHT_PX) / float(_room._panel_face_px.y))
	var poly: Array[Vector2] = []
	for c2: Vector2 in [Vector2(-half.x, half.y), Vector2(half.x, half.y), Vector2(half.x, art_bot), Vector2(-half.x, art_bot)]:
		poly.append(cam.unproject_position(panel.global_transform * Vector3(c2.x, c2.y, 0.0)))
	print("MIMIC_POLY %s %d %d %d %d %d %d %d %d" % [key,
		int(poly[0].x), int(poly[0].y), int(poly[1].x), int(poly[1].y),
		int(poly[2].x), int(poly[2].y), int(poly[3].x), int(poly[3].y)])


func _save_shot_png(path: String) -> Error:
	var img: Image = get_viewport().get_texture().get_image()
	return img.save_png(path)


## --pvlds-shot-slide P: the drum swing's QA hook (the bumper
## feel round, re-pointed at graduation). Boots the room,
## forces the ALL filter through the room's own rail handler
## (the harness library needs its stub pages for a flip to
## exist), lets the wall settle, then flips a page through
## the room's bumper path and captures P on the first frame
## the swing has travelled 60% of its arc - the shelf at full
## glide, mid-travel. Prints the verdict, quits.
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
			if _shot_slide_yaw0 < 0.0:
				_shot_slide_yaw0 = yaw
			if _shot_slide_yaw0 > 0.0 and yaw <= _shot_slide_yaw0 * 0.4:
				var path: String = _shot_slide_path
				_shot_slide_phase = -1
				var err: Error = _save_shot_png(path)
				print("PVLDS SLIDE SHOT: ", path, " err=", err, " yaw=", snappedf(yaw, 0.01))
				get_tree().quit(0 if err == OK else 1)
			elif not _room.page_slide_active():
				printerr("PVLDS SLIDE SHOT: FAIL - the swing ended before the capture frame (peak yaw %.2f)" % yaw)
				get_tree().quit(1)
			elif _shot_slide_frames > 3600:
				printerr("PVLDS SLIDE SHOT: FAIL - the swing never engaged")
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
		_desk.wovp_key_saved.connect(_on_desk_wovp_key_saved)
		_desk.wovp_test_requested.connect(_on_desk_wovp_test_requested)
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
## confined to its five buttons, the wall inert behind it -
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
				_setup_panel_expect(f == _room.setup_panel_scan_quad() or f == _room.setup_panel_download_quad() or f == _room.setup_panel_back_quad()
					or f == _room.setup_panel_wovp_paste_quad() or f == _room.setup_panel_wovp_test_quad(),
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
## Launch buttons, the rail) with the texture it wears as
## the panel's scan starts. (The graduation's status line is
## a Label3D, not a quad, and was never pickable or
## re-textured across this event, so it is not snapshotted.)
func _setup_panel_smoke_snapshot_wall() -> void:
	_setup_panel_smoke_wall_before.clear()
	_setup_panel_smoke_tex_before.clear()
	var quads: Array[ClickableQuad] = []
	quads.append_array(_room._panels)
	quads.append_array(_room._panel_launches)
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
	if _room.setup_panel_wovp_paste_quad() != null:
		quads.append(_room.setup_panel_wovp_paste_quad())
	if _room.setup_panel_wovp_test_quad() != null:
		quads.append(_room.setup_panel_wovp_test_quad())
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
	_setup_panel_expect(_room.setup_panel_wovp_paste_quad() != null, "XR setup: the panel has PASTE KEY (the WoVP row)")
	_setup_panel_expect(_room.setup_panel_wovp_test_quad() != null, "XR setup: the panel has TEST KEY (the WoVP row)")
	_setup_panel_expect(_room.setup_panel_wing_quad() != null, "XR setup: the panel has WING (the display dials row, the GRAD FIX round)")
	_setup_panel_expect(_room.setup_panel_stars_quad() != null, "XR setup: the panel has STARS (the display dials row, the GRAD FIX round)")
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
		and _room.setup_panel_wovp_paste_quad().pick_enabled
		and _room.setup_panel_wovp_test_quad().pick_enabled
		and _room.setup_panel_wing_quad().pick_enabled
		and _room.setup_panel_stars_quad().pick_enabled
		and _room.setup_panel_back_quad().pick_enabled,
		"XR setup: the panel's own buttons are live")
	_setup_panel_expect(_room._focusables.size() == 7
		and _room._focusables.has(_room.setup_panel_scan_quad())
		and _room._focusables.has(_room.setup_panel_download_quad())
		and _room._focusables.has(_room.setup_panel_wovp_paste_quad())
		and _room._focusables.has(_room.setup_panel_wovp_test_quad())
		and _room._focusables.has(_room.setup_panel_wing_quad())
		and _room._focusables.has(_room.setup_panel_stars_quad())
		and _room._focusables.has(_room.setup_panel_back_quad()),
		"XR setup: focus navigation is confined to the panel's seven buttons")
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


# --------------------------------------------------- grad smoke

## --pvlds-smoke-grad: the graduation contract (2026-10-29).
## The dome is no longer a prototype: this driver boots the
## REAL exported launcher against a library of ~107 tables
## whose fixture database is copied from the real VPS database
## (tableFile imgUrl fields included - the make_grad_fixtures
## cast: a bulk spread of author-shot games, the Bride pair
## table with its real .directb2s, two no-shot tables on
## backglass fallback, two title-card tables, one shot the
## stub 404s, and the database's longest title padded onto
## the bottom band). Shots arrive over HTTP from the harness
## stub (PVLDS_SHOT_BASE), exactly as production fetches them
## from the real host. Legs:
##   - the library lands whole and the drum boots mid-shelf;
##   - shot ranking: a landed shot IS the card's face (the
##     NC PVLDS_GRAD_NC=oldrank restores the pre-graduation
##     ranking and this leg must fail by name);
##   - the fallback chain under the shot: backglass face for
##     the no-shot tables, title cards for the artless, the
##     404 shot recorded negative and fallen through for good;
##   - nameplate: the plate stands under sampled titles
##     (NC PVLDS_GRAD_NC=noplate hides the plates and the
##     leg must fail by name);
##   - label state + label ink (the GRAD FIX round): the
##     state audit reads every filled panel's plate/label
##     visibility against the face its fill recorded, and
##     the ink legs prove the name is actually DRAWN - the
##     graduation census measured geometry only, and the
##     field fault (names that come and go) was the card's
##     own transparent face sorting after its nameplate in
##     the draw and painting over it. The card stack now
##     declares its render order; NC PVLDS_GRAD_NC=
##     nofaceorder undeclares it and the ink legs must fail
##     by name;
##   - the sweep census: EVERY shelf index becomes the
##     centre; at every centre, every visible label and plate
##     is measured - nothing under the floor, no label
##     touching the rail or the status plate, the popped
##     centre's label clear of every neighbour's art, and
##     the wing (when it stands) clear of every label;
##   - background world-lock: the three layers are not the
##     drum's children and their transforms do not move
##     while the drum swings the whole shelf (NC
##     PVLDS_BG_NC=drum parents them to the drum and the
##     leg must fail by name);
##   - wing occlusion: at the tournament table's focus the
##     wing stands with the live board and eats no label
##     (NC PVLDS_GRAD_NC=wing shoves the wing onto the card
##     and the leg must fail by name);
##   - power: the pair table performs mode 3 on focus and
##     settles back onto its author shot, pixel-compared;
##     a no-shot table performs mode 2 on its backglass.
## Grabs (PVLDS_GRAB_DIR): grad_boot.png (mid-shelf at
## boot), grad_swing.png (mid-swing), grad_wing.png (the
## tournament focus), grad_fallback_power.png (a fallback
## table mid-performance).
var _smoke_grad: bool = false ## --pvlds-smoke-grad
var _grad_phase: int = 0
var _grad_wait: int = 0
var _grad_failures: int = 0
var _grad_manifest: Dictionary = {}
var _grad_sweep_i: int = -1 ## the centre the sweep is measuring (-1 = not started)
var _grad_ink_stage: int = 0
var _grad_swing_stage: int = 0
var _grad_swing_samples: Array = [] ## [msec since journey start, target deviation in degrees]
var _grad_swing_cmds: Array = [] ## msec offsets at which step commands were issued
var _grad_swing_cmd_i: int = 0
var _grad_swing_last_cmd: int = 0
var _grad_swing_t0: int = 0
var _grad_ink_tries: int = 0 ## stability-wait cycles spent on the current ink target
var _grad_ink_plate_checked: int = 0 ## targets whose plate leg actually ran (a performing panel is exempt)
var _grad_ink_targets: Array = []
var _grad_ink_img_a: Image = null
var _grad_ink_img_b: Image = null
var _grad_ink_label: Label3D = null
var _grad_ink_plate: MeshInstance3D = null
var _grad_sweep_settle: int = 0
var _grad_labels_measured: int = 0
var _grad_long_min_bottom: float = INF
var _grad_bg_before: Array = []
var _grad_power_stage: int = 0
var _grad_power_wait: int = 0
var _grad_power_since: int = 0 ## msec at the current power stage's entry (waits are wall-clock: harness frame rates vary 20x)
var _grad_swing_grabbed: bool = false
var _grad_boot_centre: int = -1 ## the centre the boot itself chose, read before any driver input
var _grad_visit_i: int = -1 ## the fallback-visit cursor (-1 = not started)
var _grad_visit_settle: int = 0
## Census violation counters (the sweep counts; the named
## verdicts print once, with the first example of each kind).
var _grad_viol: Dictionary = {}
var _grad_viol_first: Dictionary = {}
var _grad_rail_max_depth: float = 0.0 ## the deepest label-under-rail intrusion in px (the census reports it; geometry is judged on it)
var _grad_rail_worst: String = ""
var _grad_fringe_rail: int = 0 ## rail intrusions beyond the browsing zone (reported in the census line, not convicted - see the zone note in _grad_measure_centre)


func _grad_count(kind: String, example: String) -> void:
	_grad_viol[kind] = int(_grad_viol.get(kind, 0)) + 1
	if not _grad_viol_first.has(kind):
		_grad_viol_first[kind] = example


func _grad_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - grad smoke: ", label)
	else:
		_grad_failures += 1
		printerr("  FAIL - grad smoke: ", label)


func _grad_fail(label: String) -> void:
	_grad_expect(false, label)


func _grad_game(game_id: String) -> GameEntry:
	if _room == null or _room._scanner == null:
		return null
	for g: GameEntry in _room._scanner.games:
		if g.game_id == game_id:
			return g
	return null


func _grad_panel_index(game_id: String) -> int:
	if _room == null:
		return -1
	for i: int in range(_room._panels.size()):
		if _room._panels[i] != null and _room._panels[i].payload == game_id:
			return i
	return -1


func _grad_manifest_games() -> Array:
	var out: Array = []
	var gs: Variant = _grad_manifest.get("games", [])
	if gs is Array:
		out = gs
	return out


## The fallback cast, visited one by one: a card's face is
## only real once the drum's window has filled it, so each
## special game is centred, its fill awaited, and its chain
## read there - the state a player actually meets.
func _grad_visit_games() -> Array:
	var out: Array = []
	for entry: Variant in _grad_manifest_games():
		if not (entry is Dictionary):
			continue
		var kind: String = str((entry as Dictionary).get("kind", ""))
		if kind == "b2s" or kind == "titlecard" or kind == "orphan" or kind == "missing":
			out.append(entry)
	return out


func _grad_visit_step() -> void:
	var visits: Array = _grad_visit_games()
	if _grad_visit_i < 0:
		_grad_visit_i = 0
		_grad_visit_settle = 0
		if visits.is_empty():
			_grad_phase = 2
			return
		_grad_focus_visit(visits[0])
		return
	if _grad_visit_i >= visits.size():
		_grad_phase = 2
		return
	var e: Dictionary = visits[_grad_visit_i]
	var g: GameEntry = _grad_visit_game(e)
	_grad_visit_settle += 1
	# Filled means the seated PANEL wears a real face: a
	# title-card game's face is a room-rendered texture,
	# never a file face_path() could name.
	var filled: bool = false
	if g != null:
		var pidx: int = _grad_panel_index(g.game_id)
		if pidx >= 0:
			var ptex: Texture2D = _room._panels[pidx].current_texture()
			filled = ptex != null and ptex != _room._placeholder_tex
	if _grad_visit_settle > 500:
		_grad_fail("fallback: %s's face never filled" % str(e.get("name", "?")))
		filled = true
	if filled and not _room.page_slide_active() and _grad_visit_settle > 10:
		_grad_leg_fallback_visit(e, g)
		_grad_visit_i += 1
		_grad_visit_settle = 0
		if _grad_visit_i < visits.size():
			_grad_focus_visit(visits[_grad_visit_i])
		else:
			_grad_phase = 2


func _grad_visit_game(e: Dictionary) -> GameEntry:
	var gid: String = str(e.get("id", ""))
	if gid != "":
		return _grad_game(gid)
	for cand: GameEntry in _room._scanner.games:
		if not cand.builds.is_empty() and str(cand.builds[0].file_name).begins_with(str(e.get("stem", ""))):
			return cand
	return null


func _grad_focus_visit(e: Dictionary) -> void:
	var g: GameEntry = _grad_visit_game(e)
	if g == null:
		return
	var idx: int = _grad_panel_index(g.game_id)
	if idx >= 0:
		_room._set_focused(_room._panels[idx])


func _grad_leg_fallback_visit(e: Dictionary, g: GameEntry) -> void:
	var kind: String = str(e.get("kind", ""))
	if g == null:
		_grad_fail("faces: fixture game '%s' is in the library" % str(e.get("name", "?")))
		return
	match kind:
		"b2s":
			_grad_expect(g.shot_url == "" and not g.has_shot_face(),
				"fallback: %s has no author shot" % g.title)
			_grad_expect(g.backglass_face_path() != "" and g.face_path() == g.backglass_face_path(),
				"fallback: %s's face is its backglass" % g.title)
		"titlecard", "orphan":
			_grad_expect(not g.has_shot_face() and g.backglass_face_path() == "",
				"fallback: %s has neither shot nor backglass" % g.title)
			var pidx2: int = _grad_panel_index(g.game_id)
			var ptex2: Texture2D = _room._panels[pidx2].current_texture() if pidx2 >= 0 else null
			_grad_expect(ptex2 != null and ptex2 != _room._placeholder_tex,
				"fallback: %s still wears a generated title card" % g.title)
		"missing":
			var url: String = str(e.get("shot_url", ""))
			_grad_expect(not g.has_shot_face(),
				"fallback: the 404 shot does not dress %s" % g.title)
			_grad_expect(ArtProvider.is_negative_outcome(ArtProvider.shot_outcome(url)),
				"fallback: the 404 shot is a recorded negative for %s" % g.title)
			_grad_expect(g.face_path() != ArtProvider.shot_cache_path_for(url),
				"fallback: %s falls through the chain for good" % g.title)


func _grad_save_grab(name: String) -> void:
	var dir: String = OS.get_environment("PVLDS_GRAB_DIR")
	if dir == "":
		return
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(dir.path_join(name))
	print("GRAD GRAB: ", name, " err=", err, " size=", img.get_size())


## A world AABB's screen rect through the desk camera.
func _grad_aabb_screen_rect(aabb: AABB, cam: Camera3D) -> Rect2:
	var c: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				c.append(aabb.position + Vector3(
					(aabb.size.x if sx > 0.0 else 0.0),
					(aabb.size.y if sy > 0.0 else 0.0),
					(aabb.size.z if sz > 0.0 else 0.0)))
	var rect: Rect2 = Rect2(cam.unproject_position(c[0]), Vector2.ZERO)
	for i: int in range(1, c.size()):
		rect = rect.expand(cam.unproject_position(c[i]))
	return rect


## A panel's label screen rect from its LOCAL aabb corners
## through its own transform - the tight projected quad.
## (The world AABB of a tilted label is fat in two axes;
## projecting that box again would measure the box, not
## the label - the first grad run's census convicted its
## own ruler that way.)
func _grad_label_screen_rect(i: int, cam: Camera3D) -> Rect2:
	var label: Label3D = _room._panel_labels[i] if i < _room._panel_labels.size() else null
	if label == null:
		return Rect2()
	var la: AABB = label.get_aabb()
	var gt: Transform3D = label.global_transform
	var corners: Array[Vector3] = [
		la.position, la.position + Vector3(la.size.x, 0.0, 0.0),
		la.position + Vector3(0.0, la.size.y, 0.0), la.position + la.size]
	var rect: Rect2 = Rect2(cam.unproject_position(gt * corners[0]), Vector2.ZERO)
	for ci: int in range(1, corners.size()):
		rect = rect.expand(cam.unproject_position(gt * corners[ci]))
	return rect


## A quad's four screen points, corners in order, from its
## transform and half-size.
func _grad_quad_screen_points(gt: Transform3D, half: Vector2, cam: Camera3D) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		pts.append(cam.unproject_position(gt * Vector3(c.x, c.y, 0.0)))
	return pts


## Convex-polygon overlap by the separating-axis test: the
## census's exact measure (projected AABBs of slanted quads
## intersect in their slack corners where the quads
## themselves never meet - the census convicted its ruler
## twice that way before this).
func _grad_polys_overlap(a: Array[Vector2], b: Array[Vector2]) -> bool:
	for poly: Array in [a, b]:
		for i: int in range(poly.size()):
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % poly.size()]
			var axis: Vector2 = Vector2(-(p2.y - p1.y), p2.x - p1.x).normalized()
			var amin: float = INF
			var amax: float = -INF
			var bmin: float = INF
			var bmax: float = -INF
			for p: Vector2 in a:
				var d: float = p.dot(axis)
				amin = minf(amin, d)
				amax = maxf(amax, d)
			for p: Vector2 in b:
				var d2: float = p.dot(axis)
				bmin = minf(bmin, d2)
				bmax = maxf(bmax, d2)
			if amax < bmin or bmax < amin:
				return false
	return true


## The intersection area of two convex screen polygons
## (Sutherland-Hodgman: clip a against b's edges).
func _grad_poly_intersect_area(a: Array[Vector2], b: Array[Vector2]) -> float:
	var poly: Array[Vector2] = a.duplicate()
	var bsign: float = 0.0
	for e: int in range(b.size()):
		var bp: Vector2 = b[e]
		var bq: Vector2 = b[(e + 1) % b.size()]
		bsign += bp.x * bq.y - bq.x * bp.y
	var sgn: float = 1.0 if bsign >= 0.0 else -1.0
	for e: int in range(b.size()):
		if poly.is_empty():
			return 0.0
		var p1: Vector2 = b[e]
		var p2: Vector2 = b[(e + 1) % b.size()]
		var edge: Vector2 = p2 - p1
		var out: Array[Vector2] = []
		for i: int in range(poly.size()):
			var cur: Vector2 = poly[i]
			var prev: Vector2 = poly[(i + poly.size() - 1) % poly.size()]
			var cur_in: bool = edge.cross(cur - p1) * sgn >= 0.0
			var prev_in: bool = edge.cross(prev - p1) * sgn >= 0.0
			if cur_in:
				if not prev_in:
					var d: Vector2 = cur - prev
					var denom: float = edge.cross(d)
					if absf(denom) > 0.00001:
						var t: float = edge.cross(p1 - prev) / denom
						out.append(prev + d * t)
				out.append(cur)
			elif prev_in:
				var d: Vector2 = cur - prev
				var denom: float = edge.cross(d)
				if absf(denom) > 0.00001:
					var t: float = edge.cross(p1 - prev) / denom
					out.append(prev + d * t)
		poly = out
	var area: float = 0.0
	for i: int in range(poly.size()):
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
	return absf(area) * 0.5


func _drive_grad_smoke() -> void:
	match _grad_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				Input.warp_mouse(Vector2(512.0, 764.0)) ## parked: hover would drive the centre (see the nav driver)
				_grad_boot_centre = _room.centre_index() ## before the filter press re-centres the drum
				_room._handle_rail("filter:all")
				var mpath: String = OS.get_environment("PVLDS_GRAD_MANIFEST")
				var f: FileAccess = FileAccess.open(mpath, FileAccess.READ)
				if f != null:
					var parsed: Variant = JSON.parse_string(f.get_as_text())
					if parsed is Dictionary:
						_grad_manifest = parsed
				_grad_expect(not _grad_manifest.is_empty(),
					"fixtures: the graduation manifest loads")
				_grad_phase = 1
				_grad_wait = 0
			else:
				_grad_wait += 1
				if _grad_wait > 3600:
					_grad_fail("the room never came up")
					_finish_grad_smoke()
		1:
			# Settled = the fetcher's own queue has walked:
			# it starts before the room adopts (Main's scan
			# landing order), so an idle fetcher after a
			# margin IS the drained state. (An earlier draft
			# polled for every manifest URL to resolve -
			# but a URL the matcher never assigned to a
			# library game is never queued, and the poll
			# outwaited the run: the faces legs below are
			# where unclaimed shots are named, per game.)
			_grad_wait += 1
			var drained: bool = _shot_fetcher != null and not _shot_fetcher.is_fetching()
			if _grad_wait > 3600 and not drained:
				_grad_fail("shots: the fetch queue never drained")
				_grad_leg_library()
				_grad_leg_faces()
				_grad_leg_nameplate_sample()
				_grad_leg_background_static()
				_grad_phase = 7
				_grad_wait = 0
			elif drained and _grad_wait > 240:
				_grad_leg_library()
				_grad_leg_faces()
				_grad_leg_nameplate_sample()
				_grad_audit_labels("drained")
				_grad_leg_background_static()
				_grad_save_grab("grad_boot.png")
				_grad_phase = 7
				_grad_wait = 0
		7:
			_grad_visit_step()
		2:
			_grad_sweep_step()
		3:
			_grad_leg_background_lock()
			_grad_phase = 4
			_grad_wait = 0
			_grad_power_stage = 0
		4:
			_grad_tournament_step()
		5:
			_grad_power_step()
		6:
			_finish_grad_smoke()
		10:
			_grad_ink_step()
		11:
			_grad_swing_step()


func _grad_leg_library() -> void:
	var want: int = _grad_manifest_games().size()
	var games: Array = []
	if _room != null and _room._scanner != null:
		games = _room._scanner.games
	_grad_expect(games.size() == want,
		"library: the whole fixture library lands (%d of %d games)" % [games.size(), want])
	_grad_expect(_room._panels.size() == games.size(),
		"library: one drum panel per game (%d panels)" % _room._panels.size())
	var n: int = games.size()
	_grad_expect(_room.boot_visible_count > 0
		and absi(_room.boot_centre_index - (_room.boot_visible_count - 1) / 2) <= 1,
		"library: the drum boots mid-shelf (centre %d of its %d-game boot view)"
		% [_room.boot_centre_index, _room.boot_visible_count])
	# The long title stands on the bottom band, as placed.
	var long_idx: int = _grad_panel_index(str(_grad_manifest.get("long_id", "")))
	if long_idx >= 0:
		var coord: Vector2i = _room._grid_coord(long_idx)
		_grad_expect(coord.y == 2,
			"fixtures: the longest title stands on the bottom band (shelf %d, row %d)" % [long_idx, coord.y])
	else:
		_grad_fail("fixtures: the longest title is on the shelf")


func _grad_leg_faces() -> void:
	# Every shot game in the cast, not a sample: a fixture
	# file that claimed the wrong build (or none) is named
	# here, counted like the census.
	var shot_total: int = 0
	var shot_ok: int = 0
	var shot_bad: Array[String] = []
	for entry: Variant in _grad_manifest_games():
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		var kind: String = str(e.get("kind", ""))
		var gid: String = str(e.get("id", ""))
		var g: GameEntry = _grad_game(gid) if gid != "" else null
		if kind == "orphan":
			for cand: GameEntry in _room._scanner.games:
				if not cand.builds.is_empty() and str(cand.builds[0].file_name).begins_with(str(e.get("stem", ""))):
					g = cand
					break
		if g == null:
			_grad_fail("faces: fixture game '%s' is in the library" % str(e.get("name", "?")))
			continue
		match kind:
			"shot", "long":
				shot_total += 1
				if g.has_shot_face() and g.face_path() == ArtProvider.shot_cache_path_for(str(e.get("shot_url", ""))):
					shot_ok += 1
				elif shot_bad.size() < 5:
					shot_bad.append(g.title)
			"pair":
				_grad_expect(g.has_shot_face(),
					"shot ranking: the pair table wears its author shot")
				_grad_expect(g.backglass_face_path() != "",
					"power: the pair table's backglass stands under its shot")
				_grad_expect(g.pair_on_art() != "",
					"power: the pair table still owns its Off/On pair under the shot")
			_:
				pass ## the fallback cast is read on its visits (phase 7)
	if shot_bad.is_empty():
		_grad_expect(true, "shot ranking: every author shot is its game's face (%d games)" % shot_total)
	else:
		_grad_expect(false, "shot ranking: every author shot is its game's face (%d of %d; missing: %s)"
			% [shot_ok, shot_total, ", ".join(shot_bad)])


func _grad_leg_nameplate_sample() -> void:
	# Sampled seated panels: the plate stands under the
	# title and carries it whole (the NC hides the plates).
	var cam: Camera3D = _room._active_camera()
	var checked: int = 0
	for i: int in range(_room._panels.size()):
		if checked >= 8:
			break
		var panel: ClickableQuad = _room._panels[i]
		if panel == null or not panel.visible:
			continue
		var plate: MeshInstance3D = _room._panel_plates[i] if i < _room._panel_plates.size() else null
		var label: Label3D = _room._panel_labels[i] if i < _room._panel_labels.size() else null
		if plate == null or label == null or not label.visible:
			continue
		checked += 1
		_grad_expect(plate.visible,
			"nameplate: panel %d's plate stands under its title" % i)
		if plate.visible and plate.mesh is QuadMesh:
			var qm: QuadMesh = plate.mesh as QuadMesh
			var pr: Rect2 = Rect2(Vector2(plate.position.x, plate.position.y) - qm.size * 0.5, qm.size)
			var la: AABB = label.get_aabb()
			var lr: Rect2 = Rect2(Vector2(label.position.x, label.position.y) + Vector2(la.position.x, la.position.y),
				Vector2(la.size.x, la.size.y))
			_grad_expect(pr.encloses(lr) or pr.intersects(lr),
				"nameplate: panel %d's plate carries its title block" % i)
	_grad_expect(checked >= 4, "nameplate: a sample of plates was readable (%d)" % checked)


## Label-state audit (the GRAD FIX round's diagnostic, kept
## as a standing leg): every filled panel's nameplate state
## must agree with the face its own fill recorded - an art
## face (a non-empty art segment in the face key) stands its
## plate + label up; a generated title card (empty segment)
## keeps both down, because the card carries its own title.
## The graduation census measured only labels that were
## visible; a label wrongly hidden was invisible to it -
## this audit reads the state itself, at several points in
## the run, so a divergence is named with its game and key.
func _grad_audit_labels(tag: String) -> void:
	var checked: int = 0
	for i: int in range(_room._panels.size()):
		if i >= _room._visible_games.size():
			break
		var game: GameEntry = _room._visible_games[i]
		var fkey: String = str(_room._panel_face_key.get(game.game_id, ""))
		if fkey == "":
			continue
		var parts: PackedStringArray = fkey.split("|")
		var art_seg: String = parts[1] if parts.size() > 1 else ""
		var want: bool = art_seg != ""
		var label: Label3D = _room._panel_labels[i] if i < _room._panel_labels.size() else null
		var plate: MeshInstance3D = _room._panel_plates[i] if i < _room._panel_plates.size() else null
		if label == null or plate == null:
			continue
		checked += 1
		if label.visible != want or plate.visible != want:
			_grad_expect(false,
				"label state (%s): panel %d (%s) wears face key '%s' but label=%s plate=%s (want both %s)"
				% [tag, i, game.title, fkey, str(label.visible), str(plate.visible), str(want)])
		if want:
			if label.text != game.title:
				_grad_expect(false,
					"label state (%s): panel %d's label text '%s' != title '%s'"
					% [tag, i, label.text, game.title])
			var aabb: AABB = label.get_aabb()
			if aabb.size.y <= 0.0:
				_grad_expect(false,
					"label state (%s): panel %d's label has no height (%s)"
					% [tag, i, game.title])
	print("GRAD LABEL AUDIT (%s): %d panels checked" % [tag, checked])


func _grad_leg_background_static() -> void:
	var layers: Array = _room.background_layers()
	# Four layers since the GRAD FIX round: the near star
	# shell joined the stack (starfield far, starfield near,
	# wireframe, ring).
	_grad_expect(layers.size() == 4,
		"background world-lock: the stack stands (starfield, starfield near, wireframe, ring - %d layers)" % layers.size())
	var drum: Node3D = _room.drum_node()
	_grad_bg_before.clear()
	for layer: Variant in layers:
		var node: Node3D = layer as Node3D
		_grad_expect(node != null and node.get_parent() != drum,
			"background world-lock: a layer is not the drum's child")
		if node != null:
			_grad_bg_before.append(node.global_transform)
	# The starfield dial (the GRAD FIX round): layered stands
	# both shells, flat the far one alone, off neither - and
	# the drum's parentage never moves under any setting.
	if layers.size() == 4:
		var far_shell: Node3D = layers[0] as Node3D
		var near_shell: Node3D = layers[1] as Node3D
		_room.set_starfield_mode("flat")
		_grad_expect(far_shell.visible and not near_shell.visible,
			"starfield dial: flat stands the far shell alone")
		_room.set_starfield_mode("off")
		_grad_expect(not far_shell.visible and not near_shell.visible,
			"starfield dial: off stands no stars")
		_room.set_starfield_mode("layered")
		_grad_expect(far_shell.visible and near_shell.visible,
			"starfield dial: layered stands both shells (the shipped default)")
		_grad_expect(_room.starfield_mode() == "layered",
			"starfield dial: the room reports the standing mode")


func _grad_leg_background_lock() -> void:
	var layers: Array = _room.background_layers()
	var still: bool = layers.size() == _grad_bg_before.size()
	if still:
		for i: int in range(layers.size()):
			var node: Node3D = layers[i] as Node3D
			var before_t: Transform3D = _grad_bg_before[i]
			if node == null or not node.global_transform.origin.is_equal_approx(before_t.origin):
				still = false
	_grad_expect(still,
		"background world-lock: no layer moved while the drum swept the shelf")


## The sweep: centre every shelf index in turn; at each
## settled centre, measure the visible labels.
func _grad_sweep_step() -> void:
	var n: int = _room._panels.size()
	if _grad_sweep_i < 0:
		_grad_sweep_i = 0
		_room._set_focused(_room._panels[0])
		_grad_sweep_settle = 0
		return
	if _room.page_slide_active():
		_grad_sweep_settle = 0
		# A mid-swing grab on a long early swing.
		if not _grad_swing_grabbed and _grad_sweep_i > 2 and absf(_room.page_slide_yaw_deg()) > 2.0:
			_grad_save_grab("grad_swing.png")
			_grad_swing_grabbed = true
		return
	_grad_sweep_settle += 1
	if _grad_sweep_settle < 3:
		return
	if _room.centre_index() == _grad_sweep_i:
		_grad_measure_centre(_grad_sweep_i)
	_grad_sweep_i += 1
	_grad_sweep_settle = 0
	if _grad_sweep_i >= n:
		print("GRAD CENSUS: %d centres, %d labels measured, long-title label bottom %.4f m, rail intrusion max %.1f px (%s), fringe rail intrusions beyond the browsing zone %d"
			% [n, _grad_labels_measured, _grad_long_min_bottom, _grad_rail_max_depth, _grad_rail_worst, _grad_fringe_rail])
		_grad_expect(_grad_labels_measured > n,
			"census: labels were measured across the sweep (%d)" % _grad_labels_measured)
		_grad_audit_labels("post-sweep")
		_grad_census_verdicts()
		_grad_phase = 10
		_grad_ink_stage = 0
		_grad_wait = 0
	else:
		_room._set_focused(_room._panels[_grad_sweep_i])


## The ink legs (the GRAD FIX round, kept standing): the
## graduation census measured label GEOMETRY, and the field
## fault - names that come and go - lived entirely in the
## ink: the card's own transparent face could sort after its
## nameplate plate and label in the transparent pass and
## paint over both, leaving state, alpha and geometry all
## correct and the name simply not drawn. For a spread of
## art-faced panels across the shelf: centre the panel, let
## the room go quiet, take the frame; hide the label, take
## it again (the label's ink is the diff); hide the plate
## too, take a third (the plate's presence is the mean
## darkening it lends the label's rect). Both must register,
## per panel, or the leg fails by name.
func _grad_ink_step() -> void:
	_grad_wait += 1
	match _grad_ink_stage:
		0:
			_grad_ink_targets.clear()
			var n: int = _room._panels.size()
			for k: int in range(8):
				var i: int = int(round(float(k) * float(maxi(n - 1, 0)) / 7.0))
				if i < _room._visible_games.size():
					var g: GameEntry = _room._visible_games[i]
					var fk: String = str(_room._panel_face_key.get(g.game_id, ""))
					if fk.split("|").size() > 1 and fk.split("|")[1] != "":
						_grad_ink_targets.append(i)
			_grad_expect(not _grad_ink_targets.is_empty(),
				"label ink: art-faced panels exist to probe")
			_grad_ink_stage = 1
			_grad_wait = 0
		1:
			if _grad_ink_targets.is_empty():
				_grad_expect(_grad_ink_plate_checked >= 5,
					"plate ink: at least five panels stood plate-checked (%d did)" % _grad_ink_plate_checked)
				_grad_phase = 11
				_grad_swing_stage = 0
				_grad_wait = 0
				return
			var i: int = int(_grad_ink_targets[0])
			_room._set_focused(_room._panels[i])
			_grad_ink_tries = 0
			_grad_ink_stage = 2
			_grad_wait = 0
		2:
			# Stability is judged directly, not by proxy: two
			# frames a few ticks apart must agree inside the
			# label's rect before any diff is trusted (a power
			# performance settling, a wing texture landing -
			# whatever moves, the rect says so).
			if not _room.page_slide_active() and _grad_wait > 10:
				var i: int = int(_grad_ink_targets[0])
				_grad_ink_label = _room._panel_labels[i]
				_grad_ink_plate = _room._panel_plates[i]
				_grad_ink_img_a = get_viewport().get_texture().get_image()
				_grad_ink_stage = 25
				_grad_wait = 0
			elif _grad_wait > 3600:
				_grad_fail("label ink: the room never went quiet")
				_grad_phase = 3
		25:
			if _grad_wait > 4:
				_grad_ink_tries += 1
				if _grad_ink_tries > 900:
					_grad_fail("label ink: the frame never settled")
					_grad_ink_label.visible = true
					_grad_ink_plate.visible = true
					_grad_phase = 3
					return
				var img_a2: Image = get_viewport().get_texture().get_image()
				var i: int = int(_grad_ink_targets[0])
				var cam: Camera3D = _room._active_camera()
				var rect: Rect2 = _grad_label_screen_rect(i, cam).intersection(
					Rect2(Vector2.ZERO, Vector2(img_a2.get_size())))
				var changed: int = 0
				for y: int in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
					for x: int in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
						var pa: Color = _grad_ink_img_a.get_pixel(x, y)
						var pb: Color = img_a2.get_pixel(x, y)
						if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) > 0.24:
							changed += 1
				_grad_ink_img_a = img_a2
				if changed <= 5:
					_grad_ink_label.visible = false
					_grad_ink_stage = 3
				_grad_wait = 0
		3:
			if _grad_wait > 3:
				_grad_ink_img_b = get_viewport().get_texture().get_image()
				_grad_ink_plate.visible = false
				_grad_ink_stage = 4
				_grad_wait = 0
		4:
			if _grad_wait > 3:
				var img_c: Image = get_viewport().get_texture().get_image()
				var i: int = int(_grad_ink_targets[0])
				var cam: Camera3D = _room._active_camera()
				var rect: Rect2 = _grad_label_screen_rect(i, cam).intersection(
					Rect2(Vector2.ZERO, Vector2(img_c.get_size())))
				var label_px: int = 0
				var sum_b: float = 0.0
				var sum_c: float = 0.0
				var npix: int = 0
				var x0: int = int(rect.position.x)
				var y0: int = int(rect.position.y)
				var x1: int = int(rect.position.x + rect.size.x)
				var y1: int = int(rect.position.y + rect.size.y)
				for y: int in range(y0, y1):
					for x: int in range(x0, x1):
						var pa: Color = _grad_ink_img_a.get_pixel(x, y)
						var pb: Color = _grad_ink_img_b.get_pixel(x, y)
						var pc: Color = img_c.get_pixel(x, y)
						if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) > 0.24:
							label_px += 1
						sum_b += (pb.r + pb.g + pb.b) / 3.0
						sum_c += (pc.r + pc.g + pc.b) / 3.0
						npix += 1
				var plate_lift: float = (sum_c - sum_b) / float(maxi(npix, 1))
				var g: GameEntry = _room._visible_games[i]
				printerr("GRAD INK: panel %d (%s) label px %d plate lift %.4f over %d px"
					% [i, g.title, label_px, plate_lift, npix])
				_grad_expect(label_px > 30,
					"label ink: panel %d (%s) renders its title (%d px of label ink)" % [i, g.title, label_px])
				# A panel mid-performance is exempt from the
				# plate leg: the settled power overlay owns the
				# face (a pair's On image stands in for it whole),
				# plate included, by design - the label above it
				# is still judged. The coverage leg in stage 1
				# keeps the exemption from swallowing the census.
				if _room.power_panel() == _room._panels[i]:
					printerr("GRAD INK: panel %d (%s) is performing - plate leg exempt" % [i, g.title])
				else:
					_grad_ink_plate_checked += 1
					_grad_expect(plate_lift > 0.01,
						"plate ink: panel %d (%s) stands on its nameplate (lift %.4f when the plate hides)" % [i, g.title, plate_lift])
				_grad_ink_label.visible = true
				_grad_ink_plate.visible = true
				_grad_ink_img_a = null
				_grad_ink_img_b = null
				_grad_ink_targets.pop_front()
				_grad_ink_stage = 1
				_grad_wait = 0


## The swing-glide legs (the GRAD FIX round): the drum's
## angle, sampled densely across two representative journeys -
## a held-scroll staircase (one column per 240 ms, the room's
## own hold cadence) and one long single swing (15 columns).
## The old per-step cubic ease-out settled between held steps
## and lunged at every restart: the ratchet. The legs judge
## the replacement spring on the sampled path itself, at the
## harness's own sampling rate: within every leg the approach
## is monotone (the deviation from the standing target never
## grows); mid-journey the deviation never reads zero (the
## old curve sat dead between held steps - its signature at
## any sampling rate); and arrivals land inside the old
## duration law's envelope, exactly on target.
func _grad_swing_step() -> void:
	match _grad_swing_stage:
		0:
			_room._set_focused(_room._panels[6])
			_grad_swing_stage = 1
			_grad_wait = 0
		1:
			_grad_wait += 1
			if not _room.page_slide_active() and _grad_wait > 20:
				_grad_swing_samples.clear()
				_grad_swing_cmds.clear()
				_grad_swing_cmd_i = 0
				_grad_swing_last_cmd = -240
				_grad_swing_t0 = Time.get_ticks_msec()
				_grad_swing_stage = 2
			elif _grad_wait > 3600:
				_grad_fail("swing glide: the drum never rested before the journey")
				_grad_phase = 3
		2:
			var now: int = Time.get_ticks_msec() - _grad_swing_t0
			_grad_swing_samples.append([now, _room.page_slide_yaw_deg(), rad_to_deg(_room._drum_yaw)])
			if _grad_swing_cmd_i < 6 and now - _grad_swing_last_cmd >= 240:
				_room._set_focused(_room._panels[7 + _grad_swing_cmd_i])
				_grad_swing_cmds.append(now)
				_grad_swing_last_cmd = now
				_grad_swing_cmd_i += 1
			if _grad_swing_cmd_i >= 6 and not _room.page_slide_active():
				_grad_swing_eval_journey()
				_grad_swing_samples.clear()
				_grad_swing_cmds.clear()
				_grad_swing_t0 = Time.get_ticks_msec()
				_room._set_focused(_room._panels[27])
				_grad_swing_cmds.append(0)
				_grad_swing_stage = 3
			elif now > 8000:
				_grad_fail("swing glide: the held-scroll journey never settled")
				_grad_phase = 3
		3:
			var now2: int = Time.get_ticks_msec() - _grad_swing_t0
			_grad_swing_samples.append([now2, _room.page_slide_yaw_deg(), rad_to_deg(_room._drum_yaw)])
			if not _room.page_slide_active() and now2 > 100:
				_grad_swing_eval_long()
				_grad_phase = 3
			elif now2 > 5000:
				_grad_fail("swing glide: the long swing never settled")
				_grad_phase = 3


## Within-leg analysis: a leg runs from the first sample at
## or after its command through the sample taken at the next
## command's tick (that sample was recorded before the
## retarget was issued, so it still measures the old target).
func _grad_swing_legs_of(samples: Array, cmds: Array) -> Array:
	var legs: Array = []
	var start: int = -1
	for si: int in range(samples.size()):
		if int(samples[si][0]) >= int(cmds[0]):
			start = si
			break
	if start < 0:
		return legs
	for ci: int in range(cmds.size()):
		var end: int = samples.size() - 1
		if ci + 1 < cmds.size():
			end = samples.size() - 1
			for si: int in range(start, samples.size()):
				if int(samples[si][0]) >= int(cmds[ci + 1]):
					end = si
					break
		legs.append(samples.slice(start, end + 1))
		start = end + 1
		if start >= samples.size():
			break
	return legs


func _grad_swing_eval_journey() -> void:
	var samples: Array = _grad_swing_samples
	# The harness box samples this phase at ~10-17 ticks a
	# second (the room is heavy under llvmpipe) - the legs are
	# written to convict at that rate, and the sampling itself
	# is reported, per the brief.
	var span_ms: int = int(samples[samples.size() - 1][0]) if samples.size() > 1 else 0
	printerr("GRAD SWING: held-scroll journey - %d samples over %d ms (%.0f ms median pitch)"
		% [samples.size(), span_ms,
			float(span_ms) / float(maxi(1, samples.size() - 1))])
	_grad_expect(samples.size() >= 12,
		"swing glide: the held-scroll journey is densely sampled (%d samples)" % samples.size())
	# The drum's yaw itself never reverses mid-journey. (Its
	# deviation from the standing target may dip and rise as
	# it flows THROUGH an intermediate step point - that is
	# the glide working, not a reversal.)
	var worst_reverse: float = 0.0
	for k: int in range(1, samples.size()):
		worst_reverse = maxf(worst_reverse, float(samples[k - 1][2]) - float(samples[k][2]))
	_grad_expect(worst_reverse <= 0.05,
		"swing glide: the drum's travel never reverses mid-journey (worst %.3f deg)" % worst_reverse)
	# The ratchet's signature, read at the command instants:
	# each step's sample was recorded on the tick that issued
	# the NEXT command, before the retarget - it measures the
	# drum against the target it had chased for a full cadence
	# interval. The old curve read exactly zero there from the
	# second step on (settled dead at 195 ms of every 240 ms
	# leg). The spring always carries a residual - it is
	# still travelling when the next step lands.
	var residuals: Array = []
	for ci: int in range(1, _grad_swing_cmds.size()):
		for s: Variant in samples:
			if int((s as Array)[0]) == int(_grad_swing_cmds[ci]):
				residuals.append(float((s as Array)[1]))
				break
	var min_residual: float = INF
	for rv: Variant in residuals:
		min_residual = minf(min_residual, float(rv))
	printerr("GRAD SWING: command-instant residuals %s deg" % str(residuals))
	_grad_expect(residuals.size() >= 5 and min_residual > 0.05,
		"swing glide: the drum is still travelling at every step (smallest command-instant residual %.3f deg)" % min_residual)
	var total_ms: int = int(samples[samples.size() - 1][0]) if not samples.is_empty() else 0
	_grad_expect(total_ms <= 6 * 240 + 800,
		"swing glide: the held-scroll journey lands inside its envelope (%d ms)" % total_ms)


func _grad_swing_eval_long() -> void:
	var samples: Array = _grad_swing_samples
	if samples.size() < 5:
		_grad_fail("swing glide: the long swing is too thinly sampled (%d)" % samples.size())
		return
	var d0: float = float(samples[0][1])
	var worst_back: float = 0.0
	var t_arrive: int = -1
	var t_settle: int = int(samples[samples.size() - 1][0])
	for k: int in range(1, samples.size()):
		worst_back = maxf(worst_back, float(samples[k][1]) - float(samples[k - 1][1]))
		if t_arrive < 0 and float(samples[k][1]) <= 0.10 * d0:
			t_arrive = int(samples[k][0])
	printerr("GRAD SWING: long swing from %.1f deg, within a tenth at %d ms, settled by %d ms, worst backward %.3f, %d samples"
		% [d0, t_arrive, t_settle, worst_back, samples.size()])
	_grad_expect(worst_back <= 0.05,
		"swing glide: the long swing never steps backward (worst %.3f deg)" % worst_back)
	_grad_expect(t_arrive > 0 and t_arrive <= 353,
		"swing glide: the long swing is visibly arrived inside the old law's duration (within a tenth at %d ms of 353)" % t_arrive)
	_grad_expect(float(samples[samples.size() - 1][1]) == 0.0,
		"swing glide: the long swing lands exactly on target")
	_grad_expect(t_settle <= 560,
		"swing glide: the long swing settles inside its envelope (%d ms, tick-quantised)" % t_settle)


func _grad_measure_centre(c: int) -> void:
	var cam: Camera3D = _room._active_camera()
	if cam == null:
		return
	var rail_polys: Array = []
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null:
			rail_polys.append(_grad_quad_screen_points(rq.global_transform, rq.quad_size() * 0.5, cam))
	var status_poly: Array[Vector2] = []
	if _room._status_plate != null and _room._status_plate.mesh is QuadMesh:
		var sp: MeshInstance3D = _room._status_plate
		var sqm: QuadMesh = sp.mesh as QuadMesh
		status_poly = _grad_quad_screen_points(sp.global_transform, sqm.size * 0.5, cam)
	var wing: Dictionary = _room.wing_state()
	var wing_poly: Array[Vector2] = []
	if bool(wing.get("visible", false)) and wing.get("transform") is Transform3D and wing.get("size") is Vector2:
		var wt: Transform3D = wing["transform"]
		var ws: Vector2 = wing["size"]
		wing_poly = _grad_quad_screen_points(wt, ws * 0.5, cam)
	var centre_label_poly: Array[Vector2] = []
	var long_id: String = str(_grad_manifest.get("long_id", ""))
	for i: int in range(_room._panels.size()):
		var panel: ClickableQuad = _room._panels[i]
		if panel == null or not panel.visible:
			continue
		var label: Label3D = _room._panel_labels[i] if i < _room._panel_labels.size() else null
		if label == null or not label.visible:
			continue
		if not _nav_on_screen(panel.global_position, cam):
			continue
		_grad_labels_measured += 1
		var aabb: AABB = _room.panel_label_world_aabb(i)
		if aabb.position.y < -0.0215:
			_grad_count("floor", "centre %d: panel %d's label bottom %.4f" % [c, i, aabb.position.y])
		var plate: MeshInstance3D = _room._panel_plates[i] if i < _room._panel_plates.size() else null
		if plate != null and plate.visible:
			var pa: AABB = plate.global_transform * plate.get_aabb()
			if pa.position.y < -0.0215:
				_grad_count("plate_floor", "centre %d: panel %d's nameplate bottom %.4f" % [c, i, pa.position.y])
		if panel.payload == long_id and aabb.position.y < _grad_long_min_bottom:
			_grad_long_min_bottom = aabb.position.y
		var lpoly: Array[Vector2] = _grad_label_poly(i, cam)
		for rp: Variant in rail_polys:
			if _grad_polys_overlap(lpoly, rp):
				# THE BROWSING ZONE: the drum's read model
				# is swing-to-centre; the furniture may
				# only be convicted inside +/-2 columns of
				# the centre - the cards a user reads
				# without turning. Beyond that the desk
				# camera's 70-degree frustum keystones
				# fringe labels across the rail's end
				# stops; the prototype's census acquitted
				# the same class by span (labels outside
				# its panel's azimuth span). Fringe
				# intrusions are still counted and printed
				# in the census line - surfaced, not hidden.
				var dcol: int = absi(_room._grid_coord(i).x - _room._grid_coord(c).x)
				if dcol > 2:
					_grad_fringe_rail += 1
					break
				_grad_count("rail", "centre %d: panel %d's label touches the rail" % [c, i])
				# Intrusion depth: how far the label's
				# bottom edge dips below the rail's top
				# edge, at the label corners inside the
				# rail's x-span.
				var rpoly: Array = rp
				var top0: Vector2 = rpoly[3]
				var top1: Vector2 = rpoly[2]
				for lp: Vector2 in [lpoly[0], lpoly[1]]:
					if lp.x >= minf(top0.x, top1.x) and lp.x <= maxf(top0.x, top1.x):
						var f: float = 0.0 if absf(top1.x - top0.x) < 0.01 else (lp.x - top0.x) / (top1.x - top0.x)
						var edge_y: float = lerpf(top0.y, top1.y, clampf(f, 0.0, 1.0))
						var depth: float = lp.y - edge_y
						if depth > _grad_rail_max_depth:
							_grad_rail_max_depth = depth
							_grad_rail_worst = "centre %d panel %d depth %.1fpx" % [c, i, depth]
							print("GRAD DEBUG worst: centre %d panel %d label %s rail %s panelpos %s labelaabb %s"
								% [c, i, str(lpoly), str(rpoly), str(panel.global_position), str(_room.panel_label_world_aabb(i))])
				break
		if not status_poly.is_empty() and _grad_polys_overlap(lpoly, status_poly):
			_grad_count("status", "centre %d: panel %d's label touches the status plate" % [c, i])
		if i == c:
			centre_label_poly = lpoly
		if not wing_poly.is_empty() and _grad_polys_overlap(lpoly, wing_poly):
			_grad_count("wing", "centre %d: the wing eats panel %d's label" % [c, i])
	# The wing against every drawn card's art (the GRAD FIX
	# round): the wing stands in a borrowed slot, so its screen
	# polygon may not cover any part of any visible panel -
	# the borrowed panel is hidden (not drawn, not measured),
	# and every other card must stand clear by area, not by a
	# grazed edge. Coverage is a DEPTH claim, not just a
	# screen claim: the popped centre card pulls 0.15 m toward
	# the eye, ahead of the wing's 0.10 m float, so where their
	# polygons cross it is the CARD that covers the wing. A
	# violation needs the wing nearer the camera than the card
	# it crosses.
	if not wing_poly.is_empty():
		var wing_dist: float = (wing["transform"] as Transform3D).origin.distance_to(cam.global_position)
		for j: int in range(_room._panels.size()):
			var other: ClickableQuad = _room._panels[j]
			if other == null or not other.visible:
				continue
			if not _nav_on_screen(other.global_position, cam):
				continue
			if other.global_transform.origin.distance_to(cam.global_position) < wing_dist - 0.01:
				continue # the card stands in front of the wing - it covers, it is not covered
			var cpoly: Array[Vector2] = _grad_quad_screen_points(other.global_transform, other.quad_size() * 0.5, cam)
			if _grad_polys_overlap(wing_poly, cpoly):
				var area: float = _grad_poly_intersect_area(wing_poly, cpoly)
				if area > 4.0:
					_grad_count("wingcard", "centre %d: the wing covers %.0f px of panel %d's card" % [c, area, j])
	# The popped centre's label against every neighbour's art.
	if not centre_label_poly.is_empty():
		for j: int in range(_room._panels.size()):
			if j == c:
				continue
			var other: ClickableQuad = _room._panels[j]
			if other == null or not other.visible:
				continue
			if not _nav_on_screen(other.global_position, cam):
				continue
			var apoly: Array[Vector2] = _grad_quad_screen_points(other.global_transform, other.quad_size() * 0.5, cam)
			if _grad_polys_overlap(centre_label_poly, apoly):
				_grad_count("pop", "centre %d: the popped label touches panel %d's art" % [c, j])


## One label's screen polygon from its LOCAL aabb corners
## (the quad's own four corners, in order).
func _grad_label_poly(i: int, cam: Camera3D) -> Array[Vector2]:
	var label: Label3D = _room._panel_labels[i] if i < _room._panel_labels.size() else null
	if label == null:
		return []
	var la: AABB = label.get_aabb()
	var gt: Transform3D = label.global_transform
	var pts: Array[Vector2] = []
	for c: Vector3 in [la.position, la.position + Vector3(la.size.x, 0.0, 0.0),
			la.position + Vector3(la.size.x, la.size.y, 0.0), la.position + Vector3(0.0, la.size.y, 0.0)]:
		pts.append(cam.unproject_position(gt * c))
	return pts


## The census verdicts, one per surface, first example named.
func _grad_census_verdicts() -> void:
	var kinds: Array = [
		["floor", "census: no label under the floor at any centre"],
		["plate_floor", "census: no nameplate under the floor at any centre"],
		["rail", "census: no label touches the rail at any centre"],
		["status", "census: no label touches the status plate at any centre"],
		["pop", "census: the popped centre's label clears every neighbour's art"],
		["wing", "wing occlusion: the wing eats no label at any centre"],
		["wingcard", "wing occlusion: the wing covers no part of any card at any centre"],
	]
	for pair: Variant in kinds:
		var kind: String = str((pair as Array)[0])
		var label_text: String = str((pair as Array)[1])
		var count: int = int(_grad_viol.get(kind, 0))
		if count == 0:
			_grad_expect(true, label_text)
		else:
			_grad_expect(false, "%s (%d violations; first: %s)"
				% [label_text, count, str(_grad_viol_first.get(kind, ""))])


func _grad_tournament_step() -> void:
	var tid: String = str(_grad_manifest.get("tournament_id", ""))
	var idx: int = _grad_panel_index(tid)
	if idx < 0:
		_grad_fail("wing: the tournament table is on the shelf")
		_grad_phase = 5
		return
	match _grad_power_stage:
		0:
			_room._set_focused(_room._panels[idx])
			_grad_power_stage = 1
			_grad_power_since = Time.get_ticks_msec()
		1:
			var wing: Dictionary = _room.wing_state()
			var elapsed: int = Time.get_ticks_msec() - _grad_power_since
			if elapsed > 30000:
				_grad_fail("wing: the wing never stood at the tournament table")
				_grad_phase = 5
			elif not _room.page_slide_active() and bool(wing.get("visible", false)):
				_grad_expect(str(wing.get("game_id", "")) == tid,
					"wing: the wing stands at the tournament table")
				_grad_expect(bool(wing.get("has_board_texture", false)),
					"wing: the wing carries the live board")
				var wing_before: int = int(_grad_viol.get("wing", 0))
				_grad_measure_centre(idx)
				_grad_expect(int(_grad_viol.get("wing", 0)) == wing_before,
					"wing occlusion: at the tournament focus the wing eats no label")
				_grad_save_grab("grad_wing.png")
				_grad_power_stage = 0
				_grad_phase = 5


func _grad_power_step() -> void:
	var pair_idx: int = _grad_panel_index(str(_grad_manifest.get("pair_id", "")))
	var b2s_ids: Array = _grad_manifest.get("b2s_ids", [])
	var taxi_idx: int = _grad_panel_index(str(b2s_ids[0])) if b2s_ids.size() > 0 else -1
	var elapsed: int = Time.get_ticks_msec() - _grad_power_since
	match _grad_power_stage:
		0: # warm visit: centre the pair table so its faces fill
			if pair_idx < 0:
				_grad_fail("power: the pair table is on the shelf")
				_grad_phase = 6
				return
			_room._set_focused(_room._panels[pair_idx])
			_grad_power_stage = 1
			_grad_power_since = Time.get_ticks_msec()
		1: # the pair must be claimable before its measured
			# performance - a performance that starts while
			# the pair is still extracting grades the
			# backglass instead (the shipped restart law
			# covers players; the leg measures the real one)
			var g: GameEntry = _grad_game(str(_grad_manifest.get("pair_id", "")))
			if elapsed > 30000:
				_grad_fail("power: the pair table's pair never became claimable")
				_grad_phase = 6
			elif g != null and g.pair_on_art() != "" and not _room.page_slide_active() and elapsed > 500:
				_room._set_focused(_room._panels[mini(pair_idx + 1, _room._panels.size() - 1)])
				_grad_power_stage = 2
				_grad_power_since = Time.get_ticks_msec()
		2: # focus it again: the measured performance
			if elapsed > 20000:
				_grad_fail("power: the warm visit never ended")
				_grad_phase = 6
			elif _room.power_panel() == null and not _room.page_slide_active() and elapsed > 500:
				_room._set_focused(_room._panels[pair_idx])
				_grad_power_stage = 3
				_grad_power_since = Time.get_ticks_msec()
		3: # its performance starts, mode 3, pair crossfade
			if elapsed > 30000:
				_grad_fail("power: the pair table's performance never started")
				_grad_phase = 6
			elif _room.power_panel() == _room._panels[pair_idx]:
				_grad_expect(_room.power_mode() == 3 and _room.power_is_pair(),
					"power: the pair table performs its Off/On crossfade (mode %d)" % _room.power_mode())
				_grad_expect(_room.power_overlay_count() == 1,
					"power: the performance is one overlay quad")
				_grad_power_stage = 4
				_grad_power_since = Time.get_ticks_msec()
		4: # it settles (phase 2 stands, focus still resting)
			# and the card's own face under the standing
			# overlay is the author shot again, pixel-true;
			# focus loss then restores the card outright.
			if elapsed > 60000:
				_grad_fail("power: the pair performance never settled")
				_grad_phase = 6
			elif _room.power_phase() == 2 and elapsed > 1000:
				# The standing face's own key names the art
				# it was rendered from: the shot's cache
				# path must be in it - the resting face
				# under the standing overlay is the shot's.
				var g2: GameEntry = _grad_game(str(_grad_manifest.get("pair_id", "")))
				var fkey: String = str(_room._panel_face_key.get(g2.game_id, ""))
				_grad_expect(fkey.contains(ArtProvider.shot_cache_path_for(g2.shot_url)),
					"power: settled, the pair table wears its author shot again")
				_room._set_focused(_room._panels[mini(pair_idx + 1, _room._panels.size() - 1)])
				_grad_power_stage = 10
				_grad_power_since = Time.get_ticks_msec()
		10: # focus loss restored the performer
			if elapsed > 20000:
				_grad_fail("power: focus loss never restored the pair table")
				_grad_phase = 6
			elif _room.power_panel() == null:
				_grad_expect(true, "power: focus loss restores the shot-faced card")
				_grad_power_stage = 5
				_grad_power_since = Time.get_ticks_msec()
		5: # warm visit: a no-shot table, backglass filled
			if taxi_idx < 0:
				_grad_fail("power: the backglass-fallback table is on the shelf")
				_grad_phase = 6
				return
			_room._set_focused(_room._panels[taxi_idx])
			_grad_power_stage = 6
			_grad_power_since = Time.get_ticks_msec()
		6:
			var tg: GameEntry = _grad_game(str(b2s_ids[0])) if b2s_ids.size() > 0 else null
			if elapsed > 30000:
				_grad_fail("power: the fallback table's backglass never filled")
				_grad_phase = 6
			elif tg != null and tg.backglass_face_path() != "" and not _room.page_slide_active() and elapsed > 500:
				_room._set_focused(_room._panels[mini(taxi_idx + 1, _room._panels.size() - 1)])
				_grad_power_stage = 7
				_grad_power_since = Time.get_ticks_msec()
		7:
			if elapsed > 20000:
				_grad_fail("power: the fallback warm visit never ended")
				_grad_phase = 6
			elif _room.power_panel() == null and not _room.page_slide_active() and elapsed > 500:
				_room._set_focused(_room._panels[taxi_idx])
				_grad_power_stage = 8
				_grad_power_since = Time.get_ticks_msec()
		8:
			if elapsed > 30000:
				_grad_fail("power: the fallback table's performance never started")
				_grad_phase = 6
			elif _room.power_panel() == _room._panels[taxi_idx]:
				_grad_expect(_room.power_mode() == 2 and not _room.power_is_pair(),
					"power: the fallback table performs the mimic grade on its backglass (mode %d)" % _room.power_mode())
				if _room.power_time() > 0.25:
					_grad_save_grab("grad_fallback_power.png")
					_grad_power_stage = 9
					_grad_phase = 6


func _finish_grad_smoke() -> void:
	_grad_audit_labels("final")
	if _grad_failures == 0:
		print("PVLDS GRAD SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS GRAD SMOKE: FAIL (%d)" % _grad_failures)
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
				# Park the mouse in the corner: hover wins the
				# drum's centre over pad focus (the shipped
				# law, right in the headset), so a mouse left
				# mid-screen by the harness would drive the
				# shelf while the leg drives the pad.
				Input.warp_mouse(Vector2(512.0, 764.0))
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
		"sort", "tournament", "page_prev", "page_next", "desk", "exit"]
	# The Tournament Room round's stops: TOURNAMENT walks
	# with the rail always; REFRESH is a stop only while the
	# Tournament Room stands, so this library-mode walk
	# correctly never lands on it.
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
	# The alphabet strip's lit slots are stops too (the
	# letter-jump round): greyed slots are not pickable, so
	# they are not stops - the same rule as the rail's label.
	for k: Variant in _room._strip_quads.keys():
		var sq: ClickableQuad = _room._strip_quads[k] as ClickableQuad
		if sq != null and sq.visible and sq.pick_enabled:
			stops += 1
	_nav_expect(_room._focusables.size() == stops,
		"cards-only: the focus walk is exactly the %d cards + rail stops + lit letter slots (got %d)" % [_room._panels.size(), _room._focusables.size()])
	# One column's DOWN walk: the column's three row panels
	# in order. (Graduation amendment: the flat wall's column
	# was slots 1/5/9 of a 4x3 page; the drum's grid is the
	# shelf itself - the indices come from the room's own
	# grid math, the law - DOWN walks one column's rows in
	# order - is unchanged.)
	var c0: Vector2i = _room._grid_coord(1)
	_room._set_focused(_room._panels[_room._index_at(c0.x, 0)])
	for row: int in [1, 2]:
		_room._move_focus(Vector2(0.0, 1.0))
		_nav_expect(_room.focused_quad() == _room._panels[_room._index_at(c0.x, row)],
			"cards-only: DOWN walks the column - row %d next" % row)
	_room._move_focus(Vector2(0.0, 1.0))
	_nav_expect(_nav_key_of(_room.focused_quad()) != "",
		"cards-only: DOWN from the bottom row lands on the rail, never a Launch button")


func _nav_bottom_row_panel() -> ClickableQuad:
	if _room == null or _room._panels.is_empty():
		return null
	# The drum's bottom row: the panels on the shelf's bottom
	# band (grid row 2) - the middle one stands for the row.
	var bottom: Array = []
	for i: int in range(_room._panels.size()):
		if _room._grid_coord(i).y == 2:
			bottom.append(_room._panels[i])
	if bottom.is_empty():
		return null
	return bottom[bottom.size() / 2]


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


## The y of a sampled screen-space edge at screen x x,
## linearly interpolated between the samples; INF when x
## lies outside the edge's span (no overlap, no constraint).
func _nav_edge_y_at(edge: Array[Vector2], x: float) -> float:
	var best_lo: Vector2 = Vector2(INF, INF)
	var best_hi: Vector2 = Vector2(-INF, INF)
	for p: Vector2 in edge:
		if p.x <= x and p.x > best_lo.x:
			best_lo = p
		if p.x >= x and p.x < best_hi.x:
			best_hi = p
	if best_lo.x == INF or best_hi.x == -INF:
		return INF
	if best_hi.x - best_lo.x < 0.001:
		return best_lo.y
	var f: float = (x - best_lo.x) / (best_hi.x - best_lo.x)
	return lerpf(best_lo.y, best_hi.y, f)


## A quad's screen-space rect from its VISUAL face (quad_size),
## not its collision box: the pick box is deliberately generous,
## and occlusion is a fact about what is seen, not what is
## clickable. (The graduation legs measure sight, not reach.)
func _nav_visual_rect(q: ClickableQuad, cam: Camera3D) -> Rect2:
	var size: Vector2 = q.quad_size()
	var half: Vector2 = size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, 0.0), Vector3(half.x, -half.y, 0.0),
		Vector3(-half.x, half.y, 0.0), Vector3(half.x, half.y, 0.0)]
	var rect: Rect2 = Rect2(cam.unproject_position(q.global_transform * corners[0]), Vector2.ZERO)
	for c: int in range(1, corners.size()):
		rect = rect.expand(cam.unproject_position(q.global_transform * corners[c]))
	return rect


## Whether a world point projects inside the viewport (with a
## small margin): projection legs only judge what the desk
## screen can actually show - a panel outside the frustum is
## the panel-space legs' subject, not the projection's.
func _nav_on_screen(p: Vector3, cam: Camera3D) -> bool:
	if cam.is_position_behind(p):
		return false
	var s: Vector2 = cam.unproject_position(p)
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	return s.x > -60.0 and s.y > -60.0 and s.x < vp.x + 60.0 and s.y < vp.y + 60.0


func _nav_leg_clearance(popped_only: bool) -> void:
	var cam: Camera3D = _room._desk_camera
	if cam == null:
		_nav_smoke_fail("clearance: no desk camera")
		return
	var rail_rects: Array[Rect2] = []
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		if rq != null:
			rail_rects.append(_nav_visual_rect(rq, cam))
	var rows: int = int(ceil(float(_room._panels.size()) / float(RoomView.PAGE_COLS)))
	var first_bottom: int = (rows - 1) * RoomView.PAGE_COLS
	for i: int in range(_room._panels.size()):
		var panel: ClickableQuad = _room._panels[i]
		var launch: ClickableQuad = _room._panel_launches[i] if i < _room._panel_launches.size() else null
		if not popped_only:
			# The nameplate clearance (graduation amendment):
			# the dome face carries no baked name strip - the
			# card's name rides its 3D plate + label, and the
			# Launch button must clear THAT, in panel space
			# first (exact, camera-free), then in projection.
			# Both seats are lawful: below the plate, or at
			# the card's top when a long title's plate grows
			# down over the low seat.
			if launch != null:
				var plate: MeshInstance3D = _room._panel_plates[i] if i < _room._panel_plates.size() else null
				if plate != null and plate.visible:
					var pq: QuadMesh = plate.mesh as QuadMesh
					var psz: Vector2 = pq.size if pq != null else Vector2.ZERO
					var plate_rect: Rect2 = Rect2(
						Vector2(plate.position.x, plate.position.y) - psz * 0.5, psz)
					var btn_rect: Rect2 = Rect2(
						Vector2(launch.position.x, launch.position.y) - RoomView.PANEL_LAUNCH_SIZE * 0.5,
						RoomView.PANEL_LAUNCH_SIZE)
					_nav_expect(not plate_rect.intersects(btn_rect),
						"panel %d: Launch button clears the nameplate in panel space (btn %s, plate %s)" % [i, str(btn_rect), str(plate_rect)])
					# The projection, measured on the EDGES
					# themselves (projected AABBs of slanted
					# quads intersect in their slack corners
					# where the quads themselves never meet):
					# sample the plate's near edge and the
					# button's near edge, and require the
					# button's edge to stay on its own side of
					# the plate's, wherever their screen
					# x-ranges overlap. Off-frustum panels are
					# the panel-space check's subject alone.
					if _nav_on_screen(panel.global_position, cam):
						var low_seat: bool = launch.position.y < plate.position.y
						var plate_edge: Array[Vector2] = []
						var btn_edge: Array[Vector2] = []
						for s: int in range(5):
							var f: float = float(s) / 4.0
							var px: float = plate_rect.position.x + plate_rect.size.x * f
							var py: float = plate_rect.position.y + (0.0 if low_seat else plate_rect.size.y)
							plate_edge.append(cam.unproject_position(
								panel.global_transform * Vector3(px, py, 0.012)))
							var bx: float = -RoomView.PANEL_LAUNCH_SIZE.x * 0.5 + RoomView.PANEL_LAUNCH_SIZE.x * f
							var by: float = (RoomView.PANEL_LAUNCH_SIZE.y * 0.5) if low_seat else (-RoomView.PANEL_LAUNCH_SIZE.y * 0.5)
							btn_edge.append(cam.unproject_position(
								launch.global_transform * Vector3(bx, by, 0.0)))
						var clear: bool = true
						for be: Vector2 in btn_edge:
							# The plate's edge height at this x,
							# interpolated from its samples.
							var pe_y: float = _nav_edge_y_at(plate_edge, be.x)
							if pe_y == INF:
								continue
							if low_seat and be.y < pe_y + 1.0:
								clear = false
							if not low_seat and be.y > pe_y - 1.0:
								clear = false
						_nav_expect(clear,
							"panel %d: Launch button projects clear of the nameplate (edge-sampled)" % i)
		if _room._grid_coord(i).y != 2:
			continue
		if popped_only and panel != _nav_pop_panel:
			continue
		# The bottom band vs the rail (graduation amendment):
		# on the flat wall the whole panel had to clear the
		# rail. On the drum the rail is NEAR furniture (z
		# -1.70) in front of far cards (r 3.05) - a card's ART
		# passing behind the bar in projection is depth
		# separation, not occlusion, and the pointer ray to
		# the card passes over the bar (see the rail's seat).
		# What must never be eaten is what the player reads
		# or presses: the panel's LABEL and its Launch
		# button. Those are the targets now.
		if launch != null and _nav_on_screen(panel.global_position, cam):
			# Edge-sampled, like the nameplate leg: the
			# button's bottom edge against each rail quad's
			# top edge, wherever their screen x-ranges meet.
			# (Projected AABBs of a slanted far button and a
			# flat near quad intersect in slack corners where
			# the quads themselves never meet - and where
			# they DO meet, this still convicts.)
			var btn_edge: Array[Vector2] = []
			var lsz: Vector2 = launch.quad_size()
			for s: int in range(5):
				var f2: float = float(s) / 4.0
				btn_edge.append(cam.unproject_position(launch.global_transform * Vector3(
					-lsz.x * 0.5 + lsz.x * f2, -lsz.y * 0.5, 0.0)))
			for k2: Variant in _room._rail_quads.keys():
				var rq2: ClickableQuad = _room._rail_quads[k2] as ClickableQuad
				if rq2 == null:
					continue
				var rsz: Vector2 = rq2.quad_size()
				var rail_edge: Array[Vector2] = []
				for s2: int in range(5):
					var f3: float = float(s2) / 4.0
					rail_edge.append(cam.unproject_position(rq2.global_transform * Vector3(
						-rsz.x * 0.5 + rsz.x * f3, rsz.y * 0.5, 0.0)))
				var clear2: bool = true
				for be2: Vector2 in btn_edge:
					var re_y: float = _nav_edge_y_at(rail_edge, be2.x)
					if re_y == INF:
						continue
					if be2.y > re_y - 1.0:
						clear2 = false
				_nav_expect(clear2,
					"bottom row panel %d (panel_launch) clears rail quad %s in screen space (edge-sampled)" % [i, str(k2)])
		var label: Label3D = _room._panel_labels[i] if i < _room._panel_labels.size() else null
		if label != null and label.visible and _nav_on_screen(panel.global_position, cam):
			var lab_rect: Rect2 = _nav_aabb_screen_rect(_room.panel_label_world_aabb(i), cam)
			for r2: int in range(rail_rects.size()):
				_nav_expect(not lab_rect.intersects(rail_rects[r2]),
					"bottom row panel %d (label) clears rail quad %d in screen space" % [i, r2])


## A world AABB's screen rect, projected corner by corner.
func _nav_aabb_screen_rect(aabb: AABB, cam: Camera3D) -> Rect2:
	var pts: Array[Vector3] = []
	for sx: float in [aabb.position.x, aabb.position.x + aabb.size.x]:
		for sy: float in [aabb.position.y, aabb.position.y + aabb.size.y]:
			for sz: float in [aabb.position.z, aabb.position.z + aabb.size.z]:
				pts.append(Vector3(sx, sy, sz))
	var rect: Rect2 = Rect2(cam.unproject_position(pts[0]), Vector2.ZERO)
	for k: int in range(1, pts.size()):
		rect = rect.expand(cam.unproject_position(pts[k]))
	return rect


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


## Await the drum's centre arriving at a shelf index (focus
## moves the centre on the drum - see RoomView._follow_centre)
## and the swing settling there.
func _nav_await_centre(idx: int) -> void:
	var guard: int = 0
	while _room.centre_index() != idx and guard < 2400:
		await get_tree().process_frame
		guard += 1
	_nav_expect(_room.centre_index() == idx, "centre arrives at shelf index %d" % idx)
	await _nav_await_slide()


## The swing's choreography proof, run on the bumper leg's
## first flip (graduation amendment): the flat wall swapped
## pages at a slide's far point; the drum has no swap - the
## centre commits at the press and the drum GLIDES to it.
## The proof's surviving intents: the travel is a glide, not
## a cut (the drum stands off rest mid-swing and settles at
## EXACT rest); the furniture never pops (every rail quad
## wears a real texture at the press frame itself, the rail
## being persistent); and the centre the press chose is the
## centre the drum lands on.
func _nav_flip_proof(step: int) -> void:
	var centre_before: int = _room.centre_index()
	_room._bumper_page(step)
	for k: Variant in _room._rail_quads.keys():
		var rq: ClickableQuad = _room._rail_quads[k] as ClickableQuad
		var tx: Texture2D = null
		if rq != null:
			tx = rq.current_texture()
		_nav_expect(tx != null and tx.get_width() > 4,
			"rail: %s wears a real texture on the flip's press frame" % str(k))
	var peak: float = 0.0
	var guard: int = 0
	while _room.page_slide_active() and guard < 2400:
		await get_tree().process_frame
		guard += 1
		peak = maxf(peak, absf(_room.page_slide_yaw_deg()))
	_nav_expect(peak > 1.0, "swing: the drum leaves rest mid-glide (peak deviation %.2f deg)" % peak)
	_nav_expect(not _room.page_slide_active(), "swing: the drum settles after the proof flip")
	_nav_expect(_room.page_slide_yaw_deg() == 0.0,
		"swing: the drum returns to exact rest after the proof flip")
	_nav_expect(_room.centre_index() != centre_before or step == 0,
		"swing: the press moved the centre")


## Leg 5: bumper page travel, driven through RoomView's
## _bumper_page - the same call the pad poll makes on a fresh
## shoulder edge - so the state gating (load wait, placard,
## detail view) is exercised exactly as the room enforces it.
## The harness library spans three pages on ALL (full, full,
## one-panel short), pinned by run_nav_smoke.sh's stub count.
##
## Graduation amendment: on the drum a "page" is a
## bookkeeping unit (12 shelf indices; the rail's readout
## derives from the centre), and the bumper law is the
## shelf's: a focused panel travels one page of shelf FROM
## ITSELF (index +/- PAGE_SIZE, clamped to the shelf's ends)
## and the centre lands on it; a focused rail stop keeps its
## stop while the centre jumps a page; no focus lands on the
## new page's first panel. The leg drives to known centres
## first (focus moves the drum now), because earlier legs
## leave the centre where their browsing left it.
func _nav_leg_bumpers_async() -> void:
	var pages: int = _room.page_count()
	_nav_expect(pages >= 3, "bumpers: the harness library spans at least 3 pages (got %d)" % pages)
	if pages < 2 or _room._visible_games.is_empty():
		_nav_bumpers_done = true
		return
	var filter0: String = _room._filter
	var sort0: String = _room._sort
	var last_idx: int = _room._visible_games.size() - 1
	# Drive to a known shelf place: focus panel 5, centre follows.
	_room._set_focused(_room._panels[5])
	await _nav_await_centre(5)
	_nav_expect(_room._page == 0, "bumpers: the leg starts at the shelf's head (page 1)")
	# Travel, focus riding one page of shelf from itself.
	# The first flip carries the swing's choreography proof.
	await _nav_flip_proof(1)
	_nav_expect(_room.centre_index() == 17 and _room._page == 1, "bumpers: RB advances a page of shelf")
	_nav_expect(_room.focused_quad() == _room._panels[17],
		"bumpers: focus lands a page of shelf from itself across the flip")
	_room._bumper_page(1)
	await _nav_await_slide()
	_nav_expect(_room.centre_index() == last_idx and _room._page == pages - 1, "bumpers: RB advances to the last page")
	_nav_expect(_room.focused_quad() == _room._panels[last_idx],
		"bumpers: the short last page clamps focus to its last panel")
	# Clamped at the far end: no wrap, focus instance untouched.
	var held: ClickableQuad = _room.focused_quad()
	_room._bumper_page(1)
	_nav_expect(_room.centre_index() == last_idx and _room._page == pages - 1, "bumpers: RB clamps on the last page (no wrap)")
	_nav_expect(_room.focused_quad() == held, "bumpers: a clamped RB leaves focus untouched")
	_room._bumper_page(-1)
	await _nav_await_slide()
	_nav_expect(_room.centre_index() == last_idx - 12 and _room._page == pages - 2, "bumpers: LB retreats a page")
	_room._bumper_page(-1)
	await _nav_await_slide()
	_nav_expect(_room.centre_index() == 0 and _room._page == 0, "bumpers: LB retreats to page 1")
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
	_nav_expect(_room.centre_index() == 12 and _room._page == 1 and _nav_key_of(_room.focused_quad()) == "sort",
		"bumpers: rail focus carries to the same stop across the flip")
	_room._bumper_page(-1)
	await _nav_await_slide()
	# No focus lands on the new page's first panel.
	_room._set_focused(null)
	_room._bumper_page(1)
	await _nav_await_slide()
	_nav_expect(_room.centre_index() == 12 and _room._page == 1 and _room.focused_quad() == _room._panels[12],
		"bumpers: no focus lands on the new page's first panel")
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


# ------------------------------------------------ letters smoke

## --pvlds-smoke-letters: the alphabet strip contract (the
## letter-jump round, 2026-10-27). The harness library is
## fourteen games whose titles are REAL VPS db shapes - the
## fixture database is copied from the real database's own
## records (see pvlds-harness/make_letter_fixtures.py) -
## spanning #, A, F, G, M, S, T, W across two pages in title
## order, four of them canonical-The titles arriving three
## ways:
##   (a) a file whose own title carries "The" ("The Getaway
##       - High Speed II", "The Simpsons Pinball Party"),
##   (b) a file MISSING it whose canonical db title has it
##       ("Addams Family" the file, "The Addams Family" the
##       game),
##   (c) an unmatched file titled "The ..." ("The Shadow" -
##       its db record is deliberately withheld from the
##       fixture database, so the file stands filename-only).
## "Theatre of Magic" rides along as the control: "The" is
## not a word of its own in it, so it is no THE member and
## files under T. Every pick rides the pad path (focus the
## slot, press A) - the route a player's A takes.
func _drive_letters_smoke() -> void:
	match _letters_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				Input.warp_mouse(Vector2(512.0, 764.0)) ## parked: hover would drive the drum's centre over the legs' pad focus (see the nav driver)
				_room._handle_rail("filter:all")
				_letters_smoke_wait = 0
				_letters_smoke_phase = 1
			else:
				_letters_smoke_wait += 1
				if _letters_smoke_wait > 3600:
					_letters_smoke_fail("the room never came up")
					_finish_letters_smoke()
		1:
			_letters_smoke_wait += 1
			if _letters_smoke_wait > 3600:
				_letters_smoke_fail("the ALL-filter wall never settled")
				_finish_letters_smoke()
			elif _room != null and _room.wall_ready and _letters_smoke_wait >= 4:
				_letters_leg_fixtures()
				_letters_leg_presence()
				_letters_leg_country()
				_letters_leg_hash_walk()
				_letters_leg_full_strip_walks()
				_letters_leg_anchors()
				_letters_leg_jump()
				_letters_leg_the_net()
				_letters_leg_number_net()
				_letters_smoke_wait = 0
				_letters_smoke_phase = 2
		2:
			# The focus-fix legs (Chris's field reports on the
			# letter-jump build, 2026-10-27): the pad's walk
			# DOWN from a card, through the rail, onto the
			# strip - and the highlight actually DRAWN there.
			_letters_leg_strip_entry()
			_letters_smoke_wait = 0
			_letters_smoke_phase = 3
		3:
			_letters_smoke_wait += 1
			if _letters_smoke_wait >= 6:
				_letters_leg_strip_grab()
				_letters_step = 0
				_letters_smoke_wait = 0
				_letters_smoke_phase = 4
			elif _letters_smoke_wait > 3600:
				_letters_smoke_fail("strip visual: the grab never came due")
				_finish_letters_smoke()
		4:
			# The pager legs: focus an arrow, press A (the real
			# pad route), and focus must still be on the arrow
			# when the slide settles - both directions, and at
			# both clamped ends.
			if _letters_leg_pager_step():
				_letters_step = 0
				_letters_smoke_wait = 0
				_letters_smoke_phase = 5
		5:
			# The focus-law grab legs (Chris, 2026-10-27: picks
			# move the wall, never the focus): pick W, let its
			# wall settle, and focus must STILL be on the W
			# slot - proven in the rendered pixels, not just
			# the state. Then walk the row onto # for its own
			# rendered proof.
			if _letters_step == 0:
				_letters_pick("W")
				_letters_step = 1
				_letters_smoke_wait = 0
			else:
				_letters_smoke_wait += 1
				if _room.wall_ready and _letters_smoke_wait >= 6:
					_letters_expect(_letters_key_of(_room.focused_quad()) == "W",
						"focus law: focus is still on W after its pick's wall settled (got '%s')" % _letters_key_of(_room.focused_quad()))
					var blue_w: int = _letters_grab_ring("W", "pick_focus_w.png")
					_letters_expect(blue_w >= 6,
						"focus law: the rendered frame shows the focus frame around 'W' after its pick (%d frame-blue band samples)" % blue_w)
					for i: int in range(30):
						_room._move_focus(Vector2(-1.0, 0.0))
					_letters_expect(_letters_key_of(_room.focused_quad()) == "A",
						"focus law: the post-pick walk left holds at A, the strip's first slot (got '%s')" % _letters_key_of(_room.focused_quad()))
					for i: int in range(30):
						_room._move_focus(Vector2(1.0, 0.0))
					_letters_expect(_letters_key_of(_room.focused_quad()) == "#",
						"focus law: the walk right across the strip holds at #, its far end (got '%s')" % _letters_key_of(_room.focused_quad()))
					_letters_step = 0
					_letters_smoke_wait = 0
					_letters_smoke_phase = 6
				elif _letters_smoke_wait > 3600:
					_letters_smoke_fail("focus law: the W pick's wall never settled for the grab")
					_finish_letters_smoke()
		6:
			_letters_smoke_wait += 1
			if _letters_smoke_wait >= 6:
				var blue_h: int = _letters_grab_ring("#", "walk_focus_hash.png")
				_letters_expect(blue_h >= 6,
					"focus law: the rendered frame shows the focus frame around '#' after the walk (%d frame-blue band samples)" % blue_h)
				_letters_smoke_wait = 0
				_letters_smoke_phase = 7
			elif _letters_smoke_wait > 3600:
				_letters_smoke_fail("focus law: the # grab never came due")
				_finish_letters_smoke()
		7:
			# The user's exact route (the strip-order fix,
			# Chris 2026-10-27): onto the strip the player's
			# way - card, DOWN to the rail, DOWN to the strip -
			# then hold RIGHT and arrive at #, monotonically
			# through the drawn sequence, frame flagged.
			_letters_pick("A") ## a plain wall: title sort, page 1, no net
			_room._set_focused(_room._panels[10]) ## a bottom-row card
			_room._move_focus(Vector2(0.0, 1.0))
			_room._move_focus(Vector2(0.0, 1.0))
			_letters_expect(_letters_key_of(_room.focused_quad()) != "",
				"user route: DOWN from the rail lands on the strip (got key '%s')" % _letters_key_of(_room.focused_quad()))
			var route_seq: Array[String] = _letters_walk_record(Vector2(1.0, 0.0))
			var drawn_u: Array[String] = _letters_drawn_pickable_order()
			var mono: bool = true
			var last_idx: int = -1
			for k: String in route_seq:
				var di: int = drawn_u.find(k)
				if di <= last_idx:
					mono = false
				last_idx = di
			_letters_expect(mono,
				"user route: holding RIGHT from the entry travels the drawn sequence monotonically (got %s)" % str(route_seq))
			_letters_expect(route_seq[route_seq.size() - 1] == "#",
				"user route: holding RIGHT from the entry arrives at # (got '%s')" % route_seq[route_seq.size() - 1])
			_letters_expect(_room.focused_quad() != null and _room.focused_quad().highlight_visible(),
				"user route: #'s highlight frame is flagged showing at the route's end")
			_letters_smoke_wait = 0
			_letters_smoke_phase = 8
		8:
			_letters_smoke_wait += 1
			if _letters_smoke_wait >= 6:
				var blue_r: int = _letters_grab_ring("#", "route_focus_hash.png")
				_letters_expect(blue_r >= 6,
					"user route: the rendered frame shows the focus frame around '#' reached by holding RIGHT (%d frame-blue band samples)" % blue_r)
				_finish_letters_smoke()
			elif _letters_smoke_wait > 3600:
				_letters_smoke_fail("user route: the # grab never came due")
				_finish_letters_smoke()


func _letters_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - letters smoke: ", label)
	else:
		_letters_smoke_fail(label)


func _letters_smoke_fail(label: String) -> void:
	_letters_smoke_failures += 1
	printerr("  FAIL - letters smoke: ", label)


func _finish_letters_smoke() -> void:
	if _letters_smoke_failures == 0:
		print("PVLDS LETTERS SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS LETTERS SMOKE: FAIL (%d)" % _letters_smoke_failures)
		get_tree().quit(1)


## The strip key a quad answers to, or "" when it is not a
## strip slot (a wall panel, a rail stop, anything else).
func _letters_key_of(q: ClickableQuad) -> String:
	if q == null or _room == null:
		return ""
	for k: Variant in _room._strip_quads.keys():
		if _room._strip_quads[k] == q:
			return str(k)
	return ""


## The visible wall's titles, in wall order.
func _letters_visible_titles() -> Array[String]:
	var out: Array[String] = []
	for g: GameEntry in _room._visible_games:
		out.append(g.title)
	return out


## A strip pick the way the pad makes it: focus the slot,
## press A (which routes through _activate, like any press).
func _letters_pick(key: String) -> void:
	_room._set_focused(_room.letter_quad(key))
	_room._a_press()


func _letters_leg_fixtures() -> void:
	_letters_expect(_scanner != null and _scanner.games.size() == 14,
		"fixtures: the letter library holds 14 games (got %d)" % (_scanner.games.size() if _scanner != null else -1))
	var addams: GameEntry = _scanner.game_by_id("aT_GONvw") if _scanner != null else null
	_letters_expect(addams != null and addams.title == "The Addams Family",
		"fixtures: the 'Addams Family' file stands under its canonical db title 'The Addams Family' (got '%s')" % (addams.title if addams != null else "<missing>"))
	var shadow: GameEntry = null
	if _scanner != null:
		for g: GameEntry in _scanner.games:
			if g.title == "The Shadow":
				shadow = g
	_letters_expect(shadow != null and shadow.game_id.begins_with("local:"),
		"fixtures: 'The Shadow' is filename-only (its db record is withheld from the fixture database)")
	var expected: Array[String] = [
		"8 Ball", "The Addams Family", "Attack from Mars", "Funhouse",
		"The Getaway - High Speed II", "Medieval Madness", "Monster Bash",
		"Scared Stiff", "The Shadow", "The Simpsons Pinball Party",
		"Tales of the Arabian Nights", "Theatre of Magic", "Twilight Zone", "White Water"]
	_letters_expect(_letters_visible_titles() == expected,
		"fixtures: the wall's title order is the census order (got %s)" % str(_letters_visible_titles()))
	_letters_expect(_letters_visible_titles().find("The Addams Family") == 1,
		"canonical-The: title order files The Addams Family under A, not T")


func _letters_leg_presence() -> void:
	_letters_expect(_room.strip_slot_pickable("A"), "presence: A is pickable (it has games)")
	_letters_expect(not _room.strip_slot_pickable("B"), "presence: B is greyed (no games) - not pickable")
	_letters_expect(not _room._focusables.has(_room.letter_quad("B")),
		"presence: a greyed slot is not a focus stop")
	_letters_expect(_room.strip_slot_pickable("THE"), "presence: THE is pickable (canonical-The games exist)")
	var hash_q: ClickableQuad = _room.letter_quad("#")
	_letters_expect(hash_q != null and hash_q.visible and _room.strip_slot_pickable("#"),
		"presence: the # slot is laid out and pickable (the library holds '8 Ball')")
	_letters_expect(_room.strip_slot_pickable("W"), "presence: W is pickable")


func _letters_leg_country() -> void:
	_room._set_focused(_room.rail_quad("sort"))
	_room._move_focus(Vector2(0.0, 1.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) != "",
		"country: DOWN from the rail lands on the strip (got key '%s')" % _letters_key_of(_room.focused_quad()))
	# Walk to the row's drawn start, then prove the sideways
	# walk and its greyed-slot skips against the deterministic
	# lit order - in the DRAWN sequence (the strip-order fix:
	# A is the left end, # the right end, past THE).
	for i: int in range(30):
		_room._move_focus(Vector2(-1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "A",
		"country: the sideways walk holds at the strip's first slot, A (got '%s')" % _letters_key_of(_room.focused_quad()))
	_room._move_focus(Vector2(-1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "A",
		"country: the strip's left end clamps - focus stays on A")
	_room._move_focus(Vector2(1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "F",
		"country: A steps right to F - the greyed B-E are skipped, never landed on (got '%s')" % _letters_key_of(_room.focused_quad()))
	for i: int in range(30):
		_room._move_focus(Vector2(1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "#",
		"country: the sideways walk holds at the strip's last slot, # - past THE, at the drawn right end (got '%s')" % _letters_key_of(_room.focused_quad()))
	_room._move_focus(Vector2(1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "#",
		"country: the strip's right end clamps - focus stays on #")
	_room._move_focus(Vector2(0.0, -1.0))
	_letters_expect(_nav_key_of(_room.focused_quad()) != "",
		"country: UP from the strip returns to the rail")
	# No trap: Tab cycling from a strip slot reaches a card.
	_room._set_focused(_room.letter_quad("A"))
	var saw_panel: bool = false
	for i: int in range(_room._focusables.size() + 2):
		_room._cycle_focus(1)
		if _room._panels.has(_room.focused_quad()):
			saw_panel = true
			break
	_letters_expect(saw_panel, "country: Tab cycling escapes the strip to a card (no focus trap)")


## The # walk legs (Chris, 2026-10-27: "Cant highlight #",
## then, on the focus-law build: "If I highlight down to
## letters and start moving right to get to #, I can't get
## there. Stops at THE."). # is DRAWN at the row's right
## end, past THE; these legs start from deterministic
## neighbours and take HIS route: one step RIGHT from THE
## must land on #, the frame flagged showing; # steps left
## back to THE; and the full walk LEFT from # must traverse
## the row to its drawn start at A.
func _letters_leg_hash_walk() -> void:
	_room._set_focused(_room.letter_quad("THE"))
	_room._move_focus(Vector2(1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "#",
		"# walk: THE steps right onto # (got '%s')" % _letters_key_of(_room.focused_quad()))
	_letters_expect(_room.focused_quad() != null and _room.focused_quad().highlight_visible(),
		"# walk: #'s highlight frame is flagged showing after the step from THE")
	_room._move_focus(Vector2(-1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "THE",
		"# walk: # steps left back to THE")
	for i: int in range(30):
		_room._move_focus(Vector2(-1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "A",
		"# walk: the walk left from # holds at A, the drawn left end (got '%s')" % _letters_key_of(_room.focused_quad()))


## The strip's pickable slots in DRAWN order: the slots
## sorted by their laid-out x - what the eye sees, read off
## the geometry, not off any order list.
func _letters_drawn_pickable_order() -> Array[String]:
	var pairs: Array = [] ## [x, key]
	for k: Variant in _room._strip_quads.keys():
		var q: ClickableQuad = _room._strip_quads[k] as ClickableQuad
		if q != null and q.visible and q.pick_enabled:
			pairs.append([q.position.x, str(k)])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array[String] = []
	for p: Array in pairs:
		out.append(str(p[1]))
	return out


## Step sideways until focus stops changing, recording each
## newly focused slot's key (the starting slot first).
func _letters_walk_record(dir: Vector2) -> Array[String]:
	var out: Array[String] = []
	var cur: String = _letters_key_of(_room.focused_quad())
	out.append(cur)
	for i: int in range(40):
		_room._move_focus(dir)
		var k: String = _letters_key_of(_room.focused_quad())
		if k == cur:
			break
		out.append(k)
		cur = k
	return out


## The full-strip walks (the strip-order fix's proof).
## The drawn order is read off the slots' own positions -
## the eye's truth, independent of any list in the code -
## and holding one direction from an end must reproduce it
## exactly, then its exact reverse coming back. Greyed
## slots are skipped in both directions; no stop is
## skipped or doubled.
func _letters_leg_full_strip_walks() -> void:
	var drawn: Array[String] = _letters_drawn_pickable_order()
	_letters_expect(drawn.size() >= 3,
		"strip order: the drawn pickable order reads off the slots' positions (got %s)" % str(drawn))
	_letters_expect(drawn[drawn.size() - 1] == "#",
		"strip order: # is the drawn far (right) end of this library's strip (got %s)" % str(drawn))
	_room._set_focused(_room.letter_quad(drawn[0]))
	var right_seq: Array[String] = _letters_walk_record(Vector2(1.0, 0.0))
	_letters_expect(right_seq == drawn,
		"strip order: holding RIGHT visits the drawn order exactly, far end included (got %s, drawn %s)" % [str(right_seq), str(drawn)])
	var drawn_rev: Array[String] = []
	for i: int in range(drawn.size()):
		drawn_rev.append(drawn[drawn.size() - 1 - i])
	var left_seq: Array[String] = _letters_walk_record(Vector2(-1.0, 0.0))
	_letters_expect(left_seq == drawn_rev,
		"strip order: holding LEFT visits the exact reverse (got %s, want %s)" % [str(left_seq), str(drawn_rev)])


## The bumper-anchor legs (the bumper-anchors round,
## 2026-10-28 - Chris: bumpers on the strip should "move
## you to middle, then end"): while a strip slot holds
## focus, LB/RB step between the anchors over the pickable
## slots - first / middle / last - instead of turning the
## wall's page. The fixture's pickable strip is A F G M S
## T W THE # (nine slots), so the anchors are A, S (index
## (9-1)/2 = 4) and #. Every press rides _bumper_page, the
## pad poll's own call, and every landing is asserted by
## key AND checked against the drawn pickable list - a
## greyed slot is never a landing.
func _letters_leg_anchors() -> void:
	var drawn: Array[String] = _letters_drawn_pickable_order()
	_letters_expect(drawn == ["A", "F", "G", "M", "S", "T", "W", "THE", "#"],
		"anchors: the fixture's pickable strip is A F G M S T W THE # - anchors A, S and # (got %s)" % str(drawn))
	var page0: int = _room._page
	var landings: Array[String] = []
	_room._set_focused(_room.letter_quad("G"))
	_room._bumper_page(1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "S",
		"anchors: RB from G (left of the middle) lands on the middle, S (got '%s')" % landings[landings.size() - 1])
	_room._bumper_page(1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "#",
		"anchors: RB from the middle lands on the last slot, # (got '%s')" % landings[landings.size() - 1])
	_room._bumper_page(1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "#",
		"anchors: RB at the last slot clamps - focus stays on # (got '%s')" % landings[landings.size() - 1])
	_room._bumper_page(-1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "S",
		"anchors: LB from the last slot lands back on the middle, S (got '%s')" % landings[landings.size() - 1])
	_room._bumper_page(-1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "A",
		"anchors: LB from the middle lands on the first slot, A (got '%s')" % landings[landings.size() - 1])
	_room._bumper_page(-1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "A",
		"anchors: LB at the first slot clamps - focus stays on A (got '%s')" % landings[landings.size() - 1])
	_room._set_focused(_room.letter_quad("W"))
	_room._bumper_page(-1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "S",
		"anchors: LB from W (right of the middle) lands on the middle, S (got '%s')" % landings[landings.size() - 1])
	_room._set_focused(_room.letter_quad("A"))
	_room._bumper_page(1)
	landings.append(_letters_key_of(_room.focused_quad()))
	_letters_expect(landings[landings.size() - 1] == "S",
		"anchors: a press while ON the first anchor advances to the middle - never a no-op (got '%s')" % landings[landings.size() - 1])
	var all_pickable: bool = true
	for k: String in landings:
		if not drawn.has(k):
			all_pickable = false
	_letters_expect(all_pickable,
		"anchors: every landing is a pickable slot - a greyed slot is never landed on (landings %s)" % str(landings))
	_letters_expect(_room._page == page0,
		"anchors: bumper presses inside the strip never turned the wall page (page %d, was %d)" % [_room._page, page0])


func _letters_leg_jump() -> void:
	_room._handle_rail("sort")
	_letters_expect(_room._sort == "year",
		"jump: precondition - the sort starts off NAME (got %s)" % _room._sort)
	_letters_pick("W")
	_letters_expect(_room._sort == "name", "jump: picking a letter quietly switches to title sort")
	_letters_expect(_room._page == 1, "jump: W lands on the second page (got page %d)" % _room._page)
	_letters_expect(_room.focused_quad() == _room.letter_quad("W"),
		"focus law: picking W keeps focus on the W slot (got key '%s')" % _letters_key_of(_room.focused_quad()))
	_letters_expect(_room._panels.size() > 1 and _room.centre_index() < _room._panels.size()
		and _room._panels[_room.centre_index()].payload == "LJRH3fKk",
		"jump: the wall W's pick built shows White Water")
	## (Dome amendment: the flat wall's page array made
	## _panels[1] the second card of page 2; the drum's array
	## is shelf-aligned, and what the pick BUILT is the centre
	## - so the leg reads the centred panel. The F leg below
	## reads the same way: under shelf alignment _panels[3]
	## is Funhouse whether or not the pick landed.)
	_letters_expect(_room.active_letter_net() == "", "jump: a letter pick stands in no net")
	_letters_pick("F")
	_letters_expect(_room._page == 0 and _room.focused_quad() == _room.letter_quad("F")
		and _room._panels.size() > 3 and _room.centre_index() == 3
		and _room._panels[_room.centre_index()].payload == "O1-qbuxg",
		"focus law: F's pick keeps focus on F, and the wall shows Funhouse")


func _letters_leg_the_net() -> void:
	_letters_pick("THE")
	_letters_expect(_room.active_letter_net() == "THE", "THE net: the net view stands")
	_letters_expect(_letters_visible_titles().has("The Getaway - High Speed II"),
		"THE net: (a) a file whose own title carries 'The' is a member")
	_letters_expect(_letters_visible_titles().has("The Addams Family"),
		"THE net: (b) a file missing 'The' whose canonical db title has it is a member")
	_letters_expect(_letters_visible_titles().has("The Shadow"),
		"THE net: (c) an unmatched file titled 'The ...' is a member")
	_letters_expect(not _letters_visible_titles().has("Theatre of Magic"),
		"THE net: 'Theatre of Magic' is not a member ('The' is not a word of its own in it)")
	var expected: Array[String] = ["The Addams Family", "The Getaway - High Speed II", "The Shadow", "The Simpsons Pinball Party"]
	_letters_expect(_letters_visible_titles() == expected,
		"THE net: exactly the canonical-The games, sorted by the word after The (got %s)" % str(_letters_visible_titles()))
	_letters_expect(_room._page == 0 and _room.focused_quad() == _room.letter_quad("THE"),
		"focus law: picking THE keeps focus on the THE slot")
	# The net property: the members never left their letters -
	# picking A exits the net and the wall stands on the very
	# game the net was showing, filed under its own letter.
	_letters_pick("A")
	_letters_expect(_room.active_letter_net() == "", "THE net: picking a letter exits the net")
	_letters_expect(_room.focused_quad() == _room.letter_quad("A")
		and _room._panels.size() > 1 and _room._panels[1].payload == "aT_GONvw",
		"canonical-The: picking A exits to the wall where The Addams Family files under A, focus on the A slot")
	# A rail sort press leaves the net too.
	_letters_pick("THE")
	_room._handle_rail("sort")
	_letters_expect(_room.active_letter_net() == "" and _room._visible_games.size() == 14,
		"THE net: a sort press leaves the net (the full set returns)")


func _letters_leg_number_net() -> void:
	_letters_pick("#")
	_letters_expect(_room.active_letter_net() == "#", "# net: the net view stands")
	_letters_expect(_room.focused_quad() == _room.letter_quad("#"),
		"focus law: picking # keeps focus on the # slot")
	var expected: Array[String] = ["8 Ball"]
	_letters_expect(_letters_visible_titles() == expected,
		"# net: exactly the non-letter starters (got %s)" % str(_letters_visible_titles()))
	_letters_pick("F")
	_letters_expect(_room.active_letter_net() == "" and _room.focused_quad() == _room.letter_quad("F")
		and _room._panels.size() > 3 and _room._panels[3].payload == "O1-qbuxg",
		"# net: picking a letter exits at that letter (focus on F, the wall shows Funhouse)")


## Fault 1's legs (Chris, 2026-10-27: the highlight "doesn't
## make it down to letters. It disappears."). The country leg
## above proved the strip is reachable in STATE; these legs
## walk the player's actual route - bottom-row card, DOWN to
## the rail, DOWN to the strip - and then prove the highlight
## is DRAWN on the letter: the quad's own frame flag, and blue
## frame pixels in a rendered grab. A focus that exists in
## state but draws nothing is a failed delivery.
func _letters_leg_strip_entry() -> void:
	_letters_pick("A") ## a plain wall: title sort, page 1, no net
	_room._set_focused(_room._panels[10]) ## a bottom-row card
	_room._move_focus(Vector2(0.0, 1.0))
	_letters_expect(_nav_key_of(_room.focused_quad()) != "",
		"strip entry: DOWN from a bottom-row card lands on the rail (got '%s')" % _nav_key_of(_room.focused_quad()))
	_room._move_focus(Vector2(0.0, 1.0))
	var key: String = _letters_key_of(_room.focused_quad())
	_letters_expect(key != "",
		"strip entry: DOWN from the rail lands on the strip (got key '%s')" % key)
	var fq: ClickableQuad = _room.focused_quad()
	_letters_expect(fq != null and fq.highlight_visible(),
		"strip visual: the focused letter's highlight frame is flagged showing (key '%s')" % key)
	# Steer right to the row's drawn far end (#), then one
	# step back to the wide THE slot for the photograph: its
	# frame ring is the broadest on the strip.
	for i: int in range(30):
		_room._move_focus(Vector2(1.0, 0.0))
	_letters_expect(_letters_key_of(_room.focused_quad()) == "#",
		"strip visual: the walk right from the entry holds at #, the drawn far end (got '%s')" % _letters_key_of(_room.focused_quad()))
	_room._move_focus(Vector2(-1.0, 0.0))
	_letters_focus_key = _letters_key_of(_room.focused_quad())
	_letters_expect(_letters_focus_key == "THE",
		"strip visual: one step left from # lands on THE for the grab (got '%s')" % _letters_focus_key)
	_letters_expect(_room.focused_quad() != null and _room.focused_quad().highlight_visible(),
		"strip visual: THE's highlight frame is flagged showing for the grab")


## Grab the live frame and count focus-frame-blue pixels in
## the ring band around the named slot (which must hold the
## focus - anything else counts zero). The grab is saved
## beside the log under PVLDS_GRAB_DIR.
func _letters_grab_ring(key: String, file_name: String) -> int:
	var fq: ClickableQuad = _room.letter_quad(key)
	if fq == null or _room.focused_quad() != fq:
		return 0
	var img: Image = get_viewport().get_texture().get_image()
	var dir: String = OS.get_environment("PVLDS_GRAB_DIR")
	if dir != "":
		img.save_png(dir.path_join(file_name))
	return _letters_ring_blue_count(img, fq, _room._strip_slot_size(key))


## The rendered half of fault 1: grab the actual frame and
## count focus-frame-blue pixels in the band the frame ring
## occupies (the frame quad is 1.055x its face, riding just
## behind it, so the ring lives between the face's edge and
## ~7% beyond it). The letter face itself is never that blue.
func _letters_leg_strip_grab() -> void:
	var fq: ClickableQuad = _room.focused_quad()
	if fq == null or _letters_focus_key == "":
		_letters_smoke_fail("strip visual: no focused letter to photograph")
		return
	var img: Image = get_viewport().get_texture().get_image()
	var dir: String = OS.get_environment("PVLDS_GRAB_DIR")
	if dir != "":
		img.save_png(dir.path_join("strip_focus.png"))
	var blue: int = _letters_ring_blue_count(img, fq, _room._strip_slot_size(_letters_focus_key))
	_letters_expect(blue >= 6,
		"strip visual: the rendered frame shows the focus frame around '%s' (%d frame-blue band samples)" % [_letters_focus_key, blue])


func _letters_is_frame_blue(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	var px: Color = img.get_pixel(x, y)
	# ClickableQuad.FOCUS_COLOR (0.35, 0.75, 1.0), unshaded.
	return px.b > 0.8 and px.g > 0.55 and px.r < 0.6 and px.b > px.r + 0.25


func _letters_ring_blue_count(img: Image, quad: ClickableQuad, size: Vector2) -> int:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return 0
	var half: Vector2 = size * 0.5
	var pts: Array[Vector2] = []
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		pts.append(cam.unproject_position(quad.global_transform * Vector3(c.x, c.y, 0.0)))
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p: Vector2 in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var inner: Rect2 = Rect2(mn, mx - mn).grow_individual(-2.0, -2.0, -2.0, -2.0)
	var outer: Rect2 = Rect2(mn, mx - mn)
	outer = outer.grow_individual(outer.size.x * 0.075, outer.size.y * 0.075, outer.size.x * 0.075, outer.size.y * 0.075)
	var count: int = 0
	var x: int = int(outer.position.x)
	while x < int(outer.position.x + outer.size.x):
		var y: int = int(outer.position.y)
		while y < int(outer.position.y + outer.size.y):
			if not inner.has_point(Vector2(float(x), float(y))):
				if _letters_is_frame_blue(img, x, y):
					count += 1
			y += 1
		x += 1
	return count


## Fault 2's legs (Chris, 2026-10-27: turning a page with the
## rail's arrows "resets to wall cards, upper area and you
## have to tap-tap-tap back down to arrow"). One step per
## _process call; returns true when the legs are done. Every
## press is the pad's real route: focus the arrow, press A.
## The pager legs' step machine. The settle reads poll the
## room's page_slide_active() seam (the dome's swing) -
## GRADUATION AMENDMENT: they used to read the flat wall's
## _slide_phase field, which the dome port removed; the
## seam is the same question asked of the room's current
## travel state.
func _letters_leg_pager_step() -> bool:
	match _letters_step:
		0:
			_letters_pick("A") ## page 1 of 2, title sort, no net
			_room._set_focused(_room.rail_quad("page_next"))
			_room._a_press()
			_letters_step = 1
			_letters_smoke_wait = 0
		1:
			_letters_smoke_wait += 1
			if not _room.page_slide_active() and _letters_smoke_wait >= 8:
				_letters_expect(_room._page == 1,
					"pager: NEXT turns to the second page (got %d)" % _room._page)
				_letters_expect(_room.focused_quad() == _room.rail_quad("page_next"),
					"pager: focus stays on the NEXT arrow across a page turn")
				_room._a_press() ## clamped: page 2 of 2 is the last
				_letters_step = 2
				_letters_smoke_wait = 0
			elif _letters_smoke_wait > 3600:
				_letters_smoke_fail("pager: the NEXT slide never settled")
				return true
		2:
			_letters_smoke_wait += 1
			if _letters_smoke_wait >= 12:
				_letters_expect(_room._page == 1,
					"pager: a clamped NEXT stays on the last page (got %d)" % _room._page)
				_letters_expect(_room.focused_quad() == _room.rail_quad("page_next"),
					"pager: a clamped NEXT at the last page keeps focus on the arrow")
				_room._set_focused(_room.rail_quad("page_prev"))
				_room._a_press()
				_letters_step = 3
				_letters_smoke_wait = 0
		3:
			_letters_smoke_wait += 1
			if not _room.page_slide_active() and _letters_smoke_wait >= 8:
				_letters_expect(_room._page == 0,
					"pager: PREV turns back to the first page (got %d)" % _room._page)
				_letters_expect(_room.focused_quad() == _room.rail_quad("page_prev"),
					"pager: focus stays on the PREV arrow across a page turn")
				_room._a_press() ## clamped at the first page
				_letters_step = 4
				_letters_smoke_wait = 0
			elif _letters_smoke_wait > 3600:
				_letters_smoke_fail("pager: the PREV slide never settled")
				return true
		4:
			_letters_smoke_wait += 1
			if _letters_smoke_wait >= 12:
				_letters_expect(_room._page == 0,
					"pager: a clamped PREV stays on the first page (got %d)" % _room._page)
				_letters_expect(_room.focused_quad() == _room.rail_quad("page_prev"),
					"pager: a clamped PREV at the first page keeps focus on the arrow")
				return true
	return false


# -------------------------------------------------- jump bench

## --pvlds-smoke-jumpbench: the pick-latency bench (the
## focus-law round, 2026-10-27 - Chris: "tapping letter
## switched to correct wall, but it took awhile to load,
## grinding gear. not sure if one-time thing or what").
## Boots a field-scale fixture library (360 stub tables over
## verbatim real VPS records, sidecar art on every game),
## waits out the scan + warm drain, then times the player's
## own routes end to end - the press to the wall settled
## (wall_ready): a COLD letter pick (a page never shown this
## session), a WARM re-pick of the same letter, a plain page
## turn for comparison, and the THE / # net picks. The
## numbers are the deliverable (JUMPBENCH lines); the room's
## BENCH fill lines (PVLDS_BENCH) attribute each fill's cost
## to the banner, the furniture, and the panels. Sanity
## failures (wrong library size, a pick landing wrong) fail
## the boot - a broken bench must not masquerade as data.
func _drive_jumpbench_smoke() -> void:
	if _jumpbench_after >= 0:
		_jumpbench_wait += 1
		_jumpbench_frames += 1
		if _room != null and _room.wall_ready and not _room.page_slide_active():
			print("JUMPBENCH: %s: %d ms (%d frames)" % [_jumpbench_label, Time.get_ticks_msec() - _jumpbench_t0, _jumpbench_frames])
			_jumpbench_phase = _jumpbench_after
			_jumpbench_after = -1
			_jumpbench_wait = 0
		elif _jumpbench_wait > 7200:
			_jumpbench_fail("the measurement '%s' never settled" % _jumpbench_label)
			_finish_jumpbench_smoke()
		return
	match _jumpbench_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready and not _scan_active \
					and (_art_warmer == null or _art_warmer.is_idle()):
				var games: int = _scanner.games.size() if _scanner != null else -1
				print("JUMPBENCH: library games=%d files=%d warm_drain=%dms boot_settle=%dms" % [
					games, _scanner.total_files if _scanner != null else -1,
					_art_warmer.last_pass_msec if _art_warmer != null else -1,
					Time.get_ticks_msec() - _jumpbench_boot_msec])
				if games < 330 or games > 390:
					_jumpbench_fail("the bench library holds %d games, not field scale (~360)" % games)
					_finish_jumpbench_smoke()
					return
				_jumpbench_phase = 1
			else:
				_jumpbench_wait += 1
				if _jumpbench_wait > 21600:
					_jumpbench_fail("the bench room never settled (scan/warm)")
					_finish_jumpbench_smoke()
		1:
			# The room boots into the VR filter by design; the
			# bench times the FULL shelf, so stand in ALL first
			# (the letters smoke does the same). The press is a
			# full rebuild - its timing is honest data too.
			_jumpbench_measure("filter ALL (bench setup)", Callable(self, "_jumpbench_press_all"), 2)
		2:
			_jumpbench_measure("pick S (cold page)", Callable(self, "_jumpbench_press_s"), 3)
		3:
			_jumpbench_measure("pick A (boot page, warm)", Callable(self, "_jumpbench_press_a"), 4)
		4:
			_jumpbench_measure("pick S (warm page)", Callable(self, "_jumpbench_press_s"), 5)
		5:
			_jumpbench_measure("page turn NEXT", Callable(self, "_jumpbench_press_next"), 6)
		6:
			_jumpbench_measure("pick THE (net)", Callable(self, "_jumpbench_press_the"), 7)
		7:
			if _room.strip_slot_pickable("#"):
				_jumpbench_measure("pick # (net)", Callable(self, "_jumpbench_press_hash"), 8)
			else:
				_jumpbench_fail("the # slot is not pickable on the bench shelf in ALL (the sample holds 3 non-letter starters)")
				_jumpbench_phase = 8
		8:
			_finish_jumpbench_smoke()


func _jumpbench_measure(label: String, press: Callable, after: int) -> void:
	_jumpbench_label = label
	_jumpbench_frames = 0
	_jumpbench_wait = 0
	_jumpbench_t0 = Time.get_ticks_msec()
	press.call()
	_jumpbench_after = after


func _jumpbench_press_all() -> void:
	_room._handle_rail("filter:all")
	if _room._filter != "all":
		_jumpbench_fail("the bench could not stand in the ALL filter")


func _jumpbench_press_s() -> void:
	_letters_pick("S")
	var idx: int = -1
	for i: int in range(_room._visible_games.size()):
		if LetterIndex.letter_of(_room._visible_games[i].title) == "S":
			idx = i
			break
	if idx < 0 or _room._page != idx / _room.PAGE_SIZE:
		_jumpbench_fail("pick S landed on page %d, expected %d" % [_room._page, idx / _room.PAGE_SIZE if idx >= 0 else -1])


func _jumpbench_press_a() -> void:
	_letters_pick("A")


func _jumpbench_press_next() -> void:
	var before: int = _room._page
	_room._set_focused(_room.rail_quad("page_next"))
	_room._a_press()
	if _room._page == before and not _room.page_slide_active():
		_jumpbench_fail("page turn NEXT never started its slide")


func _jumpbench_press_the() -> void:
	_letters_pick("THE")
	if _room.active_letter_net() != "THE":
		_jumpbench_fail("pick THE did not raise the net")


func _jumpbench_press_hash() -> void:
	_letters_pick("#")
	if _room.active_letter_net() != "#":
		_jumpbench_fail("pick # did not raise the net")


func _jumpbench_fail(label: String) -> void:
	_jumpbench_failures += 1
	printerr("  FAIL - jumpbench: ", label)


func _finish_jumpbench_smoke() -> void:
	if _jumpbench_failures == 0:
		print("PVLDS JUMPBENCH: DONE")
		get_tree().quit(0)
	else:
		printerr("PVLDS JUMPBENCH: FAILED (%d)" % _jumpbench_failures)
		get_tree().quit(1)


# -------------------------------------------------- boot focus smoke

## --pvlds-smoke-bootfocus: fault 3's harness (Chris,
## 2026-10-27: "Upon initial launch, the highlighter defaults
## to last played table, but the card is dark and art is not
## visible till highlighter is moved."). The runner seeds the
## state file with a last-played record; this driver then
## touches NOTHING - no _set_focused, no _move_focus, no
## presses - and judges the room the real boot path built:
## the boot-focused card must hold the focus, wear its real
## face, carry the standing power performance ON that face,
## and render art (pixel variance) in a grab, all with zero
## input.
func _drive_bootfocus_smoke() -> void:
	match _bootfocus_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_bootfocus_phase = 1
				_bootfocus_wait = 0
			else:
				_bootfocus_wait += 1
				if _bootfocus_wait > 7200:
					_bootfocus_fail("the room never came up on the real boot path")
					_finish_bootfocus_smoke()
		1:
			_bootfocus_wait += 1
			var panel: ClickableQuad = _bootfocus_panel()
			if panel != null and _room.focused_quad() == panel and _room.power_panel() == panel and _room.power_phase() == 2:
				_bootfocus_phase = 2
				_bootfocus_wait = 0
			elif _bootfocus_wait > 7200:
				_bootfocus_fail("the boot power-on never settled on the last-played card (focused=%s, power panel=%s, phase=%d)" % [
					_bootfocus_payload_of(_room.focused_quad() if _room != null else null),
					_bootfocus_payload_of(_room.power_panel() if _room != null else null),
					_room.power_phase() if _room != null else -1])
				_finish_bootfocus_smoke()
		2:
			# A few frames of slack for the readback to be the
			# settled frame, then judge and photograph.
			_bootfocus_wait += 1
			if _bootfocus_wait >= 6:
				var panel2: ClickableQuad = _bootfocus_panel()
				if panel2 != null:
					_bootfocus_leg(panel2)
				else:
					_bootfocus_fail("the last-played panel left the wall before the grab")
				_finish_bootfocus_smoke()


func _bootfocus_panel() -> ClickableQuad:
	if _room == null:
		return null
	for p: ClickableQuad in _room._panels:
		if p.payload == _bootfocus_game:
			return p
	return null


func _bootfocus_payload_of(q: ClickableQuad) -> String:
	return q.payload if q != null else "<none>"


func _bootfocus_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - bootfocus smoke: ", label)
	else:
		_bootfocus_fail(label)


func _bootfocus_fail(label: String) -> void:
	_bootfocus_failures += 1
	printerr("  FAIL - bootfocus smoke: ", label)


func _finish_bootfocus_smoke() -> void:
	if _bootfocus_failures == 0:
		print("PVLDS BOOTFOCUS SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS BOOTFOCUS SMOKE: FAIL (%d)" % _bootfocus_failures)
		get_tree().quit(1)


func _bootfocus_leg(panel: ClickableQuad) -> void:
	_bootfocus_expect(_room.focused_quad() == panel,
		"boot focus: the last-played card holds the boot focus (no input given)")
	_bootfocus_expect(panel.highlight_visible(),
		"boot focus: the boot-focused card's highlight frame shows")
	var mat: ShaderMaterial = _room._power_mat as ShaderMaterial
	var atlas: AtlasTexture = null
	if mat != null:
		atlas = mat.get_shader_parameter("face_tex") as AtlasTexture
	_bootfocus_expect(atlas != null and atlas.atlas == panel.current_texture(),
		"boot focus: the standing power overlay samples the face the card actually wears")
	var img: Image = get_viewport().get_texture().get_image()
	var dir: String = OS.get_environment("PVLDS_GRAB_DIR")
	if dir != "":
		img.save_png(dir.path_join("boot_focus.png"))
	var rect: Rect2i = _mimic_art_screen_rect(panel)
	# Judge the art's interior only: the focus frame rings the
	# rect's edge and the Launch button stands over its lower
	# rows - either would lend a flat fill a fake variance
	# (the first cut of this leg passed on exactly that).
	var inner: Rect2i = Rect2i(
		rect.position.x + rect.size.x / 4, rect.position.y,
		rect.size.x / 2, rect.size.y * 55 / 100)
	var sd: float = _bootfocus_region_stdev(img, inner)
	_bootfocus_expect(sd > 0.005,
		"boot focus: the boot-focused card's art renders its face, not a flat dark fill (interior stdev %.4f)" % sd)


## Luma stdev over a screen rect (stride 2): a flat fill -
## the placeholder, graded or not - has none; a rendered
## face (art or title card) always has some.
func _bootfocus_region_stdev(img: Image, rect: Rect2i) -> float:
	var n: int = 0
	var mean: float = 0.0
	var m2: float = 0.0
	var x: int = rect.position.x
	while x < rect.position.x + rect.size.x:
		var y: int = rect.position.y
		while y < rect.position.y + rect.size.y:
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var px: Color = img.get_pixel(x, y)
				var lum: float = 0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b
				n += 1
				var d1: float = lum - mean
				mean += d1 / float(n)
				m2 += d1 * (lum - mean)
			y += 2
		x += 2
	if n < 2:
		return 0.0
	return sqrt(m2 / float(n))


# -------------------------------------------------- tournament smoke

## --pvlds-smoke-tournament: the Tournament Room contract,
## against the harness's local WoVP stub (PVLDS_WOVP_BASE_URL
## - the league itself is never touched). Modes
## (PVLDS_WOVP_SMOKE_MODE):
##   full      - key in config, stub live: boards land,
##               his row renders highlighted, the not-owned
##               board cannot launch, REFRESH re-fetches,
##               the view enters/leaves without stranding
##               focus, and the SETUP panel's PASTE KEY /
##               TEST KEY work end to end.
##   nokey     - no key in config: the view is the plain
##               "add your key in SETUP" state, not an error.
##   failfetch - key, dead base URL, no cache: the view is
##               the failure state, never boards dressed
##               as live.
##   errbody   - key, stub refuses with HTTP 400 and words
##               of its own in the body: the words, not
##               just the code, stand on the state panel
##               (the HTTP400 round's negative control - a
##               client that discards response bodies
##               fails this leg by name).
##   errempty  - key, stub refuses with HTTP 400 and an
##               empty body: the panel falls back to the
##               bare code, gracefully.
##   cache     - a second boot in a full boot's home, base
##               URL dead: the saved boards stand with their
##               stamp, stated as last-good.
##   layout    - key, stub serving the worst-case boards
##               (a 10-digit score under a 24-character name,
##               a promotion line and a cut line): a score
##               renders whole - measured, and inked to its
##               final digit - and the Launch button, parked
##               in the face's footer band, never covers board
##               text. PVLDS_BOARD_NC=oldlayout restores the
##               pre-TR3 presentation and both layout legs
##               must fail by name.
## The honesty and his-row legs double as the negative
## controls' targets: PVLDS_WOVP_NC=clientid makes the
## client send Studio's id (the honesty leg fails by name);
## the stub's baduser variant renames his board rows (the
## his-row legs fail by name).
func _drive_tournament_smoke() -> void:
	match _tournament_smoke_mode:
		"nokey":
			_drive_tournament_state_mode(false)
		"failfetch", "errbody", "errempty":
			_drive_tournament_state_mode(true)
		"cache":
			_drive_tournament_cache_mode()
		"layout":
			_drive_tournament_layout()
		_:
			_drive_tournament_full()


## layout mode: the TR3 board-presentation contract against
## the stub's worst-case boards - the score column's law and
## the Launch footer's law, proven on measured layout and on
## rendered ink, not on how the code reads.
func _drive_tournament_layout() -> void:
	match _tournament_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_room._handle_rail("tournament")
				_tournament_expect(_room.tournament_active(), "layout: the TOURNAMENT stop raises the Tournament Room")
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 45000
				_tournament_smoke_phase = 1
			else:
				_tournament_smoke_wait += 1
				if _tournament_smoke_wait > 3600:
					_tournament_fail("the room never came up")
					_finish_tournament_smoke()
		1:
			if _wovp_boards_live and _wovp_client != null and not _wovp_client.is_busy() and _room._panels.size() >= 2:
				_tournament_leg_layout_boards()
				_layout_start_probes()
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 30000
				_tournament_smoke_phase = 2
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("layout: the boards never went live against the stub")
				_finish_tournament_smoke()
		2:
			if not _layout_probes_in_flight and _layout_probe_results.size() >= 2:
				_tournament_leg_layout()
				_finish_tournament_smoke()
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("layout: the board layout probes never landed")
				_finish_tournament_smoke()


func _tournament_leg_layout_boards() -> void:
	var rows: Array = _room.tournament_rows()
	_tournament_expect(rows.size() == 2, "layout: the two seeded worst-case challenges stand (got %d)" % rows.size())
	var owned_flags: Array = []
	for r: Variant in rows:
		owned_flags.append(bool((r as Dictionary).get("owned", false)))
	_tournament_expect(owned_flags == [true, true],
		"layout: both seeded boards are his tables (owned - footer and Launch stand on them)")
	# The redesign's shape (the GRAD FIX round, amending the
	# TR3 leg with cause): challenges stand as full art CARDS
	# at the card size, and ONE board stands beside the
	# centred card at the board's own size, paired with the
	# centred challenge.
	if _room._panels.size() >= 1:
		var psz: Vector2 = _room._panels[0].quad_size()
		_tournament_expect(psz == Vector2(0.62, 1.08),
			"layout size: tournament challenges stand as full art cards (%s), not board panels" % str(psz))
	var bs: Dictionary = _room.tournament_board_state()
	_tournament_expect(bool(bs.get("exists", false)) and (bs.get("size") as Vector2) == RoomSpecs.board_panel_size(),
		"layout size: one board stands at its own window (%s) beside the centred card" % str(bs.get("size", Vector2.ZERO)))
	if rows.size() >= 1:
		var ch0: WovpChallenge = (rows[0] as Dictionary).get("challenge") as WovpChallenge
		_tournament_expect(ch0 != null and str(bs.get("challenge_id", "")) == ch0.challenge_id,
			"layout pairing: the standing board carries the centred challenge's board")


func _layout_start_probes() -> void:
	_layout_probes_in_flight = true
	var rows: Array = _room.tournament_rows()
	var now_unix: int = int(Time.get_unix_time_from_system())
	for i: int in range(rows.size()):
		var rd: Dictionary = rows[i]
		var spec: Dictionary = RoomSpecs.tournament_board_spec(
			rd["challenge"] as WovpChallenge, bool(rd.get("owned", false)), _wovp_user_id, now_unix)
		_layout_probe_results[i] = await _room.board_layout_probe(spec)
	_layout_probes_in_flight = false


func _tournament_leg_layout() -> void:
	# The score leg, on the season board (probe 0): the
	# 10-digit score's measured need fits its column at the
	# rendered font, and the rendered texture inks the final
	# digit with nothing spilling past the column.
	var p0: Dictionary = _layout_probe_results.get(0, {})
	var target: Dictionary = {}
	for rv: Variant in (p0.get("rows", []) as Array):
		var rd: Dictionary = rv
		if str(rd.get("kind", "")) == "score" and str(rd.get("score_text", "")) == "1,234,567,890":
			target = rd
	_tournament_expect(not target.is_empty(), "layout: the seeded 10-digit score stands on the season board")
	if not target.is_empty():
		var need: float = float(target.get("score_need_px", 0.0))
		var allot: float = float(target.get("score_allot_px", 0.0))
		var ink: bool = _layout_digit_ink(p0.get("texture") as Texture2D, target)
		_tournament_expect(need <= allot + 1.0 and ink,
			"layout score: a 10-digit score renders whole, never clipped (need %.0fpx <= allot %.0fpx at %dpx font, final digit inked, no spill)" % [need, allot, int(target.get("font_px", 0))])
		# Keep the worst-case board's rendered face as a
		# grab beside the boot, for the human verdict.
		var grab_dir: String = OS.get_environment("PVLDS_GRAB_DIR")
		var gtex: Texture2D = p0.get("texture") as Texture2D
		if grab_dir != "" and gtex != null:
			var gimg: Image = gtex.get_image()
			if gimg != null and not gimg.is_empty():
				gimg.save_png(grab_dir.path_join("tournament_board_worst.png"))
	# The launch leg, on both boards: the button's rect
	# shares no ground with any row's rect, and the footer
	# band the face reserved contains the button whole.
	if OS.has_environment("PVLDS_LAYOUT_DEBUG"):
		var dbg: Dictionary = _layout_probe_results.get(0, {})
		for rv3: Variant in (dbg.get("rows", []) as Array):
			var rd3: Dictionary = rv3
			print("LAYOUTDBG row ", str(rd3.get("kind", "")), " rect ", str(rd3.get("rect", Rect2())))
		print("LAYOUTDBG footer ", str(dbg.get("footer_panel_rect", Rect2())), " launch ", str(dbg.get("launch_rect", Rect2())))
	var launch_ok: bool = true
	var launch_why: String = ""
	for idx: int in range(2):
		var p: Dictionary = _layout_probe_results.get(idx, {})
		if p.is_empty():
			launch_ok = false
			launch_why = "probe %d missing" % idx
			break
		var launch: Rect2 = p["launch_rect"]
		if not p.has("footer_panel_rect"):
			launch_ok = false
			launch_why = "board %d reserves no footer band" % idx
			break
		var footer: Rect2 = p["footer_panel_rect"]
		if not (footer.position.x <= launch.position.x + 0.002 and footer.position.y <= launch.position.y + 0.002
				and footer.end.x >= launch.end.x - 0.002 and footer.end.y >= launch.end.y - 0.002):
			launch_ok = false
			launch_why = "board %d: the button does not sit inside the footer band (button %s, band %s)" % [idx, str(launch), str(footer)]
			break
		for rv2: Variant in (p.get("rows", []) as Array):
			var rd2: Dictionary = rv2
			var rr: Rect2 = rd2["panel_rect"]
			if launch.intersects(rr):
				launch_ok = false
				launch_why = "board %d: the button covers a %s row" % [idx, str(rd2.get("kind", ""))]
				break
		if not launch_ok:
			break
	_tournament_expect(launch_ok,
		"layout launch: the LAUNCH footer never covers board text (dividers included), on season and battle-royale boards%s" % ("" if launch_ok else " - " + launch_why))


## Rendered-ink check for the layout score leg: within the
## score row's band, the score column's rightmost slice must
## carry text ink (the final digit), and the strip between
## the column's right edge and the face's edge must carry
## none (nothing ran off the board).
func _layout_digit_ink(tex: Texture2D, row: Dictionary) -> bool:
	if tex == null:
		return false
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return false
	var sr: Rect2 = row["score_rect"]
	var rr: Rect2 = row["rect"]
	var y0: int = clampi(int(rr.position.y) + 4, 0, img.get_height())
	var y1: int = clampi(int(rr.position.y + rr.size.y) - 4, 0, img.get_height())
	var dx1: int = clampi(int(sr.position.x + sr.size.x), 0, img.get_width())
	var dx0: int = clampi(dx1 - 18, 0, img.get_width())
	var ink: int = 0
	for x: int in range(dx0, dx1):
		for y: int in range(y0, y1):
			var px: Color = img.get_pixel(x, y)
			if px.r + px.g + px.b > 1.7:
				ink += 1
	var spill: int = 0
	for x2: int in range(mini(dx1 + 4, img.get_width()), img.get_width()):
		for y2: int in range(y0, y1):
			var px2: Color = img.get_pixel(x2, y2)
			if px2.r + px2.g + px2.b > 1.7:
				spill += 1
	return ink >= 3 and spill == 0


func _drive_tournament_full() -> void:
	match _tournament_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_room._handle_rail("tournament")
				_tournament_expect(_room.tournament_active(), "enter: the TOURNAMENT stop raises the Tournament Room")
				_tournament_expect(_room.focused_quad() == _room.rail_quad("tournament"),
					"enter: focus lands on the TOURNAMENT stop that was pressed")
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 45000
				_tournament_smoke_phase = 1
			else:
				_tournament_smoke_wait += 1
				if _tournament_smoke_wait > 3600:
					_tournament_fail("the room never came up")
					_finish_tournament_smoke()
		1:
			if _wovp_boards_live and _wovp_client != null and not _wovp_client.is_busy():
				_tournament_leg_boards()
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 20000
				_tournament_smoke_phase = 2
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("the boards never went live against the stub")
				_finish_tournament_smoke()
		2:
			# The REFRESH leg's verdict: the stub saw a second
			# search after the rail press in _tournament_leg_boards.
			if _tournament_search_count() >= 2 and _wovp_client != null and not _wovp_client.is_busy() and _room.wall_ready:
				_tournament_expect(true, "refresh: REFRESH on the rail re-fetches the boards")
				_tournament_smoke_wait = 0
				_tournament_smoke_phase = 3
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("refresh: REFRESH never produced a second search")
				_finish_tournament_smoke()
		3:
			_tournament_smoke_wait += 1
			if _room.wall_ready and _tournament_smoke_wait >= 4:
				_tournament_leg_rendered()
				_tournament_smoke_wait = 0
				_tournament_smoke_phase = 13
		13:
			# The re-pair (the redesign's core law): stepping
			# to the not-owned challenge re-pairs the standing
			# board - same place, same size, its content; the
			# pairing carries no Launch.
			if _tournament_smoke_wait == 0 and _room._panels.size() >= 5:
				_room._set_focused(_room._panels[4])
			_tournament_smoke_wait += 1
			var bs13: Dictionary = _room.tournament_board_state()
			var rows13: Array = _room.tournament_rows()
			var ch4: WovpChallenge = (rows13[4] as Dictionary).get("challenge") as WovpChallenge if rows13.size() >= 5 else null
			if ch4 != null and str(bs13.get("challenge_id", "")) == ch4.challenge_id and bool(bs13.get("has_board_texture", false)):
				_tournament_expect(not bool(bs13.get("owned", true)),
					"pairing: the board re-pairs to the not-owned challenge - board shown, no Launch")
				_grad_save_grab("tournament_pairing_unowned.png")
				_room._set_focused(_room._panels[0])
				_tournament_smoke_wait = 0
				_tournament_smoke_phase = 4
			elif _tournament_smoke_wait > 900:
				_tournament_fail("pairing: the standing board never re-paired to the not-owned challenge")
				_finish_tournament_smoke()
		4:
			# The SETUP panel's WoVP legs. Clear the saved key
			# first (memory + file), so the paste leg proves
			# the panel's own save, not the harness's config.
			_config.wovp_api_key = ""
			_config.save_to_disk()
			_room._xr_enabled = true
			_room._activate(_room.rail_quad("desk"))
			_tournament_smoke_wait = 0
			_tournament_smoke_phase = 5
		5:
			_tournament_smoke_wait += 1
			if _tournament_smoke_wait >= 3:
				_tournament_expect(_room.is_setup_panel_up(), "panel: SETUP opens the in-room panel")
				_tournament_expect(_room.setup_panel_wovp_paste_quad() != null and _room.setup_panel_wovp_test_quad() != null,
					"panel: PASTE KEY and TEST KEY stand on the panel")
				DisplayServer.clipboard_set("PVLDS-WOVP-SENTINEL-KEY-00000001")
				_tournament_smoke_wait = 0
				_tournament_smoke_phase = 6
			elif _tournament_smoke_wait > 600:
				_tournament_fail("panel: the SETUP panel never stood")
				_finish_tournament_smoke()
		6:
			_tournament_smoke_wait += 1
			if _tournament_smoke_wait >= 6:
				_room._activate(_room.setup_panel_wovp_paste_quad())
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 20000
				_tournament_smoke_phase = 7
		7:
			var reloaded: PvldsConfig = PvldsConfig.new()
			if reloaded.load_from_disk() and reloaded.wovp_api_key == "PVLDS-WOVP-SENTINEL-KEY-00000001":
				_tournament_expect(true, "panel paste: PASTE KEY saved the clipboard's key into the config file")
				_tournament_expect(_room.setup_panel_message().contains("saved"),
					"panel paste: the panel says the key saved")
				_tournament_smoke_phase = 8
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("panel paste: the pasted key never reached the config file (panel says: %s)" % _room.setup_panel_message())
				_finish_tournament_smoke()
		8:
			if _wovp_client != null and not _wovp_client.is_busy():
				_room._activate(_room.setup_panel_wovp_test_quad())
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 20000
				_tournament_smoke_phase = 9
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("panel test: the client never went idle for TEST KEY")
				_finish_tournament_smoke()
		9:
			if _room.setup_panel_message().contains("Fixture Player"):
				_tournament_expect(true, "panel test: TEST KEY names whose key it is, on the panel")
				# The length legs (the HTTP400 round): paste a
				# key WoVP's 32-character rule refuses. It
				# still saves - with the warning on the panel -
				# and TEST KEY then answers locally: the stub
				# must see no new request.
				_tournament_validate_count_seen = _tournament_validate_count()
				DisplayServer.clipboard_set("SHORTKEY123")
				_room._activate(_room.setup_panel_wovp_paste_quad())
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 20000
				_tournament_smoke_phase = 10
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("panel test: TEST KEY never named the key's owner (panel says: %s)" % _room.setup_panel_message())
				_finish_tournament_smoke()
		10:
			var reloaded2: PvldsConfig = PvldsConfig.new()
			if reloaded2.load_from_disk() and reloaded2.wovp_api_key == "SHORTKEY123":
				_tournament_expect(true, "panel length: a wrong-length key still saves into the config file")
				_tournament_expect(_room.setup_panel_message().contains("11 characters - WoVP keys are 32"),
					"panel length: the paste warns in words - that key is 11 characters, WoVP keys are 32 (panel says: %s)" % _room.setup_panel_message())
				_room._activate(_room.setup_panel_wovp_test_quad())
				_tournament_smoke_wait = 0
				_tournament_smoke_phase = 11
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("panel length: the short key never reached the config file (panel says: %s)" % _room.setup_panel_message())
				_finish_tournament_smoke()
		11:
			_tournament_smoke_wait += 1
			if _tournament_smoke_wait >= 6:
				_tournament_expect(_room.setup_panel_message().contains("11 characters - WoVP keys are 32"),
					"panel length: TEST KEY refuses the short key in words, on the panel (panel says: %s)" % _room.setup_panel_message())
				_tournament_expect(_tournament_validate_count() == _tournament_validate_count_seen,
					"panel length: the refused test sent nothing - the stub saw no new validate request")
				# Restore the good key before leaving: the
				# cache boot reuses this home, and its
				# trusted-identity leg needs the config and
				# the cache to name the same key.
				DisplayServer.clipboard_set("PVLDS-WOVP-SENTINEL-KEY-00000001")
				_room._activate(_room.setup_panel_wovp_paste_quad())
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 20000
				_tournament_smoke_phase = 12
		12:
			var reloaded3: PvldsConfig = PvldsConfig.new()
			if reloaded3.load_from_disk() and reloaded3.wovp_api_key == "PVLDS-WOVP-SENTINEL-KEY-00000001":
				_tournament_expect(true, "panel length: the good key is restored for the boots that reuse this home")
				_room._activate(_room.setup_panel_back_quad())
				_finish_tournament_smoke()
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("panel length: the good key was never restored (panel says: %s)" % _room.setup_panel_message())
				_finish_tournament_smoke()


func _tournament_leg_boards() -> void:
	var rows: Array = _room.tournament_rows()
	_tournament_expect(rows.size() == 5, "boards: five live challenges stand on the wall (got %d)" % rows.size())
	var all_challenges: bool = rows.size() == 5
	var owned_flags: Array = []
	for r: Variant in rows:
		var rd: Dictionary = r
		if str(rd.get("kind", "")) != "challenge":
			all_challenges = false
		owned_flags.append(bool(rd.get("owned", false)))
	_tournament_expect(all_challenges, "boards: every panel is a challenge board (no state panel among live data)")
	_tournament_expect(owned_flags == [true, true, true, true, false],
		"boards: four challenges matched his library by VPS id; the fifth is not owned")
	if rows.size() == 5:
		var first_game: GameEntry = (rows[0] as Dictionary).get("game") as GameEntry
		_tournament_expect(first_game != null and first_game.game_id == "aT_GONvw",
			"boards: the season board is his Addams Family (matched by its VPS game id)")
		var last_game: GameEntry = (rows[4] as Dictionary).get("game") as GameEntry
		_tournament_expect(last_game != null and last_game.game_id.begins_with("wovp:none:"),
			"boards: the not-owned board stands on a synthetic, unlaunchable entry")
		var season: WovpChallenge = (rows[0] as Dictionary).get("challenge") as WovpChallenge
		_tournament_expect(season != null and season.his_row(_wovp_user_id) != null and season.his_row(_wovp_user_id).position == 6,
			"his row: his scoreboard row is identified by the validated userId, mid-board")
	_tournament_expect(_room._banner_line().contains("updated"),
		"boards: the banner stamps when the boards landed")
	# The honesty leg: the stub recorded how the client
	# announced itself. PVLDS_WOVP_NC=clientid must fail this
	# by name.
	var entries: Array = _tournament_stub_entries()
	var saw_validate: bool = false
	var saw_search: bool = false
	var honest: bool = true
	for e: Variant in entries:
		var ed: Dictionary = e
		if str(ed.get("x_client_id", "")) != "pvlds":
			honest = false
		if str(ed.get("path", "")).ends_with("validate-apikey"):
			saw_validate = true
		if str(ed.get("path", "")).ends_with("challenges/search"):
			saw_search = true
			if not bool(ed.get("authorization_present", false)):
				honest = false
	_tournament_expect(saw_validate and saw_search, "honesty: the stub saw both read-side calls (validate, then search)")
	_tournament_expect(honest, "honesty: the client identified itself to WoVP as pvlds on every call, and the key rode only in the search's Authorization header")
	_tournament_expect(_room.rail_quad("wovp_refresh").pick_enabled,
		"refresh: REFRESH is a live stop while the Tournament Room stands")
	# Fire the refresh for phase 2's count.
	_room._activate(_room.rail_quad("wovp_refresh"))


func _tournament_leg_rendered() -> void:
	# His row, in the rendered pixels: the standing board's
	# texture carries a full row on the accent ground
	# (CardFace's board accent). The NC that renames his
	# rows (the stub's baduser variant) leaves no accent row
	# to find - this leg fails by name there. (Amended in the
	# GRAD FIX round with cause: the board's texture lives on
	# the standing board beside the centred card now, not on
	# a board panel.)
	if _room._panels.size() >= 5:
		var rows: Array = _room.tournament_rows()
		var bs: Dictionary = _room.tournament_board_state()
		var season0: WovpChallenge = (rows[0] as Dictionary).get("challenge") as WovpChallenge if rows.size() >= 1 else null
		_tournament_expect(season0 != null and str(bs.get("challenge_id", "")) == season0.challenge_id and bool(bs.get("owned", false)),
			"pairing: the standing board pairs with the centred challenge (his season table, owned)")
		_tournament_expect(bool(bs.get("has_board_texture", false)),
			"pairing: the standing board carries its rendered board face")
		_grad_save_grab("tournament_pairing_owned.png")
		var tex: Texture2D = bs.get("texture") as Texture2D
		var accent_px: int = 0
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and not img.is_empty():
				# The rows' region only: the band above it is a
				# palette color that can sit in the accent
				# window, and it must not be able to fake this
				# leg - his row or nothing.
				for x: int in range(0, img.get_width(), 3):
					for y: int in range(150, mini(740, img.get_height()), 3):
						var px: Color = img.get_pixel(x, y)
						if px.r >= 0.48 and px.r <= 0.64 and px.g >= 0.30 and px.g <= 0.47 and px.b <= 0.16:
							accent_px += 1
		_tournament_expect(accent_px >= 60,
			"his row: the rendered season board carries his row on the accent ground (%d accent samples)" % accent_px)
		_tournament_expect(not _room._panel_launches[4].visible and not _room._panel_launches[4].pick_enabled,
			"not-owned: the not-owned board carries no Launch button")
		_tournament_expect(_room._panel_launches[0].visible and _room._panel_launches[0].pick_enabled,
			"boards: an owned board keeps its Launch button")
		# A on the not-owned board: nothing starts, nothing
		# opens - the board is information, not a door.
		_room._set_focused(_room._panels[4])
		_room._a_press()
		_tournament_expect(not _launch_pending and _room._mode == "wall" and _room.tournament_active(),
			"not-owned: A on a not-owned board starts nothing and opens nothing")
		# Focus is never stranded in the view: DOWN from a
		# board walks to the rail by the room's own ladder
		# (five boards stand two rows deep in this column:
		# board, board, rail).
		_room._set_focused(_room._panels[0])
		var reached_rail: bool = false
		for i: int in range(3):
			_room._move_focus(Vector2(0.0, 1.0))
			if _nav_key_of(_room.focused_quad()) != "":
				reached_rail = true
				break
			_tournament_expect(_room._panels.has(_room.focused_quad()),
				"navigation: DOWN from a board stays on boards until the rail")
		_tournament_expect(reached_rail,
			"navigation: DOWN from a board reaches the rail - focus is never stranded in the view")
	# Leaving: a filter press restores the library wall,
	# focus on the pressed stop, REFRESH disarmed.
	_room._handle_rail("filter:all")
	_tournament_expect(not _room.tournament_active() and _room.tournament_rows().is_empty(),
		"leaving: a filter press leaves the Tournament Room")
	_tournament_expect(_room.focused_quad() == _room.rail_quad("filter:all"),
		"leaving: focus lands on the filter stop that was pressed")
	_tournament_expect(not _room.rail_quad("wovp_refresh").pick_enabled,
		"leaving: REFRESH is not a stop over the library wall")


## nokey / failfetch share one shape: ONE state panel, its
## lines in plain words, no launch anywhere, and a banner
## that names the state.
func _drive_tournament_state_mode(expect_failure: bool) -> void:
	match _tournament_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_room._handle_rail("tournament")
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 30000
				_tournament_smoke_phase = 1
			else:
				_tournament_smoke_wait += 1
				if _tournament_smoke_wait > 3600:
					_tournament_fail("the room never came up")
					_finish_tournament_smoke()
		1:
			var ready: bool = _room.wall_ready and (not expect_failure or _wovp_fetch_error != "")
			if ready:
				var rows: Array = _room.tournament_rows()
				_tournament_expect(rows.size() == 1 and str((rows[0] as Dictionary).get("kind", "")) == "state",
					"state: exactly one state panel stands (got %d rows)" % rows.size())
				var lines: Array = (rows[0] as Dictionary).get("lines", []) if rows.size() == 1 else []
				var joined: String = ""
				for lv: Variant in lines:
					joined += str(lv) + " "
				if expect_failure:
					_tournament_expect(joined.contains("Could not reach WoVP"),
						"state: the failure state says WoVP could not be reached, in plain words")
					_tournament_expect(_room._banner_line().contains("could not reach WoVP"),
						"state: the banner names the failure - no boards dressed as live")
					if _tournament_smoke_mode == "errbody":
						# The HTTP400 round's negative control:
						# the stub refused with words of its
						# own, and the words - not just the
						# code - must stand on the panel. A
						# client that discards response
						# bodies fails this leg by name.
						_tournament_expect(joined.contains("WOVP-STUB-REFUSAL"),
							"error body: WoVP's own words for its refusal stand on the state panel, not just the HTTP code")
					elif _tournament_smoke_mode == "errempty":
						_tournament_expect(joined.contains("HTTP 400") and not joined.contains("WoVP said"),
							"error body: an empty refusal falls back to the bare HTTP code, gracefully")
				else:
					_tournament_expect(joined.contains("No WoVP key yet"),
						"state: the no-key state says to add the key in SETUP, plainly")
					_tournament_expect(_room._banner_line().contains("no WoVP key yet"),
						"state: the banner names the no-key state")
				_tournament_expect(_room._panels.size() == 1 and not _room._panel_launches[0].visible,
					"state: the state panel carries no Launch button")
				_finish_tournament_smoke()
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("the state never settled (mode %s)" % _tournament_smoke_mode)
				_finish_tournament_smoke()


func _drive_tournament_cache_mode() -> void:
	match _tournament_smoke_phase:
		0:
			if _room != null and _room.visible and _room.wall_ready:
				_tournament_expect(_wovp_challenges.size() == 5 and _wovp_fetched_at > 0 and not _wovp_boards_live,
					"cache: the boot loaded the saved boards (5 challenges, stamped, not live)")
				_tournament_expect(_wovp_user_id == "fixture-user-1",
					"cache: the saved identity is trusted - its key hash matches the saved key")
				_room._handle_rail("tournament")
				_tournament_smoke_deadline_msec = Time.get_ticks_msec() + 30000
				_tournament_smoke_phase = 1
			else:
				_tournament_smoke_wait += 1
				if _tournament_smoke_wait > 3600:
					_tournament_fail("the room never came up (cache mode)")
					_finish_tournament_smoke()
		1:
			if _wovp_fetch_error != "":
				var rows: Array = _room.tournament_rows()
				_tournament_expect(rows.size() == 5,
					"cache: the saved boards stand on the wall (got %d rows)" % rows.size())
				_tournament_expect(_room._banner_line().contains("last good boards"),
					"cache: the banner says these are the last good boards - the failed refresh is stated, not hidden")
				_finish_tournament_smoke()
			elif Time.get_ticks_msec() > _tournament_smoke_deadline_msec:
				_tournament_fail("cache: the dead-URL refresh never reported its failure")
				_finish_tournament_smoke()


func _tournament_stub_entries() -> Array:
	var path: String = OS.get_environment("PVLDS_WOVP_STUB_LOG")
	if path == "" or not FileAccess.file_exists(path):
		return []
	var out: Array = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var parsed: Variant = JSON.parse_string(line.strip_edges())
		if parsed is Dictionary:
			out.append(parsed)
	return out


func _tournament_search_count() -> int:
	var n: int = 0
	for e: Variant in _tournament_stub_entries():
		if str((e as Dictionary).get("path", "")).ends_with("challenges/search"):
			n += 1
	return n


func _tournament_validate_count() -> int:
	var n: int = 0
	for e: Variant in _tournament_stub_entries():
		if str((e as Dictionary).get("path", "")).ends_with("validate-apikey"):
			n += 1
	return n


func _tournament_expect(cond: bool, label: String) -> void:
	if cond:
		print("  ok - tournament smoke: ", label)
	else:
		_tournament_fail(label)


func _tournament_fail(label: String) -> void:
	_tournament_smoke_failures += 1
	printerr("  FAIL - tournament smoke: ", label)


func _finish_tournament_smoke() -> void:
	if _tournament_smoke_failures == 0:
		print("PVLDS TOURNAMENT SMOKE: PASS")
		get_tree().quit(0)
	else:
		printerr("PVLDS TOURNAMENT SMOKE: FAIL (%d)" % _tournament_smoke_failures)
		get_tree().quit(1)


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
				# The WoVP section (the Tournament Room round):
				# a masked key field; Save key lands the key in
				# the config FILE on the spot; Test key answers
				# through Main's client - the harness points it
				# at its stub (PVLDS_WOVP_BASE_URL), so phase 2
				# waits for the verdict on the status line.
				_desk_expect(_desk._wovp_edit != null and _desk._wovp_edit.secret,
					"wovp: the desk's key field exists and is masked (it is a secret)")
				_desk_expect(_desk._wovp_save_button != null and _desk._wovp_test_button != null,
					"wovp: the desk has Save key and Test key")
				_desk._wovp_edit.text = "PVLDS-WOVP-SENTINEL-KEY-00000001"
				_desk._wovp_save_button.pressed.emit()
				var wovp_after: PvldsConfig = PvldsConfig.new()
				_desk_expect(wovp_after.load_from_disk() and wovp_after.wovp_api_key == "PVLDS-WOVP-SENTINEL-KEY-00000001",
					"wovp: Save key writes the key to the config FILE immediately, no Save & Scan")
				_desk_expect(_desk._wovp_label.text.contains("saved"),
					"wovp: the desk says the key saved, in words")
				if OS.has_environment("PVLDS_WOVP_BASE_URL"):
					_desk._wovp_test_button.pressed.emit()
					_desk_smoke_wait = 0
					_desk_smoke_phase = 2
				else:
					print("  info - desk smoke: no PVLDS_WOVP_BASE_URL in env - the Test key leg belongs to the harness run")
					_finish_desk_smoke()
		2:
			_desk_smoke_wait += 1
			if _desk._wovp_label.text.contains("Fixture Player"):
				_desk_expect(true, "wovp: Test key names whose key it is, on the status line")
				_desk_smoke_phase = 3
			elif _desk_smoke_wait == 240 and _wovp_client != null and not _wovp_client.is_busy():
				# The save's own board fetch may have held the
				# client when the first press landed - press
				# again now that it is idle.
				_desk._wovp_test_button.pressed.emit()
			elif _desk_smoke_wait > 1200:
				_desk_expect(false, "wovp: Test key never answered (status line: %s)" % _desk._wovp_label.text)
				_finish_desk_smoke()
		3:
			# The 32-character rule (the HTTP400 round): a
			# wrong-length key still SAVES - with the warning
			# on the line - but Test refuses it in words and
			# sends nothing; the stub's request log is the
			# witness (its count must not move).
			_desk_expect(OS.has_environment("PVLDS_WOVP_STUB_LOG"),
				"wovp: the harness gave the desk smoke the stub's request log to witness against")
			var stub_requests_before: int = _desk_stub_request_count()
			_desk._wovp_edit.text = "SHORTKEY123"
			_desk._wovp_save_button.pressed.emit()
			var short_after: PvldsConfig = PvldsConfig.new()
			_desk_expect(short_after.load_from_disk() and short_after.wovp_api_key == "SHORTKEY123",
				"wovp: a wrong-length key still saves (his pasteboard, his call)")
			_desk_expect(_desk._wovp_label.text.contains("11 characters - WoVP keys are 32"),
				"wovp: the save line warns about the key's length, in words")
			_desk._wovp_test_button.pressed.emit()
			_desk_expect(_desk._wovp_label.text.contains("11 characters - WoVP keys are 32"),
				"wovp: Test key refuses a wrong-length key in plain words")
			_desk_expect(_desk_stub_request_count() == stub_requests_before,
				"wovp: the refused save and test sent nothing - the stub saw no new request")
			# Leave the desk as the passing legs left it.
			_desk._wovp_edit.text = "PVLDS-WOVP-SENTINEL-KEY-00000001"
			_desk._wovp_save_button.pressed.emit()
			_finish_desk_smoke()


## How many requests the harness's WoVP stub has logged so
## far (the desk legs' no-send witness). The stub never logs
## key values - paths only.
func _desk_stub_request_count() -> int:
	var path: String = OS.get_environment("PVLDS_WOVP_STUB_LOG")
	if path == "" or not FileAccess.file_exists(path):
		return 0
	var n: int = 0
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if JSON.parse_string(line.strip_edges()) is Dictionary:
			n += 1
	return n


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
		elif elapsed > total * QUITWARM_PER_ITEM_BUDGET_MSEC:
			_quitwarm_fired = true
			printerr("PVLDS QUITWARM: FAIL - the warm did not drain in %ds (cached %d of %d)" % [total * QUITWARM_PER_ITEM_BUDGET_MSEC / 1000, cached, total])
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
	_expect(warmer.last_pass_items == 1, "the warm pass performed one flat extraction and nothing else (the swap round: there is no phase two)", failures)
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
	# extraction at all (the swap round: flat is the only queue -
	# there is no layer set to warm behind it).
	var warmer3: ArtWarmer = ArtWarmer.new()
	var skip_games: Array[GameEntry] = [neg_entry, ok_entry]
	warmer3.warm_library(skip_games)
	waited = 0
	while not warmer3.is_idle() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	_expect(warmer3.is_idle() and warmer3.last_pass_items == 0,
		"the warmer skips stamped negatives and cached flat art entirely", failures)
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
	# the On image is cached beside the face (the pair On) for
	# the power-on crossfade, and the two halves may disagree
	# in shape entirely (here
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
	# The swap round's pair cache: the same extraction wrote the
	# On half beside the face, panel-fitted like the face
	# (800x1000 -> 512x640), and serves it while the face cache
	# it belongs to is current.
	_expect(ArtProvider.has_pair_on(b2s_pair), "the pair extraction caches its On half beside the face", failures)
	var pair_on_img: Image = Image.new()
	_expect(pair_on_img.load(ArtProvider.pair_on_path_for(b2s_pair)) == OK
		and pair_on_img.get_width() == 512 and pair_on_img.get_height() == 640,
		"the cached On half is the On image at panel fit (800x1000 -> 512x640)", failures)
	var pair_entry: GameEntry = GameEntry.new()
	pair_entry.art_source_path = b2s_pair
	_expect(pair_entry.ensure_art() == pair_cache and pair_entry.pair_on_art() == ArtProvider.pair_on_path_for(b2s_pair),
		"a pair game serves its On half for the power-on crossfade", failures)
	var nonpair_entry: GameEntry = GameEntry.new()
	nonpair_entry.art_source_path = b2s_ok
	_expect(nonpair_entry.ensure_art() != "" and nonpair_entry.pair_on_art() == "" and not ArtProvider.has_pair_on(b2s_ok),
		"a plain backglass has no pair On half (it takes the mimic grade)", failures)
	# The graduation's author shots: the db's tableFile imgUrl is
	# the card face's PRIMARY source. A landed shot outranks
	# every legacy source; a recorded-negative shot falls
	# through to the legacy chain for good; an unlanded shot
	# (no record either way) leaves the legacy face standing
	# until the fetcher's verdict lands. Under a shot face the
	# backglass stays available - it is the power-on's subject.
	var shot_url: String = "https://example.invalid/shots/graduation-fixture.webp"
	var shot_entry: GameEntry = GameEntry.new()
	shot_entry.art_source_path = b2s_ok
	shot_entry.shot_url = shot_url
	_expect(shot_entry.face_path() == shot_entry.ensure_art() and not shot_entry.has_shot_face(),
		"an unlanded author shot leaves the legacy face standing", failures)
	var grad_shot_img: Image = mk_img.call(300, 534) as Image
	_expect(ArtProvider.store_shot_bytes(shot_url, grad_shot_img.save_png_to_buffer()) != "",
		"a fetched author shot stores into the shot cache", failures)
	_expect(ArtProvider.shot_is_cached(shot_url) and ArtProvider.shot_outcome(shot_url) == ArtProvider.STATUS_OK,
		"the stored shot records its ok outcome", failures)
	_expect(shot_entry.face_path() == ArtProvider.shot_cache_path_for(shot_url) and shot_entry.has_shot_face(),
		"a landed author shot outranks the backglass as the card face", failures)
	_expect(shot_entry.backglass_face_path() == shot_entry.ensure_art() and shot_entry.backglass_face_path() != "",
		"the backglass face stays available under a shot face (the power-on's subject)", failures)
	_expect(shot_entry.pair_on_art() == "",
		"a shot face does not invent a pair crossfade (the pair gate reads the backglass, not the face)", failures)
	var shot_neg_url: String = "https://example.invalid/shots/graduation-missing.webp"
	ArtProvider.record_shot_outcome(shot_neg_url, ArtProvider.STATUS_NO_IMAGE)
	var shot_neg_entry: GameEntry = GameEntry.new()
	shot_neg_entry.art_source_path = b2s_ok
	shot_neg_entry.shot_url = shot_neg_url
	_expect(shot_neg_entry.face_path() == shot_neg_entry.ensure_art() and not shot_neg_entry.has_shot_face(),
		"a recorded-negative author shot falls through to the legacy face for good", failures)
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

	# --- Pair halves under the flat reader (kept flat coverage
	# from the retired flicker sections): a pair file's face is
	# its OFF half in its own shape, a plain image in the same
	# file beats a decoy pair entirely, and the library's
	# median art aspect feeds the wall's sizing. The snippet
	# layers these fixtures once also exercised are GONE (the
	# swap round): nothing extracts, caches, or classifies
	# bulbs any more - the power-on is the mimic's grade, and
	# a pair's On half rides as a face texture (pair_on, above).
	var fl_solid: Callable = func(w: int, h: int, c: Color) -> Image:
		var im: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		im.fill(c)
		return im
	var fl_glass: Image = fl_solid.call(1000, 800, Color(0.06, 0.08, 0.19)) as Image
	var amber_img: Image = fl_solid.call(300, 120, Color(1.0, 0.75, 0.16)) as Image
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

	# --- The wart, deep-fixed (flicker fix round 2) + warmer
	# phase two. The wart: a .directb2s whose designated
	# DMDImage is corrupt and whose real glass lives in a
	# non-designated blob (a ReelImage). Under the split
	# readers the flat path convicted the file at the
	# designated step and never reached its blob fallback -
	# flat FAILED, face fell through to another source -
	# reader, whose narrower designated search saw nothing,
	# fell back and found the base, so its lamps composited
	# over a stranger's face. One finder now: a corrupt
	# designated element does not veto the fallback, and
	# the game wears its own glass.
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
	var wart_entry: GameEntry = GameEntry.new()
	wart_entry.art_source_path = b2s_wart
	_expect(wart_entry.ensure_art() == wart_face and wart_entry.backglass_source() == b2s_wart and wart_entry.pair_on_art() == "",
		"wart: the entry's face is its own backglass (and it is no pair - it takes the mimic grade)", failures)
	# The warmer on a bulb-bearing file: the flat extraction
	# is the whole job (the swap round - there is no layer set
	# to prefetch behind it), and stamped outcomes are never
	# re-queued. Once per game ever: a second pass extracts
	# nothing - the stamp stands.
	var pf_text: String = "<DirectB2SData><Images><BackglassImage Value=\"" + Marshalls.raw_to_base64(fl_glass.save_png_to_buffer()) + "\" /></Images><Illumination>"
	pf_text += _b2s_bulb_xml("Backglass", "1", 60, 60, 300, 120, amber_img)
	pf_text += "</Illumination></DirectB2SData>"
	var b2s_pf: String = art_dir.path_join("Prefetch Table.directb2s")
	_expect(_write_text_file(b2s_pf, pf_text), "prefetch fixture written", failures)
	var pf_entry: GameEntry = GameEntry.new()
	pf_entry.art_source_path = b2s_pf
	var pf_warmer: ArtWarmer = ArtWarmer.new()
	pf_warmer.warm_library([pf_entry])
	var pf_waited: int = 0
	while not pf_warmer.is_idle() and pf_waited < 30000:
		OS.delay_msec(20)
		pf_waited += 20
	_expect(pf_warmer.is_idle() and pf_warmer.last_pass_items == 1 and ArtProvider.is_cached(b2s_pf),
		"warmer: a bulb-bearing file warms with one flat extraction and nothing behind it", failures)
	var pf_warmer2: ArtWarmer = ArtWarmer.new()
	pf_warmer2.warm_library([pf_entry])
	pf_waited = 0
	while not pf_warmer2.is_idle() and pf_waited < 20000:
		OS.delay_msec(20)
		pf_waited += 20
	_expect(pf_warmer2.is_idle() and pf_warmer2.last_pass_items == 0,
		"warmer: stamped outcomes are never re-queued", failures)
	# The wart under the warmer: a fresh wart file warms
	# flat in the pass (the unified finder reads its base
	# through the blob fallback, where the split readers
	# stamped it FAILED).
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
	_expect(wart_warmer.is_idle() and wart_warmer.last_pass_items == 1
		and ArtProvider.outcome_for_source(b2s_wart2) == ArtProvider.STATUS_OK,
		"warmer: the wart warms flat in one pass", failures)

	# --- The swap (mimic round): the power-on's pure curves,
	# the retired stack's on-disk cleanup, and stale-index
	# tolerance. The curves are pinned here; the rendered
	# behavior is the mimic shot suite's subject.
	_expect(RoomView.mimic_power_at(0.0) == 0.0 and RoomView.mimic_power_at(0.48) == 1.0
		and RoomView.mimic_power_at(RoomView.POWER_CASCADE_SEC) == 1.0,
		"mimic envelope: dark at rest, full by 0.48s, held to the cascade's end", failures)
	_expect(absf(RoomView.mimic_power_at(0.34) - 0.62) < 0.001 and RoomView.mimic_power_at(0.34) < RoomView.mimic_power_at(0.27),
		"mimic envelope: the sag dips to 0.62 at 0.34s, below the third catch", failures)
	_expect(RoomView.pair_mix_at(0.2) == 0.0 and RoomView.pair_mix_at(RoomView.POWER_CASCADE_SEC) == 1.0
		and absf(RoomView.pair_mix_at(0.725) - 0.5) < 0.001,
		"pair crossfade: Off holds through the catch, smoothstepped to full On at the cascade's end", failures)
	# The warmer's prune keeps a pair's cached On half (it maps
	# to the face's stamp, like the face itself). Re-extract
	# first: earlier legs' warmers pruned to their own
	# libraries, exactly as prune is meant to.
	_expect(ArtProvider.extract_directb2s_image(b2s_pair) != "" and ArtProvider.has_pair_on(b2s_pair),
		"the pair re-extracts with its On half under the current reader", failures)
	var pair_keep_warmer: ArtWarmer = ArtWarmer.new()
	pair_keep_warmer.warm_library([pair_entry])
	_expect(FileAccess.file_exists(ArtProvider.pair_on_path_for(b2s_pair)),
		"the warmer's prune keeps a pair's cached On half", failures)
	# Stale layer records: an index carrying the retired stack's
	# "L" keys loads without a murmur (no reader consults them
	# any more), and the next prune erases them; a legacy
	# layers tree left on disk is wiped by the same prune.
	var swap_idx: Dictionary = {}
	var swap_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ArtProvider.INDEX_PATH))
	if swap_parsed is Dictionary:
		swap_idx = swap_parsed as Dictionary
	swap_idx["L" + ArtProvider.stamp_key_for(b2s_pair)] = {"status": "ok", "lv": 4}
	_expect(_write_text_file(ArtProvider.INDEX_PATH, JSON.stringify(swap_idx)), "stale layer key planted", failures)
	ArtProvider.reload_index()
	_expect(ArtProvider.outcome_for(b2s_pair) == ArtProvider.STATUS_OK,
		"a stale layer key in the index breaks no flat reader", failures)
	var cache_root: DirAccess = DirAccess.open("user://art_cache")
	if cache_root != null and not cache_root.dir_exists("layers"):
		cache_root.make_dir("layers")
	_expect(_write_text_file("user://art_cache/layers/orphan.txt", "retired"), "legacy layers tree planted", failures)
	var swap_warmer: ArtWarmer = ArtWarmer.new()
	swap_warmer.warm_library([pair_entry])
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://art_cache/layers")),
		"the first prune wipes the retired stack's orphaned layer cache", failures)
	var swap_after: Variant = JSON.parse_string(FileAccess.get_file_as_string(ArtProvider.INDEX_PATH))
	_expect(swap_after is Dictionary and not (swap_after as Dictionary).has("L" + ArtProvider.stamp_key_for(b2s_pair))
		and ArtProvider.outcome_for(b2s_pair) == ArtProvider.STATUS_OK,
		"the prune erases stale layer keys and leaves flat outcomes standing", failures)

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
				{"id": "fx-qq-2", "version": "2.0", "tableFormat": "VPX", "authors": ["Zippy"], "createdAt": 1710000000, "features": [], "imgUrl": "https://example.invalid/shots/quasar-queen-v2.webp", "urls": [{"url": "https://www.vpforums.org/index.php?app=downloads&showfile=19031"}]},
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
		_expect(reg2 != null and reg2.img_url == "https://example.invalid/shots/quasar-queen-v2.webp",
			"the scanner captures the matched tableFile's imgUrl onto the build (the author shot's address)", failures)
		_expect(mt_qq.shot_url == "https://example.invalid/shots/quasar-queen-v2.webp",
			"the entry's shot_url is its current build's imgUrl (the v2.0 build is current: newest date)", failures)
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

	# Edition referee (the edition-referee round, 2026-10-29):
	# the VPS db catalogs trims as separate games - "Bolt/DC",
	# "Bolt/DC (Pro)", "Bolt/DC (LUCI Premium)" - and a file
	# wearing the edition words outside the db's parentheses
	# used to match nothing: the LUCI build's download slug
	# undershoots ("boltdc-luci"), the cleaned title strips the
	# words (all trims share "boltdc"), and a team tag after the
	# maker parens breaks the title guess. The referee reads the
	# file's FULL token stream against the games' full names.
	# A separate fixture, so the ladder distribution above keeps
	# its numbers: in THAT db no LUCI game exists, and its
	# "Bolt-DC LUCI Premium.vpx" correctly stays filename-only.
	var ed_root_user: String = "user://core_test_edition"
	_wipe_tree(ProjectSettings.globalize_path(ed_root_user))
	var ed_user_dir: DirAccess = DirAccess.open("user://")
	if ed_user_dir != null and not ed_user_dir.dir_exists("core_test_edition"):
		ed_user_dir.make_dir("core_test_edition")
	var ed_dir: DirAccess = DirAccess.open(ed_root_user)
	if ed_dir != null and not ed_dir.dir_exists("tables"):
		ed_dir.make_dir("tables")
	var ed_tables: String = ed_root_user.path_join("tables")
	var ed_db_data: Array = [
		{
			"id": "fx-ed-bolt", "name": "Bolt/DC", "manufacturer": "Volt",
			"year": 2012, "designers": ["V. Olt"],
			"tableFiles": [
				{"id": "fx-ed-bolt-1", "version": "1.0", "tableFormat": "VPX", "authors": ["Volt Team"], "createdAt": 1700000000, "features": [], "urls": [{"url": "https://www.vpforums.org/index.php?app=downloads&showfile=20001"}]},
			],
		},
		{
			"id": "fx-ed-bolt-pro", "name": "Bolt/DC (Pro)", "manufacturer": "Volt",
			"year": 2012, "designers": ["V. Olt"],
			"tableFiles": [
				{"id": "fx-ed-bolt-pro-1", "version": "1.0", "tableFormat": "VPX", "authors": ["Volt Team"], "createdAt": 1700000000, "features": [], "urls": [{"url": "https://www.vpforums.org/index.php?app=downloads&showfile=20002"}]},
			],
		},
		{
			"id": "fx-ed-bolt-luci", "name": "Bolt/DC (LUCI Premium)", "manufacturer": "Volt",
			"year": 2013, "designers": ["V. Olt"],
			"tableFiles": [
				{"id": "fx-ed-bolt-luci-1", "version": "1.0.0", "tableFormat": "VPX", "authors": ["JP Sturm"], "createdAt": 1700000000, "features": [], "urls": [{"url": "https://www.vpforums.org/index.php?app=downloads&showfile=20003"}]},
				{"id": "fx-ed-bolt-luci-2", "version": "1.13", "tableFormat": "VPX", "authors": ["VPW", "Fluff"], "createdAt": 1735000000, "features": ["Hybrid", "VR"], "urls": [{"url": "https://vpuniverse.com/files/file/99999-boltdc-luci-volt-2013-vpw-mod/"}]},
			],
		},
	]
	_expect(_write_text_file(ed_root_user.path_join("vpsdb.json"), JSON.stringify(ed_db_data)), "edition fixture: db written", failures)
	var ed_db: VpsDatabase = VpsDatabase.new()
	_expect(ed_db.load_db(ed_root_user.path_join("vpsdb.json")), "edition fixture: db loads", failures)
	var ed_names: Array[String] = [
		"Bolt-DC LUCI Premium (Volt 2013) VPW v1.13.vpx",
		"Bolt-DC (Volt 2013) LUCI Premium v1.13.vpx",
		"Bolt-DC Pro (Volt 2012) VPW v1.0.vpx",
		"Bolt-DC Ultra Premium (Volt 2013) v1.0.vpx",
		"Bolt-DC LUCI Premium (Volt 2012) VPW v1.13.vpx",
		"Bolt-DC (Volt 2012).vpx",
		"Bolt-DC LUCI Premium.vpx",
	]
	for ed_name: String in ed_names:
		_expect(_write_text_file(ed_tables.path_join(ed_name), "fixture"), "edition fixture: file written (%s)" % ed_name, failures)
	var ed_folders: Array[String] = [ed_tables]
	var ed_scan: LibraryScanner = LibraryScanner.new()
	ed_scan.scan(ed_folders, ed_db)
	print("  edition fixture distribution: ", ed_scan.match_tier_counts,
		" (builds ", ed_scan.matched_files, ", game-only ", ed_scan.game_matched_files, ")")
	_expect(ed_scan.total_files == 7, "edition fixture: 7 files scanned", failures)
	_expect(ed_scan.matched_files == 4, "edition fixture: 4 builds matched", failures)
	_expect(ed_scan.game_matched_files == 1, "edition fixture: 1 by game only", failures)
	_expect(ed_scan.games.size() == 5, "edition fixture: grouped into 5 games", failures)
	_expect(int(ed_scan.match_tier_counts.get("edition", 0)) == 3
		and int(ed_scan.match_tier_counts.get("name", 0)) == 2
		and int(ed_scan.match_tier_counts.get("local", 0)) == 2,
		"edition fixture: tiers resolve edition 3 / name 2 / local 2", failures)
	var ed_luci: GameEntry = ed_scan.game_by_id("fx-ed-bolt-luci")
	_expect(ed_luci != null and ed_luci.builds.size() == 3, "edition fixture: the LUCI game groups its 3 files (2 rescued, 1 by name)", failures)
	if ed_luci != null:
		var res1: TableBuild = ed_luci.build_by_path(ed_tables.path_join("Bolt-DC LUCI Premium (Volt 2013) VPW v1.13.vpx"))
		_expect(res1 != null and res1.table_file_id == "fx-ed-bolt-luci-2" and res1.match_tier == "edition" and res1.has_vr_tag(),
			"edition referee: his AC/DC shape - team tag after the maker parens - identifies the VR build fx-ed-bolt-luci-2 (it can now appear in the VR view)", failures)
		var res2: TableBuild = ed_luci.build_by_path(ed_tables.path_join("Bolt-DC (Volt 2013) LUCI Premium v1.13.vpx"))
		_expect(res2 != null and res2.table_file_id == "fx-ed-bolt-luci-2" and res2.match_tier == "edition",
			"edition referee: edition words behind the maker parens complete the same match", failures)
		_expect(ed_luci.build_by_path(ed_tables.path_join("Bolt-DC LUCI Premium (Volt 2012) VPW v1.13.vpx")) == null,
			"edition referee: a LUCI file whose own parens state the WRONG year is still refused - the year veto is untouched", failures)
		_expect(ed_luci.build_by_path(ed_tables.path_join("Bolt-DC Pro (Volt 2012) VPW v1.0.vpx")) == null,
			"edition referee NC: the Pro file never lands on the LUCI entry", failures)
		var ed_bare_file: TableBuild = ed_luci.build_by_path(ed_tables.path_join("Bolt-DC LUCI Premium.vpx"))
		_expect(ed_bare_file != null and ed_bare_file.match_tier == "name" and not ed_bare_file.matched_db,
			"edition referee: the bare edition file keeps its historic road - the name tier, game-only (the game states two builds, the file names neither)", failures)
	var ed_pro: GameEntry = ed_scan.game_by_id("fx-ed-bolt-pro")
	_expect(ed_pro != null and ed_pro.builds.size() == 1, "edition fixture: the Pro game holds exactly its own file", failures)
	if ed_pro != null:
		var nc1: TableBuild = ed_pro.builds[0]
		_expect(nc1.table_file_id == "fx-ed-bolt-pro-1" and nc1.match_tier == "edition",
			"edition referee NC: a file naming the Pro edition lands on the Pro entry - not the base game, not LUCI", failures)
	var ed_bolt: GameEntry = ed_scan.game_by_id("fx-ed-bolt")
	_expect(ed_bolt != null and ed_bolt.builds.size() == 1, "edition fixture: the base game holds exactly its own file", failures)
	if ed_bolt != null:
		var ctrl: TableBuild = ed_bolt.builds[0]
		_expect(ctrl.table_file_id == "fx-ed-bolt-1" and ctrl.match_tier == "name",
			"edition referee: the edition-less file still matches the plain entry by name, exactly as before", failures)
	_expect(ed_scan.game_by_id("local:boltdcultrapremium") != null,
		"edition referee NC: edition words naming NO game's edition ('Ultra Premium') complete nothing - the file stays filename-only", failures)
	_expect(ed_scan.game_by_id("local:boltdclucipremiumvolt2012vpw") != null,
		"edition referee: the wrong-year LUCI file stays filename-only under its own name", failures)
	_wipe_tree(ProjectSettings.globalize_path(ed_root_user))
	_wipe_tree(mt_root)

	# Letter index (the letter-jump round): the alphabet
	# strip's mathematics over REAL title shapes - every title
	# below is a name the real VPS database actually carries
	# (census 2026-10-27: 2,669 games, 148 canonical "The "
	# starters, 24 non-A-Z starters after the strip).
	_expect(LetterIndex.sort_title("The Addams Family") == "Addams Family",
		"letter index: the sort title drops a leading 'The '", failures)
	_expect(LetterIndex.sort_title("Theatre of Magic") == "Theatre of Magic",
		"letter index: 'Theatre' is not 'The ' - nothing drops", failures)
	_expect(LetterIndex.sort_title("The 5th Element") == "5th Element",
		"letter index: 'The 5th Element' sorts as '5th Element'", failures)
	_expect(LetterIndex.sort_title("The") == "The",
		"letter index: a bare 'The' with no word after it keeps its name", failures)
	_expect(LetterIndex.is_the_title("The Addams Family") and LetterIndex.is_the_title("the sopranos")
		and not LetterIndex.is_the_title("Theatre of Magic") and not LetterIndex.is_the_title("The"),
		"letter index: THE membership wants 'The ' as its own word, any case", failures)
	_expect(LetterIndex.letter_of("The Addams Family") == "A",
		"letter index: The Addams Family files under A", failures)
	_expect(LetterIndex.letter_of("The Getaway - High Speed II") == "G",
		"letter index: The Getaway files under G", failures)
	_expect(LetterIndex.letter_of("Theatre of Magic") == "T",
		"letter index: Theatre of Magic files under T", failures)
	_expect(LetterIndex.letter_of("8 Ball") == "#" and LetterIndex.letter_of("The 5th Element") == "#"
		and LetterIndex.letter_of("'Roid Belt Racers") == "#" and LetterIndex.letter_of("2001") == "#",
		"letter index: digit and symbol starters file under #", failures)
	_expect(LetterIndex.letter_of("Apollo 13") == "A",
		"letter index: a bare number inside a title is a title word ('Apollo 13' files under A)", failures)
	# The net property, at index level: a canonical-The game
	# is in the THE net AND under its post-The letter - both
	# facts off the same canonical title, never one or the other.
	_expect(LetterIndex.in_net("The Addams Family", "THE") and LetterIndex.letter_of("The Addams Family") == "A",
		"letter index: the THE net is a net, not a move (member AND filed under A)", failures)
	_expect(LetterIndex.in_net("8 Ball", "#") and not LetterIndex.in_net("8 Ball", "THE")
		and not LetterIndex.in_net("The Addams Family", "#"),
		"letter index: the # net takes the non-letter starters only", failures)
	# THE internal order: sorted by the word after "The" - the
	# name sort over sort titles produces it directly.
	var the_games: Array[GameEntry] = []
	for t: String in ["The Sopranos", "The Shadow", "The Addams Family", "The Getaway - High Speed II"]:
		var ge: GameEntry = GameEntry.new()
		ge.title = t
		the_games.append(ge)
	the_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
		return LetterIndex.sort_title(a.title).to_lower() < LetterIndex.sort_title(b.title).to_lower())
	_expect(the_games[0].title == "The Addams Family" and the_games[1].title == "The Getaway - High Speed II"
		and the_games[2].title == "The Shadow" and the_games[3].title == "The Sopranos",
		"letter index: the THE set sorts by the word after 'The'", failures)
	# Presence: over the same real shapes - letters lit, THE
	# lit, and a letter nobody holds stays dark.
	var pres: Dictionary = LetterIndex.presence_over(the_games)
	_expect(pres.has("A") and pres.has("G") and pres.has("S") and pres.has("THE") and not pres.has("B") and not pres.has("#"),
		"letter index: presence lights exactly the held letters plus THE", failures)
	_expect(LetterIndex.slot_keys(false).size() == 27 and LetterIndex.slot_keys(true).size() == 28
		and LetterIndex.slot_keys(true)[0] == "A" and LetterIndex.slot_keys(true)[26] == "THE"
		and LetterIndex.slot_keys(true)[27] == "#" and LetterIndex.slot_keys(false)[26] == "THE",
		"letter index: the slot order is A-Z THE (#) - the one list layout and walk both read", failures)
	# Bumper anchors (the bumper-anchors round, 2026-10-28):
	# first / middle / last over a pickable list, the middle
	# at index (n - 1) / 2. The nine-slot list is the letters
	# fixture's real pickable strip (see below); the targets
	# are the press landings the room's strip step takes.
	var anch9: Array[String] = ["A", "F", "G", "M", "S", "T", "W", "THE", "#"]
	_expect(LetterIndex.anchor_keys(anch9) == ["A", "S", "#"],
		"letter index: nine pickable slots anchor at A, S (index (9-1)/2 = 4) and #", failures)
	_expect(LetterIndex.anchor_target(anch9, "G", 1) == "S" and LetterIndex.anchor_target(anch9, "S", 1) == "#"
		and LetterIndex.anchor_target(anch9, "#", 1) == "",
		"letter index: RB steps G -> middle, middle -> last, and clamps past the last", failures)
	_expect(LetterIndex.anchor_target(anch9, "S", -1) == "A" and LetterIndex.anchor_target(anch9, "W", -1) == "S"
		and LetterIndex.anchor_target(anch9, "F", -1) == "A" and LetterIndex.anchor_target(anch9, "A", -1) == "",
		"letter index: LB steps middle -> first, W -> middle, F -> first, and clamps past the first", failures)
	_expect(LetterIndex.anchor_target(anch9, "A", 1) == "S" and LetterIndex.anchor_target(anch9, "#", -1) == "S",
		"letter index: a press while ON an anchor advances to the next one - never a no-op", failures)
	var anch8: Array[String] = ["A", "F", "G", "M", "S", "T", "W", "THE"]
	_expect(LetterIndex.anchor_keys(anch8) == ["A", "M", "THE"],
		"letter index: an even count's middle is index (8-1)/2 = 3, just left of centre", failures)
	_expect(LetterIndex.anchor_keys(["A", "#"]) == ["A", "#"]
		and LetterIndex.anchor_target(["A", "#"], "A", 1) == "#" and LetterIndex.anchor_target(["A", "#"], "#", -1) == "A"
		and LetterIndex.anchor_target(["A", "#"], "#", 1) == "",
		"letter index: two pickable slots anchor at the two ends (the middle collapses)", failures)
	_expect(LetterIndex.anchor_keys(["M"]) == ["M"] and LetterIndex.anchor_target(["M"], "M", 1) == ""
		and LetterIndex.anchor_target(["M"], "M", -1) == "",
		"letter index: a single pickable slot's bumpers are a clean no-op", failures)
	_expect(LetterIndex.anchor_keys([]).is_empty() and LetterIndex.anchor_target([], "A", 1) == ""
		and LetterIndex.anchor_target(anch9, "B", 1) == "",
		"letter index: an empty list - or a slot not in it - answers no anchor", failures)

	# WoVP read side (the Tournament Room round, 2026-10-28):
	# the client core against the MODEL-DERIVED fixtures in
	# data/wovp/ (built field-by-field from VPin Studio's DTO
	# definitions - the spike found no literal sample response;
	# see data/wovp/README.md). Parsing, his-row identity,
	# cutoff selection, board composition, Chicago clock math,
	# fail-closed behavior, the key's config round-trip, and
	# the last-good cache.
	var wovp_validate_text: String = FileAccess.get_file_as_string("res://data/wovp/validate_apikey.json")
	var wovp_search_text: String = FileAccess.get_file_as_string("res://data/wovp/challenges_search.json")
	_expect(wovp_validate_text != "" and wovp_search_text != "",
		"wovp: the model-derived fixtures load", failures)
	var wovp_val: Dictionary = WovpClient.parse_validation(wovp_validate_text)
	_expect(bool(wovp_val.get("ok", false)) and str(wovp_val.get("user_id", "")) == "fixture-user-1"
		and str(wovp_val.get("display_name", "")) == "Fixture Player",
		"wovp: validate fixture resolves the key to its player (id + name)", failures)
	var wovp_refused: Dictionary = WovpClient.parse_validation("{\"success\": false}")
	_expect(not bool(wovp_refused.get("ok", true)) and bool(wovp_refused.get("refused", false)),
		"wovp: success=false is a stated refusal, not a parse failure", failures)
	_expect(not bool(WovpClient.parse_validation("not json").get("ok", true)),
		"wovp: an unreadable validate answer fails closed", failures)
	var wovp_parsed: Dictionary = WovpClient.parse_challenges(wovp_search_text)
	_expect(bool(wovp_parsed.get("ok", false)),
		"wovp: the challenges fixture parses (%s)" % str(wovp_parsed.get("error", "")), failures)
	var wovp_challenges: Array = wovp_parsed.get("challenges", [])
	_expect(wovp_challenges.size() == 5, "wovp: five challenges in the fixture", failures)
	if wovp_challenges.size() == 5:
		var ch_season: WovpChallenge = wovp_challenges[0]
		var ch_extra: WovpChallenge = wovp_challenges[1]
		var ch_br: WovpChallenge = wovp_challenges[2]
		var ch_monthly: WovpChallenge = wovp_challenges[3]
		var ch_notowned: WovpChallenge = wovp_challenges[4]
		_expect(ch_season.type_code == "season" and ch_extra.type_code == "extra"
			and ch_br.type_code == "tournament" and ch_monthly.type_code == "monthly_contracts",
			"wovp: all four challenge types parse", failures)
		_expect(ch_season.table_external_id == "aT_GONvw" and ch_season.version_external_id == "Oytg92XtEb",
			"wovp: a challenge carries its VPS game id + table-file id (the library join keys)", failures)
		_expect(ch_season.rows.size() == 12 and ch_season.rows[0].position == 1 and ch_season.rows[11].position == 12,
			"wovp: the season board parses whole and sorts by position", failures)
		var his_season: WovpScoreRow = ch_season.his_row("fixture-user-1")
		_expect(his_season != null and his_season.position == 6 and int(his_season.score) == 24531070,
			"wovp: his row is found by userId, mid-board", failures)
		_expect(ch_season.his_row("fixture-user-ghost") == null,
			"wovp: an unknown userId has no row (nobody is 'him' by accident)", failures)
		_expect(ch_season.leader_row() != null and int(ch_season.leader_row().score) == 98450210,
			"wovp: the leader's score reads off the board's head", failures)
		var his_extra: WovpScoreRow = ch_extra.his_row("fixture-user-1")
		_expect(his_extra != null and his_extra.is_pending,
			"wovp: a pending entry parses as pending (IsPending)", failures)
		_expect(ch_notowned.table_external_id == "kGBkVb-v" and ch_notowned.his_row("fixture-user-1") != null,
			"wovp: the not-owned challenge parses with his score on it (ownership is the library's call, not the board's)", failures)
		# Cutoff selection per type: season draws the
		# promotion line under 8th; Battle Royale the cut
		# under the last survivor (14 rows - 10 cut = 4);
		# a 5-row extra board has no line yet; monthly
		# contracts never draw one.
		_expect(ch_season.cutoff_position() == 8, "wovp: season cutoff is the promotion line at 8th", failures)
		_expect(ch_br.cutoff_position() == 4, "wovp: Battle Royale cutoff leaves 14 - 10 = 4 survivors", failures)
		_expect(ch_extra.cutoff_position() == 0, "wovp: a board short of 8 rows draws no promotion line", failures)
		_expect(ch_monthly.cutoff_position() == 0, "wovp: monthly contracts draw no cutoff line", failures)
		# Board composition: leader, his row, the rows
		# around the line, the divider where it falls.
		var season_board: Array = ch_season.board_rows("fixture-user-1")
		var season_seq: Array = []
		for e: Variant in season_board:
			var ed: Dictionary = e
			season_seq.append(str(ed.get("kind", "")) + ":" + str((ed.get("row") as WovpScoreRow).position if ed.get("row") is WovpScoreRow else 0))
		_expect(season_seq == ["score:1", "score:6", "score:8", "divider:0", "score:9"],
			"wovp: the season board shows leader, him, and both sides of the promotion line", failures)
		var season_mine: int = 0
		for e2: Variant in season_board:
			var ed2: Dictionary = e2
			if bool(ed2.get("mine", false)):
				season_mine += 1
		_expect(season_mine == 1, "wovp: exactly one row on the board is marked his", failures)
		var br_board: Array = ch_br.board_rows("fixture-user-1")
		var br_kinds: Array = []
		var br_divider_label: String = ""
		for e3: Variant in br_board:
			var ed3: Dictionary = e3
			br_kinds.append(str(ed3.get("kind", "")))
			if str(ed3.get("kind", "")) == "divider":
				br_divider_label = str(ed3.get("label", ""))
		_expect(br_kinds == ["score", "score", "divider", "score", "score"] and br_divider_label.contains("CUT LINE"),
			"wovp: the Battle Royale board carries its cut line between the survivor and the cut", failures)
		var ghost_board: Array = ch_monthly.board_rows("fixture-user-ghost")
		var ghost_has_note: bool = false
		for e4: Variant in ghost_board:
			var ed4: Dictionary = e4
			if str(ed4.get("kind", "")) == "note":
				ghost_has_note = true
		_expect(ghost_has_note, "wovp: a board he has no score on says so, plainly", failures)
	_expect(WovpChallenge.format_score(24531070.0) == "24,531,070" and WovpChallenge.format_score(750200.0) == "750,200"
		and WovpChallenge.format_score(0.0) == "0",
		"wovp: scores print grouped, the way pinball prints them", failures)
	# Fail-closed mutations of the fixture (built in code -
	# the fixture file itself stays DTO-shaped).
	var wovp_mut: Variant = JSON.parse_string(wovp_search_text)
	if wovp_mut is Dictionary:
		var mut_items: Array = (wovp_mut as Dictionary)["items"]
		(mut_items[0] as Dictionary).erase("endDateUTC")
		_expect(not bool(WovpClient.parse_challenges(JSON.stringify(wovp_mut)).get("ok", true)),
			"wovp: a challenge with no end date fails closed", failures)
		wovp_mut = JSON.parse_string(wovp_search_text)
		mut_items = (wovp_mut as Dictionary)["items"]
		(mut_items[0] as Dictionary)["challengeTypeCode"] = "playoffs"
		_expect(not bool(WovpClient.parse_challenges(JSON.stringify(wovp_mut)).get("ok", true)),
			"wovp: an unknown challenge type fails closed", failures)
		wovp_mut = JSON.parse_string(wovp_search_text)
		mut_items = (wovp_mut as Dictionary)["items"]
		(((mut_items[0] as Dictionary)["scoreBoard"] as Dictionary)["items"][0] as Dictionary)["values"].erase("Score")
		_expect(not bool(WovpClient.parse_challenges(JSON.stringify(wovp_mut)).get("ok", true)),
			"wovp: a scoreboard row with no score fails closed", failures)
		wovp_mut = JSON.parse_string(wovp_search_text)
		mut_items = (wovp_mut as Dictionary)["items"]
		(((mut_items[0] as Dictionary)["scoreBoard"] as Dictionary)["items"][0] as Dictionary)["values"].erase("UserId")
		_expect(not bool(WovpClient.parse_challenges(JSON.stringify(wovp_mut)).get("ok", true)),
			"wovp: a scoreboard row naming no player fails closed", failures)
		wovp_mut = JSON.parse_string(wovp_search_text)
		(wovp_mut as Dictionary).erase("items")
		_expect(not bool(WovpClient.parse_challenges(JSON.stringify(wovp_mut)).get("ok", true)),
			"wovp: a response with no challenge list fails closed", failures)
		wovp_mut = JSON.parse_string(wovp_search_text)
		mut_items = (wovp_mut as Dictionary)["items"]
		(mut_items[0] as Dictionary)["someFutureField"] = {"nested": [1, 2]}
		(((mut_items[0] as Dictionary)["scoreBoard"] as Dictionary)["items"][0] as Dictionary)["values"]["AnotherFutureField"] = true
		_expect(bool(WovpClient.parse_challenges(JSON.stringify(wovp_mut)).get("ok", false)),
			"wovp: unknown extra fields are ignored, the league's own mapper's way", failures)
		wovp_mut = JSON.parse_string(wovp_search_text)
		mut_items = (wovp_mut as Dictionary)["items"]
		(mut_items[0] as Dictionary)["scriptMatchKeywords"] = ["the addams family"]
		var kw_parsed: Dictionary = WovpClient.parse_challenges(JSON.stringify(wovp_mut))
		_expect(bool(kw_parsed.get("ok", false)) and (kw_parsed["challenges"][0] as WovpChallenge).script_keywords == ["the addams family"],
			"wovp: script match keywords parse as carried", failures)
	_expect(not bool(WovpClient.parse_challenges(wovp_search_text.left(200)).get("ok", true)),
		"wovp: a truncated response fails closed", failures)
	# The league's dates: strict ISO-8601 with offsets.
	var wovp_instant: int = Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 25, "hour": 19, "minute": 0, "second": 0})
	_expect(WovpClient.parse_iso8601("2026-10-25T19:00:00Z") == wovp_instant
		and WovpClient.parse_iso8601("2026-10-25T21:00:00+02:00") == wovp_instant
		and WovpClient.parse_iso8601("2026-10-25T19:00:00.500Z") == wovp_instant,
		"wovp: ISO dates read in Z, offset, and fractional forms as one instant", failures)
	_expect(WovpClient.parse_iso8601("garbage") == -1 and WovpClient.parse_iso8601("2026-13-25T19:00:00Z") == -1
		and WovpClient.parse_iso8601("") == -1,
		"wovp: non-dates are refused, not guessed", failures)
	# Chicago conversion, pinned to known instants (the
	# league's Sunday 19:00 UTC deadline shape): the last
	# CDT Sunday of 2026, the first CST Sunday, the spring
	# forward Sunday, and deep winter.
	_expect(WovpTime.format_deadline(wovp_instant) == "Sun Oct 25, 2:00 PM CDT",
		"wovp time: 2026-10-25 19:00 UTC is Sun 2:00 PM CDT in Chicago", failures)
	_expect(WovpTime.format_deadline(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 1, "hour": 19, "minute": 0, "second": 0})) == "Sun Nov 1, 1:00 PM CST",
		"wovp time: 2026-11-01 19:00 UTC is Sun 1:00 PM CST (DST over)", failures)
	_expect(WovpTime.format_deadline(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 3, "day": 8, "hour": 19, "minute": 0, "second": 0})) == "Sun Mar 8, 2:00 PM CDT",
		"wovp time: 2026-03-08 19:00 UTC is Sun 2:00 PM CDT (DST begun)", failures)
	_expect(WovpTime.format_deadline(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 1, "day": 18, "hour": 19, "minute": 0, "second": 0})) == "Sun Jan 18, 1:00 PM CST",
		"wovp time: deep winter is CST", failures)
	_expect(WovpTime.format_remaining(wovp_instant + 2 * 86400 + 4 * 3600, wovp_instant) == "2d 4h left"
		and WovpTime.format_remaining(wovp_instant + 3600 + 30 * 60, wovp_instant) == "1h 30m left"
		and WovpTime.format_remaining(wovp_instant - 60, wovp_instant) == "ended",
		"wovp time: remaining time reads in days/hours, minutes, and the past tense", failures)
	# The search body never carries key material (the key
	# rides in the header only) - the redaction discipline
	# at the shape level; the harness greps the logs for a
	# sentinel key on top of this.
	var wovp_body: String = WovpClient.search_body()
	_expect(not wovp_body.contains("apikey") and not wovp_body.contains("Bearer") and wovp_body.contains("inProgress"),
		"wovp: the search body is Studio's Search shape and carries no key", failures)
	# Config round-trip for the key (backed up + restored
	# like the rest of this test's file work).
	var wovp_cfg_file: String = PvldsConfig.existing_path()
	var wovp_cfg_backup: String = ""
	if FileAccess.file_exists(wovp_cfg_file):
		wovp_cfg_backup = FileAccess.get_file_as_string(wovp_cfg_file)
	var wovp_cfg: PvldsConfig = PvldsConfig.new()
	wovp_cfg.wovp_api_key = "core-test-key-not-a-real-one"
	_expect(wovp_cfg.save_to_disk(), "wovp: a config carrying a key saves", failures)
	var wovp_cfg2: PvldsConfig = PvldsConfig.new()
	_expect(wovp_cfg2.load_from_disk() and wovp_cfg2.wovp_api_key == "core-test-key-not-a-real-one",
		"wovp: the key round-trips through the local config file", failures)
	if wovp_cfg_backup != "":
		var wcf: FileAccess = FileAccess.open(wovp_cfg_file, FileAccess.WRITE)
		if wcf != null:
			wcf.store_string(wovp_cfg_backup)
			wcf.close()
	elif FileAccess.file_exists(PvldsConfig.save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PvldsConfig.save_path()))
	# The last-good cache: a saved fetch loads back through
	# the same fail-closed parser; a corrupt cache is no
	# cache (backed up + restored like the state above).
	var wovp_cache_file: String = WovpClient.cache_path()
	var wovp_cache_backup: String = ""
	if FileAccess.file_exists(wovp_cache_file):
		wovp_cache_backup = FileAccess.get_file_as_string(wovp_cache_file)
	_expect(WovpClient.save_cache(wovp_search_text, "fixture-user-1", "Fixture Player", 1761435600, 4242),
		"wovp: the last-good cache saves", failures)
	var wovp_cache: Dictionary = WovpClient.load_cache()
	_expect(bool(wovp_cache.get("ok", false)) and (wovp_cache.get("challenges", []) as Array).size() == 5
		and str(wovp_cache.get("user_id", "")) == "fixture-user-1" and int(wovp_cache.get("fetched_at", 0)) == 1761435600
		and int(wovp_cache.get("key_hash", 0)) == 4242,
		"wovp: the cache loads back - boards, player, stamp, and the key's hash (never the key)", failures)
	_expect(_write_text_file(ProjectSettings.globalize_path(wovp_cache_file), "{\"fetched_at\": 1, \"body\": \"{broken\"}"),
		"wovp: corrupt cache written for its leg", failures)
	_expect(not bool(WovpClient.load_cache().get("ok", true)),
		"wovp: a corrupt cache fails closed (it is no cache)", failures)
	if wovp_cache_backup != "":
		var wkf: FileAccess = FileAccess.open(wovp_cache_file, FileAccess.WRITE)
		if wkf != null:
			wkf.store_string(wovp_cache_backup)
			wkf.close()
	elif FileAccess.file_exists(wovp_cache_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(wovp_cache_file))
	# The server's own words (the HTTP400 round): an error
	# body is quoted in the failure, never discarded.
	# server_words unwraps a bare JSON string body (the
	# quotes are packaging), flattens to one line, caps the
	# quote with a stated cut, and answers "" for no body.
	_expect(WovpClient.server_words("\"X-Client-ID header is required or invalid\"".to_utf8_buffer()) == "X-Client-ID header is required or invalid",
		"wovp: an error body that is a JSON string is quoted as its words, not its packaging", failures)
	_expect(WovpClient.server_words("plain refusal text".to_utf8_buffer()) == "plain refusal text",
		"wovp: a plain-text error body is quoted as it stands", failures)
	_expect(WovpClient.server_words(PackedByteArray()) == "" and WovpClient.server_words("  \n ".to_utf8_buffer()) == "",
		"wovp: an empty error body answers no words (the caller falls back to the bare code)", failures)
	var wovp_long_words: String = WovpClient.server_words("x".repeat(400).to_utf8_buffer())
	_expect(wovp_long_words.length() <= 260 and wovp_long_words.contains("cut off"),
		"wovp: a long error body is capped and the cut is stated", failures)
	# Propagation: a stubbed refusal's body lands IN the
	# emitted failure, for both calls - the desk line, the
	# panel line, and the room's state panel all render
	# this one message. The handler is driven directly;
	# no network is touched.
	var wovp_probe_client: WovpClient = WovpClient.new()
	add_child(wovp_probe_client)
	var wovp_probe_answers: Array = []
	wovp_probe_client.validation_finished.connect(func(_ok: bool, message: String, _uid: String, _name: String) -> void: wovp_probe_answers.append(message))
	wovp_probe_client.challenges_finished.connect(func(_ok: bool, message: String, _ch: Array, _raw: String) -> void: wovp_probe_answers.append(message))
	wovp_probe_client._pending_kind = "validate"
	wovp_probe_client._on_request_completed(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(), "\"DISTINCTIVE-VALIDATE-REFUSAL\"".to_utf8_buffer())
	_expect(wovp_probe_answers.size() == 1 and str(wovp_probe_answers[0]).contains("DISTINCTIVE-VALIDATE-REFUSAL")
		and str(wovp_probe_answers[0]).contains("HTTP 400"),
		"wovp: a validate refusal carries WoVP's own words (validate 400 propagation)", failures)
	wovp_probe_client._pending_kind = "search"
	wovp_probe_client._on_request_completed(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(), "\"DISTINCTIVE-SEARCH-REFUSAL\"".to_utf8_buffer())
	_expect(wovp_probe_answers.size() == 2 and str(wovp_probe_answers[1]).contains("DISTINCTIVE-SEARCH-REFUSAL"),
		"wovp: a search refusal carries WoVP's own words (search 400 propagation)", failures)
	wovp_probe_client._pending_kind = "validate"
	wovp_probe_client._on_request_completed(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(), PackedByteArray())
	_expect(wovp_probe_answers.size() == 3 and str(wovp_probe_answers[2]) == "WoVP answered with an error (HTTP 400).",
		"wovp: an empty refusal body falls back to the bare code, nothing appended", failures)
	# The key's shape (WoVP's 32-character rule, probed
	# live): 31 and 33 are refused in words, 32 passes, and
	# padding never counts. And the client itself will not
	# send a short key: validate answers locally, instantly,
	# with the request never started.
	_expect(WovpClient.key_length_note("k".repeat(31)).contains("31 characters"),
		"wovp: a 31-character key is refused in words before anything is sent", failures)
	_expect(WovpClient.key_length_note("k".repeat(32)) == "",
		"wovp: a 32-character key is the shape WoVP wants", failures)
	_expect(WovpClient.key_length_note("k".repeat(33)).contains("33 characters"),
		"wovp: a 33-character key is refused in words before anything is sent", failures)
	_expect(WovpClient.key_length_note("  " + "k".repeat(32) + " ") == "",
		"wovp: the length check counts the key, not its padding", failures)
	wovp_probe_answers.clear()
	wovp_probe_client.validate_key("k".repeat(31))
	_expect(wovp_probe_answers.size() == 1 and str(wovp_probe_answers[0]).contains("31 characters") and not wovp_probe_client.is_busy(),
		"wovp: validate on a short key sends nothing - the refusal is local and instant", failures)
	wovp_probe_client.queue_free()

	if failures.is_empty():
		print("CORE TEST: PASS")
		get_tree().quit(0)
	else:
		printerr("CORE TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)
