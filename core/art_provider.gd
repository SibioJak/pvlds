class_name ArtProvider
extends RefCounted

## Resolves a display image for a table file. Order:
##   1. an image sitting beside the .vpx with the same stem
##      (.png / .jpg / .jpeg / .webp)
##   2. the backglass image extracted from a same-stem .directb2s file,
##      cached under user:// - extraction is best-effort and any
##      failure just falls through to the generated title card.
## Returns "" when no art exists. Never writes anywhere near the tables.
##
## The extraction targets the format as the B2S backglass server
## (the format's reference reader, github.com/vpinball/b2s-backglass)
## defines it: under the DirectB2SData root, Images/BackglassImage
## carries the backglass as base64 in its Value attribute; on/off
## pairs (BackglassOffImage + BackglassOnImage) replace it in
## dual-image files; Images/DMDImage is the DMD art. Only if none of
## those yield a decodable image does the extractor fall back to the
## largest image-magic blob anywhere in the file (reel/illumination
## art included - some art beats a title card). Image bytes are
## decoded with the format-specific buffer loaders (PNG/JPEG/BMP/
## WebP/TGA), the formats the designer's ImageConverter embeds -
## not PNG/JPEG only as the first extractor had it.
##
## Cache discipline (the art-speed round): a cache entry is keyed by
## the .directb2s path PLUS its size and modified time, so replacing
## a backglass invalidates its cached image instead of serving the
## stale one forever. Extracted images are stored at panel size
## (fit inside PANEL_ART_MAX_W x PANEL_ART_MAX_H - the wall panel's
## texture is 512x640 and the art rect covers it), so a warm panel
## is a small file read, not a multi-megapixel decode + downscale.
## Extractions are claimed (claim_extract) so the background warmer
## and a panel's on-demand ensure_art can never extract the same
## file twice.
##
## Outcome index (the diagnostic round): every extraction's result
## is recorded in user://art_cache/art_index.json under the same
## stamp as the cache entry:
##   ok       - an image was extracted (or a warm cache hit served)
##   no_image - the file read and parsed, but holds no usable image
##   failed   - the file could not be read/decoded, or its
##              designated backglass image would not decode, or the
##              cache write failed
## A stamped negative is REMEMBERED: panels and the warmer skip the
## file entirely until its stamp changes (the file was replaced),
## so a no-art table costs zero extraction work on every later page
## visit. The index is also the desk's art-health telemetry: exact
## ok / no-image / failed counts for the current library, readable
## after the fact without extracting anything.
##
## Extractor version (EXTRACTOR_VERSION): every index entry carries
## the version of the extractor that wrote it. Entries written by an
## OLDER extractor count as untried everywhere the index is
## consulted, so a fixed reader re-attempts every file the old
## reader stamped - once, under the new version. That is how the
## entity-escaped backglasses (see _xml_unescape) got their retry:
## v1 stamped them "failed"; v2 reads them.

const CACHE_DIR: String = "user://art_cache"
const INDEX_PATH: String = CACHE_DIR + "/art_index.json"
const IMAGE_EXTS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const PANEL_ART_MAX_W: int = 512
const PANEL_ART_MAX_H: int = 640

const STATUS_OK: String = "ok"
const STATUS_NO_IMAGE: String = "no_image"
const STATUS_FAILED: String = "failed"

## The extractor's format version, stamped into every outcome-index
## entry as "v". v1: the original reader (no unescaping - it
## refused entity-escaped backglass payloads whole). v2: attribute
## values are XML-unescaped before decoding. Bump this whenever the
## reader learns to read something a previous version stamped
## negatively; older entries then count as untried and are retried
## once under the new reader.
const EXTRACTOR_VERSION: int = 2

## Designated image elements, in the server's own precedence: the
## plain backglass; the lit half of an on/off pair; the dark half;
## the DMD art (better than a title card).
const DESIGNATED_ELEMENTS: Array[String] = [
	"BackglassImage", "BackglassOnImage", "BackglassOffImage", "DMDImage",
]

static var _claims_mutex: Mutex = Mutex.new()
static var _claims: Dictionary = {}
static var _index_mutex: Mutex = Mutex.new()
static var _index: Dictionary = {}
static var _index_loaded: bool = false


static func find_side_image(vpx_path: String) -> String:
	var stem: String = vpx_path.get_basename()
	for ext: String in IMAGE_EXTS:
		var candidate: String = stem + "." + ext
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


static func find_directb2s(vpx_path: String) -> String:
	var candidate: String = vpx_path.get_basename() + ".directb2s"
	if FileAccess.file_exists(candidate):
		return candidate
	return ""


static func resolve_art(vpx_path: String) -> String:
	var side: String = find_side_image(vpx_path)
	if side != "":
		return side
	var b2s: String = find_directb2s(vpx_path)
	if b2s == "":
		return ""
	return extract_directb2s_image(b2s)


## The stamp a .directb2s currently maps to: its path plus size and
## modified time. A replaced backglass maps to a fresh stamp - a
## fresh cache entry AND a fresh (unknown) outcome.
static func stamp_key_for(b2s_path: String) -> String:
	var size: int = 0
	var f: FileAccess = FileAccess.open(b2s_path, FileAccess.READ)
	if f != null:
		size = int(f.get_length())
		f.close()
	var mtime: int = int(FileAccess.get_modified_time(b2s_path))
	return ("%s|%d|%d" % [b2s_path, size, mtime]).md5_text()


static func cache_path_for(b2s_path: String) -> String:
	return CACHE_DIR.path_join(stamp_key_for(b2s_path) + ".png")


static func is_cached(b2s_path: String) -> bool:
	return FileAccess.file_exists(cache_path_for(b2s_path))


## The recorded extraction outcome for the file's CURRENT stamp:
## STATUS_OK / STATUS_NO_IMAGE / STATUS_FAILED, or "" when this
## exact file version has never been extracted. An entry written by
## an older extractor version also reads "" (untried): the index is
## only consulted through here - panels, the warmer, art health -
## so this one gate gives every stale stamp its one retry under the
## current reader.
static func outcome_for(b2s_path: String) -> String:
	_index_mutex.lock()
	_load_index_locked()
	var entry: Variant = _index.get(stamp_key_for(b2s_path), null)
	_index_mutex.unlock()
	if entry is Dictionary:
		var d: Dictionary = entry as Dictionary
		if int(d.get("v", 1)) < EXTRACTOR_VERSION:
			return ""
		return str(d.get("status", ""))
	return ""


static func is_negative_outcome(status: String) -> bool:
	return status == STATUS_NO_IMAGE or status == STATUS_FAILED


static func _record_outcome(b2s_path: String, status: String) -> void:
	var key: String = stamp_key_for(b2s_path)
	_index_mutex.lock()
	_load_index_locked()
	var entry: Variant = _index.get(key, null)
	# The same-status shortcut must ALSO require a current version:
	# a v1 entry re-recorded by the v2 reader has to gain its "v",
	# or it would read as untried forever and be retried every pass.
	if entry is Dictionary:
		var d: Dictionary = entry as Dictionary
		if str(d.get("status", "")) == status and int(d.get("v", 1)) >= EXTRACTOR_VERSION:
			_index_mutex.unlock()
			return
	_index[key] = {"status": status, "src": b2s_path, "v": EXTRACTOR_VERSION}
	_save_index_locked()
	_index_mutex.unlock()


## Drop the in-memory index copy and re-read it from disk. The
## core-test migration case uses this to plant a pre-version index
## file; nothing in the running app needs it (the index is written
## only through _record_outcome, under the mutex).
static func reload_index() -> void:
	_index_mutex.lock()
	_index_loaded = false
	_index = {}
	_load_index_locked()
	_index_mutex.unlock()


## Caller holds _index_mutex.
static func _load_index_locked() -> void:
	if _index_loaded:
		return
	_index_loaded = true
	_index = {}
	var text: String = FileAccess.get_file_as_string(INDEX_PATH)
	if text == "":
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_index = parsed as Dictionary


## Caller holds _index_mutex.
static func _save_index_locked() -> void:
	_ensure_cache_dir()
	var f: FileAccess = FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_index))
	f.close()


## Claim the extraction of one file. Whoever holds the claim extracts;
## everyone else skips (warmer) or joins the wait (a visible panel).
static func claim_extract(b2s_path: String) -> bool:
	_claims_mutex.lock()
	var held: bool = _claims.has(b2s_path)
	if not held:
		_claims[b2s_path] = true
	_claims_mutex.unlock()
	return not held


static func release_extract(b2s_path: String) -> void:
	_claims_mutex.lock()
	_claims.erase(b2s_path)
	_claims_mutex.unlock()


## Wait for another thread's in-flight extraction of this file to
## resolve. Bounded; returns true only when the cache now holds the
## image. Also stops early when the outcome gets RECORDED - a
## negative outcome means no cache entry is coming.
static func await_extract(b2s_path: String, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if is_cached(b2s_path):
			return true
		if outcome_for(b2s_path) != "":
			return false
		_claims_mutex.lock()
		var held: bool = _claims.has(b2s_path)
		_claims_mutex.unlock()
		if not held:
			return is_cached(b2s_path)
		OS.delay_msec(5)
	return is_cached(b2s_path)


## Delete cached images that no current source maps to (stale stamps
## from replaced backglasses, pre-stamp path-only entries), and drop
## outcome-index entries for stamps no current source maps to.
static func prune_cache(keep_paths: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(CACHE_DIR)
	if dir != null:
		for name: String in dir.get_files():
			if not name.ends_with(".png"):
				continue
			if not keep_paths.has(CACHE_DIR.path_join(name)):
				dir.remove(name)
	_index_mutex.lock()
	_load_index_locked()
	var changed: bool = false
	var keys: Array = _index.keys()
	for key: Variant in keys:
		if not keep_paths.has(CACHE_DIR.path_join(str(key) + ".png")):
			_index.erase(key)
			changed = true
	if changed:
		_save_index_locked()
	_index_mutex.unlock()


static func extract_directb2s_image(b2s_path: String) -> String:
	var cache_path: String = cache_path_for(b2s_path)
	if FileAccess.file_exists(cache_path):
		# Warm hit. Self-heal the index for caches written before
		# the index existed (or after it was pruned).
		if outcome_for(b2s_path) != STATUS_OK:
			_record_outcome(b2s_path, STATUS_OK)
		return cache_path
	var result: Dictionary = _extract_uncached(b2s_path, cache_path)
	_record_outcome(b2s_path, str(result["status"]))
	return str(result["path"])


## One real extraction attempt. Returns {"path", "status"}.
static func _extract_uncached(b2s_path: String, cache_path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(b2s_path)
	if bytes.is_empty():
		return {"path": "", "status": STATUS_FAILED} ## unreadable / empty: a read failure
	var text: String = _decode_xml_text(bytes)
	if text == "":
		return {"path": "", "status": STATUS_FAILED} ## undecodable: a parse failure
	# 1. The designated elements, in the server's precedence. The
	# designated backglass being present but undecodable is data
	# corruption - a failure, not "no image in file".
	var designated_seen: bool = false
	for element: String in DESIGNATED_ELEMENTS:
		for blob: String in _element_value_blobs(text, element):
			designated_seen = true
			var img: Image = _decode_blob_image(blob)
			if img != null:
				return _store_extracted(img, cache_path)
	if designated_seen:
		return {"path": "", "status": STATUS_FAILED}
	# 2. Fallback: any image blob anywhere in the file (reel and
	# illumination art included), largest first. NOTE: this path
	# reads the raw text as-is - it does NOT XML-unescape, so an
	# entity-escaped payload's base64 runs stay broken up by the
	# entity text and are not candidates here. The designated path
	# above is the one that unescapes; a file whose designated
	# image is escaped-but-decodable never reaches this fallback.
	var tried: Dictionary = {}
	for element2: String in DESIGNATED_ELEMENTS:
		for blob2: String in _element_value_blobs(text, element2):
			tried[blob2] = true
	for blob3: String in _base64_candidates(text):
		if tried.has(blob3):
			continue
		var img2: Image = _decode_blob_image(blob3)
		if img2 != null:
			return _store_extracted(img2, cache_path)
	return {"path": "", "status": STATUS_NO_IMAGE}


static func _store_extracted(img: Image, cache_path: String) -> Dictionary:
	_fit_to_panel(img)
	_ensure_cache_dir()
	if img.save_png(cache_path) == OK:
		return {"path": cache_path, "status": STATUS_OK}
	return {"path": "", "status": STATUS_FAILED} ## the cache write failed


## XML text from raw file bytes, tolerant of the encodings the
## designer writes: UTF-8 normally, UTF-16LE in some files (with or
## without a BOM). A UTF-16 file read as UTF-8 is NUL-interleaved
## garbage in which no tag search can find anything - one of the
## real-data failure shapes this guards.
static func _decode_xml_text(bytes: PackedByteArray) -> String:
	if bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xFE:
		return bytes.get_string_from_utf16()
	if bytes.size() >= 4 and bytes[1] == 0 and bytes[3] == 0:
		return bytes.get_string_from_utf16()
	return bytes.get_string_from_utf8()


## The Value attribute payloads of every <element ...> tag in the
## text. Tag-scoped (the tag runs to its closing '>'), so attribute
## order inside the tag does not matter and a neighbouring
## element's payload is never picked up.
static func _element_value_blobs(text: String, element: String) -> Array[String]:
	var out: Array[String] = []
	var needle: String = "<" + element
	var from: int = 0
	while true:
		var at: int = text.find(needle, from)
		if at < 0:
			return out
		var after: int = at + needle.length()
		# The character after the name must end the name (a longer
		# element sharing the prefix is a different element).
		if after < text.length() and (text[after] == " " or text[after] == "\t" or text[after] == "\r" or text[after] == "\n" or text[after] == "/" or text[after] == ">"):
			var close: int = text.find(">", after)
			if close < 0:
				return out
			var tag: String = text.substr(at, close - at)
			var v: int = tag.find("Value=\"")
			if v >= 0:
				var start: int = v + 7
				var end: int = tag.find("\"", start)
				if end > start:
					# Unescape BEFORE the whitespace strip: real
					# designer files store the base64 wrapped at 76
					# characters with each wrap's CRLF written into
					# the attribute as &#xD;&#xA; - what an XML
					# parser hands the B2S server automatically,
					# but this raw-text reader must decode itself.
					# Undecoded, the strict base64 decoder refuses
					# the whole blob and the file stamps "failed".
					var blob: String = _xml_unescape(tag.substr(start, end - start)).replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "")
					if blob.length() >= 100:
						out.append(blob)
			from = close
		else:
			from = after
	return out


## Decode the XML character/entity references in an attribute
## value, the way a real XML parser hands the value to its reader:
## numeric references (&#xHH; hex, &#NN; decimal) and the five
## named entities (&amp; &lt; &gt; &quot; &apos;). Used ONLY on
## base64 attribute payloads, whose alphabet contains no '&' of its
## own - every '&' in one is an entity's start, which is what makes
## the bulk passes below safe here (they would not be safe on
## arbitrary XML text).
static func _xml_unescape(value: String) -> String:
	if not value.contains("&"):
		return value
	var s: String = value
	# Bulk passes first: single sweeps for the shapes the designer
	# actually writes. The overwhelmingly common one is the wrap
	# CRLF - one file can carry 300k+ of them, and a per-entity
	# parse of a 27 MB payload would crawl.
	s = s.replace("&#xD;", "\r").replace("&#xA;", "\n")
	s = s.replace("&#xd;", "\r").replace("&#xa;", "\n")
	s = s.replace("&#13;", "\r").replace("&#10;", "\n")
	s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'")
	if s.contains("&#"):
		s = _xml_unescape_numeric(s)
	# &amp; LAST: an escaped ampersand is data, not another
	# entity's start; decoding it earlier could re-form an entity
	# the source meant as literal text.
	s = s.replace("&amp;", "&")
	return s


## The general numeric-reference pass of _xml_unescape, for any
## reference the bulk passes did not cover (a writer escaping '+'
## as &#43;, say). Scans once, left to right; decoded text is
## never rescanned. Malformed references pass through verbatim.
static func _xml_unescape_numeric(value: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var i: int = 0
	var n: int = value.length()
	while i < n:
		var amp: int = value.find("&#", i)
		if amp < 0:
			parts.append(value.substr(i))
			break
		var semi: int = value.find(";", amp)
		if semi < 0 or semi - amp > 10:
			parts.append(value.substr(i, amp + 2 - i))
			i = amp + 2
			continue
		var body: String = value.substr(amp + 2, semi - amp - 2)
		var code: int = -1
		if body.begins_with("x") or body.begins_with("X"):
			var hex: String = body.substr(1)
			if hex.is_valid_hex_number():
				code = hex.hex_to_int()
		elif body.is_valid_int():
			code = body.to_int()
		if code <= 0 or code > 0x10FFFF:
			parts.append(value.substr(i, semi + 1 - i))
			i = semi + 1
			continue
		parts.append(value.substr(i, amp - i))
		parts.append(char(code))
		i = semi + 1
	return "".join(parts)


## Decode one base64 blob to an Image, or null. Cheap probe first:
## the first 256 base64 characters decode to ~192 bytes - enough
## for the format magic - so a multi-megabyte non-image blob (a
## sound stream, say) never pays a full decode just to be refused.
static func _decode_blob_image(blob: String) -> Image:
	if blob.length() < 100:
		return null
	var probe: PackedByteArray = Marshalls.base64_to_raw(blob.substr(0, 256))
	if probe.size() < 8 or not _has_image_magic(probe):
		return null
	var bytes: PackedByteArray = Marshalls.base64_to_raw(blob)
	if bytes.size() < 8:
		return null
	# The format-specific buffer loaders (Godot 4.7 has no generic
	# load_from_buffer): between them they cover what the designer
	# embeds - PNG and JPEG predominantly, BMP in older files.
	var img: Image = Image.new()
	if img.load_png_from_buffer(bytes) == OK:
		return img
	if img.load_jpg_from_buffer(bytes) == OK:
		return img
	if img.load_bmp_from_buffer(bytes) == OK:
		return img
	if img.load_webp_from_buffer(bytes) == OK:
		return img
	if img.load_tga_from_buffer(bytes) == OK:
		return img
	return null


## Downscale an extracted image to panel size (never upscale). The
## panel's art rect covers a 512x640 texture, so anything larger is
## decode cost every panel would pay again on every page.
static func _fit_to_panel(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w <= PANEL_ART_MAX_W and h <= PANEL_ART_MAX_H:
		return
	var scale: float = minf(float(PANEL_ART_MAX_W) / float(w), float(PANEL_ART_MAX_H) / float(h))
	img.resize(maxi(1, int(round(float(w) * scale))), maxi(1, int(round(float(h) * scale))), Image.INTERPOLATE_LANCZOS)


static func _ensure_cache_dir() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and not dir.dir_exists("art_cache"):
		dir.make_dir("art_cache")


static func _has_image_magic(bytes: PackedByteArray) -> bool:
	# PNG: 89 50 4E 47; JPEG: FF D8; BMP: 42 4D ("BM");
	# WebP: "RIFF" .... "WEBP"; GIF: "GIF8".
	if bytes.size() < 12:
		return bytes.size() >= 2 and bytes[0] == 0x42 and bytes[1] == 0x4D
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return true
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return true
	if bytes[0] == 0x42 and bytes[1] == 0x4D:
		return true
	if bytes[0] == 0x47 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x38:
		return true
	if bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 \
			and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		return true
	return false


## Long base64-looking runs, whitespace-stripped, longest first.
## The fallback path only (the designated elements are tried
## first); the probe in _decode_blob_image keeps non-image runs
## cheap to refuse, so the attempt cap can be generous.
static func _base64_candidates(text: String) -> Array[String]:
	var re: RegEx = RegEx.new()
	if re.compile("[A-Za-z0-9+/= \t\r\n]{2000,}") != OK:
		return []
	var found: Array = []
	for m: Variant in re.search_all(text):
		if m is RegExMatch:
			var rm: RegExMatch = m
			found.append(rm.get_string())
	var cleaned: Array[String] = []
	for raw: Variant in found:
		var s: String = str(raw)
		s = s.replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "")
		if s.length() >= 2000:
			cleaned.append(s)
	cleaned.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var out: Array[String] = []
	var limit: int = mini(8, cleaned.size())
	for i: int in range(limit):
		out.append(cleaned[i])
	return out
