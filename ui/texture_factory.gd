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
	# The face's size is asserted before the spec applies:
	# a spec's layout reads it (a board's band fits itself
	# to the face's width - see CardFace.apply_spec), and
	# the viewport's own resize propagation is a frame
	# later than this call.
	_face.size = Vector2(px_size)
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
	# GRADFIX10 (item 1) introduced this measure-and-correct
	# pass; GRADFIX13 (item 1) convicts its ruler and replaces
	# it. GF10 centred the ink MASS: the spacers centre the
	# content block's BOX on the frame, the block's ink mass
	# sits off its box centre (solid score-row panels below,
	# sparse title/deadline glyphs above), so the pass shifted
	# the whole block until the MASS centred - and parked the
	# visible composition high: on the shipped full board the
	# ink mass measured +0.44% of frame height while the ink
	# EXTENT (the band's top edge to the last row's bottom
	# edge - the composition the eye actually judges) measured
	# -2.41%, over the 2% tolerance, with the void pooled
	# below (Chris's GRADFIX12 field captures: boards riding
	# high, dark slab at the base). The field judges extent,
	# not mass. The pass now measures the ink EXTENT
	# (ink_extent) and shifts the block by the extent's miss;
	# the biased spec carries the bias key, so the pass can
	# never loop, and the face the factory leaves standing
	# wears the corrected spec. The NC seam
	# PVLDS_GF13_NC=inkmass restores the GF10 mass ruler so
	# the extent legs fail against it by name. A spec that
	# asks ("ink_centre": the standing board's, and - since
	# GRADFIX13 item 2 - the card back's) and reserves no
	# footer is corrected, at its own face size.
	if bool(spec.get("ink_centre", false)) and not spec.has("ink_bias_px") \
			and int(spec.get("footer_px", 0)) == 0:
		var ink: Vector2 = ink_centroid(img, Rect2()) \
			if OS.get_environment("PVLDS_GF13_NC") == "inkmass" \
			else ink_extent(img, Rect2())
		if ink.y > 0.0:
			var delta: float = ink.x - float(px_size.y) * 0.5
			if absf(delta) > 1.0:
				var spec2: Dictionary = spec.duplicate()
				spec2["ink_bias_px"] = clampi(int(round(-delta)), -px_size.y / 4, px_size.y / 4)
				return await _render_now(spec2, px_size)
	return ImageTexture.create_from_image(img)


## A rendered board face's content-ink vertical centroid,
## in face pixels (GRADFIX10 item 1; Main's smoke legs and
## this factory's correction pass share the one measure).
## Ink is judged against the face's background, recovered
## per column: every background element on a board face
## (the cover stock, the page's horizontal gradient, the
## spine strips) is constant down a column, so a column's
## modal colour bucket IS its background, and a pixel is
## ink when its colour leaves that bucket (5 bits per
## channel). The footer plinth, when a spec reserves one,
## is furniture, not content: exclude_face_rect cuts it
## out of the measure. Returns Vector2(centroid_y,
## ink_pixels); centroid_y is -1 when no ink was found.
static func ink_centroid(img: Image, exclude_face_rect: Rect2) -> Vector2:
	if img == null or img.is_empty():
		return Vector2(-1.0, 0.0)
	# The measure runs on a half-size nearest-sampled copy
	# (the resize is the engine's C++, the sampling drops
	# three pixels in four): the ruling it feeds is 2% of
	# frame height, and the full-size pass cost ~1 s of
	# main thread per board - enough to break the
	# tournament entry's 500 ms frame-gap budget when the
	# standing boards fill (the GF10 full boot's worst gap
	# was 1406 ms against a sub-500 base). The copy is a
	# duplicate: the caller's image still has a texture to
	# become. Coordinates are mapped back to the source's
	# space before returning.
	var work: Image = img.duplicate() as Image
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	if work.get_height() >= 400:
		work.resize(maxi(1, work.get_width() / 2), work.get_height() / 2, Image.INTERPOLATE_NEAREST)
	var sx: float = float(work.get_width()) / float(img.get_width())
	var sy: float = float(work.get_height()) / float(img.get_height())
	exclude_face_rect = Rect2(exclude_face_rect.position * Vector2(sx, sy),
		exclude_face_rect.size * Vector2(sx, sy))
	var w: int = work.get_width()
	var h: int = work.get_height()
	var data: PackedByteArray = work.get_data()
	var bg_bucket: Array[int] = []
	bg_bucket.resize(w)
	for x: int in range(w):
		var counts: Dictionary = {}
		var best_key: int = -1
		var best_n: int = -1
		for y: int in range(h):
			var o: int = (y * w + x) * 4
			var key: int = ((int(data[o]) >> 3) << 10) | ((int(data[o + 1]) >> 3) << 5) | (int(data[o + 2]) >> 3)
			var n: int = int(counts.get(key, 0)) + 1
			counts[key] = n
			if n > best_n:
				best_n = n
				best_key = key
		bg_bucket[x] = best_key
	var has_ex: bool = exclude_face_rect.size.x > 0.0 and exclude_face_rect.size.y > 0.0
	var ex_x0: int = int(floor(exclude_face_rect.position.x))
	var ex_y0: int = int(floor(exclude_face_rect.position.y))
	var ex_x1: int = int(ceil(exclude_face_rect.end.x))
	var ex_y1: int = int(ceil(exclude_face_rect.end.y))
	var sum_y: float = 0.0
	var ink_n: int = 0
	for y2: int in range(h):
		for x2: int in range(w):
			if has_ex and x2 >= ex_x0 and x2 < ex_x1 and y2 >= ex_y0 and y2 < ex_y1:
				continue
			var o2: int = (y2 * w + x2) * 4
			var key2: int = ((int(data[o2]) >> 3) << 10) | ((int(data[o2 + 1]) >> 3) << 5) | (int(data[o2 + 2]) >> 3)
			if key2 != bg_bucket[x2]:
				sum_y += float(y2) + 0.5
				ink_n += 1
	if ink_n <= 0:
		return Vector2(-1.0, 0.0)
	return Vector2((sum_y / float(ink_n)) / sy, float(ink_n))


## A rendered board face's content-ink EXTENT centre, in
## face pixels (GRADFIX13 item 1 - the ruler that replaced
## GRADFIX10's ink-mass centroid above): the midpoint of
## the first and last ink rows, ink judged exactly as
## ink_centroid judges it (a pixel whose colour leaves its
## column's modal background bucket). The eye reads a
## composition by its edges - the band's top, the last
## row's bottom - not by where its mass pools, and the
## score rows' solid panels pool the mass low: on the
## shipped full board mass and extent disagreed by 27 px.
## The face's outer 12 px rows are excluded (the cover
## border and the page inset live there; content never
## legitimately does - the face's own margins start at
## 14 px), and a row counts as ink only with at least 4
## sampled ink pixels on it, so a stray spine-column or
## antialiasing row cannot set the edge. The footer
## plinth, when a spec reserves one, is furniture, not
## content: exclude_face_rect cuts it out, as the centroid
## measure does. Returns Vector2(centre_y, ink_pixels);
## centre_y is -1 when no ink was found.
static func ink_extent(img: Image, exclude_face_rect: Rect2) -> Vector2:
	if img == null or img.is_empty():
		return Vector2(-1.0, 0.0)
	var work: Image = img.duplicate() as Image
	if work.get_format() != Image.FORMAT_RGBA8:
		work.convert(Image.FORMAT_RGBA8)
	if work.get_height() >= 400:
		work.resize(maxi(1, work.get_width() / 2), work.get_height() / 2, Image.INTERPOLATE_NEAREST)
	var sx: float = float(work.get_width()) / float(img.get_width())
	var sy: float = float(work.get_height()) / float(img.get_height())
	exclude_face_rect = Rect2(exclude_face_rect.position * Vector2(sx, sy),
		exclude_face_rect.size * Vector2(sx, sy))
	var w: int = work.get_width()
	var h: int = work.get_height()
	var data: PackedByteArray = work.get_data()
	var bg_bucket: Array[int] = []
	bg_bucket.resize(w)
	for x: int in range(w):
		var counts: Dictionary = {}
		var best_key: int = -1
		var best_n: int = -1
		for y: int in range(h):
			var o: int = (y * w + x) * 4
			var key: int = ((int(data[o]) >> 3) << 10) | ((int(data[o + 1]) >> 3) << 5) | (int(data[o + 2]) >> 3)
			var n: int = int(counts.get(key, 0)) + 1
			counts[key] = n
			if n > best_n:
				best_n = n
				best_key = key
		bg_bucket[x] = best_key
	var has_ex: bool = exclude_face_rect.size.x > 0.0 and exclude_face_rect.size.y > 0.0
	var ex_x0: int = int(floor(exclude_face_rect.position.x))
	var ex_y0: int = int(floor(exclude_face_rect.position.y))
	var ex_x1: int = int(ceil(exclude_face_rect.end.x))
	var ex_y1: int = int(ceil(exclude_face_rect.end.y))
	var edge: int = maxi(1, int(round(12.0 * sy)))
	var first_row: int = -1
	var last_row: int = -1
	var ink_n: int = 0
	for y2: int in range(edge, maxi(edge, h - edge)):
		var row_ink: int = 0
		for x2: int in range(w):
			if has_ex and x2 >= ex_x0 and x2 < ex_x1 and y2 >= ex_y0 and y2 < ex_y1:
				continue
			var o2: int = (y2 * w + x2) * 4
			var key2: int = ((int(data[o2]) >> 3) << 10) | ((int(data[o2 + 1]) >> 3) << 5) | (int(data[o2 + 2]) >> 3)
			if key2 != bg_bucket[x2]:
				row_ink += 1
		ink_n += row_ink
		if row_ink >= 4:
			if first_row < 0:
				first_row = y2
			last_row = y2
	if first_row < 0 or ink_n <= 0:
		return Vector2(-1.0, 0.0)
	return Vector2((float(first_row + last_row + 1) * 0.5) / sy, float(ink_n))


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
