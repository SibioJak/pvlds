class_name LibraryScanner
extends RefCounted

## Scans table folders for .vpx files, groups duplicate builds of the
## same game, and matches them against the VPS database.
## Read-only: the scan never writes, moves, or touches anything in the
## table folders - table .ini files included.
## Art is LAZY: the scan records only facts visible in a directory
## listing (a same-stem image or .directb2s exists) plus each
## game's own .vpx as the embedded-image source. Extracting a
## backglass out of a .directb2s costs ~200 ms per file at
## real-world sizes, and opening a .vpx to read its embedded image
## is real work too, so both happen on demand via
## GameEntry.ensure_art(), never here. Safe to run on a worker
## thread: pure data in, pure data out.

const MAX_SCAN_DEPTH: int = 12 ## Recursion cap - also the cycle backstop.
const JUNK_FOLDERS: Array[String] = ["$recycle.bin", "system volume information", "recycler"]

var games: Array[GameEntry] = []
var total_files: int = 0
var matched_files: int = 0 ## builds found in the db (exact build match)
var game_matched_files: int = 0 ## builds whose game is known but build is not in the db
var match_tier_counts: Dictionary = {} ## match tier -> files resolved through it (every scanned file counted once, "local" included)
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
	match_tier_counts.clear()
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
		var tier_key: String = build.match_tier if build.match_tier != "" else "local"
		match_tier_counts[tier_key] = int(match_tier_counts.get(tier_key, 0)) + 1
		var entry: GameEntry = null
		var existing: Variant = by_key.get(build.game_key, null)
		if existing is GameEntry:
			entry = existing
		if entry == null:
			entry = _make_entry(build, db)
			by_key[build.game_key] = entry
			games.append(entry)
		entry.builds.append(build)
	for entry: GameEntry in games:
		_sort_builds(entry)
		_resolve_art(entry, art_map)
		# The card face's first source (the graduation round): the
		# CURRENT build's author screenshot, when the db carries
		# one for that exact build. The URL is recorded here; the
		# fetch itself is Main's ShotFetcher (the scan stays pure
		# data - no network on the worker thread).
		var best: TableBuild = entry.current_build()
		entry.shot_url = best.img_url if best != null else ""
		# Covered = the listing proved art exists: a side image or
		# a backglass. A game whose only source is the image inside
		# its .vpx is NOT counted here - that art is real but
		# unproven until an extraction succeeds, and this count is
		# the scan summary's pre-extraction baseline.
		if entry.art_path != "" or entry.art_source_path.get_extension().to_lower() == "directb2s":
			art_covered_games += 1
	if progress != null:
		progress.report_match(files.size())
		progress.finish()


## Art-source resolution for one grouped game, from the listing's
## facts. Runs once per game after grouping (never in the per-file
## loop), so a game's art does not depend on which build the scan
## met first. The order is the art order: a side image beside ANY
## build wins the face outright; else the first backglass found is
## the primary extraction source; else the first build's own .vpx
## is the primary - its embedded image is a real source, opened
## lazily by GameEntry.ensure_art, never by the scan. The first
## build's .vpx is ALWAYS recorded as art_vpx_path too: the
## embedded fallback behind a backglass primary.
func _resolve_art(entry: GameEntry, art_map: Dictionary) -> void:
	var first_side: String = ""
	var first_b2s: String = ""
	for b: TableBuild in entry.builds:
		var facts: Variant = art_map.get(b.file_path, null)
		if facts is Dictionary:
			var fd: Dictionary = facts
			if first_side == "":
				first_side = str(fd.get("side", ""))
			if first_b2s == "":
				first_b2s = str(fd.get("b2s", ""))
	if not entry.builds.is_empty():
		entry.art_vpx_path = entry.builds[0].file_path
	if first_side != "":
		entry.art_path = first_side
	elif first_b2s != "":
		entry.art_source_path = first_b2s
	elif entry.art_vpx_path != "":
		entry.art_source_path = entry.art_vpx_path


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
	b.match_tier = "local"
	var title_guess: String = _guess_title(b.file_name)
	var version_guess: String = _guess_version(b.file_name)
	if db != null and db.loaded:
		# 1) Download slug: the db's download page for a build bakes
		# title+maker+year+authors into its URL slug, and the file's
		# scrubbed name equals that slug's key. The key must belong
		# to ONE game - two games claiming it makes it ambiguous,
		# and an ambiguous key falls through to the next tier (a
		# false match is worse than a miss: wrong metadata, wrong
		# VR flag). Exactly one claimant file whose stated version
		# the file does not contradict claims the BUILD; otherwise
		# the game is still certain, so the within-game ladder
		# decides.
		var claimants: Array = db.find_by_slug(b.file_name)
		var claimant_games: Dictionary = {}
		for item: Variant in claimants:
			if item is Dictionary:
				var cd: Dictionary = item
				var cg: String = str(cd.get("game_id", ""))
				if cg != "":
					claimant_games[cg] = true
		if claimant_games.size() == 1:
			var slug_game_id: String = str(claimant_games.keys()[0])
			var only_tf: Dictionary = {}
			if claimants.size() == 1:
				for item2: Variant in claimants:
					if item2 is Dictionary:
						var cd2: Dictionary = item2
						var tfv: Variant = cd2.get("table_file", {})
						if tfv is Dictionary:
							only_tf = tfv
			if not only_tf.is_empty() and (version_guess == "" or version_guess == str(only_tf.get("version", ""))):
				_apply_table_file(b, slug_game_id, only_tf)
				b.match_tier = "slug"
				return b
			return _finish_game_match(b, db, slug_game_id, "slug", version_guess)
		# 2) Game by title (with/without a leading "The").
		var game_id: String = _match_game_id(db, title_guess, b.file_name)
		if game_id != "":
			return _finish_game_match(b, db, game_id, "name", version_guess)
		# 3) Cleaned game name: the file's scrubbed name equals a
		# db game's scrubbed name - for tables whose db entries
		# carry no usable download slug. Refereed by the file's
		# own (Maker Year) parens: exactly one consistent game,
		# or no match.
		var scrub_ids: Array[String] = db.find_game_ids_by_scrubbed_name(b.file_name)
		var survivors: Array[String] = []
		for sid: String in scrub_ids:
			if _meta_consistent(db, sid, b.file_name):
				survivors.append(sid)
		if survivors.size() == 1:
			return _finish_game_match(b, db, survivors[0], "scrubbed", version_guess)
	# 4) Unknown to the db: group by normalized title from the filename.
	b.game_key = "local:" + VpsDatabase.normalize_name(title_guess)
	b.version = version_guess
	return b


## The within-game ladder once a tier has identified the game:
## build by stated version token; when the file states no version
## and the db knows a single VPX build of the game, that build;
## otherwise the game is known and the build stays local - a
## stated version that matches nothing is NEVER relabeled as a
## db build.
func _finish_game_match(b: TableBuild, db: VpsDatabase, game_id: String, tier: String, version_guess: String) -> TableBuild:
	b.game_key = game_id
	b.match_tier = tier
	if version_guess != "":
		for item: Variant in db.vpx_table_files_of(game_id):
			if item is Dictionary:
				var tf: Dictionary = item
				if str(tf.get("version", "")) == version_guess:
					_apply_table_file(b, game_id, tf)
					return b
	else:
		var vpx_files: Array = db.vpx_table_files_of(game_id)
		if vpx_files.size() == 1 and vpx_files[0] is Dictionary:
			_apply_table_file(b, game_id, vpx_files[0])
			return b
	b.version = version_guess
	return b


## Whether the file name's own "(Manufacturer Year)" parens agree
## with a db game. Constraints exist only inside that convention:
## a paren without a year ("(Remake)", "(Special Edition)") is
## not maker evidence and vetoes nothing. With a year present,
## the year must agree (when the db carries one) and the maker
## tokens must overlap the db's (either side may carry the fuller
## form: "Northlight" against "Northlight Amusements").
func _meta_consistent(db: VpsDatabase, game_id: String, file_name: String) -> bool:
	var meta: Dictionary = _parse_paren_meta(file_name)
	var file_year: int = int(meta.get("year", 0))
	if file_year <= 0:
		return true
	var g: Dictionary = db.game_dict(game_id)
	var game_year: int = int(g.get("year", 0))
	if game_year > 0 and game_year != file_year:
		return false
	var file_maker: String = str(meta.get("manufacturer", ""))
	var game_maker: String = str(g.get("manufacturer", ""))
	if file_maker != "" and game_maker != "":
		var ft: PackedStringArray = VpsDatabase.scrub_tokens(file_maker)
		var gt: PackedStringArray = VpsDatabase.scrub_tokens(game_maker)
		if not ft.is_empty() and not gt.is_empty():
			if not _tokens_subset(ft, gt) and not _tokens_subset(gt, ft):
				return false
	return true


static func _tokens_subset(a: PackedStringArray, b: PackedStringArray) -> bool:
	for t: String in a:
		if not b.has(t):
			return false
	return true


func _apply_table_file(b: TableBuild, game_id: String, tf: Dictionary) -> void:
	b.game_key = game_id
	b.matched_db = true
	b.table_file_id = str(tf.get("id", ""))
	b.img_url = str(tf.get("imgUrl", ""))
	var v: String = str(tf.get("version", ""))
	b.version = v if v != "" else _guess_version(b.file_name)
	b.authors = VpsDatabase.str_array(tf.get("authors", []))
	b.features = VpsDatabase.str_array(tf.get("features", []))
	var release: int = VpsDatabase.parse_date_unix(tf.get("createdAt", 0))
	if release > 0:
		b.date_unix = release


func _match_game_id(db: VpsDatabase, title_guess: String, file_name: String) -> String:
	var names: Array[String] = [title_guess]
	if title_guess.to_lower().begins_with("the "):
		names.append(title_guess.substr(4))
	for candidate: String in names:
		var ids: Array[String] = db.find_game_ids_by_name(VpsDatabase.normalize_name(candidate))
		var survivors: Array[String] = []
		for gid: String in ids:
			if _meta_consistent(db, gid, file_name):
				survivors.append(gid)
		if survivors.size() == 1:
			return survivors[0]
		# Zero survivors: the name exists but the file's own
		# (Maker Year) parens contradict every bearer - a false
		# match refused. Several: same-name twins (remakes) the
		# parens cannot separate - ambiguous, also refused. (M1
		# took the first twin; a coin-flip identity presented as
		# fact is worse than an honest filename-only record.)
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
		# Filename-only game: the title it shows everywhere (wall
		# cards, detail view, the loading marquee) is the file
		# name decoration-scrubbed - not the raw stem with author
		# tags, version tokens and feature shouts riding along.
		var clean: String = VpsDatabase.clean_display_title(build.file_name)
		entry.title = clean if clean != "" else _guess_title(build.file_name)
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
