class_name IpdbFacts
extends RefCounted

## The IPDB well of the enriched card back (CARDBACK round,
## item 3's second leg): parsing the Internet Pinball
## Database's machine pages and the on-disk cache the backs
## read. Pure logic - no nodes, no network. The fetch itself
## is IpdbFetcher's; this class owns the page's shape and
## the cache file's shape.
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
##             design, art, music, software, features,
##             fetched_at}},
##    "failed": {game_id: "why the last fetch failed"}}
## A game under "failed" is not cached - the next Fetch
## retries it (cache-first means facts-first, not
## failure-first).

const CACHE_PATH: String = "user://ipdb_cache.json"
const DEFAULT_BASE: String = "https://www.ipdb.org/machine.cgi?id="

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


## The page a game's facts come from. PVLDS_IPDB_BASE is
## the dev seam (the harness stub pattern, VpsDownloader's
## PVLDS_VPSDB_URL precedent).
static func page_url(ipdb_id: int) -> String:
	var base: String = OS.get_environment("PVLDS_IPDB_BASE")
	if base == "":
		base = DEFAULT_BASE
	return base + str(ipdb_id)


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
## the caller counts that as a failed fetch, not a game
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
## error - the backs simply show db rows until a Fetch.
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


## The fetch plan: [{game_id, ipdb_id}] for every library
## game with an IPDB id that has no cached facts - or every
## such game at all under force (the Refetch action). A
## cached game is never in a non-force plan.
static func fetch_plan(games: Array, facts: Dictionary, force: bool) -> Array:
	var out: Array = []
	for gv: Variant in games:
		var g: GameEntry = gv as GameEntry
		if g == null or g.ipdb_id <= 0:
			continue
		if not force and facts.has(g.game_id):
			continue
		out.append({"game_id": g.game_id, "ipdb_id": g.ipdb_id})
	return out
