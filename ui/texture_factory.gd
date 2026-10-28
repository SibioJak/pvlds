class_name TextureFactory
extends Node

## Renders CardFace specs to textures through one shared SubViewport.
## Renders SERIALIZE inside the factory (a queue, below): the
## viewport and its CardFace are shared state, so two renders in
## flight at once cross their captures - the second caller's spec
## overwrites the first's before its frame is captured, and the
## first caller walks away wearing the second's texture (or a
## blank one). That is exactly how a scan landing once dressed
## the wall's banner in the SETUP panel's face, a wall card in
## the panel's BACK button, and a panel button in nothing at all
## (Chris's after-scan strays, 2026-10-25). Callers just call;
## the queue keeps each capture honest.
## In headless/dummy rendering a capture can come back empty; callers
## always get a usable texture (a dark solid) rather than null.

var _viewport: SubViewport
var _face: CardFace
var _render_in_flight: bool = false ## the serialization queue's lock: one capture at a time, ever


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 640)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_face = CardFace.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_face)


func render_texture(spec: Dictionary, px_size: Vector2i) -> Texture2D:
	# Wait for the shared viewport to be free, then hold it for
	# the whole capture. The check-and-set is atomic between
	# awaits (GDScript is single-threaded), and a waiter resumes
	# one frame later to re-check - so renders land in call
	# order and no capture ever sees another call's spec.
	while _render_in_flight:
		await get_tree().process_frame
	_render_in_flight = true
	var result: Texture2D = await _render_now(spec, px_size)
	_render_in_flight = false
	return result


## The face's board-layout metrics for the spec it currently
## wears (the smoke's layout probe reads them right after a
## board render, before any other render overwrites the face).
func face_board_metrics() -> Dictionary:
	return _face.board_metrics()


func _render_now(spec: Dictionary, px_size: Vector2i) -> Texture2D:
	_viewport.size = px_size
	_face.apply_spec(spec)
	await get_tree().process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex: Texture2D = _viewport.get_texture()
	if tex == null:
		return make_solid(Color(0.08, 0.08, 0.12))
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return make_solid(Color(0.08, 0.08, 0.12))
	return ImageTexture.create_from_image(img)


static func make_solid(color: Color) -> Texture2D:
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Decoded-art cache (the pick-latency fix, 2026-10-27): a
## wall rebuild used to re-decode and re-downscale every
## panel's art image from disk, every time - the decode is
## a pure function of the file's bytes, so it is cached by
## path and re-verified against the file's mtime + size on
## every call (a replaced file re-decodes; art-cache paths
## are content-stamped besides). Bounded FIFO: a miss is a
## cost, never a wrong image.
static var _art_decode_cache: Dictionary = {} ## path -> [Texture2D, mtime, size]
static var _art_decode_order: Array[String] = []
const ART_DECODE_CACHE_MAX: int = 64


## Loads an image file as a texture, downscaled to a sane VRAM size.
static func load_art_texture(path: String) -> Texture2D:
	var mtime: int = FileAccess.get_modified_time(path)
	var size: int = -1
	var probe: FileAccess = FileAccess.open(path, FileAccess.READ)
	if probe != null:
		size = int(probe.get_length())
		probe.close()
	var hit: Variant = _art_decode_cache.get(path)
	if hit is Array and int(hit[1]) == mtime and int(hit[2]) == size:
		return hit[0] as Texture2D
	var img: Image = Image.new()
	if img.load(path) != OK:
		return null
	if img.get_width() > 1024:
		var ratio: float = 1024.0 / float(img.get_width())
		img.resize(1024, int(float(img.get_height()) * ratio), Image.INTERPOLATE_LANCZOS)
	var tex: Texture2D = ImageTexture.create_from_image(img)
	_art_decode_cache[path] = [tex, mtime, size]
	_art_decode_order.erase(path)
	_art_decode_order.push_back(path)
	while _art_decode_order.size() > ART_DECODE_CACHE_MAX:
		var old: String = _art_decode_order.pop_front()
		_art_decode_cache.erase(old)
	return tex
