class_name ArtWarmer
extends RefCounted

## Background pre-extraction of panel art into ArtProvider's
## cache, so browsing never pays the extraction cost. Runs as ONE
## WorkerThreadPool task (the library scan's proven pattern - never
## the UI thread), walking a queue of extraction sources (.directb2s
## files and, since the embedded-art round, .vpx files themselves -
## a game's .vpx is queued as its primary source when it has no
## backglass, and as a fallback only once its backglass is already
## known to hold no usable image; see warm_library). Visible
## panels outrank it structurally: GameEntry.ensure_art claims its
## own extraction synchronously, and the claim registry means the
## warmer skips anything a panel is doing - the two never extract
## the same file twice, and a panel never queues behind this list.
## Adjacent-page prefetch is prioritize(): those paths jump the
## queue. The warmer writes only cache files - texture creation
## stays in the room, on warm hits that are a small file read.
##
## Phase two (flicker fix round): once the flat queue is empty,
## the same pass walks a second queue - the lamp-layer sets of
## B2S-backed games that have no stamped layer outcome yet -
## through GameEntry.ensure_flicker, so a first focus on a
## B2S card can cascade immediately instead of surging while
## its set is cold. Flat art is strictly first, always: the
## layer queue is only touched while the flat queue is empty,
## and anything prioritize() or a fresh warm_library() queues
## flat pre-empts it again. Same discipline as phase one -
## background worker only, never during a scan (warm_library
## is only ever called on a scan's adopt), abandoned at item
## boundaries on request_stop, and once per game ever: a
## stamped layer outcome (ok / no_layers / failed) is never
## re-queued, and a set extracted by a focus visit meanwhile
## is skipped when its turn comes. One flat outcome DOES
## skip a game here: a stamped no_image means the file was
## read and holds no usable image anywhere - no base for
## lamps to light over, so there is nothing to extract. A
## FAILED flat read (the wart: a corrupt designated element
## hiding healthy lamps behind the blob fallback) stays
## queued - that distinction is the wart's whole lesson.

## Set by the owner; fired (deferred to the main thread) when a pass
## empties its queue.
var on_drained: Callable = Callable()

var last_pass_msec: int = 0 ## wall duration of the last completed pass
var last_pass_items: int = 0 ## extractions the last pass performed

var _mutex: Mutex = Mutex.new()
var _queue: Array[String] = []
var _queued: Dictionary = {}
var _layer_queue: Array[GameEntry] = [] ## phase two: entries owing a layer extraction
var _layer_queued: Dictionary = {} ## game_id -> true, for _layer_queue
var _worker_active: bool = false
var _stop_requested: bool = false
var _pass_started_msec: int = 0
var _pass_items: int = 0


## Queue every uncached backglass in the library (replacing any
## pending queue - in-flight extractions finish) and start the
## worker if it is not already running. Also prunes cache files no
## current source maps to (stale stamps, replaced backglasses).
func warm_library(games: Array[GameEntry]) -> void:
	var keep: Dictionary = {}
	for g: GameEntry in games:
		for src: String in g.art_sources():
			keep[ArtProvider.cache_path_for(src)] = true
	ArtProvider.prune_cache(keep)
	_mutex.lock()
	_queue.clear()
	_queued.clear()
	_layer_queue.clear()
	_layer_queued.clear()
	for g: GameEntry in games:
		# Phase two's queue, built alongside phase one's: every
		# B2S-backed game whose layer set has never been tried.
		# (A FAILED flat extraction does not skip a game - a
		# backglass can fail flat and still hold lamps; the
		# wart fixture is exactly that game. A stamped
		# no_image does: no usable image anywhere in the file
		# means no base exists for lamps to light over.)
		var fsrc: String = g.flicker_source()
		if fsrc != "" and ArtProvider.flicker_outcome(fsrc) == "" \
				and ArtProvider.outcome_for_source(fsrc) != ArtProvider.STATUS_NO_IMAGE \
				and not _layer_queued.has(g.game_id):
			_layer_queue.append(g)
			_layer_queued[g.game_id] = true
	for g: GameEntry in games:
		var sources: Array[String] = g.art_sources()
		for i: int in range(sources.size()):
			var src: String = sources[i]
			if _queued.has(src) or ArtProvider.is_cached(src):
				continue
			# A stamped negative (no usable image / failed, for
			# this exact file version) is never re-queued:
			# retrying failures on every pass was the no-art
			# pages' recurring tax.
			if ArtProvider.is_negative_outcome(ArtProvider.outcome_for_source(src)):
				continue
			if i > 0:
				# A fallback (the .vpx behind a .directb2s) is
				# pre-extracted only when the primary is ALREADY
				# known to hold no usable image - queuing every
				# table file behind an untried backglass would
				# double the pass for art most games never need.
				# A backglass that fails later is covered the
				# moment it matters: the panel showing that game
				# falls through to the fallback itself
				# (GameEntry.ensure_art), and the next pass
				# queues it.
				var primary: String = sources[0]
				if primary.get_extension().to_lower() != "directb2s":
					continue
				if not ArtProvider.is_negative_outcome(ArtProvider.outcome_for_source(primary)):
					continue
			_queue.append(src)
			_queued[src] = true
	_start_locked()
	_mutex.unlock()


## Move these games' art sources to the front of the queue
## (order preserved) so a page flip lands on warm art. Paths not
## yet queued are added; cached or panel-claimed ones are skipped
## by the worker.
func prioritize(games: Array[GameEntry]) -> void:
	var front: Array[String] = []
	for g: GameEntry in games:
		for src: String in g.art_sources():
			if not front.has(src):
				front.append(src)
	if front.is_empty():
		return
	_mutex.lock()
	for src: String in front:
		_queue.erase(src)
		_queued[src] = true
	for i: int in range(front.size() - 1, -1, -1):
		_queue.push_front(front[i])
	_start_locked()
	_mutex.unlock()


func is_idle() -> bool:
	_mutex.lock()
	var idle: bool = not _worker_active and _queue.is_empty() and _layer_queue.is_empty()
	_mutex.unlock()
	return idle


## Ask the running pass to abandon its queue at the next item
## boundary. For app shutdown: Godot waits for WorkerThreadPool
## tasks during quit, so an unstoppable pass turns an exit into a
## wait for the entire remaining queue (field fault, 2026-10-22:
## EXIT after a desktop scan hung for minutes once extractor v2
## filled the queue with real multi-second extractions). Items
## already extracted keep their cache entries and outcome stamps -
## those are written per file during extraction, before the next
## item starts. Safe to call when no pass is running: a pass
## started later clears the flag (see _start_locked).
func request_stop() -> void:
	_mutex.lock()
	_stop_requested = true
	_mutex.unlock()


## Backglass health for a library, from the persisted outcome
## index - the desk's diagnostic breakdown. Counts are over games
## whose PRIMARY source is a .directb2s (games the embedded source
## serves instead are embedded_health's subject):
##   ok       - extracted; the cache serves the image instantly
##   no_image - extracted once; the file holds no usable image
##   failed   - extracted once; read/parse/decode failed
##   untried  - never extracted (no outcome recorded yet)
## Reading the index costs no extraction, so the desk can show
## these numbers after the fact - they are what convicts the
## failure class on a real library.
static func art_health(games: Array[GameEntry]) -> Dictionary:
	var health: Dictionary = {"ok": 0, "no_image": 0, "failed": 0, "untried": 0, "total": 0}
	for g: GameEntry in games:
		if g.art_source_path == "" or g.art_source_path.get_extension().to_lower() != "directb2s":
			continue
		health["total"] = int(health["total"]) + 1
		if ArtProvider.is_cached(g.art_source_path):
			health["ok"] = int(health["ok"]) + 1
			continue
		match ArtProvider.outcome_for_source(g.art_source_path):
			ArtProvider.STATUS_OK:
				health["ok"] = int(health["ok"]) + 1
			ArtProvider.STATUS_NO_IMAGE:
				health["no_image"] = int(health["no_image"]) + 1
			ArtProvider.STATUS_FAILED:
				health["failed"] = int(health["failed"]) + 1
			_:
				health["untried"] = int(health["untried"]) + 1
	return health


## Embedded-art health: the same breakdown for the image inside
## the .vpx, over the games where that source is actually in play
## - the game has no side image, and either the .vpx IS its
## primary source or its backglass is already known to hold no
## usable image. A game whose backglass serves (or has yet to be
## tried) is not counted: its embedded art is a fallback that may
## never be needed. One extra bucket over the backglass
## breakdown: legacy - the game's art exists only as pre-10.8.1
## BITS records (the census count that decides whether an LZW
## decoder is ever worth building). Outcomes are read through
## the embedded gate, so a stamp from an older embedded reader
## counts as untried here, never as its stale verdict.
static func embedded_health(games: Array[GameEntry]) -> Dictionary:
	var health: Dictionary = {"ok": 0, "no_image": 0, "legacy": 0, "failed": 0, "untried": 0, "total": 0}
	for g: GameEntry in games:
		if g.art_path != "" or g.art_vpx_path == "":
			continue
		var primary: String = g.art_source_path
		var in_play: bool = primary == g.art_vpx_path
		if not in_play and primary != "" \
				and ArtProvider.is_negative_outcome(ArtProvider.outcome_for_source(primary)):
			in_play = true
		if not in_play:
			continue
		health["total"] = int(health["total"]) + 1
		if ArtProvider.is_cached(g.art_vpx_path):
			health["ok"] = int(health["ok"]) + 1
			continue
		match ArtProvider.outcome_for_embedded(g.art_vpx_path):
			ArtProvider.STATUS_OK:
				health["ok"] = int(health["ok"]) + 1
			ArtProvider.STATUS_NO_IMAGE:
				health["no_image"] = int(health["no_image"]) + 1
			ArtProvider.STATUS_LEGACY:
				health["legacy"] = int(health["legacy"]) + 1
			ArtProvider.STATUS_FAILED:
				health["failed"] = int(health["failed"]) + 1
			_:
				health["untried"] = int(health["untried"]) + 1
	return health


## Art-cache coverage for a library: x = games whose art is ready
## instantly (side image on disk or an extraction cached), y =
## games that have any art source at all.
static func cache_coverage(games: Array[GameEntry]) -> Vector2i:
	var have: int = 0
	var want: int = 0
	for g: GameEntry in games:
		if not g.has_art_available():
			continue
		want += 1
		if g.art_path != "":
			have += 1
			continue
		for src: String in g.art_sources():
			if ArtProvider.is_cached(src):
				have += 1
				break
	return Vector2i(have, want)


## Caller holds _mutex. Starts the single worker when there is work.
func _start_locked() -> void:
	if _worker_active or (_queue.is_empty() and _layer_queue.is_empty()):
		return
	# A fresh pass is a new lease: a stop requested of some earlier,
	# already-finished moment must not abandon it. (While a pass is
	# active this function returns above, so a live stop stands.)
	_stop_requested = false
	_worker_active = true
	_pass_started_msec = Time.get_ticks_msec()
	_pass_items = 0
	WorkerThreadPool.add_task(_run_pass)


func _run_pass() -> void:
	while true:
		_mutex.lock()
		if _stop_requested:
			# Shutdown: abandon the rest of the queue at this item
			# boundary. Completed items keep their cache entries
			# and outcome stamps; the unextracted remainder is
			# simply re-queued by the next boot's warm. No
			# on_drained: the queue did not drain, it was
			# abandoned, and the owner is going away regardless.
			_stop_requested = false
			_queue.clear()
			_queued.clear()
			_layer_queue.clear()
			_layer_queued.clear()
			_worker_active = false
			last_pass_msec = Time.get_ticks_msec() - _pass_started_msec
			last_pass_items = _pass_items
			_mutex.unlock()
			return
		if _queue.is_empty() and _layer_queue.is_empty():
			_worker_active = false
			last_pass_msec = Time.get_ticks_msec() - _pass_started_msec
			last_pass_items = _pass_items
			_mutex.unlock()
			if on_drained.is_valid():
				on_drained.call_deferred()
			return
		# Flat art strictly first: a layer item is only taken
		# once the flat queue stands empty (a fresh flat queue
		# - prioritize, a new warm - pre-empts phase two at
		# the next item boundary, exactly like a scan would).
		var src: String = ""
		var layer_game: GameEntry = null
		if not _queue.is_empty():
			src = _queue.pop_front()
			_queued.erase(src)
		else:
			layer_game = _layer_queue.pop_front()
			_layer_queued.erase(layer_game.game_id)
		_mutex.unlock()
		if layer_game != null:
			_warm_layers(layer_game)
			continue
		if ArtProvider.is_cached(src):
			continue
		if ArtProvider.is_negative_outcome(ArtProvider.outcome_for_source(src)):
			# Recorded (by a panel, most likely) after this pass
			# was queued: the outcome stands, do not re-extract.
			continue
		if not ArtProvider.claim_extract(src):
			# A visible panel is extracting this one itself - its
			# result lands in the same cache. Never duplicate it.
			continue
		ArtProvider.extract_art_image(src)
		ArtProvider.release_extract(src)
		_mutex.lock()
		_pass_items += 1
		_mutex.unlock()
		# A breath between items keeps disk and CPU contention low
		# while the room is loading its own (warm) textures.
		OS.delay_msec(2)


## One game's phase-two item (worker thread): extract its
## lamp-layer set through the entry, whose claim discipline
## arbitrates with the room's focus-triggered extraction -
## whichever claimant gets there first does the work and the
## other reads the stamped outcome. A set a focus visit
## extracted while this item waited its turn is skipped by
## the outcome re-check. Counts as a pass item only when the
## outcome actually transitions from untried to stamped:
## warm hits and skips are not extractions.
func _warm_layers(g: GameEntry) -> void:
	var src: String = g.flicker_source()
	if src == "" or ArtProvider.flicker_outcome(src) != "" \
			or ArtProvider.outcome_for_source(src) == ArtProvider.STATUS_NO_IMAGE:
		return
	g.ensure_flicker()
	if ArtProvider.flicker_outcome(src) != "":
		_mutex.lock()
		_pass_items += 1
		_mutex.unlock()
	OS.delay_msec(2)
