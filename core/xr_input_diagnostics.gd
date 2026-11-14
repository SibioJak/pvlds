class_name XrInputDiagnostics
extends RefCounted

## Small local trace, shared across manual boots and watchdog returns.
## No config, credentials, or game data is recorded. Log changes and a
## ten-second heartbeat so a motionless ray still leaves usable facts.
const LOG_PATH: String = "user://pvlds_xr_input.log"
const MAX_LOG_BYTES: int = 1024 * 1024

var log_path: String = LOG_PATH
var _last_snapshot: String = ""
var _last_log_msec: int = -1
var _header_written: bool = false


func record_event(event: String, fields: Dictionary) -> void:
	var record: Dictionary = fields.duplicate(true)
	record["event"] = event
	record["pid"] = OS.get_process_id()
	record["time"] = Time.get_datetime_string_from_system()
	record["uptime_ms"] = Time.get_ticks_msec()
	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file != null and file.get_length() >= MAX_LOG_BYTES:
		file.close()
		var previous: String = log_path + ".previous"
		if FileAccess.file_exists(previous):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(previous))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(log_path), ProjectSettings.globalize_path(previous))
		file = null
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(record))
		file.close()


func observe(controllers: Array[XRController3D], selected: XRController3D, desktop_focus: bool) -> void:
	var interface: XRInterface = XRServer.find_interface("OpenXR")
	if not _header_written:
		_header_written = true
		var contract: WatchdogContract = WatchdogContract.load_from_disk()
		record_event("launcher_xr_input", {"build": "both-hands-3", "godot": Engine.get_version_info().get("string", ""),
			"session_id": contract.session_id, "session_state": contract.session_state,
			"runtime": interface.call("get_system_info") if interface != null and interface.has_method("get_system_info") else {}})
	var snapshot: Dictionary = {"initialized": interface != null and interface.is_initialized(),
		"session_state": int(interface.call("get_session_state")) if interface != null and interface.has_method("get_session_state") else -1,
		"desktop_focus": desktop_focus, "selected_hand": str(selected.tracker) if selected != null else "", "hands": []}
	var pose_samples: Dictionary = {}
	var registered: Array[Dictionary] = []
	var trackers: Dictionary = XRServer.get_trackers(XRServer.TRACKER_CONTROLLER)
	for tracker_name: StringName in trackers:
		var tracker: XRPositionalTracker = trackers[tracker_name] as XRPositionalTracker
		registered.append({"name": str(tracker_name), "profile": tracker.get_tracker_profile() if tracker != null else ""})
	snapshot["registered_controllers"] = registered
	if interface != null and interface.has_method("get_action_sets"):
		var sets: Dictionary = {}
		for set_name: String in interface.call("get_action_sets"):
			sets[set_name] = interface.call("is_action_set_active", set_name)
		snapshot["action_sets"] = sets
	for ctrl: XRController3D in controllers:
		var tracker: XRPositionalTracker = XRServer.get_tracker(ctrl.tracker) as XRPositionalTracker
		var hand: Dictionary = {"hand": str(ctrl.tracker), "node_pose": str(ctrl.pose),
			"node_active": ctrl.get_is_active(), "node_tracking": ctrl.get_has_tracking_data(),
			"tracker_present": tracker != null, "profile": tracker.get_tracker_profile() if tracker != null else "", "poses": {}}
		if tracker != null:
			for pose_name: StringName in [&"aim", &"default", &"grip"]:
				var pose: XRPose = tracker.get_pose(pose_name)
				hand["poses"][str(pose_name)] = {"present": pose != null, "tracking": pose != null and pose.has_tracking_data}
				if pose != null:
					var transform: Transform3D = pose.transform
					var rotation: Quaternion = transform.basis.get_rotation_quaternion()
					pose_samples[str(ctrl.tracker) + "/" + str(pose_name)] = {
						"position": [transform.origin.x, transform.origin.y, transform.origin.z],
						"orientation": [rotation.x, rotation.y, rotation.z, rotation.w]}
		snapshot["hands"].append(hand)
	var signature: String = JSON.stringify(snapshot)
	var now: int = Time.get_ticks_msec()
	if signature != _last_snapshot or _last_log_msec < 0 or now - _last_log_msec >= 10000:
		var record: Dictionary = snapshot.duplicate(true)
		record["pose_samples"] = pose_samples
		record_event("xr_input", record)
		_last_snapshot = signature
		_last_log_msec = now
