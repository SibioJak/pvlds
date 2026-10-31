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

## ---- Tournament board presentation (the TR3 polish round).
## Boards are NOT table cards: they stand at their own, larger
## window and render at their own face size, and an owned
## board's face reserves a footer band at its bottom where
## the room parks the Launch button - over the band, never
## over board text (Chris's field catches, 2026-10-28: "launch
## buttons are in way, scores getting cut off"; "probably
## room to expand the windows and not the same as table
## windows, liven it up"). The pre-TR3 presentation survives
## only behind the harness's negative-control seam
## (PVLDS_BOARD_NC=oldlayout, read by Main before any room
## exists): the legacy values below restore it wholesale -
## card-size panels, the 512x640 face, the Launch button at
## RoomView.PANEL_LAUNCH_Y, no footer - so the layout legs
## can fail against it by name.
## The board's size since the GRAD FIX round's Tournament
## redesign: the board stands as furniture in the slot beside
## the centred challenge's art card, a touch narrower and
## notably taller than the old grid boards - the rows gain
## air, the score column keeps its law (the layout legs
## prove the worst case at this size). GRADFIX3 (the
## Standing Book) stood it at the card's WIDTH and a breath
## under its height - 1.00 m against the card's 1.08: the
## bands pitch 20 degrees apart, and a full-height book
## floated proud at the old wall radius spanned wider than
## the pitch, painting over the nameplate of the card above
## its slot and the art of the card below (the grad census
## measured it: ~1,400 px of cover against the borrowed
## card's own ~90).
## GRADFIX5 (the user's field verdict on GRADFIX4: "info
## panel is still a little smaller than art panel so they
## don't look hinged"): the page is now the card's EXACT
## size - 0.62 x 1.08, seated flush (RoomView.WING_Y = 0) -
## so art page and text page share top and bottom edges and
## the hinge reads. The headroom the GRADFIX3 inch was
## buying comes from the wall's move back instead
## (RoomView.WALL_RADIUS 3.40): the book floats its proud
## 0.30 in front of a 3.40 wall - 3.10 from the eye - where
## a 1.08 page spans 19.8 degrees against the bands' 20
## degree pitch, INSIDE its slot, where the old 1.00 page
## at the old radius (2.75 from the eye) spanned 20.6. The
## census's flush leg measures the equality (page vs card
## extents, 1 mm tolerance); the pre-fix short page stands
## behind the harness's negative-control seam
## (PVLDS_GRADFIX5_NC=shortpage, read by Main before any
## room exists) so the leg can fail against it by name.
const BOARD_PANEL_SIZE: Vector2 = Vector2(0.62, 1.08)
const BOARD_FACE_PX: Vector2i = Vector2i(620, 1080)
const SHORT_BOARD_PANEL_SIZE: Vector2 = Vector2(0.62, 1.00) ## the GRADFIX3/4 page (the shortpage NC's restore)
const SHORT_BOARD_FACE_PX: Vector2i = Vector2i(620, 1000)
const BOARD_FOOTER_PX: int = 140 ## the owned board face's bottom band: the Launch button's home
const LEGACY_BOARD_PANEL_SIZE: Vector2 = Vector2(0.54, 0.64) ## == RoomView.PANEL_SIZE at the TR1/TR2 rounds
const LEGACY_BOARD_FACE_PX: Vector2i = Vector2i(512, 640)
const LEGACY_BOARD_LAUNCH_Y: float = -0.155 ## == RoomView.PANEL_LAUNCH_Y

static var board_nc_old: bool = false ## Main sets this from PVLDS_BOARD_NC before any room exists
static var board_short_page: bool = false ## Main sets this from PVLDS_GRADFIX5_NC=shortpage before any room exists


static func board_panel_size() -> Vector2:
	if board_nc_old:
		return LEGACY_BOARD_PANEL_SIZE
	return SHORT_BOARD_PANEL_SIZE if board_short_page else BOARD_PANEL_SIZE


static func board_face_px() -> Vector2i:
	if board_nc_old:
		return LEGACY_BOARD_FACE_PX
	return SHORT_BOARD_FACE_PX if board_short_page else BOARD_FACE_PX


## The board Launch button's centre height on its panel: the
## middle of the face's footer band, in panel-local metres -
## the one place room.gd and the face layout both derive
## from, so the button can never drift back over the text.
static func board_launch_y() -> float:
	if board_nc_old:
		return LEGACY_BOARD_LAUNCH_Y
	var p: Vector2 = board_panel_size()
	return -p.y * 0.5 + (float(BOARD_FOOTER_PX) / float(board_face_px().y) * p.y) * 0.5


## A challenge type's identity colour - the board's band.
## The band carried the table's manufacturer colour through
## TR1/TR2; the type is what changes a board's mathematics
## (whether it draws a line, and where), so the type owns
## the band now. The manufacturer stays where it always
## lived: the library card and the detail view.
static func challenge_type_color(type_code: String) -> Color:
	match type_code:
		WovpChallenge.TYPE_SEASON:
			return Color(0.15, 0.30, 0.55) # steel blue
		WovpChallenge.TYPE_EXTRA:
			return Color(0.38, 0.22, 0.55) # violet
		WovpChallenge.TYPE_TOURNAMENT:
			return Color(0.55, 0.16, 0.13) # royale red
		WovpChallenge.TYPE_MONTHLY:
			return Color(0.08, 0.38, 0.33) # contract teal
	return Color(0.25, 0.25, 0.38)


static func manufacturer_color(manufacturer: String) -> Color:
	if manufacturer == "":
		return Color(0.28, 0.28, 0.36)
	return PALETTE[absi(manufacturer.hash()) % PALETTE.size()]


## The PuP note (GRADFIX6 item 5): the one line a PuP-flagged
## table carries on its back and in its detail view, word for
## word - a PuP pack's video windows assume the PC display
## sits at 100% scale, so the player is told before he
## launches, not after the pack opens wrong.
const PUP_NOTE: String = "PuP pack — set PC display scale to 100%"


static func panel_spec(game: GameEntry, store: StateStore) -> Dictionary:
	var chips: Array = []
	if game.is_vr_tagged():
		chips.append({"text": "VR", "accent": true})
	if game.is_pup_tagged():
		chips.append({"text": "PuP", "accent": true})
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


static func art_spec(game: GameEntry, art_texture: Texture2D, store: StateStore, strip: bool = true) -> Dictionary:
	return {
		"kind": "art",
		"art_texture": art_texture,
		"title": game.title,
		# The name strip inside the face: on for the detail
		# view's big art (it captions itself), off for the
		# dome room's cards, whose nameplate label rides on
		# the card itself (the graduation round).
		"strip": strip,
		# The favorite mark: the panel face shows a FAVORITE chip
		# (panel_spec, above); the art face carries the same fact
		# as a star badge (CardFace draws it). One store, one truth,
		# mirrored on both face kinds.
		"favorite": store != null and store.is_favorite(game.game_id),
		# The PuP mark (GRADFIX6 item 5): the art face carries
		# it as a badge in the corner opposite the favorite
		# star (CardFace draws it), from the same one truth -
		# the game's CURRENT build (GameEntry.is_pup_tagged).
		"pup": game.is_pup_tagged(),
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
	if game.is_pup_tagged():
		body += "\n" + PUP_NOTE
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
##
## TR3 dressing: score rows carry their parts (position /
## name / score) separately so the face can lay them out in
## columns - the name ellipsizes, the score never does (see
## CardFace). The full line still rides along as "text" for
## the legacy layout the NC seam restores. The deadline
## line warms as the end nears (amber inside 48 hours, hot
## inside 12, with the words to match), and the divider
## knows its tone: "up" for a promotion line, "down" for a
## cut line - the face draws it as a ruled line, not a
## sentence.
static func tournament_board_spec(ch: WovpChallenge, owned: bool, user_id: String, now_unix: int) -> Dictionary:
	var rows: Array = []
	for entry: Variant in ch.board_rows(user_id):
		var e: Dictionary = entry
		match str(e.get("kind", "")):
			"score":
				var r: WovpScoreRow = e.get("row") as WovpScoreRow
				if r == null:
					continue
				var score_text: String = WovpChallenge.format_score(r.score)
				var line: String = "#%d  %s  %s" % [r.position, r.participant_name, score_text]
				if r.is_pending:
					line += " - awaiting validation"
				rows.append({
					"kind": "score", "text": line,
					"pos_text": "#%d" % r.position,
					"name_text": r.participant_name,
					"score_text": score_text,
					"pending": r.is_pending,
					"accent": bool(e.get("mine", false)),
					"size": 42 if bool(e.get("mine", false)) else 40,
				})
			"divider":
				var tone: String = ""
				match ch.type_code:
					WovpChallenge.TYPE_SEASON, WovpChallenge.TYPE_EXTRA:
						tone = "up"
					WovpChallenge.TYPE_TOURNAMENT:
						tone = "down"
				rows.append({"kind": "divider", "text": str(e.get("label", "")), "size": 28, "tone": tone})
			"note":
				rows.append({"kind": "note", "text": str(e.get("text", "")), "size": 34})
	var chips: Array = []
	if not owned:
		chips.append({"text": "NOT IN YOUR LIBRARY", "accent": true})
	var title: String = ch.table_name if ch.table_name != "" else ch.name
	var remaining: int = ch.end_unix - now_unix
	var sub: String = "Ends %s - %s" % [WovpTime.format_deadline(ch.end_unix), WovpTime.format_remaining(ch.end_unix, now_unix)]
	var sub_color: Color = Color(0.75, 0.78, 0.88)
	if remaining <= 12 * 3600:
		sub += " - CLOSES SOON"
		sub_color = Color(1.0, 0.55, 0.40)
	elif remaining <= 48 * 3600:
		sub_color = Color(0.98, 0.80, 0.45)
	return {
		"kind": "board",
		"bg": CARD_BG,
		"band": challenge_type_color(ch.type_code),
		"band_text": "%s - %s" % [ch.type_label(), ch.name],
		"band_size": 28,
		"title": title,
		"title_size": 46,
		"title_max_lines": 1,
		"sub": sub,
		"sub_size": 26,
		"sub_max_lines": 1,
		"sub_color": sub_color,
		"chips": chips,
		"rows": rows,
		"footer_px": (0 if board_nc_old else BOARD_FOOTER_PX) if owned else 0,
		# GRADFIX4 (One Book): the standing board stands RIGHT
		# of its card, so its spine - the join with the art
		# page - is its LEFT edge.
		"spine_side": "left",
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


## The focused card's wing face (the graduation's Stage B):
## for a tournament table, the TR3 board itself (composed by
## tournament_board_spec - his row, the leader, the cut line,
## the clock) with the table's metadata appended beneath it
## as note rows; a table with no board gets the metadata
## alone under a TABLE DATA band. One render, one quad: the
## page is exactly the card's height (GRADFIX5), so there is
## no room for a second surface hanging beneath the board.
static func wing_spec(game: GameEntry, ch: WovpChallenge, user_id: String, now_unix: int) -> Dictionary:
	var meta: Array = []
	var maker_line: String = game.manufacturer
	if game.year > 0:
		maker_line = (maker_line + " - " if maker_line != "" else "") + str(game.year)
	if maker_line != "":
		meta.append({"kind": "note", "text": maker_line, "size": 30})
	var des: String = game.designer_text()
	if des != "":
		meta.append({"kind": "note", "text": "Design: " + des, "size": 30})
	var b: TableBuild = game.current_build()
	var ver_line: String = ""
	if b != null and b.version != "":
		ver_line = "Version " + b.version
	if game.build_count() > 1:
		ver_line += (" - " if ver_line != "" else "") + "%d builds" % game.build_count()
	if ver_line != "":
		meta.append({"kind": "note", "text": ver_line, "size": 30})
	if game.is_pup_tagged():
		meta.append({"kind": "note", "text": PUP_NOTE, "size": 30})
	if ch != null:
		var spec: Dictionary = tournament_board_spec(ch, true, user_id, now_unix)
		var rows: Array = (spec.get("rows", []) as Array).duplicate()
		for m: Variant in meta:
			rows.append(m)
		spec["rows"] = rows
		spec["footer_px"] = 0 ## the wing carries no Launch button: the board's footer band is metadata room instead
		# GRADFIX4 (One Book): the wing stands LEFT of its
		# card, so its spine - the join with the art page -
		# is its RIGHT edge (tournament_board_spec defaults
		# to the standing board's left).
		spec["spine_side"] = "right"
		return spec
	return {
		"kind": "board",
		"bg": CARD_BG,
		"band": manufacturer_color(game.manufacturer),
		"band_text": "TABLE DATA",
		"band_size": 28,
		"title": game.title,
		"title_size": 40,
		"title_max_lines": 1,
		"sub": "",
		"rows": meta,
		"footer_px": 0,
		"spine_side": "right",
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
