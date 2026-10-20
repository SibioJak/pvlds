class_name VpsDatabase
extends RefCounted

## Reader for the Virtual Pinball Spreadsheet database (vpsdb.json).
## Real format: a top-level JSON array of game objects, each with
## id / name / manufacturer / year / designers / tableFiles[], and each
## table file with id / version / tableFormat / authors / createdAt /
## features. This reader is defensive about shape (array, or an object
## with a "games" array/object) and about dates (epoch seconds, epoch
## milliseconds, or ISO strings all occur in the wild).

var games_by_id: Dictionary = {}
var _games_by_norm_name: Dictionary = {} ## normalized title -> Array of game ids
var _by_table_filename: Dictionary = {} ## lowercased table fileName -> first {game_id, table_file} claiming it
var loaded: bool = false
var source_path: String = ""


static func normalize_name(s: String) -> String:
	var out: String = ""
	var lowered: String = s.to_lower()
	for i: int in range(lowered.length()):
		var code: int = lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			out += lowered[i]
	return out


static func str_array(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if value is Array:
		var arr: Array = value
		for item: Variant in arr:
			out.append(str(item))
	elif value is String:
		var s: String = value
		if s != "":
			out.append(s)
	return out


static func parse_date_unix(value: Variant) -> int:
	if value is int:
		return _normalize_epoch(value)
	if value is float:
		return _normalize_epoch(int(value))
	if value is String:
		var s: String = value
		if s.is_valid_int():
			return _normalize_epoch(s.to_int())
		return Time.get_unix_time_from_datetime_string(s)
	return 0


static func _normalize_epoch(v: int) -> int:
	if v > 100000000000: ## milliseconds since epoch
		return v / 1000
	return v


func load_db(path: String) -> bool:
	loaded = false
	games_by_id.clear()
	_games_by_norm_name.clear()
	_by_table_filename.clear()
	if path == "" or not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var game_list: Array = []
	if parsed is Array:
		game_list = parsed
	elif parsed is Dictionary:
		var pd: Dictionary = parsed
		var g: Variant = pd.get("games", [])
		if g is Array:
			game_list = g
		elif g is Dictionary:
			var gd: Dictionary = g
			for k: Variant in gd.keys():
				var v: Variant = gd[k]
				if v is Dictionary:
					game_list.append(v)
	else:
		return false
	for item: Variant in game_list:
		if not (item is Dictionary):
			continue
		var game: Dictionary = item
		var gid: String = str(game.get("id", ""))
		if gid == "":
			continue
		games_by_id[gid] = game
		var norm: String = VpsDatabase.normalize_name(str(game.get("name", "")))
		if norm != "":
			var ids: Array = []
			var existing: Variant = _games_by_norm_name.get(norm, [])
			if existing is Array:
				ids = existing
			ids.append(gid)
			_games_by_norm_name[norm] = ids
	# Filename index, built once here: the scanner asks once per local
	# file, and a linear walk of every game x every table file per ask
	# cost ~12 s at real db scale. First claimant wins, exactly like
	# the old linear walk's early return (same iteration order).
	for gid: Variant in games_by_id.keys():
		var game_id: String = str(gid)
		for item: Variant in vpx_table_files_of(game_id):
			if item is Dictionary:
				var tf: Dictionary = item
				var named: String = str(tf.get("fileName", tf.get("filename", ""))).to_lower()
				if named != "" and not _by_table_filename.has(named):
					_by_table_filename[named] = {"game_id": game_id, "table_file": tf}
	source_path = path
	loaded = not games_by_id.is_empty()
	return loaded


func game_count() -> int:
	return games_by_id.size()


func game_dict(game_id: String) -> Dictionary:
	var v: Variant = games_by_id.get(game_id, {})
	if v is Dictionary:
		return v
	return {}


func find_game_ids_by_name(norm_name: String) -> Array[String]:
	var out: Array[String] = []
	var v: Variant = _games_by_norm_name.get(norm_name, [])
	if v is Array:
		var arr: Array = v
		for item: Variant in arr:
			out.append(str(item))
	return out


func table_files_of(game_id: String) -> Array:
	var g: Dictionary = game_dict(game_id)
	var v: Variant = g.get("tableFiles", [])
	if v is Array:
		return v
	return []


## Only the VPX table files of a game (the db also lists other formats).
func vpx_table_files_of(game_id: String) -> Array:
	var out: Array = []
	for item: Variant in table_files_of(game_id):
		if item is Dictionary:
			var tf: Dictionary = item
			if str(tf.get("tableFormat", "VPX")).to_upper() == "VPX":
				out.append(tf)
	return out


## Strong match: a db table file that names this exact .vpx file name
## (some db entries carry one; many do not). Returns {} on no match.
func find_by_table_filename(file_name: String) -> Dictionary:
	var hit: Variant = _by_table_filename.get(file_name.to_lower(), null)
	if hit is Dictionary:
		return hit
	return {}
