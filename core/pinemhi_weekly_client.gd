class_name PinemhiWeeklyClient
extends Node

## The PINemHi weekly-boards client (PINEMHI2, Part A).
##
## PINemHi runs three weekly contests on public pages -
## no login, plain HTML standings tables:
##   week_challenge.php       Weekly Competition
##   week_challenge_5min.php  Weekly 5-Minute Mode
##   week_challenge_golf.php  Weekly Golf (closest to the
##                            pin: rows carry a DISTANCE,
##                            not a score, ranked closest
##                            first by the site itself)
## Each page names its table, its contest window, and
## (golf) the pin its distances are measured from.
##
## The discipline mirrors WovpClient's: typed fail-closed
## parsing (a page that does not read as the expected
## shape answers not-ok with the reason stated, never a
## half-built board), plain-word errors that quote the
## server's own words where sensible, and a last-good
## cache (user://pinemhi_cache.json) holding the three
## raw page bodies - a load re-parses through the same
## parser, so a corrupt cache is no cache.
##
## The fetch is sequential, one page at a time, and the
## answer comes once: every contest that read cleanly,
## or a stated failure naming each page that did not.
## A page that fails leaves its contest absent - partial
## boards are never dressed as a live fetch.

signal weekly_finished(ok: bool, message: String, contests: Array, raw_pages: Dictionary)

const BASE_URL: String = "https://www.pinemhi.com/"
const PATH_MAIN: String = "week_challenge.php"
const PATH_FIVE: String = "week_challenge_5min.php"
const PATH_GOLF: String = "week_challenge_golf.php"
const CONTEST_IDS: Array[String] = ["main", "five", "golf"]
const CONTEST_LABELS: Dictionary = {
	"main": "Weekly Competition",
	"five": "Weekly 5-Minute Mode",
	"golf": "Weekly Golf",
}
const CONTEST_PATHS: Dictionary = {
	"main": PATH_MAIN,
	"five": PATH_FIVE,
	"golf": PATH_GOLF,
}
const REQUEST_TIMEOUT_SEC: float = 30.0
const ERROR_BODY_MAX_CHARS: int = 200 ## how much of the server's own answer an error line will quote before the quote is cut and the cut is stated

const CACHE_FILE_NAME: String = "pinemhi_cache.json"

## Negative-control seam (harness env PVLDS_PINEMHI2_NC,
## set by Main before any request): "golfscore" - the
## parser reads golf distances AS scores (sign stripped,
## dots to int, the board text comma-formatted), so the
## pinemhi2 smoke's golf-shape leg fails by name;
## "stale" is Main's half (its push claims a cache-served
## board is live - see Main._push_pinemhi2_data).
## Production never sets this.
static var debug_nc: String = ""

var _http: HTTPRequest
var _busy: bool = false
var _fetch_index: int = 0
var _pages: Dictionary = {} ## contest id -> raw body, this fetch
var _contests: Array = [] ## parsed contests, this fetch
var _failures: Array[String] = [] ## per-page failure words, this fetch


func _init() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = REQUEST_TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## The base URL for the three pages. The
## PVLDS_PINEMHI_BASE_URL dev seam (the harness's local
## stub) overrides it, mirroring WovpClient.base_url -
## harness runs never touch the real site.
static func base_url() -> String:
	var override: String = OS.get_environment("PVLDS_PINEMHI_BASE_URL")
	if override != "":
		return override if override.ends_with("/") else override + "/"
	return BASE_URL


func is_busy() -> bool:
	return _busy


## Fetch all three weekly pages, in order, and answer
## once through weekly_finished: ok only when every page
## arrived and parsed; otherwise the message names each
## page that failed and why, and the contests that DID
## read cleanly still ride along (Main's failure path
## keeps the last good boards standing either way).
func fetch_weekly() -> void:
	if _busy:
		weekly_finished.emit(false, "Another PINemHi request is already running - one moment.", [], {})
		return
	_busy = true
	_fetch_index = 0
	_pages = {}
	_contests = []
	_failures = []
	_start_next()


func _start_next() -> void:
	if _fetch_index >= CONTEST_IDS.size():
		_finish_fetch()
		return
	var cid: String = CONTEST_IDS[_fetch_index]
	var url: String = base_url() + str(CONTEST_PATHS[cid])
	var err: Error = _http.request(url)
	if err != OK:
		_failures.append("%s: could not start the request (error %d)" % [str(CONTEST_LABELS[cid]), err])
		_fetch_index += 1
		_start_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var cid: String = CONTEST_IDS[_fetch_index]
	var label: String = str(CONTEST_LABELS[cid])
	if result != HTTPRequest.RESULT_SUCCESS:
		var why: String = "could not reach PINemHi - check the network connection"
		if result == HTTPRequest.RESULT_TIMEOUT:
			why = "PINemHi did not answer in time"
		elif result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CONNECTION_ERROR:
			why = "could not connect to PINemHi - check the network connection"
		_failures.append("%s: %s" % [label, why])
	elif response_code != 200:
		var why: String = "PINemHi answered with an error (HTTP %d)" % response_code
		var words: String = server_words(body)
		if words != "":
			why += " - PINemHi said: " + words
		_failures.append("%s: %s" % [label, why])
	else:
		var text: String = body.get_string_from_utf8()
		var parsed: Dictionary = parse_page(text, cid)
		if bool(parsed.get("ok", false)):
			_pages[cid] = text
			_contests.append(parsed["contest"])
		else:
			_failures.append("%s: %s" % [label, str(parsed.get("error", "the page could not be read"))])
	_fetch_index += 1
	_start_next()


func _finish_fetch() -> void:
	_busy = false
	if _failures.is_empty() and _contests.size() == CONTEST_IDS.size():
		weekly_finished.emit(true, "", _contests, _pages)
		return
	var message: String = "The PINemHi weekly boards could not be fetched in full."
	if not _failures.is_empty():
		message += " " + "; ".join(_failures) + "."
	weekly_finished.emit(false, message, _contests, _pages)


## The server's own words out of an error response's body,
## fit to ride a status line (WovpClient.server_words'
## shape): tags stripped, entities decoded, line breaks
## flattened, and past ERROR_BODY_MAX_CHARS the quote is
## cut and the cut is stated. An empty body answers "".
static func server_words(body: PackedByteArray) -> String:
	var text: String = clean_text(body.get_string_from_utf8())
	if text.length() > ERROR_BODY_MAX_CHARS:
		text = text.substr(0, ERROR_BODY_MAX_CHARS).strip_edges() + "... (PINemHi's answer was longer - cut off here.)"
	return text


# ------------------------------------------------------------ parsing

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


## Strip tags and decode the common HTML entities, then
## flatten whitespace: the one cleaning every extracted
## cell and line passes through.
static func clean_text(s: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("<[^>]*>")
	var t: String = re.sub(s, "", true)
	t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"") \
		.replace("&#39;", "'").replace("&nbsp;", " ").replace("&amp;", "&")
	t = t.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges()


## The text of the element whose opening tag contains
## marker (e.g. <b class="game-name">): everything from
## the tag's close to the next tag, cleaned. "" when the
## marker is absent.
static func _element_text(html: String, marker: String) -> String:
	var i: int = html.find(marker)
	if i < 0:
		return ""
	var gt: int = html.find(">", i)
	if gt < 0:
		return ""
	var close: int = html.find("<", gt)
	if close < 0:
		return ""
	return clean_text(html.substr(gt + 1, close - gt - 1))


## Parse one weekly page into its contest Dictionary:
## {"id", "label", "table", "window_start", "window_end",
## "pin", "rows": [{"pos", "name", "value", "value_text",
## "rom", "date"} (+ "hole_in_one" on a golf ace)]}.
## Fails closed per page: no table name, no window, or no
## recognisable interim-standings table is a stated
## failure, never a half-built contest. Only the FIRST
## leaderboard table after "Interim Standings" is read -
## every page carries a second one (previous winners)
## that is never this contest's standings.
static func parse_page(html: String, contest_id: String) -> Dictionary:
	var label: String = str(CONTEST_LABELS.get(contest_id, contest_id))
	var table: String = _element_text(html, "<b class=\"game-name\">")
	if table == "":
		return _fail("the %s page named no table" % label)
	var range_text: String = _element_text(html, "<i class=\"date-range\">")
	var win_parts: PackedStringArray = range_text.split(" --- ")
	if win_parts.size() != 2 or win_parts[0].strip_edges() == "" or win_parts[1].strip_edges() == "":
		return _fail("the %s page carried no contest window" % label)
	var window_start: String = win_parts[0].strip_edges()
	var window_end: String = win_parts[1].strip_edges()
	var pin: String = ""
	if contest_id == "golf":
		var pi: int = html.find("PIN IS SET AT:")
		if pi >= 0:
			var rest: String = clean_text(html.substr(pi + "PIN IS SET AT:".length(), 96))
			if rest != "":
				pin = rest.split(" ")[0]
	var si: int = html.find("Interim Standings")
	if si < 0:
		return _fail("the %s page carried no interim standings" % label)
	var ti: int = html.find("<table class=\"leaderboard-table\">", si)
	if ti < 0:
		return _fail("the %s page carried no standings table" % label)
	var te: int = html.find("</table>", ti)
	if te < 0:
		return _fail("the %s page's standings table never closed" % label)
	var table_html: String = html.substr(ti, te - ti)
	var tr_re: RegEx = RegEx.new()
	tr_re.compile("(?s)<tr[^>]*>(.*?)</tr>")
	var td_re: RegEx = RegEx.new()
	td_re.compile("(?s)<t[dh][^>]*>(.*?)</t[dh]>")
	var trs: Array[RegExMatch] = tr_re.search_all(table_html)
	if trs.is_empty():
		return _fail("the %s page's standings table carried no rows" % label)
	var header: Array[String] = _row_cells(trs[0].get_string(1), td_re)
	if header.size() < 6 or not header[0].begins_with("Pos"):
		return _fail("the %s page's standings header was not recognised" % label)
	if contest_id == "golf":
		if not header[1].contains("Distance"):
			return _fail("the %s page's standings header named no distance column" % label)
	elif header[1] != "Score":
		return _fail("the %s page's standings header named no score column" % label)
	var rows: Array = []
	for ri: int in range(1, trs.size()):
		var cells: Array[String] = _row_cells(trs[ri].get_string(1), td_re)
		if cells.size() < 6:
			return _fail("a standings row on the %s page carried too few columns" % label)
		if not cells[0].is_valid_int():
			return _fail("a standings row on the %s page carried no position" % label)
		var row: Dictionary = _parse_value_cell(cells[1], contest_id, label)
		if not bool(row.get("ok", false)):
			return row
		row.erase("ok")
		row["pos"] = cells[0].to_int()
		row["name"] = cells[3]
		row["rom"] = cells[4]
		row["date"] = cells[5]
		rows.append(row)
	return {"ok": true, "contest": {
		"id": contest_id,
		"label": label,
		"table": table,
		"window_start": window_start,
		"window_end": window_end,
		"pin": pin,
		"rows": rows,
	}}


static func _row_cells(tr_html: String, td_re: RegEx) -> Array[String]:
	var out: Array[String] = []
	var matches: Array[RegExMatch] = td_re.search_all(tr_html)
	for m: RegExMatch in matches:
		out.append(clean_text(m.get_string(1)))
	return out


## One value cell -> {"ok", "value", "value_text"} (+
## "hole_in_one" on a golf ace). Score pages carry
## dot-grouped scores ("8.014.130" -> 8014130, the dotted
## string kept verbatim in value_text); golf carries
## signed distances ("-620", "-1.450") or the words
## "Hole in One" (value 0, flagged). Golf NEVER takes
## the score shape in production - only behind the
## golfscore negative control, which exists to break
## that law by name.
static func _parse_value_cell(cell: String, contest_id: String, label: String) -> Dictionary:
	if contest_id == "golf" and debug_nc == "golfscore":
		if cell == "Hole in One":
			return {"ok": true, "value": 0, "value_text": "0"}
		var nc_digits: String = cell.trim_prefix("-").trim_prefix("+").replace(".", "")
		if nc_digits == "" or not nc_digits.is_valid_int():
			return _fail("a distance on the %s page could not be read ('%s')" % [label, cell])
		var nc_value: int = nc_digits.to_int()
		return {"ok": true, "value": nc_value, "value_text": WovpChallenge.format_score(float(nc_value))}
	if contest_id == "golf":
		if cell == "Hole in One":
			return {"ok": true, "value": 0, "value_text": cell, "hole_in_one": true}
		var neg: bool = cell.begins_with("-")
		var g_digits: String = cell.trim_prefix("-").trim_prefix("+").replace(".", "")
		if g_digits == "" or not g_digits.is_valid_int():
			return _fail("a distance on the %s page could not be read ('%s')" % [label, cell])
		var g_value: int = g_digits.to_int()
		return {"ok": true, "value": -g_value if neg else g_value, "value_text": cell}
	var digits: String = cell.replace(".", "")
	if digits == "" or not digits.is_valid_int():
		return _fail("a score on the %s page could not be read ('%s')" % [label, cell])
	return {"ok": true, "value": digits.to_int(), "value_text": cell}


# ------------------------------------------------------------ the last-good cache

static func cache_path() -> String:
	return "user://".path_join(CACHE_FILE_NAME)


## The boards' memory of the last good fetch: the three
## raw page bodies plus when they landed. Written only
## on a fully successful fetch.
static func save_cache(pages: Dictionary, fetched_at: int) -> bool:
	var d: Dictionary = {"fetched_at": fetched_at, "pages": pages}
	var f: FileAccess = FileAccess.open(cache_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true


## Read the cache back: the stored pages re-parse through
## the same fail-closed parser (a corrupt cache is no
## cache). A page that no longer parses drops its contest;
## no parseable contest at all is no cache.
static func load_cache() -> Dictionary:
	if not FileAccess.file_exists(cache_path()):
		return {"ok": false, "error": "no cache"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path()))
	if not (parsed is Dictionary):
		return {"ok": false, "error": "the saved PINemHi data was not readable"}
	var d: Dictionary = parsed
	var pages_raw: Variant = d.get("pages")
	if not (pages_raw is Dictionary):
		return {"ok": false, "error": "the saved PINemHi data carried no pages"}
	var pages: Dictionary = pages_raw
	var contests: Array = []
	for cid: String in CONTEST_IDS:
		var body: String = str(pages.get(cid, ""))
		if body == "":
			continue
		var one: Dictionary = parse_page(body, cid)
		if bool(one.get("ok", false)):
			contests.append(one["contest"])
	if contests.is_empty():
		return {"ok": false, "error": "the saved PINemHi data could not be read"}
	return {
		"ok": true,
		"contests": contests,
		"fetched_at": int(d.get("fetched_at", 0)),
		"pages": pages,
	}
