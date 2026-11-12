class_name VpxHunt
extends RefCounted

## AUTOFIND (FINISH LINE stage 1): the first-run hunt for the
## player's Visual Pinball install and table folders, so the
## Initial Setup desk can stand pre-filled instead of asking
## a stranger to Browse for an exe he may not know the
## location of. Existence checks only - fast, and never a
## deep scan. The desk proposes; Save & Scan persists.

## Exe names in hunt order: the GL build first (this is a VR
## product - the GL exe is the one that plays in the
## headset), then the plain 64-bit, then the 32-bit-era name.
## FIX113: the BGFX build's exe joins the hunt AFTER GL64 -
## a rig holding both keeps the GL build as the find (GL
## outranks BGFX), and a BGFX-only rig is found at all.
const EXE_NAMES: Array[String] = [
	"VPinballX_GL64.exe",
	"VPinballX_BGFX64.exe",
	"VPinballX64.exe",
	"VPinballX.exe",
]

## The standard install roots, relative to a drive root.
## FIX113: the beta program's roots join at the end - the
## 10.8.1 beta installs beside the release tree
## ("vPinball/VisualPinball BETA", field install) and BGFX
## builds commonly live in their own folder ("VPinballX_BGFX",
## the field user's own layout). Appended, so every existing
## root keeps its precedence.
const ROOT_PATTERNS: Array[String] = [
	"vPinball/VisualPinball",
	"Visual Pinball",
	"Program Files/Visual Pinball",
	"Program Files (x86)/Visual Pinball",
	"VPX",
	"vPinball/VisualPinball BETA",
	"VPinballX_BGFX",
]


## The Windows wrapper: every drive letter crossed with
## every root pattern. Drives that do not exist simply fail
## their existence checks inside the hunt - the list costs
## nothing but the checks themselves (a few hundred
## file_exists calls, all local).
static func windows_roots() -> Array:
	var roots: Array = []
	for letter: String in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		var drive: String = letter + ":"
		for pattern: String in ROOT_PATTERNS:
			roots.append(drive.path_join(pattern))
	return roots


## The pure hunt: roots in, result out.
## {found, exe_path, install_dir, table_folders, tables_total}
## - table_folders: an Array of {path, vpx_count}, deduped,
##   each holding at least one .vpx (shallow count).
## - tables_total: the summed .vpx count across those folders.
## The exe search is NAME-major: for each exe name in order,
## every root is checked; the first hit wins - so a GL build
## anywhere outranks a plain build in an earlier root.
static func hunt(roots: Array) -> Dictionary:
	var result: Dictionary = {
		"found": false,
		"exe_path": "",
		"install_dir": "",
		"table_folders": [],
		"tables_total": 0,
	}
	var install_dir: String = ""
	var exe_path: String = ""
	for exe_name: String in EXE_NAMES:
		for root_v: Variant in roots:
			var root: String = str(root_v)
			if root == "":
				continue
			var candidate: String = root.path_join(exe_name)
			if FileAccess.file_exists(candidate):
				exe_path = candidate
				install_dir = root
				break
		if exe_path != "":
			break
	if exe_path == "":
		return result
	result["found"] = true
	result["exe_path"] = exe_path
	result["install_dir"] = install_dir
	# The tables hunt, relative to the install: a Tables
	# folder inside it, or beside it (the vPinball layout's
	# D:\vPinball\Tables). Normalized + deduped; a candidate
	# is taken only if it exists and holds at least one .vpx.
	var parent: String = install_dir.get_base_dir()
	var candidates: Array[String] = [
		install_dir.path_join("Tables"),
		parent.path_join("Tables"),
	]
	var seen: Dictionary = {}
	var folders: Array = []
	var total: int = 0
	for cand: String in candidates:
		var norm: String = cand.simplify_path()
		if seen.has(norm):
			continue
		seen[norm] = true
		var count: int = count_vpx(norm)
		if count > 0:
			folders.append({"path": norm, "vpx_count": count})
			total += count
	result["table_folders"] = folders
	result["tables_total"] = total
	return result


## Shallow .vpx count of one folder (no recursion): the
## sanity check that a Tables candidate is a tables folder.
static func count_vpx(dir_path: String) -> int:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return 0
	var count: int = 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.to_lower().ends_with(".vpx"):
			count += 1
		name = dir.get_next()
	dir.list_dir_end()
	return count
