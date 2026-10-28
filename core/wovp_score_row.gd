class_name WovpScoreRow
extends RefCounted

## One row of a World of Virtual Pinball scoreboard, as the
## league's API carries it (response model: VPin Studio's
## ScoreBoardItem + ScoreBoardItemPositionValues, mirrored in
## the scores spike, FINDINGS.md). Pure data - the client
## parses, the room renders, neither invents.
##
## approval_status is an OPAQUE integer: the spike found no
## source anywhere that says what its values mean, so PVLDS
## carries the number and never interprets it. is_pending is
## the league's own flag (the score is in but not yet
## validated) and is the only lifecycle fact the wall states.

var position: int = 0 ## 1-based board position
var score: float = 0.0 ## the league carries scores as doubles
var participant_name: String = ""
var user_id: String = "" ## the league's player id - how the wall knows which row is HIS
var division: String = ""
var country_code: String = ""
var profile_picture: String = "" ## avatar URL as carried (may be empty); the wall does not fetch it in this round
var platform: int = 0 ## the server's playingPlatform vocabulary is unknown (spike §8) - carried, never interpreted
var approval_status: int = 0 ## OPAQUE - see the class note
var is_pending: bool = false
