class_name TableBuild
extends RefCounted

## One physical .vpx file on disk: a single build of a game.
## Pure data - no scene, texture, or engine-display dependencies.

var file_path: String = ""
var file_name: String = ""
var game_key: String = "" ## VPS game id when known, else "local:<normalized title>".
var table_file_id: String = "" ## VPS table-file id when this build matched the db.
var img_url: String = "" ## The db tableFile's imgUrl: the author's screenshot of this exact build (the graduation round's card face). "" when the db carries none for this file.
var version: String = "" ## e.g. "1.2.0"; "" when unknown.
var authors: PackedStringArray = PackedStringArray()
var date_unix: int = 0 ## Release date from the db when matched, else file mtime.
var features: PackedStringArray = PackedStringArray()
var matched_db: bool = false ## True when this exact build exists in the VPS db.
var match_tier: String = "" ## How the scan identified this build's game: "slug" (the db's download-page slug for the build) | "name" (title) | "scrubbed" (cleaned title) | "local" (db does not know it). "" until matched.


func display_version() -> String:
	return version if version != "" else "?"


func authors_text() -> String:
	if authors.is_empty():
		return "Unknown author"
	return ", ".join(authors)


func date_text() -> String:
	if date_unix <= 0:
		return "unknown date"
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(date_unix)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


func has_vr_tag() -> bool:
	for f: String in features:
		if f == "VR" or f == "Mixed Reality" or f == "MR":
			return true
	return false


## Numeric dotted-version compare: returns 1, 0, or -1.
static func compare_versions(a: String, b: String) -> int:
	var pa: PackedStringArray = a.split(".")
	var pb: PackedStringArray = b.split(".")
	var n: int = maxi(pa.size(), pb.size())
	for i: int in range(n):
		var va: int = 0
		var vb: int = 0
		if i < pa.size() and pa[i].is_valid_int():
			va = pa[i].to_int()
		if i < pb.size() and pb[i].is_valid_int():
			vb = pb[i].to_int()
		if va < vb:
			return -1
		if va > vb:
			return 1
	return 0
