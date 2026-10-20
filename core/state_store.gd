class_name StateStore
extends RefCounted

## Player state that must survive the launcher's exit/relaunch cycle:
## favorites, per-game default build, recents. Plain JSON at user://.

const STATE_FILE_NAME: String = "pvlds_state.json"
const MAX_RECENTS: int = 14

var favorites: Dictionary = {} ## game_id -> true
var default_builds: Dictionary = {} ## game_id -> .vpx file path
var recents: Array[String] = [] ## game ids, most recent first


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
