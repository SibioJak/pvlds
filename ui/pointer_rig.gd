class_name PointerRig
extends Node3D

## The one pointer for the whole room, whatever hand holds it:
##   - VR: laser from the active XR controller (trigger selects)
##   - Desk: ray from the fallback camera through the mouse (click selects)
## Gamepad/keyboard focus navigation lives in the Room, not here.
## Hover/select are computed with manual physics raycasts against
## layer 2 so mouse, gamepad focus, and VR all share one picking model.
## M1 simplification: a single shared hover - both controllers feed the
## same ray choice (right hand preferred), not one hover per hand.

signal hover_changed(quad: ClickableQuad)
signal select_pressed(quad: ClickableQuad)

var xr_active: bool = false
var mouse_camera: Camera3D = null
var hovered: ClickableQuad = null

var _controllers: Array[XRController3D] = []
var _lasers: Dictionary = {} ## XRController3D -> laser MeshInstance3D
var _dot: MeshInstance3D = null


func _ready() -> void:
	_dot = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.009
	sphere.height = 0.018
	_dot.mesh = sphere
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.8, 0.35)
	_dot.material_override = m
	_dot.visible = false
	add_child(_dot)


func setup_controllers(origin: XROrigin3D) -> void:
	_controllers.clear()
	for child: Node in origin.get_children():
		if child is XRController3D:
			var ctrl: XRController3D = child
			_controllers.append(ctrl)
			var laser: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.0035, 0.0035, 1.0)
			laser.mesh = box
			var lm: StandardMaterial3D = StandardMaterial3D.new()
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lm.albedo_color = Color(0.6, 0.75, 1.0, 0.55)
			lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			laser.material_override = lm
			laser.visible = false
			ctrl.add_child(laser)
			_lasers[ctrl] = laser
			ctrl.button_pressed.connect(_on_controller_button)


func _on_controller_button(button_name: String) -> void:
	if button_name == "trigger_click" or button_name == "select":
		select_pressed.emit(hovered)


func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			select_pressed.emit(hovered)


func _process(_delta: float) -> void:
	var origin: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3.ZERO
	var have_ray: bool = false
	var active_ctrl: XRController3D = null
	if xr_active:
		for ctrl: XRController3D in _controllers:
			if ctrl.get_is_active():
				active_ctrl = ctrl
				if str(ctrl.tracker) == "/user/hand/right":
					break
		if active_ctrl != null:
			origin = active_ctrl.global_position
			dir = -active_ctrl.global_transform.basis.z.normalized()
			have_ray = true
	elif mouse_camera != null:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		origin = mouse_camera.project_ray_origin(mouse_pos)
		dir = mouse_camera.project_ray_normal(mouse_pos)
		have_ray = true

	for ctrl: Variant in _lasers.keys():
		var laser: MeshInstance3D = _lasers[ctrl]
		laser.visible = xr_active and ctrl == active_ctrl

	if not have_ray:
		_set_hovered(null)
		_dot.visible = false
		return

	var world: World3D = get_world_3d()
	if world == null:
		return
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + dir * 30.0)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	var quad: ClickableQuad = null
	var hit_pos: Vector3 = origin + dir * 8.0
	if not hit.is_empty():
		hit_pos = hit["position"]
		var collider: Object = hit["collider"]
		if collider is ClickableQuad:
			var cq: ClickableQuad = collider
			if cq.pick_enabled:
				quad = cq
	_set_hovered(quad)
	_dot.visible = quad != null
	if quad != null:
		_dot.global_position = hit_pos
	if xr_active and active_ctrl != null:
		var laser: MeshInstance3D = _lasers[active_ctrl]
		var dist: float = clampf(origin.distance_to(hit_pos), 0.1, 30.0)
		laser.position = Vector3(0.0, 0.0, -dist * 0.5)
		laser.scale = Vector3(1.0, 1.0, dist)


func _set_hovered(q: ClickableQuad) -> void:
	if q != hovered:
		hovered = q
		hover_changed.emit(q)
