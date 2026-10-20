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


## A loadable image path, extracting the backglass from the .directb2s
## on first demand (ArtProvider caches the result under user://, so
## each game pays the extraction cost at most once, ever). A failed
## extraction leaves "" and is not retried - the title card covers it.
func ensure_art() -> String:
	if art_path != "" or art_source_path == "" or _art_attempted:
		return art_path
	_art_attempted = true
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
