class_name RoomView
extends Node3D

## The room: a seated-first curved wall of table panels, a control rail,
## and the detail view. One input model for every hand: the PointerRig
## (VR laser / mouse ray) plus gamepad-and-keyboard focus navigation
## over the same set of ClickableQuads.

signal setup_requested

const PAGE_COLS: int = 4
const PAGE_ROWS: int = 3
const PAGE_SIZE: int = PAGE_COLS * PAGE_ROWS
const WALL_RADIUS: float = 3.05
const EYE: Vector3 = Vector3(0.0, 1.25, 0.0)
const FILTERS: Array[String] = ["all", "vr", "favorites", "recents"]
const FILTER_LABELS: Dictionary = {"all": "ALL", "vr": "VR", "favorites": "FAVORITES", "recents": "RECENTS"}
const SORTS: Array[String] = ["name", "year", "manufacturer", "designer"]
const SORT_LABELS: Dictionary = {"name": "NAME", "year": "YEAR", "manufacturer": "MAKER", "designer": "DESIGNER"}

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
var _desk_camera: Camera3D
var _panels: Array[ClickableQuad] = []
var _rail_quads: Dictionary = {} ## key -> ClickableQuad
var _focusables: Array[ClickableQuad] = []
var _focused: ClickableQuad = null
var _joy_cooldown: float = 0.0
var _joy_prev_a: bool = false
var _joy_prev_b: bool = false


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
	refresh_library()


func refresh_library() -> void:
	_recompute_visible()
	_page = 0
	_rebuild_wall()


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
	var desk_rig: Node3D = Node3D.new()
	desk_rig.position = EYE
	add_child(desk_rig)
	_desk_camera = Camera3D.new()
	_desk_camera.fov = 70.0
	_desk_camera.current = not _xr_enabled
	desk_rig.add_child(_desk_camera)
	_rig = PointerRig.new()
	add_child(_rig)
	_rig.xr_active = _xr_enabled
	_rig.mouse_camera = _desk_camera
	_rig.setup_controllers(origin)
	_rig.hover_changed.connect(_on_hover_changed)
	_rig.select_pressed.connect(_on_select)


func _active_camera() -> Camera3D:
	return _xr_camera if _xr_enabled else _desk_camera


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
	for child: Node in _wall.get_children():
		_wall.remove_child(child)
		child.queue_free()
	for child: Node in _rail.get_children():
		_rail.remove_child(child)
		child.queue_free()
	_panels.clear()
	_rail_quads.clear()
	_set_focused(null)

	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	# Banner: above the eye line (~+23 degrees) with clear air between
	# its lower edge and the top row of panels - it sits closer than
	# the wall, so any angular overlap hides the middle panels' tops.
	_banner_quad = _make_quad(_wall, "banner", "", placeholder, Vector2(1.8, 0.46), Vector3(0.0, 2.48, -2.9))
	_banner_quad.pick_enabled = false
	# Panels for this page: rows hugging the eye line (+12 / 0 / -12
	# degrees). Panel height (0.64) stays under the row pitch (0.65) -
	# a taller panel than the pitch makes rows overlap in projection.
	var start: int = _page * PAGE_SIZE
	var row_ys: Array[float] = [1.90, 1.25, 0.60]
	for i: int in range(PAGE_SIZE):
		var idx: int = start + i
		if idx >= _visible_games.size():
			break
		var game: GameEntry = _visible_games[idx]
		var col: int = i % PAGE_COLS
		var row: int = i / PAGE_COLS
		var angle: float = deg_to_rad(float(col - 1) - 0.5) * 14.0
		var pos: Vector3 = Vector3(sin(angle) * WALL_RADIUS, row_ys[row], -cos(angle) * WALL_RADIUS)
		var q: ClickableQuad = _make_quad(_wall, "panel", game.game_id, placeholder, Vector2(0.54, 0.64), pos)
		_panels.append(q)
	# Rail.
	_build_rail(placeholder)
	_refresh_focusables()
	_fill_wall_textures(gen)


func _build_rail(placeholder: Texture2D) -> void:
	# ~22 degrees below the eye line and far enough out that the full
	# rail width sits inside a 16:9 frustum (it was clipped at the
	# bottom edge of the flat view when it hugged the player).
	var y: float = 0.55
	var z: float = -1.75
	var defs: Array = [
		["filter:all", 0.32], ["filter:vr", 0.26], ["filter:favorites", 0.46], ["filter:recents", 0.42],
		["sort", 0.56], ["page_prev", 0.2], ["page_label", 0.3], ["page_next", 0.2], ["desk", 0.34],
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


func _fill_wall_textures(gen: int) -> void:
	# Banner first: it carries the library summary line.
	var line: String = "%d files - %d games - filter %s - sort %s" % [
		_scanner.total_files, _scanner.games.size(),
		str(FILTER_LABELS[_filter]), str(SORT_LABELS[_sort])]
	if _filter_note != "":
		line += " - " + _filter_note
	var banner_tex: Texture2D = await _factory.render_texture(RoomSpecs.banner_spec(line), Vector2i(1024, 262))
	if gen != _gen or _banner_quad == null:
		return
	_banner_quad.set_texture(banner_tex)
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
	# Rail buttons.
	for key: Variant in _rail_quads.keys():
		var k: String = str(key)
		var quad: ClickableQuad = _rail_quads[k]
		var label: String = ""
		var accent: bool = false
		if k.begins_with("filter:"):
			var f: String = k.trim_prefix("filter:")
			label = str(FILTER_LABELS[f])
			accent = f == _filter
		elif k == "sort":
			label = "SORT: " + str(SORT_LABELS[_sort])
		elif k == "page_prev":
			label = "<"
		elif k == "page_next":
			label = ">"
		elif k == "page_label":
			label = "%d / %d" % [_page + 1, page_count()]
		elif k == "desk":
			label = "SETUP"
		var btex: Texture2D = await _factory.render_texture(RoomSpecs.button_spec(label, accent), Vector2i(512, 150))
		if gen != _gen:
			return
		quad.set_texture(btex)
	if gen == _gen:
		wall_ready = true


# ------------------------------------------------------------ interaction

func _refresh_focusables() -> void:
	_focusables.clear()
	if _mode == "detail" and _detail != null:
		_focusables = _detail.get_clickables()
	else:
		for q: ClickableQuad in _panels:
			_focusables.append(q)
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
	for k: Variant in _rail_quads.keys():
		all.append(_rail_quads[k])
	if _detail != null:
		all.append_array(_detail.get_clickables())
	if _banner_quad != null:
		all.append(_banner_quad)
	for q: ClickableQuad in all:
		q.set_visual_state(q == hovered, q == _focused)


func _on_hover_changed(_quad: ClickableQuad) -> void:
	_refresh_quad_states()


func _on_select(quad: ClickableQuad) -> void:
	if quad == null or not quad.pick_enabled:
		return
	_activate(quad)


func _activate(quad: ClickableQuad) -> void:
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
		"rail":
			quad.pulse()
			_handle_rail(quad.payload)


func _handle_rail(key: String) -> void:
	if key.begins_with("filter:"):
		_filter = key.trim_prefix("filter:")
		_page = 0
		_recompute_visible()
		_rebuild_wall()
	elif key == "sort":
		var idx: int = SORTS.find(_sort)
		_sort = SORTS[(idx + 1) % SORTS.size()]
		_page = 0
		_recompute_visible()
		_rebuild_wall()
	elif key == "page_prev":
		if _page > 0:
			_page -= 1
			_rebuild_wall()
	elif key == "page_next":
		if _page < page_count() - 1:
			_page += 1
			_rebuild_wall()
	elif key == "desk":
		setup_requested.emit()


func _open_detail(game: GameEntry) -> void:
	_mode = "detail"
	_store.touch_recent(game.game_id)
	_store.save_to_disk()
	for q: ClickableQuad in _panels:
		q.pick_enabled = false
	for k: Variant in _rail_quads.keys():
		_rail_quads[k].pick_enabled = false
	_detail.show_game(game)
	_set_focused(null)
	_refresh_focusables()


func _on_detail_closed() -> void:
	_mode = "wall"
	# Favorites / recents may have changed in detail: rebuild the wall.
	_recompute_visible()
	_rebuild_wall()


func _unhandled_input(event: InputEvent) -> void:
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
	_joy_cooldown = maxf(0.0, _joy_cooldown - delta)
	var ax: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ay: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var dir: Vector2 = Vector2.ZERO
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT) or ax < -0.55:
		dir = Vector2(-1.0, 0.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT) or ax > 0.55:
		dir = Vector2(1.0, 0.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP) or ay < -0.55:
		dir = Vector2(0.0, -1.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN) or ay > 0.55:
		dir = Vector2(0.0, 1.0)
	if dir != Vector2.ZERO and _joy_cooldown <= 0.0:
		_move_focus(dir)
		_joy_cooldown = 0.24
	var a_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if a_now and not _joy_prev_a and _focused != null:
		_activate(_focused)
	_joy_prev_a = a_now
	var b_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	if b_now and not _joy_prev_b and _mode == "detail":
		_detail.handle_escape()
	_joy_prev_b = b_now


func _cycle_focus(step: int) -> void:
	if _focusables.is_empty():
		return
	var idx: int = _focusables.find(_focused)
	idx = (idx + step) % _focusables.size()
	_set_focused(_focusables[idx])


func _move_focus(dir: Vector2) -> void:
	if _focusables.is_empty():
		return
	if _focused == null or not _focusables.has(_focused):
		_set_focused(_focusables[0])
		return
	var cam: Camera3D = _active_camera()
	if cam == null:
		return
	var from: Vector2 = cam.unproject_position(_focused.global_position)
	var best: ClickableQuad = null
	var best_score: float = INF
	for q: ClickableQuad in _focusables:
		if q == _focused or not q.pick_enabled:
			continue
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
