class_name CardFace
extends Control

## The 2D face rendered into the shared SubViewport and captured as a
## texture for the room's quads. One face, several layouts ("kind"):
##   panel  - a table's wall card: band, big name, maker/year, chips
##   art    - full-bleed art texture with a name strip at the bottom
##   row    - one build row in the detail view
##   button - a single centered label
##   info   - title plus stacked fact lines
##   banner - app title plus a summary line
##   board  - a Tournament Room scoreboard: band, table name,
##            deadline line, then stacked board rows - score
##            rows (his carries the accent ground), a divider
##            row where the cutoff line falls, and note rows.
##            GRADFIX15: the board face is FRAMELESS - the
##            text block stands on transparency with no panel
##            fill behind it (the One Book dressing below is
##            the retired shape, kept as the record).
##            GRADFIX4 (One Book): the face is a page of the
##            focused card's own book - the paper sits inside
##            a cover border of the card frame's stock, a
##            gradient darkening toward a spine ridge on the
##            page's SPINE edge (spec "spine_side": the edge
##            that joins the art page), and EVERY line is
##            centred: band, title, deadline, and each score
##            row as a centred block (position / name / score
##            at natural widths, the name ellipsizing in the
##            space the other two leave). A score never
##            clips: a row whose block outgrows the page
##            scales its font down until the number fits
##            whole. A board face whose spec reserves a footer
##            band (spec "footer_px") keeps its text out of
##            that band: the library flip back's plinth, which
##            its own Launch button rides. A standing board
##            reserves none since GRADFIX10 (item 1) - it has
##            carried no Launch since GRADFIX7, and the dead
##            band left its content riding high on the frame.
## Specs are plain dictionaries built by callers; reads are defensive.
## A spec may cap a text slot's lines ("title_max_lines" and friends);
## a capped label ellipsizes its overrun instead of wrapping without
## limit and pushing the rest of the card off its texture.

const FACE_MARGIN_TOP_PX: int = 22 ## the shared face layout's top margin
const FACE_MARGIN_BOTTOM_PX: int = 22 ## the shared face layout's bottom margin (a board's footer band takes the bottom over - see apply_spec)

## Title-card raise (Chris's field note, 2026-10-23): art faces are
## full-bleed - their content starts at the texture's top row -
## while a title card's content block started FACE_MARGIN_TOP_PX
## lower, so on the wall a title card's design registered that far
## below its art neighbours' (measured on the 512x640 wall faces:
## art content top row 0, title-card content top row 22). The panel
## kind's top margin shrinks by this many pixels so the band's top
## edge registers with the art faces' top edge. One constant: a
## future nudge is a one-line change here.
const PANEL_CONTENT_RAISE_PX: int = 22

## The art face's name strip: a fixed-height band across the
## texture's bottom edge. Named because the room's nameplate
## seating derives from it - the plate must back this strip,
## never cover the name it carries. (Through GRADFIX12 the
## Launch button's placement derived from it too; the plinth
## is stripped, GRADFIX13 item 2.)
const ART_STRIP_HEIGHT_PX: int = 92

## The art face's favorite mark: a star badge in the face's top
## right corner (the panel face carries the same fact as a
## FAVORITE chip). Marquee amber so the mark reads as one family
## with the chips; the top corner keeps it clear of the name
## strip (bottom edge) at wall distance.
const FAVORITE_STAR_COLOR: Color = Color(1.0, 0.78, 0.25)

## The art face's PuP mark (GRADFIX6 item 5): a badge in the
## face's top LEFT corner - the favorite star owns the top
## right - worn when the game's current build ships a PuP
## pack (RoomSpecs.art_spec's "pup" key). A cool video-blue,
## so the two corner marks never read as one family: amber
## is the player's own flag, blue is the table's cargo.
const PUP_BADGE_COLOR: Color = Color(0.45, 0.85, 1.0)

## Board score rows: TR3's fixed right-aligned score
## column is superseded by the Standing Book (GRADFIX3) -
## a row is a centred block (position / name / score at
## natural widths) and a row whose block would squeeze
## the name under its floor scales down whole instead of
## ever clipping a digit. The old cap constant stays only
## as the record of the TR3 law.
const BOARD_SCORE_COL_MAX_PX: float = 330.0

var _bg: ColorRect
## GRADFIX15 (items 1+2): the One Book's cover rect, page
## gradient and spine furniture are DELETED - a board face
## no longer renders any filled panel behind its text, and
## the thin vertical grey line at the text block's edge is
## gone at its source (Chris, 2026-11-02: "lets nuke the
## grey line and background color"). The board's text block
## stands on transparency; see apply_spec's frameless law.
## The line's convicted identity, for the record: it was
## _spine_line, the GRADFIX4 spine ridge's highlight
## hairline - Color(0.48, 0.55, 0.70, 0.85), 3 px wide, set
## at x = size.x - 44 for a "right" spine (x = 41 for
## "left"), running the face's height inside the cover
## border, with _spine_shade's dark fall (31 px, alpha 0.6)
## between it and the edge. Pixel proof on the pre-fix WPT
## render: x 676-678 reads (105, 121, 156) - the hairline
## blended over the page gradient's dark end, to the digit -
## and the line survives the panel fill's death (item 1's
## bisect render), so it was never a panel-edge artefact.
var _strip_grad_rect: TextureRect ## strip_section kind (GRADFIX14 item 1): the section's graphite gradient, drawn over the ground and under the type
var _strip_grad_tex: GradientTexture2D ## strip_section kind: the gradient's texture (its Gradient is rebuilt per spec)
var _strip_seam_dark: ColorRect ## strip_section kind: the etched seam's dark line at the section's right edge
var _strip_seam_light: ColorRect ## strip_section kind: the etched seam's hairline highlight, just inside the dark line
var _strip_top_edge: ColorRect ## strip_section kind: the bar's border line along the top edge (continuous across sections by construction)
var _strip_top_hi: ColorRect ## strip_section kind: the machined highlight just under the top edge (brighter on a lifted section)
var _strip_bot_edge: ColorRect ## strip_section kind: the bar's dark bottom edge (a lifted section's cast shade pools here)
var _strip_accent_bar: ColorRect ## strip_section kind: the standing view's light underline (accent sections at rest)
var _margin: MarginContainer
var _vbox: VBoxContainer
var _band_panel: PanelContainer
var _band_label: Label
var _title_label: Label
var _sub_label: Label
var _body_label: Label
var _chips_row: HBoxContainer
var _rows_box: VBoxContainer ## the board kind's stacked rows (score / divider / note)
var _top_spacer: Control ## board kind (GRADFIX8): the centring spacer above the band - shares the face's spare height with _footer_spacer so the content block centres (see apply_spec)
var _footer_spacer: Control ## board kind: pushes the footer band to the face's bottom edge
var _footer_panel: PanelContainer ## board kind: the footer plinth (spec "footer_px") - the flip back's Launch seat; standing boards reserve none since GRADFIX10
var _art_rect: TextureRect
var _art_strip: PanelContainer
var _art_label: Label
var _art_fav: PanelContainer
var _art_fav_label: Label
var _art_pup: PanelContainer ## art kind (GRADFIX6): the PuP badge, top-left (the star's opposite corner)
var _art_pup_label: Label
var _art_score: PanelContainer ## art kind (SCOREMARK, glyph MARKWORD): the PINemHi wordmark badge, bottom-left (the free corner: star top-right, PuP top-left, the nameplate's plate rides the lower-middle band). A badge in the PuP badge's discipline - ground in the game's OWN back-band colour (RoomSpecs.manufacturer_color - the colour the flipped back's PINEMHI band wears), white text reading "PINemHi" in the service's own capitalization (MARKWORD: the retired "#1" medallion misread as a ranking; the word cannot). Stands only when the game holds the player's own PINemHi Personal rows.
var _art_score_label: Label
var _label_stock: Array = [] ## [label, autowrap, max_lines, overrun] per text label, for per-spec restore


func _init() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.05, 0.09)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# The machined strip's section furniture (GRADFIX14 item
	# 1): gradient, etched seam, edge lines - asserted per
	# spec, standing only for strip_section faces.
	_strip_grad_tex = GradientTexture2D.new()
	_strip_grad_tex.fill_from = Vector2(0.5, 0.0)
	_strip_grad_tex.fill_to = Vector2(0.5, 1.0)
	_strip_grad_tex.width = 4
	_strip_grad_tex.height = 256
	_strip_grad_rect = TextureRect.new()
	_strip_grad_rect.texture = _strip_grad_tex
	_strip_grad_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip_grad_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_strip_grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_strip_grad_rect.visible = false
	add_child(_strip_grad_rect)
	_strip_seam_dark = ColorRect.new()
	_strip_seam_dark.color = Color(0.0, 0.0, 0.0, 0.55)
	_strip_seam_dark.visible = false
	add_child(_strip_seam_dark)
	_strip_seam_light = ColorRect.new()
	_strip_seam_light.color = Color(1.0, 1.0, 1.0, 0.08)
	_strip_seam_light.visible = false
	add_child(_strip_seam_light)
	_strip_top_edge = ColorRect.new()
	_strip_top_edge.color = Color8(76, 81, 90)
	_strip_top_edge.visible = false
	add_child(_strip_top_edge)
	_strip_top_hi = ColorRect.new()
	_strip_top_hi.color = Color(1.0, 1.0, 1.0, 0.10)
	_strip_top_hi.visible = false
	add_child(_strip_top_hi)
	_strip_bot_edge = ColorRect.new()
	_strip_bot_edge.color = Color(0.0, 0.0, 0.0, 0.6)
	_strip_bot_edge.visible = false
	add_child(_strip_bot_edge)
	_strip_accent_bar = ColorRect.new()
	_strip_accent_bar.color = Color(0.85, 0.87, 0.92, 0.9)
	_strip_accent_bar.visible = false
	add_child(_strip_accent_bar)

	_art_rect = TextureRect.new()
	_art_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art_rect.visible = false
	add_child(_art_rect)
	_art_strip = PanelContainer.new()
	_art_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_art_strip.offset_top = -float(ART_STRIP_HEIGHT_PX)
	_art_strip.add_theme_stylebox_override("panel", _box(Color(0.02, 0.02, 0.04, 0.88), 0))
	_art_label = Label.new()
	_art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The strip is one fixed-height line: a long name clips with an
	# ellipsis there instead of spilling over the art it captions.
	_art_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_art_label.add_theme_font_size_override("font_size", 44)
	_art_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	_art_strip.add_child(_art_label)
	_art_strip.visible = false
	add_child(_art_strip)

	_art_fav = PanelContainer.new()
	_art_fav.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_art_fav.offset_left = -76.0
	_art_fav.offset_top = 14.0
	_art_fav.offset_right = -14.0
	_art_fav.offset_bottom = 76.0
	_art_fav.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.05, 0.82), 10))
	_art_fav_label = Label.new()
	_art_fav_label.text = "★"
	_art_fav_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_art_fav_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_art_fav_label.add_theme_font_size_override("font_size", 44)
	_art_fav_label.add_theme_color_override("font_color", FAVORITE_STAR_COLOR)
	_art_fav.add_child(_art_fav_label)
	_art_fav.visible = false
	add_child(_art_fav)

	_art_pup = PanelContainer.new()
	_art_pup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_art_pup.offset_left = 14.0
	_art_pup.offset_top = 14.0
	_art_pup.offset_right = 98.0
	_art_pup.offset_bottom = 62.0
	_art_pup.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.05, 0.82), 10))
	_art_pup_label = Label.new()
	_art_pup_label.text = "PuP"
	_art_pup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_art_pup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_art_pup_label.add_theme_font_size_override("font_size", 30)
	_art_pup_label.add_theme_color_override("font_color", PUP_BADGE_COLOR)
	_art_pup.add_child(_art_pup_label)
	_art_pup.visible = false
	add_child(_art_pup)

	_art_score = PanelContainer.new()
	_art_score.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_art_score.offset_left = 14.0
	_art_score.offset_top = -62.0
	_art_score.offset_right = 170.0
	_art_score.offset_bottom = -14.0
	_art_score.add_theme_stylebox_override("panel", _score_box(Color(0.30, 0.34, 0.60)))
	_art_score_label = Label.new()
	_art_score_label.text = "PINemHi"
	_art_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_art_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_art_score_label.add_theme_font_size_override("font_size", 30)
	_art_score_label.add_theme_color_override("font_color", Color(0.98, 0.98, 1.0))
	_art_score.add_child(_art_score_label)
	_art_score.visible = false
	add_child(_art_score)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 26)
	_margin.add_theme_constant_override("margin_right", 26)
	_margin.add_theme_constant_override("margin_top", FACE_MARGIN_TOP_PX)
	_margin.add_theme_constant_override("margin_bottom", FACE_MARGIN_BOTTOM_PX)
	add_child(_margin)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 12)
	_margin.add_child(_vbox)

	_top_spacer = Control.new()
	_top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_top_spacer.visible = false
	_vbox.add_child(_top_spacer)

	_band_panel = PanelContainer.new()
	_band_label = Label.new()
	_band_label.add_theme_font_size_override("font_size", 30)
	_band_label.add_theme_color_override("font_color", Color(0.98, 0.98, 1.0))
	_band_panel.add_child(_band_label)
	_vbox.add_child(_band_panel)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	_vbox.add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	_vbox.add_child(_sub_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_color_override("font_color", Color(0.85, 0.86, 0.92))
	_vbox.add_child(_body_label)

	_chips_row = HBoxContainer.new()
	_chips_row.add_theme_constant_override("separation", 10)
	_vbox.add_child(_chips_row)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	_rows_box.visible = false
	_vbox.add_child(_rows_box)

	_footer_spacer = Control.new()
	_footer_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_footer_spacer.visible = false
	_vbox.add_child(_footer_spacer)
	_footer_panel = PanelContainer.new()
	_footer_panel.add_theme_stylebox_override("panel", _footer_box())
	_footer_panel.visible = false
	_vbox.add_child(_footer_panel)

	# One CardFace serves every render the TextureFactory makes, so
	# per-spec line discipline (apply_spec) must be undone before the
	# next spec: snapshot the stock label settings now.
	_snapshot_label(_title_label)
	_snapshot_label(_sub_label)
	_snapshot_label(_body_label)


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## The SCOREMARK badge's style (MARKWORD): the PuP
## badge's box - corner radius 10, the stock content
## margins - in the game's back-band colour, the white
## wordmark centred on it. Rebuilt per spec in
## apply_spec, like the band's box: one CardFace serves
## every render. The word at 30 px measures 128 px, so
## the 156 px seat (14 px insets, like the PuP badge)
## holds it with the PuP badge's own breathing room.
func _score_box(color: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## The retired medallion's style, kept ONLY behind the
## MARKWORD NC seam (PVLDS_MARKWORD_NC=hash1): a full
## disc (corner radius = half the 54 px seat), no
## content margins, the "#1" glyph centred on the plaque.
func _score_disc_box(color: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 27
	sb.corner_radius_top_right = 27
	sb.corner_radius_bottom_left = 27
	sb.corner_radius_bottom_right = 27
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


## The board footer's style: a plinth - a slightly lifted
## ground with a marquee-amber rule along its top edge, so
## the band reads as the board's base and the Launch
## button's home before the button even lands on it.
func _footer_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.15)
	sb.border_color = Color(0.55, 0.38, 0.08)
	sb.border_width_top = 3
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	return sb


## A board row's style: _box with the vertical padding
## squeezed (2px, not 6) - board rows are a dense stack,
## and the face's height budget is spent on the type.
func _board_box(color: Color, radius: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = _box(color, radius)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func apply_spec(spec: Dictionary) -> void:
	var kind: String = str(spec.get("kind", "panel"))
	# Per-spec top margin: title cards (panel kind) ride higher so
	# their content registers with the full-bleed art faces - see
	# PANEL_CONTENT_RAISE_PX. Re-asserted on every spec because one
	# CardFace serves all renders, so the raise can never leak into
	# another kind's layout.
	var top_margin_px: int = FACE_MARGIN_TOP_PX
	if kind == "panel":
		top_margin_px = maxi(0, FACE_MARGIN_TOP_PX - PANEL_CONTENT_RAISE_PX)
	elif kind == "board":
		# Boards run a tighter top margin: a full board's
		# rows plus its footer band budget the whole face.
		top_margin_px = 14
	_margin.add_theme_constant_override("margin_top", top_margin_px)
	# Vertical centring (GRADFIX6 item 4c, the Console pass-2
	# field note "words ride high in their tiles"): button
	# and banner faces centre their content BLOCK vertically.
	# The layout was top-anchored end to end - the vbox sat
	# at the top margin with BEGIN alignment and "centered"
	# below set only the labels' HORIZONTAL alignment - so a
	# button's glyph block occupied the top of its canvas
	# and the rest was empty ground (measured on the proof
	# renders: a rail tile's ink centre rode 25 px above its
	# canvas centre at 512x150, Launch 32 px at 512x164, a
	# strip letter 18.5 px at 200x250). Centring the vbox
	# fixes every button-kind surface at once - rail tiles,
	# strip letters, Launch, the SETUP panel's buttons, the
	# detail view's buttons - and the banner faces (placard,
	# SETUP panel face) centre their block the same way.
	# Panel / info / board / row kinds stay top-anchored:
	# their content is a stack that starts at the band.
	# Re-asserted on every spec, like the margins above -
	# one CardFace serves all renders, so the centring can
	# never leak into a top-anchored kind (or out of one).
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER if kind == "button" or kind == "banner" or kind == "strip_section" else BoxContainer.ALIGNMENT_BEGIN
	var bg: Color = _color_of(spec, "bg", Color(0.05, 0.05, 0.09))
	var band: Color = _color_of(spec, "band", Color(0.25, 0.25, 0.38))
	# GRADFIX15 (item 1): a board face is FRAMELESS - no
	# filled panel behind the text. The shared ground rect
	# hides for the board kind and no cover/page ground
	# stands in its place (both deleted): the face texture
	# is the text block itself - band strip, title, deadline,
	# score rows, chips, his-row ground, designer/version
	# notes - on transparency, and the standing quad shows
	# exactly that. Every other kind keeps its ground,
	# re-asserted here like everything on this shared face.
	# The NC seam PVLDS_GF15_NC=panelfill restores the flat
	# panel fill (the spec's "bg" colour, full rect) so the
	# frameless census legs fail by name.
	var frameless: bool = kind == "board" \
		and OS.get_environment("PVLDS_GF15_NC") != "panelfill"
	_bg.visible = not frameless
	_bg.color = bg
	# GRADFIX15 (item 2): there is no spine furniture to
	# assert - _spine_line and _spine_shade are deleted (see
	# the member block's conviction note). The specs'
	# "spine_side" keys are inert data now; nothing on this
	# face reads them.
	# The machined strip's section furniture (GRADFIX14 item
	# 1): stands only for strip_section faces. The gradient
	# carries the mock's four stops; the seam is etched at
	# the right edge (dark line + hairline highlight in the
	# bar's own material); the top/bottom edge lines are the
	# bar's border, drawn identically on every section so
	# the row of sections reads as ONE bar; a lifted section
	# brightens its top highlight and pools shade at its
	# bottom edge (its cast shadow on the bar it rose from).
	var is_strip: bool = kind == "strip_section"
	_strip_grad_rect.visible = is_strip
	_strip_seam_dark.visible = is_strip and bool(spec.get("seam_right", false))
	_strip_seam_light.visible = _strip_seam_dark.visible
	_strip_top_edge.visible = is_strip
	_strip_top_hi.visible = is_strip
	_strip_bot_edge.visible = is_strip
	_strip_accent_bar.visible = is_strip and bool(spec.get("accent_bar", false))
	if is_strip and size.x > 0.0:
		var grad_cols: Array = spec.get("grad", []) as Array
		if grad_cols.size() == 4:
			var g: Gradient = Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
			var cols: PackedColorArray = PackedColorArray()
			for cv: Variant in grad_cols:
				cols.append(Color(cv))
			g.colors = cols
			_strip_grad_tex.gradient = g
		var lifted_s: bool = bool(spec.get("lifted", false))
		_strip_seam_dark.position = Vector2(size.x - 2.0, 0.0)
		_strip_seam_dark.size = Vector2(2.0, size.y)
		_strip_seam_light.position = Vector2(size.x - 3.0, 0.0)
		_strip_seam_light.size = Vector2(1.0, size.y)
		_strip_top_edge.position = Vector2(0.0, 0.0)
		_strip_top_edge.size = Vector2(size.x, 2.0)
		_strip_top_hi.position = Vector2(0.0, 2.0)
		_strip_top_hi.size = Vector2(size.x, 1.0)
		_strip_top_hi.color = Color(1.0, 1.0, 1.0, 0.28 if lifted_s else 0.10)
		_strip_bot_edge.position = Vector2(0.0, size.y - (8.0 if lifted_s else 2.0))
		_strip_bot_edge.size = Vector2(size.x, 8.0 if lifted_s else 2.0)
		_strip_bot_edge.color = Color(0.0, 0.0, 0.0, 0.45 if lifted_s else 0.6)
		_strip_accent_bar.position = Vector2(size.x * 0.18, size.y - 6.0)
		_strip_accent_bar.size = Vector2(size.x * 0.64, 3.0)
	_art_rect.visible = kind == "art"
	# The name strip rides art faces by default; a spec may
	# suppress it ("strip": false) when the surface carries
	# the title itself - the dome room's cards wear a
	# nameplate label on the card, and a second title inside
	# the face would double it (the graduation round).
	_art_strip.visible = kind == "art" and bool(spec.get("strip", true))
	_art_fav.visible = kind == "art" and bool(spec.get("favorite", false))
	_art_pup.visible = kind == "art" and bool(spec.get("pup", false))
	# SCOREMARK (glyph MARKWORD): the wordmark badge stands
	# on the same discipline (spec flag, art kind only),
	# wearing the spec's band colour - rebuilt here because
	# the colour is per-game. Under the MARKWORD NC seam
	# (hash1) the retired "#1" medallion stands in the
	# badge's corner instead, so the wordmark legs fail by
	# name; the seat, offsets and glyph are re-asserted on
	# every marked spec, so the seam can never leak into a
	# later face.
	_art_score.visible = kind == "art" and bool(spec.get("scoremark", false))
	if _art_score.visible:
		var score_col: Color = _color_of(spec, "scoremark_color", Color(0.30, 0.34, 0.60))
		if RoomSpecs.markword_nc == "hash1":
			_art_score.offset_top = -68.0
			_art_score.offset_right = 68.0
			_art_score.add_theme_stylebox_override("panel", _score_disc_box(score_col))
			_art_score_label.text = "#1"
			_art_score_label.add_theme_font_size_override("font_size", 25)
		else:
			_art_score.offset_top = -62.0
			_art_score.offset_right = 170.0
			_art_score.add_theme_stylebox_override("panel", _score_box(score_col))
			_art_score_label.text = "PINemHi"
			_art_score_label.add_theme_font_size_override("font_size", 30)
	_margin.visible = kind != "art"
	if kind == "art":
		var tex: Variant = spec.get("art_texture", null)
		if tex is Texture2D:
			_art_rect.texture = tex
		_art_label.text = str(spec.get("title", ""))
		return

	_restore_labels()
	_band_panel.visible = kind == "panel" or kind == "info" or kind == "board"
	# The Standing Book centres everything (GRADFIX3, the
	# user's direction): a board's band text sits centred on
	# its band like its title, rows and notes below it. Other
	# kinds keep their left-set band.
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if kind == "board" else HORIZONTAL_ALIGNMENT_LEFT
	if _band_panel.visible:
		_band_panel.add_theme_stylebox_override("panel", _box(band, 6))
		_band_label.text = str(spec.get("band_text", ""))
		# A spec may set its own band size ("band_size") -
		# boards run theirs smaller. Re-asserted on every
		# spec, stock 30 as the default.
		var band_px: int = int(spec.get("band_size", 30))
		if kind == "board" and size.x > 0.0 and _band_label.text != "" \
				and OS.get_environment("PVLDS_GRADFIX_NC") != "oldband":
			# A board's band never clips (GRADFIX2 item 2):
			# the label carries no overrun discipline, so on
			# a render narrower than the board's own face -
			# the room's wing - a long band ("SEASON - EXTRA
			# - Phantom of the Opera") simply ran off the
			# canvas's right edge, cut mid-word. The band
			# font scales down until the whole line fits the
			# face's inner width, the same never-clip law
			# the score column lives by. At the board's own
			# width the band fits at its spec size and
			# nothing changes.
			var avail: float = size.x - 52.0 - 28.0 ## the face's side margins plus the band box's content margins
			var need: float = _text_w(_measure_font(), _band_label.text, band_px)
			if need > avail and need > 0.0:
				band_px = maxi(18, int(floor(float(band_px) * avail / need)))
		_band_label.add_theme_font_size_override("font_size", band_px)

	var centered: bool = kind == "button" or kind == "banner" or kind == "board" or kind == "strip_section"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	_chips_row.alignment = BoxContainer.ALIGNMENT_CENTER if kind == "board" else BoxContainer.ALIGNMENT_BEGIN
	_title_label.text = str(spec.get("title", ""))
	var title_px: int = int(spec.get("title_size", 58))
	if kind == "board" and size.x > 0.0 and _title_label.text != "" \
			and OS.get_environment("PVLDS_GRADFIX_NC") != "oldband":
		# A board's title never ellipsizes (GRADFIX2 item
		# 2, the band fit's sibling): the board spec caps
		# the title at one line, so at the wing's width a
		# long title ("Medieval Madness" at 440 px) was
		# cut to "Medieval Madn..." while its band and
		# scores stood whole. The title font scales down
		# until the whole line fits the face's inner
		# width - the same never-clip law. At the board's
		# own width only the very longest titles move.
		var t_avail: float = size.x - 52.0
		var t_need: float = _text_w(_measure_font(), _title_label.text, title_px)
		if t_need > t_avail and t_need > 0.0:
			title_px = maxi(20, int(floor(float(title_px) * t_avail / t_need)))
	if kind == "strip_section" and size.x > 0.0 and _title_label.text != "":
		# A strip section's label never clips (GRADFIX14 item
		# 1, the board fit's sibling law): the longest standing
		# label ("SORT: MANUFACTURER") scales down until the
		# whole line fits its section, floor 24.
		var st_avail: float = size.x - 28.0
		var st_need: float = _text_w(_measure_font(), _title_label.text, title_px)
		if st_need > st_avail and st_need > 0.0:
			title_px = maxi(24, int(floor(float(title_px) * st_avail / st_need)))
			while title_px > 24 and _text_w(_measure_font(), _title_label.text, title_px) > st_avail:
				title_px -= 1
	_title_label.add_theme_font_size_override("font_size", title_px)
	# A spec may dim its own title ("title_color") - the letter
	# strip's greyed slots render through it. Re-asserted on
	# every spec (one CardFace serves all renders), with the
	# stock colour as the default so no dimming can leak.
	_title_label.add_theme_color_override("font_color",
		_color_of(spec, "title_color", Color(0.96, 0.96, 0.98)))
	_sub_label.text = str(spec.get("sub", ""))
	_sub_label.visible = _sub_label.text != ""
	var sub_px: int = int(spec.get("sub_size", 32))
	if kind == "board" and size.x > 0.0 and _sub_label.text != "" \
			and OS.get_environment("PVLDS_GRADFIX_NC") != "oldband":
		# A board's deadline never ellipsizes (GRADFIX8 item
		# 1, the band/title fit's sibling): Chris's field
		# line - "Ends Sat Oct 31, 7:00 PM CDT - 3h 14m left
		# - CLO..." - was the sub label's ellipsis eating
		# CLOSES SOON. The board widened (0.62 -> 0.72 m)
		# and still the longest form (deadline + remaining
		# + CLOSES SOON, 723 px at 26 px on the 620 face)
		# outgrows the page, so the font scales down until
		# the whole line fits, floor 18 like the score law.
		var s_avail: float = size.x - 52.0
		var s_need: float = _text_w(_measure_font(), _sub_label.text, sub_px)
		if s_need > s_avail and s_need > 0.0:
			sub_px = maxi(18, int(floor(float(sub_px) * s_avail / s_need)))
			# The proportional step can land a pixel wide
			# (the renderer's string measure rounds up at
			# some sizes): walk down until the line truly
			# fits, never below the 18 px floor.
			while sub_px > 18 and _text_w(_measure_font(), _sub_label.text, sub_px) > s_avail:
				sub_px -= 1
	_sub_label.add_theme_font_size_override("font_size", sub_px)
	# A spec may warm its own sub line ("sub_color") - the
	# board's deadline does, as its end nears. Re-asserted on
	# every spec (one CardFace serves all renders), with the
	# stock colour as the default so no warmth can leak.
	_sub_label.add_theme_color_override("font_color",
		_color_of(spec, "sub_color", Color(0.75, 0.78, 0.88)))
	_body_label.text = str(spec.get("body", ""))
	_body_label.visible = _body_label.text != ""
	_body_label.add_theme_font_size_override("font_size", int(spec.get("body_size", 34)))
	# Optional per-spec line discipline ("<slot>_max_lines" > 0): cap
	# the label's lines and ellipsize the overrun, so a long string
	# can never push the rest of the card off its texture. Specs that
	# set no cap (detail info, rows, buttons) render exactly as before.
	_discipline_label(_title_label, int(spec.get("title_max_lines", 0)))
	_discipline_label(_sub_label, int(spec.get("sub_max_lines", 0)))
	_discipline_label(_body_label, int(spec.get("body_max_lines", 0)))

	for child: Node in _chips_row.get_children():
		_chips_row.remove_child(child)
		child.queue_free()
	var chips: Variant = spec.get("chips", [])
	if chips is Array:
		var arr: Array = chips
		for item: Variant in arr:
			if item is Dictionary:
				var cd: Dictionary = item
				# A chip may carry its own ground colour
				# ("color": the SCOREMARK chip wears the
				# game's back-band colour, white ink) -
				# absent, the accent/plain grounds stand.
				var chip_col: Variant = cd.get("color", null)
				_chips_row.add_child(_make_chip(str(cd.get("text", "")), bool(cd.get("accent", false)),
					chip_col if chip_col is Color else null))

	# The board kind's rows: rebuilt per spec like the chips
	# (one CardFace serves every render, so nothing may leak
	# from a previous board into this one).
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows_box.visible = kind == "board"
	# The row stack's own separation rides the same spec
	# key as the outer box's (see the separation note in
	# the centring block below): 6 unless the spec says
	# otherwise, re-asserted on every spec.
	_rows_box.add_theme_constant_override("separation", int(spec.get("row_separation", 6)) if kind == "board" else 6)
	if kind == "board":
		var rows_v: Variant = spec.get("rows", [])
		if rows_v is Array:
			var rarr: Array = rows_v
			var layout: Dictionary = _board_layout(rarr)
			for i: int in range(rarr.size()):
				if rarr[i] is Dictionary:
					_rows_box.add_child(_make_board_row(rarr[i], layout, i))
	# The board's footer band: a spec that reserves one (the
	# library flip back - RoomView._card_back_spec re-adds
	# the band the wing waived, because the back carries its
	# own Launch button over this plinth, seated by
	# RoomSpecs.board_launch_y) keeps it at the face's bottom
	# edge. Spacer + band stand only when the spec asks, so
	# a board without a button uses its full height and no
	# other kind ever sees the furniture.
	var footer_px: int = int(spec.get("footer_px", 0)) if kind == "board" else 0
	# Vertical centring (GRADFIX8 item 1, Chris's field
	# verdict on GRADFIX7: the board's info "sits off-centre"
	# - top-loaded, dead space below the rows; the library
	# flip back's TABLE DATA composition the same). A board's
	# content block CENTRES on the area it owns: two expanding
	# spacers share the spare height - one above the band,
	# one below the rows. GRADFIX10 (item 1) corrected the
	# ruler: GRADFIX8 centred a standing board's block in the
	# area above its footer plinth and proved it against that
	# area's centre (+4 px), but the field judges against the
	# standing FRAME - against the full canvas the block rode
	# 66 px high over a dead dark plank, because the plinth
	# was a reservation for a Launch the standing board has
	# not carried since GRADFIX7. Standing boards now reserve
	# no footer (RoomSpecs.tournament_board_spec), so their
	# spacers centre the block on the FULL canvas; a footer
	# spec (the flip back) still centres above its plinth,
	# whose seat its Launch derives from. The NC seams
	# PVLDS_GRADFIX8_NC=offcentre (spacers hidden, the shipped
	# top-loaded composition) and PVLDS_GRADFIX10_NC=
	# deadplank (the standing board's reservation restored)
	# each fail the centring legs by name.
	var centre_board: bool = kind == "board" \
		and OS.get_environment("PVLDS_GRADFIX8_NC") != "offcentre"
	_top_spacer.visible = centre_board
	_footer_spacer.visible = footer_px > 0 or centre_board
	_footer_panel.visible = footer_px > 0
	if footer_px > 0:
		_footer_panel.custom_minimum_size = Vector2(0.0, float(footer_px))
	# GRADFIX10 (item 1): the factory's ink-correction bias
	# ("ink_bias_px", standing boards only): the whole block
	# shifts by this many pixels - down when positive -
	# through the two centring spacers' STRETCH RATIOS.
	# BoxContainer splits the expanders' collective space by
	# ratio (minimum sizes are floors only - measured in the
	# GF10 debug runs, a 200/0 minimum split still landed
	# 310/310, and a margin-pair bias corrupted the
	# MarginContainer's sizing outright), so the ratio pair
	# is the one honest lever: with collective space S, a
	# ratio pair of (S/2 + bias, S/2 - bias) lands the top
	# spacer at S/2 + bias and the block moves exactly bias.
	# S is read off the spacers' standing sizes - the
	# factory's correction re-render always applies its
	# biased spec to the face still wearing the unbiased
	# layout of the same content, whose split was S/2 + S/2.
	# Ratios are re-asserted on every spec (one CardFace
	# serves all renders): an unbiased spec restores 1:1, so
	# a bias can never leak into the next face.
	var ink_bias: int = int(spec.get("ink_bias_px", 0)) if centre_board and footer_px == 0 else 0
	_top_spacer.size_flags_stretch_ratio = 1.0
	_footer_spacer.size_flags_stretch_ratio = 1.0
	if ink_bias != 0:
		var spare: float = _top_spacer.size.y + _footer_spacer.size.y
		if spare > 4.0:
			var half: float = spare * 0.5
			var fb: float = clampf(float(ink_bias), -half + 1.0, half - 1.0)
			_top_spacer.size_flags_stretch_ratio = half + fb
			_footer_spacer.size_flags_stretch_ratio = half - fb
	# Boards breathe tighter than cards: their section gaps
	# run 6px, not 12, so a full board (four score rows, the
	# line, a note) plus its footer band fits the face with
	# room to spare. A spec may carry its own separation
	# (the ONETEN card back does: its fullest composition -
	# his #1, the divider, the Best ten, two wrapped notes -
	# stands 1084 px at 6, over the face; at 2 it fits with
	# every type size and line untouched). Re-asserted on
	# every spec, so it can never leak into the next face.
	_vbox.add_theme_constant_override("separation", int(spec.get("row_separation", 6 if kind == "board" else 12)))
	# A footer board's band owns the face's bottom edge to
	# itself: the stock bottom margin would leave a dead
	# strip under the plinth and shift the band off the
	# geometry RoomSpecs.board_launch_y derives from it.
	# Re-asserted on every spec, like the top margin.
	_margin.add_theme_constant_override("margin_bottom",
		0 if footer_px > 0 else FACE_MARGIN_BOTTOM_PX)


## The board's row geometry for one spec (GRADFIX3, the
## Standing Book's centred page): every score row is a
## CENTRED BLOCK - position, name and score at their natural
## widths, the block centred on the page (the user's
## direction: "Text needs to be centered"). The name takes
## what the position and the score leave of the face's inner
## width and ellipsizes inside it; a row whose position +
## score would squeeze the name under its floor scales the
## whole row's font down until the block fits - a score
## never clips, the law the old fixed column lived by, kept
## under the new shape. Measured with the labels' own font,
## so the numbers are the renderer's numbers.
func _board_layout(entries: Array) -> Dictionary:
	var font: Font = _measure_font()
	var inner: float = size.x - 52.0 - 28.0 - 20.0 ## face margins + the row box's content margins + the row's two separations
	if inner <= 0.0:
		inner = float(RoomSpecs.BOARD_FACE_PX.x) - 100.0
	var per: Dictionary = {}
	for i: int in range(entries.size()):
		if not (entries[i] is Dictionary):
			continue
		var e: Dictionary = entries[i]
		if str(e.get("kind", "")) != "score":
			continue
		var base: int = int(e.get("size", 40))
		var font_px: int = base
		var pos_need: float = _text_w(font, str(e.get("pos_text", "")), font_px)
		var score_need: float = _text_w(font, str(e.get("score_text", "")), font_px)
		if bool(e.get("world1", false)):
			# BESTLINE: the world-#1 row stands on two
			# lines (name line, then the score right-
			# aligned) - at the mandated one-size type
			# the field pair (BaronVanAwesome beside
			# 635,739,180) measures 641 px with its
			# rank, wider than the 620 px face itself,
			# so no one-line share of the row can hold
			# the name whole. The name's allotment here
			# is what its own line leaves after the
			# rank: the full inner width, never a
			# squeezed share beside the score.
			per[i] = {"font": font_px, "pos_w": pos_need, "score_w": score_need,
				"name_w": maxf(24.0, inner - pos_need - 10.0), "w1": true}
			continue
		if pos_need + score_need + 60.0 > inner:
			font_px = maxi(18, int(floor(float(base) * (inner - 60.0) / maxf(1.0, pos_need + score_need))))
			pos_need = _text_w(font, str(e.get("pos_text", "")), font_px)
			score_need = _text_w(font, str(e.get("score_text", "")), font_px)
		per[i] = {"font": font_px, "pos_w": pos_need, "score_w": score_need,
			"name_w": maxf(24.0, inner - pos_need - score_need)}
	return {"rows": per}


func _measure_font() -> Font:
	var f: Font = _band_label.get_theme_font("font")
	if f != null:
		return f
	return ThemeDB.fallback_font


func _text_w(font: Font, text: String, font_size: int) -> float:
	if font == null:
		return float(text.length()) * float(font_size) * 0.55
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


## One board row: a divider (the cutoff line, drawn as a
## ruled line in its tone - green up for a promotion line,
## red down for a cut line), a score row in three columns,
## or a plain note. The legacy single-label score row lives
## on behind the harness's NC seam (RoomSpecs.board_nc_old):
## it is the pre-TR3 shape the layout legs fail against.
func _make_board_row(entry: Dictionary, layout: Dictionary, idx: int) -> Control:
	var kind: String = str(entry.get("kind", "note"))
	var text: String = str(entry.get("text", ""))
	if kind == "divider":
		var rule: Color = Color(0.85, 0.62, 0.20)
		var ink: Color = Color(1.0, 0.85, 0.45)
		var ground: Color = Color(0.20, 0.15, 0.04)
		match str(entry.get("tone", "")):
			"up":
				rule = Color(0.35, 0.85, 0.45)
				ink = Color(0.68, 1.0, 0.74)
				ground = Color(0.07, 0.15, 0.09)
			"down":
				rule = Color(1.0, 0.36, 0.28)
				ink = Color(1.0, 0.64, 0.56)
				ground = Color(0.17, 0.07, 0.06)
		var dp: PanelContainer = PanelContainer.new()
		var dsb: StyleBoxFlat = _board_box(ground, 6)
		dsb.border_color = rule
		dsb.border_width_top = 5
		dp.add_theme_stylebox_override("panel", dsb)
		var dl: Label = Label.new()
		dl.text = text
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_size_override("font_size", int(entry.get("size", 30)))
		dl.add_theme_color_override("font_color", ink)
		dp.add_child(dl)
		dp.set_meta("board_kind", "divider")
		return dp
	if kind == "score":
		var accent: bool = bool(entry.get("accent", false))
		var world1: bool = bool(entry.get("world1", false))
		var sp: PanelContainer = PanelContainer.new()
		if world1:
			# BACKFINE: the online world's #1 row - its own
			# steel-blue ground with a pale leading edge, so
			# the eye separates "the best score anyone has"
			# from the player's own rows (neutral) and his
			# league row (amber accent) at a glance.
			var wsb: StyleBoxFlat = _board_box(Color(0.09, 0.22, 0.40), 6)
			wsb.border_color = Color(0.45, 0.78, 1.0)
			wsb.border_width_left = 8
			sp.add_theme_stylebox_override("panel", wsb)
		elif accent:
			# His row, richer (TR3): a brighter amber ground
			# and a solid gold leading edge, so the eye finds
			# it before it reads anything.
			var asb: StyleBoxFlat = _board_box(Color(0.66, 0.46, 0.10), 6)
			asb.border_color = Color(1.0, 0.80, 0.30)
			asb.border_width_left = 8
			sp.add_theme_stylebox_override("panel", asb)
		else:
			sp.add_theme_stylebox_override("panel", _board_box(Color(0.10, 0.10, 0.16), 6))
		var ink2: Color = Color(1.0, 0.98, 0.92) if accent else Color(0.90, 0.91, 0.96)
		sp.set_meta("board_kind", "score")
		sp.set_meta("score_text", str(entry.get("score_text", "")))
		sp.set_meta("world1", world1)
		if RoomSpecs.board_nc_old:
			# The pre-TR3 row: one label, one line, and the
			# score ellipsized away with the rest when the
			# line outgrows the face. Restored only so the
			# smoke's layout legs can fail against it by name.
			var sl0: Label = Label.new()
			sl0.text = text
			sl0.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			sl0.add_theme_font_size_override("font_size", int(entry.get("size", 40)))
			sl0.add_theme_color_override("font_color", ink2)
			sp.add_child(sl0)
			sp.set_meta("score_label", sl0)
			sp.set_meta("need_text", text)
			return sp
		var per: Dictionary = (layout.get("rows", {}) as Dictionary).get(idx, {}) as Dictionary
		var font_px: int = int(per.get("font", int(entry.get("size", 40))))
		if world1:
			# BESTLINE: the world-#1 row - ONE row on its
			# steel-blue ground, standing on two lines:
			# the rank + name centred as a block on the
			# first line (the name at the full allotment
			# its line leaves - see _board_layout for the
			# measured reason no one-line row can hold
			# it), the score right-aligned on the second.
			# Type stays the back's one size; the name
			# ellipsizes only past its line's own edge.
			var vb1: VBoxContainer = VBoxContainer.new()
			vb1.add_theme_constant_override("separation", 0)
			var h1: HBoxContainer = HBoxContainer.new()
			h1.alignment = BoxContainer.ALIGNMENT_CENTER
			h1.add_theme_constant_override("separation", 10)
			var pl1: Label = Label.new()
			pl1.text = str(entry.get("pos_text", ""))
			pl1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			pl1.add_theme_font_size_override("font_size", font_px)
			pl1.add_theme_color_override("font_color", ink2)
			h1.add_child(pl1)
			var nl1: Label = Label.new()
			nl1.text = str(entry.get("name_text", ""))
			nl1.custom_minimum_size = Vector2(float(per.get("name_w", 200.0)), 0.0)
			nl1.autowrap_mode = TextServer.AUTOWRAP_OFF
			nl1.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			nl1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			nl1.add_theme_font_size_override("font_size", font_px)
			nl1.add_theme_color_override("font_color", ink2)
			h1.add_child(nl1)
			vb1.add_child(h1)
			var sl1: Label = Label.new()
			sl1.text = str(entry.get("score_text", ""))
			sl1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sl1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sl1.add_theme_font_size_override("font_size", font_px)
			sl1.add_theme_color_override("font_color", ink2)
			vb1.add_child(sl1)
			sp.add_child(vb1)
			sp.set_meta("score_label", sl1)
			sp.set_meta("name_label", nl1)
			sp.set_meta("name_text", str(entry.get("name_text", "")))
			return sp
		# The centred block (GRADFIX3): the row's three
		# parts at their natural widths, centred on the
		# page as one unit; the name holds the allotment
		# the layout measured for it and ellipsizes there.
		var h: HBoxContainer = HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 10)
		var pl: Label = Label.new()
		pl.text = str(entry.get("pos_text", ""))
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_theme_font_size_override("font_size", font_px)
		pl.add_theme_color_override("font_color", ink2)
		h.add_child(pl)
		var nl2: Label = Label.new()
		nl2.text = str(entry.get("name_text", ""))
		nl2.custom_minimum_size = Vector2(float(per.get("name_w", 200.0)), 0.0)
		nl2.autowrap_mode = TextServer.AUTOWRAP_OFF
		nl2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl2.add_theme_font_size_override("font_size", font_px)
		nl2.add_theme_color_override("font_color", ink2)
		h.add_child(nl2)
		var sl: Label = Label.new()
		sl.text = str(entry.get("score_text", ""))
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.add_theme_font_size_override("font_size", font_px)
		sl.add_theme_color_override("font_color", ink2)
		h.add_child(sl)
		if bool(entry.get("pending", false)):
			# A pending score carries its state as a quiet
			# second line inside its own row - centred
			# under its block on the book page, small, dim
			# amber - instead of stretching the score line
			# (TR1) or spending a whole note row (TR3).
			var vb: VBoxContainer = VBoxContainer.new()
			vb.add_theme_constant_override("separation", 0)
			vb.add_child(h)
			var pend: Label = Label.new()
			pend.text = "awaiting validation"
			pend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pend.add_theme_font_size_override("font_size", 22)
			pend.add_theme_color_override("font_color", Color(0.88, 0.74, 0.45))
			vb.add_child(pend)
			sp.add_child(vb)
		else:
			sp.add_child(h)
		sp.set_meta("score_label", sl)
		sp.set_meta("name_label", nl2)
		sp.set_meta("name_text", str(entry.get("name_text", "")))
		return sp
	if kind == "kv":
		# CARDBACK (item 3, second leg): a Spec Sheet grid
		# row - the fact's key at the left in rest grey, its
		# value right-aligned in ink, and the source dot at
		# the right edge naming the well the row came from
		# (● db dim / ● ipdb teal). No panel ground: the grid
		# stands on the frameless back like the rest of the
		# post-saga furniture. Under the nodots NC the spec
		# carries no "src" and no dot is drawn - the smoke
		# legs fail by name.
		var kp: PanelContainer = PanelContainer.new()
		kp.add_theme_stylebox_override("panel", _board_box(Color(0, 0, 0, 0), 0))
		var kh: HBoxContainer = HBoxContainer.new()
		kh.add_theme_constant_override("separation", 14)
		var kl: Label = Label.new()
		kl.text = str(entry.get("k", ""))
		kl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kl.add_theme_font_size_override("font_size", int(entry.get("size", 30)))
		kl.add_theme_color_override("font_color", Color(0.66, 0.68, 0.72))
		kh.add_child(kl)
		var vl: Label = Label.new()
		vl.text = str(entry.get("v", ""))
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vl.add_theme_font_size_override("font_size", int(entry.get("size", 30)))
		vl.add_theme_color_override("font_color", Color(0.91, 0.93, 0.97))
		kh.add_child(vl)
		var src: String = str(entry.get("src", ""))
		if src != "":
			var dl2: Label = Label.new()
			dl2.text = "● " + src
			dl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dl2.add_theme_font_size_override("font_size", 20)
			dl2.add_theme_color_override("font_color",
				Color(0.50, 0.83, 0.76) if src == "ipdb" else Color(0.43, 0.45, 0.50))
			kh.add_child(dl2)
		kp.add_child(kh)
		kp.set_meta("board_kind", "kv")
		kp.set_meta("kv_key", str(entry.get("k", "")))
		kp.set_meta("kv_value", str(entry.get("v", "")))
		kp.set_meta("kv_src", src)
		# The note-label lesson above applies to the wrapped
		# value too: preset the row's width so its reported
		# minimum is the wrapped height it will stand at.
		kp.size = Vector2(maxf(1.0, size.x - 52.0), 0.0)
		return kp
	var nl: Label = Label.new()
	nl.text = text
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.add_theme_font_size_override("font_size", int(entry.get("size", 34)))
	nl.add_theme_color_override("font_color", Color(0.80, 0.82, 0.90))
	nl.set_meta("board_kind", "note")
	# A fresh autowrap label reports its minimum height
	# shaped at its CURRENT width - zero before its first
	# sort - which reads as one character per line (the
	# no-score board's note measured 1447 px against its
	# standing 47) and poisons the vbox's minimum for the
	# sort that follows: on any re-render of a note-carrying
	# board the face ballooned past its own height and the
	# sizes never recovered (GRADFIX10's debug conviction -
	# the permanent labels and the panelled rows are immune:
	# one keeps its standing width, the others' minima are
	# width-independent). Preset the label's width to the
	# rows' width so the minimum it reports is the wrapped
	# height it will actually stand at; the container's
	# sort assigns the real size regardless.
	nl.size = Vector2(maxf(1.0, size.x - 52.0), 0.0)
	return nl


## The standing board spec's layout, measured off the built
## controls (the smoke's layout legs read this): every row's
## rect in face space; for score rows, the score label's own
## rect and whether the score's full text fits it at the
## rendered font - need measured with the renderer's font,
## allotment the label's real width. Read it after a render,
## while this face still wears the board.
func board_metrics() -> Dictionary:
	var rows: Array = []
	for child: Node in _rows_box.get_children():
		var c: Control = child as Control
		if c == null or not c.has_meta("board_kind"):
			continue
		var d: Dictionary = {"kind": str(c.get_meta("board_kind")), "rect": c.get_global_rect()}
		if str(d["kind"]) == "kv":
			d["kv_key"] = str(c.get_meta("kv_key"))
			d["kv_value"] = str(c.get_meta("kv_value"))
			d["kv_src"] = str(c.get_meta("kv_src"))
		if str(d["kind"]) == "score":
			d["world1"] = bool(c.get_meta("world1")) if c.has_meta("world1") else false
			var sl: Label = c.get_meta("score_label") as Label
			if sl != null:
				var need_text: String = str(c.get_meta("need_text")) if c.has_meta("need_text") else str(c.get_meta("score_text"))
				d["score_rect"] = sl.get_global_rect()
				d["score_text"] = str(c.get_meta("score_text"))
				d["font_px"] = sl.get_theme_font_size("font_size")
				d["score_need_px"] = _text_w(_measure_font(), need_text, int(d["font_px"]))
				d["score_allot_px"] = sl.get_global_rect().size.x
			# BESTLINE: the name label's own fit, judged
			# the same way - the smoke's name leg reads
			# the world-#1 name whole off the rendered
			# face (need vs the label's standing width).
			if c.has_meta("name_label"):
				var nl3: Label = c.get_meta("name_label") as Label
				if nl3 != null:
					d["name_text"] = str(c.get_meta("name_text")) if c.has_meta("name_text") else nl3.text
					d["name_need_px"] = _text_w(_measure_font(), str(d["name_text"]), int(d.get("font_px", 38)))
					d["name_allot_px"] = nl3.get_global_rect().size.x
		rows.append(d)
	var out: Dictionary = {"rows": rows, "face_size": size}
	if _footer_panel.visible:
		out["footer"] = _footer_panel.get_global_rect()
	# GRADFIX8 (item 1): the content block's union rect - band,
	# title, sub, chips and rows, WITHOUT the footer plinth or
	# the centring spacers - plus the sub (deadline) line's fit.
	# The centring legs and the harness pixel proof read the
	# block's centroid against the canvas centre from here.
	var block: Rect2 = Rect2()
	var have_block: bool = false
	var parts: Array[Control] = [_band_panel, _title_label, _sub_label, _body_label]
	if _chips_row.get_child_count() > 0:
		parts.append(_chips_row)
	if _rows_box.visible and _rows_box.get_child_count() > 0:
		parts.append(_rows_box)
	for part: Control in parts:
		if part == null or not part.visible:
			continue
		var r: Rect2 = part.get_global_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		block = r if not have_block else block.merge(r)
		have_block = true
	if have_block:
		out["content_rect"] = block
	# GRADFIX15 (item 3): the content block's INDIVIDUAL part
	# rects - band, title, sub, body, the chips row as one,
	# and each board row on its own (never the rows box as a
	# whole: its gaps are exactly where a stray fill or the
	# old spine line would stand). The frameless census
	# (TextureFactory.frameless_census) judges every visible
	# pixel against this set: ink inside a part is the text
	# block; visible alpha anywhere else is a stray.
	var part_rects: Array = []
	for part2: Control in parts:
		if part2 == null or not part2.visible or part2 == _rows_box:
			continue
		var r2: Rect2 = part2.get_global_rect()
		if r2.size.x > 0.0 and r2.size.y > 0.0:
			part_rects.append(r2)
	if _rows_box.visible:
		for child: Node in _rows_box.get_children():
			var rc: Control = child as Control
			if rc != null and rc.visible:
				var rr: Rect2 = rc.get_global_rect()
				if rr.size.x > 0.0 and rr.size.y > 0.0:
					part_rects.append(rr)
	out["part_rects"] = part_rects
	out["sub_text"] = _sub_label.text
	out["sub_need_px"] = _text_w(_measure_font(), _sub_label.text, _sub_label.get_theme_font_size("font_size"))
	out["sub_allot_px"] = _sub_label.get_global_rect().size.x
	return out


func _snapshot_label(l: Label) -> void:
	_label_stock.append([l, l.autowrap_mode, l.max_lines_visible, l.text_overrun_behavior])


func _restore_labels() -> void:
	for entry_v: Variant in _label_stock:
		var e: Array = entry_v as Array
		if e.size() < 4:
			continue
		var l: Label = e[0] as Label
		if l == null:
			continue
		l.set("autowrap_mode", e[1])
		l.max_lines_visible = int(e[2])
		l.set("text_overrun_behavior", e[3])


func _discipline_label(l: Label, max_lines: int) -> void:
	if max_lines <= 0:
		return
	l.max_lines_visible = max_lines
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if max_lines == 1:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF


func _make_chip(text: String, accent: bool, ground: Variant = null) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	var col: Color = Color(0.55, 0.38, 0.08) if accent else Color(0.16, 0.16, 0.24)
	var ink: Color = Color(0.97, 0.95, 0.9) if accent else Color(0.82, 0.84, 0.92)
	if ground is Color:
		col = ground
		ink = Color(0.98, 0.98, 1.0)
	pc.add_theme_stylebox_override("panel", _box(col, 8))
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", ink)
	pc.add_child(l)
	return pc


func _color_of(spec: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = spec.get(key, fallback)
	if v is Color:
		return v
	return fallback
