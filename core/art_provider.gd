class_name ArtProvider
extends RefCounted

## Resolves a display image for a table file. Order:
##   1. an image sitting beside the .vpx with the same stem
##      (.png / .jpg / .jpeg / .webp)
##   2. the backglass image extracted from a same-stem .directb2s file
##   3. an image extracted from inside the .vpx file itself (its
##      OLE/CFB storage holds the table's embedded images as BIFF
##      records - see _walk_vpx_image_stream), cached under
##      user:// like the backglass art - extraction is
##      best-effort and any failure just falls through to the
##      generated title card.
## Returns "" when no art exists. Never writes anywhere near the tables.
## The designated .directb2s stays ahead of the embedded image on
## purpose: it is the game's chosen backglass, while the embedded
## art is incidental - real, but whatever the author saved last.
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
##   legacy_format - embedded (.vpx) only: the file's art exists
##              only as pre-10.8.1 BITS records (LZW-compressed
##              raw pixels, no encoded image anywhere). A census
##              answer, not a failure: it says how many real files
##              would need an LZW decoder built before their
##              embedded art could serve.
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
##
## The embedded (.vpx) reader carries its OWN generation counter
## (VPX_READER_VERSION, stamped as "ev"), deliberately separate:
## the backglass version's bumps must never force .vpx files
## through a retry, and the embedded reader's fix must not disturb
## a single backglass stamp. Generation 0 (no "ev" field) is the
## offset-0 probe reader the embedded round first shipped - it
## required image bytes at a stream's very start, which no real
## .vpx image stream has, so it stamped most real files
## "no image". Generation 1 is the BIFF walker. Every embedded
## stamp from an older generation counts as untried under
## outcome_for_embedded, so each pre-fix file is retried exactly
## once under the walker and re-stamped with its true outcome.

const CACHE_DIR: String = "user://art_cache"
const INDEX_PATH: String = CACHE_DIR + "/art_index.json"
const IMAGE_EXTS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const PANEL_ART_MAX_W: int = 512
const PANEL_ART_MAX_H: int = 640

const STATUS_OK: String = "ok"
const STATUS_NO_IMAGE: String = "no_image"
const STATUS_FAILED: String = "failed"
const STATUS_LEGACY: String = "legacy_format"

## The extractor's format version, stamped into every outcome-index
## entry as "v". v1: the original reader (no unescaping - it
## refused entity-escaped backglass payloads whole). v2: attribute
## values are XML-unescaped before decoding. Bump this whenever the
## reader learns to read something a previous version stamped
## negatively; older entries then count as untried and are retried
## once under the new reader.
const EXTRACTOR_VERSION: int = 2

## The embedded (.vpx) reader's generation - see the class doc.
## 0 = the offset-0 probe reader (stamps carry no "ev"); 1 = the
## BIFF walker (_walk_vpx_image_stream).
const VPX_READER_VERSION: int = 1

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


## The recorded outcome for a .vpx's embedded image, gated on
## the embedded reader's generation rather than the backglass
## version: an entry whose "ev" predates VPX_READER_VERSION (or
## carries none - every pre-fix stamp) reads "" (untried) here,
## so the file gets its one retry under the current walker. The
## backglass gate (outcome_for) is never consulted for .vpx
## paths, and this gate never for .directb2s paths - each
## reader's fix disturbs only its own files' stamps.
static func outcome_for_embedded(vpx_path: String) -> String:
	_index_mutex.lock()
	_load_index_locked()
	var entry: Variant = _index.get(stamp_key_for(vpx_path), null)
	_index_mutex.unlock()
	if entry is Dictionary:
		var d: Dictionary = entry as Dictionary
		if int(d.get("ev", 0)) < VPX_READER_VERSION:
			return ""
		return str(d.get("status", ""))
	return ""


## The outcome gate for any art source, routed by file kind:
## .vpx sources answer to the embedded reader's generation,
## everything else to the backglass extractor's version. Panels,
## the warmer and the health counts consult outcomes through
## here (or through the kind-specific gates directly), so a
## stale embedded stamp can never suppress its one retry and a
## backglass stamp is read exactly as it always was.
static func outcome_for_source(source_path: String) -> String:
	if source_path.get_extension().to_lower() == "vpx":
		return outcome_for_embedded(source_path)
	return outcome_for(source_path)


static func is_negative_outcome(status: String) -> bool:
	return status == STATUS_NO_IMAGE or status == STATUS_FAILED or status == STATUS_LEGACY


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


## Record an embedded (.vpx) outcome, stamped with BOTH format
## counters: "v" keeps the shared entry shape (generic index
## readers stay sane), "ev" is the embedded generation
## outcome_for_embedded gates on. The same-status shortcut
## requires a current "ev" for the same reason _record_outcome
## requires a current "v": a pre-fix entry re-recorded by the
## walker must gain its generation, or it would read as untried
## forever.
static func _record_outcome_embedded(vpx_path: String, status: String) -> void:
	var key: String = stamp_key_for(vpx_path)
	_index_mutex.lock()
	_load_index_locked()
	var entry: Variant = _index.get(key, null)
	if entry is Dictionary:
		var d: Dictionary = entry as Dictionary
		if str(d.get("status", "")) == status and int(d.get("ev", 0)) >= VPX_READER_VERSION:
			_index_mutex.unlock()
			return
	_index[key] = {"status": status, "src": vpx_path, "v": EXTRACTOR_VERSION, "ev": VPX_READER_VERSION}
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


## Extract art from any extraction source, by file kind: a
## .directb2s gives its designated backglass; a .vpx gives an
## image from inside the table file. Anything else is not an
## extraction source and returns "".
static func extract_art_image(source_path: String) -> String:
	match source_path.get_extension().to_lower():
		"directb2s":
			return extract_directb2s_image(source_path)
		"vpx":
			return extract_vpx_image(source_path)
	return ""


## Extract an image from inside a .vpx table file, with the same
## cache and outcome discipline as the backglass extraction: a
## cache hit serves in microseconds, a stamped negative is never
## re-attempted until the file's stamp changes, and the result is
## stored at panel size through the same _fit_to_panel pipeline.
static func extract_vpx_image(vpx_path: String) -> String:
	var cache_path: String = cache_path_for(vpx_path)
	if FileAccess.file_exists(cache_path):
		if outcome_for_embedded(vpx_path) != STATUS_OK:
			_record_outcome_embedded(vpx_path, STATUS_OK)
		return cache_path
	var result: Dictionary = _extract_vpx_uncached(vpx_path, cache_path)
	_record_outcome_embedded(vpx_path, str(result["status"]))
	return str(result["path"])


## How much of a stream to read just to identify it: enough for
## every supported format's header dimensions (the JPEG marker
## scan included), far less than any real image. Used for the
## one raw stream in the format, TableInfo's Screenshot.
const VPX_PROBE_BYTES: int = 65536
## How much of an image stream the BIFF walk reads. The records
## that matter - the texture's name, its dimensions, and where
## its payload record sits - all live in the first few hundred
## bytes of a real stream; a megabyte of headroom is paranoia.
## The payload itself is never walked: it is range-read
## afterwards, exactly its own span.
const VPX_BIFF_WALK_BYTES: int = 1024 * 1024
## The largest embedded image stream worth decoding at all. Real
## art tops out at a few megabytes; this only refuses pathology.
const VPX_MAX_IMAGE_BYTES: int = 96 * 1024 * 1024
## The class-(c) fallback's "not obviously a small sprite/ramp
## decal" floor: a stream with no telling name only qualifies as
## card art at 200x200 and 60,000 pixels or better. Named
## backglass/playfield streams are exempt - the author named
## them, so their size is their own business.
const VPX_FALLBACK_MIN_W: int = 200
const VPX_FALLBACK_MIN_H: int = 200
const VPX_FALLBACK_MIN_AREA: int = 60000


## One real embedded extraction attempt, against the format as
## VPX actually writes it (vpinball source: PinTable::SaveData
## names the streams, Texture::Save writes the records):
##   - a table's parts live under one storage, GameStg; its
##     images are the streams named Image0, Image1, ... (the CFB
##     census is flat - the entry name carries no storage prefix
##     and no content hint, and no other storage names streams
##     that way);
##   - an image stream is a BIFF record sequence, never an image
##     file: [int32 size][4-char tag][payload] records carrying
##     the texture's NAME, its WDTH/HGHT, and then either LINK
##     (no payload in the stream - the image lives in
##     TableInfo's Screenshot stream, the one stream written as
##     a raw image file) or a JPEG object whose nested DATA
##     record holds the original imported image file's bytes
##     verbatim, a few hundred bytes in;
##   - pre-10.8.1 files may instead store a BMP import as a BITS
##     record: LZW-compressed raw pixels, no encoded image
##     anywhere. Not decoded here - see the outcomes below.
## The first embedded reader probed for image bytes at a
## stream's offset 0, a shape no real image stream has, and so
## found nothing in any real file; this walker reads the records
## instead.
##
## The image pick, in order:
##   (a) a texture whose NAME suggests backglass/backdrop art
##   (b) the playfield texture
##   (c) the largest by record dimensions over the sprite floor
## Within a class, the largest pixel area wins (equal areas: the
## larger payload). Ranked candidates are decoded in order and
## the first that decodes is the art - a corrupt payload does not
## veto the next candidate. A LINK texture is a candidate whose
## bytes are the Screenshot stream's; the Screenshot stream is
## also a candidate in its own right when no LINK claims it (its
## texture's records may have failed while the stream is whole).
## Outcomes: the file is not a readable compound file, image
## candidates existed but none decoded, or an image stream's
## records are corrupt -> failed; nothing decodable but an image
## exists only as BITS -> legacy_format; the file holds no
## GameStg images and no Screenshot stream -> no_image.
static func _extract_vpx_uncached(vpx_path: String, cache_path: String) -> Dictionary:
	var reader: CfbReader = CfbReader.new()
	if not reader.open(vpx_path):
		reader.close()
		return {"path": "", "status": STATUS_FAILED}
	var images: Array = []
	var screenshot: Dictionary = {}
	var saw_corrupt: bool = false
	for item: Variant in _walk_vpx_images(reader):
		var info: Dictionary = item as Dictionary
		if bool(info.get("is_screenshot", false)):
			screenshot = info
		else:
			images.append(info)
			if bool(info.get("corrupt", false)):
				saw_corrupt = true
	var candidates: Array = []
	var link_seen: bool = false
	for info2: Variant in images:
		var im: Dictionary = info2 as Dictionary
		var rec: Dictionary = {
			"name": str(im.get("name", "")),
			"cls": _vpx_name_class(str(im.get("name", ""))),
			"area": int(im.get("width", 0)) * int(im.get("height", 0)),
			"width": int(im.get("width", 0)),
			"height": int(im.get("height", 0)),
		}
		if bool(im.get("has_data", false)):
			rec["kind"] = "data"
			rec["entry"] = im["entry"]
			rec["offset"] = int(im.get("data_offset", 0))
			rec["size"] = int(im.get("data_size", 0))
			candidates.append(rec)
		elif bool(im.get("is_link", false)):
			link_seen = true
			rec["kind"] = "screenshot"
			rec["size"] = int(screenshot.get("size", 0))
			candidates.append(rec)
	if not link_seen and not screenshot.is_empty():
		var sdims: Vector2i = screenshot["dims"] as Vector2i
		candidates.append({
			"name": "Screenshot", "kind": "screenshot",
			"cls": 2, "area": sdims.x * sdims.y,
			"width": sdims.x, "height": sdims.y,
			"size": int(screenshot.get("size", 0)),
		})
	var usable: Array = []
	for cand: Variant in candidates:
		var c: Dictionary = cand as Dictionary
		if int(c["cls"]) == 2 and (int(c["width"]) < VPX_FALLBACK_MIN_W or int(c["height"]) < VPX_FALLBACK_MIN_H \
				or int(c["area"]) < VPX_FALLBACK_MIN_AREA):
			continue ## unnamed and small: a sprite or decal, not card art
		usable.append(c)
	usable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["cls"]) != int(b["cls"]):
			return int(a["cls"]) < int(b["cls"])
		if int(a["area"]) != int(b["area"]):
			return int(a["area"]) > int(b["area"])
		return int(a["size"]) > int(b["size"]))
	for cand2: Variant in usable:
		var c2: Dictionary = cand2 as Dictionary
		var bytes: PackedByteArray = PackedByteArray()
		if str(c2["kind"]) == "data":
			bytes = reader.read_stream_range(c2["entry"] as Dictionary, int(c2["offset"]), int(c2["size"]), VPX_MAX_IMAGE_BYTES)
		elif not screenshot.is_empty():
			bytes = reader.read_stream(screenshot["entry"] as Dictionary, VPX_MAX_IMAGE_BYTES)
		if bytes.is_empty():
			continue
		var img: Image = _decode_image_bytes(bytes)
		if img != null:
			reader.close()
			return _store_extracted(img, cache_path)
	reader.close()
	if not usable.is_empty() or saw_corrupt:
		return {"path": "", "status": STATUS_FAILED}
	for info3: Variant in images:
		if bool((info3 as Dictionary).get("has_bits", false)):
			return {"path": "", "status": STATUS_LEGACY}
	return {"path": "", "status": STATUS_NO_IMAGE}


## Walk a .vpx's image-bearing streams: every GameStg Image<n>
## stream's BIFF records (see _walk_vpx_image_stream), plus the
## Screenshot stream when one exists (flagged is_screenshot,
## with its header dimensions probed - it is a raw image file).
## Everything else in the file is not image data and is never
## opened.
static func _walk_vpx_images(reader: CfbReader) -> Array:
	var out: Array = []
	for entry: Variant in reader.stream_entries():
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry as Dictionary
		var stream_name: String = str(e.get("name", ""))
		if stream_name == "Screenshot":
			var probe: PackedByteArray = reader.read_prefix(e, VPX_PROBE_BYTES)
			var dims: Vector2i = Vector2i.ZERO
			if _has_image_magic(probe):
				dims = _image_dimensions(probe)
			out.append({
				"is_screenshot": true, "entry": e,
				"size": int(e.get("size", 0)), "dims": dims,
			})
		elif _is_vpx_image_stream_name(stream_name):
			out.append(_walk_vpx_image_stream(reader, e))
	return out


## A GameStg image stream's name: "Image" + a plain index
## (Image0, Image1, ...). Texture names never appear here - they
## live inside the streams, in the NAME records.
static func _is_vpx_image_stream_name(stream_name: String) -> bool:
	if not stream_name.begins_with("Image") or stream_name.length() <= 5:
		return false
	var suffix: String = stream_name.substr(5)
	return suffix.is_valid_int() and str(suffix.to_int()) == suffix


## Walk one Image<n> stream's BIFF records. Framing (BiffWriter):
## each record is [int32 recordSize][4-byte tag][payload], the
## size counting tag + payload, so a record spans 4 + size
## bytes; a sub-object (the JPEG PinBinary) is a bare size-4
## header record whose fields then follow as ordinary records,
## closed by an ENDB record. Texture::Save writes NAME, PATH,
## WDTH, HGHT, then LINK or the JPEG object (or, pre-10.8.1, a
## BITS record), then ALTV/MD5H/OPAQ and ENDB. Unknown records -
## older files carry an extra INME, newer ones may add more -
## are skipped by their size, which is all a reader that only
## wants the payload needs.
##
## Returns {stream, entry, name, width, height, has_data,
## data_offset, data_size, is_link, has_bits, corrupt} where the
## DATA location is a span INSIDE this stream (read it with
## CfbReader.read_stream_range). corrupt means the record walk
## broke - a size field that runs off the stream, a truncated
## read - before the texture's payload question was settled.
static func _walk_vpx_image_stream(reader: CfbReader, entry: Dictionary) -> Dictionary:
	var info: Dictionary = {
		"stream": str(entry.get("name", "")), "entry": entry,
		"name": "", "width": 0, "height": 0,
		"has_data": false, "data_offset": 0, "data_size": 0,
		"is_link": false, "has_bits": false, "corrupt": false,
	}
	var stream_size: int = int(entry.get("size", 0))
	var bytes: PackedByteArray = reader.read_prefix(entry, VPX_BIFF_WALK_BYTES)
	if bytes.is_empty():
		info["corrupt"] = true
		return info
	var pos: int = 0
	var in_jpeg: bool = false
	while pos + 8 <= bytes.size():
		var rec_size: int = _le_i32(bytes, pos)
		if rec_size < 4 or pos + 4 + rec_size > stream_size:
			info["corrupt"] = true
			return info
		var tag: String = bytes.slice(pos + 4, pos + 8).get_string_from_ascii()
		var payload_off: int = pos + 8
		var payload_len: int = rec_size - 4
		var past_prefix: bool = pos + 4 + rec_size > bytes.size()
		if in_jpeg:
			if tag == "ENDB":
				in_jpeg = false
			elif tag == "DATA":
				# The payload record itself runs past the walk
				# prefix by design (it IS the image) - its span
				# is all the walk needs from it.
				info["has_data"] = true
				info["data_offset"] = payload_off
				info["data_size"] = payload_len
				return info
			elif past_prefix:
				return info
		else:
			match tag:
				"NAME":
					info["name"] = _biff_string(bytes, payload_off, payload_len)
				"WDTH":
					if payload_len >= 4:
						info["width"] = _le_i32(bytes, payload_off)
				"HGHT":
					if payload_len >= 4:
						info["height"] = _le_i32(bytes, payload_off)
				"LINK":
					info["is_link"] = true
				"BITS":
					info["has_bits"] = true
				"JPEG":
					in_jpeg = true
					pos += 8 ## a bare header record: its fields follow flat
					continue
				"ENDB":
					return info
				_:
					if past_prefix:
						return info
		pos += 4 + rec_size
	return info


## A BIFF string record's payload: [int32 byte count][UTF-8
## bytes]. "" on anything malformed - a bad name costs the
## texture its class, never the walk.
static func _biff_string(bytes: PackedByteArray, off: int, payload_len: int) -> String:
	if payload_len < 4 or off + 4 > bytes.size():
		return ""
	var n: int = _le_i32(bytes, off)
	if n <= 0 or n > payload_len - 4 or off + 4 + n > bytes.size():
		return ""
	return bytes.slice(off + 4, off + 4 + n).get_string_from_utf8()


## Diagnostic surface (the census): a .vpx's walked image
## records, in directory order, without extracting anything -
## [{stream, name, width, height, kind}] where kind is "data"
## (an encoded image file sits in the stream's DATA record),
## "link" (the payload is the Screenshot stream), "bits"
## (legacy LZW pixels only), "none" (no payload record found)
## or "corrupt" (the record walk broke); plus a Screenshot entry
## (kind "screenshot", header dimensions) when that stream
## exists. This is the extractor's own walk - the same records
## its pick runs on - so a census can never disagree with the
## extractor about what a file holds.
static func inspect_vpx_images(vpx_path: String) -> Array:
	var reader: CfbReader = CfbReader.new()
	if not reader.open(vpx_path):
		reader.close()
		return []
	var out: Array = []
	for item: Variant in _walk_vpx_images(reader):
		var info: Dictionary = item as Dictionary
		if bool(info.get("is_screenshot", false)):
			var d: Vector2i = info["dims"] as Vector2i
			out.append({"stream": "Screenshot", "name": "Screenshot",
				"width": d.x, "height": d.y, "kind": "screenshot"})
			continue
		var kind: String = "none"
		if bool(info.get("corrupt", false)):
			kind = "corrupt"
		elif bool(info.get("has_data", false)):
			kind = "data"
		elif bool(info.get("is_link", false)):
			kind = "link"
		elif bool(info.get("has_bits", false)):
			kind = "bits"
		out.append({"stream": str(info.get("stream", "")), "name": str(info.get("name", "")),
			"width": int(info.get("width", 0)), "height": int(info.get("height", 0)), "kind": kind})
	reader.close()
	return out


## The art class a texture's NAME record claims: 0 =
## backglass/backdrop, 1 = playfield, 2 = unnamed. VPX authors
## name their textures after what they hold ("Backglass",
## "Playfield" and kin), so the name is the strongest signal in
## the file.
static func _vpx_name_class(texture_name: String) -> int:
	var n: String = texture_name.to_lower()
	if n.contains("backglass") or n.contains("backdrop") or n.contains("back glass"):
		return 0
	if n.contains("playfield"):
		return 1
	return 2


## An image's pixel dimensions from its header bytes alone -
## Vector2i.ZERO when the header carries none or the format is
## unrecognized. Covers PNG, JPEG, BMP, bare DIB, GIF and WebP.
static func _image_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() >= 24 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return Vector2i(_be_u32(bytes, 16), _be_u32(bytes, 20)) # PNG IHDR
	if bytes.size() >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		return _jpeg_dimensions(bytes)
	if bytes.size() >= 26 and bytes[0] == 0x42 and bytes[1] == 0x4D:
		return Vector2i(absi(_le_i32(bytes, 18)), absi(_le_i32(bytes, 22))) # BMP info header
	if bytes.size() >= 10 and bytes[0] == 0x47 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x38:
		return Vector2i(_le_u16(bytes, 6), _le_u16(bytes, 8)) # GIF logical screen
	if bytes.size() >= 30 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 \
			and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50:
		var chunk: String = bytes.slice(12, 16).get_string_from_ascii()
		if chunk == "VP8X":
			return Vector2i(_le_u24(bytes, 24) + 1, _le_u24(bytes, 27) + 1)
		if chunk == "VP8L" and bytes[20] == 0x2F:
			var b1: int = bytes[21]
			var b2: int = bytes[22]
			var b3: int = bytes[23]
			var b4: int = bytes[24]
			return Vector2i(1 + (b1 | ((b2 & 0x3F) << 8)), 1 + ((b2 >> 6) | (b3 << 2) | ((b4 & 0x0F) << 10)))
		if chunk == "VP8 " and bytes[23] == 0x9D and bytes[24] == 0x01 and bytes[25] == 0x2A:
			return Vector2i(_le_u16(bytes, 26) & 0x3FFF, _le_u16(bytes, 28) & 0x3FFF)
		return Vector2i.ZERO
	return _dib_dimensions(bytes)


## A bare BITMAPINFOHEADER (a DIB - how VPX-era BMP data can sit
## in a stream with no file header around it). Deliberately
## stricter than the magic probe: a plausible header size, one
## plane, a real bit depth, sane extents.
static func _dib_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 40:
		return Vector2i.ZERO
	var header_size: int = _le_u32(bytes, 0)
	if header_size != 40 and header_size != 108 and header_size != 124:
		return Vector2i.ZERO
	if _le_u16(bytes, 12) != 1:
		return Vector2i.ZERO
	var bpp: int = _le_u16(bytes, 14)
	if bpp != 1 and bpp != 4 and bpp != 8 and bpp != 16 and bpp != 24 and bpp != 32:
		return Vector2i.ZERO
	var w: int = _le_i32(bytes, 4)
	var h: int = absi(_le_i32(bytes, 8))
	if w <= 0 or w > 32768 or h <= 0 or h > 32768:
		return Vector2i.ZERO
	return Vector2i(w, h)


## JPEG dimensions: walk the marker segments to the first
## start-of-frame. Bounded by the probe the caller supplies.
static func _jpeg_dimensions(bytes: PackedByteArray) -> Vector2i:
	var i: int = 2
	while i + 9 < bytes.size():
		if bytes[i] != 0xFF:
			i += 1
			continue
		var marker: int = bytes[i + 1]
		if marker == 0xC0 or marker == 0xC1 or marker == 0xC2:
			return Vector2i(_be_u16(bytes, i + 7), _be_u16(bytes, i + 5))
		if marker == 0xD8 or marker == 0xD9 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7):
			i += 2
			continue
		var seg_len: int = _be_u16(bytes, i + 2)
		if seg_len < 2:
			return Vector2i.ZERO
		i += 2 + seg_len
	return Vector2i.ZERO


## Decode raw image bytes (already out of whatever container held
## them) to an Image, or null. The format-specific buffer loaders
## plus a rescue for a bare DIB: prefix the BITMAPFILEHEADER the
## stream never had and let the BMP loader do the rest.
static func _decode_image_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 8:
		return null
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
	var wrapped: PackedByteArray = _dib_to_bmp(bytes)
	if not wrapped.is_empty():
		var img2: Image = Image.new()
		if img2.load_bmp_from_buffer(wrapped) == OK:
			return img2
	return null


## Wrap a bare DIB in a constructed BITMAPFILEHEADER. Empty when
## the bytes are not a plausible uncompressed DIB.
static func _dib_to_bmp(dib: PackedByteArray) -> PackedByteArray:
	if _dib_dimensions(dib) == Vector2i.ZERO:
		return PackedByteArray()
	var header_size: int = _le_u32(dib, 0)
	var compression: int = _le_u32(dib, 16)
	if compression != 0 and compression != 3:
		return PackedByteArray()
	var bpp: int = _le_u16(dib, 14)
	var palette_bytes: int = 0
	if bpp <= 8:
		var colors_used: int = _le_u32(dib, 32)
		palette_bytes = (colors_used if colors_used > 0 else 1 << bpp) * 4
	var masks_bytes: int = 12 if compression == 3 and header_size == 40 else 0
	var data_offset: int = 14 + header_size + palette_bytes + masks_bytes
	if data_offset >= 14 + dib.size():
		return PackedByteArray()
	var out: PackedByteArray = PackedByteArray()
	out.resize(14)
	out[0] = 0x42 # 'B'
	out[1] = 0x4D # 'M'
	out.encode_u32(2, 14 + dib.size())
	out.encode_u32(10, data_offset)
	out.append_array(dib)
	return out


static func _le_u16(bytes: PackedByteArray, off: int) -> int:
	return int(bytes.decode_u16(off)) if off >= 0 and off + 2 <= bytes.size() else 0


static func _le_u24(bytes: PackedByteArray, off: int) -> int:
	if off < 0 or off + 3 > bytes.size():
		return 0
	return int(bytes[off]) | (int(bytes[off + 1]) << 8) | (int(bytes[off + 2]) << 16)


static func _le_u32(bytes: PackedByteArray, off: int) -> int:
	return int(bytes.decode_u32(off)) & 0xFFFFFFFF if off >= 0 and off + 4 <= bytes.size() else 0


static func _le_i32(bytes: PackedByteArray, off: int) -> int:
	return int(bytes.decode_s32(off)) if off >= 0 and off + 4 <= bytes.size() else 0


static func _be_u16(bytes: PackedByteArray, off: int) -> int:
	if off < 0 or off + 2 > bytes.size():
		return 0
	return (int(bytes[off]) << 8) | int(bytes[off + 1])


static func _be_u32(bytes: PackedByteArray, off: int) -> int:
	if off < 0 or off + 4 > bytes.size():
		return 0
	return (int(bytes[off]) << 24) | (int(bytes[off + 1]) << 16) | (int(bytes[off + 2]) << 8) | int(bytes[off + 3])


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
	return _decode_image_bytes(bytes)


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
