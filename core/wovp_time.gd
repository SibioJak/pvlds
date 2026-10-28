class_name WovpTime
extends RefCounted

## Clock math for the Tournament Room: WoVP deadlines arrive
## in UTC and the player reads them in America/Chicago (his
## league deadlines are Sundays 19:00 UTC). Godot has no
## timezone database, so the Central rules are stated plainly
## here: CDT (UTC-5) runs from the second Sunday of March at
## 2:00 local (08:00 UTC) to the first Sunday of November at
## 2:00 local (07:00 UTC); CST (UTC-6) otherwise - the US
## rules in force since 2007. Pure functions of a unix time,
## so the core test can pin known conversions exactly.

const CDT_OFFSET: int = -5 * 3600
const CST_OFFSET: int = -6 * 3600

const WEEKDAYS: Array[String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## The unix instant (UTC) of the n-th Sunday of a month at a
## given UTC hour - how the DST edges are located.
static func _nth_sunday_unix(year: int, month: int, n: int, utc_hour: int) -> int:
	var first: int = Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var wd: int = int(Time.get_datetime_dict_from_unix_time(first)["weekday"]) ## 0 = Sunday
	var first_sunday_day: int = 1 + ((7 - wd) % 7)
	var day: int = first_sunday_day + (n - 1) * 7
	return Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day, "hour": utc_hour, "minute": 0, "second": 0})


## Chicago's UTC offset, in seconds, at a unix instant.
static func central_offset_seconds(unix_time: int) -> int:
	var year: int = int(Time.get_datetime_dict_from_unix_time(unix_time)["year"])
	var dst_start: int = _nth_sunday_unix(year, 3, 2, 8) ## 2nd Sun of March, 08:00 UTC
	var dst_end: int = _nth_sunday_unix(year, 11, 1, 7) ## 1st Sun of November, 07:00 UTC
	if unix_time >= dst_start and unix_time < dst_end:
		return CDT_OFFSET
	return CST_OFFSET


static func is_dst(unix_time: int) -> bool:
	return central_offset_seconds(unix_time) == CDT_OFFSET


## The Chicago wall clock at a unix instant, as a datetime
## dictionary (the UTC dictionary of the shifted instant).
static func to_central(unix_time: int) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(unix_time + central_offset_seconds(unix_time))


static func _clock_12h(d: Dictionary) -> String:
	var hour: int = int(d["hour"])
	var ampm: String = "AM" if hour < 12 else "PM"
	var h12: int = hour % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, int(d["minute"]), ampm]


## "Sun Oct 25, 2:00 PM CDT" - a deadline in the player's own
## clock, the shape the wall shows beside the time remaining.
static func format_deadline(unix_time: int) -> String:
	var d: Dictionary = to_central(unix_time)
	return "%s %s %d, %s %s" % [
		WEEKDAYS[int(d["weekday"])], MONTHS[int(d["month"]) - 1], int(d["day"]),
		_clock_12h(d), "CDT" if is_dst(unix_time) else "CST"]


## "Oct 28, 10:41 AM CDT" - the last-updated stamp's shape.
static func format_stamp(unix_time: int) -> String:
	var d: Dictionary = to_central(unix_time)
	return "%s %d, %s %s" % [
		MONTHS[int(d["month"]) - 1], int(d["day"]),
		_clock_12h(d), "CDT" if is_dst(unix_time) else "CST"]


## The time left until a deadline, in words a glance can use:
## "2d 4h left", "4h 12m left", "12m left", "ended".
static func format_remaining(end_unix: int, now_unix: int) -> String:
	var left: int = end_unix - now_unix
	if left <= 0:
		return "ended"
	var days: int = left / 86400
	var hours: int = (left % 86400) / 3600
	var mins: int = (left % 3600) / 60
	if days > 0:
		return "%dd %dh left" % [days, hours]
	if hours > 0:
		return "%dh %dm left" % [hours, mins]
	if mins > 0:
		return "%dm left" % mins
	return "under a minute left"
