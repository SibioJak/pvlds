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
signal update_get_requested(url: String) ## AUTOFIND: the update banner's Get - Main opens the url (a browser is a PC act, and Main owns the update state)
signal update_later_pressed ## AUTOFIND: the update banner's Later - Main holds the session dismissal (it gates the room's segment too)
signal wovp_test_requested(api_key: String) ## Test key: Main validates this text against WoVP and answers on the status line

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
var _dialog_target: String = "" ## "exe" | "db" | "shots" | "folder:<index>"
var _scanned: bool = false
var _dl_button: Button
var _dl_label: Label
var _downloader: VpsDownloader
var _wovp_edit: LineEdit
var _wovp_save_button: Button
var _wovp_test_button: Button
var _wovp_label: Label
var _pinemhi_edit: LineEdit
var _pinemhi_check: CheckBox
var _pinemhi_manage_check: CheckBox ## PINEMHI2 (Part B): the watcher-management toggle - saved with the PINemHi section's Save, read by the watchdog via the contract mirror
var _pinemhi_label: Label
var _shots_edit: LineEdit
var _shots_label: Label
var _ipdb_label: Label
var _title_label: Label ## the title block: "Initial Setup" (DESKHEAD: renamed from FIRST SETUP)
var _title_box: VBoxContainer ## DESKEDIT: the head panel's box - holds the title ALONE (census: title_dress)
var _advanced_fold: _Fold ## DESKEDIT: the Advanced fold (the Launch arguments template's home)
var _db_note: Label ## DESKEDIT: the VPS database explanation line under the field
var _intro_label: Label ## DESKHEAD: the one-sentence intro under the head (census: deskedit_census)
var _herding_note: Label ## DESKEDIT: the Focus herding explanation line under the checkbox (DESKHEAD: one line)
var _herding_tag: Label ## DESKHEAD: the green "- On By Default -" tag under the herding line

## DESKHEAD: the herding tag's green - a clear green against
## the desk's dark ground, in the note labels' own dress.
const HERDING_TAG_GREEN: Color = Color(0.4, 0.9, 0.5)
var _details_fold: _Fold ## DESKEDIT: the Scan details fold (the scan summary's diagnostics)
var _details_label: Label ## DESKEDIT: the folded diagnostics text inside the Scan details fold
var _browse_buttons: Array[Button] = [] ## DESKCOLOR: every Browse... button (path rows + folder rows) - the picker family
var _shots_browse_button: Button ## DESKCOLOR: the Screenshots section's Browse... (picker family)
var _add_folder_button: Button ## DESKCOLOR: Add table folder... (picker family - it opens the picker)
var config_file_existed: bool = true ## AUTOFIND: Main sets this before setup() - half of the hunt's trigger (the other half is the config's own exe path). Default true: a desk nobody briefed never hunts.
var _exe_note: Label ## AUTOFIND: the hunt's word under the VPX executable field
var _folders_note: Label ## AUTOFIND: the hunt's word under the table folder rows
var _update_banner: PanelContainer ## AUTOFIND: the Update Available banner, directly under the title panel
var _update_label: Label ## AUTOFIND: the banner's line
var _update_get_button: Button ## AUTOFIND: the banner's Get (census)
var _update_later_button: Button ## AUTOFIND: the banner's Later (census)
var _update_url: String = "" ## AUTOFIND: the standing update's download url (the feed's, held for the Get emit)
var _version_label: Label ## AUTOFIND: the form's foot - "LaunchPin VR - version 1.0.0"
var _hunt_done: bool = false ## AUTOFIND: the hunt runs at most once per desk instance
var _hunt_census: Dictionary = {} ## AUTOFIND: the hunt's result as run (empty = the hunt never ran)

## CHECKLIST: the first-run guided checklist's machinery -
## four step shells (a slim bar over a content box) that
## stand in both of the desk's modes. In checklist mode
## the bars show, one step's content stands open, and a
## finished step's bar gains a check; in the full desk
## the bars hide and every content stands.
const STEP_NAMES: Array[String] = ["Initial Setup", "High Score Setup", "Art", "Advanced"]
var _step_bars: Array[Button] = []
var _step_contents: Array[VBoxContainer] = []
var _step_skips: Array[Button] = []
var _step_done: Array[bool] = [false, false, false, false]
var _step_open: int = 0 ## the open step's index; -1 = none open (after the last skip)
var _checklist_mode: bool = false

const MAX_FOLDER_ROWS: int = 6

var _scroll: ScrollContainer ## DESKCENTER: the desk's scroll - the layout pass sizes/scales it
var _center: CenterContainer ## DESKCENTER: centres the form column inside the scroll's layout area
var _margin: MarginContainer ## DESKCENTER: the form column's margin box (census: deskcenter_census)
var _layout_factor: float = 1.0 ## DESKCENTER: the standing layout factor (1.0 = the design size)

## DESKCENTER: the size the form was authored at - DESKHEAD's
## window stamp, 1280x720. On bigger windows the form scales
## up from it (never past MAX_LAYOUT_FACTOR) and centres; on
## smaller ones it never shrinks below the design layout.
const DESIGN_WINDOW_SIZE: Vector2 = Vector2(1280, 720)
const MAX_LAYOUT_FACTOR: float = 1.5
## The form column's standing width: the margin box's own
## width - its 760 minimum, with the 40px side margins living
## INSIDE that width (the MarginContainer wears them as theme
## constants, not as extra size). Proven on the standing desk:
## the margin box's global rect at factor 1.5 measured 1140 =
## 760 x 1.5 (the deskcenter census leg).
const FORM_COLUMN_WIDTH: float = 760.0


## The pure layout factor for a window size: how much bigger
## than the design size the window is, the tighter dimension
## governing, never below 1.0 and never above the cap. A
## degenerate size answers 1.0.
static func desk_layout_factor(win: Vector2) -> float:
	if win.x <= 0.0 or win.y <= 0.0:
		return 1.0
	return clampf(minf(win.x / DESIGN_WINDOW_SIZE.x, win.y / DESIGN_WINDOW_SIZE.y), 1.0, MAX_LAYOUT_FACTOR)


## The layout for a window size at a factor: the scroll's
## layout area (the window measured in desk coordinates) and
## the form column's offset inside it - the column stands in
## the middle of the area, or at its left edge when the area
## is narrower than the column (it scrolls instead).
static func desk_layout(win: Vector2, factor: float) -> Dictionary:
	var area: Vector2 = win / maxf(factor, 0.01)
	return {
		"factor": factor,
		"area": area,
		"form_x": maxf(0.0, (area.x - FORM_COLUMN_WIDTH) * 0.5),
	}


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
	# AUTOFIND: a first-run desk hunts for VPX itself,
	# once, after the fill (it only ever fills what the
	# fill left empty - see _apply_hunt).
	_apply_hunt()
	# DESKEDIT: both folds start collapsed on EVERY desk
	# show, not just the first - leaving to the room and
	# coming back re-folds what was opened.
	# CHECKLIST: the mode is re-judged on every show too -
	# a desk stood unconfigured walks the checklist; after
	# a successful setup the same desk stands full.
	visibility_changed.connect(func() -> void:
		if visible:
			_reset_folds()
			_refresh_desk_mode())
	_refresh_desk_mode()
	# DESKCENTER: the form centres and scales with the
	# window - now, and live on every window resize.
	_hook_window_layout()


func _hook_window_layout() -> void:
	if is_inside_tree():
		var win: Window = get_window()
		if win != null and not win.size_changed.is_connected(_apply_window_layout):
			win.size_changed.connect(_apply_window_layout)
	_apply_window_layout()


## The factor the desk wears for a window of the given size.
## A --pvlds- test boot pins exactly 1.0: every grab and leg
## stands at the design layout (the brief's guard). The
## DESKCENTER driver may force a factor through the
## environment to prove real input under scaling - nothing
## in production sets that variable.
func _standing_factor(win: Vector2) -> float:
	var forced: String = OS.get_environment("PVLDS_DESKCENTER_FORCE_FACTOR")
	if forced != "":
		return clampf(forced.to_float(), 1.0, MAX_LAYOUT_FACTOR)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pvlds-"):
			return 1.0
	return desk_layout_factor(win)


## DESKCENTER: centre + scale the form to the window. The
## scroll wears the window in desk coordinates (its size is
## the window divided by the factor) and scales by the
## factor, so its footprint is the window exactly while the
## form inside keeps laying out at the design measure; the
## centring parent spans the layout width, so the form
## column stands in the middle of the area at every size.
## At factor 1.0 the geometry is the design layout (the
## scroll covers the window 1:1, as before).
func _apply_window_layout() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var win_size: Vector2 = Vector2(get_window().size)
	_layout_factor = _standing_factor(win_size)
	var layout: Dictionary = desk_layout(win_size, _layout_factor)
	var area: Vector2 = layout["area"] as Vector2
	_scroll.position = Vector2.ZERO
	_scroll.size = area
	_scroll.scale = Vector2(_layout_factor, _layout_factor)
	if _center != null:
		_center.custom_minimum_size = Vector2(area.x, 0.0)


## Smoke census of the DESKCENTER layout: the standing
## factor, the scroll's transform, and the form column's
## rect in window pixels (global rects carry the scale).
func deskcenter_census() -> Dictionary:
	return {
		"factor": _layout_factor,
		"scroll_scale": _scroll.scale if _scroll != null else Vector2.ONE,
		"scroll_size": _scroll.size if _scroll != null else Vector2.ZERO,
		"form_rect": _margin.get_global_rect() if _margin != null else Rect2(),
		"dialog_scale_factor": _dialog.content_scale_factor if _dialog != null else 1.0,
	}


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
## desk wears its full Initial Setup dress on every show since
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


## AUTOFIND: the first-run hunt, run once from setup().
## Trigger (the brief): the desk stands as a first run -
## no config file existed on disk, or the config's exe
## path is empty. It never runs over values a user has
## set: the exe pre-fills only an empty exe field, table
## folders are added only when the config names none, and
## NOTHING is saved - the pre-fill is a proposal standing
## in the fields, and the save-and-scan flow is
## what persists it, exactly as if the user had typed it.
## Test seam: PVLDS_AUTOFIND_ROOTS (";"-separated) replaces
## WHERE the hunt looks (the Windows drive roots), never
## WHETHER it runs - the configured trigger above outranks
## it, so a configured desk is unmoved even on a staged
## tree. Without the seam, any --pvlds- boot skips the live
## hunt entirely (every standing smoke stays exactly as it
## was).
func _apply_hunt() -> void:
	if _hunt_done:
		return
	_hunt_done = true
	if config_file_existed and _config.vpx_exe_path != "":
		return
	var roots: Array = []
	var forced_roots: String = OS.get_environment("PVLDS_AUTOFIND_ROOTS")
	if forced_roots != "":
		for part: String in forced_roots.split(";"):
			var r: String = part.strip_edges()
			if r != "":
				roots.append(r)
	else:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--pvlds-"):
				return
		roots = VpxHunt.windows_roots()
	var res: Dictionary = VpxHunt.hunt(roots)
	_hunt_census = res
	if bool(res.get("found", false)):
		var exe_path: String = str(res.get("exe_path", ""))
		if _exe_edit.text.strip_edges() == "":
			_exe_edit.text = exe_path
		_exe_note.text = "Found Visual Pinball at %s — if you play a different build, Browse for it." % exe_path
		_exe_note.visible = true
		var folders: Array = res.get("table_folders", [])
		if _config.table_folders.is_empty():
			var fi: int = 0
			for fv: Variant in folders:
				var fpath: String = str((fv as Dictionary).get("path", ""))
				while fi < _folder_edits.size() and _folder_edits[fi].text.strip_edges() != "":
					fi += 1
				if fi < _folder_edits.size():
					_folder_edits[fi].text = fpath
					fi += 1
				elif fpath != "":
					_add_folder_row(fpath)
					fi = _folder_edits.size()
		if not folders.is_empty():
			_folders_note.text = "Found your Tables folder — %d tables in it." % int(res.get("tables_total", 0))
		else:
			_folders_note.text = "Found Visual Pinball, but no Tables folder near it — add your table folder(s) below."
		_folders_note.visible = true
	else:
		_exe_note.text = "LaunchPin couldn't find Visual Pinball on this PC. If it's installed, Browse to it above; if not, Visual Pinball is a free download — the LaunchPin VR manual shows where to get it."
		_exe_note.visible = true


## AUTOFIND: Main stands the update banner (it owns the
## update state - the feed's answer, the dismissal). This
## desk only shows what it is told and reports presses.
func show_update_banner(version: String, url: String) -> void:
	_update_url = url
	_update_label.text = "Update Available — %s %s is out." % [AppInfo.PRODUCT_NAME, version]
	_update_banner.visible = true


func hide_update_banner() -> void:
	if _update_banner != null:
		_update_banner.visible = false


## Smoke census of the AUTOFIND surfaces: the hunt's
## standing (did it run, what stands in the fields and
## notes), the banner, and the version foot.
func autofind_census() -> Dictionary:
	var folder_texts: Array = []
	for e: LineEdit in _folder_edits:
		folder_texts.append(e.text)
	return {
		"hunt_ran": not _hunt_census.is_empty(),
		"exe_text": _exe_edit.text if _exe_edit != null else "",
		"exe_note": _exe_note.text if _exe_note != null else "",
		"exe_note_visible": _exe_note.visible if _exe_note != null else false,
		"folder_texts": folder_texts,
		"folders_note": _folders_note.text if _folders_note != null else "",
		"folders_note_visible": _folders_note.visible if _folders_note != null else false,
		"banner_visible": _update_banner.visible if _update_banner != null else false,
		"banner_text": _update_label.text if _update_label != null else "",
		"version_text": _version_label.text if _version_label != null else "",
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
	# DESKCENTER: no full-rect anchors - the layout pass
	# (setup's _hook_window_layout) owns the scroll's size,
	# position and scale, and re-owns them on every resize.
	scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scroll.theme = DeskTheme.build()
	add_child(scroll)
	_scroll = scroll
	# DESKCENTER: a centring parent between the scroll and
	# the form - the ScrollContainer alone parks its child
	# at its minimum width against the left edge on wide
	# windows (Chris's field shot); the layout pass spans
	# this parent across the layout area and it centres the
	# column inside it.
	var center: CenterContainer = CenterContainer.new()
	scroll.add_child(center)
	_center = center
	var margin: MarginContainer = MarginContainer.new()
	margin.custom_minimum_size = Vector2(760, 0)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(margin)
	_margin = margin
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
	# desk is Initial Setup - the one-time, important initial
	# setup; the room's panel is IN-VR SETUP.
	# DESKEDIT: the panel holds the title ALONE. Both
	# sub-lines are gone - "Done once, on your PC, before you
	# play." by Chris's order, and the pointer to the IN-VR
	# panel because a first-time user hasn't seen the room
	# yet and shouldn't be told about surfaces he hasn't met.
	# The desk goes straight into the work (the intro below).
	# DESKHEAD: the desk is renamed - FIRST SETUP is Initial
	# Setup now (Chris's wording), here and everywhere the
	# name stands (the placard, the guidance lines).
	_title_label.text = "Initial Setup"
	_title_label.add_theme_font_override("font", DeskTheme.FONT_MEDIUM)
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	_title_box.add_child(_title_label)
	# AUTOFIND: the Update Available banner - directly
	# under the title panel, in the amber family, standing
	# only when Main says a newer LaunchPin VR exists (it
	# applies and dismisses; this desk just shows it and
	# reports the button presses). Hidden by default.
	_update_banner = PanelContainer.new()
	_update_banner.add_theme_stylebox_override("panel", DeskTheme.section_header_box_family(DeskTheme.FAMILY_AMBER))
	_update_banner.visible = false
	var ub_row: HBoxContainer = HBoxContainer.new()
	ub_row.add_theme_constant_override("separation", 8)
	_update_banner.add_child(ub_row)
	_update_label = Label.new()
	_update_label.add_theme_font_override("font", DeskTheme.FONT_MEDIUM)
	_update_label.add_theme_font_size_override("font_size", 20)
	_update_label.add_theme_color_override("font_color", DeskTheme.section_title_tint(DeskTheme.FAMILY_AMBER))
	_update_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ub_row.add_child(_update_label)
	_update_get_button = Button.new()
	_update_get_button.text = "Get the update"
	DeskTheme.dress_button_family(_update_get_button, DeskTheme.FAMILY_AMBER)
	_update_get_button.pressed.connect(func() -> void: update_get_requested.emit(_update_url))
	ub_row.add_child(_update_get_button)
	_update_later_button = Button.new()
	_update_later_button.text = "Later"
	_update_later_button.pressed.connect(func() -> void: update_later_pressed.emit())
	ub_row.add_child(_update_later_button)
	vbox.add_child(_update_banner)
	# DESKHEAD: one sentence - the second ("The headset room
	# is for playing, not setup.") named a room a first-timer
	# hasn't seen, the same anxiety DESKEDIT cut from the head.
	_intro_label = Label.new()
	_intro_label.text = "Point LaunchPin at your VPX executable and your table folder(s)."
	_intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_intro_label)

	# CHECKLIST: the desk's four steps. The shells stand in
	# both presentations - one desk, two modes. In the FULL
	# desk the step bars hide and every step's content
	# stands in column order (the desk as it always read);
	# on a FIRST RUN the desk walks a guided checklist:
	# each step's slim bar stands, only the open step's
	# content shows, and a finished step's bar gains a
	# check. _refresh_desk_mode owns which presentation
	# stands; any bar opens its step at any time - the
	# checklist guides, it never gates (only the scan
	# gates Enter, as it always has).
	for i: int in range(STEP_NAMES.size()):
		var bar: Button = Button.new()
		bar.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bar.add_theme_font_override("font", DeskTheme.FONT_MEDIUM)
		bar.add_theme_font_size_override("font_size", 20)
		bar.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_ACCENT)
		bar.add_theme_color_override("font_hover_color", RoomSpecs.STRIP_LABEL_ACCENT)
		bar.add_theme_color_override("font_pressed_color", RoomSpecs.STRIP_LABEL_ACCENT)
		bar.add_theme_stylebox_override("normal", DeskTheme.section_header_box())
		bar.add_theme_stylebox_override("hover", DeskTheme.section_header_box())
		bar.add_theme_stylebox_override("pressed", DeskTheme.section_header_box())
		bar.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		bar.visible = false
		bar.pressed.connect(_on_step_bar_pressed.bind(i))
		vbox.add_child(bar)
		_step_bars.append(bar)
		var step_content: VBoxContainer = VBoxContainer.new()
		step_content.add_theme_constant_override("separation", 12)
		vbox.add_child(step_content)
		_step_contents.append(step_content)
	_refresh_step_bars()
	var step1: VBoxContainer = _step_contents[0]
	var step2: VBoxContainer = _step_contents[1]
	var step3: VBoxContainer = _step_contents[2]
	var step4: VBoxContainer = _step_contents[3]

	# -- Step 1: Initial Setup. The VPX executable, the
	# table folders the intro sentence promises, and the
	# scan that reads them. The folders stand directly
	# under the VPX block in BOTH modes (CHECKLIST item 2:
	# the regroup is permanent - they used to stand at the
	# desk's far end, far from the sentence naming them).
	_exe_edit = _add_path_row(step1, "VPX executable", "Browse...", "exe")
	# AUTOFIND: the hunt's word under the exe field - what
	# it found, or the plain not-found guidance. Stands
	# only when the hunt ran (see _apply_hunt).
	_exe_note = Label.new()
	_exe_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_exe_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	_exe_note.visible = false
	step1.add_child(_exe_note)
	_folder_rows = VBoxContainer.new()
	_folder_rows.add_theme_constant_override("separation", 8)
	step1.add_child(_folder_label())
	step1.add_child(_folder_rows)
	# AUTOFIND: the hunt's word under the folder rows -
	# the found Tables folder and its size, or the word
	# that the folders still need pointing at.
	_folders_note = Label.new()
	_folders_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folders_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	_folders_note.visible = false
	step1.add_child(_folders_note)
	var add_folder: Button = Button.new()
	add_folder.text = "Add table folder..."
	# DESKCOLOR: Add folder opens the picker, so it wears
	# the picker slate too.
	DeskTheme.dress_button_family(add_folder, DeskTheme.FAMILY_PICKER)
	_add_folder_button = add_folder
	add_folder.pressed.connect(_on_add_folder_row)
	step1.add_child(add_folder)

	var dummy_button: Button = Button.new()
	dummy_button.text = "Use the bundled dummy library (invented tables, for judging the flow)"
	dummy_button.pressed.connect(_on_use_dummy)
	step1.add_child(dummy_button)

	_scan_button = Button.new()
	# CHECKLIST: the action renamed to say the whole job -
	# it saves every option on the desk, then scans.
	_scan_button.text = "Save Options and Scan for Tables"
	_scan_button.pressed.connect(_on_save_and_scan)
	step1.add_child(_scan_button)

	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.text = "Not scanned yet."
	step1.add_child(_stats_label)

	# DESKEDIT: the scan summary's diagnostics live in a
	# Scan details fold under the stats area - the standing
	# area carries the answers (headline + the plain
	# database line); the workshop numbers wait in the fold
	# for whoever goes looking. The fold stands only when a
	# scan's details exist (no empty furniture before the
	# first scan) and starts collapsed like every fold.
	_details_fold = _make_fold(step1, "Scan details")
	_details_label = Label.new()
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_fold.content.add_child(_details_label)
	_details_fold.root.visible = false

	var b2s_row: HBoxContainer = HBoxContainer.new()
	b2s_row.add_theme_constant_override("separation", 8)
	step1.add_child(b2s_row)
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
	step1.add_child(unplaced_row)
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

	# -- Step 2: High Score Setup. The WoVP boards block,
	# the screenshots folder, and the PINemHi block under
	# one heading - everything that feeds the high-score
	# surfaces, gathered (CHECKLIST item 4). The old
	# headings stand as sub-headings below it and keep
	# their DESKCOLOR families.
	step2.add_child(_section_header("High Score Setup"))
	# The WoVP section (the Tournament Room round): his
	# World of Virtual Pinball API key - self-service in his
	# WoVP profile, pasted here once. Like the session
	# switch, the key is a live setting: Save key writes
	# the config on the spot (no full save), Test key
	# validates the field's text and names whose key it
	# is. The field is masked - it is a secret, and it is
	# never printed.
	step2.add_child(_section_header("World of Virtual Pinball (WoVP) - the Tournament Room's boards", DeskTheme.FAMILY_WOVP))
	var wovp_intro: Label = Label.new()
	# CHECKLIST: the key directions, telling a first-timer
	# where the key actually lives (the brief's wording).
	wovp_intro.text = "Your WoVP API key shows your live league boards in the Tournament Room. Get your key from WoVP: open your profile page and look under Settings. Stored only in the config file on this PC."
	wovp_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step2.add_child(wovp_intro)
	_wovp_edit = LineEdit.new()
	_wovp_edit.secret = true
	_wovp_edit.placeholder_text = "Paste your WoVP API key here"
	step2.add_child(_wovp_edit)
	var wovp_row: HBoxContainer = HBoxContainer.new()
	wovp_row.add_theme_constant_override("separation", 8)
	step2.add_child(wovp_row)
	_wovp_save_button = Button.new()
	_wovp_save_button.text = "Save key"
	# DESKCOLOR: the key pair wears the confirm green.
	DeskTheme.dress_button_family(_wovp_save_button, DeskTheme.FAMILY_CONFIRM)
	_wovp_save_button.pressed.connect(_on_wovp_save_pressed)
	wovp_row.add_child(_wovp_save_button)
	_wovp_test_button = Button.new()
	_wovp_test_button.text = "Test key"
	DeskTheme.dress_button_family(_wovp_test_button, DeskTheme.FAMILY_CONFIRM)
	_wovp_test_button.pressed.connect(_on_wovp_test_pressed)
	wovp_row.add_child(_wovp_test_button)
	_wovp_label = Label.new()
	_wovp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wovp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wovp_row.add_child(_wovp_label)
	# CHECKLIST: the desk's Submit-a-score form and its
	# recent-submissions list are GONE from the desk -
	# nobody submits from this screen (the Tournament
	# Room's panel is the one submission surface), and
	# the receipt book is reborn as a panel in the
	# Tournament Room itself. The records store (the
	# local submission log) does not move.

	# The Screenshots section (ROOMSUBMIT): the folder his
	# headset score screenshots land in. The in-room submit
	# panel reads its photos from there - newest first, one
	# standing large for the flicker check - so a score can
	# be sent without leaving the room. Like the key and
	# the PINemHi settings, this is a live setting: Save
	# writes the config on the spot. No toggle: an unset
	# folder is the off state, and the panel says so.
	step2.add_child(_section_header("Screenshots - the folder your score photos land in", DeskTheme.FAMILY_WOVP))
	var shots_intro: Label = Label.new()
	# CHECKLIST: Chris's own words for what this folder is.
	shots_intro.text = "Please select the folder your VR headset screenshots appear on PC. Submit screenshots in Tournament Room while in VR."
	shots_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step2.add_child(shots_intro)
	var shots_row: HBoxContainer = HBoxContainer.new()
	shots_row.add_theme_constant_override("separation", 8)
	step2.add_child(shots_row)
	_shots_edit = LineEdit.new()
	_shots_edit.placeholder_text = "Screenshots folder - where your headset shots land"
	_shots_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shots_row.add_child(_shots_edit)
	var shots_browse: Button = Button.new()
	shots_browse.text = "Browse..."
	# DESKCOLOR: a Browse button wears the picker slate
	# wherever it stands.
	DeskTheme.dress_button_family(shots_browse, DeskTheme.FAMILY_PICKER)
	_shots_browse_button = shots_browse
	shots_browse.pressed.connect(func() -> void: _open_dialog_for("shots"))
	shots_row.add_child(shots_browse)
	var shots_save_row: HBoxContainer = HBoxContainer.new()
	shots_save_row.add_theme_constant_override("separation", 8)
	step2.add_child(shots_save_row)
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
	# these are live settings: Save writes the config on
	# the spot.
	step2.add_child(_section_header("PINemHi - your personal bests on the tournament boards", DeskTheme.FAMILY_PINEMHI))
	var pinemhi_intro: Label = Label.new()
	pinemhi_intro.text = "If you use PINemHi, LaunchPin can read its TOP10_Personal files and show your best beneath the league scores on a tournament board. That's all it does by default - it never runs PINemHi or its watcher unless you opt in below. Leave the folder empty to auto-detect the usual install places (D:\\vPinball\\Pinemhi and friends)."
	pinemhi_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step2.add_child(pinemhi_intro)
	_pinemhi_check = CheckBox.new()
	_pinemhi_check.text = "Show my PINemHi personal bests on tournament boards"
	step2.add_child(_pinemhi_check)
	_pinemhi_manage_check = CheckBox.new()
	_pinemhi_manage_check.text = "Let LaunchPin run the PINemHi watcher while a table is playing"
	_pinemhi_manage_check.tooltip_text = "Off (the default): LaunchPin never touches the watcher. On: the watchdog starts pinemhi_rom_monitor.exe when a table starts (if it isn't already running) and closes it shortly after the table exits - or when LaunchPin exits, if that comes first. A watcher already running is left running: LaunchPin only ever closes one it started itself."
	step2.add_child(_pinemhi_manage_check)
	_pinemhi_edit = LineEdit.new()
	_pinemhi_edit.placeholder_text = "PINemHi folder - empty = auto-detect"
	step2.add_child(_pinemhi_edit)
	var pinemhi_row: HBoxContainer = HBoxContainer.new()
	pinemhi_row.add_theme_constant_override("separation", 8)
	step2.add_child(pinemhi_row)
	var pinemhi_save: Button = Button.new()
	pinemhi_save.text = "Save PINemHi settings"
	pinemhi_save.pressed.connect(_on_pinemhi_save_pressed)
	pinemhi_row.add_child(pinemhi_save)
	_pinemhi_label = Label.new()
	_pinemhi_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pinemhi_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pinemhi_row.add_child(_pinemhi_label)

	# -- Step 3: Art. The VPS database block, inverted
	# (CHECKLIST item 3): the standing explanation first,
	# then the Download as the primary action, then the
	# field for a player's own copy. The bundled copy
	# covers scanning, so nothing here blocks; the
	# download is offered, never silent. The IPDB block
	# rides the same step - it is the library's other
	# well of facts and art.
	# DESKEDIT: say what the thing IS - a first-timer is
	# otherwise asked to point at a file he has never heard
	# of (Chris's wording, FINAL).
	# DESKHEAD: the line opens by NAMING the thing - "The
	# VPS Database is a community catalog..." (Chris's edit).
	_db_note = Label.new()
	_db_note.text = "The VPS Database is a community catalog of VPX tables — names, makers, cover art. LaunchPin carries a copy and can download a fresh one below; this field is only for using your own."
	_db_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_db_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	step3.add_child(_db_note)
	var dl_row: HBoxContainer = HBoxContainer.new()
	dl_row.add_theme_constant_override("separation", 8)
	step3.add_child(dl_row)
	_dl_button = Button.new()
	_dl_button.text = "Download VPS database"
	# DESKCOLOR: Download rides with the picker family -
	# it is a get-the-file button.
	DeskTheme.dress_button_family(_dl_button, DeskTheme.FAMILY_PICKER)
	_dl_button.pressed.connect(_on_download_pressed)
	dl_row.add_child(_dl_button)
	_dl_label = Label.new()
	_dl_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl_row.add_child(_dl_label)
	# The download itself is the shared service (core/vps_downloader.gd)
	# - the room's SETUP panel runs the same one. This desk only owns
	# its button, its label, and its success tail (the next scan).
	_downloader = VpsDownloader.new()
	add_child(_downloader)
	_downloader.progress.connect(func(text: String) -> void: _dl_label.text = text)
	_downloader.finished.connect(_on_download_finished)
	# CHECKLIST: the own-copy path, labelled as exactly
	# that - the exception under the download, not the
	# front door.
	_db_edit = _add_path_row(step3, "Only for using your own copy instead:", "Browse...", "db")

	# The IPDB section (CARDBACK, reshaped by IPDBFIX):
	# the card backs' second well. The facts ship BUNDLED
	# with PVLDS - a snapshot of the Internet Pinball
	# Database taken when the app was built - and seed the
	# cache at boot; the app never fetches from IPDB
	# directly (its site refuses requests from apps). The
	# button re-applies the bundled snapshot, the useful
	# move after a cache clear; a snapshot refresh rides
	# a PVLDS update.
	step3.add_child(_section_header("IPDB data - the card backs' second well"))
	var ipdb_intro: Label = Label.new()
	ipdb_intro.text = "Each card's back mixes the database's facts with the Internet Pinball Database's (production run, fun rating, full credits, notable features), each row dotted with its source. The IPDB facts ship bundled as a snapshot and apply automatically; the backs read the saved copy and never go online. Games with no IPDB link in the database show database rows only."
	ipdb_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step3.add_child(ipdb_intro)
	var ipdb_row: HBoxContainer = HBoxContainer.new()
	ipdb_row.add_theme_constant_override("separation", 8)
	step3.add_child(ipdb_row)
	var ipdb_apply: Button = Button.new()
	ipdb_apply.text = "Re-apply bundled IPDB data"
	ipdb_apply.pressed.connect(func() -> void: ipdb_snapshot_requested.emit())
	ipdb_row.add_child(ipdb_apply)
	_ipdb_label = Label.new()
	_ipdb_label.text = "IPDB data: bundled snapshot not applied yet."
	_ipdb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ipdb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ipdb_row.add_child(_ipdb_label)

	# -- Step 4: Advanced. The Launch Arguments fold and
	# Focus Herding. In the FULL desk the fold behaves as
	# it always has (collapsed at every show, its toggle
	# standing); in checklist mode the step IS the fold:
	# its toggle hides and the fold stands open (see
	# _refresh_desk_mode).
	# DESKEDIT: the Launch arguments template is buried
	# under an Advanced fold standing where the field stood
	# - a technical field a first-timer should not have to
	# wonder about. The field itself is untouched (same
	# config key, same collect/save); only Launch Arguments
	# goes under the fold, nothing else is swept in.
	_advanced_fold = _make_fold(step4, "Advanced")
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
	_herding_check.tooltip_text = "While a table launches, LaunchPin puts the game's window in front and keeps it there through the launch. During play it takes the front back only from known companions — the PINemHi LeaderBoard board and VPX's own windows — and if you alt-tab away yourself, it leaves you alone. It never moves or resizes windows."
	_herding_check.toggled.connect(func(_on: bool) -> void: _apply_session_settings())
	step4.add_child(_herding_check)
	_herding_note = Label.new()
	# DESKHEAD: the DESKEDIT paragraph is replaced whole -
	# one line, then the green tag below, and nothing else
	# (Chris's wording, FINAL; the why belongs to the manual).
	_herding_note.text = "When playing, LaunchPin keeps your game's window in front, so no other programs on your PC will interfere with your VR view."
	_herding_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_herding_note.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	step4.add_child(_herding_note)
	_herding_tag = Label.new()
	_herding_tag.text = "— On By Default —"
	_herding_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_herding_tag.add_theme_color_override("font_color", HERDING_TAG_GREEN)
	step4.add_child(_herding_tag)

	# CHECKLIST: the optional steps' way out, at each
	# step's foot - "Skip for now", shown only in checklist
	# mode. Skipping marks the step done and opens the
	# next; it costs nothing and nags never.
	for i: int in range(1, STEP_NAMES.size()):
		var skip: Button = Button.new()
		skip.text = "Skip for now"
		skip.visible = false
		skip.pressed.connect(_on_skip_step_pressed.bind(i))
		_step_contents[i].add_child(skip)
		_step_skips.append(skip)

	# The foot stands outside the steps in both modes.
	_enter_button = Button.new()
	# CHECKLIST: the door renamed for the product it opens.
	_enter_button.text = "Enter LaunchPin VR"
	_enter_button.disabled = true
	_enter_button.pressed.connect(func() -> void: enter_room_requested.emit())
	vbox.add_child(_enter_button)

	# AUTOFIND: the form's foot - the product's name and
	# version, quiet. One constant, one home (AppInfo);
	# the update check compares against the same string.
	_version_label = Label.new()
	_version_label.text = "%s — version %s" % [AppInfo.PRODUCT_NAME, AppInfo.PRODUCT_VERSION]
	_version_label.add_theme_color_override("font_color", RoomSpecs.STRIP_LABEL_REST)
	vbox.add_child(_version_label)

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_selected.connect(_on_dialog_file)
	_dialog.dir_selected.connect(_on_dialog_dir)
	add_child(_dialog)


func _folder_label() -> PanelContainer:
	return _section_header("Table folders", DeskTheme.FAMILY_AMBER)


## SETUPLOOK: a section header bar - the section's name in
## the house display type on the resting graphite gradient,
## in the strip segment's manner, instead of a plain bold
## label. Dress only: the words and the order never move.
## DESKCOLOR: a section in a colour family passes its
## family - the bar's gradient tints toward it, the accent
## underline and edges wear it, and the title takes its
## lightened tint. No family (the default) is the plain
## graphite bar, exactly as SETUPLOOK built it.
func _section_header(text: String, family: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	var tint: Color = RoomSpecs.STRIP_LABEL_ACCENT
	if family.a > 0.0:
		p.add_theme_stylebox_override("panel", DeskTheme.section_header_box_family(family))
		tint = DeskTheme.section_title_tint(family)
	else:
		p.add_theme_stylebox_override("panel", DeskTheme.section_header_box())
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", DeskTheme.FONT_MEDIUM)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", tint)
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
	# DESKCOLOR: every Browse... wears the picker slate.
	DeskTheme.dress_button_family(b, DeskTheme.FAMILY_PICKER)
	_browse_buttons.append(b)
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
	DeskTheme.dress_button_family(b, DeskTheme.FAMILY_PICKER)
	_browse_buttons.append(b)
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
	elif target == "shots":
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.title = "Pick the folder your headset screenshots land in"
	else:
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.title = "Pick a folder full of .vpx tables"
	# DESKCENTER: the picker is desk furniture and rides the
	# layout scale - it is a Window, which Control scaling
	# never reaches, so it wears the factor through its own
	# content scale instead.
	if _layout_factor > 1.0:
		_dialog.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		_dialog.content_scale_factor = _layout_factor
	else:
		_dialog.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		_dialog.content_scale_factor = 1.0
	_dialog.popup_centered_ratio(0.75)


func _on_dialog_file(path: String) -> void:
	if _dialog_target == "exe":
		_exe_edit.text = path
	elif _dialog_target == "db":
		_db_edit.text = path


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
## (Before this, the switches were only read at save-and-scan, so a
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
		_mark_step_done(3)
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
		_mark_step_done(1)
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
		_mark_step_done(1)
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
		_mark_step_done(1)
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
		_dl_label.text = message + " It will be used by the next scan."
		_mark_step_done(2)
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
			_set_enter_armed(false)
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
	_set_enter_armed(false)
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
	_set_enter_armed(_scanned)
	_scan_button.disabled = false
	# CHECKLIST: a landed scan finishes step 1 - its bar
	# gains the check, the step folds away, and the walk
	# moves on to High Score Setup (only when the player
	# is standing on step 1; a step he opened himself is
	# never yanked away).
	if summary != "" and _checklist_mode:
		_mark_step_done(0)
		if _step_open == 0:
			_open_step(1)
			if _scroll != null:
				_scroll.scroll_vertical = 0


## CHECKLIST: is this desk's stand a configured one? The
## same test the brief names: a config file on disk AND
## at least one table folder in it. Read fresh at every
## show, so a desk re-stood after a successful setup is
## the full desk, and one stood over an empty folder
## list still walks the checklist.
func _desk_is_configured() -> bool:
	if _config == null:
		return false
	return PvldsConfig.existing_path() != "" and not _config.table_folders.is_empty()


## CHECKLIST: stand the desk in the mode its stand
## calls for. Full desk: the step bars and Skip buttons
## hide, every step's content stands, the Advanced fold
## wears its toggle. Checklist: the bars stand, exactly
## the open step's content shows, the skips stand, and
## the Advanced fold's toggle hides with the fold held
## open (in step 4 the step IS the fold).
func _refresh_desk_mode() -> void:
	if _step_bars.is_empty():
		return
	_checklist_mode = not _desk_is_configured()
	for b: Button in _step_bars:
		b.visible = _checklist_mode
	for s: Button in _step_skips:
		s.visible = _checklist_mode
	if _checklist_mode:
		if _advanced_fold != null:
			_advanced_fold.toggle.visible = false
			_advanced_fold.set_expanded(true)
		_apply_step_visibility()
	else:
		if _advanced_fold != null:
			_advanced_fold.toggle.visible = true
		for c: VBoxContainer in _step_contents:
			c.visible = true


func _apply_step_visibility() -> void:
	for j: int in range(_step_contents.size()):
		_step_contents[j].visible = j == _step_open


## CHECKLIST: open a step (checklist mode). Any step can
## be opened at any time - the guide never gates.
func _open_step(i: int) -> void:
	_step_open = i
	if _checklist_mode:
		_apply_step_visibility()


func _on_step_bar_pressed(i: int) -> void:
	_open_step(i)


## CHECKLIST: an optional step's way out - the step is
## done, the walk moves on (or closes, past the last).
func _on_skip_step_pressed(i: int) -> void:
	_mark_step_done(i)
	if i + 1 < STEP_NAMES.size():
		_open_step(i + 1)
	else:
		_step_open = -1
		if _checklist_mode:
			_apply_step_visibility()


## CHECKLIST: a step earns its check - by a skip, by a
## successful save inside it, or (step 1) by a landed
## scan. The bar re-reads with the mark.
func _mark_step_done(i: int) -> void:
	if i < 0 or i >= _step_done.size():
		return
	if not _step_done[i]:
		_step_done[i] = true
		_refresh_step_bars()


func _refresh_step_bars() -> void:
	for i: int in range(_step_bars.size()):
		var t: String = "%d. %s" % [i + 1, STEP_NAMES[i]]
		if i > 0:
			t += " (optional)"
		if _step_done[i]:
			t += "  ✓"
		_step_bars[i].text = t


## CHECKLIST: Enter's armament, in one place - the
## standing rule (a scan/config with games arms it) plus
## the new dress: armed, it wears the DESKCOLOR confirm
## green; unarmed, the plain desk dress. The arming
## logic itself is unchanged (the scan arms it, a scan
## starting disarms it).
func _set_enter_armed(armed: bool) -> void:
	if _enter_button == null:
		return
	_enter_button.disabled = not armed
	if armed:
		DeskTheme.dress_button_family(_enter_button, DeskTheme.FAMILY_CONFIRM)
	else:
		_undress_button_family(_enter_button)


## Remove exactly the dress dress_button_family put on -
## the desk's theme dress stands underneath again.
func _undress_button_family(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		if b.has_theme_stylebox_override(state):
			b.remove_theme_stylebox_override(state)
	for cname: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		if b.has_theme_color_override(cname):
			b.remove_theme_color_override(cname)


## Smoke census of the CHECKLIST machinery: the standing
## mode, the open step, the done marks, the bars' exact
## texts, which contents stand, the regroup's structure
## (each old block inside its step), the Art step's new
## order, and the foot's renamed labels + Enter's dress.
func checklist_census() -> Dictionary:
	var bars: Array = []
	for b: Button in _step_bars:
		bars.append({"text": b.text, "visible": b.visible})
	var vis: Array = []
	for c: VBoxContainer in _step_contents:
		vis.append(c.visible)
	var dl_row: Control = _dl_button.get_parent() as Control if _dl_button != null else null
	return {
		"mode_checklist": _checklist_mode,
		"open_step": _step_open,
		"done": _step_done.duplicate(),
		"bars": bars,
		"contents_visible": vis,
		"folders_in_step1": _folder_rows != null and _step_contents[0].is_ancestor_of(_folder_rows),
		"wovp_in_step2": _wovp_edit != null and _step_contents[1].is_ancestor_of(_wovp_edit),
		"shots_in_step2": _shots_edit != null and _step_contents[1].is_ancestor_of(_shots_edit),
		"pinemhi_in_step2": _pinemhi_edit != null and _step_contents[1].is_ancestor_of(_pinemhi_edit),
		"db_in_step3": _db_edit != null and _step_contents[2].is_ancestor_of(_db_edit),
		"note_before_download": _db_note != null and dl_row != null and _db_note.get_index() < dl_row.get_index(),
		"download_before_field": dl_row != null and _db_edit != null and dl_row.get_index() < (_db_edit.get_parent() as Control).get_index(),
		"args_in_step4": _args_edit != null and _step_contents[3].is_ancestor_of(_args_edit),
		"advanced_toggle_visible": _advanced_fold.toggle.visible if _advanced_fold != null else true,
		"scan_text": _scan_button.text if _scan_button != null else "",
		"enter_text": _enter_button.text if _enter_button != null else "",
		"enter_disabled": _enter_button.disabled if _enter_button != null else true,
		"enter_dressed": _enter_button != null and _enter_button.has_theme_stylebox_override("normal"),
	}


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
		# DESKHEAD: the intro's exact sentence and the green
		# tag (its words + the colour it actually wears).
		"intro": _intro_label.text if _intro_label != null else "",
		"herding_tag": _herding_tag.text if _herding_tag != null else "",
		"herding_tag_color": _herding_tag.get_theme_color("font_color") if _herding_tag != null else Color.BLACK,
	}


## Smoke census of the DESKCOLOR dress: for each named
## heading bar and button, the colours sampled off the
## stylebox it actually wears (the patch texture's middle
## and its accent-underline row) plus its font colour -
## the stylebox's own colours, never screen pixels. A
## control with no family dress reports dressed=false and
## the plain theme box's samples.
func deskcolor_census() -> Dictionary:
	var browse_ok: bool = not _browse_buttons.is_empty()
	for b: Button in _browse_buttons:
		var s: Dictionary = _sample_button(b)
		if not bool(s["found"]) or not bool(s["dressed"]) or _color_dist(s["bar"] as Color, DeskTheme.FAMILY_PICKER) > 0.05:
			browse_ok = false
	return {
		"hdr_highscore": _sample_header(_find_header("High Score Setup")),
		"hdr_wovp": _sample_header(_find_header("World of Virtual Pinball (WoVP) - the Tournament Room's boards")),
		"hdr_shots": _sample_header(_find_header("Screenshots - the folder your score photos land in")),
		"hdr_pinemhi": _sample_header(_find_header("PINemHi - your personal bests on the tournament boards")),
		"hdr_folders": _sample_header(_find_header("Table folders")),
		"hdr_ipdb": _sample_header(_find_header("IPDB data - the card backs' second well")),
		"browse_count": _browse_buttons.size(),
		"browse_all_picker": browse_ok,
		"browse": _sample_button(_browse_buttons[0] if not _browse_buttons.is_empty() else null),
		"shots_browse": _sample_button(_shots_browse_button),
		"add_folder": _sample_button(_add_folder_button),
		"download": _sample_button(_dl_button),
		"save_key": _sample_button(_wovp_save_button),
		"test_key": _sample_button(_wovp_test_button),
		"scan": _sample_button(_scan_button),
		"enter": _sample_button(_enter_button),
		"open_b2s": _sample_button(_b2s_button),
		"open_unplaced": _sample_button(_unplaced_button),
		"shots_save": _sample_button(_find_button("Save screenshots folder")),
		"pinemhi_save": _sample_button(_find_button("Save PINemHi settings")),
		"ipdb_apply": _sample_button(_find_button("Re-apply bundled IPDB data")),
		"advanced_toggle": _sample_button(_advanced_fold.toggle if _advanced_fold != null else null),
		"details_toggle": _sample_button(_details_fold.toggle if _details_fold != null else null),
	}


static func _color_dist(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _sample_button(b: Button) -> Dictionary:
	if b == null:
		return {"found": false, "dressed": false, "mid": Color.TRANSPARENT, "bar": Color.TRANSPARENT, "font": Color.TRANSPARENT}
	var out: Dictionary = _sample_stylebox(b.get_theme_stylebox("normal", "Button"))
	out["found"] = true
	out["dressed"] = b.has_theme_stylebox_override("normal")
	out["font"] = b.get_theme_color("font_color", "Button")
	return out


func _sample_header(p: PanelContainer) -> Dictionary:
	if p == null:
		return {"found": false, "mid": Color.TRANSPARENT, "bar": Color.TRANSPARENT, "tint": Color.TRANSPARENT}
	var out: Dictionary = _sample_stylebox(p.get_theme_stylebox("panel", "PanelContainer"))
	out["found"] = true
	out["tint"] = Color.TRANSPARENT
	for ch: Node in p.get_children():
		var l: Label = ch as Label
		if l != null:
			out["tint"] = l.get_theme_color("font_color", "Label")
	return out


## A patch stylebox's colours: the gradient's middle row
## and the accent-underline row of its baked texture.
func _sample_stylebox(sb: StyleBox) -> Dictionary:
	var out: Dictionary = {"mid": Color.TRANSPARENT, "bar": Color.TRANSPARENT}
	var tsb: StyleBoxTexture = sb as StyleBoxTexture
	if tsb != null and tsb.texture != null:
		var img: Image = tsb.texture.get_image()
		if img != null and img.get_width() >= 96 and img.get_height() >= 48:
			out["mid"] = img.get_pixel(48, 24)
			out["bar"] = img.get_pixel(48, 43)
	return out


func _find_header(text: String) -> PanelContainer:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var nd: Node = stack.pop_back() as Node
		var pc: PanelContainer = nd as PanelContainer
		if pc != null:
			for ch: Node in pc.get_children():
				var l: Label = ch as Label
				if l != null and l.text == text:
					return pc
		for ch: Node in nd.get_children():
			stack.append(ch)
	return null


func _find_button(text: String) -> Button:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var nd: Node = stack.pop_back() as Node
		var b: Button = nd as Button
		if b != null and b.text == text:
			return b
		for ch: Node in nd.get_children():
			stack.append(ch)
	return null


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
