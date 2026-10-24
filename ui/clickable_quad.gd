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

var _mat: StandardMaterial3D
var _frame_mat: StandardMaterial3D
var _frame: MeshInstance3D

const HOVER_COLOR: Color = Color(0.9, 0.66, 0.18)
const FOCUS_COLOR: Color = Color(0.35, 0.75, 1.0)


func setup(p_action: String, p_payload: String, tex: Texture2D, size: Vector2) -> void:
	action_id = p_action
	payload = p_payload
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


## The texture the face currently shows (the nav smoke reads
## it to prove the rail never falls back to the placeholder).
func current_texture() -> Texture2D:
	return _mat.albedo_texture if _mat != null else null


## Fade the quad's face (and its frame) toward transparent via
## the materials' albedo alpha (see setup for why the material
## route, not the instance fade). The loading marquee's wall
## fade drives this (room.gd). 1 = fully opaque (the resting
## state), 0 = invisible. Only the alpha moves - the frame's
## hover/focus colour and the face's white tint are preserved.
func set_content_alpha(a: float) -> void:
	var alpha: float = clampf(a, 0.0, 1.0)
	if _mat != null:
		var c: Color = _mat.albedo_color
		c.a = alpha
		_mat.albedo_color = c
	if _frame_mat != null:
		var fc: Color = _frame_mat.albedo_color
		fc.a = alpha
		_frame_mat.albedo_color = fc


func set_visual_state(hovered: bool, focused: bool) -> void:
	if _frame == null:
		return
	_frame.visible = hovered or focused
	if focused:
		_frame_mat.albedo_color = FOCUS_COLOR
	elif hovered:
		_frame_mat.albedo_color = HOVER_COLOR


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
