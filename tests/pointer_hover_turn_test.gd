extends SceneTree

class FollowRoom extends RoomView:
	var turns: Array[int] = []

	# Capture navigation requests without starting unrelated art work.
	func _set_centre(index: int, snap: bool = false) -> void:
		_centre_index = index
		_swing_active = not snap
		turns.append(index)

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _ray(angle: float, shift: Vector3 = Vector3.ZERO, hand: String = "right_hand") -> Dictionary:
	return {"valid": true, "hand": hand, "origin": shift,
		"direction": Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))}


func _frames(room: FollowRoom, index: int, ray: Dictionary, count: int) -> void:
	room._rig._hover_ray = ray
	room._rig.hovered = room._panels[index] if index >= 0 else null
	for frame: int in range(count):
		room._follow_centre(0.05)


func _room() -> FollowRoom:
	var room: FollowRoom = FollowRoom.new()
	root.add_child(room)
	room.set_process(false)
	room._xr_enabled = true
	room._build_rigs()
	room._rig.set_process(false)
	room._columns = 3
	for i: int in range(9):
		var panel: ClickableQuad = ClickableQuad.new()
		room.add_child(panel)
		panel.action_id = "panel"
		panel.payload = str(i)
		room._panels.append(panel)
		var game: GameEntry = GameEntry.new()
		game.game_id = str(i)
		room._visible_games.append(game)
	room._focusables.assign(room._panels)
	room._centre_index = 0
	room._focused = room._panels[0]
	room._rig._hover_ray = _ray(0)
	room._follow_centre(0.0)
	return room


func _run() -> void:
	var room: FollowRoom = _room()
	_frames(room, 3, _ray(5), 7)
	_expect(room.turns.is_empty(), "crossing a card for 350ms does not turn the wall")
	_frames(room, 3, _ray(5), 1)
	_expect(room.turns == [3], "a deliberate 400ms hover turns once")
	_frames(room, 6, _ray(5), 20)
	_expect(room.turns == [3], "cards crossing the ray during rotation cannot retarget the wall")
	room._swing_active = false
	_frames(room, 6, _ray(5), 40)
	_expect(room.turns == [3], "a stationary ray cannot start another turn after rotation settles")
	_frames(room, -1, _ray(5), 10)
	_expect(room.turns == [3], "losing the ray hit does not jump back to stale gamepad focus")
	_frames(room, 6, _ray(5.5, Vector3(0.005, 0, 0)), 20)
	_expect(room.turns == [3], "small hand tremor does not rearm wall movement")
	_frames(room, 6, _ray(8), 8)
	_expect(room.turns == [3, 6], "a deliberate hand move and hover can turn to another card")
	room._swing_active = false
	room._move_focus(Vector2.RIGHT)
	room._follow_centre(0.01)
	_expect(room._focused == room._panels[3] and room.turns == [3, 6, 3], "explicit navigation stays immediate despite competing pointer hover")
	room._swing_active = false
	_frames(room, 6, _ray(8), 20)
	_expect(room.turns == [3, 6, 3], "resting pointer does not undo explicit navigation")
	room.queue_free()

	var jitter: FollowRoom = _room()
	for index: int in [3, 6, 3, 6, 3, 6]:
		_frames(jitter, index, _ray(5), 3)
	_expect(jitter.turns.is_empty(), "sweeping back and forth across cards never accumulates a dwell")
	_frames(jitter, 6, _ray(5), 5)
	_expect(jitter.turns == [6], "settling on a card completes only that card's dwell")
	jitter.queue_free()

	var blocked: FollowRoom = _room()
	_frames(blocked, 3, _ray(5), 6)
	blocked._setup_panel_up = true
	_frames(blocked, 3, _ray(5), 10)
	blocked._setup_panel_up = false
	_frames(blocked, 3, _ray(5), 10)
	_expect(blocked.turns.is_empty(), "modal panels cancel pending dwell and do not cause a surprise turn on close")
	_frames(blocked, 3, _ray(8), 8)
	_expect(blocked.turns == [3], "hover navigation resumes after a fresh deliberate point")
	blocked.queue_free()

	var intent: PointerHoverTurn = PointerHoverTurn.new()
	_expect(intent.observe(3, 0, 10.0, false, _ray(0)) == -1, "a frame hitch cannot count as a whole hover")
	intent.hold_until_moved(_ray(0))
	var turn: int = -1
	for frame: int in range(8):
		turn = intent.observe(3, 0, 0.05, false, _ray(0, Vector3(0.04, 0, 0)))
	_expect(turn == 3, "deliberate hand translation can rearm without a wrist rotation")
	for frame: int in range(8):
		turn = intent.observe(6, 3, 0.05, false, _ray(0, Vector3.ZERO, "left_hand"))
	_expect(turn == 6, "switching the pointing hand can start a deliberate hover")
	print("Pointer hover turn tests: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
