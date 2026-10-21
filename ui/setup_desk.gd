class_name SetupDesk
extends CanvasLayer

## The first-run desk pass: a flat 2D form, used with the mouse at the
## desk - never in the headset. Points the app at the VPX executable and
## the table folder(s), saves the plain config, runs the scan, and
## reports what the scan measured (duplicates, match rate, art
## coverage) plus any titles it could not identify.

signal enter_room_requested

var _config: PvldsConfig
var _exe_edit: LineEdit
var _args_edit: LineEdit
var _herding_check: CheckBox
var _db_edit: LineEdit
var _folder_rows: VBoxContainer
var _folder_edits: Array[LineEdit] = []
var _scan_button: Button
var _stats_label: Label
var _enter_button: Button
var _dialog: FileDialog
var _dialog_target: String = "" ## "exe" | "db" | "folder:<index>"
var _scanned: bool = false
var _dl_button: Button
var _dl_label: Label
var _http: HTTPRequest
var _downloading: bool = false

const MAX_FOLDER_ROWS: int = 6
const DOWNLOAD_PARTIAL_PATH: String = "user://vpsdb_download.partial"


func setup(config: PvldsConfig) -> void:
	_config = config
	_build_ui()
	_fill_from_config()


func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.custom_minimum_size = Vector2(760, 0)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = "PVLDS - first-run setup"
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)
	var intro: Label = Label.new()
	intro.text = "Point the launcher at your VPX executable and your table folder(s). This is desk work on purpose - the room in the headset is only for playing."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	_exe_edit = _add_path_row(vbox, "VPX executable", "Browse...", "exe")
	_db_edit = _add_path_row(vbox, "VPS database (vpsdb.json, optional)", "Browse...", "db")
	var dl_row: HBoxContainer = HBoxContainer.new()
	dl_row.add_theme_constant_override("separation", 8)
	vbox.add_child(dl_row)
	_dl_button = Button.new()
	_dl_button.text = "Download VPS database"
	_dl_button.pressed.connect(_on_download_pressed)
	dl_row.add_child(_dl_button)
	_dl_label = Label.new()
	_dl_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl_row.add_child(_dl_label)
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 180.0
	_http.request_completed.connect(_on_download_completed)
	add_child(_http)
	_args_edit = _add_field(vbox, "Launch arguments template ({table} is the table file; quotes group arguments)")
	_herding_check = CheckBox.new()
	_herding_check.text = "Focus herding - the watchdog keeps the game window in front during play (uncheck if it ever fights you)"
	_herding_check.tooltip_text = "Design section 3 amendment: during the launch settle and during play, the watchdog returns foreground focus to the VPX window when something steals it. It never moves or resizes windows."
	vbox.add_child(_herding_check)
	_folder_rows = VBoxContainer.new()
	_folder_rows.add_theme_constant_override("separation", 8)
	vbox.add_child(_folder_label())
	vbox.add_child(_folder_rows)
	var add_folder: Button = Button.new()
	add_folder.text = "Add table folder..."
	add_folder.pressed.connect(_on_add_folder_row)
	vbox.add_child(add_folder)

	var dummy_button: Button = Button.new()
	dummy_button.text = "Use the bundled dummy library (invented tables, for judging the flow)"
	dummy_button.pressed.connect(_on_use_dummy)
	vbox.add_child(dummy_button)

	_scan_button = Button.new()
	_scan_button.text = "Save && Scan"
	_scan_button.pressed.connect(_on_save_and_scan)
	vbox.add_child(_scan_button)

	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.text = "Not scanned yet."
	vbox.add_child(_stats_label)

	_enter_button = Button.new()
	_enter_button.text = "Enter the Room"
	_enter_button.disabled = true
	_enter_button.pressed.connect(func() -> void: enter_room_requested.emit())
	vbox.add_child(_enter_button)

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_selected.connect(_on_dialog_file)
	_dialog.dir_selected.connect(_on_dialog_dir)
	add_child(_dialog)


func _folder_label() -> Label:
	var l: Label = Label.new()
	l.text = "Table folders"
	l.add_theme_font_size_override("font_size", 20)
	return l


func _add_field(parent: VBoxContainer, label_text: String) -> LineEdit:
	var l: Label = Label.new()
	l.text = label_text
	parent.add_child(l)
	var edit: LineEdit = LineEdit.new()
	parent.add_child(edit)
	return edit


func _add_path_row(parent: VBoxContainer, label_text: String, button_text: String, target: String) -> LineEdit:
	var l: Label = Label.new()
	l.text = label_text
	parent.add_child(l)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var edit: LineEdit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var b: Button = Button.new()
	b.text = button_text
	var t: String = target
	b.pressed.connect(func() -> void: _open_dialog_for(t))
	row.add_child(b)
	return edit


func _add_folder_row(prefill: String) -> void:
	if _folder_edits.size() >= MAX_FOLDER_ROWS:
		return
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var edit: LineEdit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = prefill
	edit.placeholder_text = "C:/Visual Pinball/Tables"
	row.add_child(edit)
	var idx: int = _folder_edits.size()
	var b: Button = Button.new()
	b.text = "Browse..."
	b.pressed.connect(func() -> void: _open_dialog_for("folder:" + str(idx)))
	row.add_child(b)
	_folder_rows.add_child(row)
	_folder_edits.append(edit)


func _on_add_folder_row() -> void:
	_add_folder_row("")


func _open_dialog_for(target: String) -> void:
	_dialog_target = target
	if target == "exe":
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.filters = PackedStringArray(["*.exe ; VPX executable"])
		_dialog.title = "Find your VPX executable (VPinball_GL64.exe)"
	elif target == "db":
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.filters = PackedStringArray(["*.json ; vpsdb.json"])
		_dialog.title = "Find a cached vpsdb.json (optional)"
	else:
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.title = "Pick a folder full of .vpx tables"
	_dialog.popup_centered_ratio(0.75)


func _on_dialog_file(path: String) -> void:
	if _dialog_target == "exe":
		_exe_edit.text = path
	elif _dialog_target == "db":
		_db_edit.text = path


func _on_dialog_dir(path: String) -> void:
	if _dialog_target.begins_with("folder:"):
		var idx: int = _dialog_target.trim_prefix("folder:").to_int()
		if idx >= 0 and idx < _folder_edits.size():
			_folder_edits[idx].text = path


func _fill_from_config() -> void:
	_exe_edit.text = _config.vpx_exe_path
	_db_edit.text = _config.vpsdb_path
	_args_edit.text = _config.launch_args_template
	_herding_check.button_pressed = _config.focus_herding
	for f: String in _config.table_folders:
		_add_folder_row(f)
	if _folder_edits.is_empty():
		_add_folder_row("")


func _on_use_dummy() -> void:
	_exe_edit.text = PvldsConfig.DEFAULT_EXE_NAME
	_db_edit.text = ProjectSettings.globalize_path("res://data/vpsdb.json")
	for edit: LineEdit in _folder_edits:
		edit.text = ""
	_folder_edits[0].text = ProjectSettings.globalize_path("res://dummy_data/tables")


func _collect_into_config() -> void:
	_config.vpx_exe_path = _exe_edit.text.strip_edges()
	_config.vpsdb_path = _db_edit.text.strip_edges()
	_config.launch_args_template = _args_edit.text.strip_edges()
	if _config.launch_args_template == "":
		_config.launch_args_template = PvldsConfig.DEFAULT_LAUNCH_ARGS
	_config.focus_herding = _herding_check.button_pressed
	_config.table_folders.clear()
	for edit: LineEdit in _folder_edits:
		var f: String = edit.text.strip_edges()
		if f != "":
			_config.table_folders.append(f)


func _process(_delta: float) -> void:
	if _downloading and _http != null:
		var total: int = _http.get_body_size()
		var got: int = _http.get_downloaded_bytes()
		if total > 0:
			_dl_label.text = "Downloading VPS database... %d%% (%.1f of %.1f MB)" % [
				int(100.0 * float(got) / float(total)), float(got) / 1048576.0, float(total) / 1048576.0]
		else:
			_dl_label.text = "Downloading VPS database... %.1f MB so far" % (float(got) / 1048576.0)


func _on_download_pressed() -> void:
	if _downloading:
		return
	_downloading = true
	_dl_button.disabled = true
	_dl_label.text = "Downloading VPS database..."
	_http.download_file = DOWNLOAD_PARTIAL_PATH
	var err: Error = _http.request(VpsDatabase.DOWNLOAD_URL)
	if err != OK:
		_download_failed("Could not start the download (error %d)." % err)


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_download_failed("Download failed (result %d, HTTP %d). Check the connection and try again." % [result, response_code])
		return
	# Sanity-check the payload before it becomes the cached database:
	# the real vpsdb.json is a multi-MB top-level JSON array.
	var f: FileAccess = FileAccess.open(DOWNLOAD_PARTIAL_PATH, FileAccess.READ)
	if f == null:
		_download_failed("Download finished but the file could not be read back.")
		return
	var size: int = int(f.get_length())
	var head: PackedByteArray = f.get_buffer(mini(256, size))
	f.close()
	var head_text: String = head.get_string_from_utf8().strip_edges()
	if size < 1000000 or not head_text.begins_with("["):
		_download_failed("What arrived does not look like the VPS database - cache not updated.")
		return
	var cache_abs: String = ProjectSettings.globalize_path(VpsDatabase.CACHE_PATH)
	if FileAccess.file_exists(VpsDatabase.CACHE_PATH):
		DirAccess.remove_absolute(cache_abs)
	var err: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(DOWNLOAD_PARTIAL_PATH), cache_abs)
	if err != OK:
		_download_failed("Could not store the downloaded database (error %d)." % err)
		return
	_downloading = false
	_dl_button.disabled = false
	_dl_label.text = "VPS database downloaded (%.1f MB). It will be used by the next Save & Scan." % (float(size) / 1048576.0)
	if _db_edit.text.strip_edges() == "":
		_db_edit.text = cache_abs


func _download_failed(message: String) -> void:
	_downloading = false
	_dl_button.disabled = false
	_dl_label.text = message
	if FileAccess.file_exists(DOWNLOAD_PARTIAL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DOWNLOAD_PARTIAL_PATH))


func _on_save_and_scan() -> void:
	_collect_into_config()
	if _config.table_folders.is_empty():
		_stats_label.text = "Add at least one table folder first."
		return
	if not _config.save_to_disk():
		_stats_label.text = "Config save failed - check the folder is writable, then try again."
		return
	# The scan runs on Main's worker thread; this form stays live and
	# Main paints progress into the stats label until the summary lands.
	var main: Node = get_parent()
	if main != null and main.has_method("start_scan"):
		if bool(main.call("start_scan")):
			_scanned = false
			_scan_button.disabled = true
			_enter_button.disabled = true
			_stats_label.text = "Scanning..."
		else:
			_stats_label.text = "A scan is already running - one moment."


## A plain message in the stats area (e.g. why a launch failed and
## what to fix here).
func show_message(text: String) -> void:
	_stats_label.text = text


## Live progress text while a scan runs (driven by Main's poll loop).
## Also used by the configured-boot route, where the scan starts
## before the user touches anything.
func set_scan_progress(text: String) -> void:
	_stats_label.text = text
	_scan_button.disabled = true
	_enter_button.disabled = true


## Final summary when a scan lands; re-arms the form.
func apply_scan_summary(summary: String) -> void:
	_stats_label.text = summary
	_scanned = summary != ""
	_enter_button.disabled = not _scanned
	_scan_button.disabled = false
