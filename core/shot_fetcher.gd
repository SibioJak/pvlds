class_name ShotFetcher
extends Node

## The author screenshots' fetch (the graduation round): the
## VPS db's tableFile imgUrl is the author's own screenshot of
## the exact build, and PVLDS already downloads that database
## for matching - the shots are the one art source that arrives
## over the network. This service walks a scanned library once
## per scan landing and fetches every shot the cache does not
## already hold, ONE request at a time (the polite shape for a
## community static host: ~45 KB a file, fetched once, cached
## forever - no per-view hotlinking, no bulk re-fetch; a URL
## that fails is a recorded negative outcome in ArtProvider's
## index and is never retried by later scans).
##
## Deliberately NOT part of the scan: LibraryScanner runs on a
## worker thread as pure data, so the fetch lives here, beside
## VpsDownloader, driven by Main on every scan landing. Each
## landed shot is decoded and stored by ArtProvider
## (store_shot_bytes) and announced on shot_arrived, so the
## room can upgrade the card's face from its fallback chain to
## the screenshot the moment it exists.

signal shot_arrived(game: GameEntry)
signal queue_drained

var _http: HTTPRequest
var _queue: Array = [] ## Array of {"url": String, "games": Array[GameEntry]}
var _by_url: Dictionary = {} ## url -> the queue entry being built (dedupe: sister builds share a game's one shot_url, but two games can share a URL stem's target)
var _current: Dictionary = {} ## the in-flight entry
var _fetching: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func is_fetching() -> bool:
	return _fetching


## Queue every shot this library needs and start walking it.
## Already-cached shots and recorded failures are skipped -
## the cache and the index are the memory across scans.
func fetch_library(games: Array[GameEntry]) -> void:
	_queue.clear()
	_by_url.clear()
	for g: GameEntry in games:
		var url: String = g.shot_url
		if url == "":
			continue
		if ArtProvider.shot_is_cached(url):
			continue
		if ArtProvider.is_negative_outcome(ArtProvider.shot_outcome(url)):
			continue
		var entry: Variant = _by_url.get(url, null)
		if entry is Dictionary:
			(entry["games"] as Array).append(g)
		else:
			var fresh: Dictionary = {"url": url, "games": [g]}
			_by_url[url] = fresh
			_queue.append(fresh)
	if not _fetching:
		_next()


## The URL actually requested: the db's own, unless the
## PVLDS_SHOT_BASE dev seam re-roots it (the harness serves
## the shots from a local stub so the graduation smoke never
## touches the network - the same pattern as PVLDS_VPSDB_URL).
func effective_url(url: String) -> String:
	var base: String = OS.get_environment("PVLDS_SHOT_BASE")
	if base == "":
		return url
	var scheme_end: int = url.find("://")
	if scheme_end < 0:
		return url
	var path_start: int = url.find("/", scheme_end + 3)
	if path_start < 0:
		return base
	return base.trim_suffix("/") + url.substr(path_start)


func _next() -> void:
	if _queue.is_empty():
		_fetching = false
		_current = {}
		queue_drained.emit()
		return
	_fetching = true
	_current = _queue.pop_front()
	var url: String = str(_current.get("url", ""))
	var err: Error = _http.request(effective_url(url))
	if err != OK:
		ArtProvider.record_shot_outcome(url, ArtProvider.STATUS_FAILED)
		_next()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var entry: Dictionary = _current
	_current = {}
	if entry.is_empty():
		_next()
		return
	var url: String = str(entry.get("url", ""))
	var status: String = ArtProvider.STATUS_FAILED
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and not body.is_empty():
		status = ArtProvider.store_shot_bytes(url, body)
	else:
		ArtProvider.record_shot_outcome(url, ArtProvider.STATUS_FAILED)
	if status == ArtProvider.STATUS_OK:
		for gv: Variant in (entry.get("games", []) as Array):
			if gv is GameEntry:
				shot_arrived.emit(gv as GameEntry)
	_next()
