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
##            whole. An owned board reserves a footer band at
##            the face's bottom (spec "footer_px") for the
##            room's Launch button: a plinth the text never
##            flows into.
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
## texture's bottom edge. Named because the room's Launch-button
## placement (ui/room.gd, PANEL_LAUNCH_Y) is derived from it - the
## button must clear this strip, never cover the name it carries.
const ART_STRIP_HEIGHT_PX: int = 92

## The art face's favorite mark: a star badge in the face's top
## right corner (the panel face carries the same fact as a
## FAVORITE chip). Marquee amber so the mark reads as one family
## with the chips; the top corner keeps it clear of the name
## strip (bottom edge) and the card's Launch button (lower
## third) at wall distance.
const FAVORITE_STAR_COLOR: Color = Color(1.0, 0.78, 0.25)

## Board score rows: TR3's fixed right-aligned score
## column is superseded by the Standing Book (GRADFIX3) -
## a row is a centred block (position / name / score at
## natural widths) and a row whose block would squeeze
## the name under its floor scales down whole instead of
## ever clipping a digit. The old cap constant stays only
## as the record of the TR3 law.
const BOARD_SCORE_COL_MAX_PX: float = 330.0

var _bg: ColorRect
var _cover_rect: ColorRect ## board kind (GRADFIX4, One Book): the book's cover - a border of the card frame's own stock around the page, so the text page and the art page wear the same frame
var _page_tex: GradientTexture2D ## board kind: the page gradient, aimed per spec at the spine side
var _page_rect: TextureRect ## board kind: the One Book's page gradient (lit at the free edge, darkening toward the spine)
var _spine_line: ColorRect ## board kind: the spine ridge's highlight hairline, just inside the spine edge
var _spine_shade: ColorRect ## board kind: the dark fall past the spine hairline, to the spine edge
var _margin: MarginContainer
var _vbox: VBoxContainer
var _band_panel: PanelContainer
var _band_label: Label
var _title_label: Label
var _sub_label: Label
var _body_label: Label
var _chips_row: HBoxContainer
var _rows_box: VBoxContainer ## the board kind's stacked rows (score / divider / note)
var _footer_spacer: Control ## board kind: pushes the footer band to the face's bottom edge
var _footer_panel: PanelContainer ## board kind: the Launch button's plinth (spec "footer_px")
var _art_rect: TextureRect
var _art_strip: PanelContainer
var _art_label: Label
var _art_fav: PanelContainer
var _art_fav_label: Label
var _label_stock: Array = [] ## [label, autowrap, max_lines, overrun] per text label, for per-spec restore


func _init() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.05, 0.09)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	# The One Book's page (GRADFIX4): a board face is a page
	# of the focused card's own book - the paper sits inside
	# a COVER of the card frame's stock (the border the 3D
	# frame quad continues around the page), lit at its free
	# edge and shading down toward the spine, which sits at
	# whichever edge joins the art page (spec "spine_side":
	# "right" for the library wing, "left" for the Tournament
	# board). The gradient and the spine furniture draw over
	# the ground and under every line of type; they stand
	# only for the board kind, asserted per spec like
	# everything else on this shared face.
	_cover_rect = ColorRect.new()
	_cover_rect.color = Color(0.025, 0.03, 0.06)
	_cover_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover_rect.visible = false
	add_child(_cover_rect)
	_page_rect = TextureRect.new()
	var page_grad: Gradient = Gradient.new()
	page_grad.set_color(0, Color(0.115, 0.145, 0.225))
	page_grad.set_color(1, Color(0.035, 0.045, 0.09))
	_page_tex = GradientTexture2D.new()
	_page_tex.gradient = page_grad
	_page_tex.fill_from = Vector2(0.0, 0.5)
	_page_tex.fill_to = Vector2(1.0, 0.5)
	_page_tex.width = 256
	_page_tex.height = 8
	_page_rect.texture = _page_tex
	_page_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_rect.offset_left = 10.0
	_page_rect.offset_top = 10.0
	_page_rect.offset_right = -10.0
	_page_rect.offset_bottom = -10.0
	_page_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_page_rect.visible = false
	add_child(_page_rect)
	_spine_line = ColorRect.new()
	_spine_line.color = Color(0.48, 0.55, 0.70, 0.85)
	_spine_line.visible = false
	add_child(_spine_line)
	_spine_shade = ColorRect.new()
	_spine_shade.color = Color(0.008, 0.012, 0.028, 0.6)
	_spine_shade.visible = false
	add_child(_spine_shade)

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
	var bg: Color = _color_of(spec, "bg", Color(0.05, 0.05, 0.09))
	var band: Color = _color_of(spec, "band", Color(0.25, 0.25, 0.38))
	_bg.color = bg
	# The One Book's page furniture stands for board faces
	# only (GRADFIX4); the spine ridge hugs the page's SPINE
	# edge - the edge that joins the art page (spec
	# "spine_side", default "right") - the gradient darkens
	# toward it and the hairline + fall sit just inside the
	# cover border.
	_cover_rect.visible = kind == "board"
	_page_rect.visible = kind == "board"
	_spine_line.visible = kind == "board"
	_spine_shade.visible = kind == "board"
	if kind == "board" and size.x > 0.0:
		var spine_left: bool = str(spec.get("spine_side", "right")) == "left"
		_page_tex.fill_from = Vector2(1.0, 0.5) if spine_left else Vector2(0.0, 0.5)
		_page_tex.fill_to = Vector2(0.0, 0.5) if spine_left else Vector2(1.0, 0.5)
		if spine_left:
			_spine_shade.position = Vector2(10.0, 10.0)
			_spine_shade.size = Vector2(31.0, size.y - 20.0)
			_spine_line.position = Vector2(41.0, 10.0)
			_spine_line.size = Vector2(3.0, size.y - 20.0)
		else:
			_spine_line.position = Vector2(size.x - 44.0, 10.0)
			_spine_line.size = Vector2(3.0, size.y - 20.0)
			_spine_shade.position = Vector2(size.x - 41.0, 10.0)
			_spine_shade.size = Vector2(31.0, size.y - 20.0)
	_art_rect.visible = kind == "art"
	# The name strip rides art faces by default; a spec may
	# suppress it ("strip": false) when the surface carries
	# the title itself - the dome room's cards wear a
	# nameplate label on the card, and a second title inside
	# the face would double it (the graduation round).
	_art_strip.visible = kind == "art" and bool(spec.get("strip", true))
	_art_fav.visible = kind == "art" and bool(spec.get("favorite", false))
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

	var centered: bool = kind == "button" or kind == "banner" or kind == "board"
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
	_title_label.add_theme_font_size_override("font_size", title_px)
	# A spec may dim its own title ("title_color") - the letter
	# strip's greyed slots render through it. Re-asserted on
	# every spec (one CardFace serves all renders), with the
	# stock colour as the default so no dimming can leak.
	_title_label.add_theme_color_override("font_color",
		_color_of(spec, "title_color", Color(0.96, 0.96, 0.98)))
	_sub_label.text = str(spec.get("sub", ""))
	_sub_label.visible = _sub_label.text != ""
	_sub_label.add_theme_font_size_override("font_size", int(spec.get("sub_size", 32)))
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
				_chips_row.add_child(_make_chip(str(cd.get("text", "")), bool(cd.get("accent", false))))

	# The board kind's rows: rebuilt per spec like the chips
	# (one CardFace serves every render, so nothing may leak
	# from a previous board into this one).
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows_box.visible = kind == "board"
	if kind == "board":
		var rows_v: Variant = spec.get("rows", [])
		if rows_v is Array:
			var rarr: Array = rows_v
			var layout: Dictionary = _board_layout(rarr)
			for i: int in range(rarr.size()):
				if rarr[i] is Dictionary:
					_rows_box.add_child(_make_board_row(rarr[i], layout, i))
	# The board's footer band: an owned board reserves the
	# face's bottom for its Launch button (the room parks the
	# button over this plinth - see RoomSpecs.board_launch_y).
	# Spacer + band stand only when the spec asks, so a
	# board without a button uses its full height and no
	# other kind ever sees the furniture.
	var footer_px: int = int(spec.get("footer_px", 0)) if kind == "board" else 0
	_footer_spacer.visible = footer_px > 0
	_footer_panel.visible = footer_px > 0
	if footer_px > 0:
		_footer_panel.custom_minimum_size = Vector2(0.0, float(footer_px))
	# Boards breathe tighter than cards: their section gaps
	# run 6px, not 12, so a full board (four score rows, the
	# line, a note) plus its footer band fits the face with
	# room to spare. Re-asserted on every spec.
	_vbox.add_theme_constant_override("separation", 6 if kind == "board" else 12)
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
		var sp: PanelContainer = PanelContainer.new()
		if accent:
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
		# The centred block (GRADFIX3): the row's three
		# parts at their natural widths, centred on the
		# page as one unit; the name holds the allotment
		# the layout measured for it and ellipsizes there.
		var per: Dictionary = (layout.get("rows", {}) as Dictionary).get(idx, {}) as Dictionary
		var font_px: int = int(per.get("font", int(entry.get("size", 40))))
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
		return sp
	var nl: Label = Label.new()
	nl.text = text
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.add_theme_font_size_override("font_size", int(entry.get("size", 34)))
	nl.add_theme_color_override("font_color", Color(0.80, 0.82, 0.90))
	nl.set_meta("board_kind", "note")
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
		if str(d["kind"]) == "score":
			var sl: Label = c.get_meta("score_label") as Label
			if sl != null:
				var need_text: String = str(c.get_meta("need_text")) if c.has_meta("need_text") else str(c.get_meta("score_text"))
				d["score_rect"] = sl.get_global_rect()
				d["score_text"] = str(c.get_meta("score_text"))
				d["font_px"] = sl.get_theme_font_size("font_size")
				d["score_need_px"] = _text_w(_measure_font(), need_text, int(d["font_px"]))
				d["score_allot_px"] = sl.get_global_rect().size.x
		rows.append(d)
	var out: Dictionary = {"rows": rows, "face_size": size}
	if _footer_panel.visible:
		out["footer"] = _footer_panel.get_global_rect()
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


func _make_chip(text: String, accent: bool) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	var col: Color = Color(0.55, 0.38, 0.08) if accent else Color(0.16, 0.16, 0.24)
	pc.add_theme_stylebox_override("panel", _box(col, 8))
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9) if accent else Color(0.82, 0.84, 0.92))
	pc.add_child(l)
	return pc


func _color_of(spec: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = spec.get(key, fallback)
	if v is Color:
		return v
	return fallback
