class_name GameEntry
extends RefCounted

## One game (one panel on the wall) grouping every build found on disk.
## Pure data - the room is a face on top of this, never the reverse.

var game_id: String = "" ## VPS game id when matched, else "local:<normalized title>".
var title: String = ""
var manufacturer: String = ""
var year: int = 0 ## 0 = unknown.
var designers: PackedStringArray = PackedStringArray()
var builds: Array[TableBuild] = []
var art_path: String = "" ## Loadable image (side image or extracted cache file), or "" -> generated title card.
var art_source_path: String = "" ## The primary extraction source not yet extracted: a same-stem .directb2s, or the .vpx itself when the game has no backglass. "" when neither exists.
var art_vpx_path: String = "" ## The game's first build's .vpx - the embedded-image fallback source, tried when the primary source holds no usable image. Set for every game; it is the table file itself, so it always exists.
var _art_attempted: bool = false
var _flicker_attempted: bool = false
var _flicker_data: Dictionary = {}


## Art the scan knows exists for this game - extracted or not.
## The .vpx fallback (art_vpx_path) deliberately does NOT count
## on its own: it exists for every game, so counting it would
## claim art is "available" library-wide before a single file was
## opened. A game counts when it has a side image, a backglass,
## or - with neither - the .vpx recorded as its primary source.
func has_art_available() -> bool:
	return art_path != "" or art_source_path != ""


## The extraction sources in art order: the primary first, then
## the .vpx's embedded image when the primary is a different file
## (a .directb2s that turned out to hold no usable image does not
## end the search - the table file itself is tried next).
func art_sources() -> Array[String]:
	var out: Array[String] = []
	if art_source_path != "":
		out.append(art_source_path)
	if art_vpx_path != "" and art_vpx_path != art_source_path:
		out.append(art_vpx_path)
	return out


## How long a visible panel waits on the warmer's in-flight
## extraction of its file before it stops waiting and extracts the
## file itself. The claim registry prevents DUPLICATE work; it
## must never become a stall with no fallback.
const CLAIM_WAIT_MSEC: int = 3000


## A loadable image path for a visible panel, walking the art
## sources in order (art_sources). Per source: warm cache serves
## with no work; a stamped negative (the file was already
## extracted once and held no usable image, or failed) answers
## immediately and the NEXT source is tried - only when every
## source is exhausted does the title card render, and no page
## visit ever pays the extraction cost twice. A cold source is
## claimed and extracted by this panel - unless the background
## warmer is already extracting this exact file, in which case the
## panel joins that wait (bounded by CLAIM_WAIT_MSEC) instead of
## queueing behind the warmer's library list; if the wait stalls,
## the panel falls back to extracting the file itself. An outcome
## is recorded either way, so a failure is never retried until the
## file changes.
func ensure_art() -> String:
	if art_path != "" or _art_attempted:
		return art_path
	_art_attempted = true
	for src: String in art_sources():
		var got: String = _ensure_from_source(src)
		if got != "":
			art_path = got
			return art_path
	return art_path


## One source of ensure_art, with the claim discipline the single
## source version had: warm cache serves instantly; a stamped
## negative answers "" immediately (the NEXT source then gets its
## turn - a backglass with no usable image falls through to the
## image inside the .vpx); a cold source is claimed and extracted
## here, or joined if the warmer is already extracting it.
func _ensure_from_source(src: String) -> String:
	if ArtProvider.is_cached(src):
		return ArtProvider.cache_path_for(src)
	if ArtProvider.is_negative_outcome(ArtProvider.outcome_for_source(src)):
		return ""
	if ArtProvider.claim_extract(src):
		var got: String = ArtProvider.extract_art_image(src)
		ArtProvider.release_extract(src)
		return got
	if ArtProvider.await_extract(src, CLAIM_WAIT_MSEC):
		return ArtProvider.cache_path_for(src)
	if ArtProvider.outcome_for_source(src) == "":
		# The claim holder is still grinding past the wait bound
		# (an enormous file, a wedged warmer): extract it ourselves
		# rather than leaving the panel blank-faced. The registry
		# prevented a duplicate; it does not get to prevent art.
		return ArtProvider.extract_art_image(src)
	return ""


## The .directb2s whose lamp layers this game's face could
## wear for the power-on flicker, or "" when the game has none
## in play. Only the primary extraction source counts, and only
## when it is a backglass: a side image outranks the backglass
## for the face, so the scanner never records the backglass
## beside one (see LibraryScanner._resolve_art) - layers
## composited over a different image would sit in the wrong
## places, so those games take the brightness fallback instead.
## The room keys its layer path on this alone: a game whose
## flat extraction failed and fell through to embedded art or
## a title card still cascades from here (flicker fix round).
func flicker_source() -> String:
	if art_source_path.get_extension().to_lower() == "directb2s":
		return art_source_path
	return ""


## The game's flicker layer set (ArtProvider.extract_flicker_
## layers' dictionary), with ensure_art's claim discipline:
## a warm sibling cache serves with no work; a stamped negative
## (no_layers / failed) answers empty at once; a cold source is
## claimed and extracted here, or joined if another claimant
## (the room's focus-triggered worker) is already extracting it.
## The result memoizes for the entry's life, like _art_attempted.
## Safe to call from a worker thread - the room does exactly
## that, so a first focus never pays the extraction on the
## render thread; the ArtProvider statics it touches are
## mutex-guarded, as the warmer's path already relies on.
func ensure_flicker() -> Dictionary:
	if not _flicker_data.is_empty() or _flicker_attempted:
		return _flicker_data
	_flicker_attempted = true
	var src: String = flicker_source()
	if src == "":
		return _flicker_data
	if ArtProvider.has_flicker_layers(src):
		_flicker_data = ArtProvider.extract_flicker_layers(src)
		return _flicker_data
	if ArtProvider.is_flicker_negative(ArtProvider.flicker_outcome(src)):
		return _flicker_data
	var key: String = ArtProvider.flicker_claim_key(src)
	if ArtProvider.claim_extract(key):
		_flicker_data = ArtProvider.extract_flicker_layers(src)
		ArtProvider.release_extract(key)
		return _flicker_data
	if ArtProvider.await_flicker(src, CLAIM_WAIT_MSEC):
		_flicker_data = ArtProvider.extract_flicker_layers(src)
	return _flicker_data


func build_count() -> int:
	return builds.size()


func is_vr_tagged() -> bool:
	for b: TableBuild in builds:
		if b.has_vr_tag():
			return true
	return false


func year_text() -> String:
	return str(year) if year > 0 else "Year unknown"


func designer_text() -> String:
	if designers.is_empty():
		return "Unknown designer"
	return ", ".join(designers)


func build_by_path(path: String) -> TableBuild:
	for b: TableBuild in builds:
		if b.file_path == path:
			return b
	return null


## The build that matters. Rule (documented in README): a build the VPS db
## knows outranks a local-only build; within a class, latest date wins,
## then highest version. A stray newer download never silently outranks
## the latest known release.
func current_build() -> TableBuild:
	var best: TableBuild = null
	for b: TableBuild in builds:
		if best == null or GameEntry.is_better_current(b, best):
			best = b
	return best


static func is_better_current(a: TableBuild, b: TableBuild) -> bool:
	if a.matched_db != b.matched_db:
		return a.matched_db
	if a.date_unix != b.date_unix:
		return a.date_unix > b.date_unix
	return TableBuild.compare_versions(a.version, b.version) > 0


## The player's default build: their stored choice, else CURRENT.
func resolve_default_build(store: StateStore) -> TableBuild:
	if store != null:
		var stored: String = store.get_default_build(game_id)
		if stored != "":
			var found: TableBuild = build_by_path(stored)
			if found != null:
				return found
	return current_build()
