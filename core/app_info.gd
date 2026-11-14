class_name AppInfo
extends RefCounted

## The product's identity, in one home (AUTOFIND, FINISH LINE
## stage 1): the name the installer and the manual will carry,
## the product version the desk foot states and the update
## check compares against, and the version feed's fixed URL.
## Stage 3 (the installer/distribution) settles the feed's
## real home - the constant is one line to move.

const PRODUCT_NAME: String = "LaunchPin VR"
const PRODUCT_VERSION: String = "1.1.9"
## PANEL112 (item 1): the feed's home is the PUBLIC releases
## repo (SibioJak/launchpin-vr) - the source repo stays
## private (Chris's ruling), and a private repo's raw file
## would 404 for the shipped checker anyway. The releases
## repo carries version.json at its root on its main branch.
const UPDATE_FEED_URL: String = "https://raw.githubusercontent.com/SibioJak/launchpin-vr/main/version.json"


## Dotted-int compare: -1 when a < b, 0 when equal, 1 when
## a > b. Parts compare as integers ("1.10" > "1.9"); a
## missing part reads as 0 ("1.0" == "1.0.0"); a part with
## no leading digits reads as 0. Pure - the floor pins it.
static func compare_versions(a: String, b: String) -> int:
	var pa: PackedStringArray = a.strip_edges().split(".")
	var pb: PackedStringArray = b.strip_edges().split(".")
	var n: int = maxi(pa.size(), pb.size())
	for i: int in n:
		var va: int = _part(pa, i)
		var vb: int = _part(pb, i)
		if va != vb:
			return -1 if va < vb else 1
	return 0


static func version_is_newer(candidate: String, current: String) -> bool:
	return compare_versions(candidate, current) > 0


static func _part(parts: PackedStringArray, i: int) -> int:
	if i >= parts.size():
		return 0
	var s: String = parts[i].strip_edges()
	var digits: String = ""
	for ch: String in s:
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	return digits.to_int() if digits != "" else 0
