class_name LibraryScanner
extends RefCounted

## Scans table folders for .vpx files, groups duplicate builds of the
## same game, and matches them against the VPS database.
## Read-only: the scan never writes, moves, or touches anything in the
## table folders - table .ini files included.

var games: Array[GameEntry] = []
var total_files: int = 0
var matched_files: int = 0 ## builds found in the db (exact build match)
var game_matched_files: int = 0 ## builds whose game is known but build is not in the db
var art_covered_games: int = 0

var _version_re: RegEx = null


func _init() -> void:
	_version_re = RegEx.new()
	_version_re.compile("(?i)\\bv?(\\d+\\.\\d+(?:\\.\\d+)?)\\b")


func scan(folders: Array[String], db: VpsDatabase) -> void:
	games.clear()
	total_files = 0
	matched_files = 0
	game_matched_files = 0
	art_covered_games = 0
	var files: Array[String] = []
	for folder: String in folders:
		_collect_vpx(folder, files)
	files.sort()
	total_files = files.size()
	var by_key: Dictionary = {}
	for path: String in files:
		var build: TableBuild = _make_build(path, db)
		if build.matched_db:
			matched_files += 1
		elif build.game_key != "" and db != null and db.games_by_id.has(build.game_key):
			game_matched_files += 1
		var entry: GameEntry = null
		var existing: Variant = by_key.get(build.game_key, null)
		if existing is GameEntry:
			entry = existing
		if entry == null:
			entry = _make_entry(build, db)
			by_key[build.game_key] = entry
			games.append(entry)
		entry.builds.append(build)
		if entry.art_path == "":
			entry.art_path = ArtProvider.resolve_art(path)
	for entry: GameEntry in games:
		_sort_builds(entry)
		if entry.art_path != "":
			art_covered_games += 1


func duplicate_group_count() -> int:
	var n: int = 0
	for entry: GameEntry in games:
		if entry.builds.size() > 1:
			n += 1
	return n


func game_by_id(game_id: String) -> GameEntry:
	for entry: GameEntry in games:
		if entry.game_id == game_id:
			return entry
	return null


func _collect_vpx(folder: String, out_files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_collect_vpx(folder.path_join(sub), out_files)
	for name: String in dir.get_files():
		if name.get_extension().to_lower() == "vpx":
			out_files.append(folder.path_join(name))


func _make_build(path: String, db: VpsDatabase) -> TableBuild:
	var b: TableBuild = TableBuild.new()
	b.file_path = path
	b.file_name = path.get_file()
	b.date_unix = int(FileAccess.get_modified_time(path))
	var title_guess: String = _guess_title(b.file_name)
	var version_guess: String = _guess_version(b.file_name)
	if db != null and db.loaded:
		# 1) Strong match: a db table file naming this exact file.
		var strong: Dictionary = db.find_by_table_filename(b.file_name)
		if not strong.is_empty():
			_apply_table_file(b, str(strong["game_id"]), strong["table_file"])
			return b
		# 2) Game match by normalized title (with/without a leading "The").
		var game_id: String = _match_game_id(db, title_guess)
		if game_id != "":
			b.game_key = game_id
			# 2a) Build match inside the game by version token.
			if version_guess != "":
				for item: Variant in db.vpx_table_files_of(game_id):
					if item is Dictionary:
						var tf: Dictionary = item
						if str(tf.get("version", "")) == version_guess:
							_apply_table_file(b, game_id, tf)
							return b
			# 2b) No version in the file name, and the db knows a single
			# VPX build of this game: it is this one. (If the file name
			# DOES state a version and it matched nothing above, the
			# build is local-only - never relabel it as the db's build.)
			if version_guess == "":
				var vpx_files: Array = db.vpx_table_files_of(game_id)
				if vpx_files.size() == 1 and vpx_files[0] is Dictionary:
					_apply_table_file(b, game_id, vpx_files[0])
					return b
			# 2c) Game known, build not in the db: keep filename facts.
			b.version = version_guess
			return b
	# 3) Unknown to the db: group by normalized title from the filename.
	b.game_key = "local:" + VpsDatabase.normalize_name(title_guess)
	b.version = version_guess
	return b


func _apply_table_file(b: TableBuild, game_id: String, tf: Dictionary) -> void:
	b.game_key = game_id
	b.matched_db = true
	b.table_file_id = str(tf.get("id", ""))
	var v: String = str(tf.get("version", ""))
	b.version = v if v != "" else _guess_version(b.file_name)
	b.authors = VpsDatabase.str_array(tf.get("authors", []))
	b.features = VpsDatabase.str_array(tf.get("features", []))
	var release: int = VpsDatabase.parse_date_unix(tf.get("createdAt", 0))
	if release > 0:
		b.date_unix = release


func _match_game_id(db: VpsDatabase, title_guess: String) -> String:
	var names: Array[String] = [title_guess]
	if title_guess.to_lower().begins_with("the "):
		names.append(title_guess.substr(4))
	for candidate: String in names:
		var ids: Array[String] = db.find_game_ids_by_name(VpsDatabase.normalize_name(candidate))
		if not ids.is_empty():
			# Several db games can share a normalized name (remakes across
			# makers/years). M1 takes the first; telling twins apart is
			# what the correction pass in a later milestone is for.
			return ids[0]
	return ""


func _make_entry(build: TableBuild, db: VpsDatabase) -> GameEntry:
	var entry: GameEntry = GameEntry.new()
	entry.game_id = build.game_key
	if db != null and db.games_by_id.has(build.game_key):
		var g: Dictionary = db.game_dict(build.game_key)
		entry.title = str(g.get("name", _guess_title(build.file_name)))
		entry.manufacturer = str(g.get("manufacturer", ""))
		entry.year = int(g.get("year", 0))
		entry.designers = VpsDatabase.str_array(g.get("designers", []))
	else:
		entry.title = _guess_title(build.file_name)
		var meta: Dictionary = _parse_paren_meta(build.file_name)
		entry.manufacturer = str(meta.get("manufacturer", ""))
		entry.year = int(meta.get("year", 0))
	return entry


## "Galaxy Corsair (Northlight 1991) v1.1.0.vpx" -> "Galaxy Corsair"
func _guess_title(file_name: String) -> String:
	var stem: String = file_name.get_basename().strip_edges()
	# Drop a trailing version token first ("... v1.2"), but only when it
	# sits in the trailing segment - a dotted number that is part of the
	# title proper (before the maker parens) belongs to the name.
	var matches: Array = _version_re.search_all(stem)
	if not matches.is_empty():
		var last: RegExMatch = matches[matches.size() - 1]
		if last.get_start() > stem.rfind(")"):
			stem = stem.substr(0, last.get_start()).strip_edges()
	# Then strip trailing "(...)" / "[...]" groups (maker/year, edition).
	var changed: bool = true
	while changed:
		changed = false
		if stem.ends_with(")") and stem.contains("("):
			stem = stem.substr(0, stem.rfind("(")).strip_edges()
			changed = true
		elif stem.ends_with("]") and stem.contains("["):
			stem = stem.substr(0, stem.rfind("[")).strip_edges()
			changed = true
	while stem.ends_with("-") or stem.ends_with("_"):
		stem = stem.substr(0, stem.length() - 1).strip_edges()
	return stem


## Last version-looking token in the file name, e.g. "1.0.2"; "" if none.
func _guess_version(file_name: String) -> String:
	var stem: String = file_name.get_basename()
	var matches: Array = _version_re.search_all(stem)
	if matches.is_empty():
		return ""
	var last: RegExMatch = matches[matches.size() - 1]
	return last.get_string(1)


## "Title (Manufacturer 1991)" -> {manufacturer, year} - filename heuristic
## for games the db does not know.
func _parse_paren_meta(file_name: String) -> Dictionary:
	var out: Dictionary = {"manufacturer": "", "year": 0}
	var stem: String = file_name.get_basename()
	var open: int = stem.find("(")
	var close: int = stem.find(")", open)
	if open < 0 or close < 0:
		return out
	var inside: String = stem.substr(open + 1, close - open - 1).strip_edges()
	var year_re: RegEx = RegEx.new()
	year_re.compile("(19|20)\\d\\d")
	var m: RegExMatch = year_re.search(inside)
	if m != null:
		out["year"] = m.get_string().to_int()
		out["manufacturer"] = inside.substr(0, m.get_start()).strip_edges()
	else:
		out["manufacturer"] = inside
	return out


func _sort_builds(entry: GameEntry) -> void:
	# Display order: CURRENT (db rank) first, then newest first.
	entry.builds.sort_custom(
		func(a: TableBuild, b: TableBuild) -> bool:
			if a.matched_db != b.matched_db:
				return a.matched_db
			if a.date_unix != b.date_unix:
				return a.date_unix > b.date_unix
			return TableBuild.compare_versions(a.version, b.version) > 0
	)
