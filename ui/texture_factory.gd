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
var _race_armed: bool = false ## WART smoke seam: poison this render's first capture (see render_texture)

## GRADFIX16 (item 2) art probe: per-operation timing census
## for the travel-hitch conviction, gated by the harness env
## PVLDS_GF16_PROBE (set by Main before any factory exists).
## When off, every note is one branch. When on, each measured
## operation accumulates [count, total_usec, max_usec] in
## probe_stats; the artstream smoke prints the census. The
## probe never changes what any operation does or returns.
static var probe_enabled: bool = false
static var probe_stats: Dictionary = {} ## op -> [count, total_usec, max_usec]
static var _probe_mutex: Mutex = Mutex.new() ## GRADFIX16: decode notes also land from the art pipeline's worker thread


static func probe_note(op: String, usec: int) -> void:
	if not probe_enabled:
		return
	_probe_mutex.lock()
	var row: Array = probe_stats.get(op, [0, 0, 0]) as Array
	row[0] = int(row[0]) + 1
	row[1] = int(row[1]) + usec
	row[2] = maxi(int(row[2]), usec)
	probe_stats[op] = row
	_probe_mutex.unlock()


## The WART content gate (the dark-card wart, reopened
## 2026-11-04): a card-face capture can come back UNPAINTED -
## full-size, but transparent, uniform ground, or uniform
## black - when the capture frame lands before the freshly
## decoded art actually paints (convicted in the field by
## GRADFIX6's pixel census: faces measuring 99%+ exact-black
## while their source art is bright). Every gate the fill and
## the heal apply is key/path/SIZE based, so an unpainted
## capture - being full-size - was cached and key-stamped as
## the card's real face and no mechanism could ever see it
## again; the composed-face cache then preserved it forever.
## The gate is the missing CONTENT test, applied here in the
## factory where the capture is born: card-face specs (kind
## "art" / "panel" - the opaque-ground faces) are re-captured
## up to WART_MAX_CAPTURE_ATTEMPTS times while the capture
## reads unpainted, and a capture that never paints returns
## null - which every caller already treats as "not a face"
## (the room falls through to the styled card and its heal
## retries the art render, bounded; the detail view falls
## through to its title card). Board faces and card backs
## are transparent by design (GRADFIX15's frameless law) and
## are NEVER gated. NC: PVLDS_WART_NC=nogate restores the
## pre-gate behaviour (the first capture stands, whatever it
## holds) so the facecache smoke's wart legs fail by name.
## The smoke seam PVLDS_WART_RACE=1 makes the first capture
## of every gated render come back unpainted - the field
## species, deterministic.
const WART_MAX_CAPTURE_ATTEMPTS: int = 3
static var wart_gate_rejects: int = 0 ## gated captures that read unpainted
static var wart_gate_retries: int = 0 ## re-captures the gate issued
static var wart_gate_nulls: int = 0 ## gated renders that never painted (returned null)
static var wart_race_substituted: int = 0 ## smoke seam: first captures the race poisoned


## Whether a captured card-face image is UNPAINTED: no real
## content ever reached it. Two arms, either suffices:
##   - VOID: fewer than 1% of samples are painted at all
##     (alpha up and some colour present) - the transparent
##     capture, or a capture of nothing.
##   - UNIFORM DARK: the samples form a near-constant dark
##     field (luminance stdev < 0.004, mean < 0.10, and fewer
##     than 1% of samples reaching even 0.16) - the
##     ground-only capture, or uniform black. Genuinely dark
##     ART always carries texture and highlights (lamps,
##     reels, chrome) far past these bounds across a whole
##     face; a raced capture of the flat ground has neither.
## The grid keeps the sample count near a thousand whatever
## the capture size - the test runs inside the render, so it
## must stay cheap (measured ~1 ms at face size).
static func is_unpainted(img: Image) -> bool:
	if img == null or img.is_empty():
		return true
	var w: int = img.get_width()
	var h: int = img.get_height()
	var step: int = maxi(1, mini(w, h) / 24)
	var n: int = 0
	var painted: int = 0
	var bright: int = 0
	var sum: float = 0.0
	var sumsq: float = 0.0
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < w:
			var c: Color = img.get_pixel(x, y)
			var lum: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += lum
			sumsq += lum * lum
			n += 1
			if c.a >= 0.5 and maxf(c.r, maxf(c.g, c.b)) >= 0.03:
				painted += 1
			if lum >= 0.16:
				bright += 1
			x += step
		y += step
	if n == 0:
		return true
	if float(painted) / float(n) < 0.01:
		return true
	var mean: float = sum / float(n)
	var variance: float = maxf(0.0, sumsq / float(n) - mean * mean)
	return sqrt(variance) < 0.004 and mean < 0.10 \
		and float(bright) / float(n) < 0.01


static func probe_reset() -> void:
	_probe_mutex.lock()
	probe_stats.clear()
	_probe_mutex.unlock()


static func probe_snapshot() -> Dictionary:
	_probe_mutex.lock()
	var snap: Dictionary = probe_stats.duplicate()
	_probe_mutex.unlock()
	return snap


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 640)
	# GRADFIX15 (item 1): the capture clears to TRANSPARENT -
	# a board face's texture is its text block on transparency
	# (CardFace's frameless law), and an opaque clear colour
	# would stamp a black field behind it. Every other face
	# kind paints its own full-rect ground over the clear, so
	# their captures are unchanged.
	_viewport.transparent_bg = true
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
	var probe_t0: int = Time.get_ticks_usec() if probe_enabled else 0
	while _render_in_flight:
		await get_tree().process_frame
	if probe_enabled:
		probe_note("render_queue_wait", Time.get_ticks_usec() - probe_t0)
	_render_in_flight = true
	# The WART smoke seam arms here (never set in production):
	# the first capture of a card-face render will come back
	# unpainted - see _render_now's capture tail. It arms
	# OUTSIDE the gate so the NC (gate off) still takes the
	# poison: the negative control must reintroduce the
	# fault, not merely disable the cure.
	var race_kind: String = str(spec.get("kind", ""))
	_race_armed = OS.get_environment("PVLDS_WART_RACE") == "1" \
		and (race_kind == "art" or race_kind == "panel")
	var result: Texture2D = await _render_gated(spec, px_size)
	_race_armed = false
	_render_in_flight = false
	if probe_enabled:
		probe_note("render_total", Time.get_ticks_usec() - probe_t0)
	return result


## One render through the WART content gate (see the gate's
## note at is_unpainted): ungated specs (everything that is
## not a card face, and every spec under the NC) get exactly
## the pre-gate behaviour - one capture, returned as-is.
## Gated card faces re-capture while the capture reads
## unpainted, up to WART_MAX_CAPTURE_ATTEMPTS in total, and
## return null when no capture paints.
func _render_gated(spec: Dictionary, px_size: Vector2i) -> Texture2D:
	var kind: String = str(spec.get("kind", ""))
	var gated: bool = (kind == "art" or kind == "panel") \
		and OS.get_environment("PVLDS_WART_NC") != "nogate"
	if not gated:
		return await _render_now(spec, px_size)
	for attempt: int in range(WART_MAX_CAPTURE_ATTEMPTS):
		var result: Texture2D = await _render_now(spec, px_size)
		if result == null:
			return null
		if not (result is ImageTexture):
			return result
		var img: Image = (result as ImageTexture).get_image()
		if img == null or img.is_empty() or not is_unpainted(img):
			return result
		wart_gate_rejects += 1
		if attempt < WART_MAX_CAPTURE_ATTEMPTS - 1:
			wart_gate_retries += 1
	wart_gate_nulls += 1
	return null


## The face's board-layout metrics for the spec it currently
## wears (the smoke's layout probe reads them right after a
## board render, before any other render overwrites the face).
func face_board_metrics() -> Dictionary:
	return _face.board_metrics()


func _render_now(spec: Dictionary, px_size: Vector2i) -> Texture2D:
	var probe_t: int = Time.get_ticks_usec() if probe_enabled else 0
	_viewport.size = px_size
	# The face's size is asserted before the spec applies:
	# a spec's layout reads it (a board's band fits itself
	# to the face's width - see CardFace.apply_spec), and
	# the viewport's own resize propagation is a frame
	# later than this call.
	_face.size = Vector2(px_size)
	_face.apply_spec(spec)
	if probe_enabled:
		probe_note("render_apply_spec", Time.get_ticks_usec() - probe_t)
		probe_t = Time.get_ticks_usec()
	await get_tree().process_frame
	if probe_enabled:
		probe_note("render_wait_process_frame", Time.get_ticks_usec() - probe_t)
		probe_t = Time.get_ticks_usec()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if probe_enabled:
		probe_note("render_wait_post_draw", Time.get_ticks_usec() - probe_t)
		probe_t = Time.get_ticks_usec()
	var tex: Texture2D = _viewport.get_texture()
	if tex == null:
		return make_solid(Color(0.08, 0.08, 0.12))
	var img: Image = tex.get_image()
	if probe_enabled:
		probe_note("render_readback_get_image", Time.get_ticks_usec() - probe_t)
		probe_t = Time.get_ticks_usec()
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
		if probe_enabled:
			probe_note("render_ink_pass", Time.get_ticks_usec() - probe_t)
			probe_t = Time.get_ticks_usec()
		if ink.y > 0.0:
			var delta: float = ink.x - float(px_size.y) * 0.5
			if absf(delta) > 1.0:
				var spec2: Dictionary = spec.duplicate()
				spec2["ink_bias_px"] = clampi(int(round(-delta)), -px_size.y / 4, px_size.y / 4)
				return await _render_now(spec2, px_size)
	if _race_armed:
		# The smoke seam (never set in production): this
		# render's first capture comes back unpainted,
		# whatever the viewport held - the field species,
		# deterministic. It sits at the capture tail, outside
		# the gate, so the NC (gate off) takes the poison
		# too: the negative control must reintroduce the
		# fault, not merely disable the cure.
		_race_armed = false
		wart_race_substituted += 1
		var blank: Image = Image.create(px_size.x, px_size.y, false, Image.FORMAT_RGBA8)
		blank.fill(Color(0, 0, 0, 1))
		return ImageTexture.create_from_image(blank)
	var created: Texture2D = ImageTexture.create_from_image(img)
	if probe_enabled:
		probe_note("render_create_texture", Time.get_ticks_usec() - probe_t)
	return created


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


## A rendered board face's FRAMELESS census (GRADFIX15
## item 3): every pixel of the face, judged against the
## text block's own part rects (CardFace.board_metrics'
## "part_rects", grown 2 px for antialiasing). A frameless
## face is its text block on transparency, so: visible
## (alpha > 0) pixels INSIDE a part rect are ink/accent;
## visible pixels anywhere else are STRAY - a restored
## panel fill, a spine line, any furniture the nuke killed
## - and the count must be 0. "line_out" narrows strays to
## the former spine-line columns (x 41-43 and x w-44..w-42,
## the hairline's two seats): the grey line's absence,
## measured at its old address. Returns {total, visible,
## transparent, stray, stray_pos, line_out}; a null/empty
## image returns total 0 (the caller fails that by name).
static func frameless_census(img: Image, part_rects: Array) -> Dictionary:
	var out: Dictionary = {"total": 0, "visible": 0, "transparent": 0,
		"stray": 0, "stray_pos": Vector2i(-1, -1), "line_out": 0}
	if img == null or img.is_empty():
		return out
	var work: Image = img
	if work.get_format() != Image.FORMAT_RGBA8:
		work = img.duplicate() as Image
		work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()
	var data: PackedByteArray = work.get_data()
	var rects: Array[Rect2] = []
	for rv: Variant in part_rects:
		if rv is Rect2:
			rects.append((rv as Rect2).grow(2.0))
	var visible_n: int = 0
	var stray_n: int = 0
	var line_n: int = 0
	var stray_pos: Vector2i = Vector2i(-1, -1)
	for y: int in range(h):
		for x: int in range(w):
			if int(data[(y * w + x) * 4 + 3]) == 0:
				continue
			visible_n += 1
			var inside: bool = false
			for r: Rect2 in rects:
				if r.has_point(Vector2(x, y)):
					inside = true
					break
			if not inside:
				stray_n += 1
				if stray_pos.x < 0:
					stray_pos = Vector2i(x, y)
				if (x >= 41 and x <= 43) or (x >= w - 44 and x <= w - 42):
					line_n += 1
	out["total"] = w * h
	out["visible"] = visible_n
	out["transparent"] = w * h - visible_n
	out["stray"] = stray_n
	out["stray_pos"] = stray_pos
	out["line_out"] = line_n
	return out


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
## are content-stamped besides). Bounded: a miss is a
## cost, never a wrong image. FACECACHE round: the
## eviction is an LRU (a verified hit renews the entry -
## under the old store-order FIFO a long session
## re-decoded hot art on schedule) and the cap is reunited
## with the composed-face residency cap (108), so one
## discipline governs both cache tiers.
static var _art_decode_cache: Dictionary = {} ## path -> [Texture2D, mtime, size]
static var _art_decode_order: Array[String] = []
const ART_DECODE_CACHE_MAX: int = 108


## Drop every decoded-art entry (the artstream smoke's
## cold-art reset: a cruise that starts after this call pays
## full decode for every face it has not rendered this pass).
static func clear_art_decode_cache() -> void:
	_art_decode_cache.clear()
	_art_decode_order.clear()


## GRADFIX18 (item B) residency gauge for the decoded-art
## cache: {count, bytes} with bytes estimated from each
## texture's pixel size (w*h*4) - no image data is touched.
## The scroll telemetry samples this at column crossings so a
## cruise spike can be read against what the wall held.
static func art_decode_cache_stats() -> Dictionary:
	var bytes_est: int = 0
	for key: Variant in _art_decode_cache.keys():
		var hit: Variant = _art_decode_cache[key]
		if hit is Array:
			var arr: Array = hit as Array
			if arr.size() > 0 and arr[0] is Texture2D:
				var tex: Texture2D = arr[0] as Texture2D
				bytes_est += tex.get_width() * tex.get_height() * 4
	return {"count": _art_decode_cache.size(), "bytes": bytes_est}


## Whether the decode cache already holds this exact file
## version (the same mtime+size verification load performs).
static func art_decode_is_cached(path: String) -> bool:
	var hit: Variant = _art_decode_cache.get(path)
	if not (hit is Array):
		return false
	var arr: Array = hit as Array
	return int(arr[1]) == FileAccess.get_modified_time(path) \
		and int(arr[2]) == _file_size(path)


static func _file_size(path: String) -> int:
	var probe: FileAccess = FileAccess.open(path, FileAccess.READ)
	if probe == null:
		return -1
	var size: int = int(probe.get_length())
	probe.close()
	return size


## Decode one art file to a downscaled Image - NO texture
## creation, NO cache writes. Worker-thread safe (a pure
## function of the file's bytes): the GRADFIX16 art pipeline
## runs this on a WorkerThreadPool thread so travel frames
## never pay the decode + Lanczos resize the conviction
## measured (~15 ms of synchronous work per cold face).
static func decode_art_image(path: String) -> Image:
	var probe_t: int = Time.get_ticks_usec() if probe_enabled else 0
	var img: Image = Image.new()
	if img.load(path) != OK:
		return null
	if probe_enabled:
		probe_note("decode_image_load", Time.get_ticks_usec() - probe_t)
		probe_t = Time.get_ticks_usec()
	if img.get_width() > 1024:
		var ratio: float = 1024.0 / float(img.get_width())
		img.resize(1024, int(float(img.get_height()) * ratio), Image.INTERPOLATE_LANCZOS)
	if probe_enabled:
		probe_note("decode_resize", Time.get_ticks_usec() - probe_t)
	return img


## Turn a decoded Image into the cached art texture (main
## thread only: ImageTexture creation + the decode cache).
static func art_texture_from_decoded(path: String, img: Image) -> Texture2D:
	if img == null:
		return null
	var probe_t: int = Time.get_ticks_usec() if probe_enabled else 0
	var tex: Texture2D = ImageTexture.create_from_image(img)
	if probe_enabled:
		probe_note("decode_create_texture", Time.get_ticks_usec() - probe_t)
	_store_decoded_texture(path, tex)
	return tex


static func _store_decoded_texture(path: String, tex: Texture2D) -> void:
	_art_decode_cache[path] = [tex, FileAccess.get_modified_time(path), _file_size(path)]
	_art_decode_order.erase(path)
	_art_decode_order.push_back(path)
	while _art_decode_order.size() > ART_DECODE_CACHE_MAX:
		var old: String = _art_decode_order.pop_front()
		_art_decode_cache.erase(old)


## Loads an image file as a texture, downscaled to a sane VRAM size.
static func load_art_texture(path: String) -> Texture2D:
	var probe_total_t: int = Time.get_ticks_usec() if probe_enabled else 0
	var probe_t: int = probe_total_t
	var mtime: int = FileAccess.get_modified_time(path)
	var size: int = _file_size(path)
	var hit: Variant = _art_decode_cache.get(path)
	if hit is Array and int(hit[1]) == mtime and int(hit[2]) == size:
		_art_decode_order.erase(path) ## FACECACHE: an LRU hit renews the entry
		_art_decode_order.push_back(path)
		if probe_enabled:
			probe_note("decode_cache_hit", Time.get_ticks_usec() - probe_t)
		return hit[0] as Texture2D
	var img: Image = decode_art_image(path)
	if img == null:
		return null
	var tex: Texture2D = art_texture_from_decoded(path, img)
	if probe_enabled:
		probe_note("decode_miss_total", Time.get_ticks_usec() - probe_total_t)
	return tex


## GRADFIX18 (stream-ahead): prepare a decoded art Image as a
## FACE-ready image on the caller's thread (the art pipeline's
## background pump): cover-crop to the face's aspect exactly as
## CardFace's art TextureRect does at render time
## (STRETCH_KEEP_ASPECT_COVERED - centre crop of the long axis),
## then resize to the face's pixel size. The result can stand
## on a card as-is: the main thread's only remaining work is
## one ImageTexture creation (~0.3 ms measured on the field
## rig - see art_texture_from_image). Pure Image work, no
## texture creation, no node access: worker-thread safe, like
## decode_art_image.
static func prepare_face_image(img: Image, face_px: Vector2i) -> Image:
	if img == null or img.is_empty() or face_px.x <= 0 or face_px.y <= 0:
		return null
	var work: Image = img.duplicate() as Image
	var target_aspect: float = float(face_px.x) / float(face_px.y)
	var aspect: float = float(work.get_width()) / float(work.get_height())
	if aspect > target_aspect + 0.001:
		var crop_w: int = maxi(1, int(round(float(work.get_height()) * target_aspect)))
		var x0: int = maxi(0, (work.get_width() - crop_w) / 2)
		work = work.get_region(Rect2i(x0, 0, crop_w, work.get_height()))
	elif aspect < target_aspect - 0.001:
		var crop_h: int = maxi(1, int(round(float(work.get_width()) / target_aspect)))
		var y0: int = maxi(0, (work.get_height() - crop_h) / 2)
		work = work.get_region(Rect2i(0, y0, work.get_width(), crop_h))
	if work.get_size() != face_px:
		work.resize(face_px.x, face_px.y, Image.INTERPOLATE_LANCZOS)
	return work


## GRADFIX18 (stream-ahead): create a texture from an already
## face-prepared Image WITHOUT touching the decoded-art cache
## (the prepared image is cropped to the face; the cache's
## contract is the game's full art, which the settle-time
## full render still needs). Main thread only.
static func art_texture_from_image(img: Image) -> Texture2D:
	if img == null or img.is_empty():
		return null
	var probe_t: int = Time.get_ticks_usec() if probe_enabled else 0
	var tex: Texture2D = ImageTexture.create_from_image(img)
	if probe_enabled:
		probe_note("stream_create_texture", Time.get_ticks_usec() - probe_t)
	return tex
