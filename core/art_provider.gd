class_name ArtProvider
extends RefCounted

## Resolves a display image for a table file. Order:
##   1. an image sitting beside the .vpx with the same stem
##      (.png / .jpg / .jpeg / .webp)
##   2. the backglass image extracted from a same-stem .directb2s file,
##      cached under user:// - extraction is best-effort: the format is
##      XML carrying base64 image blobs, and any failure just falls
##      through to the generated title card.
## Returns "" when no art exists. Never writes anywhere near the tables.

const CACHE_DIR: String = "user://art_cache"
const IMAGE_EXTS: Array[String] = ["png", "jpg", "jpeg", "webp"]


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


static func extract_directb2s_image(b2s_path: String) -> String:
	var cache_path: String = CACHE_DIR.path_join(b2s_path.md5_text() + ".png")
	if FileAccess.file_exists(cache_path):
		return cache_path
	var text: String = FileAccess.get_file_as_string(b2s_path)
	if text == "":
		return ""
	var blobs: Array[String] = _base64_candidates(text)
	for blob: String in blobs:
		var bytes: PackedByteArray = Marshalls.base64_to_raw(blob)
		if bytes.size() < 8:
			continue
		if not _has_image_magic(bytes):
			continue
		var img: Image = Image.new()
		var err: Error = img.load_png_from_buffer(bytes)
		if err != OK:
			err = img.load_jpg_from_buffer(bytes)
		if err != OK:
			continue
		_ensure_cache_dir()
		if img.save_png(cache_path) == OK:
			return cache_path
	return ""


static func _ensure_cache_dir() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and not dir.dir_exists("art_cache"):
		dir.make_dir("art_cache")


static func _has_image_magic(bytes: PackedByteArray) -> bool:
	# PNG magic: 89 50 4E 47; JPEG magic: FF D8.
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return true
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return true
	return false


## Long base64-looking runs, whitespace-stripped, longest first (cap 3).
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
	var limit: int = mini(3, cleaned.size())
	for i: int in range(limit):
		out.append(cleaned[i])
	return out
