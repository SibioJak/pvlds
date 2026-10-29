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
var _author_tokens: Dictionary = {} ## token -> true, from every db table file's authors (the matcher's author vocabulary)
var _files_by_slug_key: Dictionary = {} ## slug match key of a VPX table file's download URL -> Array of {game_id, table_file} claiming it
var _games_by_scrub_name: Dictionary = {} ## match key of a db game name -> Array of game ids
var _games_by_edition_key: Dictionary = {} ## edition key (full name, edition words kept) of a db game name -> Array of game ids
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
	"fullscreen": true, "pinemhi": true,
}

## Extra words a download-page slug carries that a local file name
## never does in the same place: VPS download slugs bake the VR-room
## and conversion tags straight into the title run ("vr-room-<title>",
## "<title>-<maker>-<year>-ext2k-conversion"). Dropped from the SLUG
## side only, on top of the shared decoration vocabulary.
const SLUG_EXTRA_TOKENS: Dictionary = {
	"conversion": true, "room": true, "vrroom": true,
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
## get the same treatment, so equality survives it). A trailing
## VR-room suffix drops too - "Apollo 13 w Room" and plain
## "Apollo 13" are the same table - narrowly, at the very end of
## the name only, so a "Room" inside a title is never eaten; a
## genuine title ENDING in "Room" still meets itself because the
## game's own name gets the identical treatment, and a collision
## with a room-less twin is refused by the ambiguity rules.
static func scrub_tokens(s: String) -> PackedStringArray:
	return _tokens_of(string_scrub(s))


## The shared tail of both token views: tokenize a scrubbed
## string, drop decoration words, a leading "The", and a
## trailing VR-room suffix.
static func _tokens_of(t: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for tok: String in raw_tokens(t):
		if DECORATION_TOKENS.has(tok):
			continue
		out.append(tok)
	if not out.is_empty() and out[0] == "the":
		out.remove_at(0)
	if out.size() >= 2 and out[out.size() - 1] == "room":
		out.remove_at(out.size() - 1)
		if not out.is_empty() and out[out.size() - 1] == "w":
			out.remove_at(out.size() - 1)
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


## Whether a "(...)" segment carries a year-shaped number - the
## mark of the "(Maker Year)" convention, as the scanner's parens
## referee reads it.
static func _segment_has_year(seg: String) -> bool:
	var year_re: RegEx = RegEx.new()
	year_re.compile("(19|20)\\d\\d")
	return year_re.search(seg) != null


## String-level scrub for the EDITION key: string_scrub's sibling,
## but "(...)" segments are not deleted wholesale. A segment
## carrying a year is "(Maker Year)" meta and drops - the
## scanner's parens referee judges it separately; a segment
## without a year ("(LUCI Premium)", "(Remake)") is part of the
## name the file states, and its words stay in the token stream,
## in place. With keep_meta_parens set - the GAME side, whose
## names are authoritative - every segment's words stay: a db
## edition may itself carry a year ("(1986)"), and the game's
## key must keep what the game's name says. Bracket groups,
## version substrings and the " - Author" tail scrub exactly as
## in string_scrub.
static func string_scrub_edition(s: String, keep_meta_parens: bool) -> String:
	var t: String = s.replace("_", " ")
	var out: String = ""
	var i: int = 0
	while i < t.length():
		if t[i] == "(":
			var close: int = t.find(")", i)
			if close < 0:
				break ## unbalanced: the rest states nothing usable
			var seg: String = t.substr(i + 1, close - i - 1)
			if keep_meta_parens or not _segment_has_year(seg):
				out += " " + seg + " "
			i = close + 1
		else:
			out += t[i]
			i += 1
	t = out
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


## The edition-aware token view of a name: scrub_tokens' sibling
## over string_scrub_edition - the full token stream, edition
## words included, with the same decoration shedding.
static func edition_tokens(s: String, keep_meta_parens: bool) -> PackedStringArray:
	return _tokens_of(string_scrub_edition(s, keep_meta_parens))


## This database's EDITION match key for a name: the full token
## stream - base title AND edition words - reduced like
## match_key (the db's author tokens removed as well; author
## removal never empties a key). Two names share an edition key
## only when they state the same title and the same edition:
## "AC-DC LUCI Premium" and the db's "AC/DC (LUCI Premium)" meet
## here, while "AC/DC (Pro)" and the plain "AC/DC" never do.
func edition_key(s: String, keep_meta_parens: bool) -> String:
	var toks: PackedStringArray = edition_tokens(s, keep_meta_parens)
	var kept: PackedStringArray = PackedStringArray()
	for tok: String in toks:
		if not _author_tokens.has(tok):
			kept.append(tok)
	if kept.is_empty():
		kept = toks
	return "".join(kept)


## The slug of a VPS download URL: vpuniverse file pages are
## ".../files/file/<numeric-id>-<slug>/", and the slug bakes in
## title + maker + year + authors ("quasar-queen-starlite-1982-
## zippy"). "" when the URL carries no slug (a vpforums showfile
## link names nothing) - such a table file simply has no slug key.
static func slug_from_url(url: String) -> String:
	var marker: String = "/files/file/"
	var at: int = url.find(marker)
	if at < 0:
		return ""
	var rest: String = url.substr(at + marker.length())
	var slash: int = rest.find("/")
	var segment: String = rest if slash < 0 else rest.substr(0, slash)
	segment = segment.uri_decode()
	var dash: int = segment.find("-")
	if dash <= 0 or not segment.substr(0, dash).is_valid_int():
		return ""
	return segment.substr(dash + 1)


## A table file's slug match key: its download slug reduced like a
## file name, plus the slug-specific shedding - the game's own
## maker tokens and year token (the local side's scrub removes
## the file's "(Maker Year)" parens wholesale, so the slug side
## must shed the same facts to meet it), the slug-extra words,
## and author tokens. "" when the file has no slug URL.
func slug_match_key(game: Dictionary, tf: Dictionary) -> String:
	var slug: String = ""
	var urls_v: Variant = tf.get("urls", [])
	if urls_v is Array:
		var url_list: Array = urls_v
		for entry: Variant in url_list:
			var u: String = ""
			if entry is Dictionary:
				var ed: Dictionary = entry
				u = str(ed.get("url", ""))
			elif entry is String:
				u = entry
			slug = slug_from_url(u)
			if slug != "":
				break
	if slug == "":
		return ""
	var drop: Dictionary = {}
	for tok: String in raw_tokens(str(game.get("manufacturer", ""))):
		drop[tok] = true
	var yr: int = int(game.get("year", 0))
	if yr > 0:
		drop[str(yr)] = true
	var toks: PackedStringArray = scrub_tokens(slug)
	var kept: PackedStringArray = PackedStringArray()
	for tok: String in toks:
		if drop.has(tok) or SLUG_EXTRA_TOKENS.has(tok) or _author_tokens.has(tok):
			continue
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
	_author_tokens.clear()
	_files_by_slug_key.clear()
	_games_by_scrub_name.clear()
	_games_by_edition_key.clear()
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
	# Scrub indexes: game names reduced to match keys, and VPX
	# table files indexed by the slug key of their download URL
	# (the real db names no table files - its download pages are
	# the filename-shaped evidence it actually carries). Both
	# indexes keep EVERY claimant - the matcher reads the
	# claimant set to refuse keys two games share.
	for sgid: Variant in games_by_id.keys():
		var scrub_game_id: String = str(sgid)
		var sgame: Dictionary = game_dict(scrub_game_id)
		var name_key: String = match_key(str(sgame.get("name", "")))
		if name_key != "":
			var ids: Array = []
			var existing_ids: Variant = _games_by_scrub_name.get(name_key, [])
			if existing_ids is Array:
				ids = existing_ids
			ids.append(scrub_game_id)
			_games_by_scrub_name[name_key] = ids
		var ed_key: String = edition_key(str(sgame.get("name", "")), true)
		if ed_key != "":
			var eids: Array = []
			var existing_eids: Variant = _games_by_edition_key.get(ed_key, [])
			if existing_eids is Array:
				eids = existing_eids
			eids.append(scrub_game_id)
			_games_by_edition_key[ed_key] = eids
		for item: Variant in vpx_table_files_of(scrub_game_id):
			if item is Dictionary:
				var stf: Dictionary = item
				var slug_key: String = slug_match_key(sgame, stf)
				if slug_key == "":
					continue
				var claimants: Array = []
				var existing_claims: Variant = _files_by_slug_key.get(slug_key, [])
				if existing_claims is Array:
					claimants = existing_claims
				claimants.append({"game_id": scrub_game_id, "table_file": stf})
				_files_by_slug_key[slug_key] = claimants
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


## Every db table file whose download slug reduces to the same
## match key as this file name - the slug road's raw material.
## The caller decides what the claimant set means: one claimant
## (or several of ONE game) identifies a game; claimants from
## two games make the key ambiguous and unusable.
func find_by_slug(file_name: String) -> Array:
	var key: String = match_key(file_name)
	if key == "":
		return []
	var v: Variant = _files_by_slug_key.get(key, [])
	if v is Array:
		return v
	return []


## Db games whose NAME reduces to the same match key as this
## file name - for tables the db lists no usable download slug.
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


## Db games whose FULL name - parenthesized edition included -
## reduces to the same edition key as this file name: the file
## states the game's own edition words (trailing, or in a
## no-year paren) and they agree exactly. The caller decides
## what the claimant set means, as with the slug road: exactly
## one claimant identifies a game; several make the key
## ambiguous and unusable.
func find_game_ids_by_edition(file_name: String) -> Array[String]:
	var out: Array[String] = []
	var key: String = edition_key(file_name, false)
	if key == "":
		return out
	var v: Variant = _games_by_edition_key.get(key, [])
	if v is Array:
		var arr: Array = v
		for item: Variant in arr:
			out.append(str(item))
	return out
