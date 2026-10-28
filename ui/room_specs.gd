class_name RoomSpecs
extends RefCounted

## Builders for the CardFace spec dictionaries the TextureFactory
## renders. Shared by the wall and the detail view so a table's card
## looks the same in both places. Pure data in, dictionary out.

const PALETTE: Array[Color] = [
	Color(0.55, 0.36, 0.10), # amber
	Color(0.16, 0.38, 0.55), # steel blue
	Color(0.45, 0.18, 0.42), # plum
	Color(0.14, 0.45, 0.36), # teal green
	Color(0.55, 0.22, 0.16), # brick
	Color(0.30, 0.34, 0.60), # indigo
	Color(0.48, 0.44, 0.16), # olive brass
	Color(0.20, 0.48, 0.62), # bright steel
]

const CARD_BG: Color = Color(0.055, 0.055, 0.095)
const BUTTON_BG: Color = Color(0.11, 0.11, 0.17)
const BUTTON_BG_ACCENT: Color = Color(0.36, 0.25, 0.06)


static func manufacturer_color(manufacturer: String) -> Color:
	if manufacturer == "":
		return Color(0.28, 0.28, 0.36)
	return PALETTE[absi(manufacturer.hash()) % PALETTE.size()]


static func panel_spec(game: GameEntry, store: StateStore) -> Dictionary:
	var chips: Array = []
	if game.is_vr_tagged():
		chips.append({"text": "VR", "accent": true})
	if game.build_count() > 1:
		chips.append({"text": "%d BUILDS" % game.build_count(), "accent": false})
	if store != null and store.is_favorite(game.game_id):
		chips.append({"text": "FAVORITE", "accent": true})
	# The build/file line: the exact file Play would launch (the
	# player's default build), as ONE ellipsized line - the wall is a
	# browsing surface, and the full string lives in the detail view.
	# Skipped when it would merely repeat the title: a filename-
	# identified game carries its file stem AS its title, and the
	# two-line title cap below already disciplines it there.
	var file_line: String = ""
	var def: TableBuild = game.resolve_default_build(store)
	if def != null:
		var stem: String = def.file_name.get_basename()
		if stem != "" and stem != game.title:
			file_line = stem
	return {
		"kind": "panel",
		"bg": CARD_BG,
		"band": manufacturer_color(game.manufacturer),
		"band_text": game.manufacturer if game.manufacturer != "" else "Unknown maker",
		"title": game.title,
		"title_size": 60,
		"title_max_lines": 2,
		"sub": "%s - %s" % [game.year_text(), game.designer_text()],
		"sub_size": 30,
		"sub_max_lines": 1,
		"body": file_line,
		"body_size": 26,
		"body_max_lines": 1,
		"chips": chips,
	}


static func art_spec(game: GameEntry, art_texture: Texture2D, store: StateStore) -> Dictionary:
	return {
		"kind": "art",
		"art_texture": art_texture,
		"title": game.title,
		# The favorite mark: the panel face shows a FAVORITE chip
		# (panel_spec, above); the art face carries the same fact
		# as a star badge (CardFace draws it). One store, one truth,
		# mirrored on both face kinds.
		"favorite": store != null and store.is_favorite(game.game_id),
	}


static func info_spec(game: GameEntry, store: StateStore) -> Dictionary:
	var current: TableBuild = game.current_build()
	var def: TableBuild = game.resolve_default_build(store)
	var body: String = "Designer: %s\nBuilds: %d - Current: v%s - Default: v%s" % [
		game.designer_text(), game.build_count(),
		current.display_version() if current != null else "?",
		def.display_version() if def != null else "?"]
	if game.build_count() > MAX_LISTED_NOTE:
		body += "\n(+%d more builds on disk)" % (game.build_count() - MAX_LISTED_NOTE)
	return {
		"kind": "info",
		"bg": CARD_BG,
		"band": manufacturer_color(game.manufacturer),
		"band_text": game.manufacturer if game.manufacturer != "" else "Unknown maker",
		"title": game.title,
		"title_size": 62,
		"sub": "%s - %s" % [game.manufacturer, game.year_text()],
		"sub_size": 32,
		"body": body,
		"body_size": 34,
	}


const MAX_LISTED_NOTE: int = 6


static func row_spec(b: TableBuild, is_current: bool, is_default: bool, is_selected: bool, is_once: bool) -> Dictionary:
	var chips: Array = []
	if is_current:
		chips.append({"text": "CURRENT", "accent": true})
	if is_default:
		chips.append({"text": "DEFAULT", "accent": true})
	if is_once:
		chips.append({"text": "PLAY ONCE ARMED", "accent": true})
	elif is_selected:
		chips.append({"text": "SELECTED", "accent": false})
	var sub: String = "%s - %s" % [b.authors_text(), b.date_text()]
	if not b.matched_db:
		sub += " - not in database"
	return {
		"kind": "row",
		"bg": Color(0.075, 0.075, 0.12) if is_selected else Color(0.05, 0.05, 0.085),
		"title": "v%s" % b.display_version(),
		"title_size": 42,
		"sub": sub,
		"sub_size": 27,
		"chips": chips,
	}


static func button_spec(text: String, accent: bool) -> Dictionary:
	return {
		"kind": "button",
		"bg": BUTTON_BG_ACCENT if accent else BUTTON_BG,
		"title": text,
		"title_size": 40,
	}


## One alphabet-strip slot's face (the letter-jump round): a
## single big glyph on the button family, in one of three
## states - "plain" (a pickable letter), "accent" (the net
## slot whose view is standing: THE or #), "dim" (a letter
## with no games in the current view - greyed, unpickable,
## its glyph gone quiet rather than merely its ground).
static func letter_spec(label: String, state: String) -> Dictionary:
	var bg: Color = BUTTON_BG
	var fg: Color = Color(0.96, 0.96, 0.98)
	if state == "accent":
		bg = BUTTON_BG_ACCENT
	elif state == "dim":
		bg = Color(0.06, 0.06, 0.09)
		fg = Color(0.36, 0.36, 0.45)
	return {
		"kind": "button",
		"bg": bg,
		"title": label,
		"title_size": 118,
		"title_color": fg,
	}


## The setup placard: what stands in the room while the desk pass
## is open on the monitor during an XR session (the desk itself
## cannot reach the headset). Rendered with the banner layout -
## centered title / sub / body, no band. The caller's message (a
## launch failure's reason) rides on top when one is provided.
static func placard_spec(message: String) -> Dictionary:
	var body: String = "Finish on the desktop, then come back - or go back to the room now with BACK below."
	if message != "":
		body = message + "\n\n" + body
	return {
		"kind": "banner",
		"bg": Color(0.05, 0.05, 0.09),
		"title": "SETUP",
		"title_size": 84,
		"sub": "Setup is open on your desktop",
		"sub_size": 42,
		"body": body,
		"body_size": 36,
	}


## The in-room SETUP panel's face: the library's health in
## words, with the last action's outcome riding as the sub
## line. Health is a plain dictionary of the last completed
## scan's numbers (Main builds it in _setup_panel_health);
## an empty one means no scan has landed yet. Plain words,
## one fact per line - the panel's whole job is to be read at
## a glance in the headset.
static func setup_panel_spec(health: Dictionary, message: String) -> Dictionary:
	var lines: Array[String] = []
	if not health.has("files"):
		lines.append("Not scanned yet - press SCAN LIBRARY below.")
	else:
		var files: int = int(health.get("files", 0))
		lines.append("%d table files - %d games" % [files, int(health.get("games", 0))])
		if bool(health.get("db_ok", false)):
			var matched_line: String = "Database matched %d of %d builds" % [int(health.get("matched", 0)), files]
			var by_game: int = int(health.get("game_matched", 0))
			if by_game > 0:
				matched_line += " (%d more by game only)" % by_game
			lines.append(matched_line)
		else:
			lines.append("No database loaded - games are named from their file names alone.")
		if str(health.get("db_kind", "")) == "sample":
			lines.append("That database is the bundled SAMPLE - it cannot identify real tables. Download the VPS database below.")
		var missing: int = int(health.get("missing", 0))
		if missing > 0:
			lines.append("Missing backglass: %d table files have no .directb2s beside them. The list is missing_b2s.txt in the app data folder." % missing)
		else:
			lines.append("Missing backglass: none - every table file has a .directb2s beside it.")
	# The WoVP line (the Tournament Room round): Main composes
	# it in _setup_panel_health from the config + the last
	# validation - whose key is saved here, in plain words.
	if health.has("wovp_line"):
		lines.append(str(health["wovp_line"]))
	return {
		"kind": "banner",
		"bg": Color(0.05, 0.05, 0.09),
		"title": "SETUP",
		"title_size": 76,
		"sub": message if message != "" else "Scan the library and fetch the database - right here, no desktop trip.",
		"sub_size": 38,
		"body": "\n".join(lines),
		"body_size": 34,
	}


## One Tournament Room board face: a challenge's standings
## on its table's wall panel, glanceable - the leader, his
## own row on the accent ground, the rows around the cutoff
## line and the line itself, and the deadline in his own
## clock with the time left. The row composition is the
## challenge's own mathematics (WovpChallenge.board_rows);
## this spec only dresses it. A table he does not own still
## gets its board - with the NOT IN YOUR LIBRARY chip, and
## the room gives it no Launch button.
static func tournament_board_spec(ch: WovpChallenge, owned: bool, user_id: String, now_unix: int) -> Dictionary:
	var rows: Array = []
	for entry: Variant in ch.board_rows(user_id):
		var e: Dictionary = entry
		match str(e.get("kind", "")):
			"score":
				var r: WovpScoreRow = e.get("row") as WovpScoreRow
				if r == null:
					continue
				var line: String = "#%d  %s  %s" % [r.position, r.participant_name, WovpChallenge.format_score(r.score)]
				if r.is_pending:
					line += " - awaiting validation"
				rows.append({
					"kind": "score", "text": line,
					"accent": bool(e.get("mine", false)),
					"size": 44 if bool(e.get("mine", false)) else 40,
				})
			"divider":
				rows.append({"kind": "divider", "text": str(e.get("label", "")), "size": 30})
			"note":
				rows.append({"kind": "note", "text": str(e.get("text", "")), "size": 34})
	var chips: Array = []
	if not owned:
		chips.append({"text": "NOT IN YOUR LIBRARY", "accent": true})
	var title: String = ch.table_name if ch.table_name != "" else ch.name
	return {
		"kind": "board",
		"bg": CARD_BG,
		"band": manufacturer_color(ch.table_manufacturer),
		"band_text": "%s - %s" % [ch.type_label(), ch.name],
		"title": title,
		"title_size": 52,
		"title_max_lines": 1,
		"sub": "Ends %s - %s" % [WovpTime.format_deadline(ch.end_unix), WovpTime.format_remaining(ch.end_unix, now_unix)],
		"sub_size": 30,
		"sub_max_lines": 1,
		"chips": chips,
		"rows": rows,
	}


## A Tournament Room state face: the wall has no boards to
## show and says why, in plain words - no key yet, a fetch
## that failed with nothing saved, no live challenges. A
## state is a board-shaped panel so it stands in the same
## grid and reads at the same distance.
static func tournament_state_spec(lines: Array) -> Dictionary:
	var rows: Array = []
	for line: Variant in lines:
		rows.append({"kind": "note", "text": str(line), "size": 38})
	return {
		"kind": "board",
		"bg": CARD_BG,
		"band": Color(0.28, 0.28, 0.36),
		"band_text": "TOURNAMENT ROOM",
		"title": "Tournament Room",
		"title_size": 52,
		"title_max_lines": 1,
		"sub": "",
		"rows": rows,
	}


static func banner_spec(line: String) -> Dictionary:
	return {
		"kind": "banner",
		"bg": Color(0.04, 0.04, 0.07),
		"title": "PVLDS",
		"title_size": 92,
		"sub": line,
		"sub_size": 34,
	}
