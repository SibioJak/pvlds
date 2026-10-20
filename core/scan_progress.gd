class_name ScanProgress
extends RefCounted

## Thread-safe progress counters for a library scan running on a
## WorkerThreadPool task. The worker reports; the main thread polls a
## snapshot (about once per frame) and paints it. Nothing here touches
## the UI, the scene tree, or table files.

var _mutex: Mutex = Mutex.new()
var _phase: String = "" ## "loading_db" | "collecting" | "matching" | "done"
var _folders_total: int = 0
var _folders_done: int = 0
var _files_found: int = 0
var _files_processed: int = 0


func begin(phase: String, folders_total: int) -> void:
	_mutex.lock()
	_phase = phase
	_folders_total = folders_total
	_folders_done = 0
	_files_found = 0
	_files_processed = 0
	_mutex.unlock()


func set_phase(phase: String) -> void:
	_mutex.lock()
	_phase = phase
	_mutex.unlock()


func report_collect(folders_done: int, files_found: int) -> void:
	_mutex.lock()
	_phase = "collecting"
	_folders_done = folders_done
	_files_found = files_found
	_mutex.unlock()


func report_match(files_processed: int) -> void:
	_mutex.lock()
	_phase = "matching"
	_files_processed = files_processed
	_mutex.unlock()


func finish() -> void:
	_mutex.lock()
	_phase = "done"
	_files_processed = _files_found
	_mutex.unlock()


func snapshot() -> Dictionary:
	_mutex.lock()
	var out: Dictionary = {
		"phase": _phase,
		"folders_total": _folders_total,
		"folders_done": _folders_done,
		"files_found": _files_found,
		"files_processed": _files_processed,
	}
	_mutex.unlock()
	return out
