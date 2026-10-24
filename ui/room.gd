class_name RoomView
extends Node3D

## The room: a seated-first curved wall of table panels, a control rail,
## and the detail view. One input model for every hand: the PointerRig
## (VR laser / mouse ray) plus gamepad-and-keyboard focus navigation
## over the same set of ClickableQuads.

signal setup_requested
signal setup_placard_dismissed ## the setup placard's BACK: Main closes the desk it opened alongside
signal launch_requested(game: GameEntry, build: TableBuild) ## card Launch / detail Play - Main owns the launch + exit
signal exit_requested ## rail EXIT: Main disarms the watchdog and quits
signal art_prefetch_requested(games: Array) ## a page settled: Main's warmer should bring the neighbouring pages' art forward

const PAGE_COLS: int = 4
const PAGE_ROWS: int = 3
const PAGE_SIZE: int = PAGE_COLS * PAGE_ROWS
const WALL_RADIUS: float = 3.05
const EYE: Vector3 = Vector3(0.0, 1.25, 0.0)
const FILTERS: Array[String] = ["all", "vr", "favorites", "recents"]
const FILTER_LABELS: Dictionary = {"all": "ALL", "vr": "VR", "favorites": "FAVORITES", "recents": "RECENTS"}
const SORTS: Array[String] = ["name", "year", "manufacturer", "designer"]
const SORT_LABELS: Dictionary = {"name": "NAME", "year": "YEAR", "manufacturer": "MAKER", "designer": "DESIGNER"}

# ------------------------------------------------------- loading marquee
## The load wait's headline. Chris: "I have 50 years of hating
## loading screens" - so this is NOT a loading screen: no spinner,
## no progress bar, no percentage, no LOADING text. While a table
## loads, the wall of cards fades down and the launched table's
## year, with its designer beneath, flies in from the wall in big
## marquee letters, settles at reading distance, and holds with a
## gentle pulse until the wait settles. Every feel knob is a
## constant here, for one-line retunes after Chris's verdict.
const MARQUEE_FADE_SEC: float = 0.6 ## wall fade-down duration
const MARQUEE_WALL_ALPHA: float = 0.16 ## the wall's alpha while the marquee stands
const MARQUEE_FLY_IN_SEC: float = 1.4 ## the letters' travel time, wall -> settle
const MARQUEE_START_Z: float = -3.05 ## fly-in start depth (at the wall)
const MARQUEE_SETTLE_POS: Vector3 = Vector3(0.0, 1.42, -2.30) ## reading distance, on the view axis (retuned 2026-10-22: first pass sat too close)
const MARQUEE_PIXEL_SIZE: float = 0.005 ## Label3D world scale
const MARQUEE_YEAR_FONT_SIZE: int = 110 ## retuned 2026-10-22: 170 read too big in the headset
const MARQUEE_NAME_FONT_SIZE: int = 56 ## the designer/title line (Chris's "date and designer"); 84 -> 56 in the same retune
const MARQUEE_YEAR_Y: float = 0.30 ## year line's offset from the holder's centre
const MARQUEE_NAME_Y: float = -0.34 ## designer/title line's offset
const MARQUEE_PULSE_RATE: float = 1.6 ## settle pulse, cycles per second
const MARQUEE_PULSE_AMOUNT: float = 0.025 ## settle pulse, scale amplitude
const MARQUEE_YEAR_COLOR: Color = Color(1.0, 0.78, 0.25) ## marquee amber
const MARQUEE_NAME_COLOR: Color = Color(0.45, 0.85, 1.0) ## playfield blue
const MARQUEE_OUTLINE_COLOR: Color = Color(0.04, 0.02, 0.0)
const MARQUEE_OUTLINE_SIZE: int = 24

## Card pop-out (Chris, 2026-10-22): the card under the pointer -
## or holding gamepad/keyboard focus - lifts off the wall toward
## the viewer with depth from its neighbours. Only the one card
## is ever popped; focus loss settles it back flush.
const POP_OUT_DISTANCE: float = 0.15 ## metres off the wall at full pop
const POP_OUT_SCALE: float = 1.08 ## card scale at full pop
const POP_OUT_SEC: float = 0.15 ## pop in/out travel time, seconds

## Page slide (the bumper feel round, 2026-10-24 - Chris, on the
## bumper flip: "it snaps to next wall, which is great, its fast,
## but i need some kind of visual doodad, a quick blur or
## something"). A page change rides a short out-and-back yaw of
## the whole wall around the player's vertical axis: the wall
## glides toward the travel direction (NEXT sweeps the content
## leftward, PREV the mirror), the page content swaps at the far
## point, and the wall glides back to exact rest - about a
## quarter second end to end, the state change itself landing in
## one frame at the far point. The rail never rides the slide:
## it is furniture and stands still (see _apply_rail_textures).
const PAGE_SLIDE_OUT_SEC: float = 0.12 ## glide-out leg, seconds
const PAGE_SLIDE_BACK_SEC: float = 0.12 ## glide-back leg, seconds
const PAGE_SLIDE_YAW_DEG: float = 5.0 ## the far point's yaw, degrees (~a third of a column pitch)

## Wall card geometry (the occlusion round, 2026-10-24 - Chris's
## seated screenshot: names behind Launch buttons, the bottom row
## behind the control rail). The wall faces render at 512x640, so
## the art face's name strip (CardFace.ART_STRIP_HEIGHT_PX) owns
## the panel's bottom 92/640 of its height: with PANEL_SIZE.y =
## 0.64 the strip's top edge sits at panel-local y = -0.228. The
## Launch button used to centre at y = -0.242 - square over the
## name ("El D ... 1...", "Ele ..."). PANEL_LAUNCH_Y puts the
## button's lower edge at -0.2125: clear of the strip's top edge
## with ~15mm to spare, still riding the card's lower third as a
## distinct, unmissable target.
const PANEL_SIZE: Vector2 = Vector2(0.54, 0.64)
const PANEL_LAUNCH_SIZE: Vector2 = Vector2(0.36, 0.115)
const PANEL_LAUNCH_Y: float = -0.155
## Panel rows' centre heights. Raised 0.05 (with the banner) and
## the rail lowered 0.10 in the same round: from a seated eye at
## SEATED_EYE_Y the bottom row's lower edge - Launch buttons
## included - now clears the rail's top edge by ~4.4 degrees of
## view; before, the rail's top edge sat ~0.9 degrees BELOW the
## row's lower edge in projection and swallowed it.
const WALL_ROW_YS: Array[float] = [1.95, 1.30, 0.65]
const SEATED_EYE_Y: float = 1.2 ## a seated player's eye height - the clearance QA camera

var _factory: TextureFactory
var _scanner: LibraryScanner
var _store: StateStore
var _xr_enabled: bool = false

var _filter: String = "vr" ## VR-suitable by default (design section 4).
var _filter_note: String = "" ## set when the empty-filter guard falls back to ALL
var _sort: String = "name"
var _page: int = 0
var wall_ready: bool = false ## true once the current wall's textures have all landed
var _visible_games: Array[GameEntry] = []
var _gen: int = 0
var _mode: String = "wall" ## "wall" | "detail"

var _wall: Node3D
var _rail: Node3D
var _banner_quad: ClickableQuad
var _detail: DetailView
var _rig: PointerRig
var _xr_camera: Camera3D
var _desk_rig: Node3D
var _desk_camera: Camera3D
var _panels: Array[ClickableQuad] = []
var _panel_launches: Array[ClickableQuad] = [] ## per-panel Launch button, parallel to _panels
var _panel_base_pos: Array[Vector3] = [] ## wall-flush position per panel, parallel to _panels
var _panel_pop_dir: Array[Vector3] = [] ## unit vector from the panel toward the viewer (its wall normal)
var _panel_pop: Array[float] = [] ## current pop amount per panel, 0 flush .. 1 popped
var _panel_pop_applied: Array[float] = [] ## last pop amount written to a panel's transform (write guard)
var _launching_game_id: String = "" ## a launch is in its load wait (Main owns it); the wall is frozen meanwhile
var _failed_game_id: String = "" ## last launch died during its load; its button says FAILED until the user moves on
var _status_note: String = "" ## transient banner suffix: "Launching X..." / "Launch failed: X - reason"
var _selected_game_id: String = "" ## last game opened/launched; restored + persisted as view state
var _marquee: Node3D = null ## the loading marquee's holder; in the tree only during a load wait
var _marquee_year: Label3D = null
var _marquee_name: Label3D = null
var _marquee_up: bool = false
var _marquee_t: float = 0.0 ## seconds since the marquee rose
var _wall_alpha_applied: float = 1.0 ## the wall fade's last applied alpha (change guard)
var _placard: Node3D = null ## the setup placard's holder; in the tree only while the placard stands
var _placard_face: ClickableQuad = null
var _placard_back: ClickableQuad = null
var _placard_up: bool = false
var _placard_gen: int = 0
var _placard_message: String = "" ## the message the standing placard carries (a launch failure rides it too)
var _pick_snapshot: Dictionary = {} ## ClickableQuad -> pick_enabled, taken as the placard rises
var _rail_quads: Dictionary = {} ## key -> ClickableQuad
var _rail_tex_cache: Dictionary = {} ## "label|accent" -> Texture2D: every rail button face ever rendered, so a rebuild re-dresses the rail in its own frame
var _slide_phase: int = 0 ## the page slide: 0 rest, 1 gliding out, 2 gliding back (see _update_slide)
var _slide_dir: int = 0 ## the live slide's travel direction: +1 next page, -1 previous
var _slide_t: float = 0.0 ## seconds into the live slide's current leg
var _slide_step: int = 0 ## the pending page delta, applied at the far point
var _slide_after: Callable = Callable() ## the pending swap's focus landing (the bumper rule), run at the far point
var _slide_swapping: bool = false ## the far-point rebuild is in flight: _rebuild_wall must not cancel the slide for it
var _focusables: Array[ClickableQuad] = []
var _focused: ClickableQuad = null
var _joy_cooldown: float = 0.0
var _joy_prev_a: bool = false
var _joy_prev_b: bool = false
var _joy_prev_lb: bool = false ## bumper edge tracking: the section slide's page travel (see _process)
var _joy_prev_rb: bool = false
var _joy_prev_right: bool = false ## D-pad Right edge tracking: the room's BACK-out press (see _process)
var _joy_right_armed: bool = false ## baseline-release arming: set once THIS room instance has observed D-pad Right released; until then no right-press edge can exit (see _process)


func setup(factory: TextureFactory, scanner: LibraryScanner, store: StateStore, xr_enabled: bool) -> void:
	_factory = factory
	_scanner = scanner
	_store = store
	_xr_enabled = xr_enabled
	_build_environment()
	_build_rigs()
	_detail = DetailView.new()
	_detail.setup(factory, store)
	_detail.position = Vector3(0.0, 1.3, -1.72)
	add_child(_detail)
	ClickableQuad.face_point(_detail, EYE)
	_detail.closed.connect(_on_detail_closed)
	_detail.play_requested.connect(_on_detail_play)
	# Return-trip restore (M2): the watchdog's relaunch should land
	# the player exactly where they left - same filter/sort, and the
	# just-played (or last-opened) table's page, selected.
	if _store.view_filter != "" and FILTERS.has(_store.view_filter):
		_filter = _store.view_filter
	if _store.view_sort != "" and SORTS.has(_store.view_sort):
		_sort = _store.view_sort
	_selected_game_id = _store.selected_game_id
	if _selected_game_id == "":
		_selected_game_id = _store.last_played_game_id
	refresh_library()
	_restore_selection()


func refresh_library() -> void:
	_recompute_visible()
	_page = 0
	_rebuild_wall()


## After a restore, put the wall on the selected game's page and the
## focus on its panel. Runs once at setup; harmless no-ops when the
## game is not in the current filter.
func _restore_selection() -> void:
	if _selected_game_id == "":
		return
	for i: int in range(_visible_games.size()):
		if _visible_games[i].game_id == _selected_game_id:
			var target_page: int = i / PAGE_SIZE
			if target_page != _page:
				_page = target_page
				_rebuild_wall()
			var slot: int = i % PAGE_SIZE
			if slot < _panels.size():
				_set_focused(_panels[slot])
			return


## View state outlives the process (the launcher exits on every
## launch), so every view change lands in the store immediately.
func _persist_view() -> void:
	_store.set_view_state(_filter, _sort, _page, _selected_game_id)
	_store.save_to_disk()


# ---------------------------------------------------------------- rigs

func _build_rigs() -> void:
	var origin: XROrigin3D = XROrigin3D.new()
	origin.name = "XROrigin3D"
	add_child(origin)
	_xr_camera = XRCamera3D.new()
	origin.add_child(_xr_camera)
	for side: String in ["left", "right"]:
		var ctrl: XRController3D = XRController3D.new()
		ctrl.tracker = StringName("/user/hand/" + side)
		origin.add_child(ctrl)
	_desk_rig = Node3D.new()
	_desk_rig.position = EYE
	add_child(_desk_rig)
	_desk_camera = Camera3D.new()
	_desk_camera.fov = 70.0
	_desk_camera.current = not _xr_enabled
	_desk_rig.add_child(_desk_camera)
	_rig = PointerRig.new()
	add_child(_rig)
	_rig.xr_active = _xr_enabled
	_rig.mouse_camera = _desk_camera
	_rig.setup_controllers(origin)
	_rig.hover_changed.connect(_on_hover_changed)
	_rig.select_pressed.connect(_on_select)


func _active_camera() -> Camera3D:
	return _xr_camera if _xr_enabled else _desk_camera


## QA seam (the seated wall shots, the nav smoke): drop the flat
## camera to a seated player's eye height. The room's geometry is
## tuned around EYE (the face_point target); this moves only the
## desk rig, exactly what a shorter player changes in the headset.
func set_desk_camera_height(y: float) -> void:
	if _desk_rig != null:
		_desk_rig.position.y = y


# ---------------------------------------------------------- environment

func _build_environment() -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.012, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.44)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)

	var floor_inst: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(14.0, 14.0)
	floor_inst.mesh = plane
	var fm: StandardMaterial3D = StandardMaterial3D.new()
	fm.albedo_color = Color(0.045, 0.045, 0.065)
	fm.roughness = 0.95
	floor_inst.material_override = fm
	add_child(floor_inst)

	var backdrop: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 4.4
	cyl.bottom_radius = 4.4
	cyl.height = 3.6
	backdrop.mesh = cyl
	backdrop.position = Vector3(0.0, 1.7, 0.0)
	var bm: StandardMaterial3D = StandardMaterial3D.new()
	bm.albedo_color = Color(0.03, 0.03, 0.05)
	bm.cull_mode = BaseMaterial3D.CULL_FRONT
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	backdrop.material_override = bm
	add_child(backdrop)

	var omni: OmniLight3D = OmniLight3D.new()
	omni.position = Vector3(0.0, 2.6, -0.6)
	omni.light_color = Color(1.0, 0.93, 0.8)
	omni.light_energy = 0.7
	omni.omni_range = 7.0
	add_child(omni)
	for sx: float in [-1.8, 1.8]:
		var spot: SpotLight3D = SpotLight3D.new()
		spot.position = Vector3(sx, 2.9, -0.4)
		spot.light_color = Color(1.0, 0.95, 0.85)
		spot.light_energy = 1.1
		spot.spot_range = 8.0
		spot.spot_angle = 42.0
		add_child(spot)
		spot.look_at(Vector3(sx * 0.4, 1.1, -WALL_RADIUS), Vector3.UP)

	_wall = Node3D.new()
	_wall.name = "Wall"
	add_child(_wall)
	_rail = Node3D.new()
	_rail.name = "Rail"
	add_child(_rail)


# -------------------------------------------------------------- library

func _recompute_visible() -> void:
	_filter_note = ""
	_collect_visible()
	# Empty-filter guard: a filter that matches nothing in a non-empty
	# library must never present as an empty room (that is exactly how
	# the sample-database trap showed up in the field - a black wall
	# and "1/1"). Fall back to ALL and let the banner say why. VR
	# stays the default only when VR-tagged games actually exist.
	if _filter != "all" and _visible_games.is_empty() and _scanner != null and not _scanner.games.is_empty():
		_filter_note = "%s filter found none - showing ALL" % str(FILTER_LABELS[_filter])
		_filter = "all"
		_collect_visible()
	var pages: int = page_count()
	if _page >= pages:
		_page = maxi(0, pages - 1)


func _collect_visible() -> void:
	_visible_games.clear()
	if _scanner == null:
		return
	var source: Array[GameEntry] = []
	if _filter == "recents":
		for gid: String in _store.recents:
			var g: GameEntry = _scanner.game_by_id(gid)
			if g != null:
				source.append(g)
	else:
		for g: GameEntry in _scanner.games:
			match _filter:
				"all":
					source.append(g)
				"vr":
					if g.is_vr_tagged():
						source.append(g)
				"favorites":
					if _store.is_favorite(g.game_id):
						source.append(g)
	_visible_games = source
	if _filter != "recents":
		_sort_visible()


func page_count() -> int:
	if _visible_games.is_empty():
		return 1
	return int(ceil(float(_visible_games.size()) / float(PAGE_SIZE)))


func _sort_visible() -> void:
	match _sort:
		"name":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				return a.title.to_lower() < b.title.to_lower())
		"year":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				var ay: int = a.year if a.year > 0 else 9999
				var by: int = b.year if b.year > 0 else 9999
				if ay != by:
					return ay < by
				return a.title.to_lower() < b.title.to_lower())
		"manufacturer":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				if a.manufacturer.to_lower() != b.manufacturer.to_lower():
					return a.manufacturer.to_lower() < b.manufacturer.to_lower()
				return a.title.to_lower() < b.title.to_lower())
		"designer":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				var ad: String = a.designers[0].to_lower() if not a.designers.is_empty() else "zzzz"
				var bd: String = b.designers[0].to_lower() if not b.designers.is_empty() else "zzzz"
				if ad != bd:
					return ad < bd
				return a.title.to_lower() < b.title.to_lower())


# ---------------------------------------------------------------- wall

func _rebuild_wall() -> void:
	_gen += 1
	var gen: int = _gen
	wall_ready = false
	if _slide_phase != 0 and not _slide_swapping:
		# A rebuild that is not the slide's own far-point swap (a
		# filter change, a detail close, a launch failure) cancels
		# any live slide outright: the pending travel is forgotten
		# and the holder snaps back to exact rest rather than
		# swapping pages under a wall the player already replaced.
		_slide_phase = 0
		_slide_after = Callable()
		if _wall != null:
			_wall.rotation.y = 0.0
	for child: Node in _wall.get_children():
		_wall.remove_child(child)
		child.queue_free()
	_panels.clear()
	_panel_launches.clear()
	_panel_base_pos.clear()
	_panel_pop_dir.clear()
	_panel_pop.clear()
	_panel_pop_applied.clear()
	_wall_alpha_applied = 1.0 ## fresh quads start opaque; the marquee fade re-applies from there
	_set_focused(null)

	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	# Banner: above the eye line (~+23 degrees) with clear air between
	# its lower edge and the top row of panels - it sits closer than
	# the wall, so any angular overlap hides the middle panels' tops.
	# It rose with the rows in the occlusion round (see WALL_ROW_YS),
	# keeping that clear air the same size.
	_banner_quad = _make_quad(_wall, "banner", "", placeholder, Vector2(1.8, 0.46), Vector3(0.0, 2.53, -2.9))
	_banner_quad.pick_enabled = false
	# Panels for this page: rows hugging the eye line (+12 / 0 / -12
	# degrees). Panel height (0.64) stays under the row pitch (0.65) -
	# a taller panel than the pitch makes rows overlap in projection.
	var start: int = _page * PAGE_SIZE
	for i: int in range(PAGE_SIZE):
		var idx: int = start + i
		if idx >= _visible_games.size():
			break
		var game: GameEntry = _visible_games[idx]
		var col: int = i % PAGE_COLS
		var row: int = i / PAGE_COLS
		var angle: float = deg_to_rad(float(col - 1) - 0.5) * 14.0
		var pos: Vector3 = Vector3(sin(angle) * WALL_RADIUS, WALL_ROW_YS[row], -cos(angle) * WALL_RADIUS)
		var q: ClickableQuad = _make_quad(_wall, "panel", game.game_id, placeholder, PANEL_SIZE, pos)
		_panels.append(q)
		_panel_base_pos.append(pos)
		_panel_pop_dir.append((EYE - pos).normalized())
		_panel_pop.append(0.0)
		_panel_pop_applied.append(0.0)
		# The card's Launch button (Chris, 2026-10-21): a distinct
		# quad riding the panel's lower third - pointing at the card
		# browses (opens More Info); only the button commits to the
		# ~20s VPX load. It inherits the panel's orientation and its
		# pulse, sits proud of the card face so rays hit it first.
		# Its height on the panel is PANEL_LAUNCH_Y: clear of the
		# art face's name strip, never over the name.
		var lq: ClickableQuad = ClickableQuad.new()
		lq.setup("panel_launch", game.game_id, placeholder, PANEL_LAUNCH_SIZE)
		lq.position = Vector3(0.0, PANEL_LAUNCH_Y, 0.032)
		q.add_child(lq)
		_panel_launches.append(lq)
	# Rail: built ONCE and persistent across rebuilds (the feel
	# round, 2026-10-24). Destroying and recreating it on every
	# page flip made every button pop back into existence as its
	# texture streamed in - Chris: "the lower filter bar
	# refreshes itself every time, every button." The bar is
	# furniture: it stands while the wall moves. A rebuild just
	# resets the standing quads' pick/alpha state to the fresh-
	# build defaults the recreate used to provide (the placard
	# branch below re-inerts them when it has to) and re-dresses
	# them from the texture cache in this same frame.
	if _rail_quads.is_empty():
		_build_rail(placeholder)
	else:
		for k: Variant in _rail_quads.keys():
			var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
			if rq != null:
				rq.pick_enabled = str(k) != "page_label"
				rq.set_content_alpha(1.0)
	_apply_rail_textures()
	_refresh_focusables()
	_fill_wall_textures(gen)
	if _placard_up:
		# A rebuild while the placard stands (the launch-failure
		# path) must not resurrect live controls behind it.
		_inert_room_quads()
		_set_focused(_placard_back)


func _build_rail(placeholder: Texture2D) -> void:
	# ~22 degrees below the eye line and far enough out that the full
	# rail width sits inside a 16:9 frustum (it was clipped at the
	# bottom edge of the flat view when it hugged the player).
	# Lowered from 0.55 in the occlusion round: from a seated eye
	# the rail's top edge projected BELOW the wall's bottom row and
	# swallowed its lower edge (see WALL_ROW_YS) - at 0.45 the top
	# edge clears the row by ~4.4 degrees.
	var y: float = 0.45
	var z: float = -1.85
	var defs: Array = [
		["filter:all", 0.30], ["filter:vr", 0.24], ["filter:favorites", 0.44], ["filter:recents", 0.40],
		["sort", 0.52], ["page_prev", 0.18], ["page_label", 0.28], ["page_next", 0.18], ["desk", 0.32], ["exit", 0.28],
	]
	var total: float = 0.0
	for d: Variant in defs:
		total += float(d[1]) + 0.035
	total -= 0.035
	var x: float = -total * 0.5
	for d: Variant in defs:
		var key: String = str(d[0])
		var w: float = float(d[1])
		var q: ClickableQuad = _make_quad(_rail, "rail", key, placeholder, Vector2(w, 0.15), Vector3(x + w * 0.5, y, z))
		if key == "page_label":
			q.pick_enabled = false
		_rail_quads[key] = q
		x += w + 0.035


func _make_quad(parent: Node3D, action: String, payload: String, tex: Texture2D, size: Vector2, pos: Vector3) -> ClickableQuad:
	var q: ClickableQuad = ClickableQuad.new()
	q.setup(action, payload, tex, size)
	q.position = pos
	parent.add_child(q)
	ClickableQuad.face_point(q, EYE)
	return q


## The banner's one line: library summary, the empty-filter guard's
## explanation when it fired, and any transient launch status.
func _banner_line() -> String:
	var line: String = "%d files - %d games - filter %s - sort %s" % [
		_scanner.total_files, _scanner.games.size(),
		str(FILTER_LABELS[_filter]), str(SORT_LABELS[_sort])]
	if _filter_note != "":
		line += " - " + _filter_note
	if _status_note != "":
		line += " - " + _status_note
	return line


func _refresh_banner() -> void:
	if _banner_quad == null or _scanner == null:
		return
	var gen: int = _gen
	var tex: Texture2D = await _factory.render_texture(RoomSpecs.banner_spec(_banner_line()), Vector2i(1024, 262))
	if gen == _gen and _banner_quad != null:
		_banner_quad.set_texture(tex)


## A rail stop's [label, accent] under the room's current
## state - the one place that knows what each button says.
func _rail_label_accent(key: String) -> Array:
	var label: String = ""
	var accent: bool = false
	if key.begins_with("filter:"):
		var f: String = key.trim_prefix("filter:")
		label = str(FILTER_LABELS[f])
		accent = f == _filter
	elif key == "sort":
		label = "SORT: " + str(SORT_LABELS[_sort])
	elif key == "page_prev":
		label = "<"
	elif key == "page_next":
		label = ">"
	elif key == "page_label":
		label = "%d / %d" % [_page + 1, page_count()]
	elif key == "desk":
		label = "SETUP"
	elif key == "exit":
		label = "EXIT"
	return [label, accent]


func _rail_cache_key(label: String, accent: bool) -> String:
	return label + ("|a" if accent else "|p")


## Dress every rail quad from the texture cache, in this call -
## no awaits. A cache hit is the button's real rendered face,
## so the rail is fully dressed in the rebuild's own frame. A
## miss keeps whatever face the quad already wears (the
## standing rail never falls back to the placeholder again)
## until the async fill renders that label - once, ever.
func _apply_rail_textures() -> void:
	for k: Variant in _rail_quads.keys():
		var la: Array = _rail_label_accent(str(k))
		var ck: String = _rail_cache_key(str(la[0]), bool(la[1]))
		if _rail_tex_cache.has(ck):
			var quad: ClickableQuad = _rail_quads[k] as ClickableQuad
			if quad != null:
				quad.set_texture(_rail_tex_cache[ck] as Texture2D)


func _fill_wall_textures(gen: int) -> void:
	# Banner first: it carries the library summary line.
	var banner_tex: Texture2D = await _factory.render_texture(RoomSpecs.banner_spec(_banner_line()), Vector2i(1024, 262))
	if gen != _gen or _banner_quad == null:
		return
	_banner_quad.set_texture(banner_tex)
	# Rail buttons SECOND - they used to render last, after a
	# dozen panels and their Launch buttons, which is exactly
	# why the bar reassembled itself piece by piece on every
	# flip. Cache hits dress instantly; a label that has never
	# rendered (a first-ever page count) renders now, ahead of
	# the panels, and joins the cache for every later wall.
	for key: Variant in _rail_quads.keys():
		var k: String = str(key)
		var quad: ClickableQuad = _rail_quads[k]
		var la: Array = _rail_label_accent(k)
		var label: String = str(la[0])
		var accent: bool = bool(la[1])
		var ck: String = _rail_cache_key(label, accent)
		if _rail_tex_cache.has(ck):
			quad.set_texture(_rail_tex_cache[ck] as Texture2D)
			continue
		var btex: Texture2D = await _factory.render_texture(RoomSpecs.button_spec(label, accent), Vector2i(512, 150))
		if gen != _gen:
			return
		_rail_tex_cache[ck] = btex
		quad.set_texture(btex)
	# Panels.
	var start: int = _page * PAGE_SIZE
	for i: int in range(_panels.size()):
		var game: GameEntry = _visible_games[start + i]
		var quad: ClickableQuad = _panels[i]
		var tex: Texture2D = null
		var art_file: String = game.ensure_art()
		if art_file != "":
			var art_tex: Texture2D = TextureFactory.load_art_texture(art_file)
			if art_tex != null:
				tex = await _factory.render_texture(RoomSpecs.art_spec(game, art_tex), Vector2i(512, 640))
		if tex == null:
			tex = await _factory.render_texture(RoomSpecs.panel_spec(game, _store), Vector2i(512, 640))
		if gen != _gen:
			return
		quad.set_texture(tex)
		if i < _panel_launches.size():
			var failed: bool = game.game_id == _failed_game_id
			var ltex: Texture2D = await _factory.render_texture(
				RoomSpecs.button_spec("FAILED" if failed else "LAUNCH", not failed), Vector2i(512, 164))
			if gen != _gen:
				return
			_panel_launches[i].set_texture(ltex)
	if gen == _gen:
		wall_ready = true
		# The page is settled: ask Main's warmer to bring the
		# neighbouring pages' art forward (next page first), so a
		# flip lands on warm art even mid-warm-up.
		var near: Array = []
		var total: int = _visible_games.size()
		var next_start: int = start + PAGE_SIZE
		if next_start < total:
			var next_cnt: int = mini(PAGE_SIZE, total - next_start)
			for j: int in range(next_cnt):
				near.append(_visible_games[next_start + j])
		var prev_start: int = start - PAGE_SIZE
		if prev_start >= 0:
			var prev_cnt: int = mini(PAGE_SIZE, total - prev_start)
			for j: int in range(prev_cnt):
				near.append(_visible_games[prev_start + j])
		if not near.is_empty():
			art_prefetch_requested.emit(near)


# ------------------------------------------------------------ interaction

func _refresh_focusables() -> void:
	_focusables.clear()
	if _launching_game_id != "":
		# The load wait is deaf (see begin_launch): the focusable
		# set is EMPTY, so focus navigation has nowhere to land
		# and there is no focused quad for a stray press to fire.
		pass
	elif _placard_up:
		# The placard owns the room: BACK is the only focus stop.
		if _placard_back != null:
			_focusables.append(_placard_back)
	elif _mode == "detail" and _detail != null:
		_focusables = _detail.get_clickables()
	else:
		for i: int in range(_panels.size()):
			_focusables.append(_panels[i])
			if i < _panel_launches.size() and _panel_launches[i].pick_enabled:
				_focusables.append(_panel_launches[i])
		for k: Variant in _rail_quads.keys():
			var q: ClickableQuad = _rail_quads[k]
			if q.pick_enabled:
				_focusables.append(q)
	if _focused != null and not _focusables.has(_focused):
		_set_focused(null)
	_refresh_quad_states()


func _set_focused(q: ClickableQuad) -> void:
	_focused = q
	_refresh_quad_states()


func _refresh_quad_states() -> void:
	var hovered: ClickableQuad = _rig.hovered if _rig != null else null
	var all: Array[ClickableQuad] = []
	all.append_array(_panels)
	all.append_array(_panel_launches)
	for k: Variant in _rail_quads.keys():
		all.append(_rail_quads[k])
	if _detail != null:
		all.append_array(_detail.get_clickables())
	if _banner_quad != null:
		all.append(_banner_quad)
	if _placard_face != null:
		all.append(_placard_face)
	if _placard_back != null:
		all.append(_placard_back)
	for q: ClickableQuad in all:
		q.set_visual_state(q == hovered, q == _focused)


func _on_hover_changed(_quad: ClickableQuad) -> void:
	_refresh_quad_states()


## The panel a focus-ish quad belongs to: the quad itself when it
## is a card, or the card whose Launch button it is. Anything else
## (rail, detail, banner) owns no card.
func _panel_for(q: ClickableQuad) -> ClickableQuad:
	if q == null:
		return null
	if _panels.has(q):
		return q
	var lidx: int = _panel_launches.find(q)
	if lidx >= 0 and lidx < _panels.size():
		return _panels[lidx]
	return null


## The one card that should be popped right now, on the room's
## single shared focus: the pointer's card wins (VR laser and
## mouse hover both arrive as the rig's hover), else the
## gamepad/keyboard focus's card. No pop while the detail view or
## the placard owns the room, and none during the load wait - the
## wall is frozen behind the marquee there.
func _pop_target_panel() -> ClickableQuad:
	if _mode != "wall" or _placard_up or _launching_game_id != "":
		return null
	var hovered: ClickableQuad = _rig.hovered if _rig != null else null
	var p: ClickableQuad = _panel_for(hovered)
	if p != null:
		return p
	return _panel_for(_focused)


## Per-frame pop animation, driven from _process: each panel's
## amount walks toward 1 (the target) or 0 at POP_OUT_SEC pace,
## and the transform is written only while the amount is actually
## moving - a resting panel is never touched, so a Launch
## button's activation pulse (a scale tween) never fights this.
## The Launch button rides its panel (it is a child), so it stays
## glued to the card face and clickable while popped. The marquee
## fade needs no help here: it drives material alpha, which a
## popped card carries like any other.
func _update_pop(delta: float) -> void:
	if _panels.is_empty():
		return
	var target: ClickableQuad = _pop_target_panel()
	var step: float = delta / POP_OUT_SEC
	for i: int in range(_panels.size()):
		var want: float = 1.0 if _panels[i] == target else 0.0
		var amt: float = move_toward(_panel_pop[i], want, step)
		_panel_pop[i] = amt
		if absf(amt - _panel_pop_applied[i]) < 0.001:
			continue
		_panel_pop_applied[i] = amt
		var q: ClickableQuad = _panels[i]
		q.position = _panel_base_pos[i] + _panel_pop_dir[i] * (POP_OUT_DISTANCE * amt)
		q.scale = Vector3.ONE * (1.0 + (POP_OUT_SCALE - 1.0) * amt)


func _on_select(quad: ClickableQuad) -> void:
	if quad == null or not quad.pick_enabled:
		return
	_activate(quad)


func _activate(quad: ClickableQuad) -> void:
	if _placard_up:
		# While the placard stands, everything else is inert. The
		# pick flags already say so for the pointer; this is the
		# lock for the keyboard/gamepad paths, which activate the
		# focused quad directly.
		if quad.action_id == "placard_back":
			quad.pulse()
			hide_setup_placard()
		return
	if _launching_game_id != "":
		# The load wait is deaf (see begin_launch): NO quad
		# activates until the wait settles - not EXIT, not SETUP,
		# not a card. Every input path funnels through here, so
		# this one refusal covers pointer, keyboard, and gamepad.
		return
	if _mode == "detail":
		if quad.action_id.begins_with("detail"):
			quad.pulse()
			_detail.handle(quad)
		return
	match quad.action_id:
		"panel":
			var game: GameEntry = _scanner.game_by_id(quad.payload)
			if game != null:
				quad.pulse()
				_open_detail(game)
		"panel_launch":
			var game2: GameEntry = _scanner.game_by_id(quad.payload)
			if game2 != null:
				var build: TableBuild = game2.resolve_default_build(_store)
				if build != null:
					quad.pulse()
					_selected_game_id = game2.game_id
					_persist_view()
					launch_requested.emit(game2, build)
		"rail":
			quad.pulse()
			_handle_rail(quad.payload)


## Rail handling. Page travel (page_prev / page_next) is the
## one branch that does not rebuild on the spot: it starts the
## page slide, and the page delta, rebuild, and view persist
## land together at the slide's far point (see _begin_page_slide).
## after_swap is the bumper path's focus landing, run in the
## far-point frame; pointer and keyboard travel pass none.
func _handle_rail(key: String, after_swap: Callable = Callable()) -> void:
	if key.begins_with("filter:") or key == "sort" or key == "page_prev" or key == "page_next":
		# Browsing onward retires the last launch's marks.
		_failed_game_id = ""
		_status_note = ""
	if key.begins_with("filter:"):
		_filter = key.trim_prefix("filter:")
		_page = 0
		_recompute_visible()
		_rebuild_wall()
		_persist_view()
	elif key == "sort":
		var idx: int = SORTS.find(_sort)
		_sort = SORTS[(idx + 1) % SORTS.size()]
		_page = 0
		_recompute_visible()
		_rebuild_wall()
		_persist_view()
	elif key == "page_prev":
		if _page > 0:
			_begin_page_slide(-1, after_swap)
	elif key == "page_next":
		if _page < page_count() - 1:
			_begin_page_slide(1, after_swap)
	elif key == "desk":
		setup_requested.emit()
	elif key == "exit":
		exit_requested.emit()


## A page change's ride (see PAGE_SLIDE_*): the press commits
## to the travel at once, but the wall glides out over
## PAGE_SLIDE_OUT_SEC, the page delta + rebuild + persist land
## in ONE frame at the far point, and the wall glides back to
## exact rest over PAGE_SLIDE_BACK_SEC. A press that lands
## mid-slide fast-forwards the live slide first (its swap
## lands, the holder snaps to rest) and starts fresh, so
## presses never queue, stack, or corrupt. If the room has
## left plain wall browsing by the far point (detail opened,
## placard up, a launch begun), the pending travel is dropped
## whole: the wall just glides home wearing its old page.
func _begin_page_slide(step: int, after_swap: Callable) -> void:
	_slide_finish_now()
	_slide_dir = step
	_slide_step = step
	_slide_after = after_swap
	_slide_t = 0.0
	_slide_phase = 1


## Complete a live slide on the spot: a pending far-point
## swap lands now (subject to the same drop rule), and the
## holder returns to exact rest.
func _slide_finish_now() -> void:
	if _slide_phase == 0:
		return
	if _slide_phase == 1:
		_slide_do_swap()
	_slide_phase = 0
	_slide_t = 0.0
	if _wall != null:
		_wall.rotation.y = 0.0


## The far point: page delta, rebuild, and persist in one
## frame, then the press's focus landing. Dropped whole when
## the room is no longer plain wall browsing - a rebuild
## forced through here mid-load-wait would resurrect pickable
## quads in a room that must stay deaf.
func _slide_do_swap() -> void:
	if _mode != "wall" or _placard_up or _launching_game_id != "":
		_slide_after = Callable()
		return
	_slide_swapping = true
	_page += _slide_step
	_rebuild_wall()
	_persist_view()
	_slide_swapping = false
	var after: Callable = _slide_after
	_slide_after = Callable()
	if after.is_valid():
		after.call()


## Per-frame slide drive, from _process: eased yaw out, swap
## at the far point, eased yaw home to EXACTLY zero.
func _update_slide(delta: float) -> void:
	if _slide_phase == 0 or _wall == null:
		return
	_slide_t += delta
	if _slide_phase == 1:
		var p: float = clampf(_slide_t / PAGE_SLIDE_OUT_SEC, 0.0, 1.0)
		_wall.rotation.y = deg_to_rad(float(_slide_dir) * PAGE_SLIDE_YAW_DEG * _slide_ease(p))
		if p >= 1.0:
			_slide_do_swap()
			_slide_phase = 2
			_slide_t = 0.0
	elif _slide_phase == 2:
		var p2: float = clampf(_slide_t / PAGE_SLIDE_BACK_SEC, 0.0, 1.0)
		_wall.rotation.y = deg_to_rad(float(_slide_dir) * PAGE_SLIDE_YAW_DEG * (1.0 - _slide_ease(p2)))
		if p2 >= 1.0:
			_wall.rotation.y = 0.0
			_slide_phase = 0


func _slide_ease(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


## A bumper press's page travel: the whole section shifts one
## page over (Chris's clarification, 2026-10-24 - the bumpers
## flip PAGES, never filters; the filters change only via the
## rail). Routed through the rail pager's own handling, so the
## bounds are the pager's bounds - CLAMPED at both ends, no
## wrap - and page state persists exactly as a rail press's
## does. Inert under the room's standing input law: the load
## wait is deaf, the SETUP placard owns the room, and the
## detail view is not the wall.
##
## Focus rule (stated for the smoke to assert): focus keeps its
## PLACE across the flip. A focused panel - or its Launch
## button - hands focus to the panel in the same grid slot on
## the new page (the panel itself, never its Launch button, so
## a follow-up A press browses instead of firing a load),
## clamped to the new page's last panel when the page runs
## short; a focused rail stop hands focus to the same stop on
## the rebuilt rail; no focus lands on the first panel. The
## landing runs at the slide's far point, in the swap frame -
## until then the old wall (and its focus) rides the glide. A
## clamped press changes nothing at all - no slide, no
## rebuild, so focus keeps even its instance.
func _bumper_page(step: int) -> void:
	if _launching_game_id != "" or _placard_up or _mode != "wall":
		return
	var slot: int = -1
	var rail_key: String = ""
	if _focused != null:
		if _panels.has(_focused):
			slot = _panels.find(_focused)
		elif _panel_launches.has(_focused):
			slot = _panel_launches.find(_focused)
		elif _is_rail_quad(_focused):
			for k: Variant in _rail_quads.keys():
				if _rail_quads[k] == _focused:
					rail_key = str(k)
					break
	_handle_rail("page_next" if step > 0 else "page_prev", _flip_focus_landing(slot, rail_key))


## The bumper rule's landing, packaged for the far point: when
## the slide's swap lands, focus takes the same PLACE on the
## new wall - the same rail stop, or the panel in the same
## grid slot, clamped to a short page's last panel; from no
## focus, the first panel.
func _flip_focus_landing(slot: int, rail_key: String) -> Callable:
	return func() -> void:
		if rail_key != "":
			var rq: ClickableQuad = _rail_quads.get(rail_key) as ClickableQuad
			if rq != null:
				_set_focused(rq)
		elif not _panels.is_empty():
			var target: int = 0 if slot < 0 else mini(slot, _panels.size() - 1)
			_set_focused(_panels[target])


func _open_detail(game: GameEntry) -> void:
	_mode = "detail"
	_selected_game_id = game.game_id
	_store.touch_recent(game.game_id)
	_persist_view()
	for q: ClickableQuad in _panels:
		q.pick_enabled = false
	for q: ClickableQuad in _panel_launches:
		q.pick_enabled = false
	for k: Variant in _rail_quads.keys():
		_rail_quads[k].pick_enabled = false
	_detail.show_game(game)
	_set_focused(null)
	_refresh_focusables()


## Detail Play forwards into the same launch path as the card's
## Launch button (default build, or the armed play-once build).
func _on_detail_play(game: GameEntry, build: TableBuild) -> void:
	_selected_game_id = game.game_id
	_persist_view()
	launch_requested.emit(game, build)


# ------------------------------------------------------- setup placard

## SETUP while XR is live (Main routes here): the desk itself is a
## 2D form in the root viewport and cannot reach the headset, so the
## room stays up and this placard stands in it - the explanation,
## plus the way back. While it stands, every other control in the
## room is inert: pick flags down (the snapshot restores them on
## the way out), focus confined to BACK, and _activate refuses
## everything else. A Launch fired blind behind a setup session
## would be a state bug waiting to happen.
func show_setup_placard(message: String = "") -> void:
	_placard_message = message
	if _placard == null:
		_build_placard()
	if not _placard_up:
		_pick_snapshot.clear()
		for q: ClickableQuad in _room_pickables():
			_pick_snapshot[q] = q.pick_enabled
		_placard_up = true
		add_child(_placard)
		ClickableQuad.face_point(_placard, EYE)
		_inert_room_quads()
	_refresh_focusables()
	_set_focused(_placard_back)
	_placard_gen += 1
	_fill_placard_textures(_placard_gen, message)


## The placard's BACK: tear it down, hand the room back, and tell
## Main to close the desk it opened alongside.
func hide_setup_placard() -> void:
	if not _placard_up:
		return
	clear_setup_placard()
	setup_placard_dismissed.emit()


## Silent teardown for Main's own routes (Enter the Room on the
## desk, a fresh room entry): no signal - Main is already driving,
## and entering the room must never find a stale placard standing.
func clear_setup_placard() -> void:
	if not _placard_up:
		return
	_placard_up = false
	_placard_gen += 1
	if _placard != null:
		# Freed, not parked: an out-of-tree holder kept alive
		# orphans its meshes/materials/textures, and the renderer
		# teardown choked on them at exit (exported-build crash,
		# placard round). The detail view frees its quads the
		# same way; a rebuild on the next show costs nothing.
		if _placard.get_parent() != null:
			remove_child(_placard)
		_placard.queue_free()
		_placard = null
		_placard_face = null
		_placard_back = null
	_restore_room_pick_states()
	_set_focused(null)
	_refresh_focusables()


func is_setup_placard_up() -> bool:
	return _placard_up


func setup_placard_back_quad() -> ClickableQuad:
	return _placard_back


func setup_placard_message() -> String:
	return _placard_message


func _build_placard() -> void:
	_placard = Node3D.new()
	_placard.name = "SetupPlacard"
	_placard.position = Vector3(0.0, 1.32, -1.72)
	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	_placard_face = ClickableQuad.new()
	_placard_face.setup("placard_face", "", placeholder, Vector2(1.3, 0.64))
	_placard_face.position = Vector3(0.0, 0.17, 0.0)
	_placard_face.pick_enabled = false
	_placard.add_child(_placard_face)
	_placard_back = ClickableQuad.new()
	_placard_back.setup("placard_back", "", placeholder, Vector2(0.44, 0.15))
	_placard_back.position = Vector3(0.0, -0.30, 0.0)
	_placard.add_child(_placard_back)
	# No face_point here: the holder is oriented in
	# show_setup_placard, once it is inside the tree (look_at on
	# an out-of-tree node just errors and does nothing).


func _fill_placard_textures(gen: int, message: String) -> void:
	var tex: Texture2D = await _factory.render_texture(RoomSpecs.placard_spec(message), Vector2i(1024, 504))
	if gen != _placard_gen or not _placard_up or _placard_face == null:
		return
	_placard_face.set_texture(tex)
	var btex: Texture2D = await _factory.render_texture(RoomSpecs.button_spec("BACK", true), Vector2i(512, 164))
	if gen != _placard_gen or not _placard_up or _placard_back == null:
		return
	_placard_back.set_texture(btex)


## Every quad the placard stands in front of, in one list: the
## pick-state snapshot and the inert sweep share it.
func _room_pickables() -> Array[ClickableQuad]:
	var out: Array[ClickableQuad] = []
	out.append_array(_panels)
	out.append_array(_panel_launches)
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null:
			out.append(rq)
	if _banner_quad != null:
		out.append(_banner_quad)
	if _detail != null:
		out.append_array(_detail.get_clickables())
	return out


func _inert_room_quads() -> void:
	for q: ClickableQuad in _room_pickables():
		q.pick_enabled = false


func _restore_room_pick_states() -> void:
	var handled: Array[ClickableQuad] = []
	for key: Variant in _pick_snapshot.keys():
		if not is_instance_valid(key):
			continue
		var q: ClickableQuad = key as ClickableQuad
		if q == null:
			continue
		q.pick_enabled = bool(_pick_snapshot[key])
		handled.append(q)
	_pick_snapshot.clear()
	# Quads born while the placard stood (a wall rebuild on the
	# launch-failure path) hold no snapshot entry; they take the
	# state the room's current mode would have built them with.
	var launching: bool = _launching_game_id != ""
	for q: ClickableQuad in _panels:
		if not handled.has(q):
			q.pick_enabled = not launching
	for q: ClickableQuad in _panel_launches:
		if not handled.has(q):
			q.pick_enabled = not launching
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null and not handled.has(rq):
			if launching:
				rq.pick_enabled = false ## the load wait is deaf: no rail quad picks, EXIT/SETUP included
			else:
				rq.pick_enabled = str(k) != "page_label"


# ------------------------------------------------------- launch states

## A launch is in its load wait (Main owns the wait itself): the
## room goes DEAF for the whole wait - no quad picks, the focusable
## set is empty, _activate refuses everything, EXIT and SETUP
## included. The wait is bounded (Main's hand-off cues, its failure
## path, and the 45s cap), so no cancel control is needed, and none
## is offered.
##
## Why deaf, in full (field root cause, 2026-10-21): this room
## listens to the same gamepad the player plays VPX with, and A is
## both "activate the focused quad" here and the player's plunger
## button there. The old wait deliberately kept EXIT pickable and
## parked focus ON it ("EXIT stays live throughout"), so the
## player's first play press during the load fired EXIT: the
## session disarmed silently, VPX kept loading detached, and the
## player later exited to an editor with no watchdog on duty - the
## "never returns to the interface" failure that survived five
## builds because every switch combination left this path open.
func begin_launch(game: GameEntry) -> void:
	_launching_game_id = game.game_id
	_failed_game_id = ""
	_status_note = "Launching %s... controls are locked while the table loads" % game.title
	for q: ClickableQuad in _panels:
		q.pick_enabled = false
	for q: ClickableQuad in _panel_launches:
		q.pick_enabled = false
	for k: Variant in _rail_quads.keys():
		_rail_quads[k].pick_enabled = false
	if _detail != null and _detail.is_open():
		_detail.set_launching(true)
	_set_focused(null)
	_refresh_focusables()
	_swap_launch_textures()
	_refresh_banner()
	_raise_marquee(game)


## VPX died during the load, with the launcher still resident to
## say so: the failure lands on the wall (FAILED button, banner
## note) and browsing resumes. In detail mode the detail view is
## the visible surface - its Play button is restored and the wall
## rebuilds when it closes, as usual.
func end_launch_failed(game: GameEntry, reason: String) -> void:
	_dismiss_marquee()
	_launching_game_id = ""
	_failed_game_id = game.game_id
	_status_note = "Launch failed: %s - %s" % [game.title, reason]
	if _detail != null and _detail.is_open():
		_detail.set_launching(false)
	if _mode == "detail":
		return
	_rebuild_wall()


## Raise the loading marquee for the wait begin_launch just
## started. Line 1 is the year in big display letters; line 2 is
## the designer beneath it. Fallbacks, per the brief: no year ->
## line 1 falls back to the manufacturer (and then to the title);
## no designer -> line 2 falls back to the title. An empty line
## is HIDDEN - never an "Unknown designer" placeholder.
func _raise_marquee(game: GameEntry) -> void:
	_dismiss_marquee()
	_build_marquee()
	var top: String = ""
	if game.year > 0:
		top = str(game.year)
	elif game.manufacturer != "":
		top = game.manufacturer
	var bottom: String = ""
	if not game.designers.is_empty():
		bottom = ", ".join(PackedStringArray(game.designers))
	elif top != game.title:
		bottom = game.title
	if top == "":
		top = game.title
		bottom = ""
	_marquee_year.text = top
	_marquee_name.text = bottom
	_marquee_name.visible = bottom != ""
	_marquee_t = 0.0
	_marquee_up = true
	add_child(_marquee)
	ClickableQuad.face_point(_marquee, EYE)


func _build_marquee() -> void:
	_marquee = Node3D.new()
	_marquee.name = "LoadingMarquee"
	_marquee.position = Vector3(MARQUEE_SETTLE_POS.x, MARQUEE_SETTLE_POS.y, MARQUEE_START_Z)
	_marquee_year = Label3D.new()
	_marquee_year.pixel_size = MARQUEE_PIXEL_SIZE
	_marquee_year.font_size = MARQUEE_YEAR_FONT_SIZE
	_marquee_year.outline_size = MARQUEE_OUTLINE_SIZE
	_marquee_year.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marquee_year.position = Vector3(0.0, MARQUEE_YEAR_Y, 0.0)
	_marquee_year.modulate = Color(MARQUEE_YEAR_COLOR, 0.0)
	_marquee_year.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, 0.0)
	_marquee.add_child(_marquee_year)
	_marquee_name = Label3D.new()
	_marquee_name.pixel_size = MARQUEE_PIXEL_SIZE
	_marquee_name.font_size = MARQUEE_NAME_FONT_SIZE
	_marquee_name.outline_size = MARQUEE_OUTLINE_SIZE
	_marquee_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marquee_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_marquee_name.width = 700.0
	_marquee_name.position = Vector3(0.0, MARQUEE_NAME_Y, 0.0)
	_marquee_name.modulate = Color(MARQUEE_NAME_COLOR, 0.0)
	_marquee_name.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, 0.0)
	_marquee.add_child(_marquee_name)
	# No face_point here: the holder is oriented in _raise_marquee,
	# once it is inside the tree (the placard's lesson).


## Tear the marquee down and hand the wall its opacity back. The
## holder is FREED, not parked - the placard's rule (renderer
## teardown choked on parked holders at exit). On a successful
## hand-off this never runs: the process exits with the marquee
## standing, which is the point - it holds until the wait settles.
func _dismiss_marquee() -> void:
	_marquee_up = false
	if _marquee != null:
		if _marquee.get_parent() != null:
			remove_child(_marquee)
		_marquee.queue_free()
		_marquee = null
		_marquee_year = null
		_marquee_name = null
	_apply_wall_alpha(1.0)


## Per-frame marquee animation, driven from _process: the wall
## fades down and stays down; the letters fly from the wall to the
## settle point and hold there with a gentle pulse.
func _update_marquee(delta: float) -> void:
	if not _marquee_up or _marquee == null:
		return
	_marquee_t += delta
	var fade_p: float = clampf(_marquee_t / MARQUEE_FADE_SEC, 0.0, 1.0)
	var fade_e: float = fade_p * fade_p * (3.0 - 2.0 * fade_p)
	_apply_wall_alpha(lerpf(1.0, MARQUEE_WALL_ALPHA, fade_e))
	var fly_p: float = clampf(_marquee_t / MARQUEE_FLY_IN_SEC, 0.0, 1.0)
	var fly_e: float = 1.0 - pow(1.0 - fly_p, 3.0)
	_marquee.position = Vector3(MARQUEE_SETTLE_POS.x, MARQUEE_SETTLE_POS.y,
		lerpf(MARQUEE_START_Z, MARQUEE_SETTLE_POS.z, fly_e))
	# The pulse ramps in across the fly-in (multiplied by fly_p)
	# and the scale eases up from the wall, so neither jumps at
	# the settle point.
	var pulse: float = 1.0 + MARQUEE_PULSE_AMOUNT * sin(_marquee_t * MARQUEE_PULSE_RATE * TAU) * fly_p
	_marquee.scale = Vector3.ONE * pulse * lerpf(0.85, 1.0, fly_e)
	var alpha: float = clampf(_marquee_t / (MARQUEE_FLY_IN_SEC * 0.4), 0.0, 1.0)
	_marquee_year.modulate = Color(MARQUEE_YEAR_COLOR, alpha)
	_marquee_year.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, alpha)
	_marquee_name.modulate = Color(MARQUEE_NAME_COLOR, alpha)
	_marquee_name.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, alpha)


## The wall fade itself: panels, their Launch buttons, the rail,
## and the banner. Change-guarded - _update_marquee calls this
## every frame of the wait.
func _apply_wall_alpha(a: float) -> void:
	if absf(a - _wall_alpha_applied) < 0.002:
		return
	_wall_alpha_applied = a
	for q: ClickableQuad in _panels:
		q.set_content_alpha(a)
	for q: ClickableQuad in _panel_launches:
		q.set_content_alpha(a)
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null:
			rq.set_content_alpha(a)
	if _banner_quad != null:
		_banner_quad.set_content_alpha(a)


## Load-wait queries (the lockout smoke reads the room the way the
## placard smoke reads the placard): is a wait in progress, what
## the banner note says, where focus sits, how many focus stops
## exist, and the rail quads by key.
func is_launch_in_wait() -> bool:
	return _launching_game_id != ""


func launch_status_note() -> String:
	return _status_note


func focusable_count() -> int:
	return _focusables.size()


func focused_quad() -> ClickableQuad:
	return _focused


func rail_quad(key: String) -> ClickableQuad:
	var q: Variant = _rail_quads.get(key, null)
	return q as ClickableQuad


## Pop-out queries (the pop shot hook reads the room the way the
## other smokes read theirs): a panel's current pop amount, how
## far it currently sits off its wall-flush position, and the
## panel the shared focus would pop.
func panel_pop_amount(q: ClickableQuad) -> float:
	var idx: int = _panels.find(q)
	if idx < 0:
		return 0.0
	return _panel_pop[idx]


func panel_pop_offset(q: ClickableQuad) -> Vector3:
	var idx: int = _panels.find(q)
	if idx < 0:
		return Vector3.ZERO
	return q.position - _panel_base_pos[idx]


func pop_target() -> ClickableQuad:
	return _pop_target_panel()


## Page-slide queries (the nav smoke and the slide shot read
## the slide the way the other smokes read their subjects):
## the wall holder's current yaw in degrees - 0.0 is exact
## rest - and whether a slide is live.
func page_slide_yaw_deg() -> float:
	if _wall == null:
		return 0.0
	return rad_to_deg(_wall.rotation.y)


func page_slide_active() -> bool:
	return _slide_phase != 0


func _swap_launch_textures() -> void:
	var gen: int = _gen
	var start: int = _page * PAGE_SIZE
	for i: int in range(_panel_launches.size()):
		var game: GameEntry = _visible_games[start + i]
		var is_this: bool = game.game_id == _launching_game_id
		var tex: Texture2D = await _factory.render_texture(
			RoomSpecs.button_spec("LOADING..." if is_this else "LAUNCH", is_this), Vector2i(512, 164))
		if gen != _gen:
			return
		_panel_launches[i].set_texture(tex)


func _on_detail_closed() -> void:
	_mode = "wall"
	# Favorites / recents may have changed in detail: rebuild the wall.
	_recompute_visible()
	_rebuild_wall()


func _unhandled_input(event: InputEvent) -> void:
	if _launching_game_id != "":
		return ## the load wait is deaf: no focus moves, no activation, no detail escape
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_LEFT:
				_move_focus(Vector2(-1.0, 0.0))
			KEY_RIGHT:
				_move_focus(Vector2(1.0, 0.0))
			KEY_UP:
				_move_focus(Vector2(0.0, -1.0))
			KEY_DOWN:
				_move_focus(Vector2(0.0, 1.0))
			KEY_TAB:
				_cycle_focus(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if _focused != null:
					_activate(_focused)
			KEY_ESCAPE:
				if _mode == "detail":
					_detail.handle_escape()


func _process(delta: float) -> void:
	# The flat (non-XR) camera is STATIC at the seated viewpoint - the
	# mouse is a pure pointer there, never a look control. A view that
	# drifts with the cursor makes every click target swim (field
	# finding, round 2). XR head tracking owns the view in XR only.
	# Gamepad: left stick / d-pad moves focus, A selects, B goes back.
	# D-pad Right is NOT a focus direction: it is the BACK button,
	# with exactly two meanings in the whole app (the player's
	# ruling, 2026-10-22 - no hold gesture exists anywhere). In
	# play it is VPX's own Exit Game binding: the press lands in
	# the editor and the watchdog's close duty brings the room
	# back. Here in the room, a FRESH press of it quits the app to
	# the desktop - the rail EXIT action, on the pad. The left
	# stick still moves focus in all four directions, right
	# included.
	# The press must also be ARMED (baseline-release arming,
	# field forensics 2026-10-22): a watchdog-relaunched room
	# once exited through this very path with no human press -
	# its controller reconnected mid-relaunch and the button
	# read pressed as the fresh instance polled, manufacturing
	# an edge out of _joy_prev_right's initial false. The exit
	# may fire only on a press edge that occurs AFTER this room
	# instance has observed the button released at least once.
	# A button pressed at the instance's first poll - stuck,
	# reconnect transient, still held from the game - can never
	# fire it, no matter how long it sits pressed; once a
	# released poll is witnessed, fresh presses work at once.
	# During the load wait the room is deaf (see begin_launch): the
	# poll still tracks button state - so a press held through the
	# settle can't resurface as a phantom edge afterwards - but it
	# moves no focus, activates nothing, and escapes nothing. On
	# the SETUP placard the press also does nothing: BACK is the
	# only way off the placard.
	# The loading marquee animates on this same per-frame beat.
	if _marquee_up:
		_update_marquee(delta)
	_update_pop(delta)
	_update_slide(delta)
	var deaf: bool = _launching_game_id != ""
	_joy_cooldown = maxf(0.0, _joy_cooldown - delta)
	var ax: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ay: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var dir: Vector2 = Vector2.ZERO
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT) or ax < -0.55:
		dir = Vector2(-1.0, 0.0)
	elif ax > 0.55:
		dir = Vector2(1.0, 0.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP) or ay < -0.55:
		dir = Vector2(0.0, -1.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN) or ay > 0.55:
		dir = Vector2(0.0, 1.0)
	if dir != Vector2.ZERO and _joy_cooldown <= 0.0:
		if not deaf:
			_move_focus(dir)
		_joy_cooldown = 0.24
	var a_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if a_now and not _joy_prev_a and _focused != null and not deaf:
		_activate(_focused)
	_joy_prev_a = a_now
	var b_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	if b_now and not _joy_prev_b and _mode == "detail" and not deaf:
		_detail.handle_escape()
	_joy_prev_b = b_now
	# Bumpers (LB/RB): page travel, the section slide (Chris's
	# banked note, 2026-10-23; his clarification, 2026-10-24:
	# "my intention for bumpers was for the entire section to
	# shift left or right, one page to other"). One page per
	# fresh press - edge only, no held repeat - and the gating
	# (load wait, placard, detail view) lives in _bumper_page.
	# The prev-state updates run even while gated, so a bumper
	# held through a gated stretch can't resurface as a phantom
	# edge on the other side.
	var lb_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	var rb_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	if lb_now and not _joy_prev_lb:
		_bumper_page(-1)
	elif rb_now and not _joy_prev_rb:
		_bumper_page(1)
	_joy_prev_lb = lb_now
	_joy_prev_rb = rb_now
	var right_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT)
	if not right_now:
		_joy_right_armed = true ## a witnessed released poll: fresh press edges count from here on
	if right_now and not _joy_prev_right and _joy_right_armed and not deaf and not _placard_up:
		_handle_rail("exit")
	_joy_prev_right = right_now


func _cycle_focus(step: int) -> void:
	if _focusables.is_empty():
		return
	var idx: int = _focusables.find(_focused)
	idx = (idx + step) % _focusables.size()
	_set_focused(_focusables[idx])


## The control rail's focus stops in their left-to-right build
## order (see _build_rail's defs). page_label builds too but is
## not pickable, so it is not a stop. Sideways travel along the
## rail walks THIS order and nothing else.
const RAIL_FOCUS_ORDER: Array[String] = [
	"filter:all", "filter:vr", "filter:favorites", "filter:recents",
	"sort", "page_prev", "page_next", "desk", "exit",
]


func _is_rail_quad(q: ClickableQuad) -> bool:
	return q != null and _rail_quads.values().has(q)


## The next focus stop along the rail from the focused quad, in
## RAIL_FOCUS_ORDER, skipping stops that are not focusable right
## now. Null at the rail's end - focus stays put there.
func _rail_focus_neighbour(step: int) -> ClickableQuad:
	if _focused == null:
		return null
	var idx: int = -1
	for i: int in range(RAIL_FOCUS_ORDER.size()):
		var cand: ClickableQuad = _rail_quads.get(RAIL_FOCUS_ORDER[i]) as ClickableQuad
		if cand != null and cand == _focused:
			idx = i
			break
	if idx < 0:
		return null
	var j: int = idx + step
	while j >= 0 and j < RAIL_FOCUS_ORDER.size():
		var q: ClickableQuad = _rail_quads.get(RAIL_FOCUS_ORDER[j]) as ClickableQuad
		if q != null and q.pick_enabled and _focusables.has(q):
			return q
		j += step
	return null


func _move_focus(dir: Vector2) -> void:
	if _focusables.is_empty():
		return
	if _focused == null or not _focusables.has(_focused):
		_set_focused(_focusables[0])
		return
	# The rail is its own navigation country (Chris's field
	# report, 2026-10-24): a sideways step along the control rail
	# used to be scored against every quad in the room, and the
	# nearest "sideways" quad was as often a bottom-row card as
	# the next placard - filter, up to a title, next filter, up
	# to a title. Sideways travel with the rail focused walks
	# the rail's own order; the card grid is entered from the
	# rail only by stepping UP, and DOWN from the grid's bottom
	# row returns to the rail. A sideways step anywhere else
	# never lands on the rail either.
	var horizontal: bool = absf(dir.x) > 0.5
	if horizontal and _is_rail_quad(_focused):
		var step: int = 1 if dir.x > 0.0 else -1
		var nq: ClickableQuad = _rail_focus_neighbour(step)
		if nq != null:
			_set_focused(nq)
		return
	var cam: Camera3D = _active_camera()
	if cam == null:
		return
	var from: Vector2 = cam.unproject_position(_focused.global_position)
	var focused_rail: bool = _is_rail_quad(_focused)
	var best: ClickableQuad = null
	var best_score: float = INF
	for q: ClickableQuad in _focusables:
		if q == _focused or not q.pick_enabled:
			continue
		if horizontal and _is_rail_quad(q) != focused_rail:
			continue ## a sideways step never crosses between rail and wall
		var p: Vector2 = cam.unproject_position(q.global_position)
		var delta_v: Vector2 = p - from
		if delta_v.length() < 4.0:
			continue
		if delta_v.dot(dir) <= 2.0:
			continue
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var score: float = delta_v.length() + absf(delta_v.dot(perp)) * 2.0
		if score < best_score:
			best_score = score
			best = q
	if best != null:
		_set_focused(best)
