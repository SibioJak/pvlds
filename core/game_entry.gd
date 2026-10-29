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
var shot_url: String = "" ## The VPS db's imgUrl for the CURRENT build: the author's screenshot of that exact build, the card face's primary source (the graduation round). "" when the db carries none. The bytes live in ArtProvider's cache once Main's ShotFetcher lands them; this entry only ever reads that cache.
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
	# is_cache_current, not is_cached: a cache file written by
	# an older extractor generation must not serve (its image
	# can be a successful extraction of the wrong thing - a
	# pair file's lit On face under v2); the extraction path
	# below refreshes it once and records the new generation.
	if ArtProvider.is_cache_current(src):
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


## The face the card wears, in the graduation round's order:
## the author's screenshot of the current build first (served
## from ArtProvider's shot cache once the fetcher has landed
## it), then the standing chain (ensure_art: side image ->
## .directb2s extraction -> embedded .vpx image), then "" and
## the generated title card. A shot that has not landed yet
## does NOT blank the card: the standing chain answers for
## now, and when the fetch lands the room re-reads this
## (its face cache key carries the returned path, so the new
## face replaces the old on the next fill). A shot whose fetch
## failed is a recorded negative outcome - it never re-blocks
## the chain behind per-visit retries.
func face_path() -> String:
	if shot_url != "" and OS.get_environment("PVLDS_GRAD_NC") != "oldrank":
		# (The env check is the graduation smoke's negative
		# control: PVLDS_GRAD_NC=oldrank restores the
		# pre-graduation ranking - chain first, shot never -
		# and the smoke's shot-ranking legs must fail by name.)
		if ArtProvider.shot_is_cached(shot_url):
			return ArtProvider.shot_cache_path_for(shot_url)
		if not ArtProvider.is_negative_outcome(ArtProvider.shot_outcome(shot_url)):
			# Not landed, not failed: the standing chain
			# answers until the fetch arrives.
			return ensure_art()
		# Landed-and-failed: fall through to the chain for good.
	return ensure_art()


## Whether this game's face IS its author screenshot right
## now (the power-on's settle rule reads it: a performance
## whose subject was the backglass settles back to the shot
## only when the shot is the standing face).
func has_shot_face() -> bool:
	return shot_url != "" and ArtProvider.shot_is_cached(shot_url)


## The .directb2s face as a loadable path, extracted on the
## same claim discipline as ensure_art - the power-on's
## subject (the graduation round: the backglass is the
## power-on's rest state, whatever the card's face is).
## "" when the game has no backglass source. The room warms
## this at face-fill time, so a focus never pays an extraction
## the warmer would not have done anyway.
func backglass_face_path() -> String:
	var src: String = backglass_source()
	if src == "":
		return ""
	return _ensure_from_source(src)


## The .directb2s this game's face comes from, or "" when it
## does not. Only the primary extraction source counts, and
## only when it is a backglass: a side image outranks the
## backglass for the face, so the scanner never records the
## backglass beside one (see LibraryScanner._resolve_art).
## The room keys its pair crossfade on this (with pair_on_art):
## a game whose flat extraction failed and fell through to
## embedded art or a title card has no pair to crossfade to,
## however its file is built.
func backglass_source() -> String:
	if art_source_path.get_extension().to_lower() == "directb2s":
		return art_source_path
	return ""


## The cached pair ON half for this game, as a loadable face
## texture path, or "" when there is none to crossfade to:
## the game's backglass extraction must have cached its On
## sibling (ArtProvider.has_pair_on). Cheap probes only - the
## extraction itself is the flat pipeline's work, already done
## by the time a panel exists.
##
## Graduation note: this gate used to also require the card's
## face to BE the backglass extraction (art_path == its cache
## path). With the author screenshot as the face, that identity
## never holds - the pair would have died by construction. The
## gate now asks only about the backglass itself: the power-on
## performs ON the backglass whatever the card's face is, so
## its On half is the crossfade's target whenever it exists.
func pair_on_art() -> String:
	var src: String = backglass_source()
	if src == "":
		return ""
	if ArtProvider.has_pair_on(src):
		return ArtProvider.pair_on_path_for(src)
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
