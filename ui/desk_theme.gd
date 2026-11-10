class_name DeskTheme
extends RefCounted

## SETUPLOOK: the desk's Machined dress — the 2D (Control)
## expression of the room's Machined Strip recipe (RoomSpecs'
## STRIP_* constants are the palette law, hex for hex). The
## strip is drawn by CardFace as textures on 3D quads; a form
## needs theme styleboxes instead, so the same recipe is
## baked here into small gradient textures (StyleBoxTexture
## 9-patches) and flat boxes:
##   buttons   rest = the bar's resting gradient; hover a
##             step up (the accent gradient); pressed a step
##             down; focus = the lifted gradient (the strip's
##             focus read, with white text); disabled = the
##             gradient DRAINED to a flat dark fill with a
##             dull edge and dim text, so an unarmed button
##             (Enter the Room before a scan) cannot be
##             mistaken for a live one.
##   fields    dark insets with a machined border; the
##             focused field takes the bright edge.
##   checkboxes a drawn box in the field family with a light
##             check; clearly on, clearly off.
##   labels    the theme's Label tone is CardFace's body tone;
##             field labels wear the strip's resting grey.
## Everything here is dress only: the desk's controls,
## signals, defaults and words are untouched. The theme is
## set on the desk's ScrollContainer, so it reaches the whole
## form and nothing outside it (the FileDialog keeps the
## stock system dress).

const FONT_MEDIUM: Font = preload("res://assets/fonts/SpaceGrotesk-Medium.ttf")
const FONT_REGULAR: Font = preload("res://assets/fonts/SpaceGrotesk-Regular.ttf")

## The desk ground: the strip gradient's darkest stop,
## lifted a touch so the form reads as the room's dark
## furniture rather than a black void.
const GROUND: Color = Color8(18, 19, 24)
## Body/status text (CardFace's body tone).
const BODY_FG: Color = Color(0.85, 0.86, 0.92)
## Field recipe: a near-black inset, a machined border, and
## the bright edge a focused field takes.
const FIELD_BG: Color = Color8(13, 14, 19)
const FIELD_BG_FOCUS: Color = Color8(17, 18, 25)
const FIELD_BORDER: Color = Color8(56, 61, 71)
const FIELD_BORDER_FOCUS: Color = Color8(146, 154, 170)
const FIELD_FG: Color = Color8(226, 229, 236)
const FIELD_PLACEHOLDER: Color = Color8(116, 121, 133)
## The pressed gradient: the resting gradient stepped down.
const GRAD_PRESSED: Array[Color] = [Color8(38, 41, 47), Color8(27, 29, 35), Color8(21, 23, 27), Color8(29, 32, 37)]
## Disabled: flat, drained, dull-edged.
const DISABLED_BG: Color = Color8(27, 29, 35)
const DISABLED_BORDER: Color = Color8(48, 52, 61)
const DISABLED_FG: Color = Color8(102, 107, 118)

const _PATCH_W: int = 96
const _PATCH_H: int = 48

## DESKCOLOR: the desk's colour families (Chris's map, the
## brief's literals). The graphite stays the base; a family
## colour tints the machined gradient, tints the edges, and
## wears the accent underline, so the page's colour tells
## the story before the words do. WoVP steel dresses its
## three section bars; PINemHi violet its own; amber the
## Table folders bar and the photo pair; slate the picker
## buttons; green the WoVP key pair.
const FAMILY_WOVP: Color = Color(0.36, 0.55, 0.72)
const FAMILY_PINEMHI: Color = Color(0.62, 0.45, 0.85)
const FAMILY_AMBER: Color = Color(1.0, 0.66, 0.16)
const FAMILY_PICKER: Color = Color(0.45, 0.55, 0.68)
const FAMILY_CONFIRM: Color = Color(0.35, 0.75, 0.45)
## Family buttons keep their text near-white so the colour
## reads as the button's own, not the text's.
const FAMILY_TEXT: Color = Color(0.94, 0.95, 0.98)
## The standing accent underline's ink on undressed boxes.
const ACCENT_INK: Color = Color(0.85, 0.87, 0.92, 0.9)

static var _cached: Theme = null
static var _family_boxes: Dictionary = {}


## The desk's whole theme, built once per process (the
## gradient patches are generated images).
static func build() -> Theme:
	if _cached != null:
		return _cached
	var t: Theme = Theme.new()
	# Buttons (and the OptionButton, its sibling).
	var boxes: Dictionary = {
		"normal": _button_box(RoomSpecs.STRIP_GRAD_REST, false),
		"hover": _button_box(RoomSpecs.STRIP_GRAD_ACCENT, false),
		"pressed": _button_box(GRAD_PRESSED, false),
		"focus": _button_box(RoomSpecs.STRIP_GRAD_LIFTED, false),
		"disabled": _disabled_box(),
	}
	for type_name: String in ["Button", "OptionButton"]:
		for state: String in boxes:
			t.set_stylebox(state, type_name, boxes[state])
		t.set_color("font_color", type_name, RoomSpecs.STRIP_LABEL_REST)
		t.set_color("font_hover_color", type_name, RoomSpecs.STRIP_LABEL_ACCENT)
		t.set_color("font_pressed_color", type_name, RoomSpecs.STRIP_LABEL_ACCENT)
		t.set_color("font_focus_color", type_name, Color(1, 1, 1))
		t.set_color("font_disabled_color", type_name, DISABLED_FG)
	# Fields: dark insets; the focused field takes the
	# bright edge.
	t.set_stylebox("normal", "LineEdit", _field_box(FIELD_BORDER, FIELD_BG))
	t.set_stylebox("focus", "LineEdit", _field_box(FIELD_BORDER_FOCUS, FIELD_BG_FOCUS))
	t.set_stylebox("read_only", "LineEdit", _field_box(FIELD_BORDER, FIELD_BG))
	t.set_color("font_color", "LineEdit", FIELD_FG)
	t.set_color("font_placeholder_color", "LineEdit", FIELD_PLACEHOLDER)
	t.set_color("caret_color", "LineEdit", Color(0.92, 0.93, 0.97))
	t.set_color("selection_color", "LineEdit", Color(0.30, 0.35, 0.48, 0.85))
	# Labels: the body tone for everything; callers override
	# the special cases (title, field labels, headers).
	t.set_color("font_color", "Label", BODY_FG)
	# Checkboxes: drawn box icons in the field family.
	t.set_icon("checked", "CheckBox", _check_texture(true, false))
	t.set_icon("unchecked", "CheckBox", _check_texture(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_texture(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_texture(false, true))
	t.set_color("font_color", "CheckBox", BODY_FG)
	t.set_color("font_hover_color", "CheckBox", Color(0.93, 0.94, 0.97))
	t.set_color("font_pressed_color", "CheckBox", BODY_FG)
	t.set_color("font_disabled_color", "CheckBox", DISABLED_FG)
	# Theme lookup climbs the class chain, so without its
	# own empty boxes a CheckBox would wear the Button
	# gradient as a full-width slab behind its text. The
	# checkbox stands bare - box icon, text, and (on focus)
	# the outline below.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	var check_focus: StyleBoxFlat = StyleBoxFlat.new()
	check_focus.draw_center = false
	check_focus.border_color = FIELD_BORDER_FOCUS
	check_focus.set_border_width_all(1)
	check_focus.set_corner_radius_all(3)
	t.set_stylebox("focus", "CheckBox", check_focus)
	# Scrollbars: a dark track, a graphite grabber.
	for bar_type: String in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar_type, _flat(Color8(12, 13, 18), Color8(12, 13, 18), 5))
		t.set_stylebox("grabber", bar_type, _flat(Color8(54, 59, 69), RoomSpecs.STRIP_BORDER, 0))
		t.set_stylebox("grabber_highlight", bar_type, _flat(Color8(70, 76, 89), RoomSpecs.STRIP_BORDER, 0))
		t.set_stylebox("grabber_pressed", bar_type, _flat(Color8(86, 93, 107), RoomSpecs.STRIP_BORDER, 0))
	_cached = t
	return t


## The title block's panel: the accent gradient with the
## standing accent underline — the desk's name plate, worn
## like a strip stop.
static func title_header_box() -> StyleBoxTexture:
	return _patch_box(RoomSpecs.STRIP_GRAD_ACCENT, true, 16, 12)


## A section header bar: the resting gradient in the strip
## segment's manner.
static func section_header_box() -> StyleBoxTexture:
	return _patch_box(RoomSpecs.STRIP_GRAD_REST, false, 12, 7)


## DESKCOLOR: a family section bar — the resting gradient
## tinted toward the family colour, the family colour on
## the accent underline and in the edges; the bar's body
## stays graphite family.
static func section_header_box_family(family: Color) -> StyleBoxTexture:
	return _patch_box_dressed(_tint_grad(RoomSpecs.STRIP_GRAD_REST, family, 0.30), true, 12, 7,
		family, RoomSpecs.STRIP_BORDER.lerp(family, 0.45))


## A family title's tint: the family colour lightened
## toward white, readability first.
static func section_title_tint(family: Color) -> Color:
	return family.lerp(Color(1, 1, 1), 0.45)


## DESKCOLOR: a family's button dress, built once per
## family. Every state wears the tinted gradient and the
## family's accent underline — except disabled, which is
## the stock drained box: the colour drains with the
## button (the DESKEDIT rule).
static func button_family_boxes(family: Color) -> Dictionary:
	if _family_boxes.has(family):
		return _family_boxes[family]
	var border: Color = RoomSpecs.STRIP_BORDER.lerp(family, 0.45)
	var boxes: Dictionary = {
		"normal": _patch_box_dressed(_tint_grad(RoomSpecs.STRIP_GRAD_REST, family, 0.30), true, 14, 7, family, border),
		"hover": _patch_box_dressed(_tint_grad(RoomSpecs.STRIP_GRAD_ACCENT, family, 0.30), true, 14, 7, family, border),
		"pressed": _patch_box_dressed(_tint_grad(GRAD_PRESSED, family, 0.25), true, 14, 7, family, border),
		"focus": _patch_box_dressed(_tint_grad(RoomSpecs.STRIP_GRAD_LIFTED, family, 0.30), true, 14, 7, family, border),
		"disabled": _disabled_box(),
	}
	_family_boxes[family] = boxes
	return boxes


## Dress one button in a family's colours (stylebox
## overrides on the button itself; the desk's theme keeps
## every other button). Text stays near-white.
static func dress_button_family(b: Button, family: Color) -> void:
	var boxes: Dictionary = button_family_boxes(family)
	for state: String in boxes:
		b.add_theme_stylebox_override(state, boxes[state])
	b.add_theme_color_override("font_color", FAMILY_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", DISABLED_FG)


static func _tint_grad(grad: Array, tint: Color, amount: float) -> Array:
	var out: Array = []
	for c: Variant in grad:
		out.append(Color(c).lerp(tint, amount))
	return out


## A dark inset frame (the submit photo's seat).
static func inset_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color8(10, 11, 15)
	sb.border_color = FIELD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## The dropdown popup's panel and hovered-item boxes (the
## OptionButton's popup is styled directly — it lives
## outside the form's theme chain).
static func popup_panel_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color8(24, 26, 32)
	sb.border_color = RoomSpecs.STRIP_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func popup_hover_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color8(51, 55, 64)
	sb.set_corner_radius_all(3)
	return sb


static func _flat(bg: Color, border: Color, pad: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	if pad > 0:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = pad
		sb.content_margin_bottom = pad
	return sb


static func _field_box(border: Color, bg: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func _button_box(grad: Array, accent: bool) -> StyleBoxTexture:
	var sb: StyleBoxTexture = _patch_box(grad, accent, 14, 7)
	return sb


static func _disabled_box() -> StyleBoxTexture:
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(_patch_image([], false, true))
	sb.texture_margin_left = 4
	sb.texture_margin_right = 4
	sb.texture_margin_top = 5
	sb.texture_margin_bottom = 8
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


static func _patch_box(grad: Array, accent: bool, pad_x: int, pad_y: int) -> StyleBoxTexture:
	return _patch_box_dressed(grad, accent, pad_x, pad_y, ACCENT_INK, RoomSpecs.STRIP_BORDER)


static func _patch_box_dressed(grad: Array, accent: bool, pad_x: int, pad_y: int, accent_ink: Color, border_ink: Color) -> StyleBoxTexture:
	var sb: StyleBoxTexture = StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(_patch_image_dressed(grad, accent, false, accent_ink, border_ink))
	# The margins pin the edge rows/columns: the gradient's
	# middle stretches, the machined edges never do.
	sb.texture_margin_left = 4
	sb.texture_margin_right = 4
	sb.texture_margin_top = 5
	sb.texture_margin_bottom = 8
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## One gradient patch, drawn the strip's way (CardFace's
## furniture, baked): the four-stop vertical gradient, the
## border-colour top edge and side borders, the machined
## highlight under the top edge, the dark bottom edge, and
## — when accented — the standing light underline.
static func _patch_image(grad: Array, accent: bool, flat: bool) -> Image:
	return _patch_image_dressed(grad, accent, flat, ACCENT_INK, RoomSpecs.STRIP_BORDER)


static func _patch_image_dressed(grad: Array, accent: bool, flat: bool, accent_ink: Color, border_ink: Color) -> Image:
	var img: Image = Image.create(_PATCH_W, _PATCH_H, false, Image.FORMAT_RGBA8)
	if flat:
		for y: int in range(_PATCH_H):
			for x: int in range(_PATCH_W):
				img.set_pixel(x, y, DISABLED_BG)
		for x: int in range(_PATCH_W):
			img.set_pixel(x, 0, DISABLED_BORDER)
			img.set_pixel(x, 1, DISABLED_BORDER)
			img.set_pixel(x, _PATCH_H - 2, DISABLED_BORDER)
			img.set_pixel(x, _PATCH_H - 1, DISABLED_BORDER)
		for y: int in range(_PATCH_H):
			img.set_pixel(0, y, DISABLED_BORDER)
			img.set_pixel(1, y, DISABLED_BORDER)
			img.set_pixel(_PATCH_W - 2, y, DISABLED_BORDER)
			img.set_pixel(_PATCH_W - 1, y, DISABLED_BORDER)
		return img
	for y: int in range(_PATCH_H):
		var row: Color = _grad_color(grad, float(y) / float(_PATCH_H - 1))
		for x: int in range(_PATCH_W):
			img.set_pixel(x, y, row)
	for y: int in range(_PATCH_H):
		img.set_pixel(0, y, border_ink)
		img.set_pixel(1, y, border_ink)
		img.set_pixel(_PATCH_W - 2, y, border_ink)
		img.set_pixel(_PATCH_W - 1, y, border_ink)
	for x: int in range(_PATCH_W):
		img.set_pixel(x, 0, border_ink)
		img.set_pixel(x, 1, border_ink)
		img.set_pixel(x, 2, img.get_pixel(x, 2).lerp(Color(1, 1, 1), 0.10))
		img.set_pixel(x, _PATCH_H - 2, img.get_pixel(x, _PATCH_H - 2).lerp(Color.BLACK, 0.6))
		img.set_pixel(x, _PATCH_H - 1, img.get_pixel(x, _PATCH_H - 1).lerp(Color.BLACK, 0.6))
	if accent:
		var bar: Color = accent_ink
		for y: int in range(_PATCH_H - 6, _PATCH_H - 3):
			for x: int in range(int(_PATCH_W * 0.18), int(_PATCH_W * 0.82)):
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(bar, bar.a))
	return img


## The strip's four stops (0 / 45% / 55% / 1), sampled.
static func _grad_color(cols: Array, t: float) -> Color:
	var stops: Array[float] = [0.0, 0.45, 0.55, 1.0]
	for i: int in range(3):
		if t <= stops[i + 1]:
			var f: float = (t - stops[i]) / (stops[i + 1] - stops[i])
			return Color(cols[i]).lerp(Color(cols[i + 1]), f)
	return Color(cols[3])


## A checkbox square in the field family: dark inset, a
## machined border, and — when on — a light check drawn
## across it. Clearly on, clearly off, at form size.
static func _check_texture(on: bool, disabled: bool) -> Texture2D:
	var size: int = 24
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var border: Color = Color8(56, 60, 69) if disabled else Color8(96, 102, 114)
	var fill: Color = Color8(19, 20, 26) if disabled else FIELD_BG
	var ink: Color = Color8(110, 115, 126) if disabled else Color8(228, 232, 240)
	for y: int in range(size):
		for x: int in range(size):
			var edge: bool = x < 2 or y < 2 or x >= size - 2 or y >= size - 2
			img.set_pixel(x, y, border if edge else fill)
	if on:
		# The check: two strokes, (6,12) -> (10,17) -> (18,6),
		# lit where a pixel falls within reach of either.
		var a: Vector2 = Vector2(6, 12)
		var b: Vector2 = Vector2(10, 17)
		var c: Vector2 = Vector2(18, 6)
		for y: int in range(size):
			for x: int in range(size):
				var p: Vector2 = Vector2(x, y)
				if _segment_distance(p, a, b) < 1.7 or _segment_distance(p, b, c) < 1.7:
					img.set_pixel(x, y, ink)
	return ImageTexture.create_from_image(img)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var denom: float = ab.length_squared()
	if denom <= 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)
