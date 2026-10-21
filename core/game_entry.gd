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
var art_source_path: String = "" ## Same-stem .directb2s whose backglass has not been extracted yet, or "".
var _art_attempted: bool = false


## Art the scan knows exists for this game - extracted or not.
func has_art_available() -> bool:
	return art_path != "" or art_source_path != ""


## How long a visible panel waits on the warmer's in-flight
## extraction of its file before it stops waiting and extracts the
## file itself. The claim registry prevents DUPLICATE work; it
## must never become a stall with no fallback.
const CLAIM_WAIT_MSEC: int = 3000


## A loadable image path for a visible panel. Warm cache: a file
## path, no work. Stamped negative (the file was already extracted
## once and held no usable image, or failed): "" immediately, no
## work at all - the title card renders without paying the
## extraction cost again on every page visit. Cold and unstamped:
## this panel claims the extraction itself - unless the background
## warmer is already extracting this exact file, in which case the
## panel joins that wait (bounded by CLAIM_WAIT_MSEC) instead of
## queueing behind the warmer's library list; if the wait stalls,
## the panel falls back to extracting the file itself. An outcome
## is recorded either way, so a failure is never retried until the
## file changes.
func ensure_art() -> String:
	if art_path != "" or art_source_path == "" or _art_attempted:
		return art_path
	_art_attempted = true
	if ArtProvider.is_cached(art_source_path):
		art_path = ArtProvider.cache_path_for(art_source_path)
		return art_path
	if ArtProvider.is_negative_outcome(ArtProvider.outcome_for(art_source_path)):
		return art_path
	if ArtProvider.claim_extract(art_source_path):
		art_path = ArtProvider.extract_directb2s_image(art_source_path)
		ArtProvider.release_extract(art_source_path)
	elif ArtProvider.await_extract(art_source_path, CLAIM_WAIT_MSEC):
		art_path = ArtProvider.cache_path_for(art_source_path)
	elif ArtProvider.outcome_for(art_source_path) == "":
		# The claim holder is still grinding past the wait bound
		# (an enormous file, a wedged warmer): extract it ourselves
		# rather than leaving the panel blank-faced. The registry
		# prevented a duplicate; it does not get to prevent art.
		art_path = ArtProvider.extract_directb2s_image(art_source_path)
	return art_path


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
