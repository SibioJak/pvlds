class_name VpxIdentity
extends RefCounted

## FIX125 (ROM witness): a .vpx file's OWN identity, read from
## inside the file - the evidence a misleading file name cannot
## fake. Two facts:
##
## - "rom": the ROM name the table's script declares. VPX
##   stores the script in the GameData stream (a BIFF stream;
##   the script rides as its CODE object, plain text bytes),
##   and a VPinMAME table names its ROM in the script -
##   canonically `Const cGameName = "smanve_101"`. The reader
##   scans the stream for that declaration (a direct
##   `.GameName = "..."` assignment is the fallback shape).
##   Several DISTINCT declared ROMs read as no ROM at all: a
##   script that offers a choice of ROMs declares no single
##   identity, and the witness must not pick one for it.
##   The scan is byte-level, over the stream's hex encoding:
##   GameData is binary BIFF around the script text, and a
##   whole-stream string decode dies at the first NUL or
##   invalid byte (measured on a synthetic fixture: both
##   decoders returned a 5-character string for a 206-byte
##   stream) - the declaration would be invisible exactly
##   where it matters. Hex has no NULs and no invalid
##   bytes, and each ASCII letter has exactly two hex
##   spellings, so case-insensitivity is an alternation.
## - "table_name": the internal table name (the TableInfo
##   storage's TableName stream, raw UTF-16 text) - the
##   fallback witness for tables that declare no ROM
##   (originals, EM recreations).
##
## Read-only and fail-soft, like the art path that shares the
## CfbReader: an unreadable or non-compound file, a missing
## stream, an oversized GameData - all read as an empty
## identity, never an error. The scan consults this ONLY for
## contested claims (see LibraryScanner._rom_witness); it is
## not a per-file cost.

const MAX_GAMEDATA_BYTES: int = 64 * 1024 * 1024 ## a real GameData stream is a few MB at most; a bigger claim is a corrupt size field, refused like the art reader refuses it
const MAX_TABLENAME_BYTES: int = 64 * 1024

static var _cgamename_re: RegEx = null
static var _gamename_re: RegEx = null

## One ASCII letter as a hex alternation (lowercase|uppercase
## byte spellings - hex_encode emits lowercase hex).
static func _hx(letter: String) -> String:
	var lo: String = "%02x" % letter.unicode_at(0)
	var up: String = "%02x" % letter.to_upper().unicode_at(0)
	return "(?:%s|%s)" % [lo, up]


static func _hx_word(word: String) -> String:
	var out: String = ""
	for i: int in range(word.length()):
		out += _hx(word[i])
	return out


static func _patterns() -> void:
	if _cgamename_re == null:
		# Whitespace byte (tab/LF/CR/space), "=", the quote,
		# then the ROM name's own characters as hex pairs
		# (digits, "_", letters either case - the capture is
		# validated after decoding, so the class can run a
		# little wide), then the closing quote.
		var ws: String = "(?:09|0a|0d|20)*"
		var capture: String = "((?:3[0-9]|5f|6[0-9a-f]|7[0-9a]|4[0-9a-f]|5[0-9a])+)"
		_cgamename_re = RegEx.new()
		_cgamename_re.compile(_hx_word("cgamename") + ws + "3d" + ws + "22" + capture + "22")
		_gamename_re = RegEx.new()
		_gamename_re.compile("2e" + _hx_word("gamename") + ws + "3d" + ws + "22" + capture + "22")


## {rom, table_name} for one .vpx path; either field "" when
## the file does not state it (or states nothing readable).
static func read_identity(path: String) -> Dictionary:
	var out: Dictionary = {"rom": "", "table_name": ""}
	var reader: CfbReader = CfbReader.new()
	if not reader.open(path):
		return out
	var gamedata: Dictionary = {}
	var tablename: Dictionary = {}
	for entry_v: Variant in reader.stream_entries():
		if entry_v is Dictionary:
			var entry: Dictionary = entry_v
			var stream_name: String = str(entry.get("name", ""))
			if stream_name == "GameData":
				gamedata = entry
			elif stream_name == "TableName":
				tablename = entry
	if not tablename.is_empty():
		var name_bytes: PackedByteArray = reader.read_stream(tablename, MAX_TABLENAME_BYTES)
		if not name_bytes.is_empty():
			out["table_name"] = name_bytes.get_string_from_utf16().strip_edges()
	if not gamedata.is_empty():
		var data: PackedByteArray = reader.read_stream(gamedata, MAX_GAMEDATA_BYTES)
		if not data.is_empty():
			out["rom"] = rom_from_gamedata(data)
	reader.close()
	return out


## A captured hex run back to the ROM name it spells, or ""
## if any decoded character is outside the ROM alphabet (a
## misaligned match spells garbage, and garbage is not a
## ROM name).
static func _rom_from_hex(hex_capture: String) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	var i: int = 0
	while i + 2 <= hex_capture.length():
		bytes.append(hex_capture.substr(i, 2).hex_to_int())
		i += 2
	var value: String = bytes.get_string_from_ascii().to_lower()
	for j: int in range(value.length()):
		var c: int = value.unicode_at(j)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return ""
	return value


## Every distinct ROM one byte range declares, as a set.
static func _rom_values_in(data: PackedByteArray) -> Dictionary:
	var values: Dictionary = {}
	if data.is_empty():
		return values
	var hex: String = data.hex_encode()
	for m: Variant in _cgamename_re.search_all(hex):
		var rm: RegExMatch = m
		var v1: String = _rom_from_hex(rm.get_string(1))
		if v1 != "":
			values[v1] = true
	if values.is_empty():
		for m2: Variant in _gamename_re.search_all(hex):
			var rm2: RegExMatch = m2
			var v2: String = _rom_from_hex(rm2.get_string(1))
			if v2 != "":
				values[v2] = true
	return values


## The ROM a GameData stream's script declares, scanned at
## the byte level over the stream's hex encoding (see the
## class doc for why a string decode cannot be used). ""
## when the script declares no ROM, or declares several
## distinct ones.
##
## VPX writes the script near the END of GameData
## (PinTable::Save writes every element first and the
## script after them, with only small records behind it),
## so a large stream is scanned tail-first over a 2 MB
## window and the head is scanned only when the tail
## declares nothing - the common case pays for the
## window, never for the whole stream. The windows
## overlap by 4 KB so a declaration straddling the seam
## still reads whole in the tail window.
static func rom_from_gamedata(data: PackedByteArray) -> String:
	if data.is_empty():
		return ""
	_patterns()
	const TAIL_WINDOW: int = 2 * 1024 * 1024
	const SEAM_OVERLAP: int = 4096
	var values: Dictionary = {}
	if data.size() > TAIL_WINDOW:
		values = _rom_values_in(data.slice(data.size() - TAIL_WINDOW - SEAM_OVERLAP))
		if values.is_empty():
			values = _rom_values_in(data.slice(0, data.size() - TAIL_WINDOW))
	else:
		values = _rom_values_in(data)
	if values.size() == 1:
		return str(values.keys()[0])
	return ""
