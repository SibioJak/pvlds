class_name BootFace
extends CanvasLayer

## BOOTFACE: the configured boot's own loading face. A plain
## dark screen carrying the word "LaunchPin" and one live
## scanning line - no setup fields, no buttons, no inputs,
## nothing clickable. It stands from the boot's first frame
## until the threaded scan lands and the room takes over (or
## the desk stands in its place when the auto-enter is
## cancelled). The setup desk is never created while it stands:
## setup exists only when the user asks for it.

var _title_label: Label
var _scan_label: Label


func _init() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox: VBoxContainer = VBoxContainer.new()
	center.add_child(vbox)
	_title_label = Label.new()
	_title_label.text = "LaunchPin"
	_title_label.add_theme_font_size_override("font_size", 48)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	_scan_label = Label.new()
	_scan_label.text = "Scanning..."
	_scan_label.add_theme_font_size_override("font_size", 20)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_scan_label)


## The live scanning line, fed by Main's _process poll of the
## threaded scan's progress (the same text the desk and the
## in-room SETUP panel consume).
func set_scan_text(text: String) -> void:
	if _scan_label != null:
		_scan_label.text = text


## Smoke census.
func title_text() -> String:
	return _title_label.text if _title_label != null else ""


## Smoke census.
func scan_text() -> String:
	return _scan_label.text if _scan_label != null else ""
