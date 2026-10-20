class_name DetailView
extends Node3D

## The detail view: standing at the machine. Big art (or title card),
## the facts, every build listed with CURRENT / DEFAULT chips, a
## favorite toggle, build selection with play-once / make-default, and
## the Play quad - a labeled stub in M1 ("ARMED - M2 WILL LAUNCH").
## Play always targets the default build unless a play-once is armed;
## merely selecting a row never changes the target silently.

signal closed

const MAX_ROWS: int = 6

var _factory: TextureFactory
var _store: StateStore
var _game: GameEntry = null
var _selected_path: String = ""
var _once_path: String = ""
var _gen: int = 0
var _flash_gen: int = 0

var _big_quad: ClickableQuad
var _info_quad: ClickableQuad
var _fav_quad: ClickableQuad
var _play_quad: ClickableQuad
var _back_quad: ClickableQuad
var _once_quad: ClickableQuad
var _mkdef_quad: ClickableQuad
var _rows: Array[ClickableQuad] = []


func setup(factory: TextureFactory, store: StateStore) -> void:
	_factory = factory
	_store = store
	visible = false


func is_open() -> bool:
	return visible and _game != null


func current_game() -> GameEntry:
	return _game


func get_clickables() -> Array[ClickableQuad]:
	var out: Array[ClickableQuad] = []
	if not visible:
		return out
	for q: ClickableQuad in [_big_quad, _info_quad, _fav_quad, _play_quad, _back_quad, _once_quad, _mkdef_quad]:
		if q != null:
			out.append(q)
	for q: ClickableQuad in _rows:
		out.append(q)
	return out


func show_game(game: GameEntry) -> void:
	_game = game
	_selected_path = ""
	_once_path = ""
	var def: TableBuild = game.resolve_default_build(_store)
	if def != null:
		_selected_path = def.file_path
	visible = true
	_gen += 1
	_rebuild()


func hide_view() -> void:
	_gen += 1
	_game = null
	visible = false
	_clear_children()


func handle_escape() -> void:
	if is_open():
		hide_view()
		closed.emit()


func handle(quad: ClickableQuad) -> void:
	if _game == null:
		return
	match quad.action_id:
		"detail_back":
			hide_view()
			closed.emit()
		"detail_fav":
			_store.set_favorite(_game.game_id, not _store.is_favorite(_game.game_id))
			_store.save_to_disk()
			_rebuild()
		"detail_row":
			_selected_path = quad.payload
			_once_path = ""
			_rebuild()
		"detail_once":
			_once_path = _selected_path
			_rebuild()
		"detail_mkdef":
			_store.set_default_build(_game.game_id, _selected_path)
			_store.save_to_disk()
			_once_path = ""
			_rebuild()
		"detail_play":
			quad.pulse()
			_flash_play()


func _effective_target() -> TableBuild:
	if _game == null:
		return null
	if _once_path != "":
		var once: TableBuild = _game.build_by_path(_once_path)
		if once != null:
			return once
	return _game.resolve_default_build(_store)


func _clear_children() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_rows.clear()
	_big_quad = null
	_info_quad = null
	_fav_quad = null
	_play_quad = null
	_back_quad = null
	_once_quad = null
	_mkdef_quad = null


func _rebuild() -> void:
	_clear_children()
	if _game == null:
		return
	var gen: int = _gen
	var game: GameEntry = _game
	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))

	_big_quad = _make_quad("detail_art", "", placeholder, Vector2(0.86, 1.08), Vector3(-0.68, 0.12, 0.0))
	_big_quad.pick_enabled = false
	_info_quad = _make_quad("detail_info", "", placeholder, Vector2(1.08, 0.46), Vector3(0.42, 0.55, 0.0))
	_info_quad.pick_enabled = false
	_fav_quad = _make_quad("detail_fav", "", placeholder, Vector2(0.52, 0.13), Vector3(-0.68, 0.79, 0.01))
	_back_quad = _make_quad("detail_back", "", placeholder, Vector2(0.44, 0.19), Vector3(-0.68, -0.6, 0.0))
	_play_quad = _make_quad("detail_play", "", placeholder, Vector2(1.08, 0.21), Vector3(0.42, -0.6, 0.0))
	_once_quad = _make_quad("detail_once", "", placeholder, Vector2(0.52, 0.14), Vector3(0.16, -0.38, 0.0))
	_mkdef_quad = _make_quad("detail_mkdef", "", placeholder, Vector2(0.52, 0.14), Vector3(0.7, -0.38, 0.0))

	var row_y: float = 0.22
	var shown: int = mini(game.builds.size(), MAX_ROWS)
	for i: int in range(shown):
		var b: TableBuild = game.builds[i]
		var row: ClickableQuad = _make_quad("detail_row", b.file_path, placeholder, Vector2(1.08, 0.145), Vector3(0.42, row_y, 0.0))
		_rows.append(row)
		row_y -= 0.165
	_update_action_visibility()
	_fill_textures(gen, game)


func _make_quad(action: String, payload: String, tex: Texture2D, size: Vector2, pos: Vector3) -> ClickableQuad:
	var q: ClickableQuad = ClickableQuad.new()
	q.setup(action, payload, tex, size)
	q.position = pos
	add_child(q)
	return q


func _update_action_visibility() -> void:
	if _game == null:
		return
	var def: TableBuild = _game.resolve_default_build(_store)
	var def_path: String = def.file_path if def != null else ""
	var show_actions: bool = _selected_path != "" and _selected_path != def_path and _once_path == ""
	if _once_quad != null:
		_once_quad.visible = show_actions
		_once_quad.pick_enabled = show_actions
	if _mkdef_quad != null:
		_mkdef_quad.visible = show_actions
		_mkdef_quad.pick_enabled = show_actions


func _fill_textures(gen: int, game: GameEntry) -> void:
	# Big art or title card (card also covers undecodable art).
	var art_done: bool = false
	if game.art_path != "":
		var art_tex: Texture2D = TextureFactory.load_art_texture(game.art_path)
		if art_tex != null:
			var full_tex: Texture2D = await _factory.render_texture(
				RoomSpecs.art_spec(game, art_tex), Vector2i(640, 800))
			if gen == _gen and _big_quad != null:
				_big_quad.set_texture(full_tex)
				art_done = true
	if not art_done:
		var card_tex: Texture2D = await _factory.render_texture(
			RoomSpecs.panel_spec(game, _store), Vector2i(640, 800))
		if gen == _gen and _big_quad != null:
			_big_quad.set_texture(card_tex)
	if gen != _gen:
		return
	# Info block.
	var info_tex: Texture2D = await _factory.render_texture(RoomSpecs.info_spec(game, _store), Vector2i(1024, 440))
	if gen != _gen:
		return
	_info_quad.set_texture(info_tex)
	# Favorite toggle.
	var fav_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("FAVORITE: ON" if _store.is_favorite(game.game_id) else "FAVORITE: OFF",
			_store.is_favorite(game.game_id)), Vector2i(512, 128))
	if gen != _gen:
		return
	_fav_quad.set_texture(fav_tex)
	# Back + actions.
	_back_quad.set_texture(await _factory.render_texture(RoomSpecs.button_spec("BACK", false), Vector2i(440, 190)))
	if gen != _gen:
		return
	_once_quad.set_texture(await _factory.render_texture(RoomSpecs.button_spec("PLAY THIS ONCE", false), Vector2i(512, 140)))
	if gen != _gen:
		return
	_mkdef_quad.set_texture(await _factory.render_texture(RoomSpecs.button_spec("MAKE DEFAULT", true), Vector2i(512, 140)))
	if gen != _gen:
		return
	# Rows.
	var current: TableBuild = game.current_build()
	var def: TableBuild = game.resolve_default_build(_store)
	for row: ClickableQuad in _rows:
		var b: TableBuild = game.build_by_path(row.payload)
		if b == null:
			continue
		var row_tex: Texture2D = await _factory.render_texture(
			RoomSpecs.row_spec(b, b == current, def != null and b.file_path == def.file_path,
				b.file_path == _selected_path, b.file_path == _once_path),
			Vector2i(1024, 138))
		if gen != _gen:
			return
		row.set_texture(row_tex)
	# Play target.
	_refresh_play_texture(gen)


func _refresh_play_texture(gen: int) -> void:
	var target: TableBuild = _effective_target()
	if target == null:
		return
	var label: String = "PLAY v%s" % target.display_version()
	if _once_path != "":
		label += " (THIS ONCE)"
	else:
		label += " (DEFAULT)"
	var tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec(label + "  -  ARMED", true), Vector2i(1024, 200))
	if gen == _gen and _play_quad != null:
		_play_quad.set_texture(tex)


func _flash_play() -> void:
	var target: TableBuild = _effective_target()
	if target == null:
		return
	_flash_gen += 1
	var gen: int = _flash_gen
	var tex: Texture2D = await _factory.render_texture(
		{"kind": "info", "band_text": "M1 STUB - NOTHING LAUNCHES YET",
			"band": Color(0.55, 0.38, 0.08),
			"title": "ARMED", "title_size": 56,
			"body": "M2 will launch:\n%s" % target.file_name, "body_size": 36},
		Vector2i(1024, 440))
	if gen == _flash_gen and _play_quad != null:
		_play_quad.set_texture(tex)
	await get_tree().create_timer(2.2).timeout
	if gen == _flash_gen:
		_refresh_play_texture(_gen)
