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

## STRUCKLIGHT: the monitor's NOT SUPPORTED marker line. When
## pinemhi_rom_monitor sees a ROM load that PINemHi cannot
## score, it leaves a .txt on the LeaderBoard shelves whose
## whole content is this one line, named by the ROM's stem
## (lsrcu_l2.txt on both TOP10 shelves and the 5-min twins).
## That file is PINemHi's own word that the ROM is not
## supported - install-local, version-true non-support
## certainty, the evidence the struck corner stands on.
const NOT_SUPPORTED_LINE: String = "NOT SUPPORTED YET BY ONLINE PINEMHI LEADERBOARD"

## STRUCKLIGHT: where the stem -> pretty-title name index
## lives. PINemHi >= 3.6.3 keeps it in romfind.ini beside
## pinemhi.ini; older vintages carry it as the [romfind]
## section inside pinemhi.ini. It is read ONLY as a name
## index (which title a marker's stem belongs to) - the
## MARKS finding stands: romfind lists every VPinMAME rom,
## supported or not, so it is never support evidence.
const ROMFIND_FILE: String = "romfind.ini"
const CONFIG_FILE: String = "pinemhi.ini"

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
## {key, title, score_text, score, player, stem} -
## score_text is the file's own dotted rendering, shown
## verbatim; stem is the shelf file's own ROM stem (the
## file's basename), the identity FIX132 resolves by.
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
	best["stem"] = str(full.get("stem", ""))
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
	return {"title": title, "key": title_key(title), "rows": rows,
		"stem": path.get_file().get_basename().to_lower()}


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


## FIX132: the negative-control seam, set by Main from
## PVLDS_FIX132_NC. "titlejoin" restores the pre-FIX132
## resolution road (the raw title-key map, no ROM road),
## so the fix132 legs fail by name against the field
## fault's own values.
static var debug_nc: String = ""


## FIX132: a ROM stem reduced to its lookup key -
## lowercase, [a-z0-9_] kept - the same reduction
## VpsDatabase.rom_key applies to the db's romFiles
## versions, so a db stem and a shelf file's stem meet
## on equal footing.
static func stem_key(s: String) -> String:
	var out: String = ""
	var lowered: String = s.strip_edges().to_lower()
	for i: int in range(lowered.length()):
		var code: int = lowered.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95:
			out += lowered[i]
	return out


## FIX132: every personal best under a PINemHi folder,
## keyed by ROM stem (stem_key of the file's basename):
## {stem_key: record}. The shelf files are NAMED by the
## ROM they score, so this map is the install's own
## identity index - the road that separates the two
## Batmen the title key cannot. First file per stem
## wins, the loaders' discipline.
static func load_folder_by_stem(folder: String) -> Dictionary:
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
		var key: String = stem_key(str(rec.get("stem", "")))
		if key != "" and not out.has(key):
			out[key] = rec
	return out


## The config-driven by-stem read.
static func load_by_stem_for_config(cfg: PvldsConfig) -> Dictionary:
	return load_folder_by_stem(resolve_folder(cfg))


## FIX132: the player's best over a set of ROM stems
## (one game's revisions, already stem_key-reduced):
## the highest #1 among the stems' shelf records; a
## tie goes to the latest #1 date, then to the first
## stem named. {} when no stem has a shelf file - the
## caller states that reason, never a silent absence.
static func best_for_stems(stem_map: Dictionary, stems: Array) -> Dictionary:
	var best: Dictionary = {}
	for sv: Variant in stems:
		var rec: Dictionary = stem_map.get(stem_key(str(sv)), {}) as Dictionary
		if rec.is_empty():
			continue
		if best.is_empty() or int(rec.get("score", 0)) > int(best.get("score", 0)) \
				or (int(rec.get("score", 0)) == int(best.get("score", 0)) \
					and str(rec.get("when", "")) > str(best.get("when", ""))):
			best = rec
	return best


## FIX132: the tournament boards' bests map, resolved.
## The pre-FIX132 road keyed everything by the shelf
## file's own title and looked challenges up by WoVP's
## short name - a join that bound the Stern "Batman"
## challenge to the 1991 game's record (its title keys
## exactly to "batman") while the Dark Knight record
## sat unconsulted under "batman the dark knight", and
## no refresh could move the wrong value because the
## read was faithfully fresh. The resolved map starts
## from the title map (every standing behaviour for
## anything the ROM road does not touch), then, for
## each challenge the db can identify, overrides its
## key with the best over the db record's own ROM list
## read from the shelf BY STEM - the identity that
## separates same-named games. Returns {bests, notes}:
## one note per challenge id stating the road taken and
## the value it serves, or the plain reason no best
## stands - Main logs every note that changes, so no
## verdict on this path is ever silent.
static func resolve_challenge_bests(cfg: PvldsConfig, db: VpsDatabase, challenges: Array) -> Dictionary:
	var title_map: Dictionary = load_for_config(cfg)
	if debug_nc == "titlejoin":
		return {"bests": title_map, "notes": {}}
	var out: Dictionary = title_map.duplicate()
	var notes: Dictionary = {}
	var folder: String = resolve_folder(cfg)
	if folder == "":
		return {"bests": out, "notes": notes}
	var stem_map: Dictionary = load_folder_by_stem(folder)
	for cv: Variant in challenges:
		var ch: WovpChallenge = cv as WovpChallenge
		if ch == null:
			continue
		var key: String = challenge_key(ch.table_name)
		var stems: Array = []
		if db != null and ch.table_external_id != "":
			stems = db.rom_keys_of(ch.table_external_id)
		var stem_rec: Dictionary = best_for_stems(stem_map, stems) if not stems.is_empty() else {}
		if not stem_rec.is_empty():
			out[key] = stem_rec
			notes[ch.challenge_id] = "%s: best %s via ROM %s (db identity)" % [
				ch.name, str(stem_rec.get("score_text", "")), str(stem_rec.get("stem", ""))]
		elif title_map.has(key):
			var trec: Dictionary = title_map[key] as Dictionary
			var why: String = "no db identity" if stems.is_empty() \
				else "db ROMs [%s] have no shelf files" % ", ".join(PackedStringArray(stems))
			notes[ch.challenge_id] = "%s: best %s via title key '%s' (%s)" % [
				ch.name, str(trec.get("score_text", "")), key, why]
		else:
			var why2: String = "no db identity; no title-key record for '%s'" % key if stems.is_empty() \
				else "db ROMs [%s] have no shelf files; no title-key record for '%s'" % [", ".join(PackedStringArray(stems)), key]
			notes[ch.challenge_id] = "%s: no personal best (%s)" % [ch.name, why2]
	return {"bests": out, "notes": notes}


## FIX132: the weekly boards' bests, resolved per
## contest: {contest_id: record}. The weekly site's own
## standings state the ROM each score was played on, so
## a contest's ROM set is first-hand evidence - the
## best over those stems is the contest table's best.
## The title key (the contest's table name against the
## shelf titles) is the fallback, stated in the notes
## Main logs on change, same discipline as the
## challenge road above.
static func resolve_weekly_bests(cfg: PvldsConfig, contests: Array) -> Dictionary:
	var out: Dictionary = {}
	var notes: Dictionary = {}
	var folder: String = resolve_folder(cfg)
	if folder == "" or contests.is_empty():
		return {"bests": out, "notes": notes}
	var title_map: Dictionary = load_folder(folder)
	var stem_map: Dictionary = load_folder_by_stem(folder)
	for cv: Variant in contests:
		var c: Dictionary = cv as Dictionary
		if c.is_empty():
			continue
		var cid: String = str(c.get("id", ""))
		var table: String = str(c.get("table", ""))
		var stems: Array = []
		for rv: Variant in (c.get("rows", []) as Array):
			var r: Dictionary = rv as Dictionary
			var rk: String = stem_key(str(r.get("rom", "")))
			if rk != "" and not stems.has(rk):
				stems.append(rk)
		var rec: Dictionary = best_for_stems(stem_map, stems) if not stems.is_empty() else {}
		if not rec.is_empty():
			out[cid] = rec
			notes["weekly:" + cid] = "%s (weekly): best %s via ROM %s (contest standings)" % [
				table, str(rec.get("score_text", "")), str(rec.get("stem", ""))]
			continue
		var key: String = challenge_key(table)
		var trec: Dictionary = title_map.get(key, {}) as Dictionary
		if not trec.is_empty():
			out[cid] = trec
			notes["weekly:" + cid] = "%s (weekly): best %s via title key '%s' (contest ROMs [%s] have no shelf files)" % [
				table, str(trec.get("score_text", "")), key, ", ".join(PackedStringArray(stems))]
		else:
			notes["weekly:" + cid] = "%s (weekly): no personal best (contest ROMs [%s] have no shelf files; no title-key record for '%s')" % [
				table, ", ".join(PackedStringArray(stems)), key]
	return {"bests": out, "notes": notes}


## FIX134: the weekly contests' tables resolved to db
## games: {contest_id: game_id}. The launch door (Part B)
## needs the contest's table as a library identity, and
## the identity that cannot confuse two same-named games
## is the ROM: the standings state the ROM each score was
## played on, so the db record whose romFiles carry a
## contest ROM is the contest's game. The ROM road must
## name exactly ONE record across all the contest's ROMs;
## shared or split ownership falls through to the name
## road (the db's normalized name index, exactly one
## record), and anything else stays unresolved with the
## reason stated in the notes Main logs on change - the
## board then stands unowned and says so, never launches.
static func resolve_weekly_games(db: VpsDatabase, contests: Array) -> Dictionary:
	var out: Dictionary = {}
	var notes: Dictionary = {}
	if db == null or contests.is_empty():
		return {"games": out, "notes": notes}
	for cv: Variant in contests:
		var c: Dictionary = cv as Dictionary
		if c.is_empty():
			continue
		var cid: String = str(c.get("id", ""))
		var table: String = str(c.get("table", ""))
		if cid == "":
			continue
		var roms: Array = []
		for rv: Variant in (c.get("rows", []) as Array):
			var r: Dictionary = rv as Dictionary
			var rk: String = stem_key(str(r.get("rom", "")))
			if rk != "" and not roms.has(rk):
				roms.append(rk)
		var owners: Array = []
		for rk2: Variant in roms:
			for oid: Variant in db.rom_owners(str(rk2)):
				if not owners.has(str(oid)):
					owners.append(str(oid))
		if owners.size() == 1:
			out[cid] = str(owners[0])
			notes["weekly:" + cid] = "%s (weekly): library game %s via ROM %s (contest standings)" % [
				table, str(owners[0]), ", ".join(PackedStringArray(roms))]
			continue
		var rom_why: String = "the contest standings carry no ROM" if roms.is_empty() \
			else "ROMs [%s] name %d db records" % [", ".join(PackedStringArray(roms)), owners.size()]
		var by_name: Array[String] = db.find_game_ids_by_name(VpsDatabase.normalize_name(table))
		if by_name.size() == 1:
			out[cid] = by_name[0]
			notes["weekly:" + cid] = "%s (weekly): library game %s via name (%s)" % [
				table, by_name[0], rom_why]
		else:
			notes["weekly:" + cid] = "%s (weekly): no library game (%s; the name names %d db records) - the board cannot launch it" % [
				table, rom_why, by_name.size()]
	return {"games": out, "notes": notes}


## FIX137: every Personal file's FULL row list under a
## PINemHi folder, keyed by ROM stem (stem_key of the
## file's basename): {stem_key: {title, rows, stem}}.
## The card back's by-ROM read - the shelf files are
## named by the ROM they score, so this map is the
## install's own identity index for full row lists,
## the twin of load_folder_by_stem for best records.
static func load_folder_rows_by_stem(folder: String) -> Dictionary:
	return _load_folder_rows_by_stem_from(folder, PERSONAL_DIR)


## FIX137: every TOP10_Best file's FULL row list, keyed
## by ROM stem - the card back's online section read
## by the same identity.
static func load_folder_best_rows_by_stem(folder: String) -> Dictionary:
	return _load_folder_rows_by_stem_from(folder, BEST_DIR)


static func _load_folder_rows_by_stem_from(folder: String, shelf: String) -> Dictionary:
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
		var key: String = stem_key(str(rec.get("stem", "")))
		if key != "" and not out.has(key):
			out[key] = {"title": str(rec.get("title", "")), "rows": rec.get("rows", []),
				"stem": str(rec.get("stem", ""))}
	return out


## FIX137: the winning full-row record over a set of ROM
## stems - the stem whose file's #1 row is the highest
## (a tie goes to the latest #1 date, then to the first
## stem named): best_for_stems' ordering over row lists,
## so the back's #1 line and the boards' best line are
## the same value by construction. {} when no stem has
## a shelf file - the caller states that reason.
static func rows_for_stems(stem_rows_map: Dictionary, stems: Array) -> Dictionary:
	var best: Dictionary = {}
	for sv: Variant in stems:
		var rec: Dictionary = stem_rows_map.get(stem_key(str(sv)), {}) as Dictionary
		var rows: Array = rec.get("rows", []) as Array
		if rec.is_empty() or rows.is_empty():
			continue
		if best.is_empty():
			best = rec
			continue
		var top: Dictionary = rows[0] as Dictionary
		var btop: Dictionary = (best.get("rows", []) as Array)[0] as Dictionary
		if int(top.get("score", 0)) > int(btop.get("score", 0)) \
				or (int(top.get("score", 0)) == int(btop.get("score", 0)) \
					and str(top.get("when", "")) > str(btop.get("when", ""))):
			best = rec
	return best


## FIX137: the library boards, resolved - the ONE door
## every library PINemHi surface reads through (the card
## backs' personal + online sections, the front corner
## marks, the detail view's mark). Before this round the
## backs joined the title-keyed row maps by the game's
## title shape, so two games sharing a title (the Stern
## and Data East Batmans) wore ONE board between them -
## the 1991 game's 23.043.670 stood on the Dark Knight's
## back while its season card read its own 250.432.010.
## The resolution is FIX132's, per library game: the db
## record's own ROM list read from the shelves BY STEM
## (personal and Best independently), the title key as
## the stated fallback per shelf, and the struck
## evidence read from the monitor's marker stems (the
## romfind title join as its fallback). One guard the
## challenge road never needed, stated plainly: the
## title fallback (and the struck title join) never
## serves a record whose file stem the db assigns to a
## DIFFERENT game - that record is the other game's
## board, and this shelf stands empty instead. The
## fallback still rescues the db-drift case it exists
## for: a shelf file whose stem no library game owns.
## Returns
## {boards, notes}: boards maps EVERY game's id to
## {personal, best, struck} (empty records where PINemHi
## holds nothing - the honest empty state); a note
## stands for every game PINemHi has any evidence on,
## stating the roads taken and the values served, or
## the plain absence - Main logs the changed ones, so
## no verdict on this path is ever silent. Under the
## debug_nc "titlejoin" seam the ROM road is skipped
## wholesale: the pre-FIX137 title join, so the fix137
## legs fail by name against the field fault's values.
static func resolve_library_boards(cfg: PvldsConfig, db: VpsDatabase, games: Array) -> Dictionary:
	var out: Dictionary = {}
	var notes: Dictionary = {}
	var folder: String = resolve_folder(cfg)
	if folder == "" or games.is_empty():
		return {"boards": out, "notes": notes}
	var title_road_only: bool = debug_nc == "titlejoin"
	var pers_by_stem: Dictionary = load_folder_rows_by_stem(folder)
	var best_by_stem: Dictionary = load_folder_best_rows_by_stem(folder)
	# The title maps the fallback reads, built from the
	# by-stem maps so every title record still carries the
	# stem of the file it came from (first file per key
	# wins, the loaders' discipline) - the cross-game
	# guard below needs the stem to know whose record a
	# title hit really is.
	var pers_by_title: Dictionary = {}
	for sk: Variant in pers_by_stem.keys():
		var srec: Dictionary = pers_by_stem[sk] as Dictionary
		var skey: String = title_key(str(srec.get("title", "")))
		if skey != "" and not pers_by_title.has(skey):
			pers_by_title[skey] = srec
	var best_by_title: Dictionary = {}
	for sk2: Variant in best_by_stem.keys():
		var srec2: Dictionary = best_by_stem[sk2] as Dictionary
		var skey2: String = title_key(str(srec2.get("title", "")))
		if skey2 != "" and not best_by_title.has(skey2):
			best_by_title[skey2] = srec2
	# Every stem the db assigns to any library game, and
	# its owner - the fallback's cross-game guard: a title
	# record whose file stem belongs to a DIFFERENT game
	# is that game's board, and is never served across.
	var stem_owner: Dictionary = {}
	if db != null and not title_road_only:
		for gv0: Variant in games:
			var g0: GameEntry = gv0 as GameEntry
			if g0 == null or g0.game_id == "":
				continue
			for rk: Variant in db.rom_keys_of(g0.game_id):
				if not stem_owner.has(str(rk)):
					stem_owner[str(rk)] = g0.game_id
	var marker_keys: Dictionary = {}
	for mk: Variant in load_folder_marker_stems(folder).keys():
		marker_keys[stem_key(str(mk))] = true
	var unsupported_keys: Dictionary = load_folder_unsupported_keys(folder)
	# The markers with their romfind title keys, for the
	# struck title road's own cross-game guard: a marker
	# whose stem belongs to another game strikes THAT
	# game (by stem), never this one by title shape.
	var marker_titles: Array = []
	var romfind_titles: Dictionary = romfind_stem_titles(folder)
	for mk2: Variant in load_folder_marker_stems(folder).keys():
		var mtitle: String = str(romfind_titles.get(str(mk2), ""))
		if mtitle != "":
			marker_titles.append({"stem": stem_key(str(mk2)), "key": challenge_key(mtitle)})
	for gv: Variant in games:
		var g: GameEntry = gv as GameEntry
		if g == null or g.game_id == "":
			continue
		var stems: Array = []
		if db != null and not title_road_only:
			stems = db.rom_keys_of(g.game_id)
		var tkey: String = challenge_key(g.title)
		var personal: Dictionary = {}
		var personal_road: String = ""
		var personal_why: String = ""
		var best: Dictionary = {}
		var best_road: String = ""
		var best_why: String = ""
		if not stems.is_empty():
			personal = rows_for_stems(pers_by_stem, stems)
			if not personal.is_empty():
				personal_road = "ROM " + str(personal.get("stem", ""))
			best = rows_for_stems(best_by_stem, stems)
			if not best.is_empty():
				best_road = "ROM " + str(best.get("stem", ""))
		if personal.is_empty():
			var trec: Dictionary = pers_by_title.get(tkey, {}) as Dictionary
			var tstem: String = stem_key(str(trec.get("stem", "")))
			var towner: String = str(stem_owner.get(tstem, ""))
			if not trec.is_empty() and (title_road_only or towner == "" or towner == g.game_id):
				personal = trec
				personal_road = "title"
			elif not trec.is_empty():
				personal_why = "db ROMs [%s] have no Personal shelf files; the title record is ROM %s's (another game's)" % [", ".join(PackedStringArray(stems)), str(trec.get("stem", ""))]
		if best.is_empty():
			var btrec: Dictionary = best_by_title.get(tkey, {}) as Dictionary
			var btstem: String = stem_key(str(btrec.get("stem", "")))
			var btowner: String = str(stem_owner.get(btstem, ""))
			if not btrec.is_empty() and (title_road_only or btowner == "" or btowner == g.game_id):
				best = btrec
				best_road = "title"
			elif not btrec.is_empty():
				best_why = "db ROMs [%s] have no Best shelf files; the title record is ROM %s's (another game's)" % [", ".join(PackedStringArray(stems)), str(btrec.get("stem", ""))]
		var struck: bool = false
		var struck_road: String = ""
		if not title_road_only:
			for sv2: Variant in stems:
				if marker_keys.has(stem_key(str(sv2))):
					struck = true
					struck_road = "ROM " + str(sv2)
					break
			if not struck:
				for mv: Variant in marker_titles:
					var md: Dictionary = mv as Dictionary
					if str(md.get("key", "")) != tkey:
						continue
					var mowner: String = str(stem_owner.get(str(md.get("stem", "")), ""))
					if mowner == "" or mowner == g.game_id:
						struck = true
						struck_road = "title"
						break
		if not struck and title_road_only and unsupported_keys.has(tkey):
			struck = true
			struck_road = "title"
		out[g.game_id] = {"personal": personal, "best": best, "struck": struck}
		if personal.is_empty() and best.is_empty() and not struck:
			continue
		var why: String = "no db identity" if stems.is_empty() and not title_road_only \
			else "db ROMs [%s] have no shelf files" % ", ".join(PackedStringArray(stems)) \
			if not stems.is_empty() else "the titlejoin NC road"
		var ptxt: String = "no personal rows (%s)" % (personal_why if personal_why != "" else why) if personal.is_empty() else \
			"personal %s via %s" % [str((personal.get("rows", []) as Array)[0].get("score_text", "")),
				personal_road if personal_road != "title" else "title key '%s' (%s)" % [tkey, why]]
		var btxt: String = "no online rows (%s)" % (best_why if best_why != "" else why) if best.is_empty() else \
			"online %s via %s" % [str((best.get("rows", []) as Array)[0].get("score_text", "")),
				best_road if best_road != "title" else "title key '%s' (%s)" % [tkey, why]]
		var line: String = "%s (library): %s; %s" % [g.title, ptxt, btxt]
		if struck:
			line += "; PINemHi does not support it (marker via %s)" % struck_road
		notes[g.game_id] = line
	return {"boards": out, "notes": notes}


## PINEMHI2: the player's own PINemHi name, derived from
## his TOP10_Personal files: each file's #1 row is a best
## row (load_folder's records ARE the files' best rows),
## and its player is the name he registered with - the
## most frequent player among the files' best rows is
## that name ("Kubrick" in his install). "" when there
## are no files to read. Ties resolve to the first name
## met in title-key order, so the answer is stable.
static func player_name_for_config(cfg: PvldsConfig) -> String:
	var records: Dictionary = load_for_config(cfg)
	if records.is_empty():
		return ""
	var counts: Dictionary = {}
	var keys: Array = records.keys()
	keys.sort()
	for k: Variant in keys:
		var rec: Dictionary = records[k] as Dictionary
		var player: String = str(rec.get("player", "")).strip_edges()
		if player == "":
			continue
		counts[player] = int(counts.get(player, 0)) + 1
	var best_name: String = ""
	var best_count: int = 0
	var names: Array = counts.keys()
	names.sort()
	for n: Variant in names:
		var c: int = int(counts[n])
		if c > best_count:
			best_count = c
			best_name = str(n)
	return best_name


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


## (FIX137: the config-driven full-row reads Main used to
## push straight to the room - load_rows_for_config /
## load_best_rows_for_config - are deleted. The room's
## one door is resolve_library_boards above; these folder
## loaders survive only as its shelf readers and the
## title fallback's read.)


## STRUCKLIGHT: the ROM stems PINemHi's monitor has marked
## NOT SUPPORTED on one LeaderBoard shelf: {stem: true} for
## every .txt whose content carries the marker line. Silent
## on every absence, like every read here.
static func marker_stems_in_shelf(folder: String, shelf: String) -> Dictionary:
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
		var text: String = FileAccess.get_file_as_string(dir_path.path_join(file_name))
		if text.contains(NOT_SUPPORTED_LINE):
			out[file_name.get_basename().to_lower()] = true
	return out


## STRUCKLIGHT: the marker stems across the two TOP10
## shelves, unioned - the same program leaves the same
## answer on both, so either shelf's word stands.
static func load_folder_marker_stems(folder: String) -> Dictionary:
	var out: Dictionary = marker_stems_in_shelf(folder, PERSONAL_DIR)
	for stem: Variant in marker_stems_in_shelf(folder, BEST_DIR):
		out[stem] = true
	return out


## STRUCKLIGHT: the romfind name index under a PINemHi
## folder: {stem: pretty title}. Read from romfind.ini in
## the install root; when that file is missing or carries
## no entries, the [romfind] section of pinemhi.ini serves
## (the older vintages' home for the same list). Lines are
## "Pretty Title (rev)=stem.nv"; ";" comments, blank lines
## and other sections' entries never join. A file with no
## section header at all is read as bare entries (the
## standalone romfind.ini shape); once a header stands,
## only [romfind]'s entries count. First entry for a stem
## wins, the loaders' discipline.
static func romfind_stem_titles(folder: String) -> Dictionary:
	if folder == "":
		return {}
	var out: Dictionary = _parse_romfind(folder.path_join(ROMFIND_FILE))
	if not out.is_empty():
		return out
	return _parse_romfind(folder.path_join(CONFIG_FILE))


static func _parse_romfind(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return out
	var in_section: bool = true ## bare entries stand until a header says otherwise
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			in_section = line.trim_prefix("[").trim_suffix("]").strip_edges().to_lower() == "romfind"
			continue
		if not in_section:
			continue
		var eq: int = line.find("=")
		if eq <= 0:
			continue
		var title: String = line.substr(0, eq).strip_edges()
		var stem: String = line.substr(eq + 1).strip_edges().get_file().to_lower()
		if stem.ends_with(".nv"):
			stem = stem.left(stem.length() - 3)
		if title == "" or stem == "" or out.has(stem):
			continue
		out[stem] = title
	return out


## STRUCKLIGHT: the unsupported title-key set for one
## PINemHi folder: {challenge_key: true} for every marker
## stem the romfind index joins to a title. A marker stem
## with no join contributes nothing (no name, no mark -
## the honesty rule), and no markers or no romfind means
## the empty set: the struck corner stays dark, exactly
## the pre-STRUCKLIGHT behaviour.
static func load_folder_unsupported_keys(folder: String) -> Dictionary:
	var out: Dictionary = {}
	var stems: Dictionary = load_folder_marker_stems(folder)
	if stems.is_empty():
		return out
	var titles: Dictionary = romfind_stem_titles(folder)
	if titles.is_empty():
		return out
	for stem: Variant in stems:
		var title: String = str(titles.get(stem, ""))
		if title == "":
			continue
		var key: String = challenge_key(title)
		if key != "":
			out[key] = true
	return out


## (FIX137: the config-driven unsupported read Main used
## to push straight to the room is deleted with the other
## title-keyed pushes - the struck evidence reaches the
## room resolved per game, inside resolve_library_boards.)


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
