class_name SetupDesk
extends CanvasLayer

## The first-run desk pass: a flat 2D form, used with the mouse at the
## desk - never in the headset. Points the app at the VPX executable and
## the table folder(s), saves the plain config, runs the scan, and
## reports what the scan measured (duplicates, match rate, art
## coverage) plus any titles it could not identify.

signal enter_room_requested
signal wovp_key_saved ## the WoVP key was saved from this desk: Main refreshes the Tournament Room's boards
signal pinemhi_settings_saved ## NEXTROUND (item 4): the PINemHi folder/toggle was saved from this desk: Main re-reads the bests and re-pushes them to the room
signal screenshots_settings_saved ## ROOMSUBMIT: the screenshots folder was saved from this desk: Main re-pushes the config's folder to the room, whose submit panel reads its photos from there
signal ipdb_snapshot_requested ## IPDBFIX: re-apply the bundled IPDB snapshot to the cache (the CARDBACK live fetch is retired - IPDB's site refuses app requests): Main owns the cache and answers on the IPDB status line
signal wovp_test_requested(api_key: String) ## Test key: Main validates this text against WoVP and answers on the status line
signal wovp_submit_requested(challenge_id: String, photo_path: String, score_text: String) ## Submit a score (the SUBMIT round): Main runs the two-step WoVP submission and answers on the submit status line. score_text is the SUBMIT2 record field's raw text - Main parses it into the LOCAL log only; it never rides the wire

var _config: PvldsConfig
var _filling_from_config: bool = false ## true while _fill_from_config sets widget state (its signal emissions are not user flips)
var _exe_edit: LineEdit
var _args_edit: LineEdit
var _herding_check: CheckBox
var _db_edit: LineEdit
var _folder_rows: VBoxContainer
var _folder_edits: Array[LineEdit] = []
var _scan_button: Button
var _stats_label: Label
var _b2s_label: Label
var _b2s_button: Button
var _unplaced_label: Label
var _unplaced_button: Button
var _enter_button: Button
var _dialog: FileDialog
var _dialog_target: String = "" ## "exe" | "db" | "photo" | "folder:<index>"
var _scanned: bool = false
var _dl_button: Button
var _dl_label: Label
var _downloader: VpsDownloader
var _wovp_edit: LineEdit
var _wovp_save_button: Button
var _wovp_test_button: Button
var _wovp_label: Label
var _submit_picker: OptionButton
var _submit_info: Label
var _submit_photo_button: Button
var _submit_photo_label: Label
var _submit_preview: TextureRect
var _submit_preview_frame: PanelContainer ## SETUPLOOK: the preview's inset frame; stands and hides with the preview
var _submit_verify_label: Label
var _submit_button: Button
var _submit_label: Label
var _submit_score_edit: LineEdit ## SUBMIT2: the optional score-record field - his notebook, never sent
var _submit_history_title: Label ## SUBMIT2: "Your recent submissions" - stands only when the log has entries
var _submit_history_label: Label ## SUBMIT2: Main-built lines from the local submission log, newest first
var _submit_rows: Array = [] ## Main's submit rows (set_wovp_submit_data): one Dictionary per live challenge
var _submit_photo_path: String = "" ## the chosen score photo (filesystem path); only its name is ever shown or logged
var _submit_has_key: bool = false
var _pinemhi_edit: LineEdit
var _pinemhi_check: CheckBox
var _pinemhi_manage_check: CheckBox ## PINEMHI2 (Part B): the watcher-management toggle - saved with the PINemHi section's Save, read by the watchdog via the contract mirror
var _pinemhi_label: Label
var _shots_edit: LineEdit
var _shots_label: Label
var _ipdb_label: Label
var _title_label: Label ## the title block: "FIRST SETUP"
var _title_box: VBoxContainer ## DESKEDIT: the head panel's box - holds the title ALONE (census: title_dress)
var _advanced_fold: _Fold ## DESKEDIT: the Advanced fold (the Launch arguments template's home)
var _db_note: Label ## DESKEDIT: the VPS database explanation line under the field
var _herding_note: Label ## DESKEDIT: the Focus herding explanation line under the checkbox
var _details_fold: _Fold ## DESKEDIT: the Scan details fold (the scan summary's diagnostics)
var _details_label: Label ## DESKEDIT: the folded diagnostics text inside the Scan details fold

const MAX_FOLDER_ROWS: int = 6


## DESKEDIT: one collapsible desk section - a dressed toggle
## row (a checkable Button in the theme's button dress, a
## disclosure marker at its head) over a content box. Starts
## collapsed; while collapsed the content is hidden, which
## also keeps it out of the keyboard flow (hidden controls
## are skipped); expanded, the content joins the flow right
## after the toggle. Used by Advanced and Scan details.
class _Fold:
	var root: VBoxContainer
	var toggle: Button
	var content: VBoxContainer
	var title: String

	func set_expanded(expanded: bool) -> void:
		toggle.set_pressed_no_signal(expanded)
		content.visible = expanded
		toggle.text = ("▾ " if expanded else "▸ ") + title

	func is_expanded() -> bool:
		return content.visible


func setup(config: PvldsConfig) -> void:
	_config = config
	_build_ui()
	_fill_from_config()
	# DESKEDIT: both folds start collapsed on EVERY desk
	# show, not just the first - leaving to the room and
	# coming back re-folds what was opened.
	visibility_changed.connect(func() -> void:
		if visible:
			_reset_folds())


func _make_fold(parent: VBoxContainer, title: String) -> _Fold:
	var f: _Fold = _Fold.new()
	f.title = title
	f.root = VBoxContainer.new()
	f.root.add_theme_constant_override("separation", 8)
	parent.add_child(f.root)
	f.toggle = Button.new()
	f.toggle.toggle_mode = true
	f.toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	f.toggle.text = "▸ " + title
	f.toggle.toggled.connect(func(on: bool) -> void: f.set_expanded(on))
	f.root.add_child(f.toggle)
	f.content = VBoxContainer.new()
	f.content.add_theme_constant_override("separation", 8)
	f.content.visible = false
	f.root.add_child(f.content)
	return f


func _reset_folds() -> void:
	if _advanced_fold != null:
		_advanced_fold.set_expanded(false)
	if _details_fold != null:
		_details_fold.set_expanded(false)


## Smoke census of the title block (the BOOTFACE legs). The
## desk wears its full FIRST SETUP dress on every show since
## BOOTFACE: the boot pass has its own face now, so the desk
## only ever stands when it is stood upon for real (BOOTSHELL's
## two-dress machinery is retired). DESKEDIT: the dress is
## the title ALONE - both sub-lines are deleted (the "Done
## once" line by Chris's order, the IN-VR pointer because a
## first-timer hasn't met the room yet), so the census reads
## the head panel's child count: 1 means the title alone.
func title_dress() -> Dictionary:
	return {
		"title": _title_label.text if _title_label != null else "",
		"panel_children": _title_box.get_child_count() if _title_box != null else 0,
	}


func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	# SETUPLOOK: the desk ground is the graphite family's
	# dark stop, and the whole form wears the Machined theme
	# (DeskTheme) - set on the scroll, so it reaches every
	# control in the form and nothing outside it.
	bg.color = DeskTheme.GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.theme = DeskTheme.build()
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

	# SETUPLOOK: the title block stands in a machined header
	# panel - the desk's name plate, worn like a strip stop
	# (accent gradient, the standing underline, the title in
	# the house display type).
	var title_panel: PanelContainer = PanelContainer.new()
	title_panel.add_theme_stylebox_override("panel", DeskTheme.title_header_box())
	vbox.add_child(title_panel)
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 4)
	title_panel.add_child(_title_box)
	_title_label = Label.new()
	# ENDGAME (Part A): the two setups carry two names. This
	# desk is FIRST SETUP - the one-time, important initial
	# setup; the room's panel is IN-VR SETUP.
	# DESKEDIT: the panel holds the title ALONE. Both
	# sub-lines are gone - "Done once, on your PC, before you
	# play." by Chris's order, and the pointer to the IN-VR
	# panel because a first-time user hasn't seen the room
	# yet and shouldn't be told about surfaces he hasn't met.
	# The desk goes straight into the work (the intro below).
	_title_label.text = "FIRST SETUP"
	_title_label.add_theme_font_override("font", DeskTheme.FONT_MEDIUM)
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	_title_box.add_child(_title_label)
	var intro: Label = Label.new()
	intro.text = "Point LaunchPin at your VPX executable and your table folder(s). The headset room is for playing, not setup."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	_exe_edit = _add_path_row(vbox, "VPX executable", "Browse...", "exe")
	_db_edit = _add_path_row(vbox, "VPS database (vpsdb.json, optional)", "Browse...", "db")
	# DESKEDIT: say what the thing IS - a first-timer is
	# otherwise asked to point at a file he has never heard
	# of (Chris's wording, FINAL).
	_db_note = Label.new()
	_db_note.text = "The community catalog of VPX tables — names, makers, cover art. LaunchPin carries a copy and can download a fresh one below; this field is only for using your own."
	_db_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_db_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	vbox.add_child(_db_note)
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
	# The download itself is the shared service (core/vps_downloader.gd)
	# - the room's SETUP panel runs the same one. This desk only owns
	# its button, its label, and its success tail ("next Save & Scan").
	_downloader = VpsDownloader.new()
	add_child(_downloader)
	_downloader.progress.connect(func(text: String) -> void: _dl_label.text = text)
	_downloader.finished.connect(_on_download_finished)
	# DESKEDIT: the Launch arguments template is buried
	# under an Advanced fold standing where the field stood
	# - a technical field a first-timer should not have to
	# wonder about. The field itself is untouched (same
	# config key, same collect/save); only Launch Arguments
	# goes under the fold, nothing else is swept in.
	_advanced_fold = _make_fold(vbox, "Advanced")
	_args_edit = _add_field(_advanced_fold.content, "Launch arguments template ({table} is the table file; quotes group arguments)")
	var args_note: Label = Label.new()
	args_note.text = "The command line VPX is started with. The default starts the table you picked — change it only if your VPX setup needs special switches."
	args_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	args_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	_advanced_fold.content.add_child(args_note)
	_herding_check = CheckBox.new()
	# DESKEDIT: the short label, with the explanation as a
	# sub-line under it (Chris's wording, FINAL) - the old
	# one-string label named a mechanism a first-timer
	# could not be expected to know.
	_herding_check.text = "Focus herding"
	_herding_check.tooltip_text = "During the launch settle and during play, the watchdog returns foreground focus to the VPX window when something steals it. It never moves or resizes windows."
	_herding_check.toggled.connect(func(_on: bool) -> void: _apply_session_settings())
	vbox.add_child(_herding_check)
	_herding_note = Label.new()
	_herding_note.text = "While you play, LaunchPin keeps the game's window in front, so nothing else on your PC can pop over it and break the view in the headset. It's on because a window stealing the game mid-play is the common failure — turn it off only if it fights another program on your machine."
	_herding_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_herding_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	vbox.add_child(_herding_note)

	# The WoVP section (the Tournament Room round): his
	# World of Virtual Pinball API key - self-service in his
	# WoVP profile, pasted here once. Like the session
	# switch, the key is a live setting: Save key writes the
	# config on the spot (no Save & Scan), Test key validates
	# the field's text and names whose key it is. The field
	# is masked - it is a secret, and it is never printed.
	vbox.add_child(_section_header("World of Virtual Pinball (WoVP) - the Tournament Room's boards"))
	var wovp_intro: Label = Label.new()
	wovp_intro.text = "Your WoVP API key (from your WoVP profile) shows your live league boards in the Tournament Room. Stored only in the config file on this PC."
	wovp_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(wovp_intro)
	_wovp_edit = LineEdit.new()
	_wovp_edit.secret = true
	_wovp_edit.placeholder_text = "Paste your WoVP API key here"
	vbox.add_child(_wovp_edit)
	var wovp_row: HBoxContainer = HBoxContainer.new()
	wovp_row.add_theme_constant_override("separation", 8)
	vbox.add_child(wovp_row)
	_wovp_save_button = Button.new()
	_wovp_save_button.text = "Save key"
	_wovp_save_button.pressed.connect(_on_wovp_save_pressed)
	wovp_row.add_child(_wovp_save_button)
	_wovp_test_button = Button.new()
	_wovp_test_button.text = "Test key"
	_wovp_test_button.pressed.connect(_on_wovp_test_pressed)
	wovp_row.add_child(_wovp_test_button)
	_wovp_label = Label.new()
	_wovp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wovp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wovp_row.add_child(_wovp_label)

	# The score submission section (the SUBMIT round): the
	# desk half of the WoVP write side. Pick a live
	# challenge, attach the score photo (taken the league's
	# own way - the Quest camera method - and moved to this
	# PC), and submit: Main runs the two-step call and the
	# verdict lands on the status line. The rows Main pushes
	# (set_wovp_submit_data) carry the challenge's library
	# state and the standing warning - the league accepts
	# only a HIGHER score than the one already posted - so
	# both are read BEFORE anything is sent. Nothing here
	# gates on the library state: it is shown, never a lock.
	vbox.add_child(_section_header("Submit a score to WoVP"))
	var submit_intro: Label = Label.new()
	submit_intro.text = "Finished a game on a live challenge? Take the photo the league's way (last score, DMD and full playfield in frame), move it to this PC, then pick the challenge and the photo here. The photo carries the score; the league validates it."
	submit_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(submit_intro)
	_submit_picker = OptionButton.new()
	_submit_picker.item_selected.connect(_on_submit_challenge_selected)
	vbox.add_child(_submit_picker)
	# SETUPLOOK: the picker's dropdown lives outside the
	# form's theme chain (it is a popup window), so it is
	# dressed directly, in the same family.
	var picker_popup: PopupMenu = _submit_picker.get_popup()
	picker_popup.add_theme_stylebox_override("panel", DeskTheme.popup_panel_box())
	picker_popup.add_theme_stylebox_override("hovered", DeskTheme.popup_hover_box())
	picker_popup.add_theme_color_override("font_color", Color(0.87, 0.88, 0.93))
	picker_popup.add_theme_color_override("font_hovered_color", Color(1, 1, 1))
	_submit_info = Label.new()
	_submit_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_submit_info.text = "No WoVP key saved - save your key above first; submissions use the same key."
	vbox.add_child(_submit_info)
	var submit_photo_row: HBoxContainer = HBoxContainer.new()
	submit_photo_row.add_theme_constant_override("separation", 8)
	vbox.add_child(submit_photo_row)
	_submit_photo_button = Button.new()
	_submit_photo_button.text = "Choose photo..."
	_submit_photo_button.pressed.connect(func() -> void: _open_dialog_for("photo"))
	submit_photo_row.add_child(_submit_photo_button)
	_submit_photo_label = Label.new()
	_submit_photo_label.text = "No photo chosen yet."
	_submit_photo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submit_photo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	submit_photo_row.add_child(_submit_photo_label)
	# The verify step (Chris's field note, 2026-11-06): the
	# pick is not done when the file is named. Some tables
	# blink their score displays by design - Bad Cats gave
	# him 1 readable frame in 5 - so the chosen frame stands
	# here, big enough to read the score in it, and a blank
	# catch is rejected at the desk by his own eyes before
	# the submit button is ever used.
	# SETUPLOOK: the preview sits in a dark inset frame in
	# the field family - the photo is the content; the frame
	# is the desk's furniture around it.
	_submit_preview_frame = PanelContainer.new()
	_submit_preview_frame.add_theme_stylebox_override("panel", DeskTheme.inset_box())
	_submit_preview_frame.visible = false
	vbox.add_child(_submit_preview_frame)
	_submit_preview = TextureRect.new()
	_submit_preview.custom_minimum_size = Vector2(520, 390)
	_submit_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_submit_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_submit_preview.visible = false
	_submit_preview_frame.add_child(_submit_preview)
	_submit_verify_label = Label.new()
	_submit_verify_label.text = "Read the score in this frame before submitting - some tables blink their displays, and a photo caught mid-blink carries no score."
	_submit_verify_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_submit_verify_label.visible = false
	vbox.add_child(_submit_verify_label)
	# SUBMIT2: the score-record field. What he types is
	# his own notebook - it lands in the local submission
	# log beside the attempt and NOWHERE else: the league
	# reads the score off the photo, and the payload keeps
	# its 0 stub. Its one job is memory: the league's own
	# History page is otherwise the only place a submitted
	# score can be looked back up, and a blind (Knockout)
	# round shows nobody's number anywhere.
	var submit_score_row: HBoxContainer = HBoxContainer.new()
	submit_score_row.add_theme_constant_override("separation", 8)
	vbox.add_child(submit_score_row)
	var submit_score_label: Label = Label.new()
	submit_score_label.text = "Score in this photo (optional - your record only):"
	submit_score_label.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	submit_score_row.add_child(submit_score_label)
	_submit_score_edit = LineEdit.new()
	_submit_score_edit.placeholder_text = "e.g. 16,638,090 - leave empty to skip"
	_submit_score_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit_score_row.add_child(_submit_score_edit)
	var submit_row: HBoxContainer = HBoxContainer.new()
	submit_row.add_theme_constant_override("separation", 8)
	vbox.add_child(submit_row)
	_submit_button = Button.new()
	_submit_button.text = "Submit score"
	_submit_button.pressed.connect(_on_submit_pressed)
	submit_row.add_child(_submit_button)
	_submit_label = Label.new()
	_submit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	submit_row.add_child(_submit_label)
	# SUBMIT2: the receipt book, on the desk - his recent
	# submissions read back from the local log (Main builds
	# the lines: date, challenge, his recorded score when
	# he typed one, the outcome). Stands only when the log
	# has entries: no empty furniture.
	_submit_history_title = Label.new()
	_submit_history_title.text = "Your recent submissions"
	_submit_history_title.visible = false
	vbox.add_child(_submit_history_title)
	_submit_history_label = Label.new()
	_submit_history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_submit_history_label.visible = false
	vbox.add_child(_submit_history_label)

	# The Screenshots section (ROOMSUBMIT): the folder his
	# headset score screenshots land in. The in-room submit
	# panel reads its photos from there - newest first, one
	# standing large for the flicker check - so a score can
	# be sent without leaving the room. Like the key and
	# the PINemHi settings, this is a live setting: Save
	# writes the config on the spot. No toggle: an unset
	# folder is the off state, and the panel says so.
	vbox.add_child(_section_header("Screenshots - the folder your score photos land in"))
	var shots_intro: Label = Label.new()
	shots_intro.text = "The folder your headset screenshots end up in on this PC. In the Tournament Room, press Y on a challenge card: the newest shots here stand on the submit panel - pick the one that shows your score and send it, headset on. Same key, same send as the desk above."
	shots_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(shots_intro)
	var shots_row: HBoxContainer = HBoxContainer.new()
	shots_row.add_theme_constant_override("separation", 8)
	vbox.add_child(shots_row)
	_shots_edit = LineEdit.new()
	_shots_edit.placeholder_text = "Screenshots folder - where your headset shots land"
	_shots_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shots_row.add_child(_shots_edit)
	var shots_browse: Button = Button.new()
	shots_browse.text = "Browse..."
	shots_browse.pressed.connect(func() -> void: _open_dialog_for("shots"))
	shots_row.add_child(shots_browse)
	var shots_save_row: HBoxContainer = HBoxContainer.new()
	shots_save_row.add_theme_constant_override("separation", 8)
	vbox.add_child(shots_save_row)
	var shots_save: Button = Button.new()
	shots_save.text = "Save screenshots folder"
	shots_save.pressed.connect(_on_shots_save_pressed)
	shots_save_row.add_child(shots_save)
	_shots_label = Label.new()
	_shots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shots_save_row.add_child(_shots_label)

	# The PINemHi section (NEXTROUND item 4): the folder
	# PVLDS READS TOP10_Personal files from, plus the
	# toggle. Reading is the whole story by default - PVLDS
	# reads the leaderboard files an existing install
	# leaves behind and shows your own #1 under the league
	# scores on a tournament board. PINEMHI2 (Part B) adds
	# ONE opt-in on top of that: the watcher checkbox below
	# lets PVLDS run PINemHi's watcher while a table is
	# playing (WATCHERLIFE: its life is the session's, never
	# the app's open hours - see its label). Like the key,
	# these are live
	# settings: Save writes the config on the spot.
	vbox.add_child(_section_header("PINemHi - your personal bests on the tournament boards"))
	var pinemhi_intro: Label = Label.new()
	pinemhi_intro.text = "If you use PINemHi, LaunchPin can read its TOP10_Personal files and show your best beneath the league scores on a tournament board. That's all it does by default - it never runs PINemHi or its watcher unless you opt in below. Leave the folder empty to auto-detect the usual install places (D:\\vPinball\\Pinemhi and friends)."
	pinemhi_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(pinemhi_intro)
	_pinemhi_check = CheckBox.new()
	_pinemhi_check.text = "Show my PINemHi personal bests on tournament boards"
	vbox.add_child(_pinemhi_check)
	_pinemhi_manage_check = CheckBox.new()
	_pinemhi_manage_check.text = "Let PVLDS run the PINemHi watcher while a table is playing"
	_pinemhi_manage_check.tooltip_text = "Off (the default): LaunchPin never touches the watcher. On: the watchdog starts pinemhi_rom_monitor.exe when a table starts (if it isn't already running) and closes it shortly after the table exits - or when LaunchPin exits, if that comes first. A watcher already running is left running: LaunchPin only ever closes one it started itself."
	vbox.add_child(_pinemhi_manage_check)
	_pinemhi_edit = LineEdit.new()
	_pinemhi_edit.placeholder_text = "PINemHi folder - empty = auto-detect"
	vbox.add_child(_pinemhi_edit)
	var pinemhi_row: HBoxContainer = HBoxContainer.new()
	pinemhi_row.add_theme_constant_override("separation", 8)
	vbox.add_child(pinemhi_row)
	var pinemhi_save: Button = Button.new()
	pinemhi_save.text = "Save PINemHi settings"
	pinemhi_save.pressed.connect(_on_pinemhi_save_pressed)
	pinemhi_row.add_child(pinemhi_save)
	_pinemhi_label = Label.new()
	_pinemhi_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pinemhi_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pinemhi_row.add_child(_pinemhi_label)

	# The IPDB section (CARDBACK, reshaped by IPDBFIX):
	# the card backs' second well. The facts ship BUNDLED
	# with PVLDS - a snapshot of the Internet Pinball
	# Database taken when the app was built - and seed the
	# cache at boot; the app never fetches from IPDB
	# directly (its site refuses requests from apps). The
	# button re-applies the bundled snapshot, the useful
	# move after a cache clear; a snapshot refresh rides
	# a PVLDS update.
	vbox.add_child(_section_header("IPDB data - the card backs' second well"))
	var ipdb_intro: Label = Label.new()
	ipdb_intro.text = "Each card's back mixes the database's facts with the Internet Pinball Database's (production run, fun rating, full credits, notable features), each row dotted with its source. The IPDB facts ship bundled as a snapshot and apply automatically; the backs read the saved copy and never go online. Games with no IPDB link in the database show database rows only."
	ipdb_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(ipdb_intro)
	var ipdb_row: HBoxContainer = HBoxContainer.new()
	ipdb_row.add_theme_constant_override("separation", 8)
	vbox.add_child(ipdb_row)
	var ipdb_apply: Button = Button.new()
	ipdb_apply.text = "Re-apply bundled IPDB data"
	ipdb_apply.pressed.connect(func() -> void: ipdb_snapshot_requested.emit())
	ipdb_row.add_child(ipdb_apply)
	_ipdb_label = Label.new()
	_ipdb_label.text = "IPDB data: bundled snapshot not applied yet."
	_ipdb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ipdb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ipdb_row.add_child(_ipdb_label)
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

	# DESKEDIT: the scan summary's diagnostics live in a
	# Scan details fold under the stats area - the standing
	# area carries the answers (headline + the plain
	# database line); the workshop numbers wait in the fold
	# for whoever goes looking. The fold stands only when a
	# scan's details exist (no empty furniture before the
	# first scan) and starts collapsed like every fold.
	_details_fold = _make_fold(vbox, "Scan details")
	_details_label = Label.new()
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_fold.content.add_child(_details_label)
	_details_fold.root.visible = false

	var b2s_row: HBoxContainer = HBoxContainer.new()
	b2s_row.add_theme_constant_override("separation", 8)
	vbox.add_child(b2s_row)
	_b2s_label = Label.new()
	_b2s_label.text = "Missing backglass: not scanned yet - the list is written on every scan."
	_b2s_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_b2s_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b2s_row.add_child(_b2s_label)
	_b2s_button = Button.new()
	_b2s_button.text = "Open list"
	_b2s_button.disabled = true
	_b2s_button.tooltip_text = "Open missing_b2s.txt - the table files with no backglass - from the app data folder"
	_b2s_button.pressed.connect(_on_open_b2s_list)
	b2s_row.add_child(_b2s_button)

	var unplaced_row: HBoxContainer = HBoxContainer.new()
	unplaced_row.add_theme_constant_override("separation", 8)
	vbox.add_child(unplaced_row)
	_unplaced_label = Label.new()
	_unplaced_label.text = "Files I couldn't place: not scanned yet - the list is written on every scan."
	_unplaced_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unplaced_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unplaced_row.add_child(_unplaced_label)
	_unplaced_button = Button.new()
	_unplaced_button.text = "Open list"
	_unplaced_button.disabled = true
	_unplaced_button.tooltip_text = "Open unplaced_files.txt - the table files that match no database game - from the app data folder"
	_unplaced_button.pressed.connect(_on_open_unplaced_list)
	unplaced_row.add_child(_unplaced_button)

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


func _folder_label() -> PanelContainer:
	return _section_header("Table folders")


## SETUPLOOK: a section header bar - the section's name in
## the house display type on the resting graphite gradient,
## in the strip segment's manner, instead of a plain bold
## label. Dress only: the words and the order never move.
func _section_header(text: String) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", DeskTheme.section_header_box())
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", DeskTheme.FONT_MEDIUM)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_ACCENT)
	p.add_child(l)
	return p


func _add_field(parent: VBoxContainer, label_text: String) -> LineEdit:
	var l: Label = Label.new()
	l.text = label_text
	# SETUPLOOK: field labels wear the strip's resting grey.
	l.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	parent.add_child(l)
	var edit: LineEdit = LineEdit.new()
	parent.add_child(edit)
	return edit


func _add_path_row(parent: VBoxContainer, label_text: String, button_text: String, target: String) -> LineEdit:
	var l: Label = Label.new()
	l.text = label_text
	l.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
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
	elif target == "photo":
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.filters = PackedStringArray(["*.jpg, *.jpeg, *.png ; Score photos"])
		_dialog.title = "Choose the score photo (last score - DMD and full playfield in frame)"
	elif target == "shots":
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.title = "Pick the folder your headset screenshots land in"
	else:
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.title = "Pick a folder full of .vpx tables"
	_dialog.popup_centered_ratio(0.75)


func _on_dialog_file(path: String) -> void:
	if _dialog_target == "exe":
		_exe_edit.text = path
	elif _dialog_target == "db":
		_db_edit.text = path
	elif _dialog_target == "photo":
		_submit_photo_path = path
		_submit_photo_label.text = path.get_file()
		_show_submit_preview(path)


func _on_dialog_dir(path: String) -> void:
	if _dialog_target == "shots":
		_shots_edit.text = path
	elif _dialog_target.begins_with("folder:"):
		var idx: int = _dialog_target.trim_prefix("folder:").to_int()
		if idx >= 0 and idx < _folder_edits.size():
			_folder_edits[idx].text = path


func _fill_from_config() -> void:
	_filling_from_config = true
	_exe_edit.text = _config.vpx_exe_path
	_db_edit.text = _config.vpsdb_path
	_args_edit.text = _config.launch_args_template
	_wovp_edit.text = _config.wovp_api_key
	_wovp_label.text = "A key is saved on this PC." if _config.wovp_api_key != "" else "No key saved yet."
	_pinemhi_edit.text = _config.pinemhi_folder
	_pinemhi_check.button_pressed = _config.pinemhi_enabled
	_pinemhi_manage_check.button_pressed = _config.pinemhi_manage_watcher
	_pinemhi_label.text = PinemhiScores.status_line(_config)
	_shots_edit.text = _config.screenshots_folder
	_shots_label.text = ShotsFolder.status_line(_config)
	_fill_session_widgets()
	for f: String in _config.table_folders:
		_add_folder_row(f)
	if _folder_edits.is_empty():
		_add_folder_row("")
	_filling_from_config = false


## The session widget from the config - the fill half of the
## live-settings pair (see _apply_session_settings). Focus herding
## is the only session switch left: the close duty lost its
## checkbox when the exit model was simplified (the watchdog
## closes the editor unconditionally now), and hold-to-exit was
## stricken outright (2026-10-22).
func _fill_session_widgets() -> void:
	_herding_check.button_pressed = _config.focus_herding


func _on_use_dummy() -> void:
	_exe_edit.text = PvldsConfig.DEFAULT_EXE_NAME
	_db_edit.text = ProjectSettings.globalize_path("res://data/vpsdb.json")
	for edit: LineEdit in _folder_edits:
		edit.text = ""
	_folder_edits[0].text = ProjectSettings.globalize_path("res://dummy_data/tables")


func _collect_into_config() -> void:
	_config.vpx_exe_path = _exe_edit.text.strip_edges()
	_config.vpsdb_path = _db_edit.text.strip_edges()
	_config.wovp_api_key = _wovp_edit.text.strip_edges()
	_config.pinemhi_folder = _pinemhi_edit.text.strip_edges()
	_config.pinemhi_enabled = _pinemhi_check.button_pressed
	_config.pinemhi_manage_watcher = _pinemhi_manage_check.button_pressed
	_config.screenshots_folder = _shots_edit.text.strip_edges()
	_config.launch_args_template = _args_edit.text.strip_edges()
	if _config.launch_args_template == "":
		_config.launch_args_template = PvldsConfig.DEFAULT_LAUNCH_ARGS
	_collect_session_settings()
	_config.table_folders.clear()
	for edit: LineEdit in _folder_edits:
		var f: String = edit.text.strip_edges()
		if f != "":
			_config.table_folders.append(f)


## Just the session switch out of the widget - shared by the
## full Save & Scan collect and the live apply below.
func _collect_session_settings() -> void:
	_config.focus_herding = _herding_check.button_pressed


## The session switch (focus herding) is a live setting, not form
## data: it applies the moment it is flipped - collect just that
## field and save, no scan, no other side effects. Everything
## else on this desk (paths, template, folders) stays on the
## Save & Scan model, so half-typed text never half-saves.
## (Before this, the switches were only read on Save & Scan, so a
## flip followed by Enter the Room silently did nothing - Chris's
## isolation test, 2026-10-21.) A failed save restores the config
## and the widget to exactly what they were and says so in the
## stats area: a switch that did not save must not look - or act -
## flipped.
func _apply_session_settings() -> void:
	if _filling_from_config or _config == null:
		return
	var prev_herding: bool = _config.focus_herding
	_collect_session_settings()
	if _config.save_to_disk():
		return
	_config.focus_herding = prev_herding
	_filling_from_config = true
	_fill_session_widgets()
	_filling_from_config = false
	if _stats_label != null:
		_stats_label.text = "That setting could NOT be saved - the config file is not writable, so the switch was put back as it was. Fix the config file, then flip it again."


## Save key: the live apply, on the herding pattern - the
## key lands in the config file the moment the button is
## pressed, and a failed save restores field, config, and
## label to exactly what they were (a key that did not save
## must not look saved). A wrong-length key still saves -
## his pasteboard, his call - but the line says so in
## words (WoVP's keys are 32 characters; the client would
## refuse to test this one). The emit lets Main refresh the
## Tournament Room's boards with the new key.
func _on_wovp_save_pressed() -> void:
	if _config == null:
		return
	var prev: String = _config.wovp_api_key
	_config.wovp_api_key = _wovp_edit.text.strip_edges()
	if _config.save_to_disk():
		if _config.wovp_api_key == "":
			_wovp_label.text = "Key cleared - the Tournament Room will ask for one."
		else:
			_wovp_label.text = "Key saved on this PC."
			var length_note: String = WovpClient.key_length_note(_config.wovp_api_key)
			if length_note != "":
				_wovp_label.text += " " + length_note
		wovp_key_saved.emit()
		return
	_config.wovp_api_key = prev
	_wovp_edit.text = prev
	_wovp_label.text = "That key could NOT be saved - the config file is not writable, so nothing changed. Fix the config file, then save it again."


## Test key: validates the field's text - what he pasted,
## saved or not - so the answer names the key he is looking
## at. Main owns the client; the verdict lands on the
## status line via set_wovp_status. A wrong-length key is
## refused HERE, in words, and nothing is sent - WoVP's
## answer to it is already known (its 32-character rule),
## so the line says it instead of spending the request.
func _on_wovp_test_pressed() -> void:
	var text: String = _wovp_edit.text.strip_edges()
	if text == "":
		_wovp_label.text = "Nothing to test - paste your WoVP key into the field first."
		return
	var length_note: String = WovpClient.key_length_note(text)
	if length_note != "":
		_wovp_label.text = length_note
		return
	_wovp_label.text = "Testing that key..."
	wovp_test_requested.emit(text)


## Main's WoVP verdicts (test results, fetch outcomes) in
## the section's own status line.
func set_wovp_status(text: String) -> void:
	_wovp_label.text = text


## Main's standing challenge data for the submit section
## (the SUBMIT round): one row per live challenge, rebuilt
## on every boards/identity/scan change so the picker never
## offers a dead challenge or a stale warning. The selected
## challenge survives a rebuild when it is still live. The
## library state in a row is information, never a gate -
## the picker offers every live challenge, owned or not.
func set_wovp_submit_data(rows: Array, has_key: bool) -> void:
	var keep_id: String = ""
	var current: Dictionary = _selected_submit_row()
	if not current.is_empty():
		keep_id = str(current.get("challenge_id", ""))
	_submit_rows = rows
	_submit_has_key = has_key
	if _submit_picker == null:
		return
	_submit_picker.clear()
	for rv: Variant in rows:
		var row: Dictionary = rv as Dictionary
		_submit_picker.add_item(str(row.get("picker_text", "")))
	if not rows.is_empty():
		var sel: int = 0
		for i: int in range(rows.size()):
			if str((rows[i] as Dictionary).get("challenge_id", "")) == keep_id:
				sel = i
				break
		_submit_picker.selected = sel
	_submit_picker.disabled = not has_key
	_submit_button.disabled = not has_key
	_submit_photo_button.disabled = not has_key
	if _submit_score_edit != null:
		_submit_score_edit.editable = has_key
	_refresh_submit_info()


func _selected_submit_row() -> Dictionary:
	if _submit_picker == null or _submit_rows.is_empty():
		return {}
	var idx: int = _submit_picker.selected
	if idx < 0 or idx >= _submit_rows.size():
		return {}
	return _submit_rows[idx] as Dictionary


func _on_submit_challenge_selected(_idx: int) -> void:
	_refresh_submit_info()


## The chosen challenge's whole case, in plain lines: what
## it is, when it ends, where the library stands on it, and
## the standing warning - his posted score named, or the
## open door when he has none. Read BEFORE the submit, by
## design: the league accepts only a higher score, and a
## submission spent under a score it cannot beat is spent
## for nothing.
func _refresh_submit_info() -> void:
	if _submit_info == null:
		return
	if not _submit_has_key:
		_submit_info.text = "No WoVP key saved - save your key above first; submissions use the same key."
		return
	var row: Dictionary = _selected_submit_row()
	if row.is_empty():
		_submit_info.text = "No live challenges right now - once the boards fetch lands, the challenges to submit to stand here."
		return
	var lines: Array[String] = []
	lines.append("%s - %s" % [str(row.get("type_label", "")), str(row.get("table_name", ""))])
	lines.append("Ends " + str(row.get("deadline_text", "")))
	lines.append(str(row.get("library_note", "")))
	var posted: String = str(row.get("posted_note", ""))
	if posted != "":
		lines.append(posted)
	var vpx: String = str(row.get("vpx_file", ""))
	lines.append("Sent with the photo: your file name for the challenge's build (%s)." % (vpx if vpx != "" else "none - no matched build"))
	_submit_info.text = "\n".join(lines)


## Submit: the guards speak in words on the status line
## (no key, no challenge, no photo), then the request rides
## to Main - the client, the metadata, and the log are all
## Main's side of the desk's signal discipline.
func _on_submit_pressed() -> void:
	if not _submit_has_key:
		_submit_label.text = "No WoVP key saved - save your key above first; submissions use the same key."
		return
	var row: Dictionary = _selected_submit_row()
	if row.is_empty():
		_submit_label.text = "No live challenge to submit to right now."
		return
	if _submit_photo_path == "":
		_submit_label.text = "Choose the score photo first."
		return
	_submit_label.text = "Submitting..."
	wovp_submit_requested.emit(str(row.get("challenge_id", "")), _submit_photo_path,
		_submit_score_edit.text if _submit_score_edit != null else "")


## Main's submission verdict (success or the server's own
## refusal words) in the section's status line.
func set_wovp_submit_status(text: String) -> void:
	if _submit_label != null:
		_submit_label.text = text


## The receipt book's lines (SUBMIT2): Main reads the
## local submission log and builds one line per recent
## attempt - date, challenge, his recorded score when he
## typed one, the outcome - newest first. An empty log
## hides the block entirely: no empty furniture.
func set_wovp_submission_history(lines: Array) -> void:
	if _submit_history_label == null:
		return
	var texts: Array[String] = []
	for lv: Variant in lines:
		texts.append(str(lv))
	_submit_history_label.text = "\n".join(texts)
	var stands: bool = not texts.is_empty()
	_submit_history_label.visible = stands
	if _submit_history_title != null:
		_submit_history_title.visible = stands


## The chosen photo stands on the desk (the verify step -
## see the preview's note in _ready): the frame itself,
## fitted whole into a box big enough to read a score in.
## A file that cannot be read as an image says so in
## words and shows nothing - an unverifiable photo is
## called out here, not discovered by an admin.
func _show_submit_preview(path: String) -> void:
	if _submit_preview == null:
		return
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		_submit_preview.texture = null
		_submit_preview.visible = false
		_submit_preview_frame.visible = false
		_submit_verify_label.visible = false
		_submit_photo_label.text = path.get_file() + " - this file could not be read as an image."
		return
	_submit_preview.texture = ImageTexture.create_from_image(img)
	_submit_preview.visible = true
	_submit_preview_frame.visible = true
	_submit_verify_label.visible = true


## Save PINemHi settings: the live apply, on the WoVP key
## pattern - folder + toggle land in the config file the
## moment the button is pressed; a failed save restores
## fields, config and label to exactly what they were.
## The status line always answers from a fresh read of the
## folder (PinemhiScores.status_line), so it says what
## PVLDS actually found there.
func _on_pinemhi_save_pressed() -> void:
	if _config == null:
		return
	var prev_folder: String = _config.pinemhi_folder
	var prev_enabled: bool = _config.pinemhi_enabled
	var prev_manage: bool = _config.pinemhi_manage_watcher
	_config.pinemhi_folder = _pinemhi_edit.text.strip_edges()
	_config.pinemhi_enabled = _pinemhi_check.button_pressed
	_config.pinemhi_manage_watcher = _pinemhi_manage_check.button_pressed
	if _config.save_to_disk():
		_pinemhi_label.text = PinemhiScores.status_line(_config)
		pinemhi_settings_saved.emit()
		return
	_config.pinemhi_folder = prev_folder
	_config.pinemhi_enabled = prev_enabled
	_config.pinemhi_manage_watcher = prev_manage
	_pinemhi_edit.text = prev_folder
	_pinemhi_check.button_pressed = prev_enabled
	_pinemhi_manage_check.button_pressed = prev_manage
	_pinemhi_label.text = "Those PINemHi settings could NOT be saved - the config file is not writable, so nothing changed. Fix the config file, then save again."


## Save screenshots folder: the live apply, on the
## PINemHi pattern - the folder lands in the config file
## the moment the button is pressed; a failed save
## restores field, config and label to exactly what they
## were. The status line always answers from a fresh read
## of the folder (ShotsFolder.status_line), so it says
## what PVLDS actually found there.
func _on_shots_save_pressed() -> void:
	if _config == null:
		return
	var prev_folder: String = _config.screenshots_folder
	_config.screenshots_folder = _shots_edit.text.strip_edges()
	if _config.save_to_disk():
		_shots_label.text = ShotsFolder.status_line(_config)
		screenshots_settings_saved.emit()
		return
	_config.screenshots_folder = prev_folder
	_shots_edit.text = prev_folder
	_shots_label.text = "That screenshots folder could NOT be saved - the config file is not writable, so nothing changed. Fix the config file, then save again."


## CARDBACK/IPDBFIX: Main drives the IPDB status line
## (coverage, the bundled snapshot's apply verdict).
func set_ipdb_status(text: String) -> void:
	if _ipdb_label != null:
		_ipdb_label.text = text


func wovp_key_text() -> String:
	return _wovp_edit.text.strip_edges()


func _on_download_pressed() -> void:
	# A press while one is running (or a start that fails on the
	# spot - its verdict arrives on finished, synchronously) does
	# nothing here; the label and button state are the handlers'.
	if _downloader.start_download():
		_dl_button.disabled = true
		_dl_label.text = "Downloading VPS database..."


## The download's verdict, from the shared service: the bare
## fact plus this desk's own tail on success, the failure in
## the service's (originally this desk's) words otherwise.
func _on_download_finished(ok: bool, message: String, downloaded_path: String) -> void:
	_dl_button.disabled = false
	if ok:
		_dl_label.text = message + " It will be used by the next Save & Scan."
		if _db_edit.text.strip_edges() == "":
			_db_edit.text = downloaded_path
	else:
		_dl_label.text = message


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
## before the user touches anything. A running scan supersedes
## the last scan's folded details, so the fold clears with the
## standing text.
func set_scan_progress(text: String) -> void:
	_stats_label.text = text
	_scan_button.disabled = true
	_enter_button.disabled = true
	_details_label.text = ""
	_details_fold.root.visible = false
	_details_fold.set_expanded(false)


## Final summary when a scan lands; re-arms the form.
## DESKEDIT: two-part - the standing answers go to the stats
## area; the diagnostics go to the Scan details fold, which
## stands iff the scan produced any. Every caller passes
## both parts (Main's two builders), so the fold never holds
## a previous scan's numbers under a new summary.
func apply_scan_summary(summary: String, details: String) -> void:
	_stats_label.text = summary
	_details_label.text = details
	_details_fold.root.visible = details != ""
	_scanned = summary != ""
	_enter_button.disabled = not _scanned
	_scan_button.disabled = false


## Smoke census of the DESKEDIT folds and texts.
func deskedit_census() -> Dictionary:
	return {
		"advanced_expanded": _advanced_fold != null and _advanced_fold.is_expanded(),
		"details_standing": _details_fold != null and _details_fold.root.visible,
		"details_expanded": _details_fold != null and _details_fold.is_expanded(),
		"details_text": _details_label.text if _details_label != null else "",
		"args_in_advanced": _args_edit != null and _advanced_fold != null and _advanced_fold.content.is_ancestor_of(_args_edit),
		"db_note": _db_note.text if _db_note != null else "",
		"herding_note": _herding_note.text if _herding_note != null else "",
	}


## The missing-backglass count from the scan that just landed
## (Main regenerates missing_b2s.txt in the same pass, from the
## scanner's pairing record). A zero count says so plainly; the
## button arms either way - at zero the file itself states that
## none are missing.
func apply_missing_b2s(count: int) -> void:
	if count > 0:
		_b2s_label.text = "Missing backglass: %d table file(s) have no .directb2s beside them. The full list is missing_b2s.txt in the app data folder." % count
	else:
		_b2s_label.text = "Missing backglass: none - every table file has a .directb2s beside it."
	_b2s_button.disabled = false


func _on_open_b2s_list() -> void:
	OS.shell_open(MissingB2sList.globalized_path())


## The couldn't-place count from the scan that just landed
## (IDENTITY: Main regenerates unplaced_files.txt in the same
## pass, from the scanner's match record). Mirrors
## apply_missing_b2s: a zero count says so plainly; the
## button arms either way - at zero the file itself states
## that none are unplaced.
func apply_unplaced(count: int) -> void:
	if count > 0:
		_unplaced_label.text = "Files I couldn't place: %d table file(s) match no database game. The full list is unplaced_files.txt in the app data folder." % count
	else:
		_unplaced_label.text = "Files I couldn't place: none - every table file matched a database game."
	_unplaced_button.disabled = false


func _on_open_unplaced_list() -> void:
	OS.shell_open(UnplacedFilesList.globalized_path())
