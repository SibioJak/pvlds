class_name IpdbFacts
extends RefCounted

## The IPDB well of the enriched card back (CARDBACK round,
## item 3's second leg): parsing the Internet Pinball
## Database's machine pages and the on-disk cache the backs
## read. Pure logic - no nodes, no network.
##
## IPDBFIX round (2026-11-05): the app NO LONGER fetches
## from ipdb.org at all. The field convicted the live pass
## end to end - Chris's cache recorded 288 fetches, 288 x
## "HTTP 403 (result 0)": IPDB's bot wall refuses the
## app's requests outright, browser user agent
## notwithstanding. So the facts ship BUNDLED instead: a
## snapshot of every db-linked machine page, parsed with
## this class's own parser (data/ipdb/
## ipdb_cache_snapshot.json), seeds the user cache at
## boot. The parser stays as the snapshot's provenance
## and the core legs' witness; nothing in the app builds
## an ipdb.org URL or opens a request to one.
##
## The page's facts live in a labelled two-column table:
## rows of the form <tr><td ...><b>LABEL: </b></td>
## <td colspan=4 ...>VALUE</td></tr>. Verified against the
## page IPDB served for id=1267 (Indiana Jones) on
## 2026-11-05 with a browser user agent: Production ->
## "12,716 units (confirmed)", the Average Fun Rating cell
## carries "8.3 /10", Design by -> "Mark Ritchie, Doug
## Watson", Specialty -> "Widebody". A field the parse
## cannot extract stays ABSENT - never invented, never
## empty-stringed into the cache.
##
## The cache (user://ipdb_cache.json):
##   {"facts": {game_id: {units, fun_rating, specialty,
##             design, art, music, software, features}},
##    "failed": {game_id: "why the last fetch failed"}}
## The "failed" map is a CARDBACK-era remnant, kept for
## the file's shape: the bundled seed clears the entry of
## every game it fills, and nothing writes new ones now
## that the live fetch is retired.

const CACHE_PATH: String = "user://ipdb_cache.json"
const SNAPSHOT_PATH: String = "res://data/ipdb/ipdb_cache_snapshot.json"

## Label (as served, trailing space and all) -> raw key.
const LABELS: Dictionary = {
	"Production: ": "units_raw",
	"Average Fun Rating: ": "fun_raw",
	"Specialty: ": "specialty",
	"Design by: ": "design",
	"Art by: ": "art",
	"Music by: ": "music",
	"Software by: ": "software",
	"Notable Features: ": "features",
}


## The numeric id inside a db ipdbUrl
## ("https://www.ipdb.org/machine.cgi?id=1267" -> 1267);
## 0 when the URL carries none.
static func ipdb_id_from_url(url: String) -> int:
	if url == "":
		return 0
	var re: RegEx = RegEx.new()
	re.compile("[?&]id=(\\d+)")
	var m: RegExMatch = re.search(url)
	if m == null:
		return 0
	return int(m.get_string(1))


## Parse one served machine page into its facts dictionary
## (string values only). {} when nothing at all extracts -
## the snapshot builder counts that as no data, not a game
## with no facts.
static func parse_page(html: String) -> Dictionary:
	var facts: Dictionary = {}
	for label: Variant in LABELS.keys():
		var raw: String = _cell_text(html, str(label))
		if raw == "":
			continue
		match str(LABELS[label]):
			"units_raw":
				var units: String = _first_match(raw, "([\\d,]+)\\s*units")
				if units == "":
					units = _first_match(raw, "^([\\d,]+)")
				if units != "":
					facts["units"] = units
			"fun_raw":
				var fun: String = _first_match(raw, "(\\d+(?:\\.\\d+)?)\\s*/\\s*10")
				if fun != "":
					facts["fun_rating"] = fun
			_:
				facts[str(LABELS[label])] = raw
	return facts


## The text of the value cell that follows a "<b>LABEL</b>"
## label cell: tags stripped, entities decoded, whitespace
## collapsed, punctuation spacing tidied ("Ritchie , Doug"
## -> "Ritchie, Doug", "( confirmed )" -> "(confirmed)").
static func _cell_text(html: String, label: String) -> String:
	var i: int = html.find("<b>" + label + "</b>")
	if i < 0:
		return ""
	var label_end: int = html.find("</td>", i)
	if label_end < 0:
		return ""
	var td: int = html.find("<td", label_end)
	if td < 0:
		return ""
	var cell_end: int = html.find("</td>", td)
	if cell_end < 0:
		return ""
	return _strip_markup(html.substr(td, cell_end - td))


static func _strip_markup(seg: String) -> String:
	var re_br: RegEx = RegEx.new()
	re_br.compile("(?i)<br[^>]*>")
	seg = re_br.sub(seg, " ", true)
	var re_tag: RegEx = RegEx.new()
	re_tag.compile("<[^>]+>")
	seg = re_tag.sub(seg, "", true)
	seg = seg.replace("&nbsp;", " ")
	seg = seg.replace("&amp;", "&")
	seg = seg.replace("&quot;", "\"")
	seg = seg.replace("&#39;", "'")
	seg = seg.replace("&apos;", "'")
	seg = seg.replace("&lt;", "<")
	seg = seg.replace("&gt;", ">")
	seg = seg.replace("&mdash;", "-")
	var re_ws: RegEx = RegEx.new()
	re_ws.compile("\\s+")
	seg = re_ws.sub(seg, " ", true)
	seg = seg.replace(" ,", ",")
	seg = seg.replace("( ", "(")
	seg = seg.replace(" )", ")")
	return seg.strip_edges()


static func _first_match(text: String, pattern: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile(pattern)
	var m: RegExMatch = re.search(text)
	if m == null:
		return ""
	return m.get_string(1)


## Load the cache file: {"facts": {...}, "failed": {...}}.
## A missing or unreadable file is an empty cache, not an
## error - the backs simply show db rows until the bundled
## snapshot seeds it (Main seeds at boot).
static func load_cache(path: String = CACHE_PATH) -> Dictionary:
	var out: Dictionary = {"facts": {}, "failed": {}}
	if not FileAccess.file_exists(path):
		return out
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return out
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return out
	var d: Dictionary = parsed
	if d.get("facts") is Dictionary:
		out["facts"] = d["facts"]
	if d.get("failed") is Dictionary:
		out["failed"] = d["failed"]
	return out


static func save_cache(cache: Dictionary, path: String = CACHE_PATH) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(cache))
	f.close()
	return true


## The bundled snapshot: the cache's own shape, parsed off
## the shipped data file. A missing or unreadable snapshot
## is an empty one - the backs simply show db rows, the
## same honest degrade as an empty cache.
static func load_snapshot(path: String = SNAPSHOT_PATH) -> Dictionary:
	return load_cache(path)


## IPDBFIX: merge the bundled snapshot into the user
## cache, in place. The law: the user's own facts WIN - a
## game the user cache already holds facts for is never
## overwritten; the snapshot fills every game the user
## cache lacks (or holds an empty entry for); and a game
## that stands with facts afterwards leaves the "failed"
## map, so a poisoned pre-fix cache (facts {} + hundreds
## of recorded 403s) heals in one boot. Returns how many
## games GAINED facts from the snapshot.
static func seed_from_snapshot(cache: Dictionary, snapshot: Dictionary) -> int:
	var facts: Dictionary = cache.get("facts", {}) as Dictionary
	var failed: Dictionary = cache.get("failed", {}) as Dictionary
	var snap_facts: Dictionary = snapshot.get("facts", {}) as Dictionary
	var gained: int = 0
	for game_id: Variant in snap_facts.keys():
		var snap_entry: Variant = snap_facts[game_id]
		if not (snap_entry is Dictionary) or (snap_entry as Dictionary).is_empty():
			continue
		var held: Variant = facts.get(game_id, null)
		if held is Dictionary and not (held as Dictionary).is_empty():
			continue # the user's facts stand
		facts[game_id] = (snap_entry as Dictionary).duplicate(true)
		gained += 1
	for game_id2: Variant in facts.keys():
		failed.erase(game_id2)
	cache["facts"] = facts
	cache["failed"] = failed
	return gained


## [have, want] over a library: want = games carrying an
## IPDB id, have = those among them with cached facts. The
## coverage health line's two numbers.
static func coverage(games: Array, facts: Dictionary) -> Array:
	var want: int = 0
	var have: int = 0
	for gv: Variant in games:
		var g: GameEntry = gv as GameEntry
		if g == null or g.ipdb_id <= 0:
			continue
		want += 1
		if facts.has(g.game_id):
			have += 1
	return [have, want]

