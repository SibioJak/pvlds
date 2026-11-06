class_name StateStore
extends RefCounted

## Player state that must survive the launcher's exit/relaunch cycle:
## favorites, per-game default build, recents. Plain JSON at user://.

const STATE_FILE_NAME: String = "pvlds_state.json"
const MAX_RECENTS: int = 14

var favorites: Dictionary = {} ## game_id -> true
var default_builds: Dictionary = {} ## game_id -> .vpx file path
var recents: Array[String] = [] ## game ids, most recent first
var last_played_game_id: String = "" ## set by LaunchService on every Play
var last_played_build_path: String = ""
# Room view state, so the watchdog's relaunch lands the player exactly
# where they left: same filter, sort, page, and selected game - with
# the just-played table selected (design section 3, step 4).
var view_filter: String = ""
var view_sort: String = ""
var view_page: int = 0
var selected_game_id: String = ""
# RETURN round: the return-to-origin record. Written by Main at
# every good launch spawn ({surface: "library"|"tournament",
# challenge_id, stamp}) and consumed - read once, then cleared -
# by the next room entry, so the watchdog's relaunch lands the
# player on the surface that launched the table: a tournie launch
# returns to the Tournament Room at its challenge, a library
# launch to the library as always. A failed load clears it (no
# session, no return owed). Empty = no return pending.
var return_origin: Dictionary = {}
# GRADFIX11 (the NEW filter, Chris's order): the file-age
# tracker. Scan results are not otherwise persisted, so
# the library's memory of when each .vpx file first
# appeared - and when its mtime/size signature last
# changed - lives here, in the library's existing
# persisted state. path -> {"first": int, "changed": int,
# "mtime": int, "size": int}: "first"/"changed" are the
# NEW verdict's stamps (see apply_scan_facts), "mtime"/
# "size" the last signature those stamps were judged
# against. file_ages_seeded marks that the one-time
# seeding pass (first = each file's own mtime, so a
# library scanned for the first time does not read as
# all-new) has happened.
var file_ages: Dictionary = {}
var file_ages_seeded: bool = false


static func state_path() -> String:
	return "user://".path_join(STATE_FILE_NAME)


func load_from_disk() -> void:
	var path: String = StateStore.state_path()
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	var favs: Variant = d.get("favorites", [])
	if favs is Array:
		var arr: Array = favs
		for item: Variant in arr:
			favorites[str(item)] = true
	var defs: Variant = d.get("default_builds", {})
	if defs is Dictionary:
		var dd: Dictionary = defs
		for k: Variant in dd.keys():
			default_builds[str(k)] = str(dd[k])
	recents.clear()
	var rec: Variant = d.get("recents", [])
	if rec is Array:
		var rarr: Array = rec
		for item: Variant in rarr:
			var gid: String = str(item)
			if gid != "" and not recents.has(gid):
				recents.append(gid)
	while recents.size() > MAX_RECENTS:
		recents.pop_back()
	last_played_game_id = str(d.get("last_played_game_id", ""))
	last_played_build_path = str(d.get("last_played_build_path", ""))
	view_filter = str(d.get("view_filter", ""))
	view_sort = str(d.get("view_sort", ""))
	view_page = int(d.get("view_page", 0))
	selected_game_id = str(d.get("selected_game_id", ""))
	# RETURN: the return-origin record, parsed as tolerantly as
	# the fields above - anything that is not a dictionary of
	# the written shape is simply no record.
	return_origin = {}
	var ro: Variant = d.get("return_origin", {})
	if ro is Dictionary:
		var rd: Dictionary = ro as Dictionary
		if str(rd.get("surface", "")) != "":
			return_origin = {
				"surface": str(rd.get("surface", "")),
				"challenge_id": str(rd.get("challenge_id", "")),
				"stamp": int(rd.get("stamp", 0)),
			}
	# GRADFIX11: the file-age tracker round-trips with the
	# rest of the state, parsed as tolerantly as the fields
	# above - a record that is not a dictionary, or a state
	# file written before the tracker existed, simply
	# leaves that path (or the whole map) untracked.
	file_ages.clear()
	var ages: Variant = d.get("file_ages", {})
	if ages is Dictionary:
		var ad: Dictionary = ages
		for k: Variant in ad.keys():
			var age_rec: Variant = ad[k]
			if age_rec is Dictionary:
				var rd: Dictionary = age_rec
				file_ages[str(k)] = {
					"first": int(rd.get("first", 0)),
					"changed": int(rd.get("changed", 0)),
					"mtime": int(rd.get("mtime", 0)),
					"size": int(rd.get("size", 0)),
				}
	file_ages_seeded = bool(d.get("file_ages_seeded", false))


func save_to_disk() -> void:
	var d: Dictionary = {}
	var favs: Array = []
	for k: Variant in favorites.keys():
		favs.append(str(k))
	d["favorites"] = favs
	d["default_builds"] = default_builds
	var rec: Array = []
	for gid: String in recents:
		rec.append(gid)
	d["recents"] = rec
	d["last_played_game_id"] = last_played_game_id
	d["last_played_build_path"] = last_played_build_path
	d["view_filter"] = view_filter
	d["view_sort"] = view_sort
	d["view_page"] = view_page
	d["selected_game_id"] = selected_game_id
	d["return_origin"] = return_origin
	d["file_ages"] = file_ages
	d["file_ages_seeded"] = file_ages_seeded
	var file: FileAccess = FileAccess.open(StateStore.state_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(d, "\t"))
	file.close()


func is_favorite(game_id: String) -> bool:
	return favorites.has(game_id)


func set_favorite(game_id: String, on: bool) -> void:
	if on:
		favorites[game_id] = true
	else:
		favorites.erase(game_id)


func get_default_build(game_id: String) -> String:
	return str(default_builds.get(game_id, ""))


func set_default_build(game_id: String, file_path: String) -> void:
	default_builds[game_id] = file_path


func touch_recent(game_id: String) -> void:
	recents.erase(game_id)
	recents.push_front(game_id)
	while recents.size() > MAX_RECENTS:
		recents.pop_back()


func set_last_played(game_id: String, build_path: String) -> void:
	last_played_game_id = game_id
	last_played_build_path = build_path
	selected_game_id = game_id


## The room calls this whenever its view moves; cheap fields, saved
## by the caller's next save_to_disk().
func set_view_state(filter: String, sort: String, page: int, selected: String) -> void:
	view_filter = filter
	view_sort = sort
	view_page = page
	if selected != "":
		selected_game_id = selected


## RETURN round: record where a launch came from. The caller
## (Main) saves immediately - the record must be on disk before
## the load wait can exit the process at hand-off.
func set_return_origin(origin: Dictionary) -> void:
	return_origin = origin.duplicate()


## RETURN round: the record is one-shot. Room entry consumes it
## (applied or not), and a failed load clears it - either way it
## never survives past the first landing it was written for.
func clear_return_origin() -> void:
	return_origin = {}


## GRADFIX11 (the NEW filter): fold one landed scan's file
## facts into the tracker. facts is path -> {"mtime": int,
## "size": int} - the scanner's raw signature for every
## .vpx the scan found, built by Main in _finish_scan (the
## scan itself records the facts on each TableBuild and
## stays pure; this merge is main-thread, once per landed
## scan). Rules:
## - First ever run (not seeded): a file's first-seen is
##   its own MTIME, not the scan time - the existing
##   library's ages are its files' real ages, so only
##   files whose mtimes fall inside the NEW window read
##   as new, and a first scan never floods the filter.
## - After seeding: a path with no record is a genuine
##   arrival - first-seen is the SCAN time (now), however
##   old the file's mtime is (a table downloaded from an
##   old zip is new TO THE LIBRARY when it lands).
## - A recorded path whose mtime or size moved has
##   changed in place: "changed" becomes now, first-seen
##   is preserved (the game is new AGAIN, not new-born).
## - An identical signature leaves the record untouched.
## - A recorded path absent from facts is forgotten: a
##   deleted file's record dies with it, so the same path
##   returning in a later scan is first-seen again.
## NC seam (the house pattern, cf. LibraryScanner.
## _referee_survivors): PVLDS_GRADFIX11_NC=notrack makes
## this a no-op - nothing is ever recorded - so the core
## test's "new filter:" legs fail against it by name.
func apply_scan_facts(facts: Dictionary, now: int) -> void:
	if OS.get_environment("PVLDS_GRADFIX11_NC") == "notrack":
		return
	var seeding: bool = not file_ages_seeded
	for path_v: Variant in facts.keys():
		var path: String = str(path_v)
		var fact_v: Variant = facts[path_v]
		if not (fact_v is Dictionary):
			continue
		var fact: Dictionary = fact_v
		var mtime: int = int(fact.get("mtime", 0))
		var size: int = int(fact.get("size", 0))
		var rec_v: Variant = file_ages.get(path, null)
		if rec_v is Dictionary:
			var rec: Dictionary = rec_v
			if int(rec.get("mtime", 0)) != mtime or int(rec.get("size", 0)) != size:
				rec["changed"] = now
				rec["mtime"] = mtime
				rec["size"] = size
				file_ages[path] = rec
			# Identical signature: the record stands as is.
		else:
			var stamp: int = mtime if seeding else now
			file_ages[path] = {"first": stamp, "changed": stamp, "mtime": mtime, "size": size}
	# Forgetting: any recorded path this scan did not see
	# is gone from the library, and its record goes with it.
	var gone: Array[String] = []
	for known_v: Variant in file_ages.keys():
		var known: String = str(known_v)
		if not facts.has(known):
			gone.append(known)
	for known_path: String in gone:
		file_ages.erase(known_path)
	file_ages_seeded = true


## A file's recency for the NEW verdict: the later of its
## first-seen and last-changed stamps, 0 when the tracker
## holds no record of the path.
func file_recency(path: String) -> int:
	var rec_v: Variant = file_ages.get(path, null)
	if rec_v is Dictionary:
		var rec: Dictionary = rec_v
		return maxi(int(rec.get("first", 0)), int(rec.get("changed", 0)))
	return 0
