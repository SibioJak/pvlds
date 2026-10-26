class_name CfbReader
extends RefCounted

## Read-only reader for OLE/CFB compound files - the container a
## .vpx table file is. VPX writes each table as a compound file:
## a header, a FAT (sector allocation table), a directory of
## named streams arranged as a tree, and the streams themselves,
## the table's embedded images among them. This reader walks just
## enough of that structure to enumerate the streams and read
## their bytes: header -> FAT/DIFAT -> directory -> stream chains,
## with small streams (< the mini-stream cutoff, 4096 bytes by the
## spec's usual setting) living in 64-byte mini sectors inside the
## root entry's container stream, chained through the miniFAT.
##
## Everything is read with seeks and bounded range reads: a table
## file can be hundreds of megabytes, and the only bytes ever
## pulled are the header, the FAT/directory/miniFAT sectors, and
## the streams the caller asks for (a bounded prefix, or one
## chosen stream). The file is opened read-only and never written.
##
## Directory entries are enumerated LINEARLY (every 128-byte
## record in the directory chain), not by walking the red-black
## tree the format defines: for a read-only census the tree adds
## failure modes (bad child pointers) without adding streams, and
## every entry carries its own name, start sector and size.
## Duplicate stream names can occur in pathological files; the
## caller sees them all and decides.
##
## Every structural read is guarded - a bad signature, a cyclic
## chain, a sector past EOF all fail soft (open() returns false,
## reads return empty), never a crash: the caller's fallback is a
## generated title card, and a corrupt table must cost no more
## than that.

const ENDOFCHAIN: int = 0xFFFFFFFE
const FREESECT: int = 0xFFFFFFFF
const FATSECT: int = 0xFFFFFFFD
const DIFSECT: int = 0xFFFFFFFC
const MAX_STREAM_BYTES: int = 512 * 1024 * 1024 ## no real table stream is near this; a bigger claim is a corrupt size field

var _file: FileAccess = null
var _sector_size: int = 512
var _mini_sector_size: int = 64
var _mini_cutoff: int = 4096
var _fat: Array[int] = []
var _minifat: Array[int] = []
var _streams: Array = [] ## Array of {name, size, start, mini} - stream entries only
var _root_start: int = ENDOFCHAIN
var _root_size: int = 0
var _container_chain: Array[int] = []
var _container_chain_built: bool = false


## Open and parse the container structure (header, FAT, directory,
## miniFAT). False on anything unreadable or not a compound file.
func open(path: String) -> bool:
	close()
	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		return false
	var length: int = int(_file.get_length())
	if length < 512:
		return false
	_file.seek(0)
	var header: PackedByteArray = _file.get_buffer(512)
	if header.size() < 512:
		return false
	# Compound-file signature: D0 CF 11 E0 A1 B1 1A E1.
	if header[0] != 0xD0 or header[1] != 0xCF or header[2] != 0x11 or header[3] != 0xE0 \
			or header[4] != 0xA1 or header[5] != 0xB1 or header[6] != 0x1A or header[7] != 0xE1:
		return false
	var sector_shift: int = _u16(header, 30)
	if sector_shift != 9 and sector_shift != 12:
		return false
	_sector_size = 1 << sector_shift
	var mini_shift: int = _u16(header, 32)
	if mini_shift < 3 or mini_shift > 12:
		return false
	_mini_sector_size = 1 << mini_shift
	_mini_cutoff = int(_u32(header, 56))
	if _mini_cutoff <= 0:
		_mini_cutoff = 4096
	var num_fat: int = int(_u32(header, 44))
	var first_dir: int = int(_u32(header, 48))
	var first_minifat: int = int(_u32(header, 60))
	var num_minifat: int = int(_u32(header, 64))
	var first_difat: int = int(_u32(header, 68))
	var num_difat: int = int(_u32(header, 72))
	# The FAT's own sector list: 109 slots in the header, then the
	# DIFAT chain (each DIFAT sector's last slot points onward).
	var fat_sectors: Array[int] = []
	for i: int in range(109):
		var sid: int = int(_u32(header, 76 + i * 4))
		if sid != FREESECT and sid != ENDOFCHAIN:
			fat_sectors.append(sid)
	var difat_at: int = first_difat
	var difat_left: int = num_difat
	while difat_at != ENDOFCHAIN and difat_at != FREESECT and difat_left > 0:
		difat_left -= 1
		var sec: PackedByteArray = _sector_bytes(difat_at)
		if sec.is_empty():
			break
		var slots: int = _sector_size / 4 - 1
		for i: int in range(slots):
			var sid2: int = int(_u32(sec, i * 4))
			if sid2 != FREESECT and sid2 != ENDOFCHAIN:
				fat_sectors.append(sid2)
		difat_at = int(_u32(sec, slots * 4))
	if num_fat > 0 and fat_sectors.size() > num_fat:
		fat_sectors.resize(num_fat)
	if fat_sectors.is_empty():
		return false
	_fat.clear()
	for fsid: int in fat_sectors:
		var fsec: PackedByteArray = _sector_bytes(fsid)
		if fsec.is_empty():
			return false
		for off: int in range(0, fsec.size() - 3, 4):
			_fat.append(int(_u32(fsec, off)))
	# Directory: every entry in the chain, linearly.
	var dir_chain: Array[int] = _chain(first_dir, _fat)
	if dir_chain.is_empty():
		return false
	var dir_bytes: PackedByteArray = PackedByteArray()
	for dsid: int in dir_chain:
		dir_bytes.append_array(_sector_bytes(dsid))
	_streams.clear()
	_root_start = ENDOFCHAIN
	_root_size = 0
	var entry_count: int = dir_bytes.size() / 128
	for e: int in range(entry_count):
		var base: int = e * 128
		var obj_type: int = dir_bytes[base + 66]
		if obj_type != 1 and obj_type != 2 and obj_type != 5:
			continue
		var start: int = int(_u32(dir_bytes, base + 116))
		var size: int = int(_u32(dir_bytes, base + 120))
		if obj_type == 5:
			_root_start = start
			_root_size = size
		elif obj_type == 2:
			var name_len: int = _u16(dir_bytes, base + 64)
			var stream_name: String = ""
			if name_len >= 2 and name_len <= 64:
				stream_name = dir_bytes.slice(base, base + name_len - 2).get_string_from_utf16()
			_streams.append({
				"name": stream_name,
				"size": size,
				"start": start,
				"mini": size < _mini_cutoff,
			})
	# MiniFAT: the mini-sector chain table.
	_minifat.clear()
	if first_minifat != ENDOFCHAIN and first_minifat != FREESECT:
		var mf_chain: Array[int] = _chain(first_minifat, _fat)
		var read_sectors: int = 0
		for msid: int in mf_chain:
			if num_minifat > 0 and read_sectors >= num_minifat:
				break
			read_sectors += 1
			var msec: PackedByteArray = _sector_bytes(msid)
			for off: int in range(0, msec.size() - 3, 4):
				_minifat.append(int(_u32(msec, off)))
	return true


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## Every stream entry in the file: {name, size, start, mini}.
func stream_entries() -> Array:
	return _streams


## The first `limit` bytes of a stream (its whole content when
## the stream is smaller) - a prefix in the true sense: the
## stream's total size does NOT refuse the read, only the claimed
## size's sanity bounds it. Empty on any structural surprise.
func read_prefix(entry: Dictionary, limit: int) -> PackedByteArray:
	if _file == null or limit <= 0:
		return PackedByteArray()
	var size: int = int(entry.get("size", 0))
	if size <= 0 or size > MAX_STREAM_BYTES:
		return PackedByteArray()
	var want: int = mini(size, limit)
	if bool(entry.get("mini", false)):
		return _read_mini(entry, want)
	return _read_regular(entry, want)


## A stream's bytes in full, capped at max_bytes: a stream
## claiming more reads as empty (the caller treats that as
## unreadable), so a corrupt size field can never pull a giant
## allocation.
func read_stream(entry: Dictionary, max_bytes: int) -> PackedByteArray:
	if _file == null:
		return PackedByteArray()
	var size: int = int(entry.get("size", 0))
	if size <= 0 or size > MAX_STREAM_BYTES or size > max_bytes:
		return PackedByteArray()
	if bool(entry.get("mini", false)):
		return _read_mini(entry, size)
	return _read_regular(entry, size)


## Bytes from the middle of a stream: [offset, offset + count),
## clamped to the stream's claimed size. Same refusal discipline
## as read_stream - a corrupt claimed size or an over-cap span
## reads empty, never a giant allocation, and only the sectors
## the span touches are read. The .vpx art extractor locates one
## embedded image's record span inside its stream and reads
## exactly that span, never the whole stream around it.
func read_stream_range(entry: Dictionary, offset: int, count: int, max_total: int) -> PackedByteArray:
	if _file == null or offset < 0 or count <= 0 or count > max_total:
		return PackedByteArray()
	var size: int = int(entry.get("size", 0))
	if size <= 0 or size > MAX_STREAM_BYTES:
		return PackedByteArray()
	var want: int = mini(count, size - offset)
	if want <= 0:
		return PackedByteArray()
	if bool(entry.get("mini", false)):
		return _read_mini_range(entry, offset, want)
	return _read_regular_range(entry, offset, want)


func _read_regular_range(entry: Dictionary, offset: int, want: int) -> PackedByteArray:
	var chain: Array[int] = _chain(int(entry.get("start", ENDOFCHAIN)), _fat)
	var out: PackedByteArray = PackedByteArray()
	var logical: int = 0
	for sid: int in chain:
		if logical >= offset + want:
			break
		if logical + _sector_size > offset:
			var sec: PackedByteArray = _sector_bytes(sid)
			if sec.is_empty():
				break
			var from: int = maxi(0, offset - logical)
			var to: int = mini(sec.size(), offset + want - logical)
			if to > from:
				out.append_array(sec.slice(from, to))
		logical += _sector_size
	return out


func _read_mini_range(entry: Dictionary, offset: int, want: int) -> PackedByteArray:
	var chain: Array[int] = _chain(int(entry.get("start", ENDOFCHAIN)), _minifat)
	var out: PackedByteArray = PackedByteArray()
	var logical: int = 0
	for msid: int in chain:
		if logical >= offset + want:
			break
		if logical + _mini_sector_size > offset:
			var chunk: PackedByteArray = _container_range(msid * _mini_sector_size, _mini_sector_size)
			if chunk.is_empty():
				break
			var from: int = maxi(0, offset - logical)
			var to: int = mini(chunk.size(), offset + want - logical)
			if to > from:
				out.append_array(chunk.slice(from, to))
		logical += _mini_sector_size
	return out


func _read_regular(entry: Dictionary, want: int) -> PackedByteArray:
	var chain: Array[int] = _chain(int(entry.get("start", ENDOFCHAIN)), _fat)
	var out: PackedByteArray = PackedByteArray()
	for sid: int in chain:
		if out.size() >= want:
			break
		var sec: PackedByteArray = _sector_bytes(sid)
		if sec.is_empty():
			break
		var take: int = mini(sec.size(), want - out.size())
		out.append_array(sec.slice(0, take))
	return out


func _read_mini(entry: Dictionary, want: int) -> PackedByteArray:
	var chain: Array[int] = _chain(int(entry.get("start", ENDOFCHAIN)), _minifat)
	var out: PackedByteArray = PackedByteArray()
	for msid: int in chain:
		if out.size() >= want:
			break
		var chunk: PackedByteArray = _container_range(msid * _mini_sector_size, _mini_sector_size)
		if chunk.is_empty():
			break
		out.append_array(chunk)
	if out.size() > want:
		out.resize(want)
	return out


## Bytes from the root entry's container stream (the mini-stream
## storage), by absolute offset - the random-access helper the
## mini reader walks with.
func _container_range(offset: int, count: int) -> PackedByteArray:
	if not _container_chain_built:
		_container_chain_built = true
		_container_chain = _chain(_root_start, _fat) if _root_start != ENDOFCHAIN else []
	var out: PackedByteArray = PackedByteArray()
	var pos: int = offset
	var end: int = offset + count
	while pos < end:
		var sidx: int = pos / _sector_size
		if sidx >= _container_chain.size():
			break
		var sec: PackedByteArray = _sector_bytes(_container_chain[sidx])
		if sec.is_empty():
			break
		var within: int = pos % _sector_size
		var take: int = mini(sec.size() - within, end - pos)
		if take <= 0:
			break
		out.append_array(sec.slice(within, within + take))
		pos += take
	return out


## One sector's bytes (short at EOF). Out-of-range reads empty.
func _sector_bytes(sid: int) -> PackedByteArray:
	if _file == null or sid < 0 or sid >= FREESECT - 3:
		return PackedByteArray()
	_file.seek((sid + 1) * _sector_size)
	return _file.get_buffer(_sector_size)


## Follow a sector chain in the given allocation table, guarded
## against cycles and table overruns: a chain can never visit
## more sectors than the table has entries.
func _chain(start: int, table: Array[int]) -> Array[int]:
	var out: Array[int] = []
	var seen: Dictionary = {}
	var at: int = start
	while at != ENDOFCHAIN and at != FREESECT and at >= 0 and at < table.size():
		if seen.has(at):
			break
		seen[at] = true
		out.append(at)
		at = table[at]
	return out


static func _u16(bytes: PackedByteArray, off: int) -> int:
	if off < 0 or off + 2 > bytes.size():
		return 0
	return int(bytes.decode_u16(off))


static func _u32(bytes: PackedByteArray, off: int) -> int:
	if off < 0 or off + 4 > bytes.size():
		return 0
	return int(bytes.decode_u32(off)) & 0xFFFFFFFF
