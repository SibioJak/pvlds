class_name WovpScoreRow
extends RefCounted

## One row of a World of Virtual Pinball scoreboard, as the
## league's API carries it (response model: VPin Studio's
## ScoreBoardItem + ScoreBoardItemPositionValues, mirrored in
## the scores spike, FINDINGS.md). Pure data - the client
## parses, the room renders, neither invents.
##
## approval_status WAS an opaque integer until the
## read-back spike (pvlds-wovp-spike/FINDINGS.md) read the
## vocabulary out of the site's own JS: 0 NotSet,
## 1 Submitted, 2 Approved, 3 Pending, 4 Refused,
## 5 Cancelled. The wall's board rows still key their
## "awaiting validation" words off is_pending (the league's
## own flag - the score is in but not yet validated); the
## SUBMITPANEL read-back is the one surface that reads
## approval_status for meaning (Room._rb_recorded_line).

var position: int = 0 ## 1-based board position
var score: float = 0.0 ## the league carries scores as doubles
var participant_name: String = ""
var user_id: String = "" ## the league's player id - how the wall knows which row is HIS
var division: String = ""
var country_code: String = ""
var profile_picture: String = "" ## avatar URL as carried (may be empty); the wall does not fetch it in this round
var platform: int = 0 ## the server's playingPlatform vocabulary is unknown (spike §8) - carried, never interpreted
var approval_status: int = 0 ## the site's vocabulary - see the class note
var is_pending: bool = false
