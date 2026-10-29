class_name ClickableQuad
extends Area3D

## One interactive surface in the room: a textured quad with a thin
## collision box, picked by the PointerRig's manual raycasts (layer 2).
## Visual states: hover = amber frame, focus (gamepad/keyboard) = blue
## frame. The quad's textured face (+Z) must look at the player - the
## material is double-sided, but text reads correctly only from +Z, so
## placement code orients quads with face_player().

var action_id: String = ""
var payload: String = ""
var pick_enabled: bool = true
var _size: Vector2 = Vector2.ZERO ## the quad's face size, as set up (the tournament smoke reads board panels')

var _mat: StandardMaterial3D
var _frame_mat: StandardMaterial3D
var _frame: MeshInstance3D
var _content_alpha: float = 1.0 ## the face's current fade (set_content_alpha): the frame's ceiling too
var _hovered: bool = false ## the last visual state the room asked for; the frame's showing is derived, never stored raw
var _focused: bool = false

const HOVER_COLOR: Color = Color(0.9, 0.66, 0.18)
const FOCUS_COLOR: Color = Color(0.35, 0.75, 1.0)


func setup(p_action: String, p_payload: String, tex: Texture2D, size: Vector2) -> void:
	action_id = p_action
	payload = p_payload
	_size = size
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true

	_frame_mat = StandardMaterial3D.new()
	_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_mat.albedo_color = HOVER_COLOR
	_frame = MeshInstance3D.new()
	var fq: QuadMesh = QuadMesh.new()
	fq.size = size * 1.055
	_frame.mesh = fq
	_frame.material_override = _frame_mat
	_frame.position = Vector3(0.0, 0.0, -0.012)
	_frame.visible = false
	add_child(_frame)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Alpha transparency from the start (its alpha sits at 1 until
	# set_content_alpha moves it): the wall fade animates the
	# material's albedo alpha - the per-instance
	# GeometryInstance3D.transparency fade is silently ignored by
	# the Compatibility renderer. Depth is always written so the
	# resting room resolves overlaps exactly like an opaque one.
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_mat.albedo_texture = tex
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var qm: QuadMesh = QuadMesh.new()
	qm.size = size
	mesh_instance.mesh = qm
	mesh_instance.material_override = _mat
	add_child(mesh_instance)

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.05)
	shape.shape = box
	add_child(shape)


func set_texture(tex: Texture2D) -> void:
	if _mat != null and tex != null:
		_mat.albedo_texture = tex


## Resize the highlight frame (the dome room's cards carry
## their own frame geometry - see RoomView._make_card_nodes -
## and size this quad's ring to match it).
func set_frame_size(size: Vector2) -> void:
	if _frame != null and _frame.mesh is QuadMesh:
		(_frame.mesh as QuadMesh).size = size


## The texture the face currently shows (the nav smoke reads
## it to prove the rail never falls back to the placeholder).
func current_texture() -> Texture2D:
	return _mat.albedo_texture if _mat != null else null


## The face size the quad was set up with.
func quad_size() -> Vector2:
	return _size


## Fade the quad's face (and its frame) toward transparent via
## the materials' albedo alpha (see setup for why the material
## route, not the instance fade). The loading marquee's wall
## fade drives this (room.gd). 1 = fully opaque (the resting
## state), 0 = invisible. Only the alpha moves - the frame's
## hover/focus colour and the face's white tint are preserved.
func set_content_alpha(a: float) -> void:
	var alpha: float = clampf(a, 0.0, 1.0)
	_content_alpha = alpha
	if _mat != null:
		var c: Color = _mat.albedo_color
		c.a = alpha
		_mat.albedo_color = c
	if _frame_mat != null:
		var fc: Color = _frame_mat.albedo_color
		fc.a = alpha
		_frame_mat.albedo_color = fc
	_apply_frame_state()


func set_visual_state(hovered: bool, focused: bool) -> void:
	_hovered = hovered
	_focused = focused
	_apply_frame_state()


## The frame's one showing rule, derived fresh at every change
## (state, fade, visibility): a highlight may show only while
## its quad's FACE shows - hovered or focused, not faded away,
## and visible in the tree. It used to be a raw stored flag
## (visible = hovered or focused, colour slammed to full
## alpha), so a focused quad whose face was faded or wearing
## a broken texture stood in the room as a bare cyan bar - an
## invisible highlighted button (Chris, 2026-10-25). A frame
## with no visible face behind it is now impossible by
## construction, not by callers remembering to hide it.
func _apply_frame_state() -> void:
	if _frame == null or _frame_mat == null:
		return
	var show: bool = (_hovered or _focused) and _content_alpha > 0.01 and is_visible_in_tree()
	_frame.visible = show
	if _focused:
		_frame_mat.albedo_color = Color(FOCUS_COLOR, _content_alpha)
	elif _hovered:
		_frame_mat.albedo_color = Color(HOVER_COLOR, _content_alpha)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_frame_state()


## Smoke seams: is the highlight frame flagged showing, and
## how faded is the face it would frame?
func highlight_visible() -> bool:
	return _frame != null and _frame.visible


func content_alpha() -> float:
	return _content_alpha


func pulse() -> void:
	var s0: Vector3 = scale
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", s0 * 1.07, 0.07)
	tw.tween_property(self, "scale", s0, 0.14)


## Orients the quad so its textured face (+Z) looks at the given point.
static func face_point(node: Node3D, point: Vector3) -> void:
	if node.global_position.distance_squared_to(point) < 0.0001:
		return
	node.look_at(point, Vector3.UP)
	node.rotate_object_local(Vector3.UP, PI)
