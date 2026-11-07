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
## (RoomView.WALL_RADIUS, 3.40 in the GRADFIX5 round, 3.60
## since the OPTIMIZE round): the book floats its proud
## 0.30 in front of the wall - 3.30 from the eye at 3.60 -
## where a 1.08 page spans 18.6 degrees against the bands'
## 20 degree pitch, INSIDE its slot, where the old 1.00 page
## at the old radius (2.75 from the eye) spanned 20.6. The
## census's flush leg measures the equality (page vs card
## extents, 1 mm tolerance); the pre-fix short page stands
## behind the harness's negative-control seam
## (PVLDS_GRADFIX5_NC=shortpage, read by Main before any
## room exists) so the leg can fail against it by name.
## GRADFIX8 (item 1): the board widens a little - 0.62 ->
## 0.72 m wide, height unchanged - so its lines breathe and
## the deadline line fits (with CardFace's scale-to-fit as
## the guarantee). The width is absorbed INSIDE the pair
## block's own span: boards stand in grid columns 4-9, one
## per column slot, and a column slot at WALL_RADIUS 3.60
## on the 13.5-degree pitch is 2*pi*3.60*13.5/360 = 0.848 m
## of arc wide. A 0.72 board's half (0.36) stays inside its
## slot's half (0.424) with 0.064 m to spare, so no board
## crosses its slot's edge - not the wall's edge at the
## block's ends, not its neighbour's slot - and the gap to
## the neighbouring card (half 0.31) along the arc is
## 0.848 - 0.36 - 0.31 = 0.178 m, against 0.131 at the old
## 3.40 radius. The
## face keeps the family's 1000 px per metre: 720 x 1080.
const BOARD_PANEL_SIZE: Vector2 = Vector2(0.72, 1.08)
const BOARD_FACE_PX: Vector2i = Vector2i(720, 1080)
## The library flip back's render size: the CARD's aspect
## (0.62 x 1.08 at 1000 px/m), NOT the standing board's -
## the back wears the card's own quad, so when GRADFIX8
## widened the standing board the back's size decoupled
## into this constant (RoomView._render_card_back reads
## it; the standing-board paths read board_face_px()).
const BACK_FACE_PX: Vector2i = Vector2i(620, 1080)
const SHORT_BOARD_PANEL_SIZE: Vector2 = Vector2(0.62, 1.00) ## the GRADFIX3/4 page (the shortpage NC's restore)
const SHORT_BOARD_FACE_PX: Vector2i = Vector2i(620, 1000)
const BOARD_FOOTER_PX: int = 140 ## the flip BACK's old bottom band: its own Launch button's home, through GRADFIX12. The standing board's plinth died in GRADFIX10 (item 1); GRADFIX13 (item 2) strips the back's too - the reservation now stands only behind negative controls: the deadplank NC restores it on standing boards, and PVLDS_GF13_NC=plinth restores it (with the button) on the back, so both strips' legs can fail by name.
const LEGACY_BOARD_PANEL_SIZE: Vector2 = Vector2(0.54, 0.64) ## == RoomView.PANEL_SIZE at the TR1/TR2 rounds
const LEGACY_BOARD_FACE_PX: Vector2i = Vector2i(512, 640)
const LEGACY_BOARD_LAUNCH_Y: float = -0.155 ## == RoomView.PANEL_LAUNCH_Y

static var board_nc_old: bool = false ## Main sets this from PVLDS_BOARD_NC before any room exists
static var board_short_page: bool = false ## Main sets this from PVLDS_GRADFIX5_NC=shortpage before any room exists
static var pairing_nc_old: bool = false ## Main sets this from PVLDS_GRADFIX8_NC=oldpair before any room exists: the board forgets the build half of the pairing (no DIFFERENT BUILD chip)
static var board_deadplank_nc: bool = false ## Main sets this from PVLDS_GRADFIX10_NC=deadplank before any room exists: the standing board reserves its dead Launch plinth again, so the frame-centring legs fail by name (GRADFIX10 item 1's negative control)


static func board_panel_size() -> Vector2:
	if board_nc_old:
		return LEGACY_BOARD_PANEL_SIZE
	return SHORT_BOARD_PANEL_SIZE if board_short_page else BOARD_PANEL_SIZE


static func board_face_px() -> Vector2i:
	if board_nc_old:
		return LEGACY_BOARD_FACE_PX
	return SHORT_BOARD_FACE_PX if board_short_page else BOARD_FACE_PX


## The flip back's Launch button centre height on its panel:
## the middle of the back face's footer band, in panel-local
## metres - the one place room.gd and the face layout both
## derive from, so the button can never drift back over the
## text. (Through TR3 this seated a standing board's Launch;
## since GRADFIX7 the standing board carries no button and
## since GRADFIX10 reserves no band; through GRADFIX12 the
## back was this derivation's live user - GRADFIX13 item 2
## strips the back's button too, and the derivation now
## serves only the plinth NC's restored button.)
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


## ---- The machined strip (GRADFIX14 item 1, Chris's pick
## from the strip mocks: "Machined Strip - nice and crisp",
## colour GRAPHITE). One continuous brushed-gunmetal bar
## carries the rail's sections; the mock's .graphite palette
## is the law, hex for hex:
##   bar gradient   #333740 -> #21242a (45%) -> #1a1c20 (55%) -> #282b31
##   border         #4c515a
##   resting labels #a8adb8
##   focused        gradient #4c525e -> #31353d, text white
## An ACCENT section (the standing filter / the Tournament
## Room) rests a step brighter than its neighbours and
## carries a light underline, so the active view still reads
## at a glance without leaving the graphite family.
const STRIP_GRAD_REST: Array[Color] = [Color8(51, 55, 64), Color8(33, 36, 42), Color8(26, 28, 32), Color8(40, 43, 49)]
const STRIP_GRAD_ACCENT: Array[Color] = [Color8(62, 67, 76), Color8(42, 45, 52), Color8(34, 37, 43), Color8(48, 51, 58)]
const STRIP_GRAD_LIFTED: Array[Color] = [Color8(76, 82, 94), Color8(62, 67, 77), Color8(49, 53, 61), Color8(49, 53, 61)]
const STRIP_BORDER: Color = Color8(76, 81, 90)
const STRIP_LABEL_REST: Color = Color8(168, 173, 184)
const STRIP_LABEL_ACCENT: Color = Color8(216, 221, 232)


## One section of the machined strip: its label on the bar's
## own graphite, an etched seam at its right edge (every
## section but the last), and - when lifted - the raised
## gradient with white text. seam_right is the caller's
## geography (the room knows the order); the face only draws.
static func strip_section_spec(text: String, accent: bool, lifted: bool, seam_right: bool) -> Dictionary:
	var grad: Array[Color] = STRIP_GRAD_REST
	if lifted:
		grad = STRIP_GRAD_LIFTED
	elif accent:
		grad = STRIP_GRAD_ACCENT
	var fg: Color = STRIP_LABEL_REST
	if lifted:
		fg = Color(1.0, 1.0, 1.0)
	elif accent:
		fg = STRIP_LABEL_ACCENT
	return {
		"kind": "strip_section",
		"bg": grad[2],
		"grad": grad,
		"title": text,
		"title_size": 55,
		"title_color": fg,
		"seam_right": seam_right,
		"accent_bar": accent and not lifted,
		"lifted": lifted,
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
		var unplaced: int = int(health.get("unplaced", 0))
		if unplaced > 0:
			lines.append("Files I couldn't place: %d table files match no database game. The list is unplaced_files.txt in the app data folder." % unplaced)
		else:
			lines.append("Files I couldn't place: none - every table file matched a database game.")
	# The WoVP line (the Tournament Room round): Main composes
	# it in _setup_panel_health from the config + the last
	# validation - whose key is saved here, in plain words.
	if health.has("wovp_line"):
		lines.append(str(health["wovp_line"]))
	# NEXTROUND (item 4): the PINemHi line rides beside the
	# WoVP line - Main composes it from the same read that
	# feeds the boards, so the panel and the boards agree.
	if health.has("pinemhi_line"):
		lines.append(str(health["pinemhi_line"]))
	# CARDBACK: the IPDB coverage line rides beside the
	# PINemHi line - Main composes it from the cache, so the
	# panel, the desk, and the backs all agree on the count.
	if health.has("ipdb_line"):
		lines.append(str(health["ipdb_line"]))
	# ROOMSUBMIT: the screenshots-folder line rides beside
	# the IPDB line - information parity with the desk (the
	# folder is SET on the desk; the room's submit panel
	# reads photos from it, and this line says from where).
	if health.has("shots_line"):
		lines.append(str(health["shots_line"]))
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


## ROOMSUBMIT: the submit panel's face - one challenge's
## case in plain lines, in the SETUP panel's banner family
## (the room's operations-panel grammar): the table's name
## as the title; the status line as the sub (the panel's
## message - sending, the verdict, a refusal's words; the
## standing instruction when nothing has happened yet);
## and the case as the body: which challenge this is, when
## it ends, where the table stands in his library (the
## desk's own three sentences), the higher-score warning
## with his posted number named (WovpChallenge.posted_note,
## verbatim - the desk's unresolved-identity sentence when
## the key's owner is not known yet), and the shots line
## (ShotsFolder.panel_line - the folder read's truth).
## The photos themselves stand BELOW this face as their
## own quads; the face never carries one.
static func submit_panel_spec(ch: WovpChallenge, owned: bool, build_owned: bool, user_id: String, now_unix: int, status: String, shots_line: String) -> Dictionary:
	var lines: Array[String] = []
	lines.append("%s - %s" % [ch.type_label(), ch.name])
	lines.append("Ends %s - %s" % [WovpTime.format_deadline(ch.end_unix), WovpTime.format_remaining(ch.end_unix, now_unix)])
	if not owned:
		lines.append("Not in your library.")
	elif build_owned:
		lines.append("In your library - the challenge's build.")
	else:
		lines.append("Different build in your library.")
	if user_id != "":
		lines.append(ch.posted_note(user_id))
	else:
		lines.append("Whose key this is isn't resolved yet - Test key names it, and the posted-score warning needs it.")
	if shots_line != "":
		lines.append(shots_line)
	return {
		"kind": "banner",
		"bg": Color(0.05, 0.05, 0.09),
		"title": ch.table_name if ch.table_name != "" else ch.name,
		"title_size": 64,
		"title_max_lines": 1,
		"sub": status if status != "" else "Pick the shot that shows your score, then SEND.",
		"sub_size": 36,
		"body": "\n".join(lines),
		"body_size": 32,
	}


## One Tournament Room board face: a challenge's standings
## on its table's wall panel, glanceable - the leader, his
## own row on the accent ground, the rows around the cutoff
## line and the line itself, and the deadline in his own
## clock with the time left. The row composition is the
## challenge's own mathematics (WovpChallenge.board_rows);
## this spec only dresses it. A table he does not own still
## gets its board - with the NOT IN YOUR LIBRARY chip, and
## the room gives it no Launch button. A table he owns in a
## DIFFERENT build than the challenge specifies gets its
## board too - with the DIFFERENT BUILD IN YOUR LIBRARY
## chip (GRADFIX8 item 3): NOT IN YOUR LIBRARY is reserved
## for not owning the game at all, and the board says which
## of the two is true.
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
## NEXTROUND (item 4): the PINemHi negative-control seam,
## set by Main from PVLDS_PINEMHI_NC. "nobest" = the board
## spec drops the personal-best line even when a best was
## handed in - the tournament smoke's PINemHi legs fail
## against it by name. Same static-seam shape as
## board_deadplank_nc above.
static var pinemhi_nc: String = ""
static var cardback_nc: String = "" ## Main sets this from PVLDS_CARDBACK_NC before any room exists (nodots: the Spec Sheet grid's rows lose their source dots - the wells stand unlabelled - so the cardback legs fail by name)
static var backtrim_nc: String = "" ## Main sets this from PVLDS_BACKTRIM_NC before any room exists (PINEMHI1: nostamp = the room's PINemHi rows push never bumps its stamp, so a standing back never heals - the rewritten backtrim legs fail by name; the CARDBACK-era notrim value has no surface left and is ignored)
static var pinemhi1_nc: String = "" ## Main sets this from PVLDS_PINEMHI1_NC before any room exists (PINEMHI1 seams: oldgrid = the card back renders the retired Spec Sheet wing again, so the back legs fail by name; pulse = the loading marquee's font pulse returns, so the pulse leg fails by name)
static var backfine_nc: String = "" ## Main sets this from PVLDS_BACKFINE_NC before any room exists (BACKFINE seams: dateback = the card back's personal rows carry the date again, so the no-date legs fail by name; ghostbest = the room seats a Best section for a game whose install holds no Best file, so the no-file-no-section legs fail by name)

static func tournament_board_spec(ch: WovpChallenge, owned: bool, user_id: String, now_unix: int, build_owned: bool = true, personal_best: Dictionary = {}, submit_hint: bool = false) -> Dictionary:
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
	# ROOMSUBMIT: the submit hint - the standing board
	# itself names the command that opens the submit panel
	# (Y on the challenge's card), because the room has no
	# controls surface to list it on and a command that
	# exists must read where the player can see it. Only
	# the room's standing-board render passes submit_hint;
	# the library flip-back's board (wing_spec) and the
	# spec legs keep the default. The hint stands BELOW the
	# league rows and ABOVE the PINemHi best: the pinemhi
	# legs pin the best as the board's LAST row.
	if submit_hint:
		rows.append({"kind": "note", "text": "Y - SUBMIT A SCORE", "size": 30})
	# NEXTROUND (item 4): the PINemHi personal-best line -
	# appended BELOW the league rows as a plain note, never
	# a score row: it is the player's own best from their
	# local PINemHi files (core/pinemhi_scores.gd), not a
	# league score, and it must never read as one.
	if not personal_best.is_empty() and pinemhi_nc != "nobest":
		rows.append({
			"kind": "note",
			"text": "Your PINemHi best: %s" % str(personal_best.get("score_text", "")),
			"size": 30,
		})
	var chips: Array = []
	if not owned:
		chips.append({"text": "NOT IN YOUR LIBRARY", "accent": true})
	elif not build_owned and not pairing_nc_old:
		chips.append({"text": "DIFFERENT BUILD IN YOUR LIBRARY", "accent": true})
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
		# GRADFIX10 (item 1): a standing board reserves NO
		# footer. The 140 px plinth was the Launch button's
		# home through TR3, but since GRADFIX7 the standing
		# board carries no button (it stands open beside its
		# card; the Launch lives on the card, and on the card's
		# flip back - whose spec re-adds the band explicitly,
		# RoomView._card_back_spec). The reservation outlived
		# its button: CardFace centred the content in the area
		# ABOVE the plinth, so against the standing FRAME the
		# block rode 66 px high with a dead dark plank at the
		# bottom edge (Chris's GRADFIX8 field correction:
		# "tournie text still not centered on frame"). With no
		# reservation the centring spacers centre the block on
		# the full canvas. The deadplank NC restores the old
		# reservation (owned boards only, as it was).
		"footer_px": (BOARD_FOOTER_PX if board_deadplank_nc else 0) if owned else 0,
		# GRADFIX10 (item 1): the standing board's composition
		# is ink-centred on its frame by the factory's
		# measure-and-correct pass (TextureFactory) - the
		# spacers centre the content's bounding box, but the
		# block's ink mass sits off that centre (solid panels
		# below, sparse title/deadline text above), and the
		# field judges the mass. Only a standing-board render
		# at the board's own face size corrects; the wing
		# clears this key (its composition is the back's).
		"ink_centre": true,
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
## The Spec Sheet grid (CARDBACK round, Chris's pick -
## mock variant B): ONE dense fact grid for the card back,
## the db well's rows and the IPDB well's rows interleaved
## in reading order, every row carrying its well in "src"
## ("db" / "ipdb") - CardFace draws the source dot from it.
## A fact a well doesn't hold produces NO row: the grid
## never carries an empty line. The wells are never merged:
## the db's Designer row and IPDB's Design row are two
## rows, and when they disagree (Indiana Jones: the db
## credits Mark Ritchie alone, IPDB adds Doug Watson) BOTH
## stand, each with its own dot. Only an IPDB design string
## character-identical to the db's is skipped - the fact is
## already on the back, dotted, and a duplicate row is
## noise, not provenance. Under the nodots NC the rows are
## built without "src" at all (the wells stand unlabelled),
## so the cardback legs fail by name.
static func spec_grid_rows(game: GameEntry, ipdb: Dictionary) -> Array:
	var rows: Array = []
	# db well: the machine facts the db itself carries.
	_add_kv(rows, "Type", game.type_text(), "db")
	# IPDB's body line (Specialty: Widebody...) interleaves
	# directly under the db's Type.
	_add_kv(rows, "Body", str(ipdb.get("specialty", "")), "ipdb")
	if game.players > 0:
		_add_kv(rows, "Players", str(game.players), "db")
	_add_kv(rows, "MPU", game.mpu, "db")
	_add_kv(rows, "Theme", game.theme_text(), "db")
	var db_designer: String = ", ".join(game.designers)
	_add_kv(rows, "Designer", db_designer, "db")
	# IPDB credits: each role its own row, its own dot.
	var ipdb_design: String = str(ipdb.get("design", ""))
	if ipdb_design != db_designer:
		_add_kv(rows, "Design", ipdb_design, "ipdb")
	_add_kv(rows, "Art", str(ipdb.get("art", "")), "ipdb")
	_add_kv(rows, "Music", str(ipdb.get("music", "")), "ipdb")
	_add_kv(rows, "Software", str(ipdb.get("software", "")), "ipdb")
	# IPDB production facts.
	_add_kv(rows, "Units produced", str(ipdb.get("units", "")), "ipdb")
	# BACKTRIM (Chris's design call, literal): the grid
	# ENDS at Units produced. The Fun rating, Features and
	# IPDB entry rows are cut from the RENDER only - the
	# facts stay parsed and cached (the parser, the cache
	# and the bundled snapshot are untouched). The field
	# back carried so much text the sheet crowded itself;
	# everything after Units produced was the bulk.
	if backtrim_nc == "notrim":
		var fun: String = str(ipdb.get("fun_rating", ""))
		_add_kv(rows, "Fun rating", (fun + " / 10") if fun != "" else "", "ipdb")
		var feats: String = str(ipdb.get("features", ""))
		if feats.length() > 240:
			feats = feats.substr(0, 240).strip_edges() + "…"
		_add_kv(rows, "Features", feats, "ipdb")
		if not ipdb.is_empty() and game.ipdb_id > 0:
			_add_kv(rows, "IPDB entry", "#" + str(game.ipdb_id), "ipdb")
	return rows


static func _add_kv(rows: Array, k: String, v: String, src: String) -> void:
	if v == "":
		return
	var row: Dictionary = {"kind": "kv", "k": k, "v": v, "size": 30}
	if cardback_nc != "nodots":
		row["src"] = src
	rows.append(row)


## The back's local rows (no dot - neither well owns them):
## the version/builds line, the PuP note, and the mock's
## footer: what the player owns of this game and which
## build stands current.
static func back_local_rows(game: GameEntry) -> Array:
	var rows: Array = []
	var b: TableBuild = game.current_build()
	var ver_line: String = ""
	if b != null and b.version != "":
		ver_line = "Version " + b.version
	if game.build_count() > 1:
		ver_line += (" - " if ver_line != "" else "") + "%d builds" % game.build_count()
	if ver_line != "":
		rows.append({"kind": "note", "text": ver_line, "size": 30})
	if game.is_pup_tagged():
		rows.append({"kind": "note", "text": PUP_NOTE, "size": 30})
	if game.build_count() > 0:
		var vr_n: int = 0
		for bb: TableBuild in game.builds:
			if bb.has_vr_tag():
				vr_n += 1
		var own: String = "Your builds: %d in the library" % game.build_count()
		if vr_n > 0:
			own += " · %d with VR" % vr_n
		rows.append({"kind": "note", "text": own, "size": 30})
		if b != null:
			var cur: String = "Current: "
			var auth: String = b.authors_text()
			if auth != "":
				cur += auth + " "
			cur += "v" + b.display_version()
			rows.append({"kind": "note", "text": cur, "size": 30})
	return rows


static func wing_spec(game: GameEntry, ch: WovpChallenge, user_id: String, now_unix: int, ipdb: Dictionary = {}) -> Dictionary:
	# CARDBACK (item 3, second leg): the wing's metadata
	# block is the Spec Sheet grid now (spec_grid_rows) over
	# the back's local rows. A game with NO db facts at all
	# (a filename-only local game, no IPDB cache) keeps the
	# pre-CARDBACK meta block verbatim - maker, design,
	# version - so its back degrades to exactly what it
	# always showed instead of an empty sheet.
	var grid: Array = spec_grid_rows(game, ipdb)
	var local: Array = back_local_rows(game)
	if grid.is_empty():
		var meta: Array = []
		var maker_line: String = game.manufacturer
		if game.year > 0:
			maker_line = (maker_line + " - " if maker_line != "" else "") + str(game.year)
		if maker_line != "":
			meta.append({"kind": "note", "text": maker_line, "size": 30})
		var des: String = game.designer_text()
		if des != "":
			meta.append({"kind": "note", "text": "Design: " + des, "size": 30})
		for m2: Variant in local:
			meta.append(m2)
		local = meta
	if ch != null:
		var spec: Dictionary = tournament_board_spec(ch, true, user_id, now_unix)
		var rows: Array = (spec.get("rows", []) as Array).duplicate()
		for m: Variant in grid:
			rows.append(m)
		for m3: Variant in local:
			rows.append(m3)
		spec["rows"] = rows
		spec["footer_px"] = 0 ## the wing carries no Launch button: the board's footer band is metadata room instead
		spec["ink_centre"] = false ## the wing/back composition is not the standing board's: GRADFIX10's ink correction never touches it (the back centres as GRADFIX8 left it)
		# GRADFIX4 (One Book): the wing stands LEFT of its
		# card, so its spine - the join with the art page -
		# is its RIGHT edge (tournament_board_spec defaults
		# to the standing board's left).
		spec["spine_side"] = "right"
		return spec
	var sub: String = ""
	if game.manufacturer != "":
		sub = game.manufacturer.to_upper()
	if game.year > 0:
		sub = (sub + " · " if sub != "" else "") + str(game.year)
	return {
		"kind": "board",
		"bg": CARD_BG,
		"band": manufacturer_color(game.manufacturer),
		"band_text": "SPEC SHEET" if not grid.is_empty() else "TABLE DATA",
		"band_size": 28,
		"title": game.title,
		"title_size": 40,
		"title_max_lines": 1,
		"sub": sub,
		"sub_size": 26,
		"rows": grid + local,
		"footer_px": 0,
		"spine_side": "right",
	}


## PINEMHI1: the card back's new tenant (Chris, 2026-11-07:
## "we nuke table info and include pinemhi"). The back is
## the game's PINemHi Personal scores: the title line, then
## the file's rows AS THEY STAND - as many as the file
## holds, never padded - in the boards' own score-row shape
## (rank / player / board-formatted score). BACKFINE
## (Chris, from his PINEMHI1 field session): the date
## column is NUKED - it clipped mid-year on the standing
## back and ate a third of every row; the name is the
## player alone now, and the freed width is breathing
## room. (Under the dateback NC the date rides again, so
## the no-date legs fail by name.) A game with no Personal
## file (or no rows) gets one honest note line instead -
## no fact grid, no invented rows.
##
## BACKFINE (second ruling): the local TOP10_Best file
## joins the back - "we only need the #1 player high
## score... including the Top 10 scores under or above
## would be a nice touch." The Best section stands BELOW
## the personal rows under an ONLINE BEST divider: the
## world #1 as its own distinct score row (the "world1"
## flag - the face draws it on its own steel-blue ground),
## then the file's remaining rows in order, at most 10
## rows all told. READABILITY LAW: Best type never goes
## smaller than the personal rows' type (38 - one size for
## every score row on the back), and the full Best list
## stands only when personal + divider + full Best + the
## PuP note FIT the back's height budget at that size;
## otherwise the Best section reduces to the #1 line
## alone. The #1 line and the personal rows are never
## dropped. The budget is the renderer's own arithmetic
## (measured at BACK_FACE_PX on the real face, BACKFINE
## probe: the content block - band, title, sub, rows -
## stands 166 px over its row stack, a 38 px score row
## stands 57 px, a divider 43 px, rows separate by 6 px;
## a note stands its wrapped height in the fallback
## font). The block must fit the face inside its margins:
## 1080 - 14 top - 22 bottom = 1044 px. Personal empty +
## Best present: the honest empty line stands above the
## Best section. Neither: the empty line alone. The PuP
## note survives as the last line in EVERY state. Under
## the oldgrid NC the room routes to wing_spec instead
## (the retired Spec Sheet), so this spec is never built.
const BACK_CONTENT_BUDGET_PX: float = 1044.0 ## BACK_FACE_PX.y minus the board face's top (14) and bottom (22) margins
const BACK_BLOCK_OVERHEAD_PX: float = 166.0 ## band + title + sub + their separations, measured on the real face (the sub line's 42 px leave when a game has no sub)
const BACK_ROW_SEP_PX: float = 6.0 ## the rows stack's separation (CardFace board law)

static func pinemhi_back_spec(game: GameEntry, record: Dictionary, best_record: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	var file_rows: Array = record.get("rows", []) as Array
	if file_rows.is_empty():
		rows.append({"kind": "note", "text": "No PINemHi scores on file for this table yet.", "size": 32})
	else:
		for rv: Variant in file_rows:
			var r: Dictionary = rv as Dictionary
			rows.append(_pinemhi_score_row(r, false, true))
	var sub: String = ""
	if game.manufacturer != "":
		sub = game.manufacturer.to_upper()
	if game.year > 0:
		sub = (sub + " · " if sub != "" else "") + str(game.year)
	# The Best section, composed whole first; the
	# readability law then decides whether its full list
	# stands or it reduces to the #1 line alone.
	var best_rows: Array = best_record.get("rows", []) as Array
	if not best_rows.is_empty():
		var pup_row: Dictionary = {"kind": "note", "text": PUP_NOTE, "size": 30} if game.is_pup_tagged() else {}
		var section: Array = [{"kind": "divider", "text": "ONLINE BEST", "size": 28, "tone": ""}]
		section.append(_pinemhi_score_row(best_rows[0] as Dictionary, true, false))
		var full: Array = rows + section
		for i: int in range(1, mini(best_rows.size(), 10)):
			full.append(_pinemhi_score_row(best_rows[i] as Dictionary, false, false))
		if not pup_row.is_empty():
			full.append(pup_row)
		if _back_content_height(full, sub != "") <= BACK_CONTENT_BUDGET_PX:
			rows = full
		else:
			rows = rows + section
			if not pup_row.is_empty():
				rows.append(pup_row)
	elif game.is_pup_tagged():
		rows.append({"kind": "note", "text": PUP_NOTE, "size": 30})
	return {
		"kind": "board",
		"bg": CARD_BG,
		"band": manufacturer_color(game.manufacturer),
		"band_text": "PINEMHI",
		"band_size": 28,
		"title": game.title,
		"title_size": 40,
		"title_max_lines": 1,
		"sub": sub,
		"sub_size": 26,
		"rows": rows,
		"footer_px": 0,
		"spine_side": "right",
	}


## One PINemHi file row as a back score row (the boards'
## shape: rank / player / board-formatted score, one size
## for every score row on the back). world1 marks the
## online #1: the face draws that row on its own ground.
static func _pinemhi_score_row(r: Dictionary, world1: bool, personal: bool) -> Dictionary:
	var score: int = int(r.get("score", 0))
	var name_text: String = str(r.get("player", ""))
	if backfine_nc == "dateback" and personal:
		# BACKFINE NC seam: the retired date column
		# returns to the PERSONAL rows (the PINEMHI1
		# shape), so the no-date legs fail by name. The
		# Best rows never carried a date on the back.
		var when: String = str(r.get("when", ""))
		if when != "":
			name_text += " · " + when.split(" ")[0]
	return {
		"kind": "score",
		"text": "#%d  %s  %s" % [int(r.get("rank", 0)), name_text, WovpChallenge.format_score(float(score))],
		"pos_text": "#%d" % int(r.get("rank", 0)),
		"name_text": name_text,
		"score_text": WovpChallenge.format_score(float(score)),
		"score": score,
		"pending": false,
		"accent": false,
		"world1": world1,
		"size": 38,
	}


## The back's content-block height for a candidate row
## stack, in the renderer's own arithmetic (see the
## readability law's note on pinemhi_back_spec): the
## measured block overhead plus each row's standing
## height and the stack's separations.
static func _back_content_height(rows: Array, has_sub: bool) -> float:
	var total: float = BACK_BLOCK_OVERHEAD_PX - (0.0 if has_sub else 42.0)
	for i: int in range(rows.size()):
		if i > 0:
			total += BACK_ROW_SEP_PX
		total += _back_row_height(rows[i] as Dictionary)
	return total


## One row's standing height on the board face: a score
## row is its font height plus the row box's squeezed
## vertical margins (2 + 2, CardFace's board law); a
## divider the same (its ruled border stands inside the
## panel); a note its wrapped height at the face's inner
## width, measured with the face's own font (the fallback
## font CardFace measures with).
static func _back_row_height(row: Dictionary) -> float:
	var size: int = int(row.get("size", 38))
	var font: Font = ThemeDB.fallback_font
	match str(row.get("kind", "")):
		"score", "divider":
			return font.get_height(size) + 4.0
		"note":
			var wrapped: Vector2 = font.get_multiline_string_size(
				str(row.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER,
				float(BACK_FACE_PX.x - 52), size)
			# +4: a standing label renders a few px over
			# the raw multiline measure (the empty-state
			# note measures 90, renders 93 - BACKFINE
			# probe), and the law must never call a fit
			# the face cannot hold.
			return wrapped.y + 4.0
	return font.get_height(size) + 4.0


## PINEMHI1 (Milestone 2): the loading marquee's fact
## lines - the salvage of the nuked Spec Sheet (Chris:
## "expand whats mentioned on the table loading screen").
## The pick of the old grid, one value per label: the
## IPDB value when the bundled snapshot / cache holds
## one, else the db value (the db carries a Designer
## only; the other four live in the IPDB well alone).
## Empty labels are skipped entirely and the list caps
## at five - the marquee drops a line rather than
## shrink its type.
static func marquee_fact_lines(game: GameEntry, ipdb: Dictionary) -> Array:
	var db_designer: String = ", ".join(game.designers)
	var picks: Array = [
		["Designer", str(ipdb.get("design", "")), db_designer],
		["Art", str(ipdb.get("art", "")), ""],
		["Music", str(ipdb.get("music", "")), ""],
		["Software", str(ipdb.get("software", "")), ""],
		["Units produced", str(ipdb.get("units", "")), ""],
	]
	var lines: Array = []
	for pv: Variant in picks:
		var p: Array = pv as Array
		var v: String = str(p[1]) if str(p[1]) != "" else str(p[2])
		if v == "":
			continue
		lines.append(str(p[0]) + ": " + v)
		if lines.size() >= 5:
			break
	return lines


static func banner_spec(line: String) -> Dictionary:
	return {
		"kind": "banner",
		"bg": Color(0.04, 0.04, 0.07),
		"title": "PVLDS",
		"title_size": 92,
		"sub": line,
		"sub_size": 34,
	}
