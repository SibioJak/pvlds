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
