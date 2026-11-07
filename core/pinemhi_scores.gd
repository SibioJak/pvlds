class_name PinemhiScores
extends RefCounted

## NEXTROUND (item 4): the PINemHi personal-best reader.
##
## PVLDS never runs PINemHi or any agent; it READS the
## LeaderBoard TOP10 files an existing PINemHi install
## leaves behind:
##
##     <PINemHi folder>/PINemHi LeaderBoard/TOP10_Personal/<rom>.txt
##
## File shape (real fixture: Apollo 13): a banner line
## "PINEMHI ONLINE LEADERBOARD", the game title inside
## <<< ... >>>, then ranked rows in whitespace-separated
## columns - rank, the DOT-thousands-separated score in
## the file's own format (1.638.803.870), the player name,
## and a "date time" timestamp pair. The #1 row is the
## player's personal best; it is shown on the tournament
## board as a subordinate note line, never as a league
## score (RoomSpecs.tournament_board_spec).
##
## Everything here is read-only and silent on absence: no
## folder, no files, no match -> no line, anywhere.

const LEADERBOARD_DIR: String = "PINemHi LeaderBoard"
const PERSONAL_DIR: String = "TOP10_Personal"
const BEST_DIR: String = "TOP10_Best"

## Common install locations, tried in order when the
## config's folder is empty (Chris's own install is the
## first). A found folder with no LeaderBoard inside is
## still "the folder" - the reads below simply find no
## files and the feature stays silent.
const AUTO_DETECT_CANDIDATES: Array[String] = [
	"D:/vPinball/Pinemhi",
	"C:/vPinball/Pinemhi",
	"C:/Pinemhi",
]


## The folder the feature reads, or "" when the feature is
## off: disabled in config, or no configured folder and no
## auto-detect candidate exists.
static func resolve_folder(cfg: PvldsConfig) -> String:
	if cfg == null or not cfg.pinemhi_enabled:
		return ""
	if cfg.pinemhi_folder.strip_edges() != "":
		return cfg.pinemhi_folder.strip_edges()
	for cand: String in AUTO_DETECT_CANDIDATES:
		if DirAccess.dir_exists_absolute(cand):
			return cand
	return ""


## A parsed personal-best record for one game title:
## {key, title, score_text, score, player} - score_text is
## the file's own dotted rendering, shown verbatim.
## Returns {} when the file is not a parseable TOP10 file
## or carries no ranked rows.
static func parse_file(path: String) -> Dictionary:
	var full: Dictionary = parse_file_rows(path)
	if full.is_empty():
		return {}
	var rows: Array = full.get("rows", []) as Array
	if rows.is_empty():
		return {}
	var best: Dictionary = (rows[0] as Dictionary).duplicate()
	best["title"] = str(full.get("title", ""))
	best["key"] = str(full.get("key", ""))
	return best


## PINEMHI1: the file's FULL ranked row list, in file
## order: {title, key, rows: [{rank, score_text, score,
## player, when}]} - "when" is the row's "date time" pair
## verbatim ("" on a row shape that carries none). The
## card back renders these rows; parse_file above keeps
## serving the best-only consumers (the tournament
## board's note) off the same parse. Returns {} when the
## file is not a parseable TOP10 file or carries no
## ranked rows.
static func parse_file_rows(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var title: String = ""
	var rows: Array = []
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if title == "" and line.begins_with("<<<") and line.ends_with(">>>"):
			title = line.trim_prefix("<<<").trim_suffix(">>>").strip_edges()
			continue
		var row: Dictionary = _parse_row(line)
		if not row.is_empty():
			rows.append(row)
	if title == "" or rows.is_empty():
		return {}
	return {"title": title, "key": title_key(title), "rows": rows}


## One ranked row -> {rank, score_text, score, player}.
## {} for any other line (banners, blanks, the "TOP 10 ..."
## headers). The real file's columns are whitespace-
## separated: "1   1.638.803.870      Kubrick  2026-07-06
## 20:15:24" - rank, dotted score, player (may itself
## contain spaces), then the date and time tokens. A
## comma-separated rendering of the same columns is also
## accepted, in case another PINemHi vintage writes one.
static func _parse_row(line: String) -> Dictionary:
	if line.contains(","):
		var parts: PackedStringArray = line.split(",")
		if parts.size() < 3:
			return {}
		var crank: String = parts[0].strip_edges()
		var cscore: String = parts[1].strip_edges()
		var cdigits: String = cscore.replace(".", "").replace(" ", "")
		if not crank.is_valid_int() or cdigits == "" or not cdigits.is_valid_int():
			return {}
		return {
			"rank": crank.to_int(),
			"score_text": cscore,
			"score": cdigits.to_int(),
			"player": parts[2].strip_edges(),
			"when": "",
		}
	var tokens: PackedStringArray = line.split(" ", false)
	if tokens.size() < 5:
		return {}
	if not tokens[0].is_valid_int():
		return {}
	var score_s: String = tokens[1]
	var digits: String = score_s.replace(".", "")
	if digits == "" or not digits.is_valid_int():
		return {}
	var date_s: String = tokens[tokens.size() - 2]
	if date_s.length() != 10 or date_s.substr(4, 1) != "-" or date_s.substr(7, 1) != "-":
		return {}
	var player: String = " ".join(tokens.slice(2, tokens.size() - 2))
	if player == "":
		return {}
	return {
		"rank": tokens[0].to_int(),
		"score_text": score_s,
		"score": digits.to_int(),
		"player": player,
		"when": date_s + " " + tokens[tokens.size() - 1],
	}


## The match key for a title from either side of the wire:
## lowercase, punctuation to spaces, whitespace collapsed.
static func title_key(title: String) -> String:
	var out: String = ""
	var prev_space: bool = true
	for ch: String in title.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
			prev_space = false
		elif not prev_space:
			out += " "
			prev_space = true
	return out.strip_edges()


## The key a WoVP challenge's game name matches under: its
## table_name, with any trailing parenthetical qualifier
## ("Apollo 13 (Sega 1995)") dropped before keying - the
## PINemHi header carries the bare title.
static func challenge_key(table_name: String) -> String:
	var t: String = table_name.strip_edges()
	if t.ends_with(")"):
		var open: int = t.rfind("(")
		if open > 0:
			t = t.substr(0, open).strip_edges()
	return title_key(t)


## Every personal best under a PINemHi folder, keyed by
## title_key: {key: record}. Empty when the folder or its
## TOP10_Personal shelf is missing.
static func load_folder(folder: String) -> Dictionary:
	var out: Dictionary = {}
	if folder == "":
		return out
	var dir_path: String = folder.path_join(LEADERBOARD_DIR).path_join(PERSONAL_DIR)
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return out
	for file_name: String in da.get_files():
		if not file_name.to_lower().ends_with(".txt"):
			continue
		var rec: Dictionary = parse_file(dir_path.path_join(file_name))
		if rec.is_empty():
			continue
		var key: String = str(rec.get("key", ""))
		if key != "" and not out.has(key):
			out[key] = rec
	return out


## The config-driven read Main pushes to the room.
static func load_for_config(cfg: PvldsConfig) -> Dictionary:
	return load_folder(resolve_folder(cfg))


## PINEMHI1: every Personal file's FULL row list under a
## PINemHi folder, keyed by title_key: {key: {title,
## rows}}. The card back's read. Empty under the same
## absences load_folder is empty under.
static func load_folder_rows(folder: String) -> Dictionary:
	return _load_folder_rows_from(folder, PERSONAL_DIR)


## BACKFINE: every TOP10_Best file's FULL row list, same
## keying, same parser - the Best shelf is written by the
## same PINemHi program in the same shape as Personal (the
## file header carries the game's title inside <<< >>>;
## the shelf's own name is the only difference). The card
## back's online-best read: the world #1 line and, where
## the back's readability law lets them stand, the full
## list under the personal rows. NOTE: no real Best file
## exists in the build workspace - this parse stands as a
## same-writer assumption until a field check on a table
## with a real Best file (BACKFINE STATUS.md carries the
## flag). Empty under the same absences as Personal.
static func load_folder_best_rows(folder: String) -> Dictionary:
	return _load_folder_rows_from(folder, BEST_DIR)


static func _load_folder_rows_from(folder: String, shelf: String) -> Dictionary:
	var out: Dictionary = {}
	if folder == "":
		return out
	var dir_path: String = folder.path_join(LEADERBOARD_DIR).path_join(shelf)
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return out
	for file_name: String in da.get_files():
		if not file_name.to_lower().ends_with(".txt"):
			continue
		var rec: Dictionary = parse_file_rows(dir_path.path_join(file_name))
		if rec.is_empty():
			continue
		var key: String = str(rec.get("key", ""))
		if key != "" and not out.has(key):
			out[key] = {"title": str(rec.get("title", "")), "rows": rec.get("rows", [])}
	return out


## The config-driven full-row read Main pushes to the room.
static func load_rows_for_config(cfg: PvldsConfig) -> Dictionary:
	return load_folder_rows(resolve_folder(cfg))


## The config-driven Best read Main pushes to the room.
static func load_best_rows_for_config(cfg: PvldsConfig) -> Dictionary:
	return load_folder_best_rows(resolve_folder(cfg))


## The SETUP surfaces' standing line, in plain words.
static func status_line(cfg: PvldsConfig) -> String:
	if cfg == null or not cfg.pinemhi_enabled:
		return "PINemHi: off (personal-best lines on tournament boards are disabled)."
	var folder: String = resolve_folder(cfg)
	if folder == "":
		return "PINemHi: on, but no PINemHi folder found - set the folder to show your personal bests on tournament boards."
	var bests: Dictionary = load_folder(folder)
	if bests.is_empty():
		return "PINemHi: folder %s - no TOP10_Personal files found under it yet." % folder
	return "PINemHi: folder %s - %d personal best%s on file." % [folder, bests.size(), "" if bests.size() == 1 else "s"]
