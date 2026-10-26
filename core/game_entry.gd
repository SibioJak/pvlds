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
	if ArtProvider.is_negative_outcome(ArtProvider.outcome_for(src)):
		return ""
	if ArtProvider.claim_extract(src):
		var got: String = ArtProvider.extract_art_image(src)
		ArtProvider.release_extract(src)
		return got
	if ArtProvider.await_extract(src, CLAIM_WAIT_MSEC):
		return ArtProvider.cache_path_for(src)
	if ArtProvider.outcome_for(src) == "":
		# The claim holder is still grinding past the wait bound
		# (an enormous file, a wedged warmer): extract it ourselves
		# rather than leaving the panel blank-faced. The registry
		# prevented a duplicate; it does not get to prevent art.
		return ArtProvider.extract_art_image(src)
	return ""


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
