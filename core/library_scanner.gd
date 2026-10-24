class_name LibraryScanner
extends RefCounted

## Scans table folders for .vpx files, groups duplicate builds of the
## same game, and matches them against the VPS database.
## Read-only: the scan never writes, moves, or touches anything in the
## table folders - table .ini files included.
## Art is LAZY: the scan records only facts visible in a directory
## listing (a same-stem image or .directb2s exists). Extracting a
## backglass out of a .directb2s costs ~200 ms per file at real-world
## sizes, so it happens on demand via GameEntry.ensure_art(), never
## here. Safe to run on a worker thread: pure data in, pure data out.

const MAX_SCAN_DEPTH: int = 12 ## Recursion cap - also the cycle backstop.
const JUNK_FOLDERS: Array[String] = ["$recycle.bin", "system volume information", "recycler"]

var games: Array[GameEntry] = []
var total_files: int = 0
var matched_files: int = 0 ## builds found in the db (exact build match)
var game_matched_files: int = 0 ## builds whose game is known but build is not in the db
var art_covered_games: int = 0
var missing_b2s_files: Array[String] = [] ## .vpx files with no same-stem .directb2s beside them, from this scan's own listing - the missing-backglass list's raw material (see MissingB2sList).

var _version_re: RegEx = null


func _init() -> void:
	_version_re = RegEx.new()
	_version_re.compile("(?i)\\bv?(\\d+\\.\\d+(?:\\.\\d+)?)\\b")


func scan(folders: Array[String], db: VpsDatabase, progress: ScanProgress = null) -> void:
	games.clear()
	total_files = 0
	matched_files = 0
	game_matched_files = 0
	art_covered_games = 0
	missing_b2s_files.clear()
	if progress != null:
		progress.begin("collecting", folders.size())
	var files: Array[String] = []
	var art_map: Dictionary = {} ## .vpx path -> {"side": path} and/or {"b2s": path}
	var b2s_by_file: Dictionary = {} ## .vpx path -> true when a same-stem .directb2s was listed beside it
	var visited: Dictionary = {} ## canonical folder path -> true (cycle guard)
	var folders_done: int = 0
	for folder: String in folders:
		_collect_vpx(folder, files, art_map, visited, b2s_by_file, 0)
		folders_done += 1
		if progress != null:
			progress.report_collect(folders_done, files.size())
	files.sort()
	total_files = files.size()
	# The missing-backglass record, derived from the same listing
	# that produced the art facts - one pass, one truth. (A side
	# image does not clear a file here: the record is about the
	# backglass file's presence, not about which art won.)
	for scanned_path: String in files:
		if not bool(b2s_by_file.get(scanned_path, false)):
			missing_b2s_files.append(scanned_path)
	var by_key: Dictionary = {}
	for i: int in range(files.size()):
		var path: String = files[i]
		if progress != null and i % 16 == 0:
			progress.report_match(i)
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
		if entry.art_path == "" and entry.art_source_path == "":
			var facts: Variant = art_map.get(path, null)
			if facts is Dictionary:
				var fd: Dictionary = facts
				entry.art_path = str(fd.get("side", ""))
				entry.art_source_path = str(fd.get("b2s", ""))
	for entry: GameEntry in games:
		_sort_builds(entry)
		if entry.has_art_available():
			art_covered_games += 1
	if progress != null:
		progress.report_match(files.size())
		progress.finish()


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


## Recursive collection with guards: a visited set on canonical folder
## paths (junction/symlink cycles), a depth cap as the backstop, and
## hidden/system junk folders skipped. Art facts come from this same
## listing - no candidate file is ever opened during a scan.
func _collect_vpx(folder: String, out_files: Array[String], art_map: Dictionary, visited: Dictionary, b2s_by_file: Dictionary, depth: int) -> void:
	if depth > MAX_SCAN_DEPTH:
		return
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	var canon: String = dir.get_current_dir().to_lower()
	if visited.has(canon):
		return
	visited[canon] = true
	var names: PackedStringArray = dir.get_files()
	var side_by_stem: Dictionary = {}
	for ext: String in ArtProvider.IMAGE_EXTS:
		for name: String in names:
			if name.get_extension().to_lower() == ext:
				var stem_key: String = name.get_basename().to_lower()
				if not side_by_stem.has(stem_key):
					side_by_stem[stem_key] = folder.path_join(name)
	var b2s_by_stem: Dictionary = {}
	for name: String in names:
		if name.get_extension().to_lower() == "directb2s":
			b2s_by_stem[name.get_basename().to_lower()] = folder.path_join(name)
	for name: String in names:
		if name.get_extension().to_lower() == "vpx":
			var full: String = folder.path_join(name)
			out_files.append(full)
			var stem_key: String = name.get_basename().to_lower()
			b2s_by_file[full] = b2s_by_stem.has(stem_key)
			var facts: Dictionary = {}
			if side_by_stem.has(stem_key):
				facts["side"] = str(side_by_stem[stem_key])
			elif b2s_by_stem.has(stem_key):
				facts["b2s"] = str(b2s_by_stem[stem_key])
			if not facts.is_empty():
				art_map[full] = facts
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		if JUNK_FOLDERS.has(sub.to_lower()):
			continue
		_collect_vpx(folder.path_join(sub), out_files, art_map, visited, b2s_by_file, depth + 1)


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
