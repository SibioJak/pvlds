class_name WovpClient
extends Node

## The World of Virtual Pinball client - READ SIDE ONLY.
## Two calls exist here, the two the Tournament Room's wall
## needs (contract: the scores spike, FINDINGS.md, from VPin
## Studio's published connector source):
##   POST validate-apikey   - whose key is this?
##   POST challenges/search - every in-progress challenge
##                            with its full scoreboard
## There is deliberately NO submission code in this file -
## no submit endpoint is named, let alone called (the round's
## scope, 2026-10-28: read side first, zero submission risk).
##
## Honesty rules this file lives by:
## - X-Client-ID identifies PVLDS as itself ("pvlds"). It
##   never sends Studio's id - that would be impersonation.
## - The API key is a secret: it rides only in the request
##   it belongs to (the validate body, the search Bearer
##   header) and in the local config file. It is never
##   printed, never put in an error message, never written
##   anywhere else. The harness runs a sentinel key through
##   every path and greps the logs for it.
## - Parsing is typed and null-safe and fails CLOSED: a
##   malformed payload answers not-ok with a stated reason,
##   never a half-built board. Unknown extra fields are
##   ignored (the league's own mapper ignores them too);
##   missing or mistyped required fields fail.

signal validation_finished(ok: bool, message: String, user_id: String, display_name: String)
signal challenges_finished(ok: bool, message: String, challenges: Array, raw_body: String)

const BASE_URL: String = "https://worldofvirtualpinball.com/api/whsc/v1/"
const VALIDATE_PATH: String = "validate-apikey"
const CHALLENGES_PATH: String = "challenges/search"
const CLIENT_ID: String = "pvlds"
const REQUEST_TIMEOUT_SEC: float = 30.0 ## Studio's request timeout (spike); its connect timeout maps to the same budget headless

const CACHE_FILE_NAME: String = "wovp_cache.json"

## Negative-control seam (harness env PVLDS_WOVP_NC=clientid,
## set by Main before any request): send Studio's client id
## instead of PVLDS's own, so the tournament smoke's honesty
## leg fails by name. Production never sets this.
static var debug_client_id_override: String = ""

var _http: HTTPRequest
var _busy: bool = false
var _pending_kind: String = "" ## "validate" | "search"


func _init() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = REQUEST_TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## The base URL for both calls. The PVLDS_WOVP_BASE_URL dev
## seam (the harness's local stub) overrides it, mirroring
## the VPS downloader's PVLDS_VPSDB_URL seam - harness runs
## never touch the real league.
static func base_url() -> String:
	var override: String = OS.get_environment("PVLDS_WOVP_BASE_URL")
	if override != "":
		return override if override.ends_with("/") else override + "/"
	return BASE_URL


static func client_id() -> String:
	return debug_client_id_override if debug_client_id_override != "" else CLIENT_ID


func is_busy() -> bool:
	return _busy


## POST validate-apikey: no Bearer header (the key rides in
## the body - that IS the request), Content-Type + our own
## X-Client-ID. The answer names whose key it is.
func validate_key(api_key: String) -> void:
	if _busy:
		validation_finished.emit(false, "Another WoVP request is already running - one moment.", "", "")
		return
	if api_key.strip_edges() == "":
		validation_finished.emit(false, "No WoVP key to test - paste one first.", "", "")
		return
	_busy = true
	_pending_kind = "validate"
	var body: String = JSON.stringify({"apikey": api_key})
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"X-Client-ID: " + client_id(),
	])
	var err: Error = _http.request(base_url() + VALIDATE_PATH, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_pending_kind = ""
		validation_finished.emit(false, "Could not start the request to WoVP (error %d)." % err, "", "")


## POST challenges/search with Studio's own Search defaults
## (the spike's captured body: in-progress challenges only,
## scoreboards and table identities expanded) and the key as
## Bearer. The response carries every live board at once.
func fetch_challenges(api_key: String) -> void:
	if _busy:
		challenges_finished.emit(false, "Another WoVP request is already running - one moment.", [], "")
		return
	if api_key.strip_edges() == "":
		challenges_finished.emit(false, "No WoVP key saved - add it in SETUP first.", [], "")
		return
	_busy = true
	_pending_kind = "search"
	var body: String = search_body()
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"X-Client-ID: " + client_id(),
		"Authorization: Bearer " + api_key,
	])
	var err: Error = _http.request(base_url() + CHALLENGES_PATH, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		_pending_kind = ""
		challenges_finished.emit(false, "Could not start the request to WoVP (error %d)." % err, [], "")


## Studio's Search body, field for field (its models/Search
## + models/Filters defaults): the league is asked for
## in-progress challenges (status 1) with the scoreboard,
## table, version and keyword expansions the wall reads.
## Deliberately carries no key material - the core test
## asserts that with a sentinel.
static func search_body() -> String:
	return JSON.stringify({
		"cultureCode": "en",
		"filters": {"statuses": [1], "inProgress": true},
		"expands": [
			"challenge.scoreboard",
			"challenge.scoreboard.participantProfilePicture",
			"challenge.pinballTableVersion.minimum",
			"challenge.pinballTable.minimum",
			"challenge.scriptMatchKeywords",
		],
	})


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind: String = _pending_kind
	_busy = false
	_pending_kind = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		var why: String = "Could not reach WoVP - check the network connection."
		if result == HTTPRequest.RESULT_TIMEOUT:
			why = "WoVP did not answer in time."
		elif result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CONNECTION_ERROR:
			why = "Could not connect to WoVP - check the network connection."
		if kind == "validate":
			validation_finished.emit(false, why, "", "")
		else:
			challenges_finished.emit(false, why, [], "")
		return
	if response_code != 200:
		var why: String = "WoVP answered with an error (HTTP %d)." % response_code
		if response_code == 401 or response_code == 403:
			why = "WoVP did not accept that key (HTTP %d)." % response_code
		if kind == "validate":
			validation_finished.emit(false, why, "", "")
		else:
			challenges_finished.emit(false, why, [], "")
		return
	var text: String = body.get_string_from_utf8()
	if kind == "validate":
		var v: Dictionary = parse_validation(text)
		if bool(v.get("ok", false)):
			validation_finished.emit(true, "", str(v.get("user_id", "")), str(v.get("display_name", "")))
		else:
			validation_finished.emit(false, str(v.get("error", "WoVP's answer could not be read.")), "", "")
	else:
		var c: Dictionary = parse_challenges(text)
		if bool(c.get("ok", false)):
			challenges_finished.emit(true, "", c.get("challenges", []), text)
		else:
			challenges_finished.emit(false, str(c.get("error", "WoVP's answer could not be read.")), [], "")


# ------------------------------------------------------------ parsing

## Case-insensitive field read: Studio's Jackson mapper is
## case-insensitive and the wire's exact casing is unproven
## (the spike's models even mix cases - approvalNote is
## camelCase among PascalCase), so every payload read goes
## through a lowercased view. Unknown fields are simply
## never read.
static func _ci(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d.keys():
		out[str(k).to_lower()] = d[k]
	return out


static func _ci_str(d: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = d.get(key.to_lower())
	if v is String:
		return v
	if v == null:
		return fallback
	return str(v)


static func _ci_int(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v: Variant = d.get(key.to_lower())
	if v is int:
		return v
	if v is float:
		return int(v)
	return fallback


static func _ci_float(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	var v: Variant = d.get(key.to_lower())
	if v is float:
		return v
	if v is int:
		return float(v)
	return fallback


static func _ci_bool(d: Dictionary, key: String, fallback: bool = false) -> bool:
	var v: Variant = d.get(key.to_lower())
	if v is bool:
		return v
	return fallback


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}


## Parse a validate-apikey response body:
## {success, userId, firstName, lastName} (the spike's
## ApiKeyValidationResponse). success=false is a stated
## refusal, not a parse failure; a body that is not that
## shape at all fails closed.
static func parse_validation(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return _fail("WoVP's answer was not readable (not the expected shape).")
	var d: Dictionary = _ci(parsed)
	if not (d.get("success") is bool):
		return _fail("WoVP's answer was not readable (no success flag).")
	if not bool(d["success"]):
		return {"ok": false, "error": "WoVP did not accept that key.", "refused": true}
	var user_id: String = _ci_str(d, "userId")
	if user_id == "":
		return _fail("WoVP accepted the key but named no player for it.")
	var first: String = _ci_str(d, "firstName")
	var last: String = _ci_str(d, "lastName")
	var display: String = (first + " " + last).strip_edges()
	if display == "":
		display = user_id
	return {"ok": true, "user_id": user_id, "display_name": display}


## Parse a challenges/search response body into typed
## challenges. Fails closed (whole payload, stated reason)
## on: unreadable JSON, no items list, a challenge that is
## not an object, a missing/unknown type, a missing or
## unparseable end date, a missing table identity, or a
## scoreboard row without a position, score, or player id.
static func parse_challenges(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return _fail("WoVP's answer was not readable (not the expected shape).")
	var top: Dictionary = _ci(parsed)
	var items: Variant = top.get("items")
	if not (items is Array):
		return _fail("WoVP's answer carried no challenge list.")
	var out: Array = []
	var arr: Array = items
	for i: int in range(arr.size()):
		var one: Dictionary = _parse_challenge(arr[i], i)
		if not bool(one.get("ok", false)):
			return one
		out.append(one["challenge"])
	return {"ok": true, "challenges": out}


static func _parse_challenge(raw: Variant, idx: int) -> Dictionary:
	if not (raw is Dictionary):
		return _fail("Challenge %d in WoVP's answer was not an object." % (idx + 1))
	var d: Dictionary = _ci(raw)
	var challenge: WovpChallenge = WovpChallenge.new()
	challenge.challenge_id = _ci_str(d, "id")
	if challenge.challenge_id == "":
		return _fail("Challenge %d in WoVP's answer carried no id." % (idx + 1))
	challenge.type_code = _ci_str(d, "challengeTypeCode")
	if not WovpChallenge.KNOWN_TYPES.has(challenge.type_code):
		return _fail("Challenge '%s' has a type PVLDS does not know ('%s')." % [challenge.challenge_id, challenge.type_code])
	challenge.season_challenge_id = _ci_str(d, "seasonChallengeId")
	challenge.name = _ci_str(d, "name")
	challenge.description = _ci_str(d, "description")
	var kw: Variant = d.get("scriptmatchkeywords")
	if kw is Array:
		var kwarr: Array = kw
		for item: Variant in kwarr:
			challenge.script_keywords.append(str(item))
	var start_text: String = _ci_str(d, "startDateUTC")
	if start_text != "":
		challenge.start_unix = parse_iso8601(start_text)
		if challenge.start_unix < 0:
			return _fail("Challenge '%s' has a start date PVLDS cannot read." % challenge.challenge_id)
	var end_text: String = _ci_str(d, "endDateUTC")
	if end_text == "":
		return _fail("Challenge '%s' carries no end date." % challenge.challenge_id)
	challenge.end_unix = parse_iso8601(end_text)
	if challenge.end_unix < 0:
		return _fail("Challenge '%s' has an end date PVLDS cannot read." % challenge.challenge_id)
	var table_raw: Variant = d.get("pinballtable")
	if not (table_raw is Dictionary):
		return _fail("Challenge '%s' carries no table." % challenge.challenge_id)
	var table: Dictionary = _ci(table_raw)
	challenge.table_id = _ci_str(table, "id")
	challenge.table_external_id = _ci_str(table, "externalId")
	if challenge.table_external_id == "":
		return _fail("Challenge '%s' names a table with no VPS id." % challenge.challenge_id)
	challenge.table_name = _ci_str(table, "name")
	challenge.table_manufacturer = _ci_str(table, "manufacturer")
	challenge.table_year = _ci_int(table, "year")
	var version_raw: Variant = d.get("pinballtableversion")
	if version_raw is Dictionary:
		var version: Dictionary = _ci(version_raw)
		challenge.version_id = _ci_str(version, "id")
		challenge.version_external_id = _ci_str(version, "externalId")
		challenge.version_name = _ci_str(version, "name")
	var board_raw: Variant = d.get("scoreboard")
	if board_raw is Dictionary:
		var board: Dictionary = _ci(board_raw)
		var rows_raw: Variant = board.get("items")
		if rows_raw is Array:
			var rows_arr: Array = rows_raw
			for j: int in range(rows_arr.size()):
				var row_parsed: Dictionary = _parse_row(rows_arr[j], challenge.challenge_id, j)
				if not bool(row_parsed.get("ok", false)):
					return row_parsed
				challenge.rows.append(row_parsed["row"])
	challenge.rows.sort_custom(func(a: WovpScoreRow, b: WovpScoreRow) -> bool: return a.position < b.position)
	return {"ok": true, "challenge": challenge}


static func _parse_row(raw: Variant, challenge_id: String, idx: int) -> Dictionary:
	if not (raw is Dictionary):
		return _fail("A scoreboard row on challenge '%s' was not an object." % challenge_id)
	var item: Dictionary = _ci(raw)
	var values_raw: Variant = item.get("values")
	if not (values_raw is Dictionary):
		return _fail("A scoreboard row on challenge '%s' carried no values." % challenge_id)
	var v: Dictionary = _ci(values_raw)
	var row: WovpScoreRow = WovpScoreRow.new()
	# Position and score are the board's skeleton: the item's
	# own position is the fallback, but one of the two must
	# carry a real number for both facts.
	if v.has("position"):
		row.position = _ci_int(v, "position", -1)
	elif item.has("position"):
		row.position = _ci_int(item, "position", -1)
	if row.position < 0:
		return _fail("A scoreboard row on challenge '%s' carried no position." % challenge_id)
	if not (v.get("score") is float or v.get("score") is int):
		return _fail("A scoreboard row on challenge '%s' carried no score." % challenge_id)
	row.score = _ci_float(v, "score")
	if not (v.get("userid") is String):
		return _fail("A scoreboard row on challenge '%s' named no player." % challenge_id)
	row.user_id = str(v["userid"])
	row.participant_name = _ci_str(v, "participantName")
	row.division = _ci_str(v, "participantDivision")
	row.country_code = _ci_str(v, "participantCountryCode")
	row.profile_picture = _ci_str(v, "participantProfilePicture")
	row.platform = _ci_int(v, "participantPlayingPlatform")
	row.approval_status = _ci_int(v, "approvalStatus") ## opaque by design - carried, never read for meaning
	row.is_pending = _ci_bool(v, "isPending")
	return {"ok": true, "row": row}


## Strict ISO-8601 reading for the league's OffsetDateTime
## strings ("2026-10-25T19:00:00Z", with an offset, with
## fractional seconds). Unix seconds out, -1 when the string
## is not that shape - callers fail closed on -1.
static func parse_iso8601(s: String) -> int:
	var text: String = s.strip_edges()
	if text.length() < 19:
		return -1
	if text[4] != "-" or text[7] != "-" or text[13] != ":" or text[16] != ":":
		return -1
	var date_part: String = text.substr(0, 10)
	var time_part: String = text.substr(11, 8)
	if not _all_digits(date_part.replace("-", "")) or not _all_digits(time_part.replace(":", "")):
		return -1
	var year: int = int(text.substr(0, 4))
	var month: int = int(text.substr(5, 2))
	var day: int = int(text.substr(8, 2))
	var hour: int = int(text.substr(11, 2))
	var minute: int = int(text.substr(14, 2))
	var second: int = int(text.substr(17, 2))
	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 60:
		return -1
	var rest: String = text.substr(19)
	if rest.begins_with("."):
		var k: int = 1
		while k < rest.length() and rest[k].is_valid_int():
			k += 1
		rest = rest.substr(k)
	var offset: int = 0
	if rest == "" or rest == "Z" or rest == "z":
		offset = 0
	elif (rest.begins_with("+") or rest.begins_with("-")) and rest.length() >= 3:
		var sign: int = 1 if rest.begins_with("+") else -1
		var digits: String = rest.substr(1).replace(":", "")
		if digits.length() < 2 or not _all_digits(digits):
			return -1
		var oh: int = int(digits.substr(0, 2))
		var om: int = int(digits.substr(2, 2)) if digits.length() >= 4 else 0
		if oh > 14 or om > 59:
			return -1
		offset = sign * (oh * 3600 + om * 60)
	else:
		return -1
	var unix: int = Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": second})
	return unix - offset


static func _all_digits(s: String) -> bool:
	if s == "":
		return false
	for i: int in range(s.length()):
		if not s[i].is_valid_int():
			return false
	return true


# ------------------------------------------------------------ the last-good cache

static func cache_path() -> String:
	return "user://".path_join(CACHE_FILE_NAME)


## The wall's memory of the last good fetch: the raw search
## body (parsed again on load through the same fail-closed
## parser - a corrupt cache is no cache), whose key it was,
## and when it landed. Written only on a successful fetch.
static func save_cache(raw_body: String, user_id: String, user_name: String, fetched_at: int) -> bool:
	var d: Dictionary = {
		"fetched_at": fetched_at,
		"user_id": user_id,
		"user_name": user_name,
		"body": raw_body,
	}
	var f: FileAccess = FileAccess.open(cache_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true


static func load_cache() -> Dictionary:
	if not FileAccess.file_exists(cache_path()):
		return {"ok": false, "error": "no cache"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path()))
	if not (parsed is Dictionary):
		return {"ok": false, "error": "the saved WoVP data was not readable"}
	var d: Dictionary = parsed
	var body: String = str(d.get("body", ""))
	if body == "":
		return {"ok": false, "error": "the saved WoVP data was empty"}
	var c: Dictionary = parse_challenges(body)
	if not bool(c.get("ok", false)):
		return {"ok": false, "error": str(c.get("error", "the saved WoVP data could not be read"))}
	return {
		"ok": true,
		"challenges": c.get("challenges", []),
		"user_id": str(d.get("user_id", "")),
		"user_name": str(d.get("user_name", "")),
		"fetched_at": int(d.get("fetched_at", 0)),
	}
