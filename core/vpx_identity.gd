class_name VpxIdentity
extends RefCounted

## A .vpx file's OWN identity, read from inside the file -
## the evidence a misleading file name cannot fake. Two
## facts:
##
## - "rom": the ROM name the table's script declares.
##   VPX stores the script in the GameData stream (a BIFF
##   stream; the script rides as its CODE object, plain
##   text bytes), and a VPinMAME table names its ROM in
##   the script - canonically `Const cGameName =
##   "smanve_101"`. FIX125 hunted that declaration as a
##   raw byte pattern; FIX126 READS it as VBScript.
##   Candidate declaration sites are still found at the
##   byte level (the stream is binary BIFF around the
##   script text, and a whole-stream string decode dies
##   at the first NUL or invalid byte - measured on a
##   synthetic fixture: both decoders returned a
##   5-character string for a 206-byte stream), but each
##   candidate is then judged on its own source line:
##
##   * COMMENTS ARE NOT DECLARATIONS. A declaration
##     inside a comment (an apostrophe comment or a Rem
##     statement, found with a string-aware pass - an
##     apostrophe inside a string literal starts
##     nothing) is ignored. A real VPW script that lists
##     its ROM alternates as commented lines declares
##     exactly one ROM: the live one.
##   * FORMS. `Const cGameName = "x"`, a `Dim` followed
##     by a later assignment, a bare assignment, a
##     literal chain (`"smanve" & "_101"`), and one
##     level of variable indirection (a variable
##     assigned exactly one string literal and nothing
##     else) are all the same evidence.
##   * GENUINE CHOICE STILL ABSTAINS. Several DISTINCT
##     live cGameName literals - a script that truly
##     offers a choice of ROMs - declare no single
##     identity, and the witness must not pick one.
##     The read reports WHY via "rom_status": declared /
##     multiple-live-roms / variable-held-unreadable /
##     no-rom-in-script, so an abstention is a loggable
##     fact, never a silence.
##
##   A direct `.GameName = "..."` assignment is the
##   fallback shape, consulted only when cGameName
##   yields no live literal or variable evidence at
##   all (the FIX125 rule).
##
## - "table_name": the internal table name (the
##   TableInfo storage's TableName stream, raw UTF-16
##   text) - the fallback witness for tables that
##   declare no ROM (originals, EM recreations).
##
## "opened" reports whether the file could be opened
## and its GameData read at all - the distinction
## between "the reader abstained on a real script" and
## "there was nothing to read" (a stub, a non-compound
## file), which the scan log states as different
## verdicts.
##
## Read-only and fail-soft, like the art path that
## shares the CfbReader: an unreadable or non-compound
## file, a missing stream, an oversized GameData - all
## read as an empty identity, never an error. The scan
## consults this ONLY for contested claims (see
## LibraryScanner._rom_witness); it is not a per-file
## cost.

const MAX_GAMEDATA_BYTES: int = 64 * 1024 * 1024 ## a real GameData stream is a few MB at most; a bigger claim is a corrupt size field, refused like the art reader refuses it
const MAX_TABLENAME_BYTES: int = 64 * 1024

const ROM_DECLARED: String = "declared"
const ROM_MULTIPLE: String = "multiple-live-roms"
const ROM_VARIABLE: String = "variable-held-unreadable"
const ROM_NONE: String = "no-rom-in-script"


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


static func _lower_byte(b: int) -> int:
	return b + 32 if b >= 65 and b <= 90 else b


static func _is_ident_byte(b: int) -> bool:
	return (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95


## Byte offsets of every whole-byte occurrence of `word`
## (ASCII, case-insensitive) in data. Sightings are found
## on the data's hex encoding (native-speed over MB
## windows) and then verified against the raw bytes: a
## hex match can start on a nibble boundary and spell
## the word across two bytes, and only a whole-byte
## sighting counts.
static func _word_offsets(data: PackedByteArray, word: String) -> Array:
	var out: Array = []
	if data.is_empty() or word.is_empty():
		return out
	var re: RegEx = RegEx.new()
	re.compile(_hx_word(word.to_lower()))
	var wlen: int = word.length()
	for m: Variant in re.search_all(data.hex_encode()):
		var rm: RegExMatch = m
		var start: int = rm.get_start()
		if start % 2 != 0:
			continue
		var off: int = start / 2
		if off + wlen > data.size():
			continue
		var ok: bool = true
		for i: int in range(wlen):
			if _lower_byte(data[off + i]) != word.to_lower().unicode_at(i):
				ok = false
				break
		if ok:
			out.append(off)
	return out


## The source line around byte offset `off`, as text:
## bytes from the previous LF to the next (capped at
## 1024 either way - a script line is never that long;
## the cap bounds the work a pathological stream can
## demand), printable ASCII and tab kept, every other
## byte a space, so binary chaff around the script can
## neither forge nor swallow a character. Returns
## [text, col] with col = off's index in the text.
static func _line_at(data: PackedByteArray, off: int) -> Array:
	var start: int = off
	var floor_i: int = maxi(0, off - 1024)
	while start > floor_i and data[start - 1] != 10:
		start -= 1
	var end: int = off
	var ceil_i: int = mini(data.size(), off + 1024)
	while end < ceil_i and data[end] != 10:
		end += 1
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(end - start)
	for i: int in range(end - start):
		var b: int = data[start + i]
		bytes[i] = b if b == 9 or (b >= 32 and b <= 126) else 32
	return [bytes.get_string_from_ascii(), off - start]


static func _word_at(line: String, i: int, word: String) -> bool:
	var wlen: int = word.length()
	if i + wlen > line.length():
		return false
	for k: int in range(wlen):
		var ch: int = line.unicode_at(i + k)
		if ch >= 65 and ch <= 90:
			ch += 32
		if ch != word.unicode_at(k):
			return false
	if i + wlen < line.length() and _is_ident_byte(line.unicode_at(i + wlen)):
		return false
	return true


## Where live code ends in one source line: the index of
## the first comment start, or the line's length. A
## comment starts at an apostrophe OUTSIDE a string
## literal, or at a Rem statement at a statement start
## (line start, or after a ':' separator - Rem comments
## out the rest of the line, colons included). String
## literals are walked with VBScript's own rule - a
## doubled "" inside a string is an escaped quote, not
## its end - so an apostrophe inside a string
## ("Siggi's Mod") never starts a comment.
static func _comment_cut(line: String) -> int:
	var n: int = line.length()
	var in_str: bool = false
	var stmt_start: bool = true
	var i: int = 0
	while i < n:
		var ch: int = line.unicode_at(i)
		if in_str:
			if ch == 34:
				if i + 1 < n and line.unicode_at(i + 1) == 34:
					i += 2
					continue
				in_str = false
			i += 1
			continue
		if ch == 34:
			in_str = true
			stmt_start = false
			i += 1
			continue
		if ch == 39:
			return i
		if ch == 58:
			stmt_start = true
			i += 1
			continue
		if ch == 32 or ch == 9:
			i += 1
			continue
		if stmt_start and _word_at(line, i, "rem"):
			return i
		stmt_start = false
		i += 1
	return n


## A string-literal chain at index i of the line: "lit",
## or "lit" & "lit" & ... (still exact literal evidence -
## no guessing). Returns [value, end_index] with
## end_index just past the chain's trailing whitespace,
## or [] when the text at i is not a pure literal chain.
static func _literal_chain(line: String, i: int, cut: int) -> Array:
	var codes: PackedByteArray = PackedByteArray()
	var j: int = i
	while true:
		if j >= cut or line.unicode_at(j) != 34:
			return []
		j += 1
		var closed: bool = false
		while j < cut:
			var ch: int = line.unicode_at(j)
			if ch == 34:
				if j + 1 < cut and line.unicode_at(j + 1) == 34:
					codes.append(34)
					j += 2
					continue
				closed = true
				j += 1
				break
			codes.append(ch)
			j += 1
		if not closed:
			return []
		var k: int = j
		while k < cut and (line.unicode_at(k) == 32 or line.unicode_at(k) == 9):
			k += 1
		if k < cut and line.unicode_at(k) == 38: # &
			j = k + 1
			while j < cut and (line.unicode_at(j) == 32 or line.unicode_at(j) == 9):
				j += 1
			continue
		return [codes.get_string_from_ascii(), k]
	return [] # unreachable - the loop above only exits by returning; the analyzer cannot prove it


static func _ident_at(line: String, i: int, cut: int) -> String:
	var codes: PackedByteArray = PackedByteArray()
	var j: int = i
	while j < cut and _is_ident_byte(line.unicode_at(j)):
		codes.append(line.unicode_at(j))
		j += 1
	return codes.get_string_from_ascii()


## One sighting of `word` (at byte offset `off` in data)
## judged as an assignment. Returns {kind, value}:
## "literal" (value = the assigned string, lowercased),
## "variable" (value = the assigned variable's name,
## lowercased), "unreadable" (an assignment whose
## right-hand side is no pure literal and no single
## variable - an expression, a call, an array element),
## or "none" (not an assignment at all: a value-less
## declaration, a use, a sighting inside a comment, or
## a substring of a longer identifier - cGameNameAlt
## is not cGameName).
static func _judge_assignment(data: PackedByteArray, off: int, word: String) -> Dictionary:
	var none: Dictionary = {"kind": "none"}
	var wlen: int = word.length()
	if off > 0 and _is_ident_byte(data[off - 1]):
		return none
	if off + wlen < data.size() and _is_ident_byte(data[off + wlen]):
		return none
	var line_col: Array = _line_at(data, off)
	var line: String = str(line_col[0])
	var col: int = int(line_col[1])
	var cut: int = _comment_cut(line)
	if col >= cut:
		return none # inside a comment
	var j: int = col + wlen
	while j < cut and (line.unicode_at(j) == 32 or line.unicode_at(j) == 9):
		j += 1
	if j >= cut or line.unicode_at(j) != 61: # =
		return none
	j += 1
	while j < cut and (line.unicode_at(j) == 32 or line.unicode_at(j) == 9):
		j += 1
	if j >= cut:
		return {"kind": "unreadable"}
	var ch: int = line.unicode_at(j)
	if ch == 34:
		var chain: Array = _literal_chain(line, j, cut)
		if chain.is_empty():
			return {"kind": "unreadable"}
		# What follows the chain cannot unmake the literal:
		# a ':' starts the next statement, and anything else
		# glued here is the next BIFF record's chaff riding
		# on the script's last line (it has no LF of its
		# own). The one continuation that would change the
		# value - a '+' concatenation into parts unknown -
		# stays unreadable; '&' continuations are judged
		# inside the chain itself, which demands a literal
		# after every '&'.
		var endpos: int = int(chain[1])
		if endpos < cut and line.unicode_at(endpos) == 43: # +
			return {"kind": "unreadable"}
		return {"kind": "literal", "value": str(chain[0]).to_lower()}
	if _is_ident_byte(ch) and not (ch >= 48 and ch <= 57):
		var name: String = _ident_at(line, j, cut)
		var endpos2: int = j + name.length()
		while endpos2 < cut and (line.unicode_at(endpos2) == 32 or line.unicode_at(endpos2) == 9):
			endpos2 += 1
		# An operator hard after the name makes it an
		# expression, not a sighting of the variable: '('
		# an array element or call, '&' / '+' a
		# concatenation, '.' a member. Anything else -
		# ':' or the next record's chaff - leaves the
		# sighting standing.
		if endpos2 < cut and (line.unicode_at(endpos2) == 40 or line.unicode_at(endpos2) == 38
				or line.unicode_at(endpos2) == 43 or line.unicode_at(endpos2) == 46):
			return {"kind": "unreadable"}
		return {"kind": "variable", "value": name.to_lower()}
	return {"kind": "unreadable"}


## Every live assignment sighting of `word` in one byte
## range, as evidence: the set of literals assigned, the
## set of variables assigned from, and whether any
## assignment's right-hand side was unreadable. With
## dot_prefix, only sightings immediately preceded by a
## '.' count (the `.GameName` fallback shape).
static func _evidence_in(data: PackedByteArray, word: String, dot_prefix: bool) -> Dictionary:
	var ev: Dictionary = {"literals": {}, "variables": [], "unreadable": false}
	for off_v: Variant in _word_offsets(data, word):
		var off: int = int(off_v)
		if dot_prefix and (off == 0 or data[off - 1] != 46):
			continue
		var judged: Dictionary = _judge_assignment(data, off, word)
		match str(judged.get("kind", "none")):
			"literal":
				ev["literals"][str(judged["value"])] = true
			"variable":
				var vn: String = str(judged["value"])
				if not (ev["variables"] as Array).has(vn):
					(ev["variables"] as Array).append(vn)
			"unreadable":
				ev["unreadable"] = true
	return ev


## One byte range's ROM evidence: cGameName first; the
## `.GameName` fallback only when cGameName yielded no
## live literal or variable evidence at all (the FIX125
## rule - a non-literal cGameName right-hand side does
## not block the fallback, exactly as the old byte
## pattern, which simply never matched it).
static func _rom_evidence_in(data: PackedByteArray) -> Dictionary:
	var ev: Dictionary = _evidence_in(data, "cgamename", false)
	if (ev["literals"] as Dictionary).is_empty() and (ev["variables"] as Array).is_empty():
		var fb: Dictionary = _evidence_in(data, "gamename", true)
		for k: Variant in (fb["literals"] as Dictionary).keys():
			(ev["literals"] as Dictionary)[k] = true
		for vn: Variant in fb["variables"]:
			if not (ev["variables"] as Array).has(vn):
				(ev["variables"] as Array).append(vn)
		ev["unreadable"] = bool(ev["unreadable"]) or bool(fb["unreadable"])
	return ev


static func _evidence_empty(ev: Dictionary) -> bool:
	return (ev["literals"] as Dictionary).is_empty() and (ev["variables"] as Array).is_empty() and not bool(ev["unreadable"])


## Resolve one variable to the single string literal the
## script assigns it. {ok, value, multi}: ok=false when
## the variable is assigned anything but string literals
## (or nothing readable at all); multi=true when it is
## assigned several DISTINCT literals - a branch
## rewriting it, a genuine choice, reported upstream as
## multiple-live-roms. One level only: a variable
## assigned from another variable is unreadable, never
## chased.
static func _resolve_variable(data: PackedByteArray, varname: String) -> Dictionary:
	var literals: Dictionary = {}
	var tainted: bool = false
	var found: bool = false
	for off_v: Variant in _word_offsets(data, varname):
		var off: int = int(off_v)
		if off > 0 and data[off - 1] == 46:
			continue # a property, not the variable
		var judged: Dictionary = _judge_assignment(data, off, varname)
		match str(judged.get("kind", "none")):
			"literal":
				found = true
				literals[str(judged["value"])] = true
			"variable", "unreadable":
				found = true
				tainted = true
	if not found or tainted:
		return {"ok": false, "value": "", "multi": false}
	if literals.size() > 1:
		return {"ok": false, "value": "", "multi": true}
	if literals.size() == 1:
		var v: String = str(literals.keys()[0])
		if v != "":
			return {"ok": true, "value": v, "multi": false}
	return {"ok": false, "value": "", "multi": false}


## Evidence -> the read's verdict: {rom, status}.
static func _verdict_from_evidence(data: PackedByteArray, ev: Dictionary) -> Dictionary:
	var literals: Dictionary = ev["literals"]
	if literals.size() > 1:
		return {"rom": "", "status": ROM_MULTIPLE}
	if literals.size() == 1:
		var v: String = str(literals.keys()[0])
		if v == "":
			return {"rom": "", "status": ROM_NONE} # cGameName = "" declares no ROM
		return {"rom": v, "status": ROM_DECLARED}
	var variables: Array = ev["variables"]
	if not variables.is_empty():
		var resolved: Dictionary = {}
		for vn_v: Variant in variables:
			var r: Dictionary = _resolve_variable(data, str(vn_v))
			if bool(r.get("multi", false)):
				return {"rom": "", "status": ROM_MULTIPLE}
			if not bool(r.get("ok", false)):
				return {"rom": "", "status": ROM_VARIABLE}
			resolved[str(r["value"])] = true
		if resolved.size() > 1:
			return {"rom": "", "status": ROM_MULTIPLE}
		if resolved.size() == 1:
			return {"rom": str(resolved.keys()[0]), "status": ROM_DECLARED}
		return {"rom": "", "status": ROM_VARIABLE}
	if bool(ev["unreadable"]):
		return {"rom": "", "status": ROM_VARIABLE}
	return {"rom": "", "status": ROM_NONE}


## The script's own bytes inside GameData: the stream
## is a flat run of BIFF records (4-byte tag, int32
## size, payload), and the script rides as the CODE
## record's payload - byte-exact, so its last line is
## not glued to the next record's tag (a script that
## ends `cGameName = RomName` with no trailing newline
## otherwise reads the variable as "RomNameTLCK", a
## name no assignment can ever resolve). The walk is
## fail-soft: any framing surprise - a negative or
## overrunning size, no CODE record - returns the
## whole stream, which is then read exactly as FIX125
## read it.
static func _script_bytes(data: PackedByteArray) -> PackedByteArray:
	var i: int = 0
	while i + 8 <= data.size():
		var size: int = data.decode_s32(i + 4)
		if size < 0 or i + 8 + size > data.size():
			return data
		if data[i] == 67 and data[i + 1] == 79 and data[i + 2] == 68 and data[i + 3] == 69: # CODE
			return data.slice(i + 8, i + 8 + size)
		i += 8 + size
	return data


## One byte range's read: the window discipline below,
## applied to whatever range it is given.
static func _read_in_range(data: PackedByteArray) -> Dictionary:
	const TAIL_WINDOW: int = 2 * 1024 * 1024
	const SEAM_OVERLAP: int = 4096
	var range_data: PackedByteArray = data
	var ev: Dictionary
	if data.size() > TAIL_WINDOW:
		range_data = data.slice(data.size() - TAIL_WINDOW - SEAM_OVERLAP)
		ev = _rom_evidence_in(range_data)
		if _evidence_empty(ev):
			range_data = data.slice(0, data.size() - TAIL_WINDOW)
			ev = _rom_evidence_in(range_data)
	else:
		ev = _rom_evidence_in(data)
	return _verdict_from_evidence(range_data, ev)


## The ROM a GameData stream's script declares, with
## the reason when it declares none readable:
## {rom, status} - see the class doc for the statuses.
##
## The script is read at its own extent first (the CODE
## record's payload - see _script_bytes). If that
## extent declares nothing at all, the walk may have
## framed onto a stranger's record, and the whole
## stream gets its say before the reader abstains on
## nothing.
##
## VPX writes the script near the END of GameData
## (PinTable::Save writes every element first and the
## script after them, with only small records behind
## it), so a large range is read tail-first over a
## 2 MB window and the head is read only when the tail
## holds no live evidence at all - the common case pays
## for the window, never for the whole range. The
## windows overlap by 4 KB so a declaration straddling
## the seam still reads whole in the tail window.
## Variable resolution runs against the same window
## that produced the evidence.
static func rom_read_from_gamedata(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {"rom": "", "status": ROM_NONE}
	var script: PackedByteArray = _script_bytes(data)
	var read: Dictionary = _read_in_range(script)
	if script.size() != data.size() and str(read.get("rom", "")) == "" and str(read.get("status", "")) == ROM_NONE:
		read = _read_in_range(data)
	return read


## The FIX125 byte-pattern contract, kept for its
## standing callers: just the ROM string, "" when the
## script declares none readable.
static func rom_from_gamedata(data: PackedByteArray) -> String:
	return str(rom_read_from_gamedata(data).get("rom", ""))


## {rom, table_name, rom_status, opened} for one .vpx
## path; the string fields "" when the file does not
## state them (or states nothing readable), rom_status
## the reason when rom is "", and opened=false when the
## file could not be opened or carries no readable
## GameData at all.
static func read_identity(path: String) -> Dictionary:
	var out: Dictionary = {"rom": "", "table_name": "", "rom_status": ROM_NONE, "opened": false}
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
			out["opened"] = true
			var read: Dictionary = rom_read_from_gamedata(data)
			out["rom"] = str(read.get("rom", ""))
			out["rom_status"] = str(read.get("status", ROM_NONE))
	reader.close()
	return out
