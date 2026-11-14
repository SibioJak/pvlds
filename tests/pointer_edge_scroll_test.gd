extends SceneTree

class EdgeRoom extends RoomView:
	var samples: Array[Dictionary] = []
	# Exercise the actual centre and spring, without unrelated art work.
	func _refresh_window() -> void:
		pass
	func _request_window_fill() -> void:
		pass
	func _heal_panel_faces() -> void:
		pass
	func _heal_tournament_boards() -> void:
		pass
	func _edge_pointer_samples() -> Array[Dictionary]:
		return samples

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _sample(x: float, source: String = "mouse", valid: bool = true) -> Dictionary:
	return {"source": source, "valid": valid, "x": x}


func _room(xr: bool, count: int = 30) -> EdgeRoom:
	var room: EdgeRoom = EdgeRoom.new()
	root.add_child(room)
	room.set_process(false)
	room._xr_enabled = xr
	room._build_rigs()
	room._rig.set_process(false)
	room._wall = Node3D.new()
	room.add_child(room._wall)
	room._columns = int(ceil(float(count) / 3.0))
	for i: int in range(count):
		var panel: ClickableQuad = ClickableQuad.new()
		room.add_child(panel)
		room._panels.append(panel)
		room._visible_games.append(GameEntry.new())
	room._focusables.assign(room._panels)
	room._set_centre(4 if count > 4 else 0, true)
	return room


func _tick(room: EdgeRoom, frames: int) -> void:
	for frame: int in range(frames):
		room._step_rest_timer = maxf(0.0, room._step_rest_timer - 1.0 / 90.0)
		room._follow_centre(1.0 / 90.0)
		room._update_swing(1.0 / 90.0)


func _run() -> void:
	var viewport: Rect2 = Rect2(0, 0, 1000, 600)
	_expect(absf(PointerEdgeScroll.mouse_sample(Vector2(500, 300), viewport)["x"]) < 0.001, "mouse centre is neutral")
	_expect(PointerEdgeScroll.mouse_sample(Vector2(950, 300), viewport)["x"] > 1.0, "right viewport edge activates without a card hit")
	_expect(PointerEdgeScroll.mouse_sample(Vector2(50, 300), viewport)["x"] < -1.0, "left viewport edge activates")
	_expect(not PointerEdgeScroll.mouse_sample(Vector2(50, 590), viewport)["valid"], "bottom control strip does not scroll")
	_expect(not PointerEdgeScroll.mouse_sample(Vector2(-1, 300), viewport)["valid"], "leaving the window stops scrolling")
	var right_ray: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-40))
	var vr: Dictionary = PointerEdgeScroll.vr_sample("right_hand", Transform3D.IDENTITY, Vector3.ZERO, right_ray, 3.6)
	_expect(vr["valid"] and vr["x"] > 1.0, "VR right edge uses the ray's view-relative position")
	var camera: Transform3D = Transform3D(Basis(Vector3.UP, 0.8), Vector3(2, 1, -3))
	var rotated: Dictionary = PointerEdgeScroll.vr_sample("right_hand", camera, camera.origin, camera.basis * right_ray, 3.6)
	_expect(is_equal_approx(vr["x"], rotated["x"]), "VR edge zones follow the head, not world or wall rotation")
	_expect(not PointerEdgeScroll.vr_sample("left_hand", Transform3D.IDENTITY, Vector3.ZERO, Vector3.BACK, 3.6)["valid"], "backwards rays cannot scroll")
	var policy: PointerEdgeScroll = PointerEdgeScroll.new()
	for frame: int in range(4):
		_expect(policy.observe([_sample(1.2)], true, true, 0.05, false) == 0, "brief edge crossings do not scroll")
	_expect(policy.observe([_sample(1.2)], true, true, 0.05, false) == 1, "holding an edge begins scrolling")
	for frame: int in range(20):
		_expect(policy.observe([_sample(1.2)], true, true, 0.05, true) == 0, "in-flight steps are not retargeted")
	var repeated: int = 0
	for frame: int in range(3):
		repeated = policy.observe([_sample(1.2)], true, true, 0.05, false)
	_expect(repeated == 1, "a stationary edge pointer keeps scrolling after a step settles")
	_expect(policy.observe([_sample(0.0)], true, true, 1.0, false) == 0, "returning to the middle stops scrolling immediately")
	for frame: int in range(20):
		_expect(policy.observe([_sample(1.2)], true, false, 0.05, false) == 0, "right endpoint blocks all outward steps")
	for frame: int in range(20):
		_expect(policy.observe([_sample(-1.2)], false, true, 0.05, false) == 0, "left endpoint blocks all outward steps")
	for frame: int in range(20):
		_expect(policy.observe([_sample(-1.2, "left_hand"), _sample(1.2, "right_hand")], true, true, 0.05, false) == 0,
			"opposing controller edges cannot fight over the wall")
	policy.reset()
	for frame: int in range(4):
		policy.observe([_sample(1.02)], true, true, 0.05, false)
	_expect(policy.observe([_sample(0.98)], true, true, 0.05, false) == 1, "edge-zone hysteresis absorbs boundary tremor")
	_expect(policy.observe([_sample(0.8)], true, true, 1.0, false) == 0, "leaving the edge release zone stops scrolling")
	for side: int in [-1, 1]:
		policy.reset()
		var hand_step: int = 0
		for frame: int in range(5):
			hand_step = policy.observe([_sample(side * 1.2, "left_hand"), _sample(0, "right_hand")], true, true, 0.05, false)
		_expect(hand_step == side, "left hand can scroll with right hand pointing at the middle")

	for xr: bool in [false, true]:
		var room: EdgeRoom = _room(xr)
		var initial: int = room._centre_index
		room.samples = [_sample(0.0, "right_hand" if xr else "mouse")]
		# The real card material and pop spring must follow hover,
		# not merely PointerRig's internal hover reference.
		for index: int in range(room._panels.size()):
			var panel: ClickableQuad = room._panels[index]
			panel.setup("panel", str(index), null, Vector2(0.8, 0.8))
			panel.position = Vector3(index, 1, -3)
			room._panel_frames.append(room._make_card_quad(panel, Vector2(0.85, 0.85), Vector3(0, 0, -0.007), room._frame_mat(false)))
			room._panel_base_pos.append(panel.position)
			room._panel_pop_dir.append(Vector3.BACK)
			room._panel_pop.append(0.0)
			room._panel_pop_applied.append(0.0)
		room._focused = room._panels[initial]
		room._pointer_follow_focus = room._focused
		for hovered_index: int in [0, 11, 2]:
			room._rig._set_hovered(room._panels[hovered_index])
			for frame: int in range(180):
				room._update_pop(1.0 / 90.0)
			_expect(room.pop_target() == room._panels[hovered_index], "raised card follows pointer away from centre (XR=%s)" % xr)
			for index: int in range(room._panels.size()):
				_expect(room._panel_frames[index].material_override == room._frame_mat(index == hovered_index),
					"only hovered card wears amber (XR=%s, card=%d)" % [xr, index])
				_expect(is_equal_approx(room._panel_pop[index], 1.0 if index == hovered_index else 0.0),
					"pop transfers to hovered card (XR=%s, card=%d)" % [xr, index])
			_expect(room._centre_index == initial and not room._swing_active, "visual hover never rotates wall")
		room._rig._set_hovered(null)
		_expect(room.pop_target() == room._panels[initial], "pointer miss retains centred selection for pad navigation")
		for frame: int in range(180):
			room._rig.hovered = room._panels[11] if frame % 2 == 0 else room._panels[0]
			_tick(room, 1)
		_expect(room._centre_index == initial, "card hover never scrolls a central pointer (XR=%s)" % xr)
		room._rig.hovered = null
		room.samples = [_sample(1.2, "left_hand" if xr else "mouse")]
		_tick(room, 900)
		_expect(room._grid_coord(room._centre_index).x == room._columns - 1,
			"holding right edge with no highlighted card reaches the last column (XR=%s)" % xr)
		var end_yaw: float = room._drum_yaw
		_tick(room, 300)
		_expect(is_equal_approx(room._drum_yaw, end_yaw) and not room._swing_active,
			"right endpoint remains physically stationary (XR=%s)" % xr)
		room.samples = [_sample(-1.2)]
		_tick(room, 1200)
		_expect(room._grid_coord(room._centre_index).x == 0 and not room._swing_active,
			"holding left edge reaches and stops at the first column (XR=%s)" % xr)
		room.samples = [_sample(1.2)]
		room._setup_panel_up = true
		_tick(room, 120)
		_expect(room._grid_coord(room._centre_index).x == 0, "setup panel prevents edge scrolling")
		room._setup_panel_up = false
		room._focused = room._panels[6]
		room.samples = [_sample(0)]
		_tick(room, 1)
		_expect(room._centre_index == 6, "explicit focus navigation remains immediate")
		room.queue_free()
	var stopping: EdgeRoom = _room(false, 30)
	stopping.samples = [_sample(1.2)]
	_tick(stopping, 30)
	var last_step: int = stopping._centre_index
	_expect(last_step > 4, "edge entry starts a real wall step")
	stopping.samples = [_sample(0)]
	_tick(stopping, 600)
	_expect(stopping._centre_index == last_step and not stopping._swing_active,
		"leaving an edge finishes only the current step, with no further scrolling")
	stopping.queue_free()
	# Every single-page size stays geometrically centred, even when
	# restoring the final card or moving focus across the page.
	for xr: bool in [false, true]:
		for count: int in range(1, RoomView.PAGE_SIZE + 1):
			var small: EdgeRoom = _room(xr, count)
			var centred_yaw: float = deg_to_rad(float(small._columns - 1) * 0.5 * RoomView.ANGLE_STEP_DEG)
			for selection: int in [count - 1, 0, count / 2]:
				small._set_centre(selection, true)
				_expect(is_equal_approx(small._drum_yaw, centred_yaw), "small library restore centres all columns (XR=%s, count=%d)" % [xr, count])
				var left: Vector3 = small._wall.basis * (small._card_transform_at(0, 1).origin - RoomView.EYE - Vector3(0, RoomView.WALL_LIFT, 0))
				var right: Vector3 = small._wall.basis * (small._card_transform_at(small._columns - 1, 1).origin - RoomView.EYE - Vector3(0, RoomView.WALL_LIFT, 0))
				_expect(is_zero_approx(atan2(left.x, -left.z) + atan2(right.x, -right.z)), "small library outer cards are symmetric around view centre")
				small._focused = small._panels[(selection + 1) % count]
				small._pointer_follow_focus = null
				_tick(small, 120)
				_expect(is_equal_approx(small._drum_yaw, centred_yaw) and not small._swing_active, "small library focus changes preserve centring")
			for side: int in [-1, 1]:
				small.samples = [_sample(side * 1.2)]
				_tick(small, 300)
				_expect(small._edge_scroll_target(side) == -1 and is_equal_approx(small._drum_yaw, centred_yaw) and not small._swing_active,
					"single-page library ignores edge scrolling (XR=%s, count=%d)" % [xr, count])
			small.queue_free()
	var partial: EdgeRoom = _room(false, 13)
	_expect(partial._edge_scroll_target(1) == 7, "multi-page library still advances to the next column")
	partial._set_centre(10, true)
	_expect(partial._edge_scroll_target(1) == 12, "partial final column preserves a valid game index")
	partial._set_centre(12, true)
	_expect(partial._edge_scroll_target(1) == -1, "partial final column has no outward target")
	partial.queue_free()
	var single: EdgeRoom = _room(false, 1)
	_expect(single._edge_scroll_target(-1) == -1 and single._edge_scroll_target(1) == -1, "one-column library never scrolls")
	single.queue_free()
	var tournament: EdgeRoom = _room(false, 4)
	tournament._tournament = true
	tournament._tournament_rows = [{"kind": "challenge"}, {"kind": "challenge"}, {"kind": "challenge"}, {"kind": "challenge"}]
	tournament._columns = 8
	tournament._centre_index = 0
	_expect(tournament._edge_scroll_target(1) == 2, "tournament scrolling skips empty companion-board columns")
	_expect(tournament._edge_scroll_target(-1) == -1, "tournament first card column is a hard stop")
	tournament._centre_index = 2
	_expect(tournament._edge_scroll_target(1) == -1 and tournament._edge_scroll_target(-1) == 0, "tournament last card column is a hard stop")
	tournament.queue_free()
	print("Pointer edge scroll tests: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
