extends Node

## PVLDS entry point. Owns the pieces both faces share - config, state,
## database, scanner, texture factory - and routes between the two:
## the first-run desk pass (2D) and the room (3D / XR).
##
## Dev hooks (user args, after "--"):
##   --pvlds-core-test   run the UI-free library test suite, print, quit
##   --pvlds-seed-dummy  boot straight into the room on the dummy library
##   --setup             force the desk pass even when configured
##   --pvlds-db-stats P  load the database at P, print counts, quit
##   --pvlds-shot P      boot (with --pvlds-seed-dummy), save a room
##                       screenshot to P once textures settle, quit

var _config: PvldsConfig
var _state: StateStore
var _db: VpsDatabase
var _scanner: LibraryScanner
var _factory: TextureFactory
var _room: RoomView = null
var _desk: SetupDesk = null
var _xr_interface: XRInterface
var _xr_enabled: bool = false

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
	_init_xr()
	_factory = TextureFactory.new()
	add_child(_factory)
	_config = PvldsConfig.new()
	_state = StateStore.new()
	_state.load_from_disk()
	var configured: bool = _config.load_from_disk()
	if user_args.has("--pvlds-seed-dummy"):
		_seed_dummy_config()
		configured = true
	if configured and _config.is_configured() and not user_args.has("--setup"):
		# Configured boot: present the desk as a live shell immediately
		# (first frame, progress ticking) and enter the room only when
		# the threaded scan lands. No scan runs before the first frame.
		_show_desk()
		_enter_room_after_scan = true
		if not start_scan():
			_enter_room_after_scan = false
	else:
		_show_desk()


func _init_xr() -> void:
	_xr_interface = XRServer.find_interface("OpenXR")
	if _xr_interface != null and _xr_interface.is_initialized():
		get_viewport().use_xr = true
		_xr_enabled = true
	else:
		get_viewport().use_xr = false


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
	if _shot_path != "" and _room != null and _room.visible and _room.wall_ready:
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
	if _enter_room_after_scan:
		_enter_room_after_scan = false
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
	if _room == null:
		_room = RoomView.new()
		add_child(_room)
		_room.setup(_factory, _scanner, _state, _xr_enabled)
		_room.setup_requested.connect(_show_desk)
	else:
		_room.refresh_library()
	_room.visible = true


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


# ------------------------------------------------------------ core test

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
	if backup != "":
		var f: FileAccess = FileAccess.open(state_file, FileAccess.WRITE)
		if f != null:
			f.store_string(backup)
			f.close()
	elif FileAccess.file_exists(state_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(state_file))

	if failures.is_empty():
		print("CORE TEST: PASS")
		get_tree().quit(0)
	else:
		printerr("CORE TEST: FAIL (%d)" % failures.size())
		get_tree().quit(1)
