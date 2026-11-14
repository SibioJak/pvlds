class_name PointerHoverTurn
extends RefCounted

## Hover navigation must distinguish a deliberate point from cards
## moving underneath a stationary ray during the wall's own rotation.
const DWELL_SEC: float = 0.4
const REARM_ANGLE_RAD: float = deg_to_rad(2.0)
const REARM_DISTANCE_M: float = 0.03
const MAX_FRAME_SEC: float = 0.1

var _candidate: int = -1
var _elapsed: float = 0.0
var _require_motion: bool = false
var _last_turn_ray: Dictionary = {}


func hold_until_moved(ray: Dictionary) -> void:
	_candidate = -1
	_elapsed = 0.0
	_require_motion = true
	_last_turn_ray = ray.duplicate()


func _moved(ray: Dictionary) -> bool:
	if not bool(_last_turn_ray.get("valid", false)):
		_last_turn_ray = ray.duplicate()
		return false
	if str(ray.get("hand", "")) != str(_last_turn_ray.get("hand", "")):
		return true
	var origin: Vector3 = ray.get("origin", Vector3.ZERO)
	var previous_origin: Vector3 = _last_turn_ray.get("origin", Vector3.ZERO)
	var direction: Vector3 = ray.get("direction", Vector3.FORWARD)
	var previous_direction: Vector3 = _last_turn_ray.get("direction", Vector3.FORWARD)
	return origin.distance_to(previous_origin) >= REARM_DISTANCE_M \
		or direction.angle_to(previous_direction) >= REARM_ANGLE_RAD


func observe(candidate: int, current: int, delta: float, travelling: bool, ray: Dictionary) -> int:
	if candidate < 0 or candidate == current or travelling or not bool(ray.get("valid", false)):
		_candidate = -1
		_elapsed = 0.0
		return -1
	if _require_motion:
		if not _moved(ray):
			_candidate = -1
			_elapsed = 0.0
			return -1
		_require_motion = false
	if candidate != _candidate:
		_candidate = candidate
		_elapsed = 0.0
	_elapsed += clampf(delta, 0.0, MAX_FRAME_SEC)
	if _elapsed + 0.000001 < DWELL_SEC:
		return -1
	hold_until_moved(ray)
	return candidate
