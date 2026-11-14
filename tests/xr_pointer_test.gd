extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _track(tracker: XRPositionalTracker, pose: StringName, position: Vector3) -> void:
	tracker.set_pose(pose, Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _run() -> void:
	# Model the actual OpenXR backend: its registered XRServer names
	# are left_hand/right_hand, not the OpenXR /user/hand/... paths.
	var left: XRControllerTracker = XRControllerTracker.new()
	left.name = &"left_hand"
	left.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	var right: XRControllerTracker = XRControllerTracker.new()
	right.name = &"right_hand"
	right.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	XRServer.add_tracker(left)
	XRServer.add_tracker(right)
	var room: RoomView = RoomView.new()
	root.add_child(room)
	room.set_process(false)
	room._build_rigs() # Exercise the real room's controller wiring.
	var rig: PointerRig = room._rig
	_expect(rig._controllers.size() == 2 and rig._controllers[0].tracker == &"left_hand"
		and rig._controllers[1].tracker == &"right_hand", "room binds the engine's registered controller names")
	_expect(XRServer.get_tracker(&"/user/hand/left") == null and XRServer.get_tracker(&"/user/hand/right") == null,
		"regression fixture: OpenXR user paths do not identify registered Godot trackers")
	_expect(rig._tracked_controller() == null, "no laser before either controller has tracking")
	_track(left, &"default", Vector3(1, 2, 3))
	_track(right, &"default", Vector3(4, 5, 6))
	var chosen: XRController3D = rig._tracked_controller()
	_expect(chosen != null and chosen.tracker == right.name, "tracked right hand is preferred")
	rig._controllers.reverse()
	chosen = rig._tracked_controller()
	_expect(chosen != null and chosen.tracker == right.name, "right-hand preference is independent of controller enumeration order")
	rig._controllers.reverse()
	rig._controllers[0].tracker = &"/user/hand/left"
	rig._controllers[1].tracker = &"/user/hand/right"
	_expect(rig._tracked_controller() == null, "old OpenXR-path bindings reproduce both missing controller lookups")
	rig._controllers[0].tracker = &"left_hand"
	rig._controllers[1].tracker = &"right_hand"
	_expect(rig._tracked_controller() != null, "correct Godot tracker bindings recover the pointer immediately")
	right.invalidate_pose(&"default")
	_expect(rig._controllers[1].get_is_active(), "regression fixture: lost pose still reports active")
	_expect(not rig._controllers[1].get_has_tracking_data(), "regression fixture: right pose has lost tracking")
	chosen = rig._tracked_controller()
	_expect(chosen != null and chosen.tracker == left.name, "untracked right hand does not mask tracked left hand")
	_track(right, &"aim", Vector3(7, 8, 9))
	chosen = rig._tracked_controller()
	_expect(chosen != null and chosen.tracker == right.name and chosen.pose == &"aim", "returning right hand uses tracked aim even with stale default pose")
	_expect(chosen != null and chosen.global_position.is_equal_approx(Vector3(7, 8, 9)), "laser origin follows the recovered aim pose")
	_track(right, &"default", Vector3.ZERO)
	_expect(PointerRig.tracked_pose_name(right) == &"aim", "aim is preferred to default when both are tracked")
	right.invalidate_pose(&"aim")
	right.invalidate_pose(&"default")
	_track(right, &"grip", Vector3.ZERO)
	_expect(PointerRig.tracked_pose_name(right) == &"grip", "grip is usable when aim and default lack tracking")
	left.invalidate_pose(&"default")
	right.invalidate_pose(&"grip")
	_expect(rig._tracked_controller() == null, "both untracked hands clear the laser")
	_track(left, &"aim", Vector3(2, 3, 4))
	_expect(rig._tracked_controller() == rig._controllers[0], "controller tracking recovers without restarting the room")
	XRServer.remove_tracker(left)
	_expect(rig._tracked_controller() == null, "removed trackers are not selected")
	XRServer.add_tracker(left)
	_expect(rig._tracked_controller() == rig._controllers[0], "reconnected controller is usable without rebuilding the room")
	var presses: Array[int] = [0]
	rig.select_pressed.connect(func(_quad: ClickableQuad) -> void: presses[0] += 1)
	left.set_input(&"trigger_click", true)
	left.set_input(&"trigger_click", false)
	_expect(presses[0] == 1, "trigger selection still reaches the room after tracker reconnection")
	var diagnostics: XrInputDiagnostics = XrInputDiagnostics.new()
	diagnostics.log_path = "res://watchdog/build/test-xr-input.log"
	if FileAccess.file_exists(diagnostics.log_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(diagnostics.log_path))
	diagnostics.observe(rig._controllers, rig._controllers[0], false)
	diagnostics.observe(rig._controllers, rig._controllers[0], false)
	var lines: PackedStringArray = FileAccess.get_file_as_string(diagnostics.log_path).strip_edges().split("\n")
	_expect(lines.size() == 2, "diagnostic writes a boot header and one snapshot, suppressing identical frames")
	var snapshot: Dictionary = JSON.parse_string(lines[-1])
	_expect(snapshot.get("event") == "xr_input" and snapshot.get("hands", []).size() == 2, "diagnostic records both hands")
	_expect(str(snapshot.get("selected_hand")) == str(left.name), "diagnostic identifies the hand owning the laser")
	_expect(snapshot.get("registered_controllers", []).size() == 2, "diagnostic lists actual registered controller names")
	# Both hands must work together. Use real collision targets so a
	# left trigger cannot accidentally pass by selecting right's hover.
	rig.select_pressed.disconnect(room._on_select)
	rig.hover_changed.disconnect(room._on_hover_changed)
	rig._xr_diagnostic.log_path = diagnostics.log_path + ".hands"
	var left_target: ClickableQuad = ClickableQuad.new()
	root.add_child(left_target)
	left_target.setup("left_target", "", null, Vector2(0.8, 0.8))
	left_target.position = Vector3(-1, 1, -3)
	var right_target: ClickableQuad = ClickableQuad.new()
	root.add_child(right_target)
	right_target.setup("right_target", "", null, Vector2(0.8, 0.8))
	right_target.position = Vector3(1, 1, -3)
	_track(left, &"aim", Vector3(-1, 1, 0))
	_track(right, &"aim", Vector3(1, 1, 0))
	rig.xr_active = true
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame
	rig._process(0.0)
	_expect(str(rig.hover_ray_sample().get("hand", "")) == "right_hand",
		"hover ray records the hand actually owning room hover")
	_expect(rig._lasers[rig._controllers[0]].visible and rig._lasers[rig._controllers[1]].visible,
		"both tracked controllers show lasers simultaneously")
	_expect(rig._hand_dots[rig._controllers[0]].visible and rig._hand_dots[rig._controllers[1]].visible,
		"each hand shows its own hit marker")
	var selected: Array[ClickableQuad] = []
	rig.select_pressed.connect(func(quad: ClickableQuad) -> void: selected.append(quad))
	left.set_input(&"trigger_click", true)
	left.set_input(&"trigger_click", false)
	_expect(selected.size() == 1 and selected[0] == left_target, "left trigger selects the left ray's target while right is tracked")
	_expect(str(rig.hover_ray_sample().get("hand", "")) == "left_hand"
		and (rig.hover_ray_sample().get("origin", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(-1, 1, 0)),
		"a left-hand selection updates the hover ray immediately")
	rig._process(0.0)
	_expect(rig.hovered == left_target, "left hand retains room hover after selecting")
	var edge_samples: Array[Dictionary] = rig.edge_scroll_samples(room._xr_camera, 3.6)
	_expect(edge_samples.size() == 2 and edge_samples[0]["source"] == "left_hand"
		and edge_samples[1]["source"] == "right_hand", "edge scrolling samples both tracked hands")
	_expect(rig.hovered == left_target and rig._active_controller == rig._controllers[0]
		and rig.hover_ray_sample()["hand"] == "left_hand", "sampling both edges preserves hover and click ownership")
	right.set_input(&"trigger_click", true)
	right.set_input(&"trigger_click", false)
	_expect(selected.size() == 2 and selected[1] == right_target, "right trigger selects its own target after a left-hand selection")
	left.invalidate_pose(&"aim")
	rig._process(0.0)
	_expect(not rig._lasers[rig._controllers[0]].visible and rig._lasers[rig._controllers[1]].visible,
		"losing one hand hides only that hand's laser")
	left.set_input(&"trigger_click", true)
	left.set_input(&"trigger_click", false)
	_expect(selected.size() == 2, "untracked hand cannot select the other hand's target")
	_track(left, &"aim", Vector3(-1, 1, 0))
	rig._process(0.0)
	_expect(rig._lasers[rig._controllers[0]].visible and rig._lasers[rig._controllers[1]].visible,
		"left laser returns alongside right after tracking resumes")
	left.set_input(&"trigger_click", true)
	left.set_input(&"trigger_click", false)
	_expect(selected.size() == 3 and selected[2] == left_target, "left-hand selection recovers without restarting")
	var hover_changes: Array[int] = [0]
	rig.hover_changed.connect(func(_quad: ClickableQuad) -> void: hover_changes[0] += 1)
	for side: int in [-1, 1]:
		var tracker: XRControllerTracker = left if side < 0 else right
		var ctrl: XRController3D = rig._controllers[0] if side < 0 else rig._controllers[1]
		var target: ClickableQuad = left_target if side < 0 else right_target
		rig._active_controller = ctrl
		_track(tracker, &"aim", Vector3(side, 1, 0))
		rig._process(0.0)
		hover_changes[0] = 0
		for sample: int in range(20):
			var offset: float = 0.01 if sample % 2 == 0 else -0.005
			_track(tracker, &"aim", Vector3(side * (1.4 + offset), 1, 0))
			rig._process(0.0)
			_expect(rig.hovered == target, "hover is stable across outer edge samples (side %d)" % side)
		_expect(hover_changes[0] == 0, "outer-edge hit/miss does not repeatedly toggle hover (side %d)" % side)
		_track(tracker, &"aim", Vector3(side * 1.41, 1, 0))
		rig._process(0.0)
		_expect(rig._pick_controller(ctrl)["quad"] == null and not rig.hover_ray_sample()["target_valid"],
			"expanded hover border is excluded from real selection/navigation hits")
		tracker.set_input(&"trigger_click", true)
		tracker.set_input(&"trigger_click", false)
		_expect(selected[-1] == null, "VR trigger outside actual card does not select its retained hover")
		_track(tracker, &"aim", Vector3(side * 1.48, 1, 0))
		rig._process(0.0)
		_expect(rig.hovered == null, "moving beyond the edge margin releases hover")
		_track(tracker, &"aim", Vector3(side, 1, 0))
		rig._process(0.0)
		target.pick_enabled = false
		rig._process(0.0)
		_expect(rig.hovered == null, "disabled cards release retained hover")
		target.pick_enabled = true
	# Exercise the desktop _process and click path too. Orthographic
	# camera translation places the actual mouse ray on each boundary
	# without relying on OS mouse warping in a headless test.
	rig.xr_active = false
	var camera: Camera3D = room._desk_camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.global_rotation = Vector3.ZERO
	var mouse: Vector2 = root.get_mouse_position()
	for side: int in [-1, 1]:
		var target: ClickableQuad = left_target if side < 0 else right_target
		camera.global_position += Vector3(side, 1, 0) - camera.project_ray_origin(mouse)
		rig._process(0.0)
		_expect(rig.hovered == target, "desktop ray initially acquires the edge card")
		edge_samples = rig.edge_scroll_samples(camera, 3.6)
		_expect(edge_samples.size() == 1 and edge_samples[0]["source"] == "mouse"
			and rig.hovered == target, "desktop edge sampling preserves card hover")
		hover_changes[0] = 0
		for sample: int in range(20):
			var offset: float = 0.01 if sample % 2 == 0 else -0.005
			camera.global_position += Vector3(side * (1.4 + offset), 1, 0) - camera.project_ray_origin(mouse)
			rig._process(0.0)
			_expect(rig.hovered == target, "desktop outer-edge hover stays stable")
		_expect(hover_changes[0] == 0, "desktop outer edge does not flicker hover state")
		camera.global_position += Vector3(side * 1.41, 1, 0) - camera.project_ray_origin(mouse)
		rig._process(0.0)
		_expect(not rig.hover_ray_sample()["target_valid"], "desktop border retention remains separate from exact card hits")
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		rig._unhandled_input(click)
		_expect(selected[-1] == null, "desktop click outside actual card cannot select retained hover")
		camera.global_position += Vector3(side * 1.48, 1, 0) - camera.project_ray_origin(mouse)
		rig._process(0.0)
		_expect(rig.hovered == null, "desktop hover releases beyond the outer margin")
	var old_transform: Transform3D = right_target.transform
	right_target.rotation.y = deg_to_rad(25.0)
	right_target.scale = Vector3.ONE * 1.08
	var angled_origin: Vector3 = right_target.to_global(Vector3(0.41, 0, 3))
	var angled_direction: Vector3 = -right_target.global_basis.z.normalized()
	var miss: Dictionary = {"quad": null, "position": angled_origin + angled_direction * 8.0}
	_expect(PointerRig.stable_hover_hit(angled_origin, angled_direction, miss, {"quad": right_target})["quad"] == right_target,
		"edge tolerance follows an angled and popped card's local geometry")
	right_target.visible = false
	_expect(PointerRig.stable_hover_hit(angled_origin, angled_direction, miss, {"quad": right_target})["quad"] == null,
		"hidden card cannot retain hover")
	right_target.visible = true
	right_target.transform = old_transform
	left_target.queue_free()
	right_target.queue_free()
	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	room.queue_free()
	print("XR pointer tests: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
