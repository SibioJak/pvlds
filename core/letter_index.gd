class_name LetterIndex
extends RefCounted

## The alphabet strip's one title mathematics (the letter-jump
## round, 2026-10-27): which letter a game files under, whether
## it belongs to the THE net, and whether it belongs to the "#"
## net. Pure functions over GameEntry.title - the ONE title the
## wall sorts and displays (the db's name for a matched game,
## the scanner's cleaned file title for a filename-only one).
## No second title notion is invented here.
##
## The sort title is the title with a leading "The " removed -
## the same leading-The drop the matcher applies to both sides
## of a comparison (VpsDatabase.scrub_tokens), so the letter a
## game files under is the letter its match key starts with.
## "The Addams Family" files under A. The THE net is a NET, not
## a move: membership is read off the canonical title ("The "
## and a word after it) while the game keeps its post-The
## letter - the strip's THE slot shows the set, it never
## rehomes it. A title whose sort title starts with no A-Z
## letter at all (digits, symbols: "8 Ball", "The 5th Element",
## "'Roid Belt Racers") files under "#".

## Negative-control seam (the letters smoke's PVLDS_LJ_NC=
## nostrip): when set, sort_title stops stripping, so every
## canonical-The game files under T and the smoke's
## canonical-The legs fail by name. Production never sets it.
static var debug_disable_the_strip: bool = false


## The title the wall's name sort orders by, and the letter is
## read from: a leading "The " (any case) drops, exactly the
## matcher's treatment. A bare "The" with no word after it is
## not stripped - there is nothing to file it under but T.
static func sort_title(title: String) -> String:
	if debug_disable_the_strip:
		return title
	if is_the_title(title):
		return title.substr(4).strip_edges()
	return title


## True when the canonical title is "The " plus a word: the
## THE net's membership test. "Theatre of Magic" is NOT a
## member - "The" must be its own word.
static func is_the_title(title: String) -> bool:
	if not title.to_lower().begins_with("the "):
		return false
	return title.substr(4).strip_edges() != ""


## The letter a game files under: the first character of its
## sort title, uppercased, when that is A-Z; "#" otherwise
## (digits, symbols, and the empty title all land there).
static func letter_of(title: String) -> String:
	var s: String = sort_title(title).strip_edges()
	if s == "":
		return "#"
	var c: String = s.substr(0, 1).to_upper()
	if c.length() == 1 and c >= "A" and c <= "Z":
		return c
	return "#"


## Net membership: "THE" takes the canonical-The games, "#"
## takes the non-letter starters, anything else (including the
## empty net) takes nothing.
static func in_net(title: String, net: String) -> bool:
	if net == "THE":
		return is_the_title(title)
	if net == "#":
		return letter_of(title) == "#"
	return false


## The slot keys a game set lights up: each game's letter, and
## "THE" when any game is a canonical-The title. ("#" appears
## as a letter like any other.) Read by the strip twice over:
## across the whole library it decides whether the "#" slot is
## laid out at all, and across the current filter's collection
## it decides which slots are greyed.
static func presence_over(games: Array[GameEntry]) -> Dictionary:
	var out: Dictionary = {}
	for g: GameEntry in games:
		out[letter_of(g.title)] = true
		if is_the_title(g.title):
			out["THE"] = true
	return out


## The strip's ONE order: A-Z, then the THE net, then "#"
## when the library holds a non-letter title. This list is
## the single source of truth for the strip: the layout
## positions the slots in this order (left to right), the
## pad's sideways walk visits them in this order, the
## focusables list carries them in this order, and presence
## greys by these keys. "#" rides LAST - at the row's right
## end, after THE - because that is where the layout has
## drawn it since the strip's first build (the layout
## positions slots in build order, and "#" is built last).
## This function's first version claimed "#" led; the walk
## believed the list while the eye saw the drawing, so
## stepping right along the strip died at THE, one slot
## short of the drawn "#" - reachable only by travelling
## left, where the highlight leapt the row's full width to
## the far end (Chris's field report, 2026-10-27 - the
## strip-order fix).
static func slot_keys(has_number: bool) -> Array[String]:
	var out: Array[String] = []
	for i: int in range(26):
		out.append(String.chr(65 + i))
	out.append("THE")
	if has_number:
		out.append("#")
	return out
