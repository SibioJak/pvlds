class_name UnplacedFilesList
extends RefCounted

## The "files I couldn't place" list (IDENTITY round): a
## plain-text file naming every .vpx file the matcher could
## not place on any VPS db game - still local: after every
## tier, the rescue tier included - so the player can see
## exactly which files stand unidentified and why the wall
## shows them filename-only. Written into the app data
## folder on EVERY completed library scan (Main._finish_scan),
## from the scanner's own match record
## (LibraryScanner.unplaced_files) - never from a second
## filesystem walk, so the list can never disagree with what
## the app itself believes. Pure render plus a thin write;
## the desk's "Open list" button opens the file through
## globalized_path(). Mirrors MissingB2sList exactly.

const FILE_PATH: String = "user://unplaced_files.txt"


## The file's content: a short header (scan date + unplaced
## count), then one line per unplaced file - file name first,
## then the folder it lives in - alphabetical by file name
## (ties by folder, then full path, so the order is total
## and stable). Zero unplaced states it plainly instead of
## listing nothing.
static func render(unplaced_paths: Array[String], date_str: String) -> String:
	var sorted: Array[String] = []
	sorted.append_array(unplaced_paths)
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var an: String = a.get_file().to_lower()
		var bn: String = b.get_file().to_lower()
		if an != bn:
			return an < bn
		var ad: String = a.get_base_dir().to_lower()
		var bd: String = b.get_base_dir().to_lower()
		if ad != bd:
			return ad < bd
		return a < b)
	var lines: Array[String] = []
	lines.append("PVLDS - table files that match no database game")
	lines.append("Scan date: " + date_str)
	lines.append("Unplaced: %d" % sorted.size())
	lines.append("")
	if sorted.is_empty():
		lines.append("None unplaced - every table file matched a database game.")
	else:
		for path: String in sorted:
			lines.append("%s  (folder: %s)" % [path.get_file(), path.get_base_dir()])
	return "\n".join(lines) + "\n"


## Regenerate the file from a scan's unplaced record. An
## empty date_str stamps the system date.
static func write_file(unplaced_paths: Array[String], date_str: String = "") -> Error:
	var stamp: String = date_str if date_str != "" else Time.get_date_string_from_system()
	var f: FileAccess = FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(render(unplaced_paths, stamp))
	f.close()
	return OK


## Absolute OS path, for handing to the shell (the desk button).
static func globalized_path() -> String:
	return ProjectSettings.globalize_path(FILE_PATH)
