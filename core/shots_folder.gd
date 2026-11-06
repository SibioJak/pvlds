class_name ShotsFolder
extends RefCounted

## ROOMSUBMIT: the screenshots folder reader - the in-room
## WoVP score submission's photo shelf.
##
## The player takes his score screenshots in the headset
## (the league's own §7.1 method); they land in a folder on
## his PC - the folder he names in config (desk SETUP,
## Screenshots section). The submit panel lists that
## folder's image files NEWEST FIRST by modification time
## (his working set is "the shot I just took"), one of them
## stands large for the flicker check, and SEND posts the
## focused one through WovpClient - the same transaction
## the desk runs.
##
## Everything here is read-only and honest on absence: no
## folder set, a folder that is not there, a folder with no
## images in it - each is a stated state with its own words
## (status_line for the SETUP surfaces, panel_line for the
## submit panel), never a silent empty.

const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg"]


## One read of the folder: {exists, shots} - shots newest
## first by modification time (ties break on the name,
## descending: headset screenshot names are timestamped,
## so the name order is the time order when the clock's
## resolution ties). Each shot: {path, name, mtime}.
## Dotfiles are skipped - they are never a score photo.
static func scan(folder: String) -> Dictionary:
	var out: Dictionary = {"exists": false, "shots": []}
	if folder == "":
		return out
	var da: DirAccess = DirAccess.open(folder)
	if da == null:
		return out
	out["exists"] = true
	var shots: Array = []
	for file_name: String in da.get_files():
		if file_name.begins_with("."):
			continue
		if not IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var path: String = folder.path_join(file_name)
		shots.append({
			"path": path,
			"name": file_name,
			"mtime": FileAccess.get_modified_time(path),
		})
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["mtime"]) != int(b["mtime"]):
			return int(a["mtime"]) > int(b["mtime"])
		return str(a["name"]) > str(b["name"]))
	out["shots"] = shots
	return out


## The newest `limit` shots in a folder (the whole list
## when limit <= 0).
static func list_shots(folder: String, limit: int = 0) -> Array:
	var shots: Array = (scan(folder).get("shots", []) as Array)
	if limit > 0 and shots.size() > limit:
		return shots.slice(0, limit)
	return shots


## The SETUP surfaces' standing line (desk + in-room
## panel), in plain words - composed from the same read
## the submit panel makes, so every surface agrees.
static func status_line(cfg: PvldsConfig) -> String:
	if cfg == null or cfg.screenshots_folder.strip_edges() == "":
		return "Screenshots folder: not set - set it on the desktop desk and the room's score submission reads your photos from there."
	var folder: String = cfg.screenshots_folder.strip_edges()
	var res: Dictionary = scan(folder)
	if not bool(res.get("exists", false)):
		return "Screenshots folder: %s - that folder is not there right now." % folder
	var count: int = (res.get("shots", []) as Array).size()
	if count == 0:
		return "Screenshots folder: %s - no screenshots in it yet." % folder
	return "Screenshots folder: %s - %d screenshot%s on file, newest first in the room." % [folder, count, "" if count == 1 else "s"]


## The submit panel's shots line for the state it opened
## in: the folder read's truth in one plain sentence.
## ("ok" names the shelf the thumbs below stand on.)
static func panel_line(folder: String) -> String:
	if folder == "":
		return "No screenshots folder set yet - set it on the desktop desk (Screenshots section); the room reads photos from there."
	var res: Dictionary = scan(folder)
	if not bool(res.get("exists", false)):
		return "That screenshots folder is not there right now: %s" % folder
	var shots: Array = res.get("shots", []) as Array
	if shots.is_empty():
		return "No screenshots in that folder yet - take the shot in the headset first; it lands there."
	if shots.size() > 5:
		return "The newest 5 of %d screenshots in the folder - the focused one stands large above." % shots.size()
	return "Newest screenshots in the folder - the focused one stands large above."
