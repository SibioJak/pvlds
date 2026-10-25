class_name VpsDatabase
extends RefCounted

## Reader for the Virtual Pinball Spreadsheet database (vpsdb.json).
## Real format: a top-level JSON array of game objects, each with
## id / name / manufacturer / year / designers / tableFiles[], and each
## table file with id / version / tableFormat / authors / createdAt /
## features. This reader is defensive about shape (array, or an object
## with a "games" array/object) and about dates (epoch seconds, epoch
## milliseconds, or ISO strings all occur in the wild).

const DOWNLOAD_URL: String = "https://virtualpinballspreadsheet.github.io/vps-db/db/vpsdb.json"
const CACHE_PATH: String = "user://vpsdb_download.json" ## downloaded real db (desk pass)
const SAMPLE_PATH: String = "res://data/vpsdb.json" ## bundled sample: 10 invented games

var games_by_id: Dictionary = {}
var _games_by_norm_name: Dictionary = {} ## normalized title -> Array of game ids
var _by_table_filename: Dictionary = {} ## lowercased table fileName -> first {game_id, table_file} claiming it
var _author_tokens: Dictionary = {} ## token -> true, from every db table file's authors (the matcher's author vocabulary)
var _files_by_scrub_key: Dictionary = {} ## match key of a db table fileName -> Array of {game_id, table_file} claiming it
var _games_by_scrub_name: Dictionary = {} ## match key of a db game name -> Array of game ids
var loaded: bool = false
var source_path: String = ""

## Words that decorate table file names without naming the game:
## format/mode/feature tags authors and uploaders staple on. The
## matcher drops them from BOTH sides of a comparison (never from
## stored data), so "Table (Maker 1990) [VR] v1.2" and the db's
## plain "Table" reduce to the same key.
const DECORATION_TOKENS: Dictionary = {
	"vpx": true, "vp": true, "mod": true, "vr": true, "fss": true,
	"fs": true, "dt": true, "mr": true, "b2s": true, "hybrid": true,
	"fullscreen": true,
}


## Which database a scan should use, in order: the path the user
## picked themselves, then the downloaded VPS cache, then - last
## resort only - the bundled sample (10 invented games that exist to
## exercise PVLDS itself, NOT to identify real tables).
## Returns [path, kind] with kind "user" | "download" | "sample".
static func resolve_path(user_path: String) -> Array:
	if user_path != "" and FileAccess.file_exists(user_path):
		return [user_path, "user"]
	if FileAccess.file_exists(CACHE_PATH):
		return [CACHE_PATH, "download"]
	return [SAMPLE_PATH, "sample"]


static func normalize_name(s: String) -> String:
	var out: String = ""
	var lowered: String = s.to_lower()
	for i: int in range(lowered.length()):
		var code: int = lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			out += lowered[i]
	return out


## Lowercase alphanumeric word tokens of a string, in order.
static func raw_tokens(s: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var cur: String = ""
	var lowered: String = s.to_lower()
	for i: int in range(lowered.length()):
		var code: int = lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			cur += lowered[i]
		elif cur != "":
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	return out


## String-level decoration removal, shared by the match key and
## the display title: "(...)"/"[...]" segments anywhere (maker/
## year, edition and tag blocks), version substrings (v-prefixed
## or dotted - a bare integer stays: it can be part of a title,
## "Apollo 13", "2001"), and everything after a spaced dash (the
## " - Author" tail uploaders append).
static func string_scrub(s: String) -> String:
	var t: String = s.replace("_", " ")
	var paren_re: RegEx = RegEx.new()
	paren_re.compile("\\([^)]*\\)")
	t = paren_re.sub(t, " ", true)
	var bracket_re: RegEx = RegEx.new()
	bracket_re.compile("\\[[^\\]]*\\]")
	t = bracket_re.sub(t, " ", true)
	var vver_re: RegEx = RegEx.new()
	vver_re.compile("(?i)\\bv\\d+(?:\\.\\d+)*[a-z]?\\b")
	t = vver_re.sub(t, " ", true)
	var dver_re: RegEx = RegEx.new()
	dver_re.compile("(?i)\\b\\d+\\.\\d+(?:\\.\\d+)?[a-z]?\\b")
	t = dver_re.sub(t, " ", true)
	var dash: int = t.find(" - ")
	if dash >= 0:
		t = t.substr(0, dash)
	return t


## The matcher's token view of a name: string-scrubbed, tokenized,
## decoration words dropped, a leading "The" dropped (both sides
## get the same treatment, so equality survives it).
static func scrub_tokens(s: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for tok: String in raw_tokens(string_scrub(s)):
		if DECORATION_TOKENS.has(tok):
			continue
		out.append(tok)
	if not out.is_empty() and out[0] == "the":
		out.remove_at(0)
	return out


## This database's match key for a name (usually a file name):
## scrub tokens with the db's own author tokens removed as well -
## an author's name rides along in file names on both sides of
## the comparison (in the local file's name, in db file names),
## and the db is the only place the vocabulary can come from.
## Author removal never empties a key: a name that is ONLY an
## author token keeps it rather than collapsing to "".
func match_key(s: String) -> String:
	var toks: PackedStringArray = scrub_tokens(s)
	var kept: PackedStringArray = PackedStringArray()
	for tok: String in toks:
		if not _author_tokens.has(tok):
			kept.append(tok)
	if kept.is_empty():
		kept = toks
	return "".join(kept)


## A decoration-scrubbed, human-readable title for a file the db
## does not know - the display sibling of the match key, built
## from the same vocabulary but CONSERVATIVE about words: real
## titles contain words the key drops freely ("Mr." is a title
## word, "MR" is a feature tag), so in running text only SHOUTED
## decoration (all-caps words and dash chains like DT-FS-VR-MR)
## is removed mid-title; plain decoration words are cut only at
## the edges. "" when nothing survives - the caller falls back.
static func clean_display_title(file_name: String) -> String:
	var t: String = string_scrub(file_name.get_basename())
	var words: PackedStringArray = t.split(" ", false)
	var kept: Array[String] = []
	for w: String in words:
		if _is_shouted_decoration(w):
			continue
		kept.append(w)
	while not kept.is_empty() and _is_plain_decoration(kept[0]):
		kept.pop_front()
	while not kept.is_empty() and _is_plain_decoration(kept[kept.size() - 1]):
		kept.pop_back()
	var out: String = " ".join(kept).strip_edges()
	while out.ends_with("-") or out.ends_with("_"):
		out = out.substr(0, out.length() - 1).strip_edges()
	return out


## True when a displayed word is nothing but decoration tokens
## SHOUTED (all caps, possibly dash-chained: "VR", "FSS",
## "DT-FS-VR-MR"). Titlecase lookalikes ("Mr.", "Mod Squad")
## are title words and never qualify.
static func _is_shouted_decoration(w: String) -> bool:
	if w == "" or w != w.to_upper():
		return false
	var parts: PackedStringArray = w.split("-", false)
	if parts.is_empty():
		return false
	for p: String in parts:
		var toks: PackedStringArray = raw_tokens(p)
		if toks.size() != 1 or not DECORATION_TOKENS.has(toks[0]):
			return false
	return true


## True when a word is exactly one decoration token with no
## punctuation attached ("vr", "mod") - safe to cut at a title's
## edge. "Mr." is not: its raw token matches, its letters don't.
static func _is_plain_decoration(w: String) -> bool:
	var toks: PackedStringArray = raw_tokens(w)
	return toks.size() == 1 and w.to_lower() == toks[0] and DECORATION_TOKENS.has(toks[0])


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
	_author_tokens.clear()
	_files_by_scrub_key.clear()
	_games_by_scrub_name.clear()
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
	# Author vocabulary: every author token the db itself names,
	# from every table file (any format - the vocabulary describes
	# people, not files). Built BEFORE the scrub indexes, whose
	# keys are computed with it.
	for avid: Variant in games_by_id.keys():
		var author_game_id: String = str(avid)
		for item: Variant in table_files_of(author_game_id):
			if item is Dictionary:
				var atf: Dictionary = item
				for author: String in str_array(atf.get("authors", [])):
					for tok: String in raw_tokens(author):
						_author_tokens[tok] = true
	# Scrub indexes (matcher round): game names and VPX table
	# fileNames reduced to match keys. Unlike the exact filename
	# index these keep EVERY claimant - the matcher reads the
	# claimant set to refuse keys two games share.
	for sgid: Variant in games_by_id.keys():
		var scrub_game_id: String = str(sgid)
		var name_key: String = match_key(str(game_dict(scrub_game_id).get("name", "")))
		if name_key != "":
			var ids: Array = []
			var existing_ids: Variant = _games_by_scrub_name.get(name_key, [])
			if existing_ids is Array:
				ids = existing_ids
			ids.append(scrub_game_id)
			_games_by_scrub_name[name_key] = ids
		for item: Variant in vpx_table_files_of(scrub_game_id):
			if item is Dictionary:
				var stf: Dictionary = item
				var sname: String = str(stf.get("fileName", stf.get("filename", "")))
				if sname == "":
					continue
				var file_key: String = match_key(sname)
				if file_key == "":
					continue
				var claimants: Array = []
				var existing_claims: Variant = _files_by_scrub_key.get(file_key, [])
				if existing_claims is Array:
					claimants = existing_claims
				claimants.append({"game_id": scrub_game_id, "table_file": stf})
				_files_by_scrub_key[file_key] = claimants
	source_path = path
	loaded = not games_by_id.is_empty()
	return loaded


func game_count() -> int:
	return games_by_id.size()


## Total VPX table files across every known game (dev/sanity stats).
func vpx_table_file_count() -> int:
	var n: int = 0
	for gid: Variant in games_by_id.keys():
		n += vpx_table_files_of(str(gid)).size()
	return n


## VPX table files carrying a VR feature tag (same rule TableBuild
## applies to a local build: "VR", "Mixed Reality", or "MR").
func vr_tagged_vpx_file_count() -> int:
	var n: int = 0
	for gid: Variant in games_by_id.keys():
		for item: Variant in vpx_table_files_of(str(gid)):
			if item is Dictionary:
				var tf: Dictionary = item
				var feats: PackedStringArray = VpsDatabase.str_array(tf.get("features", []))
				for f: String in feats:
					if f == "VR" or f == "Mixed Reality" or f == "MR":
						n += 1
						break
	return n


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


## Every db table file whose fileName reduces to the same match
## key as this file name - the decorated-filename matcher's raw
## material. The caller decides what the claimant set means: one
## claimant (or several of ONE game) identifies a game; claimants
## from two games make the key ambiguous and unusable.
func find_by_scrubbed_filename(file_name: String) -> Array:
	var key: String = match_key(file_name)
	if key == "":
		return []
	var v: Variant = _files_by_scrub_key.get(key, [])
	if v is Array:
		return v
	return []


## Db games whose NAME reduces to the same match key as this
## file name - for tables the db lists no fileName for at all.
func find_game_ids_by_scrubbed_name(file_name: String) -> Array[String]:
	var out: Array[String] = []
	var key: String = match_key(file_name)
	if key == "":
		return out
	var v: Variant = _games_by_scrub_name.get(key, [])
	if v is Array:
		var arr: Array = v
		for item: Variant in arr:
			out.append(str(item))
	return out
