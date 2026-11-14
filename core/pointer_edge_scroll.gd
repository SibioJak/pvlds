class_name PointerEdgeScroll
extends RefCounted

## View-relative edge zones never move with the game wall. Hovered
## cards and collision hits do not participate in scrolling decisions.
const MOUSE_EDGE_FRACTION: float = 0.12
const VR_EDGE_ANGLE_RAD: float = deg_to_rad(35.0)
const RELEASE_RATIO: float = 0.84
const ENTER_SEC: float = 0.25
const REPEAT_SEC: float = 0.12
const MAX_FRAME_SEC: float = 0.1

var _zones: Dictionary = {}
var _direction: int = 0
var _elapsed: float = 0.0
var _repeating: bool = false


static func mouse_sample(point: Vector2, viewport: Rect2) -> Dictionary:
	if viewport.size.x <= 0.0 or viewport.size.y <= 0.0 or not viewport.has_point(point):
		return {"source": "mouse", "valid": false}
	var uv: Vector2 = (point - viewport.position) / viewport.size
	return {"source": "mouse", "valid": uv.y >= 0.05 and uv.y <= 0.8,
		"x": (uv.x - 0.5) / (0.5 - MOUSE_EDGE_FRACTION)}


static func vr_sample(source: String, camera: Transform3D, origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var inverse: Transform3D = camera.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = inverse.basis * direction
	if distance <= 0.0 or local_direction.z >= -0.000001:
		return {"source": source, "valid": false}
	var t: float = (-distance - local_origin.z) / local_direction.z
	if t <= 0.0:
		return {"source": source, "valid": false}
	var point: Vector3 = local_origin + local_direction * t
	var yaw: float = atan2(point.x, distance)
	var pitch: float = atan2(point.y, distance)
	return {"source": source, "valid": absf(yaw) <= deg_to_rad(70.0)
		and pitch >= deg_to_rad(-22.0) and pitch <= deg_to_rad(35.0),
		"x": yaw / VR_EDGE_ANGLE_RAD}


func reset() -> void:
	_zones.clear()
	_direction = 0
	_elapsed = 0.0
	_repeating = false


func observe(samples: Array[Dictionary], can_left: bool, can_right: bool, delta: float, travelling: bool) -> int:
	var zones: Dictionary = {}
	var left: bool = false
	var right: bool = false
	for sample: Dictionary in samples:
		var source: String = str(sample.get("source", ""))
		var zone: int = 0
		if bool(sample.get("valid", false)):
			var x: float = float(sample.get("x", 0.0))
			var previous: int = int(_zones.get(source, 0))
			if x >= 1.0 or (previous == 1 and x >= RELEASE_RATIO):
				zone = 1
			elif x <= -1.0 or (previous == -1 and x <= -RELEASE_RATIO):
				zone = -1
		zones[source] = zone
		left = left or zone < 0
		right = right or zone > 0
	_zones = zones
	# Opposing hands cancel rather than fighting over the drum.
	var direction: int = 0 if left == right else (-1 if left else 1)
	if (direction < 0 and not can_left) or (direction > 0 and not can_right):
		direction = 0
	if direction == 0 or direction != _direction:
		_elapsed = 0.0
		_repeating = false
	_direction = direction
	if direction == 0:
		return 0
	if travelling:
		_elapsed = 0.0
		return 0
	_elapsed += clampf(delta, 0.0, MAX_FRAME_SEC)
	var delay: float = REPEAT_SEC if _repeating else ENTER_SEC
	if _elapsed + 0.000001 < delay:
		return 0
	_elapsed = 0.0
	_repeating = true
	return direction
