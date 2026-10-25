class_name VpsDownloader
extends Node

## The VPS database download, as one shared service: fetch
## VpsDatabase.DOWNLOAD_URL, sanity-check what arrived (the real
## vpsdb.json is a multi-MB top-level JSON array), and store it
## as the downloaded cache a later scan picks up through
## VpsDatabase.resolve_path - the catalog-freshness path both
## surfaces rely on: the cache on disk is the database the next
## scan resolves to, ahead of the bundled sample.
##
## Extracted from the desk pass (2026-10-25) when the room's
## SETUP panel needed the same download: one implementation, two
## drivers. The desk pass and the panel each own an instance
## (only one surface is ever live at a time) and word the
## success tail for their own surface ("next Save & Scan" on
## the desk, "next scan" in the room), so finished() carries
## the bare fact. Progress and failure texts are the desk's
## original words, kept verbatim - both surfaces speak them
## unchanged.

signal progress(text: String)
signal finished(ok: bool, message: String, downloaded_path: String)

const PARTIAL_PATH: String = "user://vpsdb_download.partial"

var _http: HTTPRequest
var _downloading: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 180.0
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func is_downloading() -> bool:
	return _downloading


## Where the download comes from: the real VPS database, unless
## the PVLDS_VPSDB_URL dev seam overrides it (the harness serves
## a stub database over local HTTP so the panel smoke's
## download leg never touches the network).
func download_url() -> String:
	var override: String = OS.get_environment("PVLDS_VPSDB_URL")
	if override != "":
		return override
	return VpsDatabase.DOWNLOAD_URL


## Start the fetch. False when one is already running, or when
## the request could not even start - that failure also arrives
## on finished, synchronously, before this returns false.
func start_download() -> bool:
	if _downloading:
		return false
	_downloading = true
	_http.download_file = PARTIAL_PATH
	var err: Error = _http.request(download_url())
	if err != OK:
		_fail("Could not start the download (error %d)." % err)
		return false
	return true


func _process(_delta: float) -> void:
	if not _downloading or _http == null:
		return
	var total: int = _http.get_body_size()
	var got: int = _http.get_downloaded_bytes()
	if total > 0:
		progress.emit("Downloading VPS database... %d%% (%.1f of %.1f MB)" % [
			int(100.0 * float(got) / float(total)), float(got) / 1048576.0, float(total) / 1048576.0])
	else:
		progress.emit("Downloading VPS database... %.1f MB so far" % (float(got) / 1048576.0))


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail("Download failed (result %d, HTTP %d). Check the connection and try again." % [result, response_code])
		return
	# Sanity-check the payload before it becomes the cached database:
	# the real vpsdb.json is a multi-MB top-level JSON array.
	var f: FileAccess = FileAccess.open(PARTIAL_PATH, FileAccess.READ)
	if f == null:
		_fail("Download finished but the file could not be read back.")
		return
	var size: int = int(f.get_length())
	var head: PackedByteArray = f.get_buffer(mini(256, size))
	f.close()
	var head_text: String = head.get_string_from_utf8().strip_edges()
	if size < 1000000 or not head_text.begins_with("["):
		_fail("What arrived does not look like the VPS database - cache not updated.")
		return
	var cache_abs: String = ProjectSettings.globalize_path(VpsDatabase.CACHE_PATH)
	if FileAccess.file_exists(VpsDatabase.CACHE_PATH):
		DirAccess.remove_absolute(cache_abs)
	var err: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(PARTIAL_PATH), cache_abs)
	if err != OK:
		_fail("Could not store the downloaded database (error %d)." % err)
		return
	_downloading = false
	finished.emit(true, "VPS database downloaded (%.1f MB)." % (float(size) / 1048576.0), cache_abs)


func _fail(message: String) -> void:
	_downloading = false
	if FileAccess.file_exists(PARTIAL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PARTIAL_PATH))
	finished.emit(false, message, "")
