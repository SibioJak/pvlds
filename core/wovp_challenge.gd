class_name WovpChallenge
extends RefCounted

## One live WoVP challenge and its full scoreboard, as the
## league's challenges/search carries it (response model:
## VPin Studio's Challenge / PinballTable /
## PinballTableVersion / ScoreBoard DTOs, mirrored in the
## scores spike, FINDINGS.md). Pure data plus the board
## mathematics the wall renders: which row is his, who leads,
## and where the cutoff line the challenge type implies
## falls. The matching to his library is by the VPS ids this
## object carries (table_external_id is the VPS game id,
## version_external_id the VPS table-file id) - the room does
## that join against the scanner's existing match data.

const TYPE_SEASON: String = "season"
const TYPE_EXTRA: String = "extra"
const TYPE_TOURNAMENT: String = "tournament"
const TYPE_MONTHLY: String = "monthly_contracts"
const KNOWN_TYPES: Array[String] = [TYPE_SEASON, TYPE_EXTRA, TYPE_TOURNAMENT, TYPE_MONTHLY]

## Battle Royale (rules §2): the bottom 10 are cut each
## round - the cut line sits under the last survivor.
const BATTLE_ROYALE_CUT: int = 10
## Season divisions (rules §5): the top 8 move up at the
## season's end - the promotion line sits under 8th.
const PROMOTION_LINE: int = 8

var challenge_id: String = ""
var season_challenge_id: String = ""
var name: String = ""
var description: String = ""
var type_code: String = ""
var script_keywords: Array[String] = [] ## every phrase must appear in the local table's script for Studio activation (spike); PVLDS reads boards only in this round and does not evaluate them
var start_unix: int = 0 ## 0 = the payload carried none
var end_unix: int = 0
var table_id: String = "" ## the league's own table row id
var table_external_id: String = "" ## the VPS game id - the library join key
var table_name: String = ""
var table_manufacturer: String = ""
var table_year: int = 0
var version_id: String = ""
var version_external_id: String = "" ## the VPS table-file id - the build join key
var version_name: String = ""
var rows: Array[WovpScoreRow] = [] ## the board, sorted by position


## The band label the wall shows for this challenge type.
func type_label() -> String:
	match type_code:
		TYPE_SEASON:
			return "SEASON"
		TYPE_EXTRA:
			return "SEASON - EXTRA"
		TYPE_TOURNAMENT:
			return "BATTLE ROYALE"
		TYPE_MONTHLY:
			return "MONTHLY CONTRACT"
	return "CHALLENGE"


func leader_row() -> WovpScoreRow:
	return rows[0] if not rows.is_empty() else null


## His row on this board, by the userId validate-apikey
## resolved for his key. Null when he has no score on it.
func his_row(user_id: String) -> WovpScoreRow:
	if user_id == "":
		return null
	for r: WovpScoreRow in rows:
		if r.user_id == user_id:
			return r
	return null


## The position the cutoff line sits UNDER, per the
## challenge type (0 = this type draws no line):
## - Battle Royale: under the last survivor - with N rows
##   the bottom 10 are cut, so the line falls under position
##   N-10. A board of 10 or fewer has cut nobody yet.
## - Season / Extra: the promotion line, under 8th - drawn
##   once the board holds at least 8 rows.
## - Monthly Contracts: completion-based, no line.
func cutoff_position() -> int:
	match type_code:
		TYPE_TOURNAMENT:
			if rows.size() > BATTLE_ROYALE_CUT:
				return rows.size() - BATTLE_ROYALE_CUT
			return 0
		TYPE_SEASON, TYPE_EXTRA:
			if rows.size() >= PROMOTION_LINE:
				return PROMOTION_LINE
			return 0
	return 0


## The divider's honest label for this challenge's line.
func cutoff_label() -> String:
	match type_code:
		TYPE_TOURNAMENT:
			return "CUT LINE - the %d below are out" % BATTLE_ROYALE_CUT
		TYPE_SEASON, TYPE_EXTRA:
			return "PROMOTION LINE - top %d move up" % PROMOTION_LINE
	return ""


## The rows the wall's board face shows, in board order:
## the leader, the rows around the cutoff line (the last
## row above it and the first below), and his row wherever
## it stands - each once, with the divider entry where the
## line falls. Entry shapes:
##   {"kind": "score", "row": WovpScoreRow, "mine": bool}
##   {"kind": "divider", "label": String}
##   {"kind": "note", "text": String} - he has no score yet
func board_rows(user_id: String) -> Array:
	var out: Array = []
	var cut: int = cutoff_position()
	var want: Array[int] = []
	if not rows.is_empty():
		want.append(1)
	if cut > 0:
		if not want.has(cut):
			want.append(cut)
		if cut + 1 <= rows.size() and not want.has(cut + 1):
			want.append(cut + 1)
	var mine: WovpScoreRow = his_row(user_id)
	if mine != null and not want.has(mine.position):
		want.append(mine.position)
	want.sort()
	for pos: int in want:
		var r: WovpScoreRow = _row_at(pos)
		if r == null:
			continue
		out.append({"kind": "score", "row": r, "mine": mine != null and r == mine})
		if cut > 0 and pos == cut:
			out.append({"kind": "divider", "label": cutoff_label()})
	if mine == null and user_id != "":
		out.append({"kind": "note", "text": "You have no score on this board yet"})
	return out


func _row_at(position: int) -> WovpScoreRow:
	for r: WovpScoreRow in rows:
		if r.position == position:
			return r
	return null


## Scores print the way pinball prints them: grouped, no
## decimals on a whole number (the league carries doubles;
## a fractional score - none is known - keeps its cents).
static func format_score(score: float) -> String:
	var whole: int = int(score)
	var text: String = str(absi(whole))
	var grouped: String = ""
	while text.length() > 3:
		grouped = "," + text.right(3) + grouped
		text = text.left(text.length() - 3)
	grouped = text + grouped
	if whole < 0:
		grouped = "-" + grouped
	var frac: float = absf(score - float(whole))
	if frac > 0.0001:
		grouped += ("%.2f" % frac).trim_prefix("0")
	return grouped
