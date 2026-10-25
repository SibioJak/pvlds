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


static func banner_spec(line: String) -> Dictionary:
	return {
		"kind": "banner",
		"bg": Color(0.04, 0.04, 0.07),
		"title": "PVLDS",
		"title_size": 92,
		"sub": line,
		"sub_size": 34,
	}
