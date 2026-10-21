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
## Specs are plain dictionaries built by callers; reads are defensive.
## A spec may cap a text slot's lines ("title_max_lines" and friends);
## a capped label ellipsizes its overrun instead of wrapping without
## limit and pushing the rest of the card off its texture.

var _bg: ColorRect
var _margin: MarginContainer
var _vbox: VBoxContainer
var _band_panel: PanelContainer
var _band_label: Label
var _title_label: Label
var _sub_label: Label
var _body_label: Label
var _chips_row: HBoxContainer
var _art_rect: TextureRect
var _art_strip: PanelContainer
var _art_label: Label
var _label_stock: Array = [] ## [label, autowrap, max_lines, overrun] per text label, for per-spec restore


func _init() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.05, 0.09)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_art_rect = TextureRect.new()
	_art_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art_rect.visible = false
	add_child(_art_rect)
	_art_strip = PanelContainer.new()
	_art_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_art_strip.offset_top = -92.0
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

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 26)
	_margin.add_theme_constant_override("margin_right", 26)
	_margin.add_theme_constant_override("margin_top", 22)
	_margin.add_theme_constant_override("margin_bottom", 22)
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


func apply_spec(spec: Dictionary) -> void:
	var kind: String = str(spec.get("kind", "panel"))
	var bg: Color = _color_of(spec, "bg", Color(0.05, 0.05, 0.09))
	var band: Color = _color_of(spec, "band", Color(0.25, 0.25, 0.38))
	_bg.color = bg
	_art_rect.visible = kind == "art"
	_art_strip.visible = kind == "art"
	_margin.visible = kind != "art"
	if kind == "art":
		var tex: Variant = spec.get("art_texture", null)
		if tex is Texture2D:
			_art_rect.texture = tex
		_art_label.text = str(spec.get("title", ""))
		return

	_restore_labels()
	_band_panel.visible = kind == "panel" or kind == "info"
	if _band_panel.visible:
		_band_panel.add_theme_stylebox_override("panel", _box(band, 6))
		_band_label.text = str(spec.get("band_text", ""))

	var centered: bool = kind == "button" or kind == "banner"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	_title_label.text = str(spec.get("title", ""))
	_title_label.add_theme_font_size_override("font_size", int(spec.get("title_size", 58)))
	_sub_label.text = str(spec.get("sub", ""))
	_sub_label.visible = _sub_label.text != ""
	_sub_label.add_theme_font_size_override("font_size", int(spec.get("sub_size", 32)))
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
