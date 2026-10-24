class_name MissingB2sList
extends RefCounted

## The missing-backglass shopping list (Chris's ask, 2026-10-23):
## a plain-text file naming every .vpx file that has no same-stem
## .directb2s beside it, so the player knows exactly which
## backglasses to go download. Written into the app data folder
## on EVERY completed library scan (Main._finish_scan), from the
## scanner's own pairing record (LibraryScanner.missing_b2s_files)
## - never from a second filesystem walk, so the list can never
## disagree with what the app itself believes. Pure render plus a
## thin write; the desk's "Open list" button opens the file
## through globalized_path().

const FILE_PATH: String = "user://missing_b2s.txt"


## The file's content: a short header (scan date + missing
## count), then one line per missing file - file name first, then
## the folder it lives in - alphabetical by file name (ties by
## folder, then full path, so the order is total and stable).
## Zero missing states it plainly instead of listing nothing.
static func render(missing_paths: Array[String], date_str: String) -> String:
	var sorted: Array[String] = []
	sorted.append_array(missing_paths)
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
	lines.append("PVLDS - table files with no backglass file (.directb2s)")
	lines.append("Scan date: " + date_str)
	lines.append("Missing: %d" % sorted.size())
	lines.append("")
	if sorted.is_empty():
		lines.append("None missing - every table file has a .directb2s beside it.")
	else:
		for path: String in sorted:
			lines.append("%s  (folder: %s)" % [path.get_file(), path.get_base_dir()])
	return "\n".join(lines) + "\n"


## Regenerate the file from a scan's missing record. An empty
## date_str stamps the system date.
static func write_file(missing_paths: Array[String], date_str: String = "") -> Error:
	var stamp: String = date_str if date_str != "" else Time.get_date_string_from_system()
	var f: FileAccess = FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(render(missing_paths, stamp))
	f.close()
	return OK


## Absolute OS path, for handing to the shell (the desk button).
static func globalized_path() -> String:
	return ProjectSettings.globalize_path(FILE_PATH)
