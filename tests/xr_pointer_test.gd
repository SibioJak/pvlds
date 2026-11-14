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
	_expect(rig._lasers[rig._controllers[0]].visible and rig._lasers[rig._controllers[1]].visible,
		"both tracked controllers show lasers simultaneously")
	_expect(rig._hand_dots[rig._controllers[0]].visible and rig._hand_dots[rig._controllers[1]].visible,
		"each hand shows its own hit marker")
	var selected: Array[ClickableQuad] = []
	rig.select_pressed.connect(func(quad: ClickableQuad) -> void: selected.append(quad))
	left.set_input(&"trigger_click", true)
	left.set_input(&"trigger_click", false)
	_expect(selected.size() == 1 and selected[0] == left_target, "left trigger selects the left ray's target while right is tracked")
	rig._process(0.0)
	_expect(rig.hovered == left_target, "left hand retains room hover after selecting")
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
	left_target.queue_free()
	right_target.queue_free()
	XRServer.remove_tracker(left)
	XRServer.remove_tracker(right)
	room.queue_free()
	print("XR pointer tests: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
