class_name PointerRig
extends Node3D

## Pointers for the whole room:
##   - VR: a laser for each tracked hand (its trigger selects its target)
##   - Desk: ray from the fallback camera through the mouse (click selects)
## Gamepad/keyboard focus navigation lives in the Room, not here.
## Hover/select are computed with manual physics raycasts against
## layer 2 so mouse, gamepad focus, and VR all share one picking model.
## The room keeps one highlighted hover, owned by the last selecting
## hand (right hand initially). Each hand's ray and click stay independent.

signal hover_changed(quad: ClickableQuad)
signal select_pressed(quad: ClickableQuad)

## These are XRServer tracker names, distinct from the OpenXR user
## paths in the action map. OpenXR maps /user/hand/left to left_hand
## and /user/hand/right to right_hand before registering controllers.
const HAND_TRACKERS: Array[StringName] = [&"left_hand", &"right_hand"]
const HOVER_EDGE_MARGIN_M: float = 0.025

var xr_active: bool = false
var mouse_camera: Camera3D = null
var hovered: ClickableQuad = null

var _controllers: Array[XRController3D] = []
var _lasers: Dictionary = {} ## XRController3D -> laser MeshInstance3D
var _hand_dots: Dictionary = {} ## XRController3D -> hit marker
var _dot: MeshInstance3D = null
var _active_controller: XRController3D = null
var _hover_ray: Dictionary = {}
var _hand_hover_hits: Dictionary = {}
var _desktop_hover_hit: Dictionary = {}
var _xr_diagnostic_elapsed: float = 0.0
var _xr_diagnostic: XrInputDiagnostics = XrInputDiagnostics.new()


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
			var dot: MeshInstance3D = MeshInstance3D.new()
			dot.mesh = _dot.mesh
			dot.material_override = _dot.material_override
			dot.visible = false
			add_child(dot)
			_hand_dots[ctrl] = dot
			ctrl.button_pressed.connect(_on_controller_button.bind(ctrl))


static func add_hand_controllers(origin: XROrigin3D) -> void:
	for tracker_name: StringName in HAND_TRACKERS:
		var ctrl: XRController3D = XRController3D.new()
		ctrl.tracker = tracker_name
		origin.add_child(ctrl)


func _on_controller_button(button_name: String, ctrl: XRController3D) -> void:
	var selects: bool = button_name in ["trigger_click", "select", "select_button"]
	if not xr_active:
		if selects:
			select_pressed.emit(hovered)
		return
	var quad: ClickableQuad = null
	var tracked: bool = _tracked_controllers().has(ctrl)
	if selects:
		if tracked:
			_active_controller = ctrl
			_hover_ray = _controller_ray(ctrl)
			var hit: Dictionary = _pick_controller(ctrl)
			quad = hit["quad"]
			_set_hovered(quad)
			_update_hand_laser(ctrl, hit)
	_xr_diagnostic.record_event("controller_button", {"hand": str(ctrl.tracker), "action": button_name,
		"tracked": tracked, "hover": quad.action_id if quad != null else ""})
	if selects and tracked:
		select_pressed.emit(quad)


func _unhandled_input(event: InputEvent) -> void:
	if xr_active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Hover has a small release margin; clicks always use the
			# exact current ray so empty space cannot activate a card.
			if mouse_camera != null:
				var mouse_pos: Vector2 = get_viewport().get_mouse_position()
				var hit: Dictionary = _pick_ray(mouse_camera.project_ray_origin(mouse_pos), mouse_camera.project_ray_normal(mouse_pos))
				_set_hovered(hit["quad"])
				select_pressed.emit(hit["quad"])


## A registered pose may remain "active" after tracking is lost.
## Resolve a currently tracked pose before choosing a hand; otherwise
## an untracked right hand can mask a working left hand indefinitely.
static func tracked_pose_name(tracker: XRPositionalTracker) -> StringName:
	if tracker == null:
		return &""
	for pose_name: StringName in [&"aim", &"default", &"grip"]:
		var pose: XRPose = tracker.get_pose(pose_name)
		if pose != null and pose.has_tracking_data:
			return pose_name
	return &""


func _tracked_controllers() -> Array[XRController3D]:
	var tracked: Array[XRController3D] = []
	for ctrl: XRController3D in _controllers:
		var tracker: XRPositionalTracker = XRServer.get_tracker(ctrl.tracker) as XRPositionalTracker
		var pose_name: StringName = tracked_pose_name(tracker)
		if pose_name == &"":
			continue
		if ctrl.pose != pose_name:
			ctrl.pose = pose_name
		# The XRServer is the source of current tracking. Refresh a
		# node binding only when it still references another pose.
		var pose: XRPose = tracker.get_pose(pose_name)
		if ctrl.get_pose() != pose:
			var tracker_name: StringName = ctrl.tracker
			ctrl.tracker = &""
			ctrl.tracker = tracker_name
			ctrl.pose = pose_name # set_tracker resets the pose to default.
			_xr_diagnostic.record_event("controller_rebound", {"hand": str(tracker_name), "pose": str(pose_name)})
		# Setting pose updates the transform but not Godot's cached
		# node tracking flag until another pose_changed event arrives.
		# Read the actual pose, which we already verified is tracked.
		ctrl.transform = pose.get_adjusted_transform()
		tracked.append(ctrl)
	return tracked


func _choose_controller(tracked: Array[XRController3D]) -> XRController3D:
	if tracked.has(_active_controller):
		return _active_controller
	for ctrl: XRController3D in tracked:
		if ctrl.tracker == &"right_hand":
			return ctrl
	return tracked[0] if not tracked.is_empty() else null


func _tracked_controller() -> XRController3D:
	return _choose_controller(_tracked_controllers())


func hover_ray_sample() -> Dictionary:
	return _hover_ray


## Spatial navigation samples are separate from picking and hover.
## Both hands may request a scroll without changing hover ownership.
func edge_scroll_samples(camera: Camera3D, distance: float) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if xr_active:
		if camera == null:
			return samples
		for ctrl: XRController3D in _tracked_controllers():
			samples.append(PointerEdgeScroll.vr_sample(str(ctrl.tracker), camera.global_transform,
				ctrl.global_position, -ctrl.global_transform.basis.z.normalized(), distance))
	else:
		samples.append(PointerEdgeScroll.mouse_sample(get_viewport().get_mouse_position(), get_viewport().get_visible_rect()))
	return samples


func _controller_ray(ctrl: XRController3D) -> Dictionary:
	if ctrl == null:
		return {"valid": false}
	return {"valid": true, "hand": str(ctrl.tracker), "origin": ctrl.global_position,
		"direction": -ctrl.global_transform.basis.z.normalized()}


func _process(delta: float) -> void:
	for ctrl: Variant in _lasers:
		(_lasers[ctrl] as MeshInstance3D).visible = false
		(_hand_dots[ctrl] as MeshInstance3D).visible = false
	if xr_active:
		_dot.visible = false
		var tracked: Array[XRController3D] = _tracked_controllers()
		var active_ctrl: XRController3D = _choose_controller(tracked)
		_hover_ray = _controller_ray(active_ctrl)
		_hover_ray["target_valid"] = false
		var active_quad: ClickableQuad = null
		for ctrl: Variant in _hand_hover_hits.keys():
			if not tracked.has(ctrl):
				_hand_hover_hits.erase(ctrl)
		for ctrl: XRController3D in tracked:
			var raw_hit: Dictionary = _pick_controller(ctrl)
			var hit: Dictionary = stable_hover_hit(ctrl.global_position, -ctrl.global_transform.basis.z.normalized(),
				raw_hit, _hand_hover_hits.get(ctrl, {}))
			_hand_hover_hits[ctrl] = hit
			_update_hand_laser(ctrl, hit)
			if ctrl == active_ctrl:
				active_quad = hit["quad"]
				_hover_ray["target_valid"] = raw_hit["quad"] != null
		_set_hovered(active_quad)
		_xr_diagnostic_elapsed += delta
		if _xr_diagnostic_elapsed >= 0.5:
			_xr_diagnostic_elapsed = 0.0
			_xr_diagnostic.observe(_controllers, active_ctrl, get_window().has_focus())
		return
	_hover_ray = {}
	if mouse_camera == null:
		_set_hovered(null)
		_dot.visible = false
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = mouse_camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = mouse_camera.project_ray_normal(mouse_pos)
	var raw_hit: Dictionary = _pick_ray(origin, direction)
	_hover_ray = {"valid": true, "hand": "mouse", "origin": origin, "direction": direction,
		"target_valid": raw_hit["quad"] != null}
	var hit: Dictionary = stable_hover_hit(origin, direction, raw_hit, _desktop_hover_hit)
	_desktop_hover_hit = hit
	_set_hovered(hit["quad"])
	_dot.visible = hovered != null
	if _dot.visible:
		_dot.global_position = hit["position"]


func _pick_controller(ctrl: XRController3D) -> Dictionary:
	return _pick_ray(ctrl.global_position, -ctrl.global_transform.basis.z.normalized())


func _pick_ray(origin: Vector3, dir: Vector3) -> Dictionary:
	var world: World3D = get_world_3d()
	if world == null:
		return {"quad": null, "position": origin + dir * 8.0}
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
			if cq.pick_enabled and cq.is_visible_in_tree():
				quad = cq
	return {"quad": quad, "position": hit_pos}


## Keep hover through tiny excursions beyond a card edge, but release
## it as soon as the ray moves beyond the margin or hits another item.
## This is visual hysteresis only: clicking uses the raw physics hit.
## Edge scrolling uses view position and does not consult either hit.
static func stable_hover_hit(origin: Vector3, direction: Vector3, raw_hit: Dictionary, previous: Dictionary) -> Dictionary:
	if raw_hit.get("quad") != null:
		return raw_hit
	var old_quad: Variant = previous.get("quad")
	if not is_instance_valid(old_quad):
		return raw_hit
	var quad: ClickableQuad = old_quad as ClickableQuad
	if quad == null or not quad.pick_enabled or not quad.is_visible_in_tree():
		return raw_hit
	var inverse: Transform3D = quad.global_transform.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = inverse.basis * direction
	if absf(local_direction.z) < 0.000001:
		return raw_hit
	var distance: float = -local_origin.z / local_direction.z
	if distance <= 0.0 or distance > 30.0:
		return raw_hit
	var point: Vector3 = local_origin + local_direction * distance
	if absf(point.x) > quad._size.x * 0.5 + HOVER_EDGE_MARGIN_M \
		or absf(point.y) > quad._size.y * 0.5 + HOVER_EDGE_MARGIN_M:
		return raw_hit
	return {"quad": quad, "position": origin + direction * distance, "held_at_edge": true}


func _update_hand_laser(ctrl: XRController3D, hit: Dictionary) -> void:
	var laser: MeshInstance3D = _lasers[ctrl]
	var dot: MeshInstance3D = _hand_dots[ctrl]
	laser.visible = true
	dot.visible = hit["quad"] != null
	var hit_pos: Vector3 = hit["position"]
	if dot.visible:
		dot.global_position = hit_pos
	var dist: float = clampf(ctrl.global_position.distance_to(hit_pos), 0.1, 30.0)
	laser.position = Vector3(0.0, 0.0, -dist * 0.5)
	laser.scale = Vector3(1.0, 1.0, dist)


func _set_hovered(q: ClickableQuad) -> void:
	if q != hovered:
		hovered = q
		hover_changed.emit(q)
