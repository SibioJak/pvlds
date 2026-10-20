class_name TextureFactory
extends Node

## Renders CardFace specs to textures through one shared SubViewport.
## Callers must serialize renders (await each call) - the room does.
## In headless/dummy rendering a capture can come back empty; callers
## always get a usable texture (a dark solid) rather than null.

var _viewport: SubViewport
var _face: CardFace


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(512, 640)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_face = CardFace.new()
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_face)


func render_texture(spec: Dictionary, px_size: Vector2i) -> Texture2D:
	_viewport.size = px_size
	_face.apply_spec(spec)
	await get_tree().process_frame
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var tex: Texture2D = _viewport.get_texture()
	if tex == null:
		return make_solid(Color(0.08, 0.08, 0.12))
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return make_solid(Color(0.08, 0.08, 0.12))
	return ImageTexture.create_from_image(img)


static func make_solid(color: Color) -> Texture2D:
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Loads an image file as a texture, downscaled to a sane VRAM size.
static func load_art_texture(path: String) -> Texture2D:
	var img: Image = Image.new()
	if img.load(path) != OK:
		return null
	if img.get_width() > 1024:
		var ratio: float = 1024.0 / float(img.get_width())
		img.resize(1024, int(float(img.get_height()) * ratio), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
