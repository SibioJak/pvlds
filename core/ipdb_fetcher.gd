class_name IpdbFetcher
extends Node

## CARDBACK (item 3, second leg): the SETUP fetch pass's
## engine - a small queue of IPDB machine-page GETs (two
## in flight), nothing more. Main builds the plan from
## IpdbFacts.fetch_plan (cache-first), feeds it here, and
## owns parsing/caching on item_done. This node exists
## ONLY on the SETUP path: nothing starts it at boot, in
## play, or on a flip, and fetch_count - the number of
## requests actually started - is the smoke's proof of
## exactly that (a flip renders from cache with the count
## standing at 0).
##
## IPDB is a volunteer archive; the pass is deliberately
## gentle: two concurrent requests, a browser user agent
## (the site serves its facts table to one), and a 30 s
## per-request timeout. A failure is reported, never
## retried inside the pass - Main records it in the cache
## and the coverage line counts it.

signal item_done(game_id: String, ok: bool, payload: String)
signal progress(done: int, total: int)
signal finished

const CONCURRENCY: int = 2
const USER_AGENT: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

var fetch_count: int = 0 ## requests actually started - the offline proof's counter

var _queue: Array = []
var _total: int = 0
var _done: int = 0
var _running: bool = false
var _slots: Array = []


func _ready() -> void:
	for i: int in CONCURRENCY:
		var req: HTTPRequest = HTTPRequest.new()
		req.timeout = 30.0
		req.use_threads = true
		add_child(req)
		var slot: Dictionary = {"req": req, "game_id": "", "busy": false}
		_slots.append(slot)
		req.request_completed.connect(_on_completed.bind(slot))


func is_running() -> bool:
	return _running


## Begin a pass over a fetch plan (IpdbFacts.fetch_plan's
## shape: [{game_id, ipdb_id}]). A pass already running
## swallows the call - the SETUP buttons re-ask harmlessly.
func start(plan: Array) -> void:
	if _running:
		return
	_queue = plan.duplicate()
	_total = plan.size()
	_done = 0
	if _total == 0:
		finished.emit()
		return
	_running = true
	_pump()


func _pump() -> void:
	for slot_v: Variant in _slots:
		var slot: Dictionary = slot_v as Dictionary
		if _queue.is_empty():
			break
		if bool(slot.get("busy", false)):
			continue
		var item: Dictionary = _queue.pop_front() as Dictionary
		slot["busy"] = true
		slot["game_id"] = str(item.get("game_id", ""))
		fetch_count += 1
		var req: HTTPRequest = slot.get("req") as HTTPRequest
		var err: int = req.request(IpdbFacts.page_url(int(item.get("ipdb_id", 0))),
			PackedStringArray(["User-Agent: " + USER_AGENT]))
		if err != OK:
			_finish_slot(slot, false, "request error %d" % err)
	if _queue.is_empty() and _running:
		var any_busy: bool = false
		for slot_v2: Variant in _slots:
			if bool((slot_v2 as Dictionary).get("busy", false)):
				any_busy = true
		if not any_busy:
			_running = false
			finished.emit()


func _on_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, slot: Dictionary) -> void:
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	_finish_slot(slot, ok, body.get_string_from_utf8() if ok else "HTTP %d (result %d)" % [response_code, result])


func _finish_slot(slot: Dictionary, ok: bool, payload: String) -> void:
	var game_id: String = str(slot.get("game_id", ""))
	slot["busy"] = false
	slot["game_id"] = ""
	_done += 1
	item_done.emit(game_id, ok, payload)
	progress.emit(_done, _total)
	_pump()
