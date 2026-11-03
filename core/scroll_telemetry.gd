class_name ScrollTelemetry
extends RefCounted

## Scroll telemetry (first built as the diagnostic build's
## witness on branch diag/scroll-telemetry; ported into
## GRADFIX16 so the shipped build produces the same log):
## an observation-only JSONL logger
## for the wall-motion investigation. It is written to by
## RoomView at the product's own poll cadence, at cruise
## state transitions, per rendered frame while the drum is
## moving, and when the wall-motion dial changes. It never
## reads input, never touches scroll state, and returns no
## value any product decision can consume - deleting every
## call site restores the shipped build byte for byte in
## behaviour. Records are buffered in memory and flushed in
## small batches (every FLUSH_LINES records or
## FLUSH_INTERVAL_MSEC, whichever comes first), so a crash
## loses at most the last fraction of a second and the
## logging itself never does file work per frame.

const LOG_PATH: String = "user://scroll_telemetry.jsonl"
const BUILD_STAMP: String = "PVLDS-OPTIMIZE"
const BASE_COMMIT: String = "629f8b5"
const FLUSH_LINES: int = 64
const FLUSH_INTERVAL_MSEC: int = 250

var _file: FileAccess = null
var _pending: Array[String] = []
var _seq: int = 0
var _boot_msec: int = 0
var _last_flush_msec: int = 0
var _flush_count: int = 0
var _bytes_written: int = 0
var _work_usec_total: int = 0 ## the logger's own measured cost (JSON + buffering + file writes), reported in the footer


static func _sanitize(value: Variant) -> Variant:
	# Floats are rounded to six decimals so the file stays
	# readable at poll cadence; six decimals is far below
	# the stick's own resolution and changes no evidence.
	if value is float:
		var f: float = value
		if absf(f) < 0.0000005:
			return 0.0
		return snappedf(f, 0.000001)
	if value is Dictionary:
		var src: Dictionary = value
		var out: Dictionary = {}
		for key: Variant in src.keys():
			out[key] = _sanitize(src[key])
		return out
	if value is Array:
		var arr: Array = value
		var out_arr: Array = []
		for item: Variant in arr:
			out_arr.append(_sanitize(item))
		return out_arr
	return value


func is_active() -> bool:
	return _file != null


func start(fields: Dictionary) -> bool:
	if _file != null:
		return true
	_boot_msec = Time.get_ticks_msec()
	_last_flush_msec = _boot_msec
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		return false
	var line: String = JSON.stringify(_make_record("header", fields))
	_file.store_line(line)
	_file.flush()
	_bytes_written += line.length() + 1
	_flush_count += 1
	return true


func record(kind: String, fields: Dictionary) -> void:
	if _file == null:
		return
	var t0: int = Time.get_ticks_usec()
	_pending.append(JSON.stringify(_make_record(kind, fields)))
	if _pending.size() >= FLUSH_LINES or Time.get_ticks_msec() - _last_flush_msec >= FLUSH_INTERVAL_MSEC:
		flush_pending()
	_work_usec_total += Time.get_ticks_usec() - t0


func flush_pending() -> void:
	if _file == null or _pending.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	for line: String in _pending:
		_file.store_line(line)
		_bytes_written += line.length() + 1
	_file.flush()
	_pending.clear()
	_flush_count += 1
	_last_flush_msec = Time.get_ticks_msec()
	_work_usec_total += Time.get_ticks_usec() - t0


func close() -> void:
	if _file == null:
		return
	flush_pending()
	var footer: Dictionary = {
		"records_written": _seq,
		"flushes": _flush_count,
		"bytes_written_before_footer": _bytes_written,
		"logger_self_time_ms_before_footer": float(_work_usec_total) / 1000.0,
	}
	var line: String = JSON.stringify(_make_record("footer", footer))
	_file.store_line(line)
	_file.flush()
	_file.close()
	_file = null


func _make_record(kind: String, fields: Dictionary) -> Dictionary:
	var rec: Dictionary = {}
	rec["seq"] = _seq
	_seq += 1
	rec["t_ms"] = Time.get_ticks_msec() - _boot_msec
	rec["kind"] = kind
	var clean: Dictionary = _sanitize(fields) as Dictionary
	for key: Variant in clean.keys():
		rec[key] = clean[key]
	return rec
