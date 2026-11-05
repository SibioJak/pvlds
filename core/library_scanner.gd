class_name LibraryScanner
extends RefCounted

## Scans table folders for .vpx files, groups duplicate builds of the
## same game, and matches them against the VPS database.
## Read-only: the scan never writes, moves, or touches anything in the
## table folders - table .ini files included.
## Art is LAZY: the scan records only facts visible in a directory
## listing (a same-stem image or .directb2s exists) plus each
## game's own .vpx as the embedded-image source. Extracting a
## backglass out of a .directb2s costs ~200 ms per file at
## real-world sizes, and opening a .vpx to read its embedded image
## is real work too, so both happen on demand via
## GameEntry.ensure_art(), never here. Safe to run on a worker
## thread: pure data in, pure data out.
##
## IDENTITY: between the edition tier and the local fallback
## sits the RESCUE tier (_rescue_match) - a last chance for
## file names whose identity evidence is smeared by
## decoration the equality tiers cannot see through: text
## trailing the (Maker Year) paren, letters squished into a
## single token, an acronym standing in for the title, a
## db-unique version riding in the name. Every rescue road
## ends at the parens referee with exactly one survivor, or
## it does not land at all - rescue never relaxes the
## discipline the tiers above it keep, it only reads the
## evidence they could not parse.

const MAX_SCAN_DEPTH: int = 12 ## Recursion cap - also the cycle backstop.
const JUNK_FOLDERS: Array[String] = ["$recycle.bin", "system volume information", "recycler"]

var games: Array[GameEntry] = []
var total_files: int = 0
var matched_files: int = 0 ## builds found in the db (exact build match)
var game_matched_files: int = 0 ## builds whose game is known but build is not in the db
var match_tier_counts: Dictionary = {} ## match tier -> files resolved through it (every scanned file counted once, "local" included)
var art_covered_games: int = 0
var missing_b2s_files: Array[String] = [] ## .vpx files with no same-stem .directb2s beside them, from this scan's own listing - the missing-backglass list's raw material (see MissingB2sList).
var unplaced_files: Array[String] = [] ## IDENTITY: .vpx files still local: after every tier, rescue included - the "files I couldn't place" list's raw material (see UnplacedFilesList).
var inherited_shot_games: int = 0 ## IDENTITY: games whose recorded shot came from inheritance on the last scan (see _inherit_shot).
var rescued_files: int = 0 ## IDENTITY: files the rescue tier landed on the last scan (also visible in match_tier_counts under "rescue").

var _version_re: RegEx = null
var _witness_re: RegEx = null ## IDENTITY: like _version_re but tolerates a trailing letter ("1.08a") - the version witness's net.


func _init() -> void:
	_version_re = RegEx.new()
	_version_re.compile("(?i)\\bv?(\\d+\\.\\d+(?:\\.\\d+)?)\\b")
	_witness_re = RegEx.new()
	_witness_re.compile("(?i)\\bv?(\\d+\\.\\d+(?:\\.\\d+)?[a-z]?)\\b")


func scan(folders: Array[String], db: VpsDatabase, progress: ScanProgress = null) -> void:
	games.clear()
	total_files = 0
	matched_files = 0
	game_matched_files = 0
	match_tier_counts.clear()
	art_covered_games = 0
	missing_b2s_files.clear()
	unplaced_files.clear()
	inherited_shot_games = 0
	rescued_files = 0
	if progress != null:
		progress.begin("collecting", folders.size())
	var files: Array[String] = []
	var art_map: Dictionary = {} ## .vpx path -> {"side": path} and/or {"b2s": path}
	var b2s_by_file: Dictionary = {} ## .vpx path -> true when a same-stem .directb2s was listed beside it
	var visited: Dictionary = {} ## canonical folder path -> true (cycle guard)
	var folders_done: int = 0
	for folder: String in folders:
		_collect_vpx(folder, files, art_map, visited, b2s_by_file, 0)
		folders_done += 1
		if progress != null:
			progress.report_collect(folders_done, files.size())
	files.sort()
	total_files = files.size()
	# The missing-backglass record, derived from the same listing
	# that produced the art facts - one pass, one truth. (A side
	# image does not clear a file here: the record is about the
	# backglass file's presence, not about which art won.)
	for scanned_path: String in files:
		if not bool(b2s_by_file.get(scanned_path, false)):
			missing_b2s_files.append(scanned_path)
	var by_key: Dictionary = {}
	for i: int in range(files.size()):
		var path: String = files[i]
		if progress != null and i % 16 == 0:
			progress.report_match(i)
		var build: TableBuild = _make_build(path, db)
		if build.matched_db:
			matched_files += 1
		elif build.game_key != "" and db != null and db.games_by_id.has(build.game_key):
			game_matched_files += 1
		var tier_key: String = build.match_tier if build.match_tier != "" else "local"
		match_tier_counts[tier_key] = int(match_tier_counts.get(tier_key, 0)) + 1
		if build.game_key.begins_with("local:"):
			unplaced_files.append(path)
		var entry: GameEntry = null
		var existing: Variant = by_key.get(build.game_key, null)
		if existing is GameEntry:
			entry = existing
		if entry == null:
			entry = _make_entry(build, db)
			by_key[build.game_key] = entry
			games.append(entry)
		entry.builds.append(build)
	for entry: GameEntry in games:
		_sort_builds(entry)
		_resolve_art(entry, art_map)
		# The card face's first source (the graduation round): the
		# CURRENT build's author screenshot, when the db carries
		# one for that exact build. The URL is recorded here; the
		# fetch itself is Main's ShotFetcher (the scan stays pure
		# data - no network on the worker thread).
		var best: TableBuild = entry.current_build()
		entry.shot_url = best.img_url if best != null else ""
		entry.shot_from_build = best.table_file_id if best != null and best.matched_db else ""
		entry.shot_inherited = false
		# IDENTITY: game-level shot inheritance. A game the db
		# knows whose current build carries no shot of its own
		# inherits one from the game's builds (see _inherit_shot
		# for the pick rule) - a build-unmatched file no longer
		# stands shotless while its own game's author shots sit
		# in the db. The donation is FLAGGED on the entry
		# (shot_inherited + the donor's tableFile id), never
		# silent, and it only ever fills an empty slot: a
		# build-exact shot always wins.
		if entry.shot_url == "" and db != null and db.games_by_id.has(entry.game_id) and _identity_nc() != "noinherit":
			var inherited: Dictionary = _inherit_shot(db, entry.game_id)
			if not inherited.is_empty():
				entry.shot_url = str(inherited.get("url", ""))
				entry.shot_from_build = str(inherited.get("from", ""))
				entry.shot_inherited = true
				inherited_shot_games += 1
		# Covered = the listing proved art exists: a side image or
		# a backglass. A game whose only source is the image inside
		# its .vpx is NOT counted here - that art is real but
		# unproven until an extraction succeeds, and this count is
		# the scan summary's pre-extraction baseline.
		if entry.art_path != "" or entry.art_source_path.get_extension().to_lower() == "directb2s":
			art_covered_games += 1
	if progress != null:
		progress.report_match(files.size())
		progress.finish()


## Art-source resolution for one grouped game, from the listing's
## facts. Runs once per game after grouping (never in the per-file
## loop), so a game's art does not depend on which build the scan
## met first. The order is the art order: a side image beside ANY
## build wins the face outright; else the first backglass found is
## the primary extraction source; else the first build's own .vpx
## is the primary - its embedded image is a real source, opened
## lazily by GameEntry.ensure_art, never by the scan. The first
## build's .vpx is ALWAYS recorded as art_vpx_path too: the
## embedded fallback behind a backglass primary.
func _resolve_art(entry: GameEntry, art_map: Dictionary) -> void:
	var first_side: String = ""
	var first_b2s: String = ""
	for b: TableBuild in entry.builds:
		var facts: Variant = art_map.get(b.file_path, null)
		if facts is Dictionary:
			var fd: Dictionary = facts
			if first_side == "":
				first_side = str(fd.get("side", ""))
			if first_b2s == "":
				first_b2s = str(fd.get("b2s", ""))
	if not entry.builds.is_empty():
		entry.art_vpx_path = entry.builds[0].file_path
	if first_side != "":
		entry.art_path = first_side
	elif first_b2s != "":
		entry.art_source_path = first_b2s
	elif entry.art_vpx_path != "":
		entry.art_source_path = entry.art_vpx_path


func duplicate_group_count() -> int:
	var n: int = 0
	for entry: GameEntry in games:
		if entry.builds.size() > 1:
			n += 1
	return n


func game_by_id(game_id: String) -> GameEntry:
	for entry: GameEntry in games:
		if entry.game_id == game_id:
			return entry
	return null


## Recursive collection with guards: a visited set on canonical folder
## paths (junction/symlink cycles), a depth cap as the backstop, and
## hidden/system junk folders skipped. Art facts come from this same
## listing - no candidate file is ever opened during a scan.
func _collect_vpx(folder: String, out_files: Array[String], art_map: Dictionary, visited: Dictionary, b2s_by_file: Dictionary, depth: int) -> void:
	if depth > MAX_SCAN_DEPTH:
		return
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	var canon: String = dir.get_current_dir().to_lower()
	if visited.has(canon):
		return
	visited[canon] = true
	var names: PackedStringArray = dir.get_files()
	var side_by_stem: Dictionary = {}
	for ext: String in ArtProvider.IMAGE_EXTS:
		for name: String in names:
			if name.get_extension().to_lower() == ext:
				var stem_key: String = name.get_basename().to_lower()
				if not side_by_stem.has(stem_key):
					side_by_stem[stem_key] = folder.path_join(name)
	var b2s_by_stem: Dictionary = {}
	for name: String in names:
		if name.get_extension().to_lower() == "directb2s":
			b2s_by_stem[name.get_basename().to_lower()] = folder.path_join(name)
	for name: String in names:
		if name.get_extension().to_lower() == "vpx":
			var full: String = folder.path_join(name)
			out_files.append(full)
			var stem_key: String = name.get_basename().to_lower()
			b2s_by_file[full] = b2s_by_stem.has(stem_key)
			var facts: Dictionary = {}
			if side_by_stem.has(stem_key):
				facts["side"] = str(side_by_stem[stem_key])
			elif b2s_by_stem.has(stem_key):
				facts["b2s"] = str(b2s_by_stem[stem_key])
			if not facts.is_empty():
				art_map[full] = facts
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		if JUNK_FOLDERS.has(sub.to_lower()):
			continue
		_collect_vpx(folder.path_join(sub), out_files, art_map, visited, b2s_by_file, depth + 1)


func _make_build(path: String, db: VpsDatabase) -> TableBuild:
	var b: TableBuild = TableBuild.new()
	b.file_path = path
	b.file_name = path.get_file()
	b.date_unix = int(FileAccess.get_modified_time(path))
	# GRADFIX11 (the NEW filter): the file's raw facts,
	# recorded beside date_unix because _apply_table_file
	# may overwrite date_unix with the db's release date -
	# the NEW filter's tracker (StateStore.apply_scan_facts)
	# needs the file's OWN mtime, not the release's.
	# mtime + size is the change signature: two cheap stats,
	# no content reads, so the scan's purity contract holds
	# (facts only, worker-thread safe). A rewrite that keeps
	# both the same size and the same mtime is
	# indistinguishable from untouched - which is fine,
	# because a file identical in those facts IS the same
	# table for the player's purpose.
	b.file_mtime = int(FileAccess.get_modified_time(path))
	b.file_size = 0
	var size_probe: FileAccess = FileAccess.open(path, FileAccess.READ)
	if size_probe != null:
		b.file_size = int(size_probe.get_length())
		size_probe.close()
	_match_build(b, db)
	if b.match_tier == "rescue":
		rescued_files += 1
	return b


## The tier chain alone, on a build whose file facts are
## already set (or, for a dry run, on a synthetic build
## carrying only a candidate file_name): slug -> name ->
## scrubbed -> edition -> rescue -> local. NEXTROUND
## (item 5): the rename suggester dry-runs candidate names
## through THIS function on synthetic builds - no
## filesystem writes, no library mutation, and the rescue
## counter is the caller's business (a dry run never
## counts).
func _match_build(b: TableBuild, db: VpsDatabase) -> void:
	b.match_tier = "local"
	var title_guess: String = _guess_title(b.file_name)
	var version_guess: String = _guess_version(b.file_name)
	if db != null and db.loaded:
		# 1) Download slug: the db's download page for a build bakes
		# title+maker+year+authors into its URL slug, and the file's
		# scrubbed name equals that slug's key. The key must belong
		# to ONE game - two games claiming it makes it ambiguous,
		# and an ambiguous key falls through to the next tier (a
		# false match is worse than a miss: wrong metadata, wrong
		# VR flag). Exactly one claimant file whose stated version
		# the file does not contradict claims the BUILD; otherwise
		# the game is still certain, so the within-game ladder
		# decides.
		var claimants: Array = db.find_by_slug(b.file_name)
		var claimant_games: Dictionary = {}
		for item: Variant in claimants:
			if item is Dictionary:
				var cd: Dictionary = item
				var cg: String = str(cd.get("game_id", ""))
				if cg != "":
					claimant_games[cg] = true
		if claimant_games.size() == 1:
			var slug_game_id: String = str(claimant_games.keys()[0])
			var only_tf: Dictionary = {}
			if claimants.size() == 1:
				for item2: Variant in claimants:
					if item2 is Dictionary:
						var cd2: Dictionary = item2
						var tfv: Variant = cd2.get("table_file", {})
						if tfv is Dictionary:
							only_tf = tfv
			if not only_tf.is_empty() and (version_guess == "" or version_guess == str(only_tf.get("version", ""))):
				_apply_table_file(b, slug_game_id, only_tf)
				b.match_tier = "slug"
				return
			_finish_game_match(b, db, slug_game_id, "slug", version_guess)
			return
		# 2) Game by title (with/without a leading "The").
		var game_id: String = _match_game_id(db, title_guess, b.file_name)
		if game_id != "":
			_finish_game_match(b, db, game_id, "name", version_guess)
			return
		# 3) Cleaned game name: the file's scrubbed name equals a
		# db game's scrubbed name - for tables whose db entries
		# carry no usable download slug. Refereed by the file's
		# own (Maker Year) parens: exactly one consistent game,
		# or no match.
		var scrub_ids: Array[String] = db.find_game_ids_by_scrubbed_name(b.file_name)
		var survivors: Array[String] = _referee_survivors(db, scrub_ids, b.file_name)
		if survivors.size() == 1:
			_finish_game_match(b, db, survivors[0], "scrubbed", version_guess)
			return
		# 3b) Edition referee: the file states a game's EDITION
		# words - trailing ("AC-DC LUCI Premium ... VPW v1.13"),
		# behind the maker parens, or in a no-year paren of its
		# own - and every road above refused it: the download
		# slug undershoots the edition ("acdc-luci"), the title
		# guess chokes on the decoration carrying the words, and
		# the cleaned title strips them, leaving the base name
		# shared by every trim. The file's FULL token stream -
		# edition words included - must equal exactly one db
		# game's full name, edition included, and the file's
		# (Maker Year) parens are refereed as always. Exactness
		# is the guard: a file naming one edition can never land
		# on another edition's entry, and words naming no game's
		# edition complete nothing.
		var edition_ids: Array[String] = db.find_game_ids_by_edition(b.file_name)
		var ed_survivors: Array[String] = _referee_survivors(db, edition_ids, b.file_name)
		if ed_survivors.size() == 1:
			_finish_game_match(b, db, ed_survivors[0], "edition", version_guess)
			return
		# 3c) IDENTITY rescue tier: the last chance before the
		# local fallback, for decoration the equality tiers
		# cannot parse (see _rescue_match). It runs only on
		# files every tier above refused, so by construction it
		# cannot move a file any earlier tier claimed.
		if _rescue_match(b, db, version_guess):
			return
	# 4) Unknown to the db: group by normalized title from the filename.
	b.game_key = "local:" + VpsDatabase.normalize_name(title_guess)
	b.version = version_guess


## The within-game ladder once a tier has identified the game:
## build by stated version token; when the file states no version
## and the db knows a single VPX build of the game, that build;
## otherwise the game is known and the build stays local - a
## stated version that matches nothing is NEVER relabeled as a
## db build.
func _finish_game_match(b: TableBuild, db: VpsDatabase, game_id: String, tier: String, version_guess: String) -> TableBuild:
	b.game_key = game_id
	b.match_tier = tier
	if version_guess != "":
		for item: Variant in db.vpx_table_files_of(game_id):
			if item is Dictionary:
				var tf: Dictionary = item
				if str(tf.get("version", "")) == version_guess:
					_apply_table_file(b, game_id, tf)
					return b
	else:
		var vpx_files: Array = db.vpx_table_files_of(game_id)
		if vpx_files.size() == 1 and vpx_files[0] is Dictionary:
			_apply_table_file(b, game_id, vpx_files[0])
			return b
	b.version = version_guess
	return b


## The IDENTITY round's negative-control seam, read the same
## way the house reads its others - at call time, from the
## environment: "norescue" disables the rescue tier (the
## decorated fixtures must fall back to local), "noinherit"
## disables shot inheritance (build-unmatched fixtures must
## stand shotless). Production runs with the env unset.
static func _identity_nc() -> String:
	return OS.get_environment("PVLDS_IDENTITY_NC")


## ---------------------------------------------------------------
## NEXTROUND (item 5): rename suggestions for the unplaced list.
##
## For each file the scan could not place, generate candidate
## canonical names from db games the filename gives real
## evidence for, DRY-RUN each candidate through the scanner's
## own tier chain (_match_build on a synthetic build - no
## filesystem writes, no library mutation), and suggest a name
## ONLY when a candidate actually lands AND lands on the game
## it was generated from. A wrong-game landing is discarded,
## never printed: the guard is the heart of the feature, and
## when nothing lands there is no suggestion - never a guess.
##
## The NC seam, read at call time like the house's others:
## PVLDS_SUGGEST_NC=noverify prints the first candidate
## unverified (the core test's suggester legs fail by name).

const SUGGEST_MAX_CANDIDATES: int = 16

static func _suggest_nc() -> String:
	return OS.get_environment("PVLDS_SUGGEST_NC")


## Suggestions for the standing unplaced list:
## {file_path: {"name", "game_id", "game_name",
## "build_matched", "version", "has_vr", "has_shot",
## "is_pup"}} - only for files a verified candidate exists
## for. Runs on the completed scan's own data; the cost is
## bounded by SUGGEST_MAX_CANDIDATES dry runs per file.
func suggest_renames(db: VpsDatabase) -> Dictionary:
	var out: Dictionary = {}
	if db == null or not db.loaded:
		return out
	for path: String in unplaced_files:
		var s: Dictionary = _suggest_for_file(path.get_file(), db)
		if not s.is_empty():
			out[path] = s
	return out


func _suggest_for_file(file_name: String, db: VpsDatabase) -> Dictionary:
	var candidates: Array = _suggest_candidates(file_name, db)
	if candidates.is_empty():
		return {}
	if _suggest_nc() == "noverify":
		# The seam: print the first candidate UNVERIFIED -
		# exactly the guess-printing the feature forbids.
		var first: Dictionary = candidates[0] as Dictionary
		return _suggest_describe(str(first.get("name", "")), str(first.get("game_id", "")), db, null)
	# The patch preference: a file stamped by a patch tool
	# (".vpx_VPUMod" and kin) names after the PATCH build
	# when the db lists one - the build carrying the db's
	# own "VPU Patch" tag - over the base build it patched
	# (the rename-sheet rule from the unplaced audit: the
	# patch is registered as its own build, with its own
	# version). Only patch-stamped files engage it.
	var lower_name: String = file_name.to_lower()
	var patch_evidence: bool = lower_name.contains("vpumod") or lower_name.contains("vpupatch") or lower_name.contains("vpuremix")
	var best: Dictionary = {}
	var best_rank: int = -1
	var best_patch: int = 1
	var best_close: int = 1 << 30
	for cand_v: Variant in candidates:
		var cand: Dictionary = cand_v
		var probe: TableBuild = TableBuild.new()
		probe.file_name = str(cand.get("name", ""))
		_match_build(probe, db)
		if probe.game_key != str(cand.get("game_id", "")):
			continue # landed elsewhere, or nowhere: discarded
		var rank: int = 2 if probe.matched_db else 1
		var patch_rank: int = 0 if (patch_evidence and probe.features.has("VPU Patch")) else 1
		var close: int = _suggest_closeness(file_name, probe.file_name)
		if rank > best_rank or (rank == best_rank and patch_rank < best_patch) or (rank == best_rank and patch_rank == best_patch and close < best_close):
			best_rank = rank
			best_patch = patch_rank
			best_close = close
			best = _suggest_describe(probe.file_name, probe.game_key, db, probe)
	return best


## The candidate names for one unplaced file, in the order
## they should be tried: for each eligible game (strongest
## corroboration first), the version-matching build's form
## and its tail-token forms, then the no-version form, then
## the remaining builds' forms. Capped at
## SUGGEST_MAX_CANDIDATES.
func _suggest_candidates(file_name: String, db: VpsDatabase) -> Array:
	var out: Array = []
	var version_guess: String = _guess_version(file_name)
	for gid: String in _suggest_candidate_games(file_name, db):
		var gd: Dictionary = db.game_dict(gid)
		var gname: String = str(gd.get("name", ""))
		var base: String = "%s (%s %d)" % [gname, str(gd.get("manufacturer", "")), int(gd.get("year", 0))]
		var builds: Array = db.vpx_table_files_of(gid)
		# The version-matching build first (its plain form,
		# then its tail-token forms), the no-version form,
		# then the rest of the builds in db order.
		var ordered: Array = []
		var rest: Array = []
		for item: Variant in builds:
			if item is Dictionary:
				var tf: Dictionary = item
				if version_guess != "" and str(tf.get("version", "")) == version_guess:
					ordered.append(tf)
				else:
					rest.append(tf)
		for tf: Dictionary in ordered:
			out.append({"name": "%s v%s.vpx" % [base, str(tf.get("version", ""))], "game_id": gid})
			for tok: String in _suggest_tail_tokens(file_name, tf):
				out.append({"name": "%s %s v%s.vpx" % [base, tok, str(tf.get("version", ""))], "game_id": gid})
		out.append({"name": base + ".vpx", "game_id": gid})
		for tf2: Dictionary in rest:
			var ver: String = str(tf2.get("version", ""))
			if ver != "":
				out.append({"name": "%s v%s.vpx" % [base, ver], "game_id": gid})
		if out.size() >= SUGGEST_MAX_CANDIDATES:
			break
	return out.slice(0, SUGGEST_MAX_CANDIDATES)


## The games a filename gives real evidence for, strongest
## first. A game is eligible only with corroboration - a
## filename that merely shares a word with a game proves
## nothing (the same-name deadlock is the standing example:
## "Predator (Gottlieb 1986)" corroborates NONE of the four
## db Predators, so it earns no candidates and no
## suggestion):
##   (a) the file's version guess is one of the game's VPX
##       build versions, or
##   (b) the file's (Maker Year) paren states the game's
##       maker or year, or
##   (c) the game's full name tokens all appear in the
##       file's tokens AND no other candidate game
##       satisfies (c), or
##   (d) the file's guessed-title tokens all appear in the
##       game's name AND the game is the unique such game.
func _suggest_candidate_games(file_name: String, db: VpsDatabase) -> Array:
	# The token evidence comes from the file's HEAD - the
	# name up to its first ".vpx". A patch tool's stamp
	# (".vpx_VPUMod" and friends) rides after a complete
	# extension, and its debris tokens must not poison the
	# title evidence ("Big Buck Hunter.vpx_VPUMod.vpx" is
	# titled "Big Buck Hunter").
	var head: String = file_name
	var vpos: int = head.to_lower().find(".vpx")
	if vpos > 0:
		head = head.substr(0, vpos)
	var file_tokens: Dictionary = {}
	for tok: String in VpsDatabase.scrub_tokens(head):
		file_tokens[tok] = true
	var guess_tokens: Dictionary = {}
	for tok: String in VpsDatabase.scrub_tokens(_guess_title(head + ".vpx")):
		guess_tokens[tok] = true
	var version_guess: String = _guess_version(file_name)
	var meta: Dictionary = _parse_paren_meta(file_name)
	var meta_maker: String = str(meta.get("manufacturer", "")).to_lower()
	var meta_year: int = int(meta.get("year", 0))
	var strong: Array[String] = [] # (a) or (b), db order
	var rule_c: Array[String] = []
	var rule_d: Array[String] = []
	for gid_v: Variant in db.games_by_id.keys():
		var gid: String = str(gid_v)
		var gd: Dictionary = db.game_dict(gid)
		var name_tokens: Dictionary = {}
		for tok: String in VpsDatabase.scrub_tokens(str(gd.get("name", ""))):
			name_tokens[tok] = true
		var shares: bool = false
		for tok: String in name_tokens.keys():
			if file_tokens.has(tok):
				shares = true
				break
		if not shares:
			continue
		var corr: bool = false
		if version_guess != "":
			for item: Variant in db.vpx_table_files_of(gid):
				if item is Dictionary and str((item as Dictionary).get("version", "")) == version_guess:
					corr = true
					break
		if not corr and meta_maker != "" and meta_maker == str(gd.get("manufacturer", "")).to_lower():
			corr = true
		if not corr and meta_year > 0 and meta_year == int(gd.get("year", 0)):
			corr = true
		if corr:
			strong.append(gid)
			continue
		var name_in_file: bool = not name_tokens.is_empty()
		for tok: String in name_tokens.keys():
			if not file_tokens.has(tok):
				name_in_file = false
				break
		if name_in_file:
			rule_c.append(gid)
		var guess_in_name: bool = not guess_tokens.is_empty()
		for tok: String in guess_tokens.keys():
			if not name_tokens.has(tok):
				guess_in_name = false
				break
		if guess_in_name:
			rule_d.append(gid)
	var out: Array = []
	for gid: String in strong:
		out.append(gid)
	if rule_c.size() == 1:
		out.append(rule_c[0])
	if rule_d.size() == 1 and not out.has(rule_d[0]):
		out.append(rule_d[0])
	return out


## Tail tokens for one build's candidate forms: words the
## FILENAME carries (in its own spelling) that are also
## among the build's authors or feature tags - the steering
## words a decorated name legitimately carries ("4K" on
## the Whirlwind file, matching the build's own 4K tag).
## Tokens that belong to the game's canonical name, its
## maker/year, or the version itself are not tail tokens.
func _suggest_tail_tokens(file_name: String, tf: Dictionary) -> Array:
	var wanted: Dictionary = {}
	for a: String in VpsDatabase.str_array(tf.get("authors", [])):
		for tok: String in VpsDatabase.scrub_tokens(a):
			wanted[tok] = true
	for f: String in VpsDatabase.str_array(tf.get("features", [])):
		for tok: String in VpsDatabase.scrub_tokens(f):
			wanted[tok] = true
	var stem: String = file_name.get_basename()
	var raw: PackedStringArray = stem.split(" ", false)
	var out: Array = []
	for tok: String in raw:
		var clean: String = tok.strip_edges()
		if clean == "" or clean.begins_with("(") or (clean.begins_with("v") and clean.length() > 1 and clean.substr(1, 1).is_valid_int()):
			continue
		var key: String = VpsDatabase.string_scrub(clean).to_lower()
		if wanted.has(key) and not out.has(clean):
			out.append(clean)
	return out


## How far a candidate name stands from the file's current
## name, in scrubbed tokens (symmetric difference) - the
## ranking's tie-break: among equal landings, suggest the
## smallest rename.
func _suggest_closeness(current_name: String, candidate_name: String) -> int:
	var a: Dictionary = {}
	for tok: String in VpsDatabase.scrub_tokens(current_name):
		a[tok] = true
	var b: Dictionary = {}
	for tok: String in VpsDatabase.scrub_tokens(candidate_name):
		b[tok] = true
	var n: int = 0
	for tok: String in a.keys():
		if not b.has(tok):
			n += 1
	for tok: String in b.keys():
		if not a.has(tok):
			n += 1
	return n


## The suggestion record for one verified (or, under the NC
## seam, unverified) candidate. Flags come from the probe
## build when there is one - the build the candidate
## actually landed on - else from the candidate's own game
## and build in the db.
func _suggest_describe(cand_name: String, game_id: String, db: VpsDatabase, probe: TableBuild) -> Dictionary:
	var gd: Dictionary = db.game_dict(game_id)
	var has_vr: bool = false
	var has_shot: bool = false
	var is_pup: bool = false
	var build_matched: bool = false
	var version: String = ""
	if probe != null:
		build_matched = probe.matched_db
		version = probe.version if probe.matched_db else ""
		has_shot = probe.img_url != ""
		for f: String in probe.features:
			if f == "VR" or f == "Mixed Reality" or f == "MR":
				has_vr = true
			if f == "incl. PuP":
				is_pup = true
		if not probe.matched_db:
			# Game-matched only: the flags describe the GAME
			# (any build), not a build the file does not have.
			for item: Variant in db.vpx_table_files_of(game_id):
				if item is Dictionary:
					var tf: Dictionary = item
					if str(tf.get("imgUrl", "")) != "":
						has_shot = true
					for f: String in VpsDatabase.str_array(tf.get("features", [])):
						if f == "VR" or f == "Mixed Reality" or f == "MR":
							has_vr = true
						if f == "incl. PuP":
							is_pup = true
	else:
		var cand_version: String = _guess_version(cand_name)
		for item: Variant in db.vpx_table_files_of(game_id):
			if item is Dictionary:
				var tf: Dictionary = item
				if cand_version != "" and str(tf.get("version", "")) == cand_version:
					build_matched = true
					version = cand_version
					has_shot = str(tf.get("imgUrl", "")) != ""
					for f: String in VpsDatabase.str_array(tf.get("features", [])):
						if f == "VR" or f == "Mixed Reality" or f == "MR":
							has_vr = true
						if f == "incl. PuP":
							is_pup = true
					break
	return {
		"name": cand_name,
		"game_id": game_id,
		"game_name": str(gd.get("name", "")),
		"build_matched": build_matched,
		"version": version,
		"has_vr": has_vr,
		"has_shot": has_shot,
		"is_pup": is_pup,
	}


## IDENTITY: the rescue tier. Four roads, each reading one
## shape of smeared evidence, each ending at the referee with
## exactly one survivor or not landing at all:
##   A. post-paren strip - text trailing the (Maker Year)
##      paren ("Tales from the Crypt (Data East 1993) VPW
##      PATCHED") defeats every equality tier because the
##      title guess keeps the tail or chokes on it; truncate
##      the name at that paren's close and re-run the
##      name/scrubbed/edition roads on the reduced name. The
##      referee reads the same first paren from either name,
##      so the year veto is untouched.
##   B. squish - a one-word file name ("BlizzardOfOzz") keeps
##      inside a single token the very letters the db's keys
##      shed through author-token removal (the author
##      vocabulary contains "of"); the joined-letters key
##      removes nothing on either side, so the spellings meet.
##   C. acronym - "BTILC 2026 Original 1": the title rides as
##      initials; every remaining token must be explained by
##      the candidate (decoration, author, number, the
##      candidate's own maker or year, the rescue tail
##      vocabulary), and a stated year token vetoes candidates
##      whose db year differs - the paren-year veto's spirit
##      for files that carry no parens.
##   D. version witness - a version string owned by exactly
##      ONE VPX build in the whole db (the field case:
##      "1.08a", JP's Deadpool, whose plain-regex version
##      guess the scanner cannot even read) corroborated by
##      the game name's last token and one of the build's own
##      author tokens both riding in the file name.
## A road that finds candidates but no unique survivor falls
## through to the next road; none of them relaxes a veto.
func _rescue_match(b: TableBuild, db: VpsDatabase, version_guess: String) -> bool:
	if _identity_nc() == "norescue":
		return false
	var reduced: String = _post_paren_reduced_name(b.file_name)
	if reduced != "" and _rescue_post_paren(b, db, reduced, version_guess):
		return true
	var names: Array[String] = [b.file_name]
	if reduced != "":
		names.append(reduced)
	if _rescue_squish(b, db, names, version_guess):
		return true
	if _rescue_acronym(b, db, version_guess):
		return true
	if _rescue_witness(b, db):
		return true
	return false


## Rescue road A: re-run the name, scrubbed and edition roads
## on the name truncated after its first year-carrying paren
## group. The reduced name carries the file's own title+paren
## evidence and nothing else; what trailed the paren - the
## uploader's tags - is simply not part of the question.
## DISCIPLINE (the Avengers lesson, corpus-censused): the
## truncated tail is DISCARDED evidence, and a discarded word
## can be another game's distinguishing word - "The Avengers
## (Stern 2012) Pro" is the db's "The Avengers (Pro)", not
## its "Avengers". So every tail token must be explained
## before a landing stands: a decoration word, an author
## token, the rescue tail vocabulary, digit-carrying version
## debris - or a word of the LANDING candidate's own name
## (the TMNT shape: "…(Original 2021) Stern - Data East
## remix", where the db spells those same words inside the
## game's own name). An unexplained tail token voids the
## landing; the file falls through to the other roads.
func _rescue_post_paren(b: TableBuild, db: VpsDatabase, reduced: String, version_guess: String) -> bool:
	var stem: String = b.file_name.get_file().get_basename()
	var reduced_stem: String = reduced.get_basename()
	var tail: String = stem.substr(reduced_stem.length()) if stem.begins_with(reduced_stem) else ""
	var unexplained: Array[String] = []
	for t: String in VpsDatabase.raw_tokens(tail):
		if VpsDatabase.DECORATION_TOKENS.has(t) or VpsDatabase.RESCUE_TAIL_TOKENS.has(t) or db.is_author_token(t) or _token_has_digit(t):
			continue
		unexplained.append(t)
	var game_id: String = _match_game_id(db, _guess_title(reduced), reduced)
	if game_id != "" and _tail_explained_by(db, game_id, unexplained):
		return _finish_game_match(b, db, game_id, "rescue", version_guess) != null
	var scrub_ids: Array[String] = db.find_game_ids_by_scrubbed_name(reduced)
	var survivors: Array[String] = _referee_survivors(db, scrub_ids, reduced)
	if survivors.size() == 1 and _tail_explained_by(db, survivors[0], unexplained):
		return _finish_game_match(b, db, survivors[0], "rescue", version_guess) != null
	var edition_ids: Array[String] = db.find_game_ids_by_edition(reduced)
	var ed_survivors: Array[String] = _referee_survivors(db, edition_ids, reduced)
	if ed_survivors.size() == 1 and _tail_explained_by(db, ed_survivors[0], unexplained):
		return _finish_game_match(b, db, ed_survivors[0], "rescue", version_guess) != null
	return false


## Whether every unexplained tail token is a word of the
## candidate game's own db name - see road A's discipline.
func _tail_explained_by(db: VpsDatabase, game_id: String, unexplained: Array[String]) -> bool:
	if unexplained.is_empty():
		return true
	var name_toks: PackedStringArray = VpsDatabase.raw_tokens(str(db.game_dict(game_id).get("name", "")))
	for t: String in unexplained:
		if not name_toks.has(t):
			return false
	return true


## Whether a token carries a digit - version and copy debris
## ("v1", "0f2", "mod1", "c2", "ext2k", bare numbers): shapes
## that ride in file-name tails without naming anything.
static func _token_has_digit(tok: String) -> bool:
	for i: int in range(tok.length()):
		if tok[i].is_valid_int():
			return true
	return false


## Rescue road B: joined-letters equality, refereed against
## the file's FULL name (its parens are its own evidence,
## unchanged by the reduction).
func _rescue_squish(b: TableBuild, db: VpsDatabase, names: Array[String], version_guess: String) -> bool:
	var candidates: Array[String] = []
	for nm: String in names:
		for gid: String in db.find_game_ids_by_squish(nm):
			if not candidates.has(gid):
				candidates.append(gid)
	if candidates.is_empty():
		return false
	var survivors: Array[String] = _referee_survivors(db, candidates, b.file_name)
	if survivors.size() == 1:
		return _finish_game_match(b, db, survivors[0], "rescue", version_guess) != null
	return false


## Rescue road C: the acronym. The file's first scrub token
## (3+ letters) must equal a game's name initials; the
## candidate must then explain EVERY remaining token (see
## _acronym_token_explained), survive the stated-year veto,
## and pass the parens referee. Exactly one survivor lands.
func _rescue_acronym(b: TableBuild, db: VpsDatabase, version_guess: String) -> bool:
	var toks: PackedStringArray = VpsDatabase.scrub_tokens(b.file_name)
	if toks.size() < 2 or toks[0].length() < 3:
		return false
	var candidates: Array[String] = db.find_game_ids_by_initials(toks[0])
	if candidates.is_empty():
		return false
	var stated_year: int = 0
	for t: String in toks:
		if _is_year_token(t):
			stated_year = t.to_int()
			break
	var rest: PackedStringArray = toks.slice(1)
	var survivors: Array[String] = []
	for gid: String in candidates:
		var g: Dictionary = db.game_dict(gid)
		var game_year: int = int(g.get("year", 0))
		if stated_year > 0 and game_year > 0 and game_year != stated_year:
			continue
		var explained: bool = true
		for t2: String in rest:
			if not _acronym_token_explained(db, t2, g):
				explained = false
				break
		if not explained:
			continue
		if not _meta_consistent(db, gid, b.file_name):
			continue
		survivors.append(gid)
	if survivors.size() == 1:
		return _finish_game_match(b, db, survivors[0], "rescue", version_guess) != null
	return false


## Whether one trailing token of an acronym-named file is
## accounted for by a candidate game: a shared decoration
## word, a word from the rescue tail vocabulary, one of the
## db's author tokens, a bare number, one of the candidate's
## own maker tokens, or the candidate's own year. Anything
## else is unexplained - it is part of some other name.
func _acronym_token_explained(db: VpsDatabase, tok: String, game: Dictionary) -> bool:
	if VpsDatabase.DECORATION_TOKENS.has(tok) or VpsDatabase.RESCUE_TAIL_TOKENS.has(tok):
		return true
	if tok.is_valid_int() or db.is_author_token(tok):
		return true
	if tok == str(int(game.get("year", 0))):
		return true
	return VpsDatabase.scrub_tokens(str(game.get("manufacturer", ""))).has(tok)


## Rescue road D: the version witness. Collects every
## version-shaped token in the file name (trailing letter
## tolerated - the shape the plain version guess cannot
## read), keeps those owned by exactly one VPX build in the
## whole db, and corroborates each: the candidate game's
## last name token rides in the file's scrub tokens AND at
## least one of the build's own author tokens rides in the
## file's raw tokens. Exactly one corroborated build in
## total lands the file on that build itself. The shape the
## road exists for, from the field: "Deadpool 1.08a Minimal
## Hacksaw777 R&BMetals.vpx" - version 1.08a belongs to one
## build db-wide (JP's Deadpool), "deadpool" is the game's
## last name token, "hacksaw777" is that build's author.
func _rescue_witness(b: TableBuild, db: VpsDatabase) -> bool:
	var stem: String = b.file_name.get_basename()
	var file_toks: PackedStringArray = VpsDatabase.scrub_tokens(b.file_name)
	var file_raw: Dictionary = {}
	for rt: String in VpsDatabase.raw_tokens(b.file_name):
		file_raw[rt] = true
	var seen_versions: Dictionary = {}
	var corroborated: Array = []
	for m: Variant in _witness_re.search_all(stem):
		var rm: RegExMatch = m
		var ver: String = rm.get_string(1)
		if seen_versions.has(ver):
			continue
		seen_versions[ver] = true
		var claims: Array = db.find_builds_by_version(ver)
		if claims.size() != 1 or not (claims[0] is Dictionary):
			continue
		var claim: Dictionary = claims[0]
		var gid: String = str(claim.get("game_id", ""))
		var tfv: Variant = claim.get("table_file", {})
		if gid == "" or not (tfv is Dictionary):
			continue
		var tf: Dictionary = tfv
		var g: Dictionary = db.game_dict(gid)
		var gtoks: PackedStringArray = VpsDatabase.scrub_tokens(str(g.get("name", "")))
		if gtoks.is_empty() or not file_toks.has(gtoks[gtoks.size() - 1]):
			continue
		var author_hit: bool = false
		for author: String in VpsDatabase.str_array(tf.get("authors", [])):
			for atok: String in VpsDatabase.raw_tokens(author):
				if file_raw.has(atok):
					author_hit = true
					break
			if author_hit:
				break
		if not author_hit:
			continue
		if not _meta_consistent(db, gid, b.file_name):
			continue
		corroborated.append(claim)
	if corroborated.size() == 1:
		var hit: Dictionary = corroborated[0]
		var htf: Variant = hit.get("table_file", {})
		if htf is Dictionary:
			_apply_table_file(b, str(hit.get("game_id", "")), htf)
			b.match_tier = "rescue"
			return true
	return false


## The name truncated at the close of its first
## year-carrying paren group: "Tales from the Crypt (Data
## East 1993) VPW PATCHED.vpx" -> "Tales from the Crypt
## (Data East 1993).vpx". "" when no paren group carries a
## year (nothing to truncate after) - a paren without a year
## is not the (Maker Year) anchor the road keys on.
static func _post_paren_reduced_name(file_name: String) -> String:
	var stem: String = file_name.get_file().get_basename()
	var depth: int = 0
	var seg_start: int = -1
	var i: int = 0
	while i < stem.length():
		var ch: String = stem[i]
		if ch == "(":
			if depth == 0:
				seg_start = i
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth == 0 and seg_start >= 0:
				if _segment_carries_year(stem.substr(seg_start, i - seg_start + 1)):
					return stem.substr(0, i + 1) + ".vpx"
				seg_start = -1
		i += 1
	return ""


## Whether one parenthesized segment states a year - the
## same "(19|20)xx" shape the parens referee reads.
static func _segment_carries_year(segment: String) -> bool:
	var year_re: RegEx = RegEx.new()
	year_re.compile("(19|20)\\d\\d")
	return year_re.search(segment) != null


## A bare 4-digit year token, 1950-2099 - the acronym road's
## stated-year evidence.
static func _is_year_token(tok: String) -> bool:
	if tok.length() != 4 or not tok.is_valid_int():
		return false
	var y: int = tok.to_int()
	return y >= 1950 and y <= 2099


## IDENTITY: the shot a game-matched but build-unmatched
## entry inherits. The pick rule, deterministic over the
## game's VPX table files IN DB ORDER: the first build with
## an imgUrl among the VR-tagged builds (the db's own VR /
## Mixed Reality / MR vocabulary - this is a VR launcher, so
## the shot framed for VR is the face to wear); failing that,
## the first with an imgUrl among the Hybrid builds; failing
## that, the first build with an imgUrl at all. Returns
## {"url", "from"} (the donor's tableFile id, recorded so
## the donation is auditable), or {} when the game carries
## no shot anywhere.
func _inherit_shot(db: VpsDatabase, game_id: String) -> Dictionary:
	var vr_first: Dictionary = {}
	var hybrid_first: Dictionary = {}
	var any_first: Dictionary = {}
	for item: Variant in db.vpx_table_files_of(game_id):
		if not (item is Dictionary):
			continue
		var tf: Dictionary = item
		var url: String = str(tf.get("imgUrl", "")).strip_edges()
		if url == "":
			continue
		if any_first.is_empty():
			any_first = tf
		var is_vr: bool = false
		var is_hybrid: bool = false
		for f: String in VpsDatabase.str_array(tf.get("features", [])):
			if f == "VR" or f == "Mixed Reality" or f == "MR":
				is_vr = true
			elif f == "Hybrid":
				is_hybrid = true
		if is_vr and vr_first.is_empty():
			vr_first = tf
		if is_hybrid and hybrid_first.is_empty():
			hybrid_first = tf
	for pick: Dictionary in [vr_first, hybrid_first, any_first]:
		if not pick.is_empty():
			return {"url": str(pick.get("imgUrl", "")), "from": str(pick.get("id", ""))}
	return {}


## The parens referee over a whole candidate set. The unit
## below (_meta_consistent) judges one game at a time, but
## whether the file's parens are "(Maker Year)" evidence at
## all is a property of the SET: the paren's maker words
## must engage at least one candidate's maker (the same
## subset-either-way test the unit applies). A paren that
## engages NONE of the candidates is not a statement about
## any bearer of this name - the field case (GRADFIX8 item
## 3): "Iron Maiden Legacy of the Beast (Original 2022) VPW
## 1.0.12.vpx", where the paren states the BUILD's kind and
## year (an original, no-ROM recreation released in 2022 -
## the very words the build's VPS download slug carries,
## "iron-maiden-legacy-of-the-beast-original-2022-vpw"),
## not the physical game's maker and year (Stern 2018).
## The old per-game veto read it as (Maker Year) and
## refused the game's sole claimant on both the scrubbed
## and edition roads, so a db-exact build filed as local
## and its WoVP board read NOT IN YOUR LIBRARY. So: no
## engagement anywhere -> the paren carries no evidence
## and every candidate survives (the callers' uniqueness
## rules still decide - several survivors is an ambiguity
## refusal, as before). Engagement anywhere -> the old
## per-game referee judges every candidate exactly as it
## always has: the same-name twins are still separated by
## their parens, and a file whose parens name the right
## maker with the wrong year is still refused. A paren
## with no maker words (a bare "(2022)") always engages -
## a year-only paren is still judged the old way.
## NC: PVLDS_GRADFIX8_NC=oldpair restores the pre-fix
## per-game veto for every candidate, engaged or not.
func _referee_survivors(db: VpsDatabase, candidate_ids: Array, file_name: String) -> Array[String]:
	var out: Array[String] = []
	if OS.get_environment("PVLDS_GRADFIX8_NC") == "oldpair":
		for cid: Variant in candidate_ids:
			if _meta_consistent(db, str(cid), file_name):
				out.append(str(cid))
		return out
	var meta: Dictionary = _parse_paren_meta(file_name)
	var ft: PackedStringArray = VpsDatabase.scrub_tokens(str(meta.get("manufacturer", "")))
	var engaged: bool = ft.is_empty()
	if not engaged:
		for cid2: Variant in candidate_ids:
			var g: Dictionary = db.game_dict(str(cid2))
			var gt: PackedStringArray = VpsDatabase.scrub_tokens(str(g.get("manufacturer", "")))
			if not gt.is_empty() and (_tokens_subset(ft, gt) or _tokens_subset(gt, ft)):
				engaged = true
				break
	if not engaged:
		for cid3: Variant in candidate_ids:
			out.append(str(cid3))
		return out
	for cid4: Variant in candidate_ids:
		if _meta_consistent(db, str(cid4), file_name):
			out.append(str(cid4))
	return out


## Whether the file name's own "(Manufacturer Year)" parens agree
## with a db game. Constraints exist only inside that convention:
## a paren without a year ("(Remake)", "(Special Edition)") is
## not maker evidence and vetoes nothing. With a year present,
## the year must agree (when the db carries one) and the maker
## tokens must overlap the db's (either side may carry the fuller
## form: "Northlight" against "Northlight Amusements").
func _meta_consistent(db: VpsDatabase, game_id: String, file_name: String) -> bool:
	var meta: Dictionary = _parse_paren_meta(file_name)
	var file_year: int = int(meta.get("year", 0))
	if file_year <= 0:
		return true
	var g: Dictionary = db.game_dict(game_id)
	var game_year: int = int(g.get("year", 0))
	if game_year > 0 and game_year != file_year:
		return false
	var file_maker: String = str(meta.get("manufacturer", ""))
	var game_maker: String = str(g.get("manufacturer", ""))
	if file_maker != "" and game_maker != "":
		var ft: PackedStringArray = VpsDatabase.scrub_tokens(file_maker)
		var gt: PackedStringArray = VpsDatabase.scrub_tokens(game_maker)
		if not ft.is_empty() and not gt.is_empty():
			if not _tokens_subset(ft, gt) and not _tokens_subset(gt, ft):
				return false
	return true


static func _tokens_subset(a: PackedStringArray, b: PackedStringArray) -> bool:
	for t: String in a:
		if not b.has(t):
			return false
	return true


func _apply_table_file(b: TableBuild, game_id: String, tf: Dictionary) -> void:
	b.game_key = game_id
	b.matched_db = true
	b.table_file_id = str(tf.get("id", ""))
	b.img_url = str(tf.get("imgUrl", ""))
	var v: String = str(tf.get("version", ""))
	b.version = v if v != "" else _guess_version(b.file_name)
	b.authors = VpsDatabase.str_array(tf.get("authors", []))
	b.features = VpsDatabase.str_array(tf.get("features", []))
	var release: int = VpsDatabase.parse_date_unix(tf.get("createdAt", 0))
	if release > 0:
		b.date_unix = release


func _match_game_id(db: VpsDatabase, title_guess: String, file_name: String) -> String:
	var names: Array[String] = [title_guess]
	if title_guess.to_lower().begins_with("the "):
		names.append(title_guess.substr(4))
	for candidate: String in names:
		var ids: Array[String] = db.find_game_ids_by_name(VpsDatabase.normalize_name(candidate))
		var survivors: Array[String] = _referee_survivors(db, ids, file_name)
		if survivors.size() == 1:
			return survivors[0]
		# Zero survivors: the name exists but the file's own
		# (Maker Year) parens contradict every bearer - a false
		# match refused. Several: same-name twins (remakes) the
		# parens cannot separate - ambiguous, also refused. (M1
		# took the first twin; a coin-flip identity presented as
		# fact is worse than an honest filename-only record.)
	return ""


func _make_entry(build: TableBuild, db: VpsDatabase) -> GameEntry:
	var entry: GameEntry = GameEntry.new()
	entry.game_id = build.game_key
	if db != null and db.games_by_id.has(build.game_key):
		var g: Dictionary = db.game_dict(build.game_key)
		entry.title = str(g.get("name", _guess_title(build.file_name)))
		entry.manufacturer = str(g.get("manufacturer", ""))
		entry.year = int(g.get("year", 0))
		entry.designers = VpsDatabase.str_array(g.get("designers", []))
		# CARDBACK: the db fact fields ride the entry to the
		# card back's spec grid (theme / players / MPU / type)
		# with the game's IPDB id parsed out of its ipdbUrl.
		entry.theme = VpsDatabase.str_array(g.get("theme", []))
		entry.players = int(g.get("players", 0))
		entry.mpu = str(g.get("MPU", ""))
		entry.db_type = str(g.get("type", ""))
		entry.ipdb_id = IpdbFacts.ipdb_id_from_url(str(g.get("ipdbUrl", "")))
	else:
		# Filename-only game: the title it shows everywhere (wall
		# cards, detail view, the loading marquee) is the file
		# name decoration-scrubbed - not the raw stem with author
		# tags, version tokens and feature shouts riding along.
		var clean: String = VpsDatabase.clean_display_title(build.file_name)
		entry.title = clean if clean != "" else _guess_title(build.file_name)
		var meta: Dictionary = _parse_paren_meta(build.file_name)
		entry.manufacturer = str(meta.get("manufacturer", ""))
		entry.year = int(meta.get("year", 0))
	return entry


## "Galaxy Corsair (Northlight 1991) v1.1.0.vpx" -> "Galaxy Corsair"
func _guess_title(file_name: String) -> String:
	var stem: String = file_name.get_basename().strip_edges()
	# Drop a trailing version token first ("... v1.2"), but only when it
	# sits in the trailing segment - a dotted number that is part of the
	# title proper (before the maker parens) belongs to the name.
	var matches: Array = _version_re.search_all(stem)
	if not matches.is_empty():
		var last: RegExMatch = matches[matches.size() - 1]
		if last.get_start() > stem.rfind(")"):
			stem = stem.substr(0, last.get_start()).strip_edges()
	# Then strip trailing "(...)" / "[...]" groups (maker/year, edition).
	var changed: bool = true
	while changed:
		changed = false
		if stem.ends_with(")") and stem.contains("("):
			stem = stem.substr(0, stem.rfind("(")).strip_edges()
			changed = true
		elif stem.ends_with("]") and stem.contains("["):
			stem = stem.substr(0, stem.rfind("[")).strip_edges()
			changed = true
	while stem.ends_with("-") or stem.ends_with("_"):
		stem = stem.substr(0, stem.length() - 1).strip_edges()
	return stem


## Last version-looking token in the file name, e.g. "1.0.2"; "" if none.
func _guess_version(file_name: String) -> String:
	var stem: String = file_name.get_basename()
	var matches: Array = _version_re.search_all(stem)
	if matches.is_empty():
		return ""
	var last: RegExMatch = matches[matches.size() - 1]
	return last.get_string(1)


## "Title (Manufacturer 1991)" -> {manufacturer, year} - filename heuristic
## for games the db does not know.
func _parse_paren_meta(file_name: String) -> Dictionary:
	var out: Dictionary = {"manufacturer": "", "year": 0}
	var stem: String = file_name.get_basename()
	var open: int = stem.find("(")
	var close: int = stem.find(")", open)
	if open < 0 or close < 0:
		return out
	var inside: String = stem.substr(open + 1, close - open - 1).strip_edges()
	var year_re: RegEx = RegEx.new()
	year_re.compile("(19|20)\\d\\d")
	var m: RegExMatch = year_re.search(inside)
	if m != null:
		out["year"] = m.get_string().to_int()
		out["manufacturer"] = inside.substr(0, m.get_start()).strip_edges()
	else:
		out["manufacturer"] = inside
	return out


func _sort_builds(entry: GameEntry) -> void:
	# Display order: CURRENT (db rank) first, then newest first.
	entry.builds.sort_custom(
		func(a: TableBuild, b: TableBuild) -> bool:
			if a.matched_db != b.matched_db:
				return a.matched_db
			if a.date_unix != b.date_unix:
				return a.date_unix > b.date_unix
			return TableBuild.compare_versions(a.version, b.version) > 0
	)
