class_name RoomView
extends Node3D

## The room: the planetarium drum (the graduation round,
## 2026-10-29 - the DOME prototype, field-approved across
## DOME1-DOME5, becomes PVLDS's room). The library stands on
## a spherical drum around the player: three bands on a
## sphere of WALL_RADIUS, column-major in the standing sort
## order, the drum swinging so the focused column faces the
## player. Around it, the furniture the wall always had: the
## control rail, the alphabet strip, the detail view, the
## SETUP panel and placard, the loading marquee, the
## Tournament Room's boards (which ride the drum at their
## own size), and the power-on mimic. One input model for
## every hand: the PointerRig (VR laser / mouse ray) plus
## gamepad-and-keyboard focus navigation over the same set
## of ClickableQuads.

signal setup_requested
signal setup_placard_dismissed ## the setup placard's BACK: Main closes the desk it opened alongside
signal setup_panel_scan_requested ## the SETUP panel's SCAN LIBRARY: Main owns the scan machinery
signal setup_panel_ipdb_requested ## CARDBACK/IPDBFIX: the SETUP panel's RE-APPLY IPDB DATA: Main re-applies the bundled snapshot to the cache (no fetch exists)
signal launch_requested(game: GameEntry, build: TableBuild) ## card Launch / detail Play - Main owns the launch + exit
signal exit_requested ## rail EXIT: Main disarms the watchdog and quits
signal art_prefetch_requested(games: Array) ## a page settled: Main's warmer should bring the neighbouring pages' art forward
signal tournament_refresh_requested ## the Tournament Room wants its boards (re)fetched: entering the view, or REFRESH pressed - Main owns the WoVP client
signal wovp_key_pasted(api_key: String) ## the SETUP panel's PASTE KEY read a key off the clipboard: Main saves it to the config
signal wovp_key_test_requested ## the SETUP panel's TEST KEY: Main validates the saved key and reports whose it is
signal wovp_submit_requested(challenge_id: String, photo_path: String) ## ROOMSUBMIT: the submit panel's SEND: Main runs the same two-step WoVP submission the desk runs (its refusals, its log, its boards refresh) and answers through set_wovp_submit_result
signal display_settings_changed ## a SETUP display dial turned (the starfield): Main persists the room's standing values to the config

const PAGE_COLS: int = 4
const PAGE_ROWS: int = 3
const PAGE_SIZE: int = PAGE_COLS * PAGE_ROWS
static var WALL_RADIUS: float = 3.60 ## OPTIMIZE round: 3.40 -> 3.60, locked by Chris, fixed, no dial. GRADFIX5 (item 4) history: the wall pushed back a step from the dome's 3.05 (the user's ask: "push back a bit, fit a few more cards into your central vision"). +0.35 m (+11%): the census's wall measure reads the centre card at 10.72 degrees across against 11.98 on the old radius (same arithmetic both sides), the air between columns grows from ~1.5 to ~2.8 degrees, and every drawn column's frame overflow shrinks - while the column CENTRES stay pitch-fixed at 13.5 degrees, so the step buys size and air, not new columns. The step is also item 1's headroom: the flush book floats 0.30 proud of a 3.40 wall - 3.10 from the eye, the old wall's own distance - so the full-height page spans inside its band pitch. Cards keep their physical size; everything seated on the wall (book, fins, tournament block, pop) derives from this one value and re-seats with it. A static, not a const, so the harness's oldwall NC can restore the shipped geometry wholesale.
static var WALL_LIFT: float = 0.06 ## GRADFIX5 (item 4): the wall's rise with its push-back - the seats ride a sphere around the eye, so the farther wall's bottom band hangs lower; the lift keeps its labels and nameplates on the heights the field-passed build held them at (the census's floor datum is the retired floor slab's old surface).
const EYE: Vector3 = Vector3(0.0, 1.25, 0.0)
const FILTERS: Array[String] = ["all", "vr", "favorites", "recents", "new"]
const FILTER_LABELS: Dictionary = {"all": "ALL", "vr": "VR", "favorites": "FAVORITES", "recents": "RECENTS", "new": "NEW"}
const SORTS: Array[String] = ["name", "year", "manufacturer", "designer"]
const SORT_LABELS: Dictionary = {"name": "NAME", "year": "YEAR", "manufacturer": "MAKER", "designer": "DESIGNER"}

# ------------------------------------------------------- loading marquee
## The load wait's headline. Chris: "I have 50 years of hating
## loading screens" - so this is NOT a loading screen: no spinner,
## no progress bar, no percentage, no LOADING text. While a table
## loads, the wall of cards fades down and the launched table's
## year, with its designer beneath, flies in from the wall in big
## marquee letters, settles at reading distance, and holds with a
## gentle pulse until the wait settles. Every feel knob is a
## constant here, for one-line retunes after Chris's verdict.
const MARQUEE_FADE_SEC: float = 0.6 ## wall fade-down duration
const MARQUEE_WALL_ALPHA: float = 0.16 ## the wall's alpha while the marquee stands
const MARQUEE_FLY_IN_SEC: float = 1.4 ## the letters' travel time, wall -> settle
static var MARQUEE_START_Z: float = -3.60 ## fly-in start depth (at the wall - tracks WALL_RADIUS; a static beside it so the oldwall NC restores both)
const MARQUEE_SETTLE_POS: Vector3 = Vector3(0.0, 1.42, -2.30) ## reading distance, on the view axis (retuned 2026-10-22: first pass sat too close)
const MARQUEE_PIXEL_SIZE: float = 0.005 ## Label3D world scale
const MARQUEE_YEAR_FONT_SIZE: int = 110 ## retuned 2026-10-22: 170 read too big in the headset
const MARQUEE_NAME_FONT_SIZE: int = 56 ## the designer/title line (Chris's "date and designer"); 84 -> 56 in the same retune
const MARQUEE_YEAR_Y: float = 0.30 ## year line's offset from the holder's centre
const MARQUEE_NAME_Y: float = -0.34 ## designer/title line's offset
const MARQUEE_PULSE_RATE: float = 1.6 ## settle pulse, cycles per second
const MARQUEE_PULSE_AMOUNT: float = 0.025 ## settle pulse, scale amplitude
## NEXTROUND (item 2): the marquee's type treatment joins
## the frameless graphite house look (the filter strip /
## SETUP furniture language) - the year takes the strip's
## lifted-label white and the designer line its resting
## label grey (RoomSpecs.STRIP_LABEL_ACCENT / _REST, the
## same values), and the heavy display outline gives way
## to a graphite hairline that only keeps the letters
## defined over bright art. Presentational only: sizes,
## positions, the fly-in and the pulse are untouched.
const MARQUEE_YEAR_COLOR: Color = Color(0.847, 0.867, 0.910) ## = RoomSpecs.STRIP_LABEL_ACCENT (#d8dde8)
const MARQUEE_NAME_COLOR: Color = Color(0.659, 0.678, 0.722) ## = RoomSpecs.STRIP_LABEL_REST (#a8adb8)
const MARQUEE_OUTLINE_COLOR: Color = Color(0.102, 0.106, 0.122) ## the strip gradient's deep graphite family (#1a1c20)
const MARQUEE_OUTLINE_SIZE: int = 8

## Card pop-out (Chris, 2026-10-22): the card under the pointer -
## or holding gamepad/keyboard focus - lifts off the wall toward
## the viewer with depth from its neighbours. Only the one card
## is ever popped; focus loss settles it back flush.
const POP_OUT_DISTANCE: float = 0.15 ## metres off the shelf at full pop
const POP_OUT_SCALE: float = 1.04 ## card scale at full pop (DOME5's trim: 1.08 -> 1.04 so the popped frame's top clears the label above - see the dome constants below)
const POP_OUT_SEC: float = 0.15 ## the pop's core travel time, seconds: the spring below reaches ~90% home in this span (its soft landing tail runs a little longer - GRADFIX10 item 2)
const POP_SPRING_TAU: float = 0.055 ## the pop spring's time constant (GRADFIX10 item 2 - see _update_pop): the critically damped spring that replaced the fixed linear ramp whose visible frame count collapsed with frame pacing
const POP_MAX_STEP_SEC: float = 1.0 / 30.0 ## the pop's per-frame step clamp (GRADFIX10 item 2): a hitch frame may slow the pop, never skip its poses - the spring integrates at most this much time per frame

## Card proportions (the graduation round): the drum's cards
## stand at the prototype's proven size - CARD_SIZE below,
## portrait, the author screenshot's own shape (aspect
## ~0.562). The old wall's median-aspect grid tune and the
## pop's true-aspect width grow are RETIRED with the wall:
## the dome's pop is one uniform scale (DOME5's clearance
## proof was measured against exactly that), and a uniform
## grid is what lets 300+ cards share one shelf geometry.

## Power-on (the swap round, 2026-10-27): the snippet-layer
## cascade is RETIRED - four field ghosts in a row were one
## more value of the file's own taxonomy the compositor did
## not honor (solenoid flashers held as lamps, animation
## frames stacked, GI circuit washes, transparent quads
## sorting in camera order), and the stack is deleted, not
## dormant. What performs now is the MIMIC: one shader quad
## over the focused card's face, grading the face's own
## pixels through a lamp-catch envelope and a diagonal
## sweep (ui/mimic_power.gdshader) - the power-on the mimic
## prototype proved on the real Taxi, Goonies and Bride
## faces, with a soft shoulder added so bright printed art
## cannot clip. A pair card crossfades the whole picture to
## the author's On image instead; its settled state carries
## no synthesized grade. Every face class gets the same
## performance - B2S, embedded, sidecar, title card -
## because the shader samples the face the card already
## wears, and no extraction or file work happens on focus.
## One card ever performs; focus leaving restores the
## plain face. No audio. Every feel knob is a constant
## here or a uniform default in the shader.
const POWER_SETTLE_SEC: float = 0.2 ## focus must rest this long before the power-on starts
const POWER_CASCADE_SEC: float = 1.05 ## the power-on's full run, seconds
const MIMIC_SHADER: Shader = preload("res://ui/mimic_power.gdshader")
## The catch envelope's keyframes [seconds, power]: three
## stuttering catches across 0.06-0.27 s, a sag dip to 0.62
## at 0.34 s, full by 0.48 s, held to the cascade's end.
## Read by mimic_power_at - the prototype's proven curve.
const MIMIC_POWER_KEYS: Array = [
	[0.0, 0.0], [0.06, 0.50], [0.10, 0.15], [0.16, 0.68],
	[0.21, 0.30], [0.27, 0.88], [0.34, 0.62], [0.48, 1.0],
	[1.05, 1.0],
]
const MIMIC_SWEEP_SEC: float = 0.79 ## the diagonal sweep front completes at this cascade second
const PAIR_MIX_T0: float = 0.40 ## cascade second where a pair card's crossfade to its On image begins (it completes at the cascade's end)

## Page slide (the bumper feel round, 2026-10-24 - Chris, on the
## bumper flip: "it snaps to next wall, which is great, its fast,
## but i need some kind of visual doodad, a quick blur or
## something"). A page change rides a short out-and-back yaw of
## the whole wall around the player's vertical axis: the wall
## glides toward the travel direction (NEXT sweeps the content
## leftward, PREV the mirror), the page content swaps at the far
## point, and the wall glides back to exact rest - about a
## quarter second end to end, the state change itself landing in
## one frame at the far point. The rail never rides the slide:
## it is furniture and stands still (see _apply_rail_textures).
## The alphabet strip (the letter-jump round, 2026-10-27 -
## Chris: "a way to quickly get to a specific letter in the
## list of titles", with his addition: "an extra slot for
## games that start with THE (or are missing THE)"). A row of
## letter slots riding under the control rail - furniture,
## like the rail: built once, persistent across rebuilds,
## dressed from its own texture cache. A letter files by its
## sort title (LetterIndex: a leading "The " drops, the
## matcher's own convention), so The Addams Family lives
## under A. Letters with no games in the current filter's set
## render dim and are not stops at all. Picking a letter
## quietly switches to title sort and lands the wall on that
## letter's first page, focus on its first card. The THE slot
## (and "#" for the number/symbol starters, laid out only
## when the library holds one) is a NET, not a move: it shows
## exactly its games, sorted by the word after "The", and the
## games keep their own letters - picking any letter exits
## the net at that letter. The strip is its own focus country
## beside the rail's: sideways travel walks the strip's own
## order, and the two rows trade places only vertically.
const STRIP_Y: float = 0.045 ## the strip row's height (the rail rides at 0.225 above it). GRADFIX6 (Console pass 2): lowered from 0.0825 for vertical air - see the Console block below for the gap arithmetic and the status-plate sight-line check.
const STRIP_Z: float = -1.62 ## the rail's depth: the strip is rail furniture
## The Console bar (GRADFIX5 item 3, the user's pick - variant
## A of the bar mocks: "the current bar, disciplined - pulled
## in"): the whole desk rail tightened to ~70% of its former
## span. The rail's tiles carry widths x0.72 with the gaps
## closed 0.035 -> 0.018 and the tile height 0.15 -> 0.135
## (see _build_rail); the strip's pads condense to sit WITHIN
## the bar's new span (0.095 -> 0.080 wide, THE 0.21 -> 0.175,
## height 0.13 -> 0.10, gap 0.014 -> 0.010); the status plate
## slims to one line tucked under the bar (see
## _build_status_line). Nothing is dropped and no behaviour
## changes - focus laws, bumper anchors, THE-as-net, the
## pager all ride the same quads; only the furniture's
## measurements moved. Faces render on fixed canvases, so a
## smaller quad carries proportionally smaller type - the
## mock's discipline, not a font change. The pre-fix wide
## bar stands behind the harness's negative-control seam
## (PVLDS_GRADFIX5_NC=widebar) so the census's console leg
## can fail against it by name.
##
## Console pass 2 (GRADFIX6 item 4, the GRADFIX5 field
## verdict: "in the headset the bar is almost, not quite,
## all in view" + more air between the rows + slimmer
## tiles): the rail tightens once more, widths x0.90 on the
## GRADFIX5 defs - span 2.964 -> 2.687 m. At the rail's
## depth (z -1.62 from the eye) that span's total angular
## width is 2*atan(1.3435/1.62) = 79.3 degrees, against
## 84.9 degrees for GRADFIX5's 2.964 and 105.0 for the
## pre-Console 4.225 - the ends pull ~2.8 degrees a side
## toward the centre of the view. Tiles slim too:
## RAIL_TILE_H 0.135 -> 0.115, strip pads 0.100 -> 0.085
## tall and a hair narrower (letters 0.080 -> 0.078, THE
## 0.175 -> 0.170), so the strip's span (2.546 m with "#"
## laid out) still sits inside the rail's. The strip row
## moves DOWN for air (STRIP_Y 0.0825 -> 0.045; the rail
## cannot move up - its top edge is census-bound against
## the bottom-band labels): rail bottom 0.1675 (centre
## 0.225, tile 0.115) minus strip top 0.0875 (centre
## 0.045, pad 0.085) leaves a 0.080 m gap, 3.2x the
## GRADFIX5 rows' 0.025. The status plate does NOT move:
## at its seat (y 0.09, z -1.30) its top edge rides at
## 40.6 degrees of depression from the eye, while the
## lowered strip's bottom edge rides at 37.6 - a 3.0
## degree sight-line clearance, and the two never share
## ground. The widebar NC still restores the PRE-Console
## bar wholesale (4.225 m), so it still convicts pass 2
## by name. Nothing dropped at pass 2: 12 rail stops, 28
## strip slots (A-Z, THE, #) - bar_state counts them.
## GRADFIX8 (item 6, Chris's order) drops the two pager
## stops from the rail: TEN entries stand from here
## (bar_state's rail_stops reads 10), span 2.417 m; the
## page readout stays (see _build_rail).
## GRADFIX11 (Chris's order): ELEVEN entries stand from
## here (bar_state's rail_stops reads 11), span 2.591 m -
## the NEW filter tile joins the rail beside RECENTS.
const STRIP_LETTER_SIZE: Vector2 = Vector2(0.076, 0.085) ## GRADFIX8 (item 6): letters 0.078 -> 0.076 and STRIP_GAP 0.010 -> 0.006 - the pager removal shortens the rail to 2.417 m, and the strip condenses the last hair (span 2.546 -> 2.384 m) so the Console law - the strip sits WITHIN the rail's span - survives the tightening instead of being amended away
const STRIP_THE_SIZE: Vector2 = Vector2(0.170, 0.085)
const STRIP_GAP: float = 0.006
const STRIP_LETTER_SIZE_WIDE: Vector2 = Vector2(0.095, 0.13) ## the pre-Console strip (the widebar NC's restore)
const STRIP_THE_SIZE_WIDE: Vector2 = Vector2(0.21, 0.13)
const STRIP_GAP_WIDE: float = 0.014
const RAIL_TILE_H: float = 0.115 ## the Console rail's tile height, pass 2 (GRADFIX5 0.135, pre-Console 0.15)
const RAIL_GAP: float = 0.018 ## the Console rail's inter-tile gap (pre-Console 0.035)
## GRADFIX14 (item 1, Chris's order): the rail's per-tile
## boxes are REPLACED by one machined graphite strip - "no
## individual boxes, it looks like a mess. One long strip
## with the category sections, made to look like buttons.
## when you highlight one, it pops up 3d and sinks back down
## when you move on by." Chris's mock pick: Machined Strip,
## GRAPHITE (see RoomSpecs' STRIP_* palette, hex for hex
## from the chosen mock). The strip keeps the shipped rail's
## exact sections, order, relative widths, labels, seat,
## span (2.591 m) and height: the sections sit CONTIGUOUS
## (no gaps - the old 0.018 m gaps are absorbed into the
## sections at their shipped proportions), seams are ETCHED
## into the bar's face between sections, and ONE continuous
## backing bar (the same graphite, a hair behind the faces)
## guarantees the bar reads whole even while a section is
## lifted off it. Focus lifts exactly one section toward
## the viewer on the pop spring's discipline (see
## _update_rail_lift). The tileboxes NC
## (PVLDS_GF14_NC=tileboxes - the same env var as item 3's
## grammar seams, a distinct value) restores the shipped
## per-tile boxes wholesale - gaps, button faces, frames, no
## bar, no lift - so the machined-strip census legs fail
## by name.
const RAIL_STRIP_LIFT: float = 0.032 ## the focused section's rise toward the viewer, metres (the mock's ~5 px lift at its bar's scale, translated: ~28% of the bar's height, in the pop spring's character - proud enough to read as the bar's own material rising, far short of the cards' 0.15 pop)
const RAIL_STRIP_PX_PER_M: float = 1800.0 ## the strip faces' render density: each section renders at its own aspect (no stretch - the shipped tiles stretched one 512x150 canvas over every width), 207 px tall for the 0.115 bar

## ------------------------------------------------------------ the drum
## The dome's geometry, ported from the field-approved
## prototype (pvlds-dome-prototype, DOME1-DOME5) number for
## number: cards on a sphere of WALL_RADIUS around EYE, in
## three bands; consecutive games run along the TOP band,
## then the middle, then the bottom (column-major: a game's
## column is its index along its band). Only the columns
## within VISIBLE_HALF_COLUMNS of the focused column are
## drawn - the shelf is long (his ~356 games make ~119
## columns, ~1600 degrees of arc) and its ends stand bare
## (the DOME3 bookend fins were removed at GRADFIX8 item 5).
const ROW_ELEVATIONS: Array[float] = [25.0, 5.0, -15.0] ## band elevations in degrees: top, middle, bottom
const ANGLE_STEP_DEG: float = 13.5 ## column pitch, degrees
const VISIBLE_HALF_COLUMNS: int = 10 ## drawn columns either side of the focused column
const CARD_SIZE: Vector2 = Vector2(0.62, 1.08) ## the card face, metres - the author screenshot's portrait shape
const CARD_FRAME_SIZE: Vector2 = Vector2(0.68, 1.10) ## the frame quad behind the face (DOME5's trimmed height)
const CARD_FACE_PX: Vector2i = Vector2i(496, 864) ## the production card-face size (GRADFIX19 restores it: GF18-HALFRES halved it to 248x432 as a diagnostic only - that variable never ships); card faces render at the card's own aspect (0.574)
## GRADFIX8 (item 4): the tournie border - a live-challenge
## card's animated ring, standing OUTSIDE the card's own
## frame (0.68 x 1.10) with a small air gap, inside the
## shelf's pitches (13.5 deg columns = 0.80 m of arc and
## 20 deg bands = 1.19 m at WALL_RADIUS, against the
## border's 0.75 x 1.16). One ring quad per card, parented
## to the card's flip pivot (see _make_card_nodes), drawn
## by the shared shader below: the ring is the type colour
## (RoomSpecs.challenge_type_color of the SOONEST-CLOSING
## live challenge on that game - see tourney_border_map),
## and two sheen heads travel its perimeter off the
## engine's TIME, so the motion costs zero per-frame CPU
## per card and never gates input. Everything else about
## the card is untouched (the scenery-quiet / headline-loud
## law: the border IS the headline).
const TOURNEY_BORDER_OUTER: Vector2 = Vector2(0.75, 1.16) ## the ring quad's size, metres
const TOURNEY_BORDER_INNER: Vector2 = Vector2(0.69, 1.11) ## the ring's inner cut, metres (stroke 0.030 sides / 0.025 top-bottom)
const TOURNEY_BORDER_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform vec3 border_color : source_color = vec3(0.15, 0.30, 0.55);
uniform float global_alpha = 1.0;
uniform vec2 outer_size = vec2(0.75, 1.16);
uniform vec2 inner_size = vec2(0.69, 1.11);
void fragment() {
	vec2 v = (UV - 0.5) * outer_size;
	vec2 hv = outer_size * 0.5;
	vec2 hi = inner_size * 0.5;
	if (abs(v.x) < hi.x && abs(v.y) < hi.y) {
		discard;
	}
	float W = outer_size.x;
	float H = outer_size.y;
	float P = 2.0 * (W + H);
	float nx = abs(v.x) / hv.x;
	float ny = abs(v.y) / hv.y;
	float d;
	if (nx > ny) {
		if (v.x > 0.0) {
			d = W + (v.y + hv.y);
		} else {
			d = 2.0 * W + H + (hv.y - v.y);
		}
	} else {
		if (v.y < 0.0) {
			d = v.x + hv.x;
		} else {
			d = W + H + (hv.x - v.x);
		}
	}
	float head = mod(TIME * 0.45, P);
	float cd = abs(d - head);
	cd = min(cd, P - cd);
	float head2 = mod(head + P * 0.5, P);
	float cd2 = abs(d - head2);
	cd2 = min(cd2, P - cd2);
	float sheen = smoothstep(0.17, 0.0, cd) + 0.75 * smoothstep(0.17, 0.0, cd2);
	float breathe = 0.94 + 0.06 * sin(TIME * 1.7);
	vec3 col = border_color * breathe;
	col = mix(col, vec3(1.0), clamp(sheen, 0.0, 1.0) * 0.8);
	col += vec3(sheen * 0.12);
	ALBEDO = col;
	ALPHA = global_alpha;
}
"""
const LABEL_STRIP_Y: float = -0.30 ## the nameplate strip's centre, card-local metres (DOME5: raised from -0.47)
const LABEL_STRIP_SIZE: Vector2 = Vector2(0.62, 0.135) ## the nameplate's dark plate behind the title
const LABEL_PIXEL_SIZE: float = 0.0024 ## the title Label3D's world scale (the prototype's)
const LABEL_FONT_SIZE: int = 30
const LABEL_WIDTH_PX: float = 246.0 ## wrapped-title width: a long name takes up to four lines inside the plate's column (246px = 0.590 m of ink on the 0.62 m card - the block stands inside its own card with margin; was 255 = 0.612 m, its right edge flush with the silhouette - GRADFIX2 item 1)
## The swing: the drum eases to the focused column on a cubic
## ease-out; the duration grows with the travel (a letter
## jump's full-alphabet swing caps at 0.72 s) and input is
## NEVER gated by the motion - every step retargets from the
## drum's current angle (the prototype's speed-gate law).
const SWING_MIN_SEC: float = 0.16
const SWING_MAX_SEC: float = 0.72
## OPTIMIZE finish (hold cadence): after a swing lands, the
## drum rests this long before a QUEUED hold-repeat step may
## fire - the pause that makes a hold read as a train of
## discrete steps (settle plateaus between steps) instead of
## one blended glide. Only hold-repeats queue; taps and
## jumps retarget immediately, as they always have.
const STEP_REST_SEC: float = 0.10
## How soon the poll re-checks a queued hold-repeat step
## while it waits for the drum to land and rest.
const STEP_QUEUE_RECHECK_SEC: float = 0.03
## OPTIMIZE round: the SMOOTH driver is deleted - STEPPED (the
## spring above) is the only gait, and its constants die with it.

## Stage B - the background stack (all WORLD-LOCKED; see
## _build_background) and the focused card's flip.
const BG_STAR_RADIUS: float = 30.0 ## the starfield shell's radius around the eye
## (The orbit ring's radius const went with the ring -
## GRADFIX4 item 5e removed it, and the wireframe shell's
## radius const went with the shell - GRADFIX9 removed it;
## see _build_background.)
const HAZE_FLOOR: float = 0.45 ## the far window columns' dim floor (see _haze_for)
## The card flip (GRADFIX6 item 1 - Chris's design, back to
## the original concept after the wing/book line died in the
## GRADFIX5 field verdict: "the book look ain't working...
## still off-center, still butting into table art's
## business"): Y flips the focused card IN PLACE - the art
## face in front, the info the wing/book used to carry on
## the card's own back (RoomSpecs.wing_spec in the library,
## the TR3 board spec in the Tournament Room). The wing,
## the book, the hinge, the borrowed slots and the board's
## free-slot seating are DELETED: a card's back has no side
## to get wrong, covers no neighbour at any point of the
## motion (at mid-flip the card is edge-on inside its own
## slot), and never leaves its seat. The flip is a rotation
## about the card's own vertical centre axis on the quad's
## flip pivot (see ClickableQuad), at FLIP_SEC for the full
## half-turn - quick, neat, one clean ease (Chris: "earn a
## bagel on the quick, neat flip"). Input is never gated by
## the flip: the animation is cosmetic, presses land on the
## standing state. The NC seam PVLDS_GRADFIX6_NC=noflip
## makes Y inert, so the flip legs fail by name.
const FLIP_SEC: float = 0.30 ## the flip's full half-turn, seconds
## The starfield shaders (GRADFIX4 item 5, the sky pass): the
## field is computed from the fragment's DIRECTION in the
## shell's local space, hashed over 3D cells - never from the
## sphere's UV. The old UV grid pinched every cell into the
## poles (his field capture: looking straight up, the stars
## swirled into a point) and drew soft smoothstep blobs (his
## direction: pinpoint stars, small and hard). A direction
## field has no poles: density stays even looking straight
## up or down, the shell fully surrounds the viewer by
## construction, and a star is a hard pinpoint - a tight
## smoothstep whose edge is a fraction of its radius. The
## vertex stage carries the local position out; the shells
## are centred on the eye, so the normalized position IS the
## look direction.
const BG_STAR_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 deep_color : source_color = vec4(0.006, 0.008, 0.018, 1.0);
uniform float cells = 120.0;
uniform float density = 0.30;
uniform float star_radius = 0.10;
uniform float brightness = 0.9;
varying vec3 local_pos;
void vertex() {
	local_pos = VERTEX;
}
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
void fragment() {
	vec3 dir = normalize(local_pos);
	vec3 p = dir * cells;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	vec3 h = hash33(cell);
	vec3 spos = (hash33(cell + 19.19) - 0.5) * 0.72;
	float d = length(f - spos);
	float star = smoothstep(star_radius, star_radius * 0.35, d) * step(density, h.x);
	float shade = 0.5 + 0.5 * h.y;
	vec3 col = deep_color.rgb + vec3(0.90, 0.93, 1.0) * star * shade * brightness;
	// The milky band rides the direction's height now, not
	// the UV - it circles the room's equator at every yaw.
	float band = exp(-pow(dir.y * 3.2, 2.0));
	col += vec3(0.016, 0.021, 0.038) * band;
	ALBEDO = col;
}
"""
## The near star shell's shader: the same direction field,
## drawn stars-only (no sky of its own) so the far shell shows
## through between its nearer, brighter, sparser pinpoints -
## the two shells at 30 m and 12 m are the starfield's depth:
## under any head motion the layers parallax against each
## other (the wireframe shell that used to sit between
## them at 14 m was removed in GRADFIX9), and under
## the LAYERED dial both shells
## DRIFT on their own world-space rotations (see
## _update_background) - near faster than far, so a head turn
## sweeps both across the view opposite the turn, the near
## layer sweeping faster: direction-correct parallax, the
## user's own test for the drift.
const BG_STAR_NEAR_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform float cells = 52.0;
uniform float density = 0.42;
uniform float star_radius = 0.13;
uniform float brightness = 1.0;
varying vec3 local_pos;
void vertex() {
	local_pos = VERTEX;
}
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
void fragment() {
	vec3 dir = normalize(local_pos);
	vec3 p = dir * cells + vec3(37.7, 91.3, 53.1);
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	vec3 h = hash33(cell);
	vec3 spos = (hash33(cell + 19.19) - 0.5) * 0.72;
	float d = length(f - spos);
	float star = smoothstep(star_radius, star_radius * 0.35, d) * step(density, h.x);
	// No blend, no alpha: the shell is opaque and DISCARDS
	// every fragment that is not a star, so the far field
	// shows through the holes with plain depth. (The first
	// cut blended with a depth render mode the Compatibility
	// renderer refuses, so the shell never compiled there.)
	if (star < 0.35) {
		discard;
	}
	float shade = 0.55 + 0.45 * h.y;
	ALBEDO = vec3(0.90, 0.93, 1.0) * (star * shade * brightness);
}
"""
## The drift (GRADFIX4 item 5d): each star shell rotates
## about the viewer in WORLD space at its own slow angular
## speed - the near shell faster - so the field reads as
## floating through space and a head turn sweeps both layers
## across the view opposite the turn at their true relative
## rates. Positive rotation about +Y carries the forward
## stars leftward across the view: the room drifts rightward
## through the field. One steady direction, always; the
## drift never gates input, never moves the drum, pauses
## nothing. Only the LAYERED dial drifts - FLAT is a single
## static layer, OFF is none (see _update_background).
const BG_DRIFT_FAR_DEG: float = 0.20 ## the far shell's world-space drift, degrees per second
const BG_DRIFT_NEAR_DEG: float = 0.45 ## the near shell's world-space drift, degrees per second (faster: it is nearer)
## The pre-GRADFIX4 UV-grid star shaders, kept ONLY behind
## the sky NC (PVLDS_BG_NC=uv): the UV field pinches into the
## poles and draws soft blobs, so the sky legs (zenith,
## pinpoint) fail against it by name. Never shipped live.
const BG_STAR_SHADER_UV: String = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 deep_color : source_color = vec4(0.006, 0.008, 0.018, 1.0);
uniform vec2 grid_size = vec2(220.0, 110.0);
uniform float density = 0.82;
uniform float star_radius = 0.16;
uniform float brightness = 0.85;
float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	vec2 cell = floor(UV * grid_size);
	vec2 f = fract(UV * grid_size) - 0.5;
	float h = cell_hash(cell);
	vec2 star_pos = vec2(cell_hash(cell + 19.19), cell_hash(cell + 47.47)) - 0.5;
	float d = length(f - star_pos * 0.72);
	float star = smoothstep(star_radius, 0.0, d) * step(density, h);
	float shade = 0.55 + 0.45 * cell_hash(cell + 91.31);
	vec3 col = deep_color.rgb + vec3(0.90, 0.93, 1.0) * star * shade * brightness;
	ALBEDO = col;
}
"""
const BG_STAR_NEAR_SHADER_UV: String = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec2 grid_size = vec2(120.0, 60.0);
uniform float density = 0.86;
uniform float star_radius = 0.26;
uniform float brightness = 1.0;
float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	vec2 cell = floor(UV * grid_size) + vec2(37.7, 91.3);
	vec2 f = fract(UV * grid_size) - 0.5;
	float h = cell_hash(cell);
	vec2 star_pos = vec2(cell_hash(cell + 19.19), cell_hash(cell + 47.47)) - 0.5;
	float d = length(f - star_pos * 0.72);
	float star = smoothstep(star_radius, 0.0, d) * step(density, h);
	if (star < 0.35) {
		discard;
	}
	float shade = 0.55 + 0.45 * cell_hash(cell + 91.31);
	ALBEDO = vec3(0.90, 0.93, 1.0) * (star * shade * brightness);
}
"""
const BG_STAR_NEAR_RADIUS: float = 12.0 ## the near star shell's distance (the far shell rides BG_STAR_RADIUS, 30)

## The Launch button's seat on a card: the dome face carries
## NO name strip inside it (the nameplate rides on the card),
## so the button sits in the card's lower third, below the
## nameplate (the standard plate's bottom edge is at
## card-local y = -0.3675; the button's top edge at -0.4025).
## A card whose title wraps long grows its plate down over
## that seat (a four-line block bottoms at -0.502); its
## button moves to the card's top instead (PANEL_LAUNCH_Y_TOP)
## - the plate never shares ground with the button, on any
## card, by construction (see _make_card_nodes).
## GRADFIX13 (item 2): the Launch plinth is STRIPPED - these
## constants now serve only the plinth NC seam, which mints
## the buttons on their old seats so the strip's census can
## convict them. No shipped code seats a button by them.
const PANEL_SIZE: Vector2 = CARD_SIZE
const PANEL_LAUNCH_SIZE: Vector2 = Vector2(0.36, 0.115)
const PANEL_LAUNCH_Y: float = -0.47
const PANEL_LAUNCH_Y_TOP: float = 0.44
const SEATED_EYE_Y: float = 1.2 ## a seated player's eye height - the clearance QA camera

var _factory: TextureFactory
var _scanner: LibraryScanner
var _store: StateStore
var _xr_enabled: bool = false

var _filter: String = "vr" ## VR-suitable by default (design section 4).
var _filter_note: String = "" ## set when the empty-filter guard falls back to ALL
var _sort: String = "name"
var _page: int = 0
var wall_ready: bool = false ## true once the current wall's textures have all landed
var boot_centre_index: int = -1 ## the centre the boot itself chose (mid-shelf, or the restored selection) - set once in setup(), before any pointer or pad can move it
var boot_visible_count: int = 0 ## the view's size at that same moment (the shipped default filter is 'vr': the boot centre is the mid of THAT shelf)
var _boot_guard: bool = false ## the boot seating guard stands: the restore's seating (or the mid-shelf law's) may not be taken by a pointer that has not moved yet (see setup and _follow_centre)
var _boot_hover_sampled: bool = false ## the resting hover has been recorded (once the wall lands) as the guard's change reference
var _boot_hover_ref: ClickableQuad = null ## the hover the room opened with - the pointer's resting place, not its point
var _boot_focus_ref: ClickableQuad = null ## the focus the restore seated (setup's end)
var _boot_centre_ref: int = -1 ## the centre the restore seated (setup's end)
var _visible_games: Array[GameEntry] = []
var _gen: int = 0
var _mode: String = "wall" ## "wall" | "detail"

var _wall: Node3D  ## the drum: every card rides it; only it rotates
var _rail: Node3D
var _status_plate: MeshInstance3D  ## the banner's new home (a plate, not a quad)
var _status_label: Label3D
var _status_text: String = ""
var _detail: DetailView
var _rig: PointerRig
var _xr_camera: Camera3D
var _desk_rig: Node3D
var _desk_camera: Camera3D
var _panels: Array[ClickableQuad] = []
var _panel_launches: Array[ClickableQuad] = [] ## per-panel Launch button, parallel to _panels - GRADFIX13 (item 2): the plinths are stripped, so every entry is null in the shipped build; the plinth NC (PVLDS_GF13_NC=plinth) mints the buttons again and the entries go live
var _panel_back_launches: Array[ClickableQuad] = [] ## per-panel BACK Launch button (GRADFIX6 item 1: the flipped card's own Launch, on its back), parallel to _panels; null where a panel has no back - and, since GRADFIX13 item 2, null everywhere in the shipped build (the plinth NC mints it again)
var _panel_base_pos: Array[Vector3] = [] ## wall-flush position per panel, parallel to _panels
var _panel_pop_dir: Array[Vector3] = [] ## unit vector from the panel toward the viewer (its wall normal)
var _panel_pop: Array[float] = [] ## current pop amount per panel, 0 flush .. 1 popped
var _panel_pop_applied: Array[float] = [] ## last pop amount written to a panel's transform (write guard)
var _panel_pop_vel: Array[float] = [] ## pop spring velocity per panel (GRADFIX10 item 2), carried across retargets
var _panel_size: Vector2 = PANEL_SIZE ## the standing view's card size: CARD_SIZE, or the Tournament board size
var _panel_face_px: Vector2i = CARD_FACE_PX ## the panel faces' render size (CARD_FACE_PX, or the board's)
var _panel_art_aspect: Array[float] = [] ## per panel: its art's aspect (w/h) once its face lands, 0 = no art (title card)
var _panel_frames: Array[MeshInstance3D] = [] ## per panel: the card's frame quad (prototype geometry; amber while the card is the centre)
var _panel_plates: Array[MeshInstance3D] = [] ## per panel: the nameplate's dark plate behind the title label
var _panel_labels: Array[Label3D] = [] ## per panel: the title label on its nameplate
var _mat_frame_dark: StandardMaterial3D = null ## the cards' shared dark frame material
var _mat_frame_amber: StandardMaterial3D = null ## the centred card's amber frame material
var _mat_plate: StandardMaterial3D = null ## the shared nameplate/status plate material (the marquee fade drives its alpha)
var _window_fill_busy: bool = false ## a window face-fill pass is running (centre changes coalesce through _window_fill_dirty)
var _window_fill_dirty: bool = false
## GRADFIX16 (item 2) art pipeline state: the staged face
## fill that replaced the serial window fill on the travel
## path (see the pipeline block at _request_window_fill).
var _art_pipe_busy: bool = false ## a staged pipeline pass is running
var _art_pipe_queue: Array[int] = [] ## panel indices awaiting a staged face, centre-out order, revalidated at pop time
var _travel_dir: int = 0 ## COMPOSE-AHEAD: the last nonzero centre-column travel direction (-1/+1), witnessed by the window enqueue
var _ca_last_centre_col: int = -1 ## COMPOSE-AHEAD: the centre column the last enqueue saw (the direction witness's memory)
var _art_ahead_busy: bool = false ## COMPOSE-AHEAD: an ahead pass is running
var _ca_composed: int = 0 ## COMPOSE-AHEAD account: faces composed ahead this session
var _ca_gate_dropped: int = 0 ## COMPOSE-AHEAD account: ahead renders the reality gate refused (nothing put - arrival composes as it always did)
var _ca_decode_failed: int = 0 ## COMPOSE-AHEAD account: ahead asks whose art decode had failed (nothing put)
var _ca_raced: int = 0 ## COMPOSE-AHEAD account: ahead renders discarded because a window fill composed the same face while the render was in flight
var _art_pipe_in_stage: bool = false ## the pipeline is inside _fill_one_face_sync: its decode branch reads staged results instead of paying a synchronous decode
var _art_decode_pending: Dictionary = {} ## art path -> true while a background decode is queued for or in flight on the decode pump
var _art_decoded_ready: Dictionary = {} ## art path -> Image: a finished background decode awaiting texture creation on the pipeline's own frames
var _art_decoded_failed: Dictionary = {} ## art path -> true: a background decode finished and produced no image (the staged face falls through to its styled card, exactly as a synchronous load failure did)
var _art_decode_mutex: Mutex = Mutex.new() ## guards the decode dictionaries and the pump's queue against the worker thread
var _art_decode_queue: Array[String] = [] ## art paths awaiting the decode pump (mutex-guarded)
var _art_decode_pump_active: bool = false ## a pump task is draining _art_decode_queue (mutex-guarded)
var _art_decode_workers: int = 0 ## pump tasks currently draining (mutex-guarded) - OPTIMIZE: back to GF16's one-at-a-time law (the GF18 pool existed to feed stream-ahead, which is deleted)
const ART_DECODE_WORKERS: int = 1 ## the decode pump's bound: SERIAL, one drain at a time (GF16's law, restored by the OPTIMIZE round)
const APPLY_CAP_PER_FRAME: int = 1 ## staged applies allowed per frame, ever - the pipeline pass yields a frame between faces; only the debug_opt_nc="streamahead" seam ignores it
var _art_stopping: bool = false ## the room is leaving the tree: the pipeline starts no new face and the pump returns after its current decode - art work must wind down at exit, not continue into engine teardown (the harness's swing probe segfaulted at quit with fills in flight; the serial worker it replaced was almost always idle by quit, the pipeline by design is not)
## GRADFIX17 (hitch hunt) art-pipeline telemetry staging:
## the pipeline's seams (enqueue, decode pump, apply, heal,
## prefetch) stage event dictionaries here through
## _art_event (mutex-guarded: the decode pump stages from
## its worker thread), and the main thread drains them into
## the scroll telemetry log (see _telemetry_drain_art_events).
## Observation only: staging is one mutex + one array
## append per event; no pipeline decision reads it.
## PVLDS_GF17_TEL=off disables the staging entirely (the
## overhead A/B seam: same build, witness muted).
var _art_tel_mutex: Mutex = Mutex.new()
var _art_tel_pending: Array[Dictionary] = []
var _art_tel_mode: int = -1 ## -1 unknown, 0 off, 1 on (the env read is cached on first use)
var _art_apply_branch: String = "" ## the branch the running _fill_one_face_sync took (written by the fill, read by its caller's telemetry wrap)
var _art_apply_load_ms: float = 0.0 ## the running fill's art-load cost (same wrap)
var _art_apply_render_ms: float = 0.0 ## the running fill's face-render cost (same wrap)
var _face_path_memo: Dictionary = {} ## game_id -> art path, for the pipeline's per-centre-change filter ONLY: _face_path_for probes the filesystem per game, and asking it for all 63 window faces on every column crossing put a measurable burst on the crossing frame (healthy-box runs: 1-2 spikes of 50-90 ms per column with all art work parked). The memo is rewritten by every fill from its own fresh probe, erased on shot refresh, and cleared on rebuild. GRADFIX17 (item 1): a fill is NOT the only corrector any more - the heal and the settle audit probe fresh and rewrite the memo from that probe whenever their fresh key disagrees with the stamp, because a memo written while a face's art was still cold otherwise vetoed every later pass for that face (the filter judged it standing; the fill that would have corrected the memo was the very thing being filtered out).
var _power_subject_inflight: Dictionary = {} ## game_id -> true while its power-on subject renders
var _power_prefetch_asked: Dictionary = {} ## game_id -> true once the warmer has been asked for its cold backglass (GRADFIX6)
var _face_heal_retries: Dictionary = {} ## GRADFIX6 item 2: "game_id|art_file" -> art-render retries already spent by the panel heal
var _face_heal_msec: int = 0 ## GRADFIX6 item 2: the panel heal's throttle stamp (one sweep per BOARD_TEX_RETRY_MS)
var _gf17_was_travelling: bool = false ## GRADFIX17 item 1: the drum was travelling last frame (cruise / swing / page slide) - its falling edge arms the landing guarantee's settle audit
var _gf17_audit_armed: bool = false ## GRADFIX17 item 1: a settle audit is owed: the standing window is re-audited against fresh probes until every visible face honestly stands or its heal budget is spent
var _gf17_audit_msec: int = 0 ## GRADFIX17 item 1: the settle audit's throttle stamp (one sweep per BOARD_TEX_RETRY_MS, the heal's cadence)
var _gf17_audit_runs: int = 0 ## GRADFIX17 item 1: sweeps spent on the current settle (bounded - see _guarantee_audit)
## OPTIMIZE round: the GF18 stream-ahead machinery and the
## GF19 travel costume are deleted wholesale. What stands here
## instead: the apply-cap account, the settle audit's dress
## stamp, and the eviction law's state.
const EVICT_MARGIN_COLS: int = 6 ## RETIRED by the FACECACHE round: the settle-time margin eviction this named is deleted (distance is no eviction offence - see _evict_after_settle); the constant stays only so old comments and NC runners that name it still parse
const RESIDENT_FACES_CAP: int = 384 ## resident face cap: the face cache's LRU enforces it in _face_cache_put. COMPOSE-AHEAD round raised it from 108 (drawn window 63 + margin): a resident face measures exactly 1,714,176 B (496x864x4, the residency gauge's own count, field-verified), so 384 faces bound composed residency at 658,243,584 B (~628 MiB) while covering a whole 350-game library - the field session at cap 108 paid 218 eviction-forced re-renders on one full tour (telemetry-9). Libraries past 384 fall back to the LRU behaviour the 108 cap always had.
const COMPOSE_AHEAD_COLS: int = 6 ## COMPOSE-AHEAD: columns composed ahead beyond the drawn window's edge in the travel direction
const COMPOSE_BEHIND_COLS: int = 2 ## COMPOSE-AHEAD: columns composed beyond the window's other edge (the at-rest neighbourhood's far side)
var _evicted_total: int = 0 ## faces evicted since boot (margin pass + LRU cap drops)
var _applies_total: int = 0 ## staged applies since boot (art_frame_stats)
var _applies_during_travel: int = 0 ## staged applies that landed while the drum travelled
var _applies_max_one_frame: int = 0 ## most applies landed in any single engine frame
var _applies_frame_id: int = -1 ## the engine frame the running apply count belongs to
var _applies_this_frame: int = 0 ## applies landed in _applies_frame_id so far
## FACECACHE round: the composed-face cache's own account -
## the field conviction (OPTIMIZE log, 177 s) was 1,056
## composed renders over 320 games (35.9 s of main thread)
## with ZERO cache hits, because the OPTIMIZE distance
## eviction dropped entries (and cleared panel stamps) for
## leaving the window's margin. The law now: a composed
## face renders ONCE per game-state (the face key: game,
## art path, favourite, PuP - every input the render reads),
## is served from the cache as a pointer swap while it
## lives, and leaves the cache only under LRU cap pressure
## (RESIDENT_FACES_CAP in _face_cache_put) or when the heal
## force-evicts the one key it is retrying. These counters
## are the proof's raw numbers (face_cache_stats + the
## telemetry footer's extra fields).
var _fc_renders: int = 0 ## composed renders served (a fill reached _face_cache_put)
var _fc_swaps: int = 0 ## fills served from the cache (the "facecache" branch)
var _fc_rerenders_eviction: int = 0 ## renders whose game+key had already rendered this session: the previous entry was dropped (cap pressure or a heal force-evict) - the number the field log must hold at ~0 for cap headroom
var _fc_renders_per_game: Dictionary = {} ## game_id -> composed renders served this session
var _fc_last_render_key: Dictionary = {} ## game_id -> the face key its last served render wore
var _fc_evict_reported: int = 0 ## _evicted_total as of the last settle evict record (the record reports the delta)
var _swaps_total: int = 0 ## staged swap-applies since boot (art_frame_stats: swaps ride their own account, never the render cap's)
var _swaps_during_travel: int = 0 ## swap-applies that landed while the drum travelled
var _swaps_max_one_frame: int = 0 ## most swap-applies landed in any single engine frame
var _swaps_frame_id: int = -1 ## the engine frame the running swap count belongs to
var _swaps_this_frame: int = 0 ## swap-applies landed in _swaps_frame_id so far
var _settle_travel_end_msec: int = 0 ## when the last travel ended (the settle audit's dress_ms zero)
var _nc_costume_saved: Dictionary = {} ## debug_opt_nc="costume" seam only: panel idx -> texture it wore before the blank swap
var _nc_costume_on: bool = false ## debug_opt_nc="costume" seam only: the blank swap stands

var _power_panel: ClickableQuad = null ## the card currently performing (or holding) the power-on
var _power_candidate: ClickableQuad = null ## the pop target the settle debounce is timing
var _power_candidate_t: float = 0.0 ## seconds the candidate has rested
var _power_phase: int = 0 ## 0 idle, 1 cascading, 2 settled lit
var _power_mode: int = 0 ## 0 = none, 2 = mimic grade, 3 = pair crossfade (the swap round's modes; 1 was the retired layer cascade)
var _power_pair: bool = false ## the performance crossfades to the author's On image (mode 3)
var _power_t: float = 0.0 ## seconds into the live cascade
var _power_game: GameEntry = null ## the performing card's game
var _power_overlay: MeshInstance3D = null ## the mimic's one quad over the performing face (a child of the panel)
var _power_mat: ShaderMaterial = null ## the overlay's material - its uniforms are the performance
var _power_missed: ClickableQuad = null ## a candidate whose face texture was not ready when its settle fired: skipped until focus changes, never retried per frame
var _placeholder_tex: Texture2D = null ## the standing wall's placeholder face (minted per _rebuild_wall): a panel still wearing it has no face yet
## GRADFIX15 (item 1): the board faces' placeholder - a fully
## TRANSPARENT 4x4. A board (or flip back, or state face) that
## has not rendered yet stands INVISIBLE, never as the dark
## placeholder slab: a frameless face has no fill to fake.
## Reality bookkeeping is untouched by the swap: real is
## still size + the book's tex_real flag (_tex_is_real reads
## a 4x4 as unreal whatever its colour), so the heal rounds
## keep re-issuing a missing board exactly as before, and a
## landed board face - mostly alpha 0 - is a REAL face by
## its size, never mistaken for this placeholder.
static var _clear_tex: Texture2D = null


static func clear_tex() -> Texture2D:
	if _clear_tex == null:
		_clear_tex = TextureFactory.make_solid(Color(0.0, 0.0, 0.0, 0.0))
	return _clear_tex
## Negative-control seam (the focus-fix round's harness env
## PVLDS_FOCUS_NC, set by Main before any room exists):
## "visual" starves the strip quads of visual-state refreshes
## (fault 1's shape), "pager" drops the page-travel focus
## landing (fault 2's shape), "letterland" restores the
## letter picks' first-card landing (the focus law's shape),
## "striporder" permutes the strip's walk order away from
## its drawn order (the strip-order fix's shape),
## "greyanchors" computes the strip's bumper anchors over
## every laid-out slot, greyed ones included (the bumper-
## anchors round's shape). Empty in every real run.
static var debug_focus_nc: String = ""
## Negative-control seam for the strip colour encoding (the
## NEXTROUND round's harness env PVLDS_STRIP_NC, set by Main
## before any room exists): "stale" freezes the strip's
## presence at the first refresh after the library lands and
## reuses it for every later refresh, so the tiles keep the
## boot filter's colours no matter what filter stands - the
## field symptom (Chris, 2026-11-02: tiles reading as stale
## state that does not track filter changes) restored, so
## the letters smoke's strip-colour legs fail by name.
## Empty in every real run.
static var debug_strip_nc: String = ""
## Bench seam (the focus-law round's harness env PVLDS_BENCH,
## set by Main before any room exists): when true, every wall
## fill prints its phase timings (banner / furniture / panels)
## and its factory render + cache-hit counts as BENCH lines -
## the pick-latency evidence. Silent in every real run.
static var debug_bench: bool = false
## Negative-control seam for the background stack (the
## harness env PVLDS_BG_NC, set by Main before any room
## exists): "drum" parents the stack to the drum, breaking
## the world-lock so the graduation smoke's lock leg fails
## by name. Empty in every real run.
static var debug_bg_nc: String = ""
## Negative-control seam for the boot seating guard (the
## harness env PVLDS_BOOT_NC, set by Main before any room
## exists): "oldbind" never arms the guard, restoring the
## pre-BOOTFIX binding - the resting pointer's hover owns
## the centre from the first frame, so the boot power-on
## binds the hovered card instead of the restored focus -
## and the bootfocus smoke's legs fail by name. Empty in
## every real run.
static var debug_boot_nc: String = ""
## Negative-control seam for the shelf's fill order (the
## harness env PVLDS_GRID_NC, set by Main before any room
## exists): "rowmajor" restores the shipped across-the-band
## fill, so the grad census's column-order leg fails by
## name. Empty in every real run (the shelf fills
## column-major - see _grid_coord).
static var debug_grid_nc: String = ""
## Negative-control seam for the Tournament view's B exit
## (the harness env PVLDS_B_NC, set by Main before any room
## exists): "nobexit" leaves B unassigned in the Tournament
## view again (its pre-GRADFIX4 state), so the nav smoke's
## B-exit leg fails by name. Empty in every real run.
static var debug_b_nc: String = ""
## Negative-control seam for the blank-board heal (the
## harness env PVLDS_GRADFIX4_NC, set by Main before any room
## exists): "solidboard" makes every board render land
## the factory's fallback solid AND count it as the board
## (the pre-GRADFIX4 bookkeeping) - the field's empty-
## faced board, stuck - so the heal leg fails by name.
## GRADFIX6: the seam now bites in _render_card_back, the
## board's render on the flipped card. Empty in every
## real run.
static var debug_gf4_nc: String = ""
## Negative-control seam for the tournie border (the
## harness env PVLDS_GRADFIX8_NC, set by Main before any
## room exists): "noborder" never applies a border, so
## the grad census's tourney-border legs fail by name.
## Empty in every real run.
static var debug_gf8_nc: String = ""
## Negative-control seam for GRADFIX10 items 4+5 (the
## harness env PVLDS_INPUT_NC, set by Main before any room
## exists): "dpadmove" restores the pre-nuke D-pad
## Left/Up/Down focus movement, "notrig" leaves the
## triggers unread (their pre-GRADFIX10 state) - each so
## the input smoke's matching legs fail by name. Empty in
## every real run.
static var debug_input_nc: String = ""
## Negative-control seams for GRADFIX10 items 2+3 (the
## harness env PVLDS_GRADFIX10_NC, set by Main before any
## room exists): "steppop" restores the convicted pop
## stepping (the pop amount quantised to coarse steps -
## see _update_pop), so the motion smoke's pop-smoothness
## leg fails by name; "stepswing" restores slot-stepping
## under the SMOOTH wall-motion dial (the drum re-seats on
## each column boundary instead of rolling continuously),
## so the smooth-travel leg fails by name. Empty in every
## real run.
static var debug_gf10_nc: String = ""
## Negative-control seam for GRADFIX12 item 1 (the harness
## env PVLDS_GRADFIX12_NC, set by Main before any room
## exists): "nolive" severs the wall-motion dial's live
## apply - set_wall_motion_mode still records the mode the
## SETUP panel reads, but the DRIVER keeps the boot mode
## (see _wall_driver_mode), so the motion smoke's live
## toggle leg fails by name. Empty in every real run.
static var debug_gf12_nc: String = ""
## Negative-control seams for GRADFIX13 items 3+4 (the
## harness env PVLDS_GF13_NC, set by Main before any room
## exists): "steprepeat" restores the convicted held-stick
## shape - every auto-repeat tick of the pad poll feeds a
## fresh discrete step into the SMOOTH driver and no
## hold-cruise ever arms (item 3) - so the motion smoke's
## held-cruise leg fails by name; "oldascent" restores the
## shipped rail->rows ascent - UP from the rail falls
## through to the screen-projection walk instead of taking
## the deterministic ascent edge (item 4) - so the nav
## smoke's vertical-wall-law legs fail by name. Empty in
## every real run.
static var debug_gf13_nc: String = ""
## Negative-control seam for GRADFIX14 item 2 (the harness
## env PVLDS_GF14_NC, set by Main before any room exists):
## "oldadopt" restores the pre-fix adoption behaviour -
## refresh_library discards the player's place (centre back
## to the shelf's head, focus dropped) and Main drops a scan
## that lands while a launch wait stands - so the scanwall
## smoke's focus and launch-wait legs fail by name. Empty in
## every real run.
## Negative-control seam for GRADFIX14 item 1 (the harness
## env PVLDS_GF14_NC, set by Main before any room exists):
## "tileboxes" restores the shipped per-tile rail boxes
## wholesale (see the RAIL_STRIP_LIFT block), so the grad
## census's machined-strip legs fail by name. The same env
## var carries item 3's grammar values (a distinct set);
## empty in every real run.
## Negative-control seams for GRADFIX14 item 3 (the unified
## travel grammar - the harness env PVLDS_GF14_NC, set by
## Main before any room exists): "stripanchor" restores the
## strip's bumper anchor-hops (supersession (a)'s pre-fix
## shape), "railwall" restores rail-focus bumpers driving
## the wall's page travel (supersession (b)'s pre-fix
## shape), "bartriginert" leaves the triggers inert under
## rail/strip focus again (supersession (c)'s pre-fix
## shape) - each so the input smoke's gf14 grammar legs
## fail by name. Empty in every real run.
static var debug_gf14_nc: String = ""
## Negative-control seams for GRADFIX16 (the harness env
## PVLDS_GF16_NC, set by Main before any room exists; one
## var, two values, the GF14 pattern): item 1's
## "refreshgate" restores the shipped gating - REFRESH is
## pickable only while the Tournament Room stands, so it
## drops out of the library rail's focus walk, bumper and
## trigger lists, pointer pick and lift, and the input
## smoke's gf16 refresh legs fail by name. Item 2's
## "syncfill" restores the pre-fix fill law - a window fill
## awaited from _set_centre's travel path pays decode +
## render inline, serially, exactly as the base build did -
## so the artstream smoke's travel-frame legs fail by name.
## Empty in every real run.
static var debug_gf16_nc: String = ""
## Negative-control seam for GRADFIX17 (item 1, the art-landing
## guarantee; the harness env PVLDS_GF17_NC, set by Main before
## any room exists): "noguarantee" disables the settle audit
## and its memo correction - a face whose ready art path changed
## after the pipeline's memo first read it is never re-issued,
## exactly the GRADFIX16 field defect - so the landing smoke's
## "landing guarantee:" census legs fail by name. Empty in
## every real run.
## GRADFIX17 (item 2) negative-control seam (harness env
## PVLDS_GF17_NC): "hazeall" restores the pre-fix wall-alpha
## law - _apply_wall_alpha rewrites every panel's, launch's
## and label's alpha on every centre change, changed or not
## (the per-column write storm the hitchhunt convicted) -
## so the hitchhunt smoke's alpha-write leg fails by name.
## Empty in every real run.
static var debug_gf17_nc: String = ""
## Negative-control seam for the OPTIMIZE round (the harness
## env PVLDS_OPT_NC, set by Main before any room exists):
## "smoothcruise" restores a continuous roll on a held stick
## (the deleted SMOOTH gait's shape, minimal seam in
## _update_swing / the _process poll), "costume" blanks the
## drawn window's faces while a swing travels, "streamahead"
## lifts the pipeline's per-frame apply cap on travel frames,
## "evictvis" drops the eviction pass's visible-window guard,
## "oldradius" is Main's (it assigns WALL_RADIUS before the
## room exists). Empty in every real run.
static var debug_opt_nc: String = ""
## Negative-control seam for the NEVERBLANK round (the
## harness env PVLDS_NEVERBLANK_NC, set by Main before any
## room exists): "clearfirst" restores the clear-then-fill
## shape on the face-swap seam - the swap binds the dark
## placeholder first and the real face a few frames later -
## so the facecache chain census's black-pane legs fail by
## name. Empty in every real run.
static var debug_nb_nc: String = ""
## Negative-control seam for the PHANTOMFIX round (the
## harness env PVLDS_PHANTOM_NC, set by Main before any
## room exists): "phantom" restores both pre-fix behaviours
## - provenance-blind face-cache serving (Layer 1) and the
## direct-ask sync shortcut inside the art pipe's stage
## (Layer 3) - so the phantom fixture fails by name. Empty
## in every real run.
static var debug_phantom_nc: String = ""

## COMPOSE-AHEAD round's negative-control seam:
## "noahead" - ahead composition never runs, so first-visit
## arrivals compose at arrival exactly as they did before
## the round and the compose smoke's arrival legs fail by
## name. Empty in every real run. (Declared ahead of the
## mechanism; inert until the round's product commit.)
static var debug_compose_nc: String = ""

var _border_shader: Shader = null ## the tournie border's one shader (GRADFIX8 item 4)
var _border_mats: Dictionary = {} ## type_code -> ShaderMaterial: ONE shared material per challenge type, its colour baked in; every bordered card of that type draws with it (TIME-driven, no per-card material, no per-frame CPU)
var _bg_root: Node3D = null ## the background stack's holder (a Room child - world-locked; the drum is its only moving neighbour)
var _bg_starfield: MeshInstance3D = null
var _bg_starfield_near: MeshInstance3D = null ## the near star shell (the GRAD FIX round's depth layer)
var _starfield_mode: String = "layered" ## the SETUP dial: "layered" | "flat" | "off" (see set_starfield_mode)
var _wall_motion_mode: String = "stepped" ## OPTIMIZE: STEPPED is the only gait - the field stands for the SETUP panel's label, and set_wall_motion_mode coerces every value to "stepped"
var _bg_ring: MeshInstance3D = null ## always null since GRADFIX4 removed the orbit ring (item 5e); background_layers() skips it
## The card flip's standing state (GRADFIX6 item 1): one
## card at a time wears the turn - the one the player
## flipped. _flip_idx is its index in _panels (-1 = no card
## flipped or turning); _flip_t is the turn's progress
## (0 = front, 1 = back) and _flip_open its target. The
## back's content bookkeeping mirrors the deleted
## companions' heal discipline (the GRADFIX4 blank-face
## heal, carried over whole): the standing key, the APPLIED
## texture's key and whether it is a real capture are
## separate facts, and a watchdog re-issues the render
## (bounded) whenever the standing back's face is missing
## or the factory's fallback solid.
var _flip_idx: int = -1
var _flip_t: float = 0.0
var _flip_open: bool = false
var _flip_key: String = "" ## the standing back content's key (game/challenge + fetch stamp + player + owned)
var _flip_tex_key: String = "" ## the key the flipped card's APPLIED back texture was rendered for
var _flip_tex_real: bool = false ## the applied back texture is a real capture, not the fallback solid
var _flip_render_key: String = "" ## the key a back render is in flight for ("" = none)
var _flip_retry_key: String = ""
var _flip_retries: int = 0
var _flip_retry_msec: int = 0
## GRADFIX7 item 2 (Tournament Room): the standing boards.
## Every challenge card stands with its scoreboard BESIDE it
## (no flip in the Tournament Room - Chris's correction:
## "no flip on tournie screen, its not needs, plenty of room
## to just display the works. Table art, tournie info.").
## Boards are pooled nodes keyed by CHALLENGE_ID (never
## game_id - the panel pool's mode-mismatch path would
## free/re-mint them), never seated in _panels/_focusables,
## never pickable, and take no pop of their own - since
## GRADFIX10 item 2 a board RIDES its pair card's pop (see
## _update_pop), so the highlighted pair travels as one.
## Their per-board
## bookkeeping mirrors the flip's heal discipline: standing
## key, applied texture's key, real-or-fallback are separate
## facts per board (a single shared slot would starve all
## but the last board).
var _board_pool: Dictionary = {} ## challenge_id -> {root: MeshInstance3D, mat: StandardMaterial3D}
var _board_book: Dictionary = {} ## challenge_id -> {key, tex_key, tex_real, render_key, retry_key, retries, retry_msec}
var _board_nodes: Array = [] ## standing board node per _visible_games index (null for the state row / library)
var _board_base_pos: Array = [] ## GRADFIX10 item 2: standing board's wall-flush position per index (its pair card's pop rides it from here)
var _board_pop_dir: Array = [] ## GRADFIX10 item 2: standing board's pop direction per index (its pair card's wall normal)
var _board_tex_cache: Dictionary = {} ## standing key -> Texture2D: real board captures, kept across rebuilds so a REFRESH does not re-render unchanged boards
var _board_heal_msec: int = 0 ## the board heal's throttle stamp (one sweep per BOARD_TEX_RETRY_MS)
var _board_fill_busy: bool = false ## a tournament board fill pass is running (request coalescing, like the window fill)
var _board_fill_dirty: bool = false
const BOARD_TEX_MAX_RETRIES: int = 5 ## the blank-face heal's bound per standing key
const BOARD_TEX_RETRY_MS: int = 600 ## the heal's minimum interval between re-renders
var _launching_game_id: String = "" ## a launch is in its load wait (Main owns it); the wall is frozen meanwhile
var _failed_game_id: String = "" ## last launch died during its load; its button says FAILED until the user moves on
var _status_note: String = "" ## transient banner suffix: "Launching X..." / "Launch failed: X - reason"
var _selected_game_id: String = "" ## last game opened/launched; restored + persisted as view state
var _marquee: Node3D = null ## the loading marquee's holder; in the tree only during a load wait
var _marquee_year: Label3D = null
var _marquee_name: Label3D = null
var _marquee_up: bool = false
var _marquee_t: float = 0.0 ## seconds since the marquee rose
var _wall_alpha_applied: float = 1.0 ## the wall fade's last applied alpha (change guard)
## GRADFIX17 (item 2): the wall-alpha pass's write-on-change
## bookkeeping. The pass used to rewrite every panel's,
## launch's and label's alpha on EVERY centre change (the
## haze "follows the centre", so _refresh_window defeated
## the change guard by resetting it) - some 3 renderer
## writes per panel per column crossing, ~99% of them
## writing the value already standing (a panel's haze
## factor moves materially only while it crosses the
## 6-to-10-column band around the centre). The pass now
## writes only what changed by at least its own standing
## epsilon (0.002, the guard's own threshold - a smaller
## change is invisible by the code's own standard), and
## _alpha_write_count counts the writes so the hitchhunt
## smoke can judge the law structurally. PVLDS_GF17_NC=
## hazeall restores the write-everything law (debug_gf17_nc).
var _alpha_write_count: int = 0 ## wall-alpha values written since boot (the hitchhunt smoke reads the cruise deltas)
## OPTIMIZE round (item 5) standing-cost audit counters:
## observation only - no product decision reads them. They
## count work the room does for cards that are NOT changing:
## mimic evaluations (_apply_power calls), label/nameplate
## texture reassignments (rail/strip dress set_texture calls
## + status-label text sets), panel face-texture assignments
## whose texture equals the standing one (no-op swaps),
## wall-alpha writes (the standing _alpha_write_count above),
## and pop-loop panel visits made while the room is at rest.
## standing_cost_stats() reports totals plus per-second rates
## over the accumulated at-rest time.
var _sc_mimic_evals: int = 0 ## _apply_power calls since boot
var _sc_label_reassign: int = 0 ## label/nameplate texture-or-text reassignments since boot
var _sc_noop_face_swaps: int = 0 ## panel face assignments where new tex == standing tex (attempted no-ops)
var _sc_face_assigns: int = 0 ## panel face assignments total (the no-op rate's denominator)
var _sc_pop_visits_rest: int = 0 ## pop-loop panel visits while at rest since boot
var _sc_rest_msec: int = 0 ## accumulated wall time with the room at rest (no swing, no pop motion, no cascade, no pipeline work)
var _sc_rest_since: int = 0 ## msec stamp the current rest stretch began (0 = not at rest)
var _alpha_haze_centre: int = -999 ## the centre column the standing per-panel alphas were computed for
var _panel_alpha_applied: Array[float] = [] ## per panel: the content alpha last written (-1 = never)
var _launch_alpha_applied: Array[float] = [] ## per launch quad: same
var _label_alpha_applied: Array[float] = [] ## per panel label: same
var _board_alpha_applied: Array[float] = [] ## per board node: same
var _alpha_flat_applied: Dictionary = {} ## rail/strip/status/plate/border key -> the alpha last written (these ride the global fade only, never the haze)
var _placard: Node3D = null ## the setup placard's holder; in the tree only while the placard stands
var _placard_face: ClickableQuad = null
var _placard_back: ClickableQuad = null
var _placard_up: bool = false
var _placard_gen: int = 0
var _placard_message: String = "" ## the message the standing placard carries (a launch failure rides it too)
var _setup_panel: Node3D = null ## the in-room SETUP panel's holder; in the tree only while the panel stands
var _setup_panel_face: ClickableQuad = null
var _setup_panel_scan_btn: ClickableQuad = null
var _setup_panel_dl_btn: ClickableQuad = null
var _setup_panel_wovp_paste_btn: ClickableQuad = null ## PASTE KEY: reads the WoVP key off the PC clipboard (VR has no keyboard - the paste IS the field)
var _setup_panel_wovp_test_btn: ClickableQuad = null ## TEST KEY: Main validates the saved key and names whose it is
var _setup_panel_stars_btn: ClickableQuad = null ## STARS: LAYERED/FLAT/OFF - the display dial (the GRAD FIX round)
var _setup_panel_wall_btn: ClickableQuad = null ## WALL MOTION: STEPPED - the panel's gait label (OPTIMIZE: the dial is gone, STEPPED is the only gait)
var _setup_panel_back_btn: ClickableQuad = null
var _setup_panel_ipdb_btn: ClickableQuad = null ## CARDBACK/IPDBFIX: RE-APPLY IPDB DATA - Main re-applies the bundled snapshot, the panel's mirror of the desk's button
var _setup_panel_up: bool = false
var _setup_panel_gen: int = 0
## ROOMSUBMIT: the submit panel - the SETUP panel's sibling
## (same seat, same modal grammar), opened by Y on a focused
## challenge card in the Tournament Room. It carries one
## challenge's case, the newest screenshots from the
## player's screenshots folder (thumbs), one focused shot
## standing large for the flicker check, SEND and BACK.
var _submit_panel: Node3D = null ## the panel's holder; in the tree only while the panel stands
var _submit_panel_face: ClickableQuad = null
var _submit_big_quad: ClickableQuad = null ## the focused shot, standing large (a display surface - never a focus stop)
var _submit_thumb_quads: Array[ClickableQuad] = [] ## the shot strip, newest first; payload = the shot's path
var _submit_send_btn: ClickableQuad = null
var _submit_back_btn: ClickableQuad = null
var _submit_panel_up: bool = false
var _submit_panel_gen: int = 0
var _submit_render_in_flight: bool = false
var _submit_render_pending: bool = false
var _submit_render_msec: int = 0
var _submit_challenge: WovpChallenge = null ## the challenge the standing panel serves (held by reference; SEND uses its id, never a row)
var _submit_challenge_id: String = ""
var _submit_owned: bool = false
var _submit_build_owned: bool = false
var _submit_shots: Array = [] ## the folder read at open: [{path, name, mtime}], newest first, capped at the strip's five
var _submit_shots_line: String = "" ## ShotsFolder.panel_line for the folder read at open
var _submit_selected_path: String = "" ## the shot SEND would post: the focused thumb's (focus IS the verify step)
var _submit_status: String = "" ## the face's message line: states and verdicts in words
var _submit_sending: bool = false
var _setup_health: Dictionary = {} ## the last completed scan's numbers, fed by Main (see set_setup_health)
var _setup_message: String = "" ## the panel's message line: the last action's outcome, in plain words
var _setup_scanning: bool = false ## a scan Main started for the panel is running (its progress feeds the message line)
var _setup_downloader: VpsDownloader = null ## the panel's handle on the shared download service (created with the panel, kept for the room's life)
var _setup_render_in_flight: bool = false ## a panel render is awaiting the factory (the factory takes one render at a time)
var _setup_render_pending: bool = false ## state changed mid-render or inside the progress throttle: render again after
var _setup_render_msec: int = 0 ## when the last panel render started (the progress throttle's clock)
var _pending_library: LibraryScanner = null ## a scan that landed while the SETUP panel stands: held, and adopted ONCE when the panel closes (see adopt_library)
var _pick_snapshot: Dictionary = {} ## ClickableQuad -> pick_enabled, taken as the placard rises
var _rail_quads: Dictionary = {} ## key -> ClickableQuad
var _rail_tex_cache: Dictionary = {} ## "label|accent" -> Texture2D: every rail button face ever rendered, so a rebuild re-dresses the rail in its own frame
var _rail_bar: MeshInstance3D = null ## GRADFIX14 (item 1): the machined strip's ONE continuous backing bar (null in tileboxes NC mode)
var _rail_def_w: Dictionary = {} ## GRADFIX14 (item 1): key -> the section's laid-out width, metres (the strip faces render at each section's own aspect from it)
var _rail_last_key: String = "" ## GRADFIX14 (item 1): the rightmost section's key (it carries no etched seam)
var _rail_base_pos: Dictionary = {} ## GRADFIX14 (item 1): key -> the section's flush position (its lift rides from here)
var _rail_pop_dir: Dictionary = {} ## GRADFIX14 (item 1): key -> unit vector from the section toward the viewer (its lift direction)
var _rail_pop: Dictionary = {} ## GRADFIX14 (item 1): key -> current lift amount, 0 flush .. 1 lifted (the pop spring's discipline, see _update_rail_lift)
var _rail_pop_vel: Dictionary = {} ## GRADFIX14 (item 1): key -> lift spring velocity, carried across retargets
var _rail_pop_applied: Dictionary = {} ## GRADFIX14 (item 1): key -> last lift amount written to the section's transform (write guard)
var _rail_tex_lifted: Dictionary = {} ## GRADFIX14 (item 1): key -> whether the section's face currently wears the lifted gradient (swaps at the lift's half-rise, so the material change rides the motion, never jumps ahead of it)
var _rail_applied_key: Dictionary = {} ## GRADFIX14 (item 1): key -> the strip cache key last applied to the section (change guard)
var _strip_quads: Dictionary = {} ## letter key ("A".."Z", "THE", "#") -> ClickableQuad: the alphabet strip, built once with the rail
var _strip_tex_cache: Dictionary = {} ## "key|state" -> Texture2D: every strip slot face ever rendered (the rail cache's pattern)
var _strip_worn_state: Dictionary = {} ## NEXTROUND (item 1): letter key -> the colour state ("plain"/"dim"/"accent") the slot's worn face was rendered for, recorded at BOTH dress sites (the synchronous cache dress and the fill's render) - the strip-colour smoke reads the encoding from here, and the record is what makes a slot's standing colour assertable at all
var _strip_frozen_presence: Dictionary = {} ## PVLDS_STRIP_NC=stale only: the presence frozen at the first refresh (see debug_strip_nc)
var _strip_frozen_valid: bool = false ## PVLDS_STRIP_NC=stale only: _strip_frozen_presence holds the frozen read
var _strip_presence_now: Dictionary = {} ## NEXTROUND (item 1): the presence the latest _refresh_strip read - the fill's strip loop dresses from THIS read, so the synchronous dress and the async render can never disagree about which filter's colours the strip wears
var _btn_tex_cache: Dictionary = {} ## "label|accent" -> Texture2D: the panels' Launch/Failed button faces - two textures in existence, once rendered per panel per rebuild before the pick-latency fix. GRADFIX13 (item 2): dormant in the shipped build (no plinth is dressed); the plinth NC's minted buttons use it as before
var _face_tex_cache: Dictionary = {} ## "game_id|art_path|fav" -> [Texture2D, art_aspect]: rendered panel faces (the pick-latency fix - a revisit re-rendered every face from scratch)
var _face_cache_order: Array[String] = [] ## the face cache's LRU order (oldest first)
const FACE_CACHE_MAX: int = RESIDENT_FACES_CAP ## OPTIMIZE: the resident cap IS the cache cap (384 since COMPOSE-AHEAD - see RESIDENT_FACES_CAP's arithmetic)
var _strip_has_number: bool = false ## the library holds a non-letter title, so the "#" slot is laid out (see _refresh_strip)
var _letter_net: String = "" ## "" | "THE" | "#": the standing net view - the wall shows exactly that net's games, in title order (see _jump_to_letter)
var _tournament: bool = false ## the Tournament Room view stands: the wall shows WoVP challenge boards, not the library (see _build_tournament_rows)
var _tournament_rows: Array = [] ## the standing view's rows, aligned 1:1 with _visible_games: {"kind": "challenge"|"state", "challenge", "game", "owned", "build_owned", "lines"}
var _wovp_has_key: bool = false ## Main's word on the config: a WoVP key is saved
var _wovp_user_id: String = "" ## whose key it is (validate-apikey's answer, or the cache's) - how the wall knows which row is HIS
var _wovp_challenges: Array = [] ## the last-good boards (Array of WovpChallenge), live or from the disk cache
var _pinemhi_bests: Dictionary = {} ## NEXTROUND (item 4): PINemHi personal bests by PinemhiScores title key, pushed by Main (set_pinemhi_bests); a challenge whose title keys into this map gets the subordinate best line on its standing board
var _ipdb_facts: Dictionary = {} ## CARDBACK: the IPDB cache's facts by game id, pushed by Main (set_ipdb_facts); backs read ONLY this map - the flip path never fetches
var _ipdb_stamp: int = 0 ## CARDBACK: Main's cache stamp; it rides _card_back_key so a snapshot apply re-renders a standing back under its new key
var _wovp_shots_folder: String = "" ## ROOMSUBMIT: the config's screenshots folder, pushed by Main with the boards - the submit panel reads its photos from there
var _wovp_fetched_at: int = 0 ## unix time the standing boards landed (0 = never)
var _wovp_live: bool = false ## the standing boards came from a fetch this session (false = the disk cache's)
var _wovp_fetch_error: String = "" ## the last fetch's failure, in words, when it failed - the wall says so rather than dressing stale boards as live
var _centre_index: int = 0 ## the shelf index the drum is centred on: the popped card's index in _visible_games (the pop target and the power-on follow it; it is NOT the pad focus - focus may sit on the rail or the strip while the drum stays centred where browsing left it, and a letter pick swings the drum without moving the focus: the focus law)
var _columns: int = 1 ## the standing view's column count: ceil(visible / 3 bands)
var _swing_to: float = 0.0 ## drum yaw the live swing is heading to (the centred column's angle)
var _swing_duration: float = 0.2 ## the live swing's calibrated length (grows with the column travel; the spring's stiffness derives from it)
var _swing_vel: float = 0.0 ## drum yaw velocity (rad/s), carried across retargets - the glide's continuity lives here
var _swing_cols: float = 1.0 ## the live swing's remaining travel in columns (the spring stiffens with distance: its settle tail grows logarithmically, the duration law only as a square root)
var _swing_journey: bool = false ## a retarget arrived mid-travel in the travel's own direction: the spring softens to the stepping cadence so a held scroll builds to a cruise instead of settling between steps
var _swing_active: bool = false
var _nc_roll_dir: int = 0 ## debug_opt_nc="smoothcruise" seam only: the continuous roll's direction while it stands (0 in every production run - STEPPED never rolls)
var _step_from_col: int = -1 ## OPTIMIZE telemetry: the standing step record's origin column (-1 = no step in flight)
var _step_to_col: int = -1 ## OPTIMIZE telemetry: the standing step record's target column
var _step_start_msec: int = 0 ## OPTIMIZE telemetry: when the standing step's travel began
var _pop_awake: bool = true ## OPTIMIZE standing-cost cut: the pop spring loop runs only while awake (a target change, a face landing under a popped card, or motion in flight wakes it; all-settled puts it to sleep)
var _pop_last_target: ClickableQuad = null ## OPTIMIZE standing-cost cut: the pop target the sleeping loop last settled under

var _drum_yaw: float = 0.0 ## the drum's current yaw, radians (== _swing_to at rest)
var _panel_pool: Dictionary = {} ## game_id -> {root, launch, frame, plate, label, mode, plate_done}: card nodes built once per library adoption and re-seated per view (a rebuild that freed and rebuilt 300+ cards would tax every letter pick - the pick-latency law)
var _plates_pending: bool = false ## a rebuild stood new cards: their nameplates re-derive from the labels' live AABBs until every one settles (see _refresh_card_plate)
var _panel_face_key: Dictionary = {} ## game_id -> the face key its standing texture was filled for ("" = never filled)
var _panel_window_lo: int = -1 ## the drawn window's first COLUMN (visibility + face fill range), -1 = none yet
var _panel_window_hi: int = -1 ## the drawn window's last COLUMN
var _power_subject_cache: Dictionary = {} ## game_id -> [backglass path, fav, Texture2D]: rendered power-on subjects (the backglass face, rendered once per game per library PER FAVOURITE STATE - GRADFIX12 item 2: the subject is a rendered face, so it carries the favourite badge its render was made under; a cache that ignored the flag served the pre-toggle subject over the new face and the star died under the settled overlay)
var _power_on_cache: Dictionary = {} ## game_id -> [pair On path, fav, Texture2D]: the pair crossfade's On half rendered AS A FACE (GRADFIX12 item 2 - it used to ride the overlay as the raw art texture, which no badge can ever be composed on, so a favourited pair card's settled overlay was badgeless by construction)
var _power_on_inflight: Dictionary = {} ## game_id -> true while its rendered pair On face renders
var _focusables: Array[ClickableQuad] = []
var _focused: ClickableQuad = null
var _joy_cooldown: float = 0.0
var _joy_hold_dir: Vector2 = Vector2.ZERO ## GRADFIX13 item 3: the direction of the stick hold in progress (ZERO = no hold) - the poll's hold bookkeeping (see the poll in _process)
var _joy_hold_steps: int = 0 ## discrete steps fired inside the current continuous hold (OPTIMIZE: every step is discrete; the count survives only for the debug_opt_nc="smoothcruise" seam, which arms its roll on the second step)
var _joy_step_queued: Vector2 = Vector2.ZERO ## OPTIMIZE finish (hold cadence): one pending hold-REPEAT step (the hold's first step never queues) waiting for the drum to land + rest; cleared on release or direction change, fires only while the stick still holds its direction
var _step_rest_timer: float = 0.0 ## seconds of enforced drum rest left after the last swing landing (STEP_REST_SEC), spent in _process
var _joy_prev_a: bool = false
var _joy_prev_b: bool = false
var _joy_prev_y: bool = false ## Y edge tracking: open the focused card's info (see _process)
var _joy_prev_x: bool = false ## X edge tracking: favorite the focused card (see _process)
var _joy_prev_lb: bool = false ## bumper edge tracking: the section slide's page travel (see _process)
var _joy_prev_rb: bool = false
var _joy_prev_lt: bool = false ## trigger edge tracking (GRADFIX10 item 4): the axis reads "down" past TRIGGER_PRESS_THRESHOLD; a wall-anchor step fires only on the crossing, and the trigger must fall back below the threshold before another can fire (see _process)
var _joy_prev_rt: bool = false
var _joy_prev_right: bool = false ## D-pad Right edge tracking: the room's BACK-out press (see _process)
var _joy_right_armed: bool = false ## baseline-release arming: set once THIS room instance has observed D-pad Right released; until then no right-press edge can exit (see _process)
## Scroll telemetry (the diagnostic build's witness -
## core/scroll_telemetry.gd): observation only. The logger
## is started lazily on the room's first visible frame (by
## then Main's config apply has named the boot wall-motion
## mode), and every hook below only READS the standing
## state - no hook assigns scroll/input state, returns a
## value a decision can consume, or runs when the room is
## hidden. Deleting the hooks restores the shipped build.
var _scroll_telemetry: ScrollTelemetry = ScrollTelemetry.new()
var _scroll_telemetry_started: bool = false

## NEVERBLANK (the law: a card panel's displayed texture
## is only ever REPLACED, never cleared first). The
## instrument: ClickableQuad's assignment probe convicts
## any empty-over-real assignment on a card panel, and the
## eviction paths report dropping a texture a visible
## panel still wears. The fix: cache evictions defer
## while their texture is bound to a visible panel, and
## cache-hit faces bind synchronously at enqueue - in the
## same call stack as the centre change that brought
## their card into the window - so a served face never
## waits behind an in-flight render to be seen.
var _nb_face_clear_count: int = 0 ## assignments of an empty-like texture over a real standing card face (the law: stays 0)
var _nb_evict_bound_count: int = 0 ## cache evictions that dropped a texture bound to a visible card panel (instrument; the fix turns these into deferrals)
var _nb_evict_deferred_count: int = 0 ## evictions deferred because the texture is bound to a visible panel (the fix's account)
var _nb_enqueue_swaps: int = 0 ## cache-hit faces bound synchronously at enqueue (the fix's account)
var _nb_nc_pending: Array = [] ## NC "clearfirst" only: [quad, tex, frames_left] real binds waiting out their clear dwell


func setup(factory: TextureFactory, scanner: LibraryScanner, store: StateStore, xr_enabled: bool) -> void:
	_factory = factory
	_scanner = scanner
	_store = store
	_xr_enabled = xr_enabled
	ClickableQuad.texture_assign_probe = _nb_on_texture_assign ## NEVERBLANK instrument (see _nb_on_texture_assign)
	_build_environment()
	_build_rigs()
	_detail = DetailView.new()
	_detail.setup(factory, store)
	_detail.position = Vector3(0.0, 1.3, -1.72)
	add_child(_detail)
	ClickableQuad.face_point(_detail, EYE)
	_detail.closed.connect(_on_detail_closed)
	_detail.play_requested.connect(_on_detail_play)
	# Return-trip restore (M2): the watchdog's relaunch should land
	# the player exactly where they left - same filter/sort, and the
	# just-played (or last-opened) table's page, selected.
	if _store.view_filter != "" and FILTERS.has(_store.view_filter):
		_filter = _store.view_filter
	if _store.view_sort != "" and SORTS.has(_store.view_sort):
		_sort = _store.view_sort
	_selected_game_id = _store.selected_game_id
	if _selected_game_id == "":
		_selected_game_id = _store.last_played_game_id
	refresh_library()
	if _selected_game_id == "":
		# The dome's boot law (the prototype's DOME1 catch,
		# field-passed): a linear shelf that opens on its
		# first card shows a void on one side - with nothing
		# to restore, the middle card is the honest home.
		# (The flat wall opened on its first page; the drum
		# has no pages to open on.) A saved selection still
		# wins, through _restore_selection below.
		_set_centre((_visible_games.size() - 1) / 2, true)
	_restore_selection()
	boot_centre_index = _centre_index
	boot_visible_count = _visible_games.size()
	print("ROOM SETUP: %d visible, boot centre %d (selected '%s', filter '%s', sort '%s')"
		% [_visible_games.size(), _centre_index, _selected_game_id, _filter, _sort])
	# The boot seating guard (BOOTFIX, convicted on the
	# bootfocus harness against the shipped build): the
	# power-on's subject is the CENTRE (see _update_power),
	# and the centre is seated correctly HERE - on the
	# restored selection, or on the mid-shelf card when
	# there is nothing to restore. But _follow_centre hands
	# the centre to the pointer's hover from the very first
	# frame, and a pointer nobody has moved yet still
	# hovers SOMEWHERE: on the flat path the resting mouse
	# ray lands on some card of the restored column (under
	# the column-major fill, GRADFIX3, often the restored
	# card's own column-mates - the geography changed, the
	# hazard did not), and in the headset a resting laser
	# can lie on any card. That
	# unmeant hover unseated the restore before the
	# power-on's settle ever ran, so the standing
	# performance bound the hovered card while the focus
	# sat on the restored one. The guard holds the
	# seating: until the pointer's hover CHANGES from the
	# resting place recorded when the wall lands, or the
	# focus or the centre is moved by any other path,
	# hover does not drive the centre (see _follow_centre)
	# - the restore does, through the focus. The first
	# genuine point or step releases the guard for the
	# session; the shipped follow law then rules exactly
	# as before.
	if debug_boot_nc != "oldbind":
		_boot_guard = true
		_boot_focus_ref = _focused
		_boot_centre_ref = _centre_index


func refresh_library() -> void:
	_letter_net = "" ## a fresh library lifts any standing net: its set was the old scan's truth
	_strip_frozen_valid = false ## NEXTROUND (item 1): a fresh library re-arms the strip NC's freeze at the new library's first refresh - and in production (NC unset) this is the only trace the seam leaves
	# GRADFIX14 (item 2): the player's place survives an
	# adoption. Before this, every landed scan reset the
	# centre to the shelf's head and dropped the focus, so
	# the wall the player returned to was a wall restarted
	# at zero - a game deep in the shelf (a new "W..." among
	# 374) was not on the wall in front of him until a later
	# view rebuild re-seated his browsing (Chris's post-scan
	# wall, 2026-11-01: World Poker Tour found only after a
	# tournament detour). The place is read from the standing
	# wall BEFORE the recompute: the focused card first,
	# then the centred game, then the restored selection.
	# If the placed game survived the scan it keeps its
	# centre (and its focus, when the focus was its card);
	# if it vanished, the standing fallback stands: centre
	# at the refreshed wall's first card, focus wherever the
	# caller's own landing law puts it (the panel close's
	# rail SETUP stop, or none). The NC seam (oldadopt)
	# restores the reset wholesale.
	var place_id: String = ""
	var place_focus: bool = false
	if debug_gf14_nc != "oldadopt":
		if _focused != null and _panels.has(_focused):
			place_id = _focused.payload
			place_focus = true
		elif _centre_index >= 0 and _centre_index < _visible_games.size():
			place_id = _visible_games[_centre_index].game_id
		elif _selected_game_id != "":
			place_id = _selected_game_id
	# Cached faces belong to the old library's truth (titles,
	# build counts, art can all change under a game_id across
	# a rescan): they die with the library that minted them.
	_face_tex_cache.clear()
	_face_cache_order.clear()
	_power_subject_cache.clear()
	_power_on_cache.clear()
	_free_panel_pool()
	_recompute_visible()
	_page = 0
	_centre_index = 0
	var place_idx: int = -1
	if place_id != "":
		for i: int in range(_visible_games.size()):
			if _visible_games[i].game_id == place_id:
				place_idx = i
				break
	if place_idx >= 0:
		_centre_index = place_idx
	_rebuild_wall()
	if place_focus and place_idx >= 0 and place_idx < _panels.size():
		_set_focused(_panels[place_idx])


## The card pool dies with its library: every pooled card node
## is freed (they are out of the tree or drum children - either
## way queue_free takes them), and the next rebuild mints fresh
## cards from the new scan's truth.
func _free_panel_pool() -> void:
	for gid: Variant in _panel_pool.keys():
		var nodes: Dictionary = _panel_pool[gid] as Dictionary
		var root: ClickableQuad = nodes.get("root") as ClickableQuad
		if root != null and is_instance_valid(root):
			if root.get_parent() != null:
				root.get_parent().remove_child(root)
			root.queue_free()
	_panel_pool.clear()
	_panel_face_key.clear()
	for cid: Variant in _board_pool.keys():
		var bnodes: Dictionary = _board_pool[cid] as Dictionary
		var broot: MeshInstance3D = bnodes.get("root") as MeshInstance3D
		if broot != null and is_instance_valid(broot):
			if broot.get_parent() != null:
				broot.get_parent().remove_child(broot)
			broot.queue_free()
	_board_pool.clear()
	_board_book.clear()
	_board_nodes.clear()
	_board_base_pos.clear()
	_board_pop_dir.clear()
	_board_tex_cache.clear()


## Take a fresh scanner as the room's library and rebuild
## (Main, when a scan lands). Until this existed the room
## kept the scanner it was built with, so a rescan's results
## only reached the wall through a process relaunch; the
## SETUP panel's scan lands HERE, in the room it was started
## from.
##
## While the SETUP panel stands, the adoption DEFERS: the
## landing used to rebuild the wall behind the open panel in
## the same moment the panel re-rendered its own face, and
## the two texture streams crossed (see TextureFactory) -
## the room woke wearing the panel's textures and bare
## highlight bars (Chris's after-scan strays, 2026-10-25).
## Behind a modal panel a scan changes NOTHING in the room:
## the scanner is held here, the panel alone shows the
## landing (its health and message are Main-fed), and the
## wall adopts the held library ONCE, when the panel closes
## (clear_setup_panel) - the player returns to a Table
## Select wall built cleanly from the new scan.
func adopt_library(scanner: LibraryScanner) -> void:
	if _setup_panel_up:
		_pending_library = scanner
		return
	if _launching_game_id != "":
		# GRADFIX14 (item 2): a scan that lands while the load
		# wait stands is HELD, exactly like the panel's hold -
		# never dropped. Main used to skip this call outright
		# during a wait, so when the launch then FAILED back
		# to the room, the room kept the pre-scan library for
		# the rest of the session while Main ran on the new
		# one. The wait is undisturbed (no rebuild behind it);
		# the held scan adopts when the wait settles back to
		# the wall (end_launch_failed). A successful hand-off
		# exits the process, and the next boot scans fresh.
		_pending_library = scanner
		return
	_scanner = scanner
	refresh_library()


## Adopt a held scan (the panel's close, the load wait's
## settle): the held library becomes the room's, once, and
## the wall rebuilds from it in place.
func _adopt_pending_library() -> void:
	if _pending_library == null:
		return
	var pending: LibraryScanner = _pending_library
	_pending_library = null
	_scanner = pending
	refresh_library()


## After a restore, centre the drum on the selected game and
## put the focus on its card. Runs once at setup; harmless
## no-ops when the game is not in the current filter.
func _restore_selection() -> void:
	if _selected_game_id == "":
		return
	for i: int in range(_visible_games.size()):
		if _visible_games[i].game_id == _selected_game_id:
			_set_centre(i, true)
			if i < _panels.size():
				_set_focused(_panels[i])
			return


## View state outlives the process (the launcher exits on every
## launch), so every view change lands in the store immediately.
func _persist_view() -> void:
	_store.set_view_state(_filter, _sort, _page, _selected_game_id)
	_store.save_to_disk()


# ---------------------------------------------------------------- rigs

func _build_rigs() -> void:
	var origin: XROrigin3D = XROrigin3D.new()
	origin.name = "XROrigin3D"
	add_child(origin)
	_xr_camera = XRCamera3D.new()
	origin.add_child(_xr_camera)
	for side: String in ["left", "right"]:
		var ctrl: XRController3D = XRController3D.new()
		ctrl.tracker = StringName("/user/hand/" + side)
		origin.add_child(ctrl)
	_desk_rig = Node3D.new()
	_desk_rig.position = EYE
	add_child(_desk_rig)
	_desk_camera = Camera3D.new()
	_desk_camera.fov = 70.0
	_desk_camera.current = not _xr_enabled
	_desk_rig.add_child(_desk_camera)
	_rig = PointerRig.new()
	add_child(_rig)
	_rig.xr_active = _xr_enabled
	_rig.mouse_camera = _desk_camera
	_rig.setup_controllers(origin)
	_rig.hover_changed.connect(_on_hover_changed)
	_rig.select_pressed.connect(_on_select)


func _active_camera() -> Camera3D:
	return _xr_camera if _xr_enabled else _desk_camera


## QA seam (the seated wall shots, the nav smoke): drop the flat
## camera to a seated player's eye height. The room's geometry is
## tuned around EYE (the face_point target); this moves only the
## desk rig, exactly what a shorter player changes in the headset.
func set_desk_camera_height(y: float) -> void:
	if _desk_rig != null:
		_desk_rig.position.y = y


# ---------------------------------------------------------- environment

func _build_environment() -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.012, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.44)
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)

	# GRADFIX5 (item 2): the floor is RETIRED - convicted as
	# the occluder that ate the sky's lower half (his
	# GRADFIX4 field verdict: "stars look a lot better but
	# disappear on lower half of dome", in BOTH rooms). The
	# GRADFIX4 shells themselves are whole: full spheres
	# centred on the eye, a direction field with no horizon
	# term - read in the shader, there is nothing to fade.
	# What stood in their way was this: a 14 x 14 m opaque
	# plane at y = -0.02 in near-black (0.045, 0.045, 0.065).
	# From the eye at 1.25, EVERY look direction below the
	# horizon meets that slab before it can reach either
	# shell (12 / 30 m) - steeply down it fills the frame,
	# at desk height it is the surface under the rail, and
	# only a grazing band a few degrees deep ever slipped
	# past its edges. The field read exactly that geometry:
	# stars to a clean horizon line, bare black below. The
	# slab was the flat room's ground and the DOME5 census's
	# occluder besides (the prototype's fault #3); in a room
	# whose sky is the point ("floating along in space"),
	# the enclosure is the starfield in every direction,
	# nadir included - the desk and rail now stand over open
	# sky. The census's floor LINE survives as a datum (no
	# label may sink below y = -0.0215); it was always a
	# placement rule, never this mesh.
	# The harness's negative control (PVLDS_GRADFIX5_NC=
	# floor) restores the slab so the sky-nadir legs can
	# fail against the convicted occluder by name.
	if OS.get_environment("PVLDS_GRADFIX5_NC") == "floor":
		var floor_inst: MeshInstance3D = MeshInstance3D.new()
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(14.0, 14.0)
		floor_inst.mesh = plane
		floor_inst.position = Vector3(0.0, -0.02, 0.0)
		var fm: StandardMaterial3D = StandardMaterial3D.new()
		fm.albedo_color = Color(0.045, 0.045, 0.065)
		fm.roughness = 0.95
		floor_inst.material_override = fm
		add_child(floor_inst)

	# The flat room's backdrop cylinder stood here (r 4.4,
	# a dark enclosure around the wall). The graduation
	# retires it: the background stack's starfield shell is
	# the room's enclosure now (see _build_background) - a
	# cylinder at 4.4 would hide every far layer behind it.

	var omni: OmniLight3D = OmniLight3D.new()
	omni.position = Vector3(0.0, 2.6, -0.6)
	omni.light_color = Color(1.0, 0.93, 0.8)
	omni.light_energy = 0.7
	omni.omni_range = 7.0
	add_child(omni)
	for sx: float in [-1.8, 1.8]:
		var spot: SpotLight3D = SpotLight3D.new()
		spot.position = Vector3(sx, 2.9, -0.4)
		spot.light_color = Color(1.0, 0.95, 0.85)
		spot.light_energy = 1.1
		spot.spot_range = 8.0
		spot.spot_angle = 42.0
		add_child(spot)
		spot.look_at(Vector3(sx * 0.4, 1.1, -WALL_RADIUS), Vector3.UP)

	_wall = Node3D.new()
	_wall.name = "Wall"
	add_child(_wall)
	_rail = Node3D.new()
	_rail.name = "Rail"
	add_child(_rail)
	_build_background()


## The room's background stack (the graduation's Stage B,
## banked by the user 2026-10-29): a far starfield shell and
## a near starfield shell - plus the haze the far window
## columns wear. (The stack once also carried a faint
## latitude/longitude wireframe shell and ONE tilted orbit
## ring; the ring was removed in GRADFIX4 and the wireframe
## shell in GRADFIX9, both on the user's order.)
## (see _haze_for). COMFORT LAW: every layer is WORLD-LOCKED
## - the stack hangs on the Room, never on the drum, and no
## layer animates, drifts, or breathes, ever; only the drum
## moves. The one deliberate exception is the harness's NC
## (PVLDS_BG_NC=drum parents the stack to the drum so the
## graduation smoke's world-lock leg can fail by name).
## The starfield dial (the SETUP panel's STARS button rides
## it), with the GRADFIX4 sky-pass semantics: "layered"
## shows both star shells AND drifts them (each on its own
## slow world-space rotation about the viewer - the floating
## parallax the user specced), "flat" shows the far shell
## alone, static, "off" no stars. The dial touches nothing
## else - since GRADFIX9 the two star shells are the whole
## stack. Every layer stays parented to the room
## (world space, centred on the eye): the drift is a
## rotation about the viewer, never a slide with the view.
func set_starfield_mode(mode: String) -> void:
	_starfield_mode = mode if ["layered", "flat", "off"].has(mode) else "layered"
	_apply_starfield_mode()


func starfield_mode() -> String:
	return _starfield_mode


## The wall motion (OPTIMIZE round): STEPPED is the only
## gait - the smooth-cruise saga is closed by the user's
## ruling and the drum advances on the stepped spring alone
## (see _update_swing). The SETUP panel's WALL MOTION button
## stands as a label; its action lands here and coerces to
## "stepped" like every other call. The driver mode is the
## same word, always.
func set_wall_motion_mode(mode: String) -> void:
	var telemetry_old_mode: String = _wall_motion_mode ## scroll telemetry: the dial event's before (read-only)
	_wall_motion_mode = "stepped" ## OPTIMIZE: any value coerces to the one gait
	if _scroll_telemetry_started and telemetry_old_mode != _wall_motion_mode:
		var dial_fields: Dictionary = _telemetry_context()
		dial_fields["old_mode"] = telemetry_old_mode
		dial_fields["new_mode"] = _wall_motion_mode
		dial_fields["source"] = "setup_panel" if _setup_panel_up else "set_wall_motion_mode"
		_telemetry_record("wall_motion_mode_changed", dial_fields)


func wall_motion_mode() -> String:
	return _wall_motion_mode


func _wall_driver_mode() -> String:
	return "stepped"


func wall_driver_mode() -> String:
	return _wall_driver_mode()


## ------------------------------------------------ scroll telemetry hooks
## The witness's read-only hooks (see the state block at
## _scroll_telemetry). _telemetry_context snapshots the
## standing scroll state for a record; nothing here assigns
## anything outside the logger.

func _telemetry_start_if_needed() -> void:
	if _scroll_telemetry_started or not visible:
		return
	_scroll_telemetry_started = _scroll_telemetry.start({
		"build_stamp": ScrollTelemetry.BUILD_STAMP,
		"base_commit": ScrollTelemetry.BASE_COMMIT,
		"face_px": [CARD_FACE_PX.x, CARD_FACE_PX.y], ## GF18-HALFRES: the face texture size in force, so a returned log self-identifies the diagnostic's one variable
		"log_path": ScrollTelemetry.LOG_PATH,
		"wall_motion_mode_at_boot": wall_motion_mode(),
		"wall_driver_mode_at_boot": _wall_driver_mode(),
		"wall_radius": WALL_RADIUS, ## OPTIMIZE telemetry header
		"gait": "stepped", ## OPTIMIZE telemetry header
		"view_at_room_entry": "tournament" if _tournament else "library",
		"filter_at_room_entry": _filter,
		"sort_at_room_entry": _sort,
		"room_mode_at_entry": _mode,
		"visible_games_at_entry": _visible_games.size(),
		"columns_at_entry": _columns,
		"centre_index_at_entry": _centre_index,
	})


func _telemetry_context() -> Dictionary:
	var centre_col: int = -1
	if _centre_index >= 0 and _centre_index < _panels.size():
		centre_col = _grid_coord(_centre_index).x
	return {
		"wall_motion_mode": _wall_motion_mode,
		"wall_driver_mode": _wall_driver_mode(),
		"room_mode": _mode,
		"tournament": _tournament,
		"setup_panel_up": _setup_panel_up,
		"submit_panel_up": _submit_panel_up,
		"placard_up": _placard_up,
		"launch_wait": _launching_game_id != "",
		"focused_panel_index": _panels.find(_focused) if _focused != null else -1,
		"centre_index": _centre_index,
		"centre_column": centre_col,
		"columns": _columns,
		"swing_active": _swing_active,
		"swing_target_yaw_deg": rad_to_deg(_swing_to),
		"drum_yaw_deg": rad_to_deg(_drum_yaw),
		"applied_yaw_deg": rad_to_deg(_wall.rotation.y) if _wall != null else rad_to_deg(_drum_yaw),
		"angular_velocity_deg_s": rad_to_deg(_swing_vel),
		"gait": "stepped",
		"nc_roll_dir": _nc_roll_dir,
		"hold_dir_x": _joy_hold_dir.x,
		"hold_dir_y": _joy_hold_dir.y,
		"hold_steps": _joy_hold_steps,
	}


func _telemetry_record(kind: String, fields: Dictionary) -> void:
	if not _scroll_telemetry_started or not visible:
		return
	_telemetry_drain_art_events()
	_scroll_telemetry.record(kind, fields)


## GRADFIX17: stage one art-pipeline event for the scroll
## telemetry log. Callable from any thread (the decode pump
## stages its decode start/end here): the whole cost is one
## mutex, one dictionary append, one unlock. Costs and wall
## stamps are measured BY THE SEAM and carried in fields -
## the record's own t_ms is the drain time (within a frame
## on the main thread, a frame or two for the pump), never
## the evidence. The pending array is capped: a witness
## that grows without bound would become the fault it hunts.
func _art_event(event: String, fields: Dictionary) -> void:
	if _art_tel_mode < 0:
		_art_tel_mode = 0 if OS.get_environment("PVLDS_GF17_TEL") == "off" else 1
	if _art_tel_mode == 0:
		return
	var rec: Dictionary = {"event": event}
	for key: Variant in fields.keys():
		rec[key] = fields[key]
	_art_tel_mutex.lock()
	if _art_tel_pending.size() < 1024:
		_art_tel_pending.append(rec)
	_art_tel_mutex.unlock()


## Main thread only: move staged art events into the log as
## kind "art" records (a NEW kind - the shipped kinds keep
## their exact shape for Chris's A/B reads). Called from
## _telemetry_record, so drains ride the log's own cadence.
func _telemetry_drain_art_events() -> void:
	if not _scroll_telemetry_started:
		return
	_art_tel_mutex.lock()
	var staged: Array[Dictionary] = _art_tel_pending.duplicate()
	_art_tel_pending.clear()
	_art_tel_mutex.unlock()
	for rec: Dictionary in staged:
		_scroll_telemetry.record("art", rec)


## OPTIMIZE round: the wall's residency account - what the
## room's face cache holds at this moment, measured the way
## the GF18 gauge measured it (live face textures, bytes
## estimated from pixel size at 4 bytes/px). This is the
## eviction law's own gauge: resident faces/bytes, the
## evictions since boot, and the law's margin and cap.
func residency_stats() -> Dictionary:
	var face_bytes: int = 0
	for key: Variant in _face_tex_cache.keys():
		var entry: Variant = _face_tex_cache[key]
		if entry is Array:
			var earr: Array = entry as Array
			if earr.size() > 0 and earr[0] is Texture2D:
				var tex: Texture2D = earr[0] as Texture2D
				face_bytes += tex.get_width() * tex.get_height() * 4
	return {
		"resident_faces": _face_tex_cache.size(),
		"resident_bytes": face_bytes,
		"evicted_total": _evicted_total,
		"margin_cols": EVICT_MARGIN_COLS,
		"cap_faces": RESIDENT_FACES_CAP,
	}


## OPTIMIZE round: the staged pipeline's apply account -
## applies since boot, how many landed while the drum
## travelled, and the most that ever landed in one engine
## frame (APPLY_CAP_PER_FRAME is the law; the
## debug_opt_nc="streamahead" seam exists to break it).
func art_frame_stats() -> Dictionary:
	return {
		"applies_total": _applies_total,
		"applies_during_travel": _applies_during_travel,
		"max_applies_one_frame": _applies_max_one_frame,
		"swaps_total": _swaps_total,
		"swaps_during_travel": _swaps_during_travel,
		"max_swaps_one_frame": _swaps_max_one_frame,
	}


## Count one landed staged apply (the apply-cap account).
func _note_apply(travelling: bool) -> void:
	_applies_total += 1
	if travelling:
		_applies_during_travel += 1
	var fid: int = Engine.get_process_frames()
	if fid != _applies_frame_id:
		_applies_frame_id = fid
		_applies_this_frame = 0
	_applies_this_frame += 1
	_applies_max_one_frame = maxi(_applies_max_one_frame, _applies_this_frame)


## Count one landed staged SWAP (FACECACHE): a fill the
## composed-face cache served as a pointer swap. Swaps ride
## their own account - the apply cap exists to bound the
## main-thread cost of composed RENDERS, and a swap is not
## one (the GF18 measurement put it at ~0.34 ms), so a swap
## never spends the cap's frame and never inflates its max.
func _note_swap(travelling: bool) -> void:
	_swaps_total += 1
	if travelling:
		_swaps_during_travel += 1
	var fid: int = Engine.get_process_frames()
	if fid != _swaps_frame_id:
		_swaps_frame_id = fid
		_swaps_this_frame = 0
	_swaps_this_frame += 1
	_swaps_max_one_frame = maxi(_swaps_max_one_frame, _swaps_this_frame)


## OPTIMIZE telemetry: a step's travel began (from _set_centre's
## retarget). Chained retargets mid-swing extend the standing
## step's target; the record lands when the swing lands.
func _step_begin(from_col: int, to_col: int) -> void:
	if _step_from_col < 0:
		_step_from_col = from_col
		_step_start_msec = Time.get_ticks_msec()
	_step_to_col = to_col


## OPTIMIZE telemetry: the standing step landed - emit its
## record with the measured settle duration.
func _step_landed() -> void:
	if _step_from_col < 0:
		return
	var fields: Dictionary = _telemetry_context()
	fields["from_centre"] = _step_from_col
	fields["to_centre"] = _step_to_col
	fields["settle_ms"] = float(Time.get_ticks_msec() - _step_start_msec)
	_telemetry_record("step", fields)
	_step_from_col = -1
	_step_to_col = -1


func _apply_starfield_mode() -> void:
	if _bg_starfield != null:
		_bg_starfield.visible = _starfield_mode != "off"
	if _bg_starfield_near != null:
		_bg_starfield_near.visible = _starfield_mode == "layered"


## The drift, one frame's worth (GRADFIX4 item 5d): in
## LAYERED mode each star shell turns about the viewer at
## its own speed (BG_DRIFT_*_DEG) - world-space rotation, so
## a head turn sweeps both layers across the view opposite
## the turn, the near layer faster, with the drift adding
## on top. FLAT and OFF stand still. Called from _process;
## never gated on input state.
func _update_background(delta: float) -> void:
	if _starfield_mode != "layered":
		return
	if _bg_starfield != null:
		_bg_starfield.rotation.y += deg_to_rad(BG_DRIFT_FAR_DEG) * delta
	if _bg_starfield_near != null:
		_bg_starfield_near.rotation.y += deg_to_rad(BG_DRIFT_NEAR_DEG) * delta


## The drift's standing state (the sky-pass proofs read it):
## each shell's accumulated world-space yaw about the viewer.
func starfield_drift_state() -> Dictionary:
	return {
		"mode": _starfield_mode,
		"far_yaw_deg": rad_to_deg(_bg_starfield.rotation.y) if _bg_starfield != null else 0.0,
		"near_yaw_deg": rad_to_deg(_bg_starfield_near.rotation.y) if _bg_starfield_near != null else 0.0,
		"far_speed_deg_s": BG_DRIFT_FAR_DEG,
		"near_speed_deg_s": BG_DRIFT_NEAR_DEG,
	}


func _build_background() -> void:
	_bg_root = Node3D.new()
	_bg_root.name = "BackgroundStack"
	if debug_bg_nc == "drum" and _wall != null:
		_wall.add_child(_bg_root)
	else:
		add_child(_bg_root)
	# The starfield shell: one inward sphere, a procedural
	# direction-field star shader - no texture, the room's
	# far enclosure (it replaces the flat room's backdrop
	# cylinder, retired above). In LAYERED mode it drifts on
	# its own world-space rotation (see _update_background).
	var stars: MeshInstance3D = MeshInstance3D.new()
	stars.name = "StarfieldShell"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = BG_STAR_RADIUS
	sphere.height = BG_STAR_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	stars.mesh = sphere
	var sm: ShaderMaterial = ShaderMaterial.new()
	var sh: Shader = Shader.new()
	sh.code = BG_STAR_SHADER_UV if debug_bg_nc == "uv" else BG_STAR_SHADER
	sm.shader = sh
	stars.material_override = sm
	stars.position = EYE
	_bg_root.add_child(stars)
	_bg_starfield = stars
	# The near star shell (the GRAD FIX round): a second,
	# nearer sphere of brighter, sparser pinpoints with no
	# sky of its own - the far shell shows through it.
	# Layered mode stands both and drifts both (the field
	# parallaxes under head motion AND under the drift);
	# flat keeps the far shell alone, static; off kills
	# both. Both shells stay centred on the eye in world
	# space, like every layer.
	var near_stars: MeshInstance3D = MeshInstance3D.new()
	near_stars.name = "StarfieldNearShell"
	var near_sphere: SphereMesh = SphereMesh.new()
	near_sphere.radius = BG_STAR_NEAR_RADIUS
	near_sphere.height = BG_STAR_NEAR_RADIUS * 2.0
	near_sphere.radial_segments = 48
	near_sphere.rings = 24
	near_stars.mesh = near_sphere
	var nsm: ShaderMaterial = ShaderMaterial.new()
	var nsh: Shader = Shader.new()
	nsh.code = BG_STAR_NEAR_SHADER_UV if debug_bg_nc == "uv" else BG_STAR_NEAR_SHADER
	nsm.shader = nsh
	near_stars.material_override = nsm
	near_stars.position = EYE
	_bg_root.add_child(near_stars)
	_bg_starfield_near = near_stars
	# GRADFIX9: the wireframe shell is REMOVED (Chris's
	# order, 2026-10-31 - "drop the wireframe shell
	# entirely, like the ring and the fins"). The dome's
	# faint latitude/longitude line shell read, looking
	# straight down, as lines converging at a central point
	# and radiating outward over the whole globe - the
	# nadir pole pinch his capture showed. No builder, no
	# mesh, no field remains; wireframe_shell_count() is
	# the standing census and the smokes assert zero.
	# Nothing replaces it: the stack is the two star
	# shells alone.
	# GRADFIX4 (item 5e): the orbit ring is REMOVED. The old
	# 63/17 tilt read as a straight scratch line across the
	# sky from below (his capture), and the reworked 32/7
	# tilt with a thicker tube still read as a band, not a
	# ring, in the level and below grabs - a 9 m great circle
	# only ever shows a gently curved arc inside a headset's
	# field of view, never a closed ring. The task's fork
	# named the outcome: rework until it reads as a ring, or
	# remove it. The drifting pinpoint layers are the sky
	# now; _bg_ring stays null and background_layers() omits
	# it.
	_apply_starfield_mode()


## The haze a card wears by its column's distance from the
## centre (the background stack's fourth layer): full
## presence inside 6 columns, easing to HAZE_FLOOR at the
## window's edge - far cards dim and cool into the room
## instead of ending at a hard window edge.
func _haze_for(idx: int) -> float:
	if _centre_index < 0 or idx < 0 or idx >= _visible_games.size():
		return 1.0
	var dist: int = absi(_grid_coord(idx).x - _grid_coord(_centre_index).x)
	if dist <= 6:
		return 1.0
	return lerpf(1.0, HAZE_FLOOR, clampf(float(dist - 6) / 4.0, 0.0, 1.0))


# -------------------------------------------------------------- library

func _recompute_visible() -> void:
	_filter_note = ""
	_collect_visible()
	# Empty-net guard (the letter-jump round): a standing net
	# whose last member just left the filter's set (the last
	# THE favorite un-flagged from inside the net) must not
	# present as an empty room either - the net lifts, the
	# plain filtered list shows, and the banner says why.
	# The Tournament Room is exempt from both guards below:
	# its empty states (no key, no live challenges, a failed
	# fetch) are real states with their own state panel, not
	# a broken filter to fall back from.
	if not _tournament and _visible_games.is_empty() and _letter_net != "" and _scanner != null and not _scanner.games.is_empty():
		_filter_note = "%s view is empty here - showing the full list" % _letter_net
		_letter_net = ""
		_collect_visible()
	# Empty-filter guard: a filter that matches nothing in a non-empty
	# library must never present as an empty room (that is exactly how
	# the sample-database trap showed up in the field - a black wall
	# and "1/1"). Fall back to ALL and let the banner say why. VR
	# stays the default only when VR-tagged games actually exist.
	if not _tournament and _filter != "all" and _visible_games.is_empty() and _scanner != null and not _scanner.games.is_empty():
		_filter_note = "%s filter found none - showing ALL" % str(FILTER_LABELS[_filter])
		_filter = "all"
		_collect_visible()
	var pages: int = page_count()
	if _page >= pages:
		_page = maxi(0, pages - 1)


## The current filter's collection, unsorted and net-free:
## the set the wall draws from, and the set the alphabet
## strip's presence is read over (the strip indexes what the
## filter could show, never just the standing net's members -
## its letters must stay pickable from inside a net view,
## because picking one is how the net exits).
func _collect_filtered() -> Array[GameEntry]:
	var source: Array[GameEntry] = []
	if _scanner == null:
		return source
	if _filter == "recents":
		for gid: String in _store.recents:
			var g: GameEntry = _scanner.game_by_id(gid)
			if g != null:
				source.append(g)
	else:
		# GRADFIX11: the NEW filter's judging instant,
		# taken once per collection so every game in the
		# set is judged against the same clock.
		var now: int = int(Time.get_unix_time_from_system())
		for g: GameEntry in _scanner.games:
			match _filter:
				"all":
					source.append(g)
				"vr":
					if g.is_vr_tagged():
						source.append(g)
				"favorites":
					if _store.is_favorite(g.game_id):
						source.append(g)
				"new":
					if g.is_new(now):
						source.append(g)
	return source


func _collect_visible() -> void:
	if _tournament:
		# The Tournament Room's wall: one panel per live
		# challenge (or a single state panel saying why there
		# are none), in the league's own order - no sort, no
		# net. _tournament_rows stays aligned 1:1 with
		# _visible_games; the games are the matched library
		# entries (launchable) or synthetic stand-ins for
		# tables he does not own and for state panels (inert).
		_tournament_rows = _build_tournament_rows()
		_visible_games = []
		for r: Variant in _tournament_rows:
			_visible_games.append((r as Dictionary)["game"] as GameEntry)
		return
	_tournament_rows = []
	var source: Array[GameEntry] = _collect_filtered()
	if _letter_net != "":
		# The net view: exactly the net's members out of the
		# filter's set, in title order - the THE set sorted by
		# the word after "The" falls out of the name sort,
		# whose key is the sort title (see _title_key).
		var members: Array[GameEntry] = []
		for g: GameEntry in source:
			if LetterIndex.in_net(g.title, _letter_net):
				members.append(g)
		source = members
	_visible_games = source
	if _letter_net != "":
		_sort_by_name()
	elif _filter == "new":
		# GRADFIX11: the NEW filter's standing order is
		# recency - newest first - not the SORT stop's
		# order. The letter net above still name-sorts
		# (a letter pick stays inside NEW, as it does in
		# favorites), and recents below still keeps its
		# store order; the SORT stop keeps governing the
		# other filters exactly as before.
		_sort_by_newness()
	elif _filter != "recents":
		_sort_visible()


## ------------------------------------------------------ Tournament Room

## Main's delivery of the WoVP state: whose key, the
## last-good boards (live or the disk cache's), when they
## landed, and the last fetch's failure when it failed. The
## wall renders exactly this and nothing else - no boards
## are ever invented locally, and a failed refresh keeps
## the last good boards WITH their stamp and the failure
## stated (see _tournament_banner_line), never dressed as
## live.
## NEXTROUND (item 4): Main's push of the PINemHi personal
## bests it read from the player's own install (the room
## never touches the disk for this). A changed map re-seats
## the standing boards - their content keys carry the best.
func set_pinemhi_bests(bests: Dictionary) -> void:
	if bests == _pinemhi_bests:
		return
	_pinemhi_bests = bests
	if _tournament:
		# The boards' content keys carry the best line, so
		# a re-render under the new key is the refresh's
		# whole job (the render's own key check decides).
		for idx: int in range(_board_nodes.size()):
			_render_tournament_board(idx)


## CARDBACK: Main's push of the IPDB cache (facts by game
## id + the cache stamp). The stamp rides the back's
## content key, so when a fetch lands while a card stands
## flipped, the back heal re-renders it under the new key -
## the same discipline the boards' fetch stamp uses.
func set_ipdb_facts(facts: Dictionary, stamp: int) -> void:
	var stamp_changed: bool = stamp != _ipdb_stamp
	_ipdb_facts = facts
	_ipdb_stamp = stamp
	# BACKTRIM: a changed stamp is the facts' new name -
	# a back standing open under the old name re-renders
	# under the new key, the same heal fresh boards get
	# in set_wovp_data (whose own heal reads the stamp
	# before this push lands, so it cannot carry this
	# one). An unchanged stamp - a repeat push of the
	# same facts - touches nothing: no churn.
	if stamp_changed and _flip_idx >= 0:
		_flip_key = _card_back_key(_flip_idx)
		_refresh_card_back()


func set_wovp_data(d: Dictionary) -> void:
	_wovp_has_key = bool(d.get("has_key", false))
	_wovp_user_id = str(d.get("user_id", ""))
	_wovp_shots_folder = str(d.get("shots_folder", _wovp_shots_folder))
	_wovp_challenges = []
	var arr: Variant = d.get("challenges", [])
	if arr is Array:
		var a: Array = arr
		for c: Variant in a:
			if c is WovpChallenge:
				_wovp_challenges.append(c)
	_wovp_fetched_at = int(d.get("fetched_at", 0))
	_wovp_live = bool(d.get("live", false))
	_wovp_fetch_error = str(d.get("fetch_error", ""))
	if _tournament:
		_recompute_visible()
		_rebuild_wall()
	else:
		# Fresh boards can give the flipped card a back it
		# did not have (or change the one it has): the back's
		# key carries the fetch stamp, so a re-render under
		# the new key is the refresh's whole job.
		if _flip_idx >= 0:
			_flip_key = _card_back_key(_flip_idx)
			_refresh_card_back()
	# Fresh WoVP data re-derives the tournie borders
	# (GRADFIX8 item 4): a challenge that appeared gains
	# its ring, one that ended loses it - on the standing
	# wall, without waiting for a rebuild.
	_apply_tourney_borders()


func tournament_active() -> bool:
	return _tournament


## The standing view's rows (the smoke's read of the wall's
## own truth): aligned with _visible_games while the
## Tournament Room stands, empty otherwise.
func tournament_rows() -> Array:
	return _tournament_rows.duplicate()


## RETURN round: where a launch of this game comes from, in
## the store's record shape ({surface, challenge_id}). The
## classification keys on (this view, the launched game), not
## on the input path, so the A-press, the pointer's Launch,
## and the detail view's Play all classify alike: in the
## Tournament Room, the launched game's own challenge row
## names the origin (by challenge ID, never by index); a
## tournie launch that somehow matches no row still records
## the tournament surface with an empty ID, which restores
## to the room's default landing. Everywhere else the origin
## is the library.
func launch_origin_for(game: GameEntry) -> Dictionary:
	if game == null or not _tournament:
		return {"surface": "library", "challenge_id": ""}
	for row: Variant in _tournament_rows:
		var r: Dictionary = row as Dictionary
		if str(r.get("kind", "")) != "challenge":
			continue
		var row_game: GameEntry = r.get("game") as GameEntry
		if row_game != null and row_game.game_id == game.game_id:
			var ch: WovpChallenge = r.get("challenge") as WovpChallenge
			return {"surface": "tournament",
				"challenge_id": ch.challenge_id if ch != null else ""}
	return {"surface": "tournament", "challenge_id": ""}


## The row index of one challenge in the standing tournament
## view, by challenge ID - or -1 when it does not stand
## (ended, refreshed away, never there).
func _tournament_row_index_for_challenge(challenge_id: String) -> int:
	if challenge_id == "":
		return -1
	for i: int in range(_tournament_rows.size()):
		var r: Dictionary = _tournament_rows[i] as Dictionary
		if str(r.get("kind", "")) != "challenge":
			continue
		var ch: WovpChallenge = r.get("challenge") as WovpChallenge
		if ch != null and ch.challenge_id == challenge_id:
			return i
	return -1


## The challenge ID of the focused card in the Tournament
## Room, or "" when focus stands anywhere else (a rail stop,
## a state row, the library). The return smoke's read of
## where a return landing actually put the player.
func tournament_focused_challenge_id() -> String:
	if not _tournament or _focused == null:
		return ""
	var idx: int = _panels.find(_focused)
	if idx < 0 or idx >= _tournament_rows.size():
		return ""
	var r: Dictionary = _tournament_rows[idx] as Dictionary
	if str(r.get("kind", "")) != "challenge":
		return ""
	var ch: WovpChallenge = r.get("challenge") as WovpChallenge
	return ch.challenge_id if ch != null else ""


## The banner while the Tournament Room stands: the boards'
## provenance in one line - how many, when they landed, and
## when they are not fresh, exactly that.
func _tournament_banner_line() -> String:
	if not _wovp_has_key:
		return "Tournament Room - no WoVP key yet (add it in SETUP)"
	if _wovp_challenges.is_empty():
		if _wovp_fetch_error != "" and _wovp_fetched_at == 0:
			return "Tournament Room - could not reach WoVP"
		if _wovp_fetched_at == 0:
			return "Tournament Room - fetching..."
		return "Tournament Room - no live challenges right now"
	var line: String = "Tournament Room - %d live challenges" % _wovp_challenges.size()
	if _wovp_fetched_at > 0:
		line += " - updated " + WovpTime.format_stamp(_wovp_fetched_at)
	if _wovp_fetch_error != "":
		line += " - refresh failed, showing the last good boards"
	elif not _wovp_live:
		line += " - saved boards, not yet refreshed"
	return line


## The standing view's rows from the standing data. A
## challenge he owns joins his library by its VPS game id
## against the scanner's match data (the join is game-level
## - the build the wall launches is his default), and the
## build half of the truth rides along in the row: whether
## any of his builds IS the challenge's build, by the VPS
## table-file id the challenge carries. The board's chip
## reads the pair (owned, build_owned) - see
## RoomSpecs.tournament_board_spec.
func _build_tournament_rows() -> Array:
	var rows: Array = []
	if not _wovp_has_key:
		rows.append(_tournament_state_row([
			"No WoVP key yet.",
			"Add your key in SETUP - PASTE KEY there (copy it first), or paste it on the desktop desk.",
			"The key lives only on this PC.",
		]))
		return rows
	if _wovp_challenges.is_empty():
		if _wovp_fetch_error != "" and _wovp_fetched_at == 0:
			rows.append(_tournament_state_row([
				"Could not reach WoVP.",
				_wovp_fetch_error,
				"Press REFRESH on the rail to try again.",
			]))
		elif _wovp_fetched_at == 0:
			rows.append(_tournament_state_row([
				"Fetching your live challenges from WoVP...",
			]))
		else:
			rows.append(_tournament_state_row([
				"No live challenges right now.",
				"Last checked " + WovpTime.format_stamp(_wovp_fetched_at) + ".",
			]))
		return rows
	for ch: WovpChallenge in _wovp_challenges:
		var game: GameEntry = _match_challenge(ch)
		var owned: bool = game != null
		if not owned:
			game = _tournament_unowned_game(ch)
		rows.append({"kind": "challenge", "challenge": ch, "game": game, "owned": owned,
			"build_owned": owned and _challenge_build_owned(game, ch), "lines": []})
	return rows


func _tournament_state_row(lines: Array) -> Dictionary:
	var game: GameEntry = GameEntry.new()
	game.game_id = "wovp:state"
	game.title = "Tournament Room"
	return {"kind": "state", "challenge": null, "game": game, "owned": false, "lines": lines}


func _tournament_unowned_game(ch: WovpChallenge) -> GameEntry:
	var game: GameEntry = GameEntry.new()
	game.game_id = "wovp:none:" + ch.challenge_id
	game.title = ch.table_name if ch.table_name != "" else ch.name
	game.manufacturer = ch.table_manufacturer
	game.year = ch.table_year
	return game


func _match_challenge(ch: WovpChallenge) -> GameEntry:
	if _scanner == null or ch.table_external_id == "":
		return null
	return _scanner.game_by_id(ch.table_external_id)


## Whether any of his builds of this game IS the challenge's
## build, by the VPS table-file id the challenge carries
## (WovpChallenge.version_external_id). A build his scan
## resolved to the game only - its table_file_id still "" -
## is not the challenge's build, and neither is a db build
## of the game he happens not to hold. A challenge carrying
## no version id specifies no build, so there is nothing to
## miss: every build of the game serves, and this reads true.
func _challenge_build_owned(game: GameEntry, ch: WovpChallenge) -> bool:
	if game == null or ch == null:
		return false
	if ch.version_external_id == "":
		return true
	for b: TableBuild in game.builds:
		if b.table_file_id == ch.version_external_id:
			return true
	return false


## GRADFIX8 (item 4): the tournie border's data, derived
## from the SAME cached WoVP challenges the Tournament
## Room renders (_wovp_challenges, pushed by Main via
## set_wovp_data - no network at room time, and a cache
## refresh re-derives this whole map, so a challenge that
## ends loses its border on the next push/rebuild).
## game_id -> {type_code, color, challenge_id, end_unix}
## for every library game holding at least one live
## challenge. A game with several wears its SOONEST-
## CLOSING challenge's colour (smallest end_unix; an
## end-less challenge sorts last; an exact end tie breaks
## on the smaller challenge_id, so the pick is stable
## across refreshes of the same data).
func tourney_border_map() -> Dictionary:
	var out: Dictionary = {}
	if debug_gf8_nc == "noborder":
		return out
	for cv: Variant in _wovp_challenges:
		var ch: WovpChallenge = cv as WovpChallenge
		if ch == null:
			continue
		var g: GameEntry = _match_challenge(ch)
		if g == null:
			continue
		var end_key: int = ch.end_unix if ch.end_unix > 0 else 2000000000
		var cur: Dictionary = out.get(g.game_id, {}) as Dictionary
		var take: bool = cur.is_empty() or end_key < int(cur.get("end_key", 0)) \
			or (end_key == int(cur.get("end_key", 0)) and ch.challenge_id < str(cur.get("challenge_id", "")))
		if take:
			out[g.game_id] = {
				"type_code": ch.type_code,
				"color": RoomSpecs.challenge_type_color(ch.type_code),
				"challenge_id": ch.challenge_id,
				"end_unix": ch.end_unix,
				"end_key": end_key,
			}
	return out


## The border's shared material for one challenge type:
## minted once per type (four types exist), shared by
## every bordered card of that type. The animation runs
## off the shader's TIME - no per-frame CPU anywhere.
func _tourney_border_mat(type_code: String, color: Color) -> ShaderMaterial:
	var existing: ShaderMaterial = _border_mats.get(type_code) as ShaderMaterial
	if existing != null:
		return existing
	if _border_shader == null:
		_border_shader = Shader.new()
		_border_shader.code = TOURNEY_BORDER_SHADER
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = _border_shader
	m.render_priority = -5 ## the ring draws before the face (-3) and its furniture; its interior is discarded, so nothing is covered
	m.set_shader_parameter("border_color", color)
	m.set_shader_parameter("global_alpha", clampf(_wall_alpha_applied, 0.0, 1.0))
	_border_mats[type_code] = m
	return m


## Seat (or clear) every pooled card's tournie border
## from the standing WoVP data. Runs over the whole pool
## - not just the standing window - so a card pooled by
## an earlier view can never carry a stale border into
## this one, and a refresh that ends a challenge clears
## its card wherever it stands. The border shows only
## in the LIBRARY (Table Select): in the Tournament
## Room every card is a challenge card and the boards
## beside them are the headline there.
func _apply_tourney_borders() -> void:
	var map: Dictionary = tourney_border_map()
	var in_library: bool = not _tournament
	for gid: Variant in _panel_pool.keys():
		var nodes: Dictionary = _panel_pool[gid] as Dictionary
		if str(nodes.get("mode", "")) != "card":
			continue
		var border: MeshInstance3D = nodes.get("border") as MeshInstance3D
		if border == null:
			continue
		var info: Dictionary = map.get(str(gid), {}) as Dictionary
		var on: bool = in_library and not info.is_empty()
		border.visible = on
		nodes["border_on"] = on
		if on:
			var type_code: String = str(info.get("type_code", ""))
			var color: Color = info.get("color", Color.WHITE)
			border.material_override = _tourney_border_mat(type_code, color)
			nodes["border_type"] = type_code
			nodes["border_color"] = color
		else:
			nodes["border_type"] = ""
			nodes["border_color"] = Color(0.0, 0.0, 0.0, 0.0)


## One game's standing border state (the grad census's
## read): whether its ring stands, and the colour/type
## it was applied with.
func tourney_border_state(game_id: String) -> Dictionary:
	var nodes: Dictionary = _panel_pool.get(game_id, {}) as Dictionary
	if nodes.is_empty():
		return {"on": false, "type_code": "", "color": Color(0.0, 0.0, 0.0, 0.0), "has_node": false}
	var border: MeshInstance3D = nodes.get("border") as MeshInstance3D
	return {
		"on": bool(nodes.get("border_on", false)) and border != null and border.visible,
		"type_code": str(nodes.get("border_type", "")),
		"color": nodes.get("border_color", Color(0.0, 0.0, 0.0, 0.0)),
		"has_node": border != null,
	}


## Enter the Tournament Room: the wall becomes the boards
## (whatever data already stands - the cache at boot), and
## a fetch is requested so what stands becomes live. Focus
## lands on the TOURNAMENT stop (the rail law: a press lands
## on the stop that was pressed).
func _enter_tournament() -> void:
	_failed_game_id = ""
	_status_note = ""
	_tournament = true
	_letter_net = ""
	_page = 0
	_centre_index = 0
	_recompute_visible()
	_rebuild_wall()
	_persist_view()
	_land_on_rail_stop("tournament")
	tournament_refresh_requested.emit()


## Leave the Tournament Room for a library view. Called by
## every rail branch that rebuilds the wall as the library
## (filters, sort) and by a letter pick - the views are
## alternatives, never layers.
func _exit_tournament() -> void:
	_tournament = false


## B in the Tournament view returns to Table Select
## (GRADFIX4 item 4 - the user's hand voted: "I feel like I
## want to press B in tournie screen to get to table
## select"). B was unassigned in the room's wall mode - it
## served only the detail view's escape and the SETUP
## panel's close - so this claims no other mapping. The
## exit mirrors the rail exits exactly (fresh centre, the
## library wall rebuilt, the view persisted) and lands the
## focus on the bar's tournament stop, where his hand
## already is - the rail law (an activation keeps focus on
## the bar) applied to a departure.
func _b_exit_tournament() -> void:
	_exit_tournament()
	_page = 0
	_centre_index = 0
	_recompute_visible()
	_rebuild_wall()
	_persist_view()
	_land_on_rail_stop("tournament")


## RETURN round: a session that launched from the Tournament
## Room returns to it. Called by Main at room entry when a
## consumed return-origin record names this surface (the
## boards Main just pushed are the data the rows build from,
## cache or live). Mirrors _enter_tournament's landing, then
## seats the launched challenge - centred, focused, its board
## beside it - when it still stands; when it has gone (ended,
## refreshed away, rescanned away), the landing is the manual
## entry's own default: the TOURNAMENT rail stop, the room at
## its first row. Either way a fetch is requested, exactly as
## a manual entry asks, so the board beside the card is live
## for what the player came back to do (Y - submit).
func restore_tournament_return(challenge_id: String) -> void:
	_failed_game_id = ""
	_status_note = ""
	_tournament = true
	_letter_net = ""
	_page = 0
	_centre_index = 0
	_recompute_visible()
	_rebuild_wall()
	_persist_view()
	var idx: int = _tournament_row_index_for_challenge(challenge_id)
	if idx >= 0:
		_set_centre(idx, true)
		if idx < _panels.size():
			_set_focused(_panels[idx])
		print("ROOM RETURN: back to the Tournament Room - challenge %s standing, focused" % challenge_id)
	else:
		_land_on_rail_stop("tournament")
		print("ROOM RETURN: back to the Tournament Room - challenge '%s' no longer standing, default landing" % challenge_id)
	tournament_refresh_requested.emit()


func page_count() -> int:
	if _visible_games.is_empty():
		return 1
	return int(ceil(float(_visible_games.size()) / float(PAGE_SIZE)))


## The wall's title key: the sort title (a leading "The "
## dropped - LetterIndex), lowercased. Title sort files The
## Addams Family under A, which is what makes the alphabet
## strip's letters and the wall's own pages one truth: a
## letter's first page in title sort is where that letter's
## games actually start. Every other sort tiebreaks on the
## same key, so "the title the wall sorts by" is one notion.
func _title_key(g: GameEntry) -> String:
	return LetterIndex.sort_title(g.title).to_lower()


func _title_less(a: GameEntry, b: GameEntry) -> bool:
	var ka: String = _title_key(a)
	var kb: String = _title_key(b)
	if ka != kb:
		return ka < kb
	return a.title.to_lower() < b.title.to_lower()


func _sort_by_name() -> void:
	_visible_games.sort_custom(_title_less)


## GRADFIX11: the NEW filter's order - newest file fact
## first (GameEntry.newest_stamp, descending); ties break
## on the same title key _sort_by_name uses, so equal-age
## games stand in the wall's one title order.
func _sort_by_newness() -> void:
	_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
		var as_: int = a.newest_stamp()
		var bs: int = b.newest_stamp()
		if as_ != bs:
			return as_ > bs
		return _title_less(a, b))


func _sort_visible() -> void:
	match _sort:
		"name":
			_sort_by_name()
		"year":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				var ay: int = a.year if a.year > 0 else 9999
				var by: int = b.year if b.year > 0 else 9999
				if ay != by:
					return ay < by
				return _title_less(a, b))
		"manufacturer":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				if a.manufacturer.to_lower() != b.manufacturer.to_lower():
					return a.manufacturer.to_lower() < b.manufacturer.to_lower()
				return _title_less(a, b))
		"designer":
			_visible_games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
				var ad: String = a.designers[0].to_lower() if not a.designers.is_empty() else "zzzz"
				var bd: String = b.designers[0].to_lower() if not b.designers.is_empty() else "zzzz"
				if ad != bd:
					return ad < bd
				return _title_less(a, b))


# ---------------------------------------------------------------- wall

# ---------------------------------------------------------------- the drum

## Grid math: a game's place on the shelf - its column and
## its band. The shelf fills TOP TO BOTTOM in a column,
## then steps right (COLUMN-MAJOR, GRADFIX3 - the user's
## design call): consecutive games run down one column's
## three bands before the next column begins, so a title's
## horizontal position is monotonic with its alphabetical
## rank - far right is always late alphabet. The shipped
## row-major fill ran the alphabet along a band and wrapped
## it back to the left edge one band down, so a title's
## column said nothing about its letter ("I may get there
## and find the table is actually a few spots from the left
## side" - his words). The row-major mapping survives only
## behind the NC seam (debug_grid_nc, from harness env
## PVLDS_GRID_NC=rowmajor), so the census's column-order
## leg can fail against it by name.
const BAND_COUNT: int = 3 ## the shelf's bands per column (== ROW_ELEVATIONS.size())

## The Tournament wall's block (GRADFIX4 item 3): with the
## bookend fins nuked (GRADFIX3), the challenge grid leaned
## on them and collapsed into a single skinny column with
## dead space around it. The challenges now compose a proper
## shelf section of their own on the drum grid: a TWO-BAND
## block (the middle and bottom bands - the pair straddling
## the eye line) starting TOURN_BLOCK_COL0 columns in, so the
## block stands composed mid-window with intentional ends
## instead of hugging the shelf's start. The seat map stays
## a bijection (the pad-walk and focus legs depend on it);
## the NC seam (rowmajor) restores the library map over the
## block too, and the layout legs fail by name.
const TOURN_BLOCK_COL0: int = 4
const TOURN_BAND0: int = 1
const TOURN_BAND_COUNT: int = 2


## GRADFIX7 item 2: the Tournament pair layout. Challenge i
## (league order) belongs to pair-group g = i/2 and band
## b = 1 + (i%2) (elevations +5/-15 deg). Group g owns grid
## columns 4+2g (left slot) and 5+2g (right slot) of band b.
## The board stands in the group's OUTER slot and the card in
## the INNER slot: with G = ceil(n/2) groups and the
## (fractional) centre gc = (G-1)/2, groups left of centre
## put their board LEFT (g < gc), groups right of centre put
## it RIGHT (g > gc), and the centre group itself (g == gc)
## puts it RIGHT - the deterministic centre default. Side
## rule in Chris's words: the left-column table's board is on
## the LEFT of its card, the right-column table's on the
## RIGHT - outward, always. The single state row seats
## unpaired at (4, band 1), as it always has.
func _tourn_innerside_nc() -> bool:
	return OS.get_environment("PVLDS_GRADFIX7_NC") == "innerside"


func _tourn_state_idx(idx: int) -> bool:
	return _tournament and idx >= 0 and idx < _tournament_rows.size() \
		and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state"


func _tourn_pair_coords(idx: int) -> Dictionary:
	var g: int = idx / 2
	var band: int = TOURN_BAND0 + idx % TOURN_BAND_COUNT
	var groups: int = maxi(1, int(ceil(float(maxi(1, _visible_games.size())) / 2.0)))
	var gc: float = float(groups - 1) / 2.0
	var board_left: bool = float(g) < gc
	var left_col: int = TOURN_BLOCK_COL0 + 2 * g
	var right_col: int = left_col + 1
	var card_coord: Vector2i = Vector2i(right_col, band) if board_left else Vector2i(left_col, band)
	var board_coord: Vector2i = Vector2i(left_col, band) if board_left else Vector2i(right_col, band)
	if _tourn_innerside_nc():
		var swap: Vector2i = card_coord
		card_coord = board_coord
		board_coord = swap
	return {"card": card_coord, "board": board_coord, "side": "left" if board_coord.x < card_coord.x else "right"}


func _board_coord(idx: int) -> Vector2i:
	if not _tournament or _tourn_state_idx(idx):
		return Vector2i(-1, -1)
	return (_tourn_pair_coords(idx)["board"] as Vector2i)


func _grid_coord(index: int) -> Vector2i:
	if debug_grid_nc == "rowmajor":
		return Vector2i(index % _columns, index / _columns)
	if _tournament:
		if _tourn_state_idx(index):
			return Vector2i(TOURN_BLOCK_COL0, TOURN_BAND0)
		return (_tourn_pair_coords(index)["card"] as Vector2i)
	return Vector2i(index / BAND_COUNT, index % BAND_COUNT)


## The unclamped shelf index at a grid place, under the
## standing mapping - the raw material _index_at clamps.
func _raw_index(col: int, row: int) -> int:
	if debug_grid_nc == "rowmajor":
		return row * _columns + col
	if _tournament:
		# Defined over CARD coords only (GRADFIX7 item 2):
		# a board's column has no card in it and maps to -1.
		var want: Vector2i = Vector2i(col, row)
		for i: int in range(_visible_games.size()):
			if _grid_coord(i) == want:
				return i
		return -1
	return col * BAND_COUNT + row


func _index_at(col: int, row: int) -> int:
	return clampi(_raw_index(col, row), 0, maxi(0, _visible_games.size() - 1))


## A card's transform on the sphere (the prototype's
## _card_transform_at, verbatim): the point at (column angle,
## band elevation) on WALL_RADIUS around EYE, facing the eye.
func _card_transform_at(col: int, row: int) -> Transform3D:
	var az: float = deg_to_rad(float(col) * ANGLE_STEP_DEG)
	var el: float = deg_to_rad(ROW_ELEVATIONS[clampi(row, 0, ROW_ELEVATIONS.size() - 1)])
	var dir: Vector3 = Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	var pos: Vector3 = EYE + Vector3(0.0, WALL_LIFT, 0.0) + dir * WALL_RADIUS
	var z_axis: Vector3 = (EYE - pos).normalized()
	var x_axis: Vector3 = Vector3.UP.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis)
	return Transform3D(Basis(x_axis, y_axis, z_axis), pos)


## The drum's resting yaw for a column: the swing target that
## brings that column in front of the player.
func _yaw_for_column(col: int) -> float:
	return deg_to_rad(float(col) * ANGLE_STEP_DEG)


## Shared card materials (the prototype's palette): the dark
## frame every card wears, the amber it takes while it is the
## centred card, and the nameplate's dark plate.
func _frame_mat(amber: bool) -> StandardMaterial3D:
	if amber:
		if _mat_frame_amber == null:
			_mat_frame_amber = _unshaded_mat(Color(1.0, 0.66, 0.16), 1.0)
		return _mat_frame_amber
	if _mat_frame_dark == null:
		_mat_frame_dark = _unshaded_mat(Color(0.025, 0.03, 0.06), 1.0)
	return _mat_frame_dark


func _plate_mat() -> StandardMaterial3D:
	if _mat_plate == null:
		_mat_plate = _unshaded_mat(Color(0.0, 0.0, 0.0), 0.66)
		# The nameplate's rung in the card stack (see
		# _make_card_nodes): above the face (-3), below the
		# label (0). The NC seam leaves it undeclared.
		if OS.get_environment("PVLDS_GRAD_NC") != "nofaceorder":
			_mat_plate.render_priority = -2
	return _mat_plate


func _unshaded_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, alpha)
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_card_quad(parent: Node, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var qm: QuadMesh = QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## A card's title label (the prototype's _make_label settings):
## white, centre-wrapped inside the nameplate's column, with
## the dark outline the busy art behind it demands.
func _make_card_label(parent: Node, text: String) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.position = Vector3(0.0, LABEL_STRIP_Y, 0.012)
	l.pixel_size = LABEL_PIXEL_SIZE
	l.font_size = LABEL_FONT_SIZE
	l.width = LABEL_WIDTH_PX
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.outline_size = 7
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	l.modulate = Color(0.96, 0.97, 1.0)
	parent.add_child(l)
	return l


## Mint one game's card nodes (once per library adoption; the
## pool re-seats them per view - see _panel_pool). The root is
## the panel ClickableQuad the whole room already speaks
## (payload = game_id); riding on its flip pivot in card mode:
## the frame quad behind, the nameplate plate + title label
## in front - and the card's BACK (a holder turned PI on the
## pivot: its own frame, its info face), which the flip shows
## instead of the front past the turn's midpoint (GRADFIX6
## item 1). GRADFIX13 (item 2) strips the Launch plinths the
## front and back used to carry: no Launch quad is minted
## (nodes["launch"] / nodes["back_launch"] are null; the
## plinth NC seam mints them again). Board mode mints the
## bare board panel at the board's own size (its face
## carries its own text; no plate, no label, no frame, no
## back - the state row has nothing to flip to).
func _make_card_nodes(game: GameEntry, mode: String) -> Dictionary:
	var size: Vector2 = RoomSpecs.board_panel_size() if mode == "board" else CARD_SIZE
	var q: ClickableQuad = ClickableQuad.new()
	# GRADFIX15 (item 1): a board-mode panel (the tournament
	# state face) starts on the CLEAR texture, like a standing
	# board - no face yet reads as no fill, never a dark slab.
	q.setup("panel", game.game_id, clear_tex() if mode == "board" else _placeholder_tex, size)
	# The quad's own highlight frame is sized off the face
	# (x1.055): on a dome card that ring would outgrow the
	# prototype's frame geometry the clearance proof measured,
	# so the card-mode frame below replaces it - the built-in
	# frame is shrunk to the face itself, where the card's own
	# frame quad (a hair larger, behind) covers its edge.
	if mode == "card":
		q.set_frame_size(CARD_FRAME_SIZE)
	var nodes: Dictionary = {"root": q, "mode": mode}
	var pivot: Node3D = q.flip_pivot()
	if mode == "card":
		nodes["frame"] = _make_card_quad(pivot, CARD_FRAME_SIZE, Vector3(0.0, 0.0, -0.007), _frame_mat(false))
		# The tournie border (GRADFIX8 item 4): a ring quad
		# on the SAME pivot, behind the frame - it rides the
		# drum, the pop and the flip exactly as the card
		# does, with no transform of its own to shear or
		# lag. Hidden until _apply_tourney_borders seats a
		# live challenge's colour on it; its material is
		# the shared per-type ShaderMaterial (assigned
		# there, never minted per card).
		var border: MeshInstance3D = MeshInstance3D.new()
		border.name = "TourneyBorder"
		var tbqm: QuadMesh = QuadMesh.new()
		tbqm.size = TOURNEY_BORDER_OUTER
		border.mesh = tbqm
		border.position = Vector3(0.0, 0.0, -0.010)
		border.visible = false
		pivot.add_child(border)
		nodes["border"] = border
		nodes["border_on"] = false
		nodes["border_type"] = ""
		nodes["border_color"] = Color(0.0, 0.0, 0.0, 0.0)
		nodes["label"] = _make_card_label(pivot, game.title)
		# The plate starts at the strip's floor size; _seat_card
		# grows it to the title block's measured height once the
		# label is in the tree and its AABB is real.
		nodes["plate"] = _make_card_quad(pivot, LABEL_STRIP_SIZE, Vector3(0.0, LABEL_STRIP_Y, 0.005), _plate_mat())
		# The back assembly: a holder turned PI inside the
		# pivot, so the pivot's own half-turn brings it square
		# to the player. Its local frame is the front's mirror:
		# frame behind (-0.007), face at +0.001 (a breath proud
		# of the front face's plane, so the two never z-fight
		# at the turn's edge-on instant). Hidden until the
		# flip's midpoint swap (see _apply_flip_side).
		# GRADFIX13 (item 2): the back carries NO Launch
		# button - the plinth is stripped everywhere (Chris:
		# "they all launch, we know they launch, you press A
		# to launch, its not necessary"). The NC seam
		# PVLDS_GF13_NC=plinth mints the button again, on its
		# old seat, so the strip's census legs fail by name.
		var back: Node3D = Node3D.new()
		back.name = "CardBack"
		back.rotation.y = PI
		back.visible = false
		pivot.add_child(back)
		nodes["back_frame"] = _make_card_quad(back, CARD_FRAME_SIZE, Vector3(0.0, 0.0, -0.007), _frame_mat(false))
		var bface: MeshInstance3D = MeshInstance3D.new()
		bface.name = "CardBackFace"
		var bqm: QuadMesh = QuadMesh.new()
		bqm.size = CARD_SIZE
		bface.mesh = bqm
		var bmat: StandardMaterial3D = StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# GRADFIX15 (item 1): the back face is a frameless board
		# face (its texture is text on transparency), so its
		# material blends alpha like the standing boards' -
		# without this the transparent field would render as
		# an opaque black slab - and it stands on the clear
		# texture until its first real capture lands.
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_texture = clear_tex()
		bface.material_override = bmat
		bface.position = Vector3(0.0, 0.0, 0.001)
		back.add_child(bface)
		nodes["back"] = back
		nodes["back_mat"] = bmat
		if _plinth_nc():
			var blq: ClickableQuad = ClickableQuad.new()
			blq.setup("panel_launch", game.game_id, _placeholder_tex, PANEL_LAUNCH_SIZE)
			blq.position = Vector3(0.0, RoomSpecs.board_launch_y(), 0.020)
			blq.pick_enabled = false
			back.add_child(blq)
			nodes["back_launch"] = blq
		else:
			nodes["back_launch"] = null
		nodes["back_key"] = "" ## the content key this card's back texture was rendered for ("" = never)
		nodes["back_tex_real"] = false ## the back's standing texture is a real capture, not the fallback solid
	# GRADFIX13 (item 2): the front Launch plinth is stripped
	# with the back's - no quad is minted, and every consumer
	# of nodes["launch"] / _panel_launches treats the null as
	# the standing law (the arrays stay parallel, null-filled,
	# exactly as back_launch entries always could be). Only
	# the plinth NC mints the button, on its old seats.
	var lq: ClickableQuad = null
	if _plinth_nc():
		lq = ClickableQuad.new()
		lq.setup("panel_launch", game.game_id, _placeholder_tex, PANEL_LAUNCH_SIZE)
		lq.position = Vector3(0.0, RoomSpecs.board_launch_y() if mode == "board" else PANEL_LAUNCH_Y, 0.020)
		pivot.add_child(lq)
	nodes["launch"] = lq
	# The card's layer stack, declared (the GRAD FIX round):
	# at equal render priority the transparent sort could seat
	# the depth-writing face AFTER its own nameplate and label
	# and paint over both - the "names come and go" fault. The
	# order is now contractual: the quad's highlight frame
	# first, the face next, then the plate (its material's
	# priority, in _plate_mat), the power overlay above the
	# face (-1, in _build_power_overlay), the label at the
	# default 0, and (plinth NC only) the Launch pair on top.
	# The NC seam PVLDS_GRAD_NC=nofaceorder restores the
	# undeclared stack.
	if OS.get_environment("PVLDS_GRAD_NC") != "nofaceorder":
		q.set_stack_order(-4, -3)
		if lq != null:
			lq.set_stack_order(0, 1)
	return nodes


## GRADFIX13 (item 2): the Launch-plinth negative control -
## true only when the harness asks for the stripped plinths
## back (PVLDS_GF13_NC=plinth), so the strip's census legs
## can fail against the restored furniture by name.
func _plinth_nc() -> bool:
	return OS.get_environment("PVLDS_GF13_NC") == "plinth"


## Get a game's card nodes from the pool, minting them if this
## view's mode has none (a library card and a Tournament board
## are different panels for the same game_id across views -
## the mode tag keeps them honest; a mismatch is freed and
## re-minted at the right size).
func _pool_card(game: GameEntry) -> Dictionary:
	# Since the Tournament redesign, challenge panels are
	# CARDS (the board stands beside the centred one as
	# furniture); only the state row still wears a board face.
	var mode: String = "board" if (_tournament and game.game_id == "wovp:state") else "card"
	var nodes: Dictionary = _panel_pool.get(game.game_id, {}) as Dictionary
	if not nodes.is_empty() and str(nodes.get("mode", "")) != mode:
		var old_root: ClickableQuad = nodes.get("root") as ClickableQuad
		if old_root != null and is_instance_valid(old_root):
			if old_root.get_parent() != null:
				old_root.get_parent().remove_child(old_root)
			old_root.queue_free()
		nodes = {}
		_panel_face_key.erase(game.game_id)
	if nodes.is_empty():
		nodes = _make_card_nodes(game, mode)
		_panel_pool[game.game_id] = nodes
	return nodes


## Seat a pooled card on the drum at its shelf place and set
## its per-view state: transform, base position and pop
## direction for the pop's bookkeeping, the nameplate's grown
## plate (first seat only), and the Launch button's seat
## (below the plate - or at the card's top when a long title's
## plate grows down over the low seat).
func _seat_card(idx: int, nodes: Dictionary) -> void:
	var q: ClickableQuad = nodes["root"] as ClickableQuad
	if str(nodes.get("mode", "")) == "board":
		# A board-mode panel is the Tournament state row: it
		# carries no Launch, ever - hide its Launch quad from
		# the first frame, not whenever the async state fill
		# lands (the fill re-asserts the same law; GRADFIX6's
		# fill reorder - window faces before state faces, so
		# entry never waits - exposed the seat-time gap).
		var slq: ClickableQuad = nodes.get("launch") as ClickableQuad
		if slq != null:
			slq.visible = false
			slq.pick_enabled = false
	var coord: Vector2i = _grid_coord(idx)
	var t: Transform3D = _card_transform_at(coord.x, coord.y)
	if q.get_parent() != _wall:
		_wall.add_child(q)
	q.transform = t
	_panel_base_pos[idx] = t.origin
	_panel_pop_dir[idx] = t.basis.z.normalized()
	if str(nodes.get("mode", "")) == "card" and not bool(nodes.get("plate_done", false)):
		nodes["plate_done"] = true
		# The seat-time derivation: the label has not shaped
		# its text yet at this point in the seat (its AABB
		# still reads empty - measured over the whole fixture
		# library, GRADFIX2), so what this applies is the
		# strip's floor plate with the Launch at the low seat.
		# The standing derivation below re-derives both from
		# the label's REAL AABB once the text stands shaped;
		# this pass only guarantees a plate exists from the
		# first frame.
		var label0: Label3D = nodes["label"] as Label3D
		nodes["plate_basis_h"] = -1.0
		_apply_card_plate(nodes, label0.get_aabb())


## Derive a card's nameplate and Launch seat from a title
## block: the plate grows to the block's measured height
## (the strip's floor size for a one-line name), and the
## Launch button moves to the card's top when the grown
## plate's bottom would reach its low seat - the plate
## never shares ground with the button, by construction.
## Whether a card's STANDING face is an art face, for the
## plate law below (GRADFIX7 item 1): the stamped face key's
## art segment is non-empty AND the fill recorded a real art
## aspect for the panel's current seat. A styled title card
## (empty art segment, aspect 0) is NOT an art face even
## though its plate and label stand hidden - the plate law
## must not read geometry off a face that is not standing.
func _nodes_face_is_art(nodes: Dictionary) -> bool:
	var root: ClickableQuad = nodes.get("root") as ClickableQuad
	if root == null:
		return false
	var gid: String = root.payload
	if gid == "":
		return false
	var fkey: String = str(_panel_face_key.get(gid, ""))
	var parts: PackedStringArray = fkey.split("|")
	if parts.size() <= 1 or parts[1] == "":
		return false
	for idx: int in range(_visible_games.size()):
		if _visible_games[idx].game_id == gid:
			return idx < _panel_art_aspect.size() and _panel_art_aspect[idx] > 0.0
	return false


func _apply_card_plate(nodes: Dictionary, aabb: AABB) -> void:
	var plate: MeshInstance3D = nodes["plate"] as MeshInstance3D
	var block_h: float = maxf(LABEL_STRIP_SIZE.y, aabb.size.y + 0.034)
	var block_cy: float = LABEL_STRIP_Y + aabb.position.y + aabb.size.y * 0.5
	var pq: QuadMesh = plate.mesh as QuadMesh
	if pq != null:
		pq.size = Vector2(LABEL_STRIP_SIZE.x, block_h)
	plate.position = Vector3(0.0, block_cy, 0.005)
	# GRADFIX13 (item 2): the plate derivation used to also
	# seat the card's Launch button - low, or at the card's
	# top (PANEL_LAUNCH_Y_TOP) when a long title's grown
	# plate would reach the low seat (the GRADFIX2/GRADFIX7
	# seat law). The plinth is stripped, so the seat law
	# dies with it: the plate derives from the live label
	# AABB alone, and a long multi-line name's block now
	# answers to nothing below it - the card's face bottom
	# is the only bound (the census's name legs re-prove
	# the block standing whole on its plate). Under the
	# plinth NC the button is minted again and the old seat
	# law re-applies, so the NC's census can convict it.
	var lq: ClickableQuad = nodes.get("launch") as ClickableQuad
	if lq != null:
		var plate_bottom: float = block_cy - block_h * 0.5
		var top_seat: bool = plate_bottom < -0.40 and _nodes_face_is_art(nodes)
		lq.position = Vector3(0.0, PANEL_LAUNCH_Y_TOP if top_seat else PANEL_LAUNCH_Y, 0.020)


## The GRADFIX2 item 1 fix: the nameplate derivation runs
## again from the label's LIVE AABB. At seat time the
## label's geometry does not exist yet (the AABB reads
## empty for every card - the probe over the fixture
## library: 103 of 103), so the shipped derivation sized
## every plate at the one-line floor and never moved a
## Launch: multi-line names overflowed the plate and their
## last line fell under the low Launch plinth - No Fear's
## third line, Capt. Fantastic's, Indiana Jones's, and The
## Addams Family's first line standing off its plate
## (item 5: the label was whole; the plate was one line
## tall). The refresh re-derives plate and Launch seat
## from the shaped block, per card, until the AABB it
## applied matches the label's standing AABB. The NC seam
## PVLDS_GRADFIX_NC=staleplate restores the shipped
## seat-time-only behaviour so the census's plinth legs
## fail against it by name.
func _refresh_card_plate(nodes: Dictionary) -> bool:
	if OS.get_environment("PVLDS_GRADFIX_NC") == "staleplate":
		return true
	if str(nodes.get("mode", "")) != "card":
		return true
	var label: Label3D = nodes["label"] as Label3D
	if label == null:
		return true
	var aabb: AABB = label.get_aabb()
	if aabb.size.y <= 0.0:
		return false ## not shaped yet - a later sweep retries
	if absf(aabb.size.y - float(nodes.get("plate_basis_h", -1.0))) < 0.001:
		return true ## the standing derivation already wears this block
	nodes["plate_basis_h"] = aabb.size.y
	_apply_card_plate(nodes, aabb)
	return true


## One sweep of the standing wall's plate refresh; true
## when every standing card's plate wears its label's
## standing AABB. Driven from _process while a rebuild's
## plates are pending (a label shapes within a frame or
## two of standing; the sweep retires itself).
func _refresh_all_card_plates() -> bool:
	var settled: bool = true
	for idx: int in range(_panels.size()):
		if idx >= _visible_games.size():
			break
		var nodes: Dictionary = _panel_pool.get(_visible_games[idx].game_id, {}) as Dictionary
		if not nodes.is_empty() and not _refresh_card_plate(nodes):
			settled = false
	return settled


## (The shelf's bookend fins - DOME3's dark slabs with amber
## bars, one column past each shelf end - were removed
## entirely by GRADFIX8 item 5, Chris's order: "doesn't fit
## aesthetic", after days of trying to be rid of them. No
## replacement geometry. The Tournament view already stood
## without them since GRADFIX3; the library's pair followed
## here - builder, window gating and rebuild seating are
## all gone, and bookend_fin_count() below is the census
## that proves no fin node stands in either view.)


## Centre the drum on a shelf index: the swing target moves,
## the window and the centred frame follow, and the page
## bookkeeping (the rail's readout, the persisted view) is
## derived here so every travel - step, jump, pick, restore -
## keeps one truth. Input is never gated by the swing: a step
## mid-swing retargets from the drum's current angle.
func _set_centre(index: int, snap: bool = false) -> void:
	if _visible_games.is_empty():
		return
	var clamped: int = clampi(index, 0, _visible_games.size() - 1)
	var col: int = _grid_coord(clamped).x
	var target: float = _yaw_for_column(col)
	var changed: bool = clamped != _centre_index
	var from_col: int = _grid_coord(_centre_index).x if _centre_index >= 0 and _centre_index < _panels.size() else col
	_centre_index = clamped
	_page = _centre_index / PAGE_SIZE
	if snap or _wall == null:
		_drum_yaw = target
		_swing_to = target
		_swing_vel = 0.0
		_swing_active = false
		_swing_journey = false
		_nc_roll_dir = 0 ## a teleport kills the NC seam's roll outright (production never rolls)
		_step_from_col = -1 ## a teleport is not a step: no settle record
		_step_to_col = -1
		if _wall != null:
			_wall.rotation.y = target
	elif target != _swing_to or not _swing_active:
		if absf(target - _drum_yaw) < 0.0001 and absf(_swing_vel) < 0.001:
			_drum_yaw = target
			_swing_to = target
			_swing_vel = 0.0
			_swing_active = false
			_swing_journey = false
			if _wall != null:
				_wall.rotation.y = target
		else:
			# A retarget only names the new target and
			# recalibrates the spring from the distance left:
			# the velocity is NOT reset - the drum bends its
			# path instead of restarting a curve (the GRAD
			# FIX round's glide; see _update_swing). A
			# retarget that arrives while the drum is already
			# travelling the same way marks a journey: the
			# spring softens to the stepping cadence, so a
			# held scroll chains discrete steps instead of
			# settling between them - a train of steps with
			# settle plateaus, never a cruise (OPTIMIZE: the
			# held-stick cruise is deleted with the SMOOTH
			# driver; the poll's repeat cadence retargets
			# through this same path).
			if _swing_active and absf(_swing_vel) > 0.05 \
					and signf(target - _drum_yaw) == signf(_swing_vel):
				_swing_journey = true
			_swing_to = target
			var cols: float = absf(target - _drum_yaw) / deg_to_rad(ANGLE_STEP_DEG)
			_swing_cols = cols
			_swing_duration = clampf(0.14 + 0.055 * sqrt(maxf(cols, 1.0)), SWING_MIN_SEC, SWING_MAX_SEC)
			_swing_active = true
			_step_begin(from_col, col) ## OPTIMIZE telemetry: the step record opens (it lands in _update_swing)
	if changed:
		# GRADFIX17 telemetry: a centre change's parts, timed
		# - this block is the per-column work travel pays,
		# and a slow part names itself in the log.
		var tel_c_t0: int = Time.get_ticks_usec()
		_refresh_window()
		var tel_c_t1: int = Time.get_ticks_usec()
		_refresh_card_frames()
		var tel_c_t2: int = Time.get_ticks_usec()
		_request_window_fill()
		var tel_c_ms: float = float(Time.get_ticks_usec() - tel_c_t0) / 1000.0
		if tel_c_ms >= 4.0:
			_art_event("seg", {
				"seg": "set_centre", "cost_ms": tel_c_ms,
				"window_ms": float(tel_c_t1 - tel_c_t0) / 1000.0,
				"frames_ms": float(tel_c_t2 - tel_c_t1) / 1000.0,
				"fill_ms": float(Time.get_ticks_usec() - tel_c_t2) / 1000.0,
				"col": col, "nc_roll_dir": _nc_roll_dir, "snap": snap,
			})
		# No companion follows the centre any more (the flip
		# replaced the wing/board): a centre change is one of
		# the flip's closing conditions, and _update_flip
		# reads it per frame - no hook needed here.


## Per-frame swing drive, from _process. ONE driver stands
## (OPTIMIZE round): STEPPED - the critically damped spring
## (the classic smooth-damp form) carries the drum to its
## target, velocity included. The prototype's per-step cubic
## ease-out restarted its curve at every retarget, so a
## stepped journey - or a laser hover sweeping the shelf -
## moved as dart-and-settle, dart-and-settle: the ratchet the
## player reported (the GRAD FIX round). The spring never
## restarts: a retarget bends the path, the velocity carries
## through, and travel reads as one continuous glide. Its
## stiffness is calibrated from the standing duration law
## (tau = duration / 3.5), so arrival times stay inside the
## envelope the law always promised - motion never gates
## input and no journey takes longer than it used to - and
## the landing is exact: inside a hair of the target the drum
## snaps onto it, at rest, like it always did. The SMOOTH
## driver and the held-stick cruise that rode it are deleted
## (the OPTIMIZE round, the user's ruling closing the
## smooth-cruise saga): a held stick repeats discrete steps
## at the poll's step-repeat cadence, each retargeting
## through _set_centre's journey logic above, so a hold is a
## train of discrete steps with settle plateaus.
func _update_swing(delta: float) -> void:
	if _nc_roll_dir != 0:
		_nc_roll_drive() ## debug_opt_nc="smoothcruise" seam only (never armed in production)
	if not _swing_active or _wall == null:
		return
	var tau: float = maxf(_swing_duration / (3.5 + 0.55 * log(maxf(_swing_cols, 1.0))), 0.02)
	if _swing_journey:
		tau = maxf(tau, 0.11)
	var omega: float = 2.0 / tau
	var x: float = omega * delta
	var ex: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change: float = _drum_yaw - _swing_to
	var temp: float = (_swing_vel + omega * change) * delta
	_swing_vel = (_swing_vel - omega * temp) * ex
	_drum_yaw = _swing_to + (change + temp) * ex
	if absf(_drum_yaw - _swing_to) < 0.00035 and absf(_swing_vel) < 0.05:
		_drum_yaw = _swing_to
		_swing_vel = 0.0
		_swing_active = false
		_swing_journey = false
		_step_rest_timer = STEP_REST_SEC ## OPTIMIZE finish: a queued hold-repeat waits out this rest (the inter-step plateau)
		_step_landed() ## OPTIMIZE telemetry: the step record closes with its settle duration
	_wall.rotation.y = _drum_yaw


## debug_opt_nc="smoothcruise" seam ONLY (PVLDS_OPT_NC, set by
## Main before the room exists; empty in every real run): the
## deleted SMOOTH gait's shape in miniature - while the seam's
## roll stands, the swing's target keeps extending column by
## column ahead of the drum, so the spring never lands and no
## settle plateau forms. Armed by the _process poll when a
## held stick's second same-direction step would fire; ends
## on release or at the shelf's end, where the ordinary
## stepped landing settles the drum. Production code never
## sets _nc_roll_dir.
func _nc_roll_drive() -> void:
	if _columns <= 0:
		_nc_roll_dir = 0
		return
	var step_rad: float = deg_to_rad(ANGLE_STEP_DEG)
	var target_col: int = clampi(int(roundf(_swing_to / step_rad)), 0, _columns - 1)
	if absf(_drum_yaw - _swing_to) < step_rad * 0.6:
		var next_col: int = clampi(target_col + _nc_roll_dir, 0, _columns - 1)
		if next_col == target_col:
			_nc_roll_dir = 0 ## the shelf's end: the standing target settles through the spring
			return
		_swing_to = _yaw_for_column(next_col)
		_swing_cols = absf(_swing_to - _drum_yaw) / step_rad
		_swing_duration = clampf(0.14 + 0.055 * sqrt(maxf(_swing_cols, 1.0)), SWING_MIN_SEC, SWING_MAX_SEC)
		_swing_active = true
		# The centre follows the extending target, one column
		# at a time - bookkeeping only, no retarget.
		var idx: int = _panel_in_column(next_col, _grid_coord(_centre_index).y if _centre_index >= 0 else 0)
		if idx >= 0:
			_centre_index = idx
			_page = _centre_index / PAGE_SIZE
			_refresh_window()
			_refresh_card_frames()
			_request_window_fill()


## debug_opt_nc="costume" seam ONLY (empty in every real
## run): the deleted GF19 costume's symptom in miniature -
## while a swing travels, the drawn window's panel faces are
## swapped to blank (the clear texture) and restored at
## settle, so the dressed-during-step leg fails by name.
## Hooks: called per frame from _update_pop where the GF19
## tick stood.
func _nc_costume_tick() -> void:
	if debug_opt_nc != "costume":
		return
	var travelling: bool = _swing_active or page_slide_active()
	if travelling:
		if _panel_window_lo >= 0:
			for idx: int in range(_panels.size()):
				if _nc_costume_saved.has(idx):
					continue
				var cc: int = _grid_coord(idx).x
				if cc < _panel_window_lo or cc > _panel_window_hi:
					continue
				_nc_costume_saved[idx] = _panels[idx].current_texture()
				_panels[idx].set_texture(clear_tex())
		_nc_costume_on = true
	elif _nc_costume_on:
		for idx_v: Variant in _nc_costume_saved.keys():
			var idx: int = int(idx_v)
			if idx >= 0 and idx < _panels.size():
				var tex: Texture2D = _nc_costume_saved[idx_v] as Texture2D
				if tex != null:
					_panels[idx].set_texture(tex)
		_nc_costume_saved.clear()
		_nc_costume_on = false


## The centred card's frame goes amber; every other card's
## stays dark. The ClickableQuad highlight frame still answers
## hover/focus on top of this - the amber frame is the shelf's
## own statement of where its centre stands.
func _refresh_card_frames() -> void:
	for idx: int in range(_panels.size()):
		if idx >= _panel_frames.size():
			break
		var f: MeshInstance3D = _panel_frames[idx]
		if f != null:
			# GRADFIX17: only the old and new centre frames
			# ever change material (two shared materials,
			# centre or dark) - assigning the standing one
			# again is a renderer write for nothing, per
			# panel per column. Compare and skip.
			var want_mat: StandardMaterial3D = _frame_mat(idx == _centre_index)
			if f.material_override != want_mat:
				f.material_override = want_mat


## The drawn window: cards within VISIBLE_HALF_COLUMNS of the
## centred column are visible (and, in plain browsing, pickable);
## the rest are dark and inert.
func _refresh_window() -> void:
	var n: int = _visible_games.size()
	if n == 0 or _panels.is_empty():
		_panel_window_lo = -1
		_panel_window_hi = -1
		return
	var fc: int = _grid_coord(_centre_index).x
	_panel_window_lo = maxi(0, fc - VISIBLE_HALF_COLUMNS)
	_panel_window_hi = mini(_columns - 1, fc + VISIBLE_HALF_COLUMNS)
	var browsing: bool = _mode == "wall" and not _placard_up and not _setup_panel_up and not _submit_panel_up and _launching_game_id == ""
	for idx: int in range(_panels.size()):
		var c: int = _grid_coord(idx).x
		var vis: bool = c >= _panel_window_lo and c <= _panel_window_hi
		_panels[idx].visible = vis
		if browsing:
			_panels[idx].pick_enabled = vis
			if idx < _panel_launches.size() and _panel_launches[idx] != null:
				_panel_launches[idx].pick_enabled = vis and not (_tournament and not _tournament_launchable(idx))
	for bi: int in range(_board_nodes.size()):
		var bnode2: MeshInstance3D = _board_nodes[bi] as MeshInstance3D
		if bnode2 == null:
			continue
		var bc2: Vector2i = _board_coord(bi)
		bnode2.visible = bc2.x >= _panel_window_lo and bc2.x <= _panel_window_hi
	# The haze follows the centre (see _haze_for): re-apply
	# the standing wall fade with the new centre's factors.
	# GRADFIX17: the pass itself now knows the haze moved
	# (it watches the centre column) and writes only the
	# alphas that actually change - the old shape defeated
	# its change guard here (resetting it to -1) so EVERY
	# centre change rewrote every alpha on the wall.
	_apply_wall_alpha(_wall_alpha_applied)
## Whether a Tournament panel may launch: only a challenge row
## he owns (a state row and a not-owned board carry no launch
## at all - the fill also hides their buttons; this is the
## pick-side of the same law).
func _tournament_launchable(idx: int) -> bool:
	if idx < 0 or idx >= _tournament_rows.size():
		return false
	var row: Dictionary = _tournament_rows[idx] as Dictionary
	return str(row.get("kind", "")) == "challenge" and bool(row.get("owned", false))


## Whether REFRESH stands as a live rail stop right now
## (GRADFIX16 item 1). THE CONVICTION (Chris's field report,
## 2026-11-02, on the GRADFIX14 build): REFRESH stood drawn
## on the library rail but could not be selected - every
## gate in the room keyed on _tournament: _build_rail built
## the quad pick-dead, _rebuild_wall re-armed it only while
## the Tournament Room stood, _refresh_focusables admits
## only pick_enabled quads (so the focus walk, the bumper
## neighbour walk, the descent edge and the rail's trigger
## anchor list all skipped it), the pointer rig picks only
## pick_enabled quads (and _on_select refuses the rest), the
## strip lift lifts only the FOCUSED section, and
## _handle_rail's own wovp_refresh branch was tournament-
## gated besides. THE FIX: REFRESH is a rail stop in EVERY
## view, like every other stop - pressing it emits
## tournament_refresh_requested (Main re-pulls the WoVP
## boards; the fetch is view-agnostic and the room caches
## the boards for the Tournament Room), focus lands on it,
## and it lifts like any other stop. The NC value
## "refreshgate" (PVLDS_GF16_NC) restores the shipped
## tournament-only gating at this one seam, so every gate
## downstream re-closes at once.
func _refresh_pickable() -> bool:
	return debug_gf16_nc != "refreshgate" or _tournament


func _rebuild_wall() -> void:
	# The NC costume seam's blank swap belongs to the wall
	# being torn down too - drop it without restoring (the
	# rebuild re-dresses every face itself).
	_nc_costume_saved.clear()
	_nc_costume_on = false
	# The power-on's performer and its overlay die with
	# the wall being torn down: drop the state without
	# touching the (about to be freed) nodes.
	_power_reset_state()
	# The flip's standing turn belongs to the wall being
	# torn down: snap it shut before the new wall seats (the
	# pooled cards keep their nodes - a pivot left turned
	# would seat its card backwards).
	_snap_flip_shut()
	for q2: ClickableQuad in _panels:
		if q2 != null and is_instance_valid(q2):
			q2.set_flip_angle(0.0)
			q2.set_face_shown(true)
	# The SETUP panel's focus, remembered across the rebuild:
	# if a rebuild ever runs while the panel stands, the
	# player's place on the panel must survive it (the tail
	# below hands it back). Scan landings no longer rebuild
	# here at all - they defer to the panel's close (see
	# adopt_library) - but the confinement law is general.
	var panel_focus: ClickableQuad = _focused if _setup_panel_up else null
	_plates_pending = true ## the new wall's nameplates re-derive once their labels shape (see _refresh_card_plate)
	_face_path_memo.clear() # a rebuilt wall re-derives its paths (the pipeline filter's memo, see _face_path_memo)
	_gen += 1
	var gen: int = _gen
	wall_ready = false
	_swing_active = false
	_swing_vel = 0.0
	_swing_journey = false
	_nc_roll_dir = 0 ## a rebuild kills the NC seam's roll with the wall it travelled
	_step_from_col = -1
	_step_to_col = -1
	_pop_awake = true ## OPTIMIZE standing-cost cut: a rebuilt wall's pops start awake
	_pop_last_target = null
	# Standing cards return to the pool (they are NOT freed:
	# a rebuild re-seats the same nodes at the new view's
	# places, faces and all - freeing and re-minting 300+
	# cards per letter pick is the pick-latency tax the pool
	# exists to refuse). The banner is Room furniture now
	# (built once, below) and never rides the drum.
	for q: ClickableQuad in _panels:
		if q != null and is_instance_valid(q) and q.get_parent() == _wall:
			_wall.remove_child(q)
	for bn: Variant in _board_nodes:
		var bnode: MeshInstance3D = bn as MeshInstance3D
		if bnode != null and is_instance_valid(bnode) and bnode.get_parent() == _wall:
			_wall.remove_child(bnode)
	_board_nodes.clear()
	_board_base_pos.clear()
	_board_pop_dir.clear()
	_panels.clear()
	_panel_launches.clear()
	_panel_back_launches.clear()
	_panel_base_pos.clear()
	_panel_pop_dir.clear()
	_panel_pop.clear()
	_panel_pop_vel.clear()
	_panel_pop_applied.clear()
	_panel_art_aspect.clear()
	_panel_frames.clear()
	_panel_plates.clear()
	_panel_labels.clear()
	_panel_window_lo = -1
	_panel_window_hi = -1
	_wall_alpha_applied = 1.0 ## fresh quads start opaque; the marquee fade re-applies from there
	_panel_alpha_applied.clear() ## GRADFIX17: the alpha pass's write-on-change caches reset with the wall (fresh materials stand at their own defaults)
	_launch_alpha_applied.clear()
	_label_alpha_applied.clear()
	_board_alpha_applied.clear()
	_alpha_flat_applied.clear()
	_alpha_haze_centre = -999
	_set_focused(null)

	_placeholder_tex = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	_panel_size = CARD_SIZE
	_panel_face_px = CARD_FACE_PX
	if _tournament:
		# The block's own extent: pad columns + the two-band
		# block (GRADFIX4 item 3 - see TOURN_BLOCK_COL0).
		_columns = TOURN_BLOCK_COL0 + 2 * maxi(1, int(ceil(float(maxi(1, _visible_games.size())) / float(TOURN_BAND_COUNT))))
	else:
		_columns = maxi(1, int(ceil(float(maxi(1, _visible_games.size())) / 3.0)))
	if _status_label == null:
		_build_status_line()
	# Panels for the whole standing view, seated on the drum.
	for idx: int in range(_visible_games.size()):
		var game: GameEntry = _visible_games[idx]
		var nodes: Dictionary = _pool_card(game)
		_panels.append(nodes["root"] as ClickableQuad)
		_panel_launches.append(nodes["launch"] as ClickableQuad)
		_panel_back_launches.append(nodes.get("back_launch") as ClickableQuad)
		_panel_base_pos.append(Vector3.ZERO)
		_panel_pop_dir.append(Vector3.ZERO)
		_panel_pop.append(0.0)
		_panel_pop_vel.append(0.0)
		_panel_pop_applied.append(0.0)
		_panel_art_aspect.append(0.0)
		_panel_frames.append(nodes.get("frame") as MeshInstance3D)
		_panel_plates.append(nodes.get("plate") as MeshInstance3D)
		_panel_labels.append(nodes.get("label") as Label3D)
		_seat_card(idx, nodes)
	# The new wall's tournie borders (GRADFIX8 item 4):
	# pooled cards are re-seated above, so their rings
	# are re-derived from the standing WoVP data here -
	# a rebuild never inherits a stale or missing border.
	_apply_tourney_borders()
	# The Tournament Room's standing boards (GRADFIX7 item 2):
	# one beside every challenge card, in its pair's outer
	# slot. Seated here with placeholder faces; the textures
	# fill asynchronously at the rebuild's tail - never awaited
	# on this path (an await here re-creates the first-entry
	# freeze the phase-16 legs exist to convict).
	if _tournament:
		_seat_tournament_boards()
	# No bookend fins seat here any more (GRADFIX8 item 5):
	# the Tournament view dropped them at GRADFIX3 and the
	# library's pair is now gone too - the shelf ends bare.
	# The drum rests centred on the standing centre (a rebuild
	# is a new wall: it snaps, exactly as the flat wall rebuilt
	# flat; travel WITHIN a standing wall is the swing's job).
	_centre_index = clampi(_centre_index, 0, maxi(0, _visible_games.size() - 1))
	_page = _centre_index / PAGE_SIZE if not _visible_games.is_empty() else 0
	_drum_yaw = _yaw_for_column(_grid_coord(_centre_index).x) if not _visible_games.is_empty() else 0.0
	_swing_to = _drum_yaw
	_swing_vel = 0.0
	_wall.rotation.y = _drum_yaw
	# Rail: built ONCE and persistent across rebuilds (the feel
	# round, 2026-10-24). Destroying and recreating it on every
	# page flip made every button pop back into existence as its
	# texture streamed in - Chris: "the lower filter bar
	# refreshes itself every time, every button." The bar is
	# furniture: it stands while the wall moves. A rebuild just
	# resets the standing quads' pick/alpha state to the fresh-
	# build defaults the recreate used to provide (the placard
	# branch below re-inerts them when it has to) and re-dresses
	# them from the texture cache in this same frame.
	if _rail_quads.is_empty():
		_build_rail(_placeholder_tex)
	else:
		for k: Variant in _rail_quads.keys():
			var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
			if rq != null:
				rq.pick_enabled = str(k) != "page_label"
				rq.set_content_alpha(1.0)
	# REFRESH takes the same reset as every other stop
	# (GRADFIX16 item 1: it is a live stop in every view -
	# see _refresh_pickable); only the NC's restored gating
	# re-closes it over the library wall.
	var refresh_q: ClickableQuad = _rail_quads.get("wovp_refresh") as ClickableQuad
	if refresh_q != null:
		refresh_q.pick_enabled = _refresh_pickable()
	# The alphabet strip is furniture on the same terms: built
	# once beside the rail, and every rebuild re-lays it out
	# (the "#" slot's existence follows the library), re-reads
	# its pick states (greyed letters are not stops) and
	# re-dresses it from its texture cache in this same frame.
	if _strip_quads.is_empty():
		_build_strip(_placeholder_tex)
	_refresh_strip()
	_apply_rail_textures()
	_refresh_focusables()
	_refresh_window()
	_refresh_card_frames()
	_fill_wall_textures(gen)
	if _tournament:
		_request_tournament_board_fill()
	if _placard_up:
		# A rebuild while the placard stands (the launch-failure
		# path) must not resurrect live controls behind it.
		_inert_room_quads()
		_set_focused(_placard_back)
	if _setup_panel_up:
		# The same law behind the SETUP panel: the scan-landing
		# refresh must not resurrect live controls behind it,
		# and focus stays on the panel button it was on.
		_inert_room_quads()
		_set_focused(panel_focus if panel_focus != null else _setup_panel_scan_btn)


## The status line (the wall's banner, re-homed): the library
## summary / launch status the banner quad used to carry,
## moved low and forward - the dome's top band stands where
## the banner hung, and the prototype proved a low panel
## clears every label. A dark plate with a Label3D line: no
## factory render, so a status change is instant and the
## pick-latency caches never see it. Not a quad: it is not
## pickable, focusable, or part of any pick snapshot.
## The plate sits LOW and CLOSE (y 0.09, z -1.30, in front of
## and below the strip): the graduation census proved the
## rail/strip/status stack cannot share one depth without
## eating bottom-band labels, so the status line left the
## stack - down here its top edge rides at ~40 degrees of
## depression, below every label's sight line.
func _build_status_line() -> void:
	# The Console (GRADFIX5 item 3): the plate slims with the
	# bar - 2.3 x 0.11 -> 1.95 x 0.088, the type 30 -> 26 on a
	# 680 px measure - one line, tucked under the bar at the
	# same seat. The widebar NC restores the old plate.
	var wide: bool = _console_wide()
	_status_plate = _make_card_quad(self, Vector2(2.3, 0.11) if wide else Vector2(1.95, 0.088), Vector3(0.0, 0.09, -1.30), _plate_mat())
	_status_label = Label3D.new()
	_status_label.position = Vector3(0.0, 0.09, -1.288)
	_status_label.pixel_size = 0.0028 if wide else 0.0026
	_status_label.font_size = 30 if wide else 26
	_status_label.width = 780.0 if wide else 680.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.outline_size = 6
	_status_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_status_label.modulate = Color(0.92, 0.95, 1.0)
	add_child(_status_label)


func _build_rail(placeholder: Texture2D) -> void:
	# ~26 degrees below the eye line and far enough out that the full
	# rail width sits inside a 16:9 frustum (it was clipped at the
	# bottom edge of the flat view when it hugged the player).
	# The seat was re-tuned at graduation, three rounds deep.
	# The flat wall's rail (0.45 / -1.85) projected over the
	# dome's bottom band. The census then convicted the STACK:
	# rail + status plate + strip cannot fit between the
	# bottom labels' sight line and the floor at any single
	# depth - and an eye-centred ARC rail (constant depression,
	# zero label intrusions) spans +/-75 degrees of azimuth,
	# furniture beside the user's head. The shipped shape: the
	# status plate leaves the stack (a low console plate in
	# front of the strip, _build_status_line), and the two
	# remaining rows sit at the prototype panel's distance:
	# rail centre 0.225 (top 0.30 - at the widest in-zone stop
	# its top edge holds ~25.6 degrees of depression against
	# the labels' ~24.5), strip below it (STRIP_Y - 0.045
	# since Console pass 2, GRADFIX6), both at z -1.62.
	# Beyond the browsing zone the flat rail's far ends still
	# graze fringe labels in the desk projection; the census
	# counts and prints those, it does not convict them.
	var y: float = 0.225
	var z: float = -1.62
	# The Console (GRADFIX5 item 3): the same twelve stops at
	# x0.72 widths, gaps closed to RAIL_GAP, tiles RAIL_TILE_H
	# tall - total span 2.96 m against the old 4.225 (70%).
	# Console pass 2 (GRADFIX6 item 4): widths x0.90 again -
	# span 2.687 m, total angular width 79.3 degrees at the
	# rail's z -1.62 (see the constants block for the full
	# arithmetic). The widebar NC restores the pre-Console
	# row wholesale. GRADFIX8 (item 6) then drops the two
	# pager stops from both rows: the standing span is
	# 2.417 m over ten entries (see the GRADFIX8 note on the
	# defs below). GRADFIX11 (Chris's order) seats the NEW
	# filter tile after RECENTS in both rows: the standing
	# Console span is 2.591 m over eleven entries.
	var defs: Array = []
	# GRADFIX8 (item 6, Chris's order): the < > pager stops
	# are REMOVED from both bars' defs - unused, with the
	# thumbstick and bumpers covering travel. What stays is
	# the page-position READOUT (page_label): information,
	# not navigation - it keeps its seat in the row, now
	# directly right of TOURNAMENT, and _set_centre keeps
	# its text tracking the centred column's page exactly
	# as before. Page TRAVEL itself is untouched: the
	# bumpers (_bumper_page) and _handle_rail's page
	# branches remain the travel engine.
	if _console_wide():
		defs = [
			["filter:all", 0.30], ["filter:vr", 0.24], ["filter:favorites", 0.44], ["filter:recents", 0.40], ["filter:new", 0.24],
			["sort", 0.46], ["tournament", 0.44], ["page_label", 0.28],
			["wovp_refresh", 0.32], ["desk", 0.32], ["exit", 0.28],
		]
	else:
		defs = [
			["filter:all", 0.194], ["filter:vr", 0.156], ["filter:favorites", 0.285], ["filter:recents", 0.259], ["filter:new", 0.156],
			["sort", 0.298], ["tournament", 0.285], ["page_label", 0.182],
			["wovp_refresh", 0.207], ["desk", 0.207], ["exit", 0.182],
		]
	var gap: float = 0.035 if _console_wide() else RAIL_GAP
	var tile_h: float = 0.15 if _console_wide() else RAIL_TILE_H
	var total: float = 0.0
	for d: Variant in defs:
		total += float(d[1]) + gap
	total -= gap
	# GRADFIX14 (item 1): in strip mode the sections sit
	# CONTIGUOUS - the gaps close to zero and their span is
	# absorbed into the sections at the shipped proportions,
	# so the bar's total span, seat and height are the
	# shipped rail's exactly, with no gaps between boxes
	# because there are no boxes. The widebar NC and the
	# tileboxes NC both keep the shipped gapped row.
	var strip_mode: bool = _strip_mode()
	if strip_mode:
		var sum_w: float = 0.0
		for d2: Variant in defs:
			sum_w += float(d2[1])
		var scale: float = total / sum_w
		for d3: Variant in defs:
			d3[1] = float(d3[1]) * scale
		gap = 0.0
	if strip_mode:
		# The bar stands FIRST: the sections take its plane
		# (below), so it must exist before they seat.
		_build_rail_bar(total, tile_h, y, z)
	var x: float = -total * 0.5
	for d: Variant in defs:
		var key: String = str(d[0])
		var w: float = float(d[1])
		var q: ClickableQuad = _make_quad(_rail, "rail", key, placeholder, Vector2(w, tile_h), Vector3(x + w * 0.5, y, z))
		if key == "page_label" or (key == "wovp_refresh" and not _refresh_pickable()):
			# page_label is a readout, never a stop. REFRESH
			# builds live like every other stop (GRADFIX16
			# item 1 - see _refresh_pickable); only the NC's
			# restored gating builds it pick-dead.
			q.pick_enabled = false
		_rail_quads[key] = q
		_rail_def_w[key] = w
		_rail_last_key = key
		if strip_mode:
			# The strip's sections carry no frame (the lift
			# is the highlight) and remember their flush
			# seat + lift direction for _update_rail_lift.
			q.suppress_frame = true
			# ONE PLANE (the machined law): a section seats
			# COPLANAR with the backing bar - the bar's own
			# basis, not _make_quad's per-quad face_point.
			# Individually eye-facing sections shingle over
			# each other from any viewpoint but the eye point
			# itself, eating each other's label ink at the
			# seams (convicted on the first strip grabs: AL /
			# RECEN / XIT truncations in the desk view); one
			# flat bar tiles exactly from everywhere, and its
			# lift direction is the bar's own normal for
			# every section.
			q.transform = Transform3D(_rail_bar.transform.basis, q.position)
			_rail_base_pos[key] = q.position
			_rail_pop_dir[key] = _rail_bar.transform.basis.z.normalized()
			_rail_pop[key] = 0.0
			_rail_pop_vel[key] = 0.0
			_rail_pop_applied[key] = 0.0
			_rail_tex_lifted[key] = false
		x += w + gap


## The machined strip's ONE backing bar (GRADFIX14 item 1):
## a single quad spanning the whole rail, wearing the bar's
## resting graphite gradient, seated a hair behind the
## section faces. It is what a lifted section lifts OFF -
## the recess it leaves is bar material, never a hole - and
## it makes the one-piece read structural, not a texture
## trick: bar_state counts it, and the tileboxes NC (no
## bar, gapped tiles) fails that count by name. Not a
## ClickableQuad: it is never pickable, focusable or a stop.
func _build_rail_bar(total: float, tile_h: float, y: float, z: float) -> void:
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	grad.colors = PackedColorArray(RoomSpecs.STRIP_GRAD_REST)
	var gtex: GradientTexture2D = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 4
	gtex.height = 256
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = gtex
	_rail_bar = MeshInstance3D.new()
	_rail_bar.name = "RailStripBar"
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(total, tile_h)
	_rail_bar.mesh = qm
	_rail_bar.material_override = mat
	_rail_bar.position = Vector3(0.0, y, z)
	_rail.add_child(_rail_bar)
	ClickableQuad.face_point(_rail_bar, EYE)
	# A hair behind the section faces, along its own normal.
	_rail_bar.position += (_rail_bar.position - EYE).normalized() * 0.006


## True while the rail stands as the machined strip
## (GRADFIX14 item 1): the shipped build, minus the two
## wholesale-restore NCs (the pre-Console widebar and this
## item's own tileboxes).
func _strip_mode() -> bool:
	return debug_gf14_nc != "tileboxes" and not _console_wide()


func _make_quad(parent: Node3D, action: String, payload: String, tex: Texture2D, size: Vector2, pos: Vector3) -> ClickableQuad:
	var q: ClickableQuad = ClickableQuad.new()
	q.setup(action, payload, tex, size)
	q.position = pos
	parent.add_child(q)
	ClickableQuad.face_point(q, EYE)
	return q


## The banner's one line: library summary, the empty-filter guard's
## explanation when it fired, and any transient launch status.
func _banner_line() -> String:
	if _tournament:
		return _tournament_banner_line()
	var line: String = "%d files - %d games - filter %s - sort %s" % [
		_scanner.total_files, _scanner.games.size(),
		str(FILTER_LABELS[_filter]), str(SORT_LABELS[_sort])]
	if _filter == "new":
		# GRADFIX11: the NEW banner carries the filter's
		# whole membership - how many games in the library
		# are new right now, counted over the scanner's
		# full set (net or no net: a standing letter net
		# narrows the wall, never this count) - after the
		# sort segment, before the letter-net suffix.
		var new_now: int = int(Time.get_unix_time_from_system())
		var new_count: int = 0
		for g: GameEntry in _scanner.games:
			if g.is_new(new_now):
				new_count += 1
		line += " - %d new" % new_count
	if _letter_net == "THE":
		line += " - THE tables"
	elif _letter_net == "#":
		line += " - number/symbol titles"
	if _filter_note != "":
		line += " - " + _filter_note
	if _status_note != "":
		line += " - " + _status_note
	return line


## The status line's refresh: a text set, not a render - the
## plate + Label3D carry it now (see _build_status_line), so
## a banner change costs nothing and never enters the face
## caches. The line's CONTENT is unchanged (library summary,
## view note, status note) - only its carrier moved.
func _refresh_banner() -> void:
	if _status_label == null or _scanner == null:
		return
	var new_line: String = _banner_line()
	if new_line != _status_text:
		# OPTIMIZE standing-cost cut: the status label's text
		# is re-assigned only when the line actually changes
		# (a Label3D text set re-shapes the label; the banner
		# refresh runs on every fill and centre change).
		_status_text = new_line
		_sc_label_reassign += 1 ## OPTIMIZE standing-cost audit (observation only)
		_status_label.text = _status_text


## A rail stop's [label, accent] under the room's current
## state - the one place that knows what each button says.
func _rail_label_accent(key: String) -> Array:
	var label: String = ""
	var accent: bool = false
	if key.begins_with("filter:"):
		var f: String = key.trim_prefix("filter:")
		label = str(FILTER_LABELS[f])
		accent = f == _filter and not _tournament
	elif key == "sort":
		label = "SORT: " + str(SORT_LABELS[_sort])
	elif key == "tournament":
		label = "TOURNAMENT"
		accent = _tournament
	elif key == "wovp_refresh":
		label = "REFRESH"
	elif key == "page_label":
		label = "%d / %d" % [_page + 1, page_count()]
	elif key == "desk":
		label = "SETUP"
	elif key == "exit":
		label = "EXIT"
	return [label, accent]


func _rail_cache_key(label: String, accent: bool) -> String:
	return label + ("|a" if accent else "|p")


## A strip section face's cache key (GRADFIX14 item 1): the
## label, its accent state and its lift state - both lift
## variants of every standing label render once and cache,
## so a focus move never waits on a render.
func _rail_strip_cache_key(label: String, accent: bool, lifted: bool) -> String:
	return label + "|s" + ("a" if accent else "p") + ("l" if lifted else "r")


## Dress ONE rail section from the strip cache (GRADFIX14
## item 1): the face it wears follows its lift state
## (_rail_tex_lifted, driven by the lift spring's half-rise)
## as well as its label/accent. Change-guarded: a section
## already wearing the right face is untouched.
func _apply_rail_texture_for(key: String) -> void:
	var quad: ClickableQuad = _rail_quads.get(key) as ClickableQuad
	if quad == null:
		return
	var la: Array = _rail_label_accent(key)
	var lifted: bool = bool(_rail_tex_lifted.get(key, false))
	var ck: String = _rail_strip_cache_key(str(la[0]), bool(la[1]), lifted)
	if str(_rail_applied_key.get(key, "")) == ck:
		return
	if _rail_tex_cache.has(ck):
		quad.set_texture(_rail_tex_cache[ck] as Texture2D)
		_rail_applied_key[key] = ck


## Dress every rail quad from the texture cache, in this call -
## no awaits. A cache hit is the button's real rendered face,
## so the rail is fully dressed in the rebuild's own frame. A
## miss keeps whatever face the quad already wears (the
## standing rail never falls back to the placeholder again)
## until the async fill renders that label - once, ever.
func _apply_rail_textures() -> void:
	if _strip_mode():
		for k2: Variant in _rail_quads.keys():
			_apply_rail_texture_for(str(k2))
		return
	for k: Variant in _rail_quads.keys():
		var la: Array = _rail_label_accent(str(k))
		var ck: String = _rail_cache_key(str(la[0]), bool(la[1]))
		if _rail_tex_cache.has(ck):
			var quad: ClickableQuad = _rail_quads[k] as ClickableQuad
			if quad != null:
				quad.set_texture(_rail_tex_cache[ck] as Texture2D)


## The strip's laid-out slots, in the ONE order
## (LetterIndex.slot_keys): A-Z, then THE, then "#" at the
## row's right end when the library holds a non-letter
## title. Layout, walk, focusables and greying all read
## this list - see LetterIndex.slot_keys for the history.
func _strip_slot_keys() -> Array[String]:
	return LetterIndex.slot_keys(_strip_has_number)


## Build every slot once (the "#" slot included - _refresh_
## strip decides whether it is laid out). Creation order is
## not layout order; _refresh_strip positions the row.
func _build_strip(placeholder: Texture2D) -> void:
	var provisional: Vector3 = Vector3(0.0, STRIP_Y, STRIP_Z)
	for i: int in range(26):
		var letter: String = String.chr(65 + i)
		_strip_quads[letter] = _make_quad(_rail, "letter", letter, placeholder, _strip_letter_size(), provisional)
	_strip_quads["THE"] = _make_quad(_rail, "letter", "THE", placeholder, _strip_slot_size("THE"), provisional)
	_strip_quads["#"] = _make_quad(_rail, "letter", "#", placeholder, _strip_letter_size(), provisional)


## The strip's per-rebuild truth, from the two presence reads
## (see LetterIndex.presence_over): across the whole library,
## whether the "#" slot exists at all; across the current
## filter's collection, which slots light up. Laid-out slots
## are centered as one row under the rail; a slot that is not
## laid out is invisible and unpickable. Pick states land
## here too - a greyed slot is never a stop, for the pointer
## or for focus.
func _refresh_strip() -> void:
	var lib_presence: Dictionary = {}
	var presence: Dictionary = {}
	var colour_presence: Dictionary = {}
	if _scanner != null:
		lib_presence = LetterIndex.presence_over(_scanner.games)
		# NEXTROUND (item 1): presence over the CURRENT
		# filter's collection, taken fresh at every refresh
		# (every rebuild follows a filter press, a library
		# adoption, a favourite-driven rebuild or a net
		# change, so the strip's truth is the standing
		# filter's by construction). This read drives the
		# slots' PICK state and layout, always fresh.
		presence = LetterIndex.presence_over(_collect_filtered())
		# The COLOUR encoding's read is the same presence -
		# except under the PVLDS_STRIP_NC=stale seam, which
		# freezes the colour read at the first refresh after
		# the library landed (the pick state above never
		# freezes: the seam restores stale COLOURS, the
		# field symptom, not a broken strip).
		if debug_strip_nc == "stale" and _strip_frozen_valid:
			colour_presence = _strip_frozen_presence
		else:
			colour_presence = presence
			if debug_strip_nc == "stale":
				_strip_frozen_presence = colour_presence
				_strip_frozen_valid = true
	_strip_presence_now = colour_presence
	_strip_has_number = lib_presence.has("#")
	var keys: Array[String] = _strip_slot_keys()
	var total: float = 0.0
	for key: String in keys:
		total += _strip_slot_size(key).x + _strip_gap()
	total -= _strip_gap()
	# The row is positioned BY THE ONE LIST (keys): the x
	# cursor advances in slot_keys order, so the drawn
	# sequence is the list's sequence by construction - it
	# can never again drift from the walk's order the way
	# the build-order iteration let it (the strip-order
	# fix: _build_strip creates "#" last, and positioning
	# in creation order drew it last while slot_keys
	# claimed it led). A quad the list does not carry is
	# not laid out at all.
	var x: float = -total * 0.5
	for key: String in keys:
		var q: ClickableQuad = _strip_quads.get(key) as ClickableQuad
		if q == null:
			continue
		var w: float = _strip_slot_size(key).x
		q.visible = true
		q.position = Vector3(x + w * 0.5, STRIP_Y, STRIP_Z)
		# The row re-centers whenever the "#" slot joins or
		# leaves, so a slot's facing follows its laid-out
		# position, not the position it was built at.
		ClickableQuad.face_point(q, EYE)
		x += w + _strip_gap()
		q.pick_enabled = presence.has(key)
		q.set_content_alpha(1.0)
	for key: String in _strip_quads.keys():
		if not keys.has(key):
			var hq: ClickableQuad = _strip_quads[key] as ClickableQuad
			if hq != null:
				hq.visible = false
				hq.pick_enabled = false
	_apply_strip_textures(colour_presence)


func _strip_slot_size(key: String) -> Vector2:
	if key == "THE":
		return STRIP_THE_SIZE_WIDE if _console_wide() else STRIP_THE_SIZE
	return _strip_letter_size()


## The Console bar's live seam (GRADFIX5): the widebar NC
## restores the pre-Console furniture's measurements
## wholesale - rail widths, gaps, strip pads, status plate.
func _console_wide() -> bool:
	return OS.get_environment("PVLDS_GRADFIX5_NC") == "widebar"


func _strip_letter_size() -> Vector2:
	return STRIP_LETTER_SIZE_WIDE if _console_wide() else STRIP_LETTER_SIZE


func _strip_gap() -> float:
	return STRIP_GAP_WIDE if _console_wide() else STRIP_GAP


## A slot's [label, state] under the current view: the label
## is the key itself; the state is "dim" for a slot with no
## games in the filter's set, "accent" for the net slot whose
## view is standing, "plain" otherwise.
func _strip_label_state(key: String, presence: Dictionary) -> Array:
	var state: String = "plain"
	if not presence.has(key):
		state = "dim"
	elif key == _letter_net:
		state = "accent"
	return [key, state]


## Dress every laid-out slot from the texture cache, in this
## call (the rail's discipline): a hit is the slot's real
## face in the rebuild's own frame; a miss keeps the face it
## already wears until _fill_wall_textures renders that
## label+state once, ever.
func _apply_strip_textures(presence: Dictionary) -> void:
	for key: String in _strip_slot_keys():
		var quad: ClickableQuad = _strip_quads.get(key) as ClickableQuad
		if quad == null:
			continue
		var ls: Array = _strip_label_state(key, presence)
		var ck: String = str(ls[0]) + "|" + str(ls[1])
		if _strip_tex_cache.has(ck):
			var want_tex: Texture2D = _strip_tex_cache[ck] as Texture2D
			if quad.current_texture() != want_tex:
				# OPTIMIZE standing-cost cut: a slot already
				# wearing its face is not re-assigned it (the
				# dress ran on every rebuild, same texture).
				_sc_label_reassign += 1 ## OPTIMIZE standing-cost audit (observation only)
				quad.set_texture(want_tex)
			if quad.current_texture() == want_tex:
				_strip_worn_state[key] = str(ls[1]) ## NEXTROUND (item 1): the worn-state record (see _strip_worn_state) - recorded on the wear, not the assignment, so a slot already wearing its face still testifies


## A strip pick: the jump itself. An ordinary letter files
## the wall to title sort (quietly - the banner's sort line
## says NAME after) and lands on the letter's first page.
## A net slot (THE / #) raises the net view instead: page
## one of exactly its games. Picking a letter from inside a
## net exits the net at that letter - the games were never
## moved, only viewed. RECENTS drops to ALL on any pick: a
## recency list's order is its meaning, and a letter index
## over it would be a lie - the jump leaves the list for the
## library, the way picking a filter leaves a sort. Greyed
## slots are not pickable and never reach here; the
## no-such-letter landing below is defensive only.
##
## THE FOCUS LAW (Chris, 2026-10-27, reversing this round's
## first landing in the field): PICKS MOVE THE WALL, NEVER
## THE FOCUS. A letter pick used to land focus on the page's
## first card; from the strip that reads as a theft - the
## player is pulled off the bar and has to climb back down
## for the next letter. So every pick lands on the slot that
## was pressed (see _land_after_letter_pick) - the same rule
## the rail's stops won in the 2026-10-25 round and page
## travel in the focus-fix round: a press lands on the stop
## that was activated, and the letter slot IS the activated
## stop. Do not re-litigate this in a later round without
## the player's word.
func _jump_to_letter(key: String) -> void:
	_failed_game_id = ""
	_status_note = ""
	_exit_tournament() ## a letter pick files the LIBRARY - it leaves the Tournament Room like any library view change
	if _filter == "recents":
		_filter = "all"
	_sort = "name"
	if key == "THE" or key == "#":
		_letter_net = key
		_page = 0
		_centre_index = 0
		_recompute_visible()
		_rebuild_wall()
		_persist_view()
		_land_after_letter_pick(key, _panels[0] if not _panels.is_empty() else null)
		return
	_letter_net = ""
	_recompute_visible()
	var idx: int = -1
	for i: int in range(_visible_games.size()):
		if LetterIndex.letter_of(_visible_games[i].title) == key:
			idx = i
			break
	if idx < 0:
		_rebuild_wall()
		_persist_view()
		_land_after_letter_pick(key, null)
		return
	# The drum swings to the letter's first game (the letter
	# round's whole point: position the shelf at the letter);
	# focus stays on the pressed slot (the focus law below).
	# The rebuild stands because the pick forces the name
	# sort - if the standing sort was another, the shelf's
	# order itself changed and the cards must re-seat.
	_rebuild_wall()
	_set_centre(idx)
	_persist_view()
	_land_after_letter_pick(key, _panels[idx] if idx < _panels.size() else null)


## The letter pick's focus landing - the one place the focus
## law above is decided. Focus takes the pressed slot (the
## strip is persistent furniture, so the quad is the same
## instance the rebuild re-dressed); the wall moved, the
## player did not. When the slot is somehow not a live focus
## stop (a defensive path - greyed slots never reach the
## jump), focus stays wherever the rebuild left it. The NC
## value "letterland" restores the letter round's original
## first-card landing for the harness, so the smoke's
## focus-law legs fail by name against it.
func _land_after_letter_pick(key: String, nc_fallback: ClickableQuad) -> void:
	if debug_focus_nc == "letterland":
		if nc_fallback != null:
			_set_focused(nc_fallback)
		return
	var sq: ClickableQuad = _strip_quads.get(key) as ClickableQuad
	if sq != null and _focusables.has(sq):
		_set_focused(sq)


## The panel face cache's LRU read: a hit returns
## [Texture2D, art_aspect, art_path] and renews the entry's
## place. The art path rides along as the entry's provenance
## (which art file the texture was composed from; "" for a
## styled card) - the readers that only ever used [0]/[1]
## are untouched. Under the debug_opt_nc="nocache" seam the
## cache never serves: every issue re-renders, so the
## facecache smoke's swap and counters legs fail by name.
func _face_cache_get(key: String) -> Array:
	if debug_opt_nc == "nocache":
		return [] ## NC seam (PVLDS_OPT_NC=nocache): the cache is disabled
	if not _face_tex_cache.has(key):
		return []
	_face_cache_order.erase(key)
	_face_cache_order.push_back(key)
	return _face_tex_cache[key] as Array


## PHANTOMFIX Layer 1 - the provenance law: a cache entry
## serves a key only when the art path recorded at its put
## (entry[2]) IS the key's art path. A styled fallback put
## under an art key by a failed art attempt (a failed
## capture, a failed decode) carries "" there, so it can
## never serve the art key again - the fill falls through
## to a genuine render, and the heal's retry can cure the
## face instead of restamping the fallback forever. The
## NC seam restores provenance-blind serving.
func _face_cache_serves(entry: Array, art_path: String) -> bool:
	if debug_phantom_nc == "phantom":
		return true ## NC seam (PVLDS_PHANTOM_NC=phantom): pre-fix blind serving
	return entry.size() >= 3 and str(entry[2]) == art_path


## The panel face cache's LRU write: past FACE_CACHE_MAX
## the oldest faces are dropped (their games simply
## re-render on a later visit - a miss is a cost, never a
## wrong face, because the key carries the game's art path,
## favorite flag and PuP flag (GRADFIX6 item 5: a face
## rendered before the db match lands must not serve forever
## without its PuP badge), and a fresh library clears the
## cache). FACECACHE: this LRU cap drop is now the ONLY
## distance-blind eviction the cache knows - the OPTIMIZE
## round's settle-time margin pass (drop whatever stands
## outside the window +/- EVICT_MARGIN_COLS columns, and
## clear its panel's stamp with it) is deleted: leaving the
## window is not an eviction offence any more, so a face
## the player scrolls away from and back to is still here.
func _face_cache_put(key: String, tex: Texture2D, aspect: float, art_path: String = "") -> void:
	_face_tex_cache[key] = [tex, aspect, art_path]
	_face_cache_order.erase(key)
	_face_cache_order.push_back(key)
	var nb_guard: int = 0
	while _face_cache_order.size() > FACE_CACHE_MAX:
		var old: String = str(_face_cache_order[0])
		var old_ent: Array = _face_tex_cache.get(old, []) as Array
		var old_tex: Texture2D = (old_ent[0] as Texture2D) if not old_ent.is_empty() else null
		if old_tex != null and _nb_tex_bound_visible(old_tex):
			# NEVERBLANK (the fix): skip-and-mark - the LRU
			# entry's texture is bound to a visible panel,
			# so it rotates to the back of the line instead
			# of dropping; cap pressure is absorbed by
			# unbound entries only. If every over-cap entry
			# is bound, the cache rides over the cap until
			# one unbinds (the guard ends the rotation).
			_face_cache_order.pop_front()
			_face_cache_order.push_back(old)
			_nb_evict_deferred_count += 1
			_nb_sync_footer()
			_telemetry_record("evict_deferred", {
				"key": old, "via": "cap",
				"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
			})
			nb_guard += 1
			if nb_guard > _face_cache_order.size():
				break
			continue
		_face_cache_order.pop_front()
		if not old_ent.is_empty():
			_nb_note_evict(old, old_tex, "cap") ## NEVERBLANK instrument
		_face_tex_cache.erase(old)
		_evicted_total += 1 ## a cap drop is an eviction (the only kind left)
	_fc_sync_footer()


## Drop one cached face (the panel heal's art retry: the
## styled card cached under an art key must not re-serve
## itself when the heal asks for the art render again).
func _face_cache_evict(key: String) -> void:
	var fent: Array = _face_tex_cache.get(key, []) as Array
	if not fent.is_empty():
		var ftex: Texture2D = fent[0] as Texture2D
		if ftex != null and _nb_tex_bound_visible(ftex):
			# NEVERBLANK (the fix): the entry's texture is
			# bound to a visible panel, so the eviction is
			# DEFERRED - the entry stays. The heal's retry
			# render replaces it under this key when it
			# lands, and the deferred entry cannot re-serve
			# itself meanwhile (the fill's cache branch
			# refuses a stale-aspect art entry); cap
			# pressure reaches it once it is unbound.
			_nb_evict_deferred_count += 1
			_nb_sync_footer()
			_telemetry_record("evict_deferred", {
				"key": key, "via": "force",
				"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
			})
			return
		_nb_note_evict(key, ftex, "force") ## NEVERBLANK instrument
	_face_tex_cache.erase(key)
	_face_cache_order.erase(key)


## FACECACHE account: one composed render served for a
## game under a face key. A render whose game already
## rendered under the SAME key this session is an
## eviction-forced re-render (its entry was dropped under
## cap pressure, or the heal force-evicted the key for its
## retry) - counted apart, because that is the number the
## retention law exists to hold down.
func _fc_note_render(game_id: String, fkey: String) -> void:
	_fc_renders += 1
	_fc_renders_per_game[game_id] = int(_fc_renders_per_game.get(game_id, 0)) + 1
	if str(_fc_last_render_key.get(game_id, "")) == fkey:
		_fc_rerenders_eviction += 1
	_fc_last_render_key[game_id] = fkey
	_fc_sync_footer()


## FACECACHE account: one fill served from the cache.
func _fc_note_swap() -> void:
	_fc_swaps += 1
	_fc_sync_footer()


## The composed-face cache's session account, for the
## smokes and the telemetry footer: how many games ever
## rendered, how many renders and swaps were served, how
## many renders were eviction-forced re-renders, and the
## worst per-game render count (the field log's ~4x, the
## number this round exists to bring to ~1 per state).
func face_cache_stats() -> Dictionary:
	var worst: int = 0
	for gid: Variant in _fc_renders_per_game.keys():
		worst = maxi(worst, int(_fc_renders_per_game[gid]))
	return {
		"unique_games": _fc_renders_per_game.size(),
		"renders": _fc_renders,
		"swaps": _fc_swaps,
		"rerenders_after_eviction": _fc_rerenders_eviction,
		"max_renders_one_game": worst,
		"renders_per_game": _fc_renders_per_game.duplicate(),
	}


## The game ids whose composed faces are resident in the
## cache right now (the facecache smoke's pass-2 baseline:
## a resident game must never read missing mid-chain, and
## must never re-render - only cap-evicted games may).
func face_cache_resident_games() -> Array[String]:
	var out: Array[String] = []
	for key: String in _face_tex_cache.keys():
		var gid: String = key.split("|")[0]
		if not out.has(gid):
			out.append(gid)
	return out


## Push the cache account into the telemetry footer's
## extra fields (called on every counter change - a small
## dictionary write, never on a frame path of its own).
func _fc_sync_footer() -> void:
	if not _scroll_telemetry_started:
		return
	_scroll_telemetry.set_footer_extra({
		"facecache_unique_games": _fc_renders_per_game.size(),
		"facecache_renders": _fc_renders,
		"facecache_swaps": _fc_swaps,
		"facecache_rerenders_after_eviction": _fc_rerenders_eviction,
		"facecache_evicted_total": _evicted_total,
	})
	_nb_sync_footer()


## NEVERBLANK: the session's never-blank account, merged
## into the telemetry footer beside the face cache's (the
## proof reads the law's counters from the log's own
## footer: face_clear attempts must read 0).
func _nb_sync_footer() -> void:
	if not _scroll_telemetry_started:
		return
	_scroll_telemetry.set_footer_extra({
		"neverblank_face_clear_attempts": _nb_face_clear_count,
		"neverblank_evict_bound": _nb_evict_bound_count,
		"neverblank_evict_deferred": _nb_evict_deferred_count,
		"neverblank_enqueue_swaps": _nb_enqueue_swaps,
	})


## The assignment probe (installed on ClickableQuad in
## setup): fires on every set_texture in the room. Only
## one transition is the law's business - an EMPTY-LIKE
## incoming texture (null, or not a real face by the
## standing _tex_is_real measure: the 4x4 placeholder,
## clear and fallback solids) over a REAL standing face,
## on a CARD panel. Everything else returns in two size
## checks. Convictions count + record; the shipped law is
## that the count stays 0.
func _nb_on_texture_assign(quad: ClickableQuad, old_tex: Texture2D, new_tex: Texture2D) -> void:
	if quad == null or not _tex_is_real(old_tex) or _tex_is_real(new_tex):
		return
	var entry: Dictionary = _panel_pool.get(quad.payload, {}) as Dictionary
	if entry.is_empty() or str(entry.get("mode", "")) != "card":
		return
	_nb_face_clear_count += 1
	_nb_sync_footer()
	var idx: int = _panels.find(quad)
	_telemetry_record("face_clear", {
		"game": quad.payload,
		"col": _grid_coord(idx).x if idx >= 0 else -1,
		"old_size": "%dx%d" % [old_tex.get_width(), old_tex.get_height()],
		"new_size": "null" if new_tex == null else "%dx%d" % [new_tex.get_width(), new_tex.get_height()],
		"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
	})


## Whether a composed face texture is bound to a panel
## the drawn window currently shows. A bound texture may
## not be dropped by the cache: the panel keeps wearing
## it, and dropping the cache's reference under it is
## exactly the eviction the instrument watches.
func _nb_tex_bound_visible(tex: Texture2D) -> bool:
	if tex == null:
		return false
	for qv: Variant in _panels:
		var q: ClickableQuad = qv as ClickableQuad
		if q != null and q.visible and q.current_texture() == tex:
			return true
	return false


## An eviction is about to drop a key: if its texture is
## bound to a visible panel, that is the instrument's
## second conviction - count it and put it in the log.
func _nb_note_evict(key: String, tex: Texture2D, via: String) -> void:
	if tex == null or not _nb_tex_bound_visible(tex):
		return
	_nb_evict_bound_count += 1
	_nb_sync_footer()
	_telemetry_record("evict_bound", {
		"key": key, "via": via,
		"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
	})


## The session's never-blank account for the smokes (the
## footer carries the same numbers for the field log).
func neverblank_counts() -> Dictionary:
	return {
		"face_clear": _nb_face_clear_count,
		"evict_bound": _nb_evict_bound_count,
		"evict_deferred": _nb_evict_deferred_count,
		"enqueue_swaps": _nb_enqueue_swaps,
	}


## NEVERBLANK: the one door every card-face bind walks
## through. Production binds the replacement directly -
## the panel's standing texture holds until this call, and
## this call replaces it in the same operation; there is
## no frame in which the panel wears nothing. The
## clearfirst NC restores the pre-law shape on the swap
## seam only: the dark placeholder binds first and the
## real face lands a few frames later (the pending list
## below, drained in _process), so the chain census's
## black-pane legs fail by name.
func _nb_bind_face(quad: ClickableQuad, tex: Texture2D, seam: String) -> void:
	if debug_nb_nc == "clearfirst" and seam == "swap":
		quad.set_texture(_placeholder_tex)
		_nb_nc_pending.append([quad, tex, 12])
		return
	quad.set_texture(tex)


## Bind one cache-hit face at ENQUEUE time - synchronously,
## in the centre change's own call stack, before the art
## pipeline's pass starts. Mirrors the fill tail's duties
## for a served face: the stamp, the nameplate law, the
## power-on debts, the plate re-derivation. (The Launch
## plinth is not dressed here: a cache hit implies a fill
## tail already ran for this game and dressed it.)
func _nb_apply_swap(idx: int, fkey: String, hit: Array) -> void:
	var game: GameEntry = _visible_games[idx]
	var quad: ClickableQuad = _panels[idx]
	var tex: Texture2D = hit[0] as Texture2D
	var aspect: float = float(hit[1]) if hit.size() >= 2 else 0.0
	var from_art: bool = aspect > 0.0
	_sc_face_assigns += 1 ## OPTIMIZE standing-cost audit (observation only)
	if quad.current_texture() == tex and debug_nb_nc != "clearfirst":
		_sc_noop_face_swaps += 1 ## the heal erased the stamp, not the dress: counted, skipped
	else:
		_nb_bind_face(quad, tex, "swap")
	_panel_face_key[game.game_id] = fkey
	if idx < _panel_plates.size() and _panel_plates[idx] != null:
		_panel_plates[idx].visible = from_art
		_panel_labels[idx].visible = from_art
		if idx == _flip_idx and _flip_t >= 0.5:
			_apply_flip_side(idx, true)
	if quad == _power_missed:
		_power_missed = null
		if _power_candidate == quad:
			_power_candidate_t = POWER_SETTLE_SEC
	if quad == _power_panel:
		_restore_power("face_arrived")
	_panel_art_aspect[idx] = aspect
	_rederive_card_plate(idx, game)
	if _panel_pop[idx] > 0.0:
		_panel_pop_applied[idx] = -1.0
		_pop_awake = true
	_note_swap(_swing_active or page_slide_active())
	_fc_note_swap()
	_nb_enqueue_swaps += 1
	_nb_sync_footer()
	_art_event("apply", {
		"game": game.game_id, "path": _face_path_memoized(game), "col": _grid_coord(idx).x,
		"shot_origin": game.shot_origin() if game.is_shot_path(_face_path_memoized(game)) else "",
		"centre_col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
		"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
		"cost_ms": 0.0, "branch": "facecache", "load_ms": 0.0, "render_ms": 0.0,
		"cache": "hit", "via": "enqueue",
	})


## Whether the enqueue may serve this face from the cache
## right now - the fill's own gates, read through the
## pipeline memo: not a tournament state panel, not the
## blackface NC's target, a cache entry exists, and the
## entry is not a styled render cached under an art key
## (the poison the heal exists to retry).
func _nb_try_enqueue_swap(idx: int) -> bool:
	if idx < 0 or idx >= _visible_games.size() or idx >= _panels.size():
		return false
	if _tournament and idx < _tournament_rows.size() \
			and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
		return false
	var game: GameEntry = _visible_games[idx]
	if _blackface_nc(game):
		return false
	var fkey: String = _face_key_for_memo(idx)
	var hit: Array = _face_cache_get(fkey)
	if hit.is_empty():
		return false
	# PHANTOMFIX Layer 1: the swap may bind only an entry
	# whose provenance is this key's art path - the old
	# aspect proxy (a memoized art path with a zero-aspect
	# entry) let a styled fallback cached under the art key
	# through whenever the memo had already been corrected.
	var key_parts: PackedStringArray = fkey.split("|")
	var key_art: String = str(key_parts[1]) if key_parts.size() >= 2 else ""
	if not _face_cache_serves(hit, key_art):
		return false
	_nb_apply_swap(idx, fkey, hit)
	return true


func _fill_wall_textures(gen: int) -> void:
	var bench_t0: int = Time.get_ticks_msec()
	var bench_renders: int = 0
	# The status line first: it carries the library summary.
	# It is a Label3D now - a text set, no factory render, so
	# it never touches the caches below.
	_refresh_banner()
	var bench_t_banner: int = Time.get_ticks_msec()
	# Rail buttons SECOND - they used to render last, after a
	# dozen panels and their Launch buttons, which is exactly
	# why the bar reassembled itself piece by piece on every
	# flip. Cache hits dress instantly; a label that has never
	# rendered (a first-ever page count) renders now, ahead of
	# the panels, and joins the cache for every later wall.
	for key: Variant in _rail_quads.keys():
		var k: String = str(key)
		var quad: ClickableQuad = _rail_quads[k]
		var la: Array = _rail_label_accent(k)
		var label: String = str(la[0])
		var accent: bool = bool(la[1])
		if _strip_mode():
			# GRADFIX14 (item 1): the section's strip faces -
			# rest and lifted variants, each rendered at the
			# section's own aspect, cached like every rail
			# face before them. The page readout never lifts.
			var variants: Array[bool] = [false, true]
			for lifted_v: bool in variants:
				if lifted_v and k == "page_label":
					continue
				var sck: String = _rail_strip_cache_key(label, accent, lifted_v)
				if _rail_tex_cache.has(sck):
					continue
				bench_renders += 1
				var spx: Vector2i = Vector2i(maxi(96, int(round(float(_rail_def_w.get(k, 0.2)) * RAIL_STRIP_PX_PER_M))), int(round(RAIL_TILE_H * RAIL_STRIP_PX_PER_M)))
				var stex: Texture2D = await _factory.render_texture(RoomSpecs.strip_section_spec(label, accent, lifted_v, k != _rail_last_key), spx)
				if gen != _gen:
					return
				_rail_tex_cache[sck] = stex
			_apply_rail_texture_for(k)
			continue
		var ck: String = _rail_cache_key(label, accent)
		if _rail_tex_cache.has(ck):
			quad.set_texture(_rail_tex_cache[ck] as Texture2D)
			continue
		bench_renders += 1
		var btex: Texture2D = await _factory.render_texture(RoomSpecs.button_spec(label, accent), Vector2i(512, 150))
		if gen != _gen:
			return
		_rail_tex_cache[ck] = btex
		quad.set_texture(btex)
	# Strip slots THIRD - same furniture family as the rail:
	# cache hits already dressed in _refresh_strip; a
	# label+state that has never rendered (a first-ever dim
	# letter, the accent of a net just raised) renders now,
	# ahead of the panels, and joins the cache.
	# NEXTROUND (item 1): the fill dresses from the SAME
	# presence read _refresh_strip just took (_strip_
	# presence_now), never a second read of its own - the
	# two dress sites can no longer disagree about which
	# filter's colours the strip wears.
	var strip_presence: Dictionary = _strip_presence_now if _scanner != null else {}
	for skey: String in _strip_slot_keys():
		var squad: ClickableQuad = _strip_quads.get(skey) as ClickableQuad
		if squad == null:
			continue
		var ls: Array = _strip_label_state(skey, strip_presence)
		var sck: String = str(ls[0]) + "|" + str(ls[1])
		if _strip_tex_cache.has(sck):
			squad.set_texture(_strip_tex_cache[sck] as Texture2D)
			_strip_worn_state[skey] = str(ls[1]) ## NEXTROUND (item 1): the worn-state record
			continue
		var spx: Vector2i = Vector2i(500, 250) if skey == "THE" else Vector2i(229, 250) ## the Console pads' own aspect (pass 2: 0.170/0.085 and 0.078/0.085), so the glyphs are not stretched (GRADFIX5's rule, GRADFIX6's numbers)
		bench_renders += 1
		var stex: Texture2D = await _factory.render_texture(RoomSpecs.letter_spec(str(ls[0]), str(ls[1])), spx)
		if gen != _gen:
			return
		_strip_tex_cache[sck] = stex
		squad.set_texture(stex)
		_strip_worn_state[skey] = str(ls[1]) ## NEXTROUND (item 1): the worn-state record
	var bench_t_furniture: int = Time.get_ticks_msec()
	if _tournament:
		# The Tournament Room's challenge panels are cards and
		# dress through the standard window fill; the lone
		# state panel (when the view is a state row) wears its
		# board face here. GRADFIX6 (item 3): the window fill
		# is requested FIRST - the state face's render used to
		# head-of-line block the challenge faces in the serial
		# factory queue on first entry.
		_request_window_fill()
		await _fill_tournament_state_faces(gen)
		if gen != _gen:
			return
		if gen == _gen:
			wall_ready = true
		return
	# Cards: the window's faces stream in through the fill
	# worker (see _request_window_fill) - the rebuild only
	# asks; centre changes re-ask, and the worker coalesces.
	_request_window_fill()
	if debug_bench:
		print("BENCH: fill gen=%d page=%d banner=%dms furniture=%dms renders=%d" % [
			gen, _page, bench_t_banner - bench_t0, bench_t_furniture - bench_t_banner,
			bench_renders])


## The window fill worker: fills the standing window's faces,
## centre card first, then outward. One pass at a time - a
## centre change mid-pass marks the fill dirty and the pass
## re-runs for the new window when the current one ends, so a
## fast swing never stacks render queues. A face is a pure
## function of (game, its face file, favorite flag, PuP flag) inside
## one library adoption, cached like the furniture's faces
## (the pick-latency fix): pooled cards keep their faces
## across rebuilds, so a revisit usually costs nothing at all.
##
## GRADFIX16 (item 2) - THE STAGED PIPELINE. The conviction
## (Chris's scroll telemetry + the harness probe, same
## fixture before/after): during a held cruise each incoming
## column made the travel path itself pay, serially per face,
## a synchronous PNG decode (~7.5 ms) + Lanczos resize
## (~8 ms) in TextureFactory.load_art_texture and a GPU
## readback in TextureFactory.render_texture - per-column
## fill totals of 54-105 ms on the harness box, ~125 ms a
## hitch on the field rig, one hitch per column at cruise
## cadence. The fill now runs OFF the travel frame:
## _set_centre only ENQUEUES the window's faces (below) and
## returns; a deferred pipeline pass does the work on its
## own frames, one face per frame at most -
##   1. DECODE stages on a WorkerThreadPool thread
##      (TextureFactory.decode_art_image: load + resize, no
##      texture creation), dispatched for every queued face
##      up front, so decodes overlap travel instead of
##      punctuating it;
##   2. RENDER + APPLY run in the pipeline pass when the
##      decode has landed (or immediately, for cache hits
##      and styled faces), still through the factory's
##      serial capture queue - but the pass is a background
##      coroutine yielding a frame between faces, never a
##      call the travel path awaits.
## A picture may land late; the drum never waits for it.
##
## OPTIMIZE round: the GF18 stream-ahead shape is deleted -
## the pipeline is the GF17 shape above, whole: the drawn
## window only, the serial decode pump, applies capped at
## APPLY_CAP_PER_FRAME, and the GF17 settle guarantee
## dressing whatever travel left behind. The card a face
## belongs to keeps whatever honest texture it already
## wears (or the placeholder) until its staged face
## applies; the standing heal re-asks for anything the
## pipeline skipped, exactly as before. Under the NC
## PVLDS_GF16_NC=syncfill the pre-fix serial worker below
## runs instead and _set_centre's callers pay inline again,
## so the artstream smoke's travel legs fail by name.
func _request_window_fill() -> void:
	if debug_gf16_nc == "syncfill":
		if _window_fill_busy:
			_window_fill_dirty = true
			return
		_run_window_fill_sync()
		return
	if _art_pipe_busy:
		_window_fill_dirty = true
	_art_pipe_enqueue_window()
	if not _art_pipe_busy:
		_run_art_pipe()


## The pre-GRADFIX16 serial worker (the NC's restored shape,
## and nothing else's): a centre change's pass is awaited
## inline, face by face, decode + render on the caller's
## frames.
func _run_window_fill_sync() -> void:
	_window_fill_busy = true
	_window_fill_dirty = false
	var gen: int = _gen
	await _fill_window_faces_sync(gen)
	_window_fill_busy = false
	if _window_fill_dirty and gen == _gen:
		_run_window_fill_sync()


func _fill_window_faces_sync(gen: int) -> void:
	if _panel_window_lo < 0:
		return
	var order: Array[int] = _window_fill_order()
	for idx: int in order:
		if gen != _gen:
			return
		var cc: int = _grid_coord(idx).x
		if cc < _panel_window_lo or cc > _panel_window_hi:
			continue
		var gf16_probe_t: int = Time.get_ticks_usec() if TextureFactory.probe_enabled else 0
		_art_apply_branch = ""
		_art_apply_load_ms = 0.0
		_art_apply_render_ms = 0.0
		var tel_apply_t0: int = Time.get_ticks_usec()
		await _fill_one_face_sync(idx, gen)
		_art_event("apply", {
			"game": _visible_games[idx].game_id, "path": _face_path_memoized(_visible_games[idx]), "col": cc,
			"shot_origin": _visible_games[idx].shot_origin() if _visible_games[idx].is_shot_path(_face_path_memoized(_visible_games[idx])) else "",
			"centre_col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
			"gait": "stepped",
		"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
			"cost_ms": float(Time.get_ticks_usec() - tel_apply_t0) / 1000.0,
			"branch": _art_apply_branch, "load_ms": _art_apply_load_ms, "render_ms": _art_apply_render_ms,
			"cache": "hit" if _art_apply_branch == "facecache" else ("standing" if _art_apply_branch == "standing" else "render"), ## FACECACHE
			"via": "syncfill",
		})
		if TextureFactory.probe_enabled:
			var gf16_us: int = Time.get_ticks_usec() - gf16_probe_t
			TextureFactory.probe_note("fill_face_total", gf16_us)
			TextureFactory.probe_note("fill_col_%d" % cc, gf16_us)
	if gen == _gen:
		_on_window_fill_drained(gen)


## The window's face indices, centre column outward - the
## one fill order both workers walk.
func _window_fill_order() -> Array[int]:
	if _panel_window_lo < 0:
		return []
	return _fill_order_for(_panel_window_lo, _panel_window_hi)


## Face indices over an explicit column span, centre column
## outward (the window order's general shape).
func _fill_order_for(lo: int, hi: int) -> Array[int]:
	var order: Array[int] = []
	if lo < 0 or hi < lo or _centre_index < 0:
		return order
	var centre_col: int = _grid_coord(_centre_index).x
	var max_dist: int = maxi(centre_col - lo, hi - centre_col)
	for dist: int in range(0, max_dist + 1):
		for c: int in [centre_col - dist, centre_col + dist]:
			if dist == 0 and c != centre_col:
				continue
			if c < lo or c > hi:
				continue
			for row: int in range(3):
				var idx: int = _raw_index(c, row)
				if idx >= 0 and idx < _panels.size():
					order.append(idx)
	return order


## A fill pass resolved the standing window: the wall is
## ready, and Main's warmer is asked to bring the columns
## just outside the window forward (GRADFIX6's widened ask -
## on the staged path the extraction lookahead plus the
## pipeline's own queue are what stand between a fast sweep
## and a wall of title cards).
func _on_window_fill_drained(gen: int) -> void:
	if gen != _gen:
		return
	wall_ready = true
	var near: Array = []
	for c: int in [_panel_window_lo - 2, _panel_window_lo - 1, _panel_window_hi + 1, _panel_window_hi + 2]:
		if c < 0 or c >= _columns:
			continue
		for row: int in range(3):
			var idx: int = _raw_index(c, row)
			if idx >= 0 and idx < _visible_games.size():
				near.append(_visible_games[idx])
	if not near.is_empty():
		# The prefetch ask is a queue note: the signal runs
		# Main's handler and the warmer's prioritize
		# synchronously on this thread (the OPTIMIZE shape -
		# see ArtWarmer.prioritize), so emit_ms IS the ask's
		# main-thread cost, timed here beside the residency
		# the ask was made under.
		var tel_drain_t0: int = Time.get_ticks_usec()
		art_prefetch_requested.emit(near)
		var tel_rec: Dictionary = {
			"col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
			"nc_roll_dir": _nc_roll_dir, "games": near.size(),
			"first": (near[0] as GameEntry).game_id,
			"emit_ms": float(Time.get_ticks_usec() - tel_drain_t0) / 1000.0,
			"ask_ms": float(ArtWarmer.last_ask.get("ask_ms", -1.0)),
			"ask_mode": str(ArtWarmer.last_ask.get("mode", "")),
		}
		var gauge: Dictionary = residency_stats()
		for gkey: Variant in gauge.keys():
			tel_rec[gkey] = gauge[gkey]
		_art_event("prefetch", tel_rec)


## The face key a panel's fill would compute right now
## (game, its ready art file, favorite flag, PuP flag) -
## the one stamp the fill and the heal both judge by.
func _face_key_for(idx: int) -> String:
	if idx < 0 or idx >= _visible_games.size():
		return ""
	var game: GameEntry = _visible_games[idx]
	var art_file: String = _face_path_for(game)
	var fav: bool = _store != null and _store.is_favorite(game.game_id)
	var pup: bool = game.is_pup_tagged()
	return game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")


## Whether a panel's standing face is honestly the face its
## key asks for (the fill's own already-wearing test, asked
## without rendering anything).
func _face_is_standing(idx: int) -> bool:
	if idx < 0 or idx >= _visible_games.size():
		return true
	var game: GameEntry = _visible_games[idx]
	return str(_panel_face_key.get(game.game_id, "")) == _face_key_for(idx)


## The pipeline filter's key: _face_key_for with the art
## path read through the memo (see _face_path_memo). Only
## the enqueue filter and the pass's dispatch/landed checks
## use it - never the heal, never a fill.
func _face_key_for_memo(idx: int) -> String:
	if idx < 0 or idx >= _visible_games.size():
		return ""
	var game: GameEntry = _visible_games[idx]
	var art_file: String = _face_path_memoized(game)
	var fav: bool = _store != null and _store.is_favorite(game.game_id)
	var pup: bool = game.is_pup_tagged()
	return game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")


func _face_path_memoized(game: GameEntry) -> String:
	if _face_path_memo.has(game.game_id):
		return str(_face_path_memo[game.game_id])
	var p: String = _face_path_for(game)
	_face_path_memo[game.game_id] = p
	return p


## The filter's standing test (memoized path): a face whose
## memo key matches its stamp needs no pipeline work.
func _face_is_standing_memo(idx: int) -> bool:
	if idx < 0 or idx >= _visible_games.size():
		return true
	var game: GameEntry = _visible_games[idx]
	return str(_panel_face_key.get(game.game_id, "")) == _face_key_for_memo(idx)


## Enqueue the standing window's faces for the staged
## pipeline (centre-out). Called on every centre change:
## the queue is REBUILT from the standing window each time,
## holding ONLY the faces that are not honestly standing -
## a stamped face costs the rebuild one key comparison, so
## the pipeline's one-face-per-frame budget is spent on
## real work, never on re-walking the dressed window. A
## face the window left is dropped before it can spend a
## render. Background decodes for the first few queued
## faces dispatch here; the rest dispatch as the pass pops
## them (see _art_pipe_pass), so this call itself stays
## cheap on the travel path that calls it.
func _art_pipe_enqueue_window() -> void:
	var tel_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry: the enqueue's own cost, measured unconditionally
	var probe_t: int = Time.get_ticks_usec() if TextureFactory.probe_enabled else 0
	# COMPOSE-AHEAD: the direction witness. This enqueue runs
	# on every centre change, so the centre column's delta
	# across calls IS the travel direction (last nonzero wins).
	if _centre_index >= 0:
		var ca_col: int = _grid_coord(_centre_index).x
		if _ca_last_centre_col >= 0 and ca_col != _ca_last_centre_col:
			_travel_dir = 1 if ca_col > _ca_last_centre_col else -1
		_ca_last_centre_col = ca_col
	# OPTIMIZE: the queue is built over the DRAWN window only -
	# the GF17 shape. (GF18's stream window reached ahead of
	# the drum; stream-ahead is deleted with the SMOOTH gait.)
	var order: Array[int] = _window_fill_order()
	var tel_order_done: int = Time.get_ticks_usec()
	var needy: Array[int] = []
	var tel_filter_ms: float = 0.0
	var tel_filter_max_ms: float = 0.0
	var tel_filter_max_game: String = ""
	var tel_memo_miss: int = 0
	for idx: int in order:
		var tel_face_t0: int = Time.get_ticks_usec()
		var fgame: GameEntry = _visible_games[idx]
		if not _face_path_memo.has(fgame.game_id):
			tel_memo_miss += 1
		if not _face_is_standing_memo(idx):
			needy.append(idx)
		var tel_face_ms: float = float(Time.get_ticks_usec() - tel_face_t0) / 1000.0
		tel_filter_ms += tel_face_ms
		if tel_face_ms > tel_filter_max_ms:
			tel_filter_max_ms = tel_face_ms
			tel_filter_max_game = fgame.game_id
	_art_pipe_queue = needy
	# NEVERBLANK (the fix): cache-hit faces bind NOW, in
	# this call - the centre change's own stack, before the
	# pipeline's pass starts and before the next frame can
	# draw. A served face used to wait for the pass to
	# reach it, and while a composed render was in flight
	# the pass was suspended: a warm card entering the
	# window stood on the dark placeholder for the wait,
	# the field blink. Renders stay queued and capped
	# exactly as before; only the pointer swaps move up.
	var nb_swapped: int = 0
	if not needy.is_empty():
		var nb_rest: Array[int] = []
		for nidx: int in needy:
			if _nb_try_enqueue_swap(nidx):
				nb_swapped += 1
			else:
				nb_rest.append(nidx)
		needy = nb_rest
		_art_pipe_queue = needy
	if debug_nb_nc == "clearfirst":
		# NC (clearfirst): every cache-served face in the
		# window re-binds through the clear-first door on
		# every enqueue - the pre-law world where a served
		# face passes through the placeholder - so the
		# census's black-pane legs fail by name.
		for widx: int in order:
			_nb_try_enqueue_swap(widx)
	var tel_filter_done: int = Time.get_ticks_usec()
	# GRADFIX17 telemetry: the enqueue's own account - which
	# faces it found needy (identity = game + art file), on
	# which column, under which travel state, with the
	# sub-step costs and the residency gauge.
	var tel_faces: Array = []
	for nidx: int in needy:
		var ngame: GameEntry = _visible_games[nidx]
		tel_faces.append({"g": ngame.game_id, "p": _face_path_memoized(ngame)})
	var tel_faces_ms: float = float(Time.get_ticks_usec() - tel_filter_done) / 1000.0
	var tel_rec: Dictionary = {
		"col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
		"nc_roll_dir": _nc_roll_dir,
		"swing": _swing_active,
		"needy": needy.size(),
		"enqueue_swaps": nb_swapped, ## NEVERBLANK: faces bound synchronously at this enqueue
		"faces": tel_faces,
		"cost_ms": float(Time.get_ticks_usec() - tel_t0) / 1000.0,
		"order_ms": float(tel_order_done - tel_t0) / 1000.0,
		"filter_ms": tel_filter_ms,
		"filter_max_ms": tel_filter_max_ms,
		"filter_max_game": tel_filter_max_game,
		"memo_miss": tel_memo_miss,
		"faces_ms": tel_faces_ms,
	}
	var gauge: Dictionary = residency_stats()
	for gkey: Variant in gauge.keys():
		tel_rec[gkey] = gauge[gkey]
	_art_event("enqueue", tel_rec)
	var pre: Array[int] = []
	for i: int in range(mini(6, needy.size())):
		pre.append(needy[i])
	_art_pipe_dispatch_decodes(pre)
	if TextureFactory.probe_enabled:
		TextureFactory.probe_note("pipe_enqueue_window", Time.get_ticks_usec() - probe_t)


func _art_pipe_dispatch_decodes(idxs: Array[int]) -> void:
	for idx: int in idxs:
		if idx < 0 or idx >= _visible_games.size():
			continue
		var path: String = _face_path_memoized(_visible_games[idx])
		if path == "":
			continue
		if TextureFactory.art_decode_is_cached(path):
			continue
		_art_pipe_dispatch_one(path)


## Queue one art path for the background decode pump
## (deduplicated against queued / in-flight / landed /
## failed decodes, and against the standing decode cache's
## own hits at stage time). Starts the pump when it is idle.
func _art_pipe_dispatch_one(path: String) -> void:
	_art_decode_mutex.lock()
	var known: bool = _art_decode_pending.has(path) or _art_decoded_ready.has(path) or _art_decoded_failed.has(path)
	var start_pump: bool = false
	if not known:
		_art_decode_pending[path] = true
		_art_decode_queue.append(path)
		if _art_decode_workers < ART_DECODE_WORKERS:
			_art_decode_workers += 1
			_art_decode_pump_active = true
			start_pump = true
	_art_decode_mutex.unlock()
	if not known:
		_art_event("decode_queue", {"path": path, "col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1, "nc_roll_dir": _nc_roll_dir})
	if start_pump:
		WorkerThreadPool.add_task(Callable(self, "_art_decode_pump"))


## The background decode pump (ONE worker task,
## ART_DECODE_WORKERS = 1 - GF16's serial law, restored by
## the OPTIMIZE round): drains the decode queue - load +
## downscale into Images, handed back through the
## mutex-guarded dictionaries. No texture creation, no cache
## writes, no node access: everything a pump task touches is
## either its own local Image or the guarded dictionaries.
## (A task per face - the unbounded swarm - stays banned.)
func _art_decode_pump() -> void:
	while true:
		if _art_stopping:
			_art_decode_mutex.lock()
			_art_decode_workers -= 1
			_art_decode_pump_active = _art_decode_workers > 0
			_art_decode_mutex.unlock()
			return
		_art_decode_mutex.lock()
		if _art_decode_queue.is_empty():
			_art_decode_workers -= 1
			_art_decode_pump_active = _art_decode_workers > 0
			_art_decode_mutex.unlock()
			return
		var path: String = _art_decode_queue.pop_front()
		_art_decode_mutex.unlock()
		_art_event("decode_start", {"path": path, "thread": OS.get_thread_caller_id(), "wall_ms": Time.get_ticks_msec()})
		var tel_t0: int = Time.get_ticks_usec()
		var img: Image = TextureFactory.decode_art_image(path)
		_art_event("decode_end", {"path": path, "thread": OS.get_thread_caller_id(), "wall_ms": Time.get_ticks_msec(), "cost_ms": float(Time.get_ticks_usec() - tel_t0) / 1000.0, "ok": img != null})
		_art_decode_mutex.lock()
		_art_decode_pending.erase(path)
		if img != null:
			_art_decoded_ready[path] = img
		else:
			_art_decoded_failed[path] = true
		_art_decode_mutex.unlock()


## The staged pipeline pass: a deferred coroutine (started
## via call_deferred from _run_art_pipe, so it never runs
## inside a _set_centre call). It walks the queue one full
## face per frame at most (APPLY_CAP_PER_FRAME), applied by
## the same _fill_one_face_sync the serial worker uses, with
## _art_pipe_in_stage set so its decode branch consumes the
## staged result instead of paying a synchronous decode.
## This is the GF17 shape the OPTIMIZE round restores: no
## stream path, no travel budget apparatus - during travel
## the rate halves (one face per two frames) exactly as
## GF17 shipped, and the GF17 settle audit dresses whatever
## travel left behind. A face whose decode is still in
## flight is SKIPPED this pass - never waited on - and
## re-queued behind the rest; the pass ends only when the
## queue holds nothing but in-flight decodes, and even then
## it polls on its own frames until they land or the
## generation changes. The ONE exception is the
## debug_opt_nc="streamahead" seam: on travel frames it
## skips the yield entirely, draining applies inline as
## GF18 did, so the apply-cap leg fails by name.
func _run_art_pipe() -> void:
	_art_pipe_busy = true
	_window_fill_busy = true
	call_deferred("_art_pipe_pass")


## True when no pipeline pass is running and the decode
## pump has drained (quiescence - the smokes wait for this
## before quitting, and it is the honest test that staged
## work has fully landed or been dropped).
func art_pipeline_idle() -> bool:
	_art_decode_mutex.lock()
	var pump_active: bool = _art_decode_pump_active
	_art_decode_mutex.unlock()
	return not _art_pipe_busy and not pump_active


func _art_pipe_pass() -> void:
	var gen: int = _gen
	var deferred: Array[int] = []
	var swap_run: int = 0 ## FACECACHE: consecutive swap-applies served without a yield (bounded - see the yield below)
	while gen == _gen:
		while not _art_pipe_queue.is_empty():
			if gen != _gen:
				break
			var idx: int = _art_pipe_queue.pop_front()
			if idx < 0 or idx >= _panels.size() or idx >= _visible_games.size():
				continue
			var cc: int = _grid_coord(idx).x
			if cc < _panel_window_lo or cc > _panel_window_hi:
				continue # the drawn window left this card behind mid-pass
			var path: String = _face_path_memoized(_visible_games[idx])
			if path != "" and not TextureFactory.art_decode_is_cached(path):
				_art_decode_mutex.lock()
				var decode_landed: bool = _art_decoded_ready.has(path) or _art_decoded_failed.has(path)
				_art_decode_mutex.unlock()
				if not decode_landed:
					_art_pipe_dispatch_one(path)
					deferred.append(idx)
					continue
			var gf16_probe_t: int = Time.get_ticks_usec() if TextureFactory.probe_enabled else 0
			_art_pipe_in_stage = true
			_art_apply_branch = ""
			_art_apply_load_ms = 0.0
			_art_apply_render_ms = 0.0
			var tel_apply_t0: int = Time.get_ticks_usec()
			var travelling_now: bool = _swing_active or page_slide_active()
			await _fill_one_face_sync(idx, gen)
			_art_pipe_in_stage = false
			var was_swap: bool = _art_apply_branch == "facecache"
			if was_swap:
				_note_swap(travelling_now) ## FACECACHE: swaps ride their own account, never the render cap's
			else:
				_note_apply(travelling_now) ## OPTIMIZE: the apply-cap account
			_art_event("apply", {
				"game": _visible_games[idx].game_id, "path": path, "col": cc,
				"shot_origin": _visible_games[idx].shot_origin() if _visible_games[idx].is_shot_path(path) else "",
				"centre_col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
				"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
				"cost_ms": float(Time.get_ticks_usec() - tel_apply_t0) / 1000.0,
				"branch": _art_apply_branch, "load_ms": _art_apply_load_ms, "render_ms": _art_apply_render_ms,
				"cache": "hit" if was_swap else ("standing" if _art_apply_branch == "standing" else "render"), ## FACECACHE: hit = swap, render = a composed render, standing = already wearing it
				"via": "pipe",
			})
			if TextureFactory.probe_enabled:
				var gf16_us: int = Time.get_ticks_usec() - gf16_probe_t
				TextureFactory.probe_note("fill_face_total", gf16_us)
				TextureFactory.probe_note("fill_col_%d" % cc, gf16_us)
			if gen != _gen:
				break
			if debug_opt_nc == "streamahead" and travelling_now:
				continue ## NC seam: no yield on travel frames - applies drain inline, past the cap
			if was_swap:
				# FACECACHE: a swap is a pointer assignment
				# (~0.34 ms measured in GF18), not a render -
				# it does not spend the render cap's frame, so
				# a cached face lands inside the very step that
				# brought its card into the window. The run is
				# bounded so a queue of nothing but swaps still
				# yields once in a while.
				swap_run += 1
				if swap_run < 18:
					continue
			swap_run = 0
			await get_tree().process_frame # the cap: at most APPLY_CAP_PER_FRAME staged faces per frame, ever
			if travelling_now:
				# Travelling: halve the application rate -
				# one face per two frames (the GF17 shape).
				await get_tree().process_frame
		if gen != _gen:
			break
		if deferred.is_empty():
			break
		# Only in-flight decodes remain: poll on the
		# pipeline's own frames until they land.
		_art_pipe_queue = deferred
		deferred = []
		await get_tree().process_frame
	_art_pipe_busy = false
	_window_fill_busy = false
	if gen == _gen:
		_on_window_fill_drained(gen)
		if _window_fill_dirty:
			# A centre change landed while this pass ran:
			# one more pass for the window as it now stands.
			_window_fill_dirty = false
			_art_pipe_enqueue_window()
			_run_art_pipe()
		if not _art_pipe_busy:
			# COMPOSE-AHEAD: the window stands dressed and
			# the pipe is idle - spend the idle frames on
			# the columns the player is heading toward.
			_compose_ahead_kick()


## ------------------------------------------------------------
## COMPOSE-AHEAD (this round): the first-visit dress latency's
## cure. The profile (field telemetry-9 + the bench probe
## split) convicted the shape of the cost: a composed render
## is ~35 ms on the field rig and ~93% of it is two serialized
## frame waits through the factory's ONE shared viewport -
## the CPU phases are ~2 ms. A render cannot be made much
## cheaper; it can only be moved off the arrival moment. So:
## when the pipe drains and the wall is idle, compose the
## faces of the columns just outside the drawn window -
## COMPOSE_AHEAD_COLS beyond the edge in the travel direction,
## COMPOSE_BEHIND_COLS beyond the other edge - into the same
## composed-face cache, under the same key and the PHANTOMFIX
## provenance law. An arrival in that span is then a cache
## swap (~0.04 ms) instead of a render. The laws:
## - Window work owns the machine: the ahead pass checks for
##   pipe work before EVERY composition and stops; the next
##   drain re-kicks it with fresh geometry. Drum motion and
##   input never wait on it (the yield discipline is the
##   pipe's own: one render per frame, one per two while
##   travelling).
## - It never binds a panel and never stamps a face key: it
##   only puts composed textures in the cache. The settle
##   guarantee and the never-blank law are untouched - they
##   judge what stands, and ahead work changes only what the
##   cache holds before a face is ever asked for.
## - A failed capture puts NOTHING (the fill's own fallback
##   discipline, minus the panel): arrival then composes
##   exactly as it did before this round.
## - The composer keeps its timings in locals - never the
##   shared _art_apply_* wrap whose corruption minted the
##   phantom faces.
## The honest ceiling: a nonstop end-to-end tour outruns any
## finite margin; the win is normal travel - bursts, stops,
## reversals - arriving dressed.

## Kick the ahead pass if the room is in a state to spend
## idle frames (called from the pipe pass's drained tail).
func _compose_ahead_kick() -> void:
	if debug_compose_nc == "noahead":
		return ## NC seam (PVLDS_COMPOSE_NC=noahead): ahead composition never runs
	if _art_ahead_busy or _tournament:
		return
	if _panel_window_lo < 0 or _centre_index < 0:
		return
	_art_ahead_busy = true
	call_deferred("_art_ahead_pass")


## The ahead span's panel indices, nearest column first: the
## lead span (travel direction) in full, then the trail span.
func _compose_ahead_targets() -> Array[int]:
	var out: Array[int] = []
	if _panel_window_lo < 0 or _centre_index < 0:
		return out
	var dir: int = _travel_dir if _travel_dir != 0 else 1
	var cols: Array = []
	if dir > 0:
		for i: int in range(COMPOSE_AHEAD_COLS):
			cols.append(_panel_window_hi + 1 + i)
		for i: int in range(COMPOSE_BEHIND_COLS):
			cols.append(_panel_window_lo - 1 - i)
	else:
		for i: int in range(COMPOSE_AHEAD_COLS):
			cols.append(_panel_window_lo - 1 - i)
		for i: int in range(COMPOSE_BEHIND_COLS):
			cols.append(_panel_window_hi + 1 + i)
	for cv: Variant in cols:
		var c: int = int(cv)
		if c < 0 or c >= _columns:
			continue
		for row: int in range(3):
			var idx: int = _raw_index(c, row)
			if idx >= 0 and idx < _visible_games.size():
				out.append(idx)
	return out


## The ahead pass: compose the span, one face per iteration,
## strictly below window work in priority.
func _art_ahead_pass() -> void:
	var gen: int = _gen
	var centre_col0: int = _grid_coord(_centre_index).x if _centre_index >= 0 else -1
	var queue: Array[int] = _compose_ahead_targets()
	var deferred: Array[int] = []
	var pre: Array[int] = []
	for i: int in range(mini(6, queue.size())):
		pre.append(queue[i])
	_art_pipe_dispatch_decodes(pre)
	while gen == _gen:
		if _art_pipe_busy or not _art_pipe_queue.is_empty() or _window_fill_dirty:
			break # window work owns the machine; the next drain re-kicks
		if _centre_index < 0 or _grid_coord(_centre_index).x != centre_col0:
			break # geometry moved; the next drain re-kicks with a fresh span
		var idx: int = -1
		if not queue.is_empty():
			idx = queue.pop_front()
		elif not deferred.is_empty():
			queue = deferred
			deferred = []
			await get_tree().process_frame
			continue
		else:
			break
		if idx >= 0 and idx < _panels.size():
			# Revalidate at pop time, the pipe's own discipline
			# mirrored: the span was computed at kick time, and
			# a face the window has since claimed belongs to
			# the window's fill, not to idle work.
			var acc: int = _grid_coord(idx).x
			if acc >= _panel_window_lo and acc <= _panel_window_hi:
				continue
		var spent: int = await _compose_ahead_one(idx, gen, centre_col0)
		if spent < 0:
			deferred.append(idx) # its decode is still in flight - retry behind the rest
			continue
		if spent > 0:
			await get_tree().process_frame # the yield law: at most one ahead render per frame
			if _swing_active or page_slide_active():
				await get_tree().process_frame # travelling: one per two frames, the pipe's own rate
	_art_ahead_busy = false


## Compose ONE span face into the cache. Returns 1 when a
## render was spent, 0 when there was nothing to compose (or
## the art decode had failed - nothing is put either way),
## -1 when the face's decode is still in flight.
func _compose_ahead_one(idx: int, gen: int, centre_col0: int) -> int:
	if idx < 0 or idx >= _panels.size() or idx >= _visible_games.size():
		return 0
	if _tournament and idx < _tournament_rows.size() \
			and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
		return 0
	var game: GameEntry = _visible_games[idx]
	var art_file: String = _face_path_for(game)
	_face_path_memo[game.game_id] = art_file # a fresh probe, like every fill writes
	var fav: bool = _store != null and _store.is_favorite(game.game_id)
	var pup: bool = game.is_pup_tagged()
	var fkey: String = game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")
	var existing: Array = _face_cache_get(fkey)
	if not existing.is_empty() and _face_cache_serves(existing, art_file):
		return 0 # already composed under this key, provenance honest
	var tex: Texture2D = null
	var art_aspect: float = 0.0
	var branch: String = ""
	var load_ms: float = 0.0
	var render_ms: float = 0.0
	if art_file != "":
		var art_tex: Texture2D = null
		var tel_load_t0: int = Time.get_ticks_usec()
		_art_decode_mutex.lock()
		var staged_img: Image = _art_decoded_ready.get(art_file, null) as Image
		var staged_failed: bool = _art_decoded_failed.has(art_file)
		if staged_img != null:
			_art_decoded_ready.erase(art_file)
		if staged_failed:
			_art_decoded_failed.erase(art_file)
		_art_decode_mutex.unlock()
		if staged_img != null:
			branch = "staged"
			art_tex = TextureFactory.art_texture_from_decoded(art_file, staged_img)
		elif staged_failed:
			_ca_decode_failed += 1
			return 0 # nothing put: arrival composes exactly as it did before this round
		elif TextureFactory.art_decode_is_cached(art_file):
			branch = "decodecache"
			art_tex = TextureFactory.load_art_texture(art_file)
		else:
			_art_pipe_dispatch_one(art_file)
			return -1 # decode in flight - the pass retries behind the rest
		load_ms = float(Time.get_ticks_usec() - tel_load_t0) / 1000.0
		if art_tex == null:
			_ca_decode_failed += 1
			return 0
		art_aspect = float(art_tex.get_width()) / float(art_tex.get_height())
		var tel_render_t0: int = Time.get_ticks_usec()
		tex = await _factory.render_texture(RoomSpecs.art_spec(game, art_tex, _store, false), _panel_face_px)
		render_ms = float(Time.get_ticks_usec() - tel_render_t0) / 1000.0
		if gen != _gen:
			return 1 # a render was spent; its result belongs to a dead generation
		if tex == null or not _tex_is_real(tex):
			# The WART reality gate, the ahead shape: a failed
			# capture puts nothing (never a styled fallback
			# under the art key - that species is the phantom's).
			_ca_gate_dropped += 1
			return 1
	else:
		branch = "styled"
		var tel_styled_t0: int = Time.get_ticks_usec()
		tex = await _factory.render_texture(RoomSpecs.panel_spec(game, _store), _panel_face_px)
		render_ms = float(Time.get_ticks_usec() - tel_styled_t0) / 1000.0
		if gen != _gen:
			return 1
		if tex == null or not _tex_is_real(tex):
			_ca_gate_dropped += 1
			return 1
	# The render spanned real time, and the boot churn races
	# it both ways: a window fill for this face may have put
	# first (the cache serves - discard), or may still be in
	# flight while the seating moved the window over this
	# face or the centre moved on (the window owns the face
	# now, and its fill's put must be the one that stands -
	# discard). Either way the duplicate dies unnoted, so
	# the account never counts two renders for one face.
	var raced: Array = _face_cache_get(fkey)
	var face_col: int = _grid_coord(idx).x
	var claimed: bool = _panel_window_lo >= 0 and face_col >= _panel_window_lo and face_col <= _panel_window_hi
	var moved: bool = _centre_index < 0 or _grid_coord(_centre_index).x != centre_col0
	if claimed or moved or (not raced.is_empty() and _face_cache_serves(raced, art_file)):
		_ca_raced += 1
		return 1
	_fc_note_render(game.game_id, fkey)
	_face_cache_put(fkey, tex, art_aspect, art_file)
	_ca_composed += 1
	_art_event("apply", {
		"game": game.game_id, "path": art_file, "col": _grid_coord(idx).x,
		"shot_origin": game.shot_origin() if game.is_shot_path(art_file) else "",
		"centre_col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
		"branch": branch, "load_ms": load_ms, "render_ms": render_ms,
		"cache": "render", "via": "ahead",
	})
	return 1


## The ahead account for the smokes and the field: how much
## was composed ahead, how the standing span reads right now.
func compose_ahead_stats() -> Dictionary:
	var span: Array[int] = _compose_ahead_targets()
	var ready: int = 0
	for idx: int in span:
		var game: GameEntry = _visible_games[idx]
		var art_file: String = _face_path_memoized(game)
		var fav: bool = _store != null and _store.is_favorite(game.game_id)
		var pup: bool = game.is_pup_tagged()
		var fkey: String = game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")
		var ent: Array = _face_cache_get(fkey)
		if not ent.is_empty() and _face_cache_serves(ent, art_file):
			ready += 1
	return {
		"composed_total": _ca_composed,
		"gate_dropped": _ca_gate_dropped,
		"decode_failed": _ca_decode_failed,
		"raced": _ca_raced,
		"span_faces": span.size(),
		"span_ready": ready,
		"travel_dir": _travel_dir,
		"cap_faces": FACE_CACHE_MAX,
	}


## True when no ahead pass is running (the smokes' rest
## witness; the span's readiness is compose_ahead_stats').
func compose_ahead_idle() -> bool:
	return not _art_ahead_busy


## The fill path's face read (GRADFIX6 items 2+3): the
## READY probe - art that already sits on disk - never the
## paying read. A cold card dresses in its styled title
## card immediately and upgrades when the warmer lands the
## real thing (the panel heal watches for the key change);
## the old read extracted synchronously on this path, which
## is the convicted mechanism behind both the tournie
## first-entry freeze and the serial stall a fast sweep
## outruns. PVLDS_TOURN_NC=coldfill restores the paying
## read so the tournament smoke's first-entry legs can
## fail against it by name.
func _face_path_for(game: GameEntry) -> String:
	if OS.get_environment("PVLDS_TOURN_NC") == "coldfill":
		return game.face_path()
	return game.face_path_ready()


## The blank-face negative control's predicate (see
## _fill_one_face): PVLDS_GRADFIX6_NC=blackface with the
## target game in PVLDS_GF6_NC_TARGET restores the pre-fix
## accept-cache-stamp bookkeeping for that one game.
func _blackface_nc(game: GameEntry) -> bool:
	return OS.get_environment("PVLDS_GRADFIX6_NC") == "blackface" \
		and game.game_id == OS.get_environment("PVLDS_GF6_NC_TARGET")


## Re-derive one card's nameplate + Launch seat from its
## label's live AABB, with the seat's art aspect already
## standing (GRADFIX7 item 1): the plate law's top seat is
## gated on the face kind, and the standing derivation in
## _refresh_card_plate skips a card whose label AABB did not
## change - but the FACE under an unchanging label can change
## kind (a styled card upgrading to art), and a rebuild can
## reset the aspect under an unchanged face. Both paths that
## settle a face's kind - the full fill and the already-
## wearing early return - re-derive through here.
func _rederive_card_plate(idx: int, game: GameEntry) -> void:
	if idx < 0 or idx >= _panel_labels.size() or _panel_labels[idx] == null:
		return
	var fnodes: Dictionary = _panel_pool.get(game.game_id, {}) as Dictionary
	if fnodes.is_empty() or str(fnodes.get("mode", "")) != "card":
		return
	var fla: AABB = _panel_labels[idx].get_aabb()
	if fla.size.y <= 0.0:
		return
	fnodes["plate_basis_h"] = fla.size.y
	_apply_card_plate(fnodes, fla)


## One card's face: the author shot first (GameEntry's
## ranking), then the shipped fallback chain - rendered
## WITHOUT the art's baked name strip: the nameplate's plate
## + label is the card's name now (the DOME5 geometry put the
## title there), and a second name painted into the art would
## fight it. The favorite star stays inside the rendered
## face, exactly as the shipped art_spec draws it.
## The one-face fill entry every direct caller uses
## (refresh_shot_faces, the X-press re-render, the heal via
## the window worker). GRADFIX16: on the staged path a
## direct ask never pays inline either - the face joins the
## pipeline's queue (at the front: it was asked for by name)
## and lands when the pipeline reaches it, a frame or two
## later. The NC's syncfill path, and the pipeline's own
## stage step, call _fill_one_face_sync directly.
func _fill_one_face(idx: int, gen: int) -> void:
	# PHANTOMFIX Layer 3: a direct ask ALWAYS queues - the
	# old in-stage shortcut ran the fill re-entrantly inside
	# the pipe's own stage step, where its bookkeeping (the
	# shared apply-branch string, the unwrapped cache put)
	# corrupted the stage fill it interrupted. The phantom
	# NC restores the shortcut verbatim.
	if debug_gf16_nc == "syncfill" or (_art_pipe_in_stage and debug_phantom_nc == "phantom"):
		await _fill_one_face_sync(idx, gen)
		return
	# GRADFIX17 telemetry: a direct ask (shot landing, X-press
	# re-render, the heal's window worker) joins the queue.
	if idx >= 0 and idx < _visible_games.size():
		_art_event("fill_direct", {
			"game": _visible_games[idx].game_id, "col": _grid_coord(idx).x,
			"gait": "stepped",
		"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
		})
	if idx < 0 or idx >= _panels.size():
		return
	if not _art_pipe_queue.has(idx):
		_art_pipe_queue.push_front(idx)
		_art_pipe_dispatch_decodes([idx])
	if not _art_pipe_busy:
		_run_art_pipe()


func _fill_one_face_sync(idx: int, gen: int) -> void:
	if idx < 0 or idx >= _panels.size() or idx >= _visible_games.size():
		return
	if _tournament and idx < _tournament_rows.size() \
			and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
		return # the state panel wears its board face (see _fill_tournament_state_faces), never a card face
	var game: GameEntry = _visible_games[idx]
	var quad: ClickableQuad = _panels[idx]
	var art_file: String = _face_path_for(game)
	_face_path_memo[game.game_id] = art_file # every fill refreshes the pipeline filter's memo from its own fresh probe
	var fav: bool = _store != null and _store.is_favorite(game.game_id)
	var pup: bool = game.is_pup_tagged()
	var fkey: String = game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")
	if str(_panel_face_key.get(game.game_id, "")) == fkey:
		# PHANTOMFIX Layer 1: the stamp alone no longer
		# vouches for the face - a styled fallback cached
		# under the art key stamps exactly this key. The
		# standing return stands only when the cache holds
		# no entry for the key (the panel still wears the
		# texture the stamp names; the entry was evicted)
		# or the entry's provenance is this key's art path.
		# An entry that does not serve means the stamp is
		# lying: fall through to a full fill.
		var standing_face: Array = _face_cache_get(fkey)
		if standing_face.is_empty() or _face_cache_serves(standing_face, art_file):
			_art_apply_branch = "standing" ## GRADFIX17 telemetry (read by the caller's apply wrap)
			# Already wearing exactly this face - but a rebuild
			# since the fill reset this seat's art aspect to 0
			# and re-derived its plate under the styled law, so
			# an art card can be standing with the wrong Launch
			# seat (and a lying aspect) under an honest face.
			# Restore the aspect from the face cache's own record
			# and re-derive the plate before returning.
			if not standing_face.is_empty():
				_panel_art_aspect[idx] = float(standing_face[1])
			_rederive_card_plate(idx, game)
			return
	var tex: Texture2D = null
	var art_aspect: float = 0.0
	var from_art: bool = false
	var cached_face: Array = _face_cache_get(fkey)
	if not cached_face.is_empty() and not _face_cache_serves(cached_face, art_file):
		# PHANTOMFIX Layer 1: the entry's provenance is not
		# this key's art (a styled fallback cached under the
		# art key by a failed art attempt) - it must not
		# serve. Drop it when its texture is unbound; when
		# bound the eviction defers and the genuine render
		# below replaces the entry with its own put.
		_face_cache_evict(fkey)
		cached_face = []
	if not cached_face.is_empty():
		tex = cached_face[0] as Texture2D
		art_aspect = float(cached_face[1])
		from_art = art_aspect > 0.0
		_art_apply_branch = "facecache" ## GRADFIX17 telemetry
		_fc_note_swap() ## FACECACHE: the cache served this face - a pointer swap, no render, no decode
	else:
		if art_file != "":
			var art_tex: Texture2D = null
			var tel_load_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry
			if _art_pipe_in_stage:
				# GRADFIX16 staged decode: consume the
				# background decode's Image (texture
				# creation only - the ~2 ms tail), or the
				# decode cache's standing texture. A decode
				# that failed in the background falls
				# through with art_tex null, exactly as a
				# synchronous load failure did.
				_art_decode_mutex.lock()
				var staged_img: Image = _art_decoded_ready.get(art_file, null) as Image
				var staged_failed: bool = _art_decoded_failed.has(art_file)
				if staged_img != null:
					_art_decoded_ready.erase(art_file)
				if staged_failed:
					_art_decoded_failed.erase(art_file)
				_art_decode_mutex.unlock()
				if staged_img != null:
					_art_apply_branch = "staged" ## GRADFIX17 telemetry
					art_tex = TextureFactory.art_texture_from_decoded(art_file, staged_img)
				elif not staged_failed and TextureFactory.art_decode_is_cached(art_file):
					_art_apply_branch = "decodecache" ## GRADFIX17 telemetry
					art_tex = TextureFactory.load_art_texture(art_file)
			else:
				_art_apply_branch = "syncload" ## GRADFIX17 telemetry
				art_tex = TextureFactory.load_art_texture(art_file)
			_art_apply_load_ms = float(Time.get_ticks_usec() - tel_load_t0) / 1000.0 ## GRADFIX17 telemetry
			if art_tex != null:
				art_aspect = float(art_tex.get_width()) / float(art_tex.get_height())
				var tel_render_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry
				tex = await _factory.render_texture(RoomSpecs.art_spec(game, art_tex, _store, false), _panel_face_px)
				_art_apply_render_ms = float(Time.get_ticks_usec() - tel_render_t0) / 1000.0 ## GRADFIX17 telemetry
				from_art = tex != null
				if from_art and _blackface_nc(game):
					# NC (PVLDS_GRADFIX6_NC=blackface, target in
					# PVLDS_GF6_NC_TARGET): the pre-GRADFIX6
					# bookkeeping restored for one named game -
					# the failed capture's dark solid accepted
					# as its face, cached and stamped below, so
					# the sweep smoke's dwell leg fails by name.
					tex = TextureFactory.make_solid(Color(0.08, 0.08, 0.12))
				elif from_art and not _tex_is_real(tex):
					# GRADFIX6 item 2 (the convicted blank-face
					# mechanism): a failed factory capture comes
					# back as a dark fallback solid, and the old
					# code cached and key-stamped it as the
					# card's art face - black forever. It is not
					# a face: never cache it, never stamp it.
					# Fall through to the styled title card; the
					# panel heal re-tries the art render.
					tex = null
					from_art = false
		if tex == null:
			_art_apply_branch = "styled" if _art_apply_branch == "" else _art_apply_branch + "+styled" ## GRADFIX17 telemetry
			var tel_styled_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry
			tex = await _factory.render_texture(RoomSpecs.panel_spec(game, _store), _panel_face_px)
			_art_apply_render_ms += float(Time.get_ticks_usec() - tel_styled_t0) / 1000.0 ## GRADFIX17 telemetry
			from_art = false
		if gen != _gen:
			return
		if tex != null and (_tex_is_real(tex) or _blackface_nc(game)):
			_fc_note_render(game.game_id, fkey) ## FACECACHE: a composed render served - the count the retention law judges
			_face_cache_put(fkey, tex, art_aspect if from_art else 0.0, art_file if from_art else "")
		elif tex != null:
			# The styled card's own capture failed too: stamp
			# nothing, cache nothing - the placeholder stands
			# and the heal retries (bounded per face key).
			tex = null
	if tex == null:
		return
	_sc_face_assigns += 1 ## OPTIMIZE standing-cost audit (observation only)
	if quad.current_texture() == tex:
		# OPTIMIZE standing-cost cut: a no-op face swap (the
		# new texture IS the standing one) is counted and
		# SKIPPED - the assignment and its renderer write
		# never happen.
		_sc_noop_face_swaps += 1
	else:
		_nb_bind_face(quad, tex, "swap" if _art_apply_branch == "facecache" else "render") ## NEVERBLANK: the one bind door
	_panel_face_key[game.game_id] = fkey
	# The nameplate shows only over an art face: a generated
	# title card carries its own title, and a title under a
	# title would double it.
	if idx < _panel_plates.size() and _panel_plates[idx] != null:
		_panel_plates[idx].visible = from_art
		_panel_labels[idx].visible = from_art
		if OS.get_environment("PVLDS_GRAD_NC") == "noplate":
			# NC seam (graduation smoke): the nameplate
			# removed - the nameplate legs must convict it.
			_panel_plates[idx].visible = false
		if idx == _flip_idx and _flip_t >= 0.5:
			# A face landing under a standing back: the
			# derivation above speaks for the FRONT - the
			# flip's side swap re-asserts the back's claim.
			_apply_flip_side(idx, true)
	# The face has landed. Two power-on debts settle here
	# (the boot fault's halves): a performance that skipped
	# this card for wearing the placeholder retries now - its
	# missed mark clears and its settle clock primes, so the
	# cascade starts on the real face with no input; and a
	# performance already standing on this card bound the
	# face it wore then, so it restarts on the face the card
	# wears now (the candidate logic re-picks the same card -
	# focus never moved).
	if quad == _power_missed:
		_power_missed = null
		if _power_candidate == quad:
			_power_candidate_t = POWER_SETTLE_SEC
	if quad == _power_panel:
		_restore_power("face_arrived")
	_panel_art_aspect[idx] = art_aspect if from_art else 0.0
	_rederive_card_plate(idx, game)
	if _panel_pop[idx] > 0.0:
		# The card is already popped (focus rested while its
		# face streamed in): force the pop transform to
		# re-apply next frame.
		_panel_pop_applied[idx] = -1.0
		_pop_awake = true ## OPTIMIZE standing-cost cut: a face landing under a popped card wakes the pop loop
	# GRADFIX13 (item 2): this tail used to dress the card's
	# Launch plinth (LAUNCH, or FAILED for the last failed
	# game - the two cached button faces). The plinth is
	# stripped; under the plinth NC the minted button is
	# dressed exactly as before, tournament visibility law
	# included (a challenge card he does not own carries no
	# Launch: there is nothing on it to press - the
	# pick-side of the same law lives in _refresh_window
	# via _tournament_launchable).
	if idx < _panel_launches.size() and _panel_launches[idx] != null:
		var failed: bool = game.game_id == _failed_game_id
		var blabel: String = "FAILED" if failed else "LAUNCH"
		var baccent: bool = not failed
		var bkey: String = blabel + "|" + ("a" if baccent else "p")
		var ltex: Texture2D = _btn_tex_cache.get(bkey) as Texture2D
		if ltex == null:
			ltex = await _factory.render_texture(
				RoomSpecs.button_spec(blabel, baccent), Vector2i(512, 164))
			if gen != _gen:
				return
			if ltex != null:
				_btn_tex_cache[bkey] = ltex
		_panel_launches[idx].set_texture(ltex)
		if _tournament:
			var launchable: bool = _tournament_launchable(idx)
			_panel_launches[idx].visible = launchable
			_panel_launches[idx].pick_enabled = launchable and _mode == "wall"
	# The power-on's subject warms through the warmer now,
	# not here (GRADFIX6 items 2+3): this tail used to call
	# backglass_face_path() - a synchronous extraction on
	# the fill path, one of the convicted first-entry
	# blocks. _prepare_power_subject reads the ready probe
	# and asks the warmer forward when it is cold.


## A shot landed for a game (Main's ShotFetcher): if its card
## stands in the standing view and inside the window, its
## face re-fills - the face key changed under it, so the card
## swaps the fallback it wore for the author shot.
func refresh_shot_faces(game: GameEntry) -> void:
	if game == null:
		return
	_face_path_memo.erase(game.game_id) # the shot changed this game's art path; the fill below re-memoizes it fresh
	var idx: int = _visible_games.find(game)
	if idx < 0 or idx >= _panels.size():
		return
	if _panel_window_lo < 0:
		return
	var c: int = _grid_coord(idx).x
	if c < _panel_window_lo or c > _panel_window_hi:
		return
	_fill_one_face(idx, _gen)


## The panel-face heal (GRADFIX6 item 2 - the GRADFIX4
## companions' heal discipline, extended to the cards
## themselves, which the original heal left out): once per
## BOARD_TEX_RETRY_MS, walk the standing window's panels
## and re-issue the fill for any face that is not honestly
## standing:
##   - the face key the ready probe computes differs from
##     the stamped key (the warmer landed the extraction,
##     or the shot arrived without a refresh hook) - refill
##     (an upgrade, never charged against the retry budget);
##   - the standing texture is unreal (the placeholder, or
##     a fallback solid that got applied before the reality
##     gate existed in a render race) - restamp and refill,
##     bounded per face key;
##   - the card wears its styled card over art that was
##     ready all along but whose RENDER captured empty -
##     evict the cached styled face and retry the art
##     render, bounded per face key (BOARD_TEX_MAX_RETRIES)
##     so a persistently failing capture settles on the
##     styled card instead of spinning.
## The heal NEVER renders itself: the factory is a serial
## resource driven by the window-fill worker, and a second
## concurrent fill source can starve the worker's pass (the
## first grad run of this round wedged exactly there -
## three faces never filled). The heal only clears the
## bookkeeping that stands in the worker's way and asks
## for a pass; the worker's key checks make the pass cheap
## for every honest face.
func _heal_panel_faces() -> void:
	if _panel_window_lo < 0 or _panels.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _face_heal_msec < BOARD_TEX_RETRY_MS:
		return
	_face_heal_msec = now
	var tel_heal_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry: the sweep's own cost + findings
	var tel_mismatch: Array = []
	var tel_unreal: Array = []
	var needs_pass: bool = false
	for idx: int in range(_panels.size()):
		if idx >= _visible_games.size():
			continue
		var cc: int = _grid_coord(idx).x
		if cc < _panel_window_lo or cc > _panel_window_hi:
			continue
		if _tournament and idx < _tournament_rows.size() \
				and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
			continue # state panels wear board faces, not card faces
		var game: GameEntry = _visible_games[idx]
		var quad: ClickableQuad = _panels[idx]
		var tex: Texture2D = quad.current_texture()
		var stamped: String = str(_panel_face_key.get(game.game_id, ""))
		var art_file: String = _face_path_for(game)
		var fav: bool = _store != null and _store.is_favorite(game.game_id)
		var pup: bool = game.is_pup_tagged()
		var want_key: String = game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")
		if stamped != want_key:
			# GRADFIX17 (item 1): correct the pipeline
			# filter's memo from this fresh probe before
			# asking for the pass. The memo is only ever
			# rewritten by a fill, and the enqueue filter
			# spends the pass budget by the memo - so a
			# face whose art landed after its memo was
			# written (the extraction chain, a pair's On
			# half, a landed shot the refresh hook missed)
			# was judged "standing" by the filter forever:
			# the heal asked, the pipeline refused, and
			# the card stood dark for good. With the memo
			# corrected, the pass the heal asks for below
			# can finally spend itself on this face.
			if debug_gf17_nc != "noguarantee":
				_face_path_memo[game.game_id] = art_file
			needs_pass = true # an upgrade is ready (or the face never landed); never budget-charged
			tel_mismatch.append(game.game_id) ## GRADFIX17 telemetry
		elif tex == null or tex == _placeholder_tex or not _tex_is_real(tex):
			tel_unreal.append(game.game_id) ## GRADFIX17 telemetry
			# Stamped as this face, yet not honestly standing
			# (a rebuild re-dressed the pooled panel, a race):
			# clear the stamp so the worker re-renders it,
			# bounded per face key.
			var rkey: String = game.game_id + "|" + want_key
			var spent: int = int(_face_heal_retries.get(rkey, 0))
			if spent < BOARD_TEX_MAX_RETRIES:
				_face_heal_retries[rkey] = spent + 1
				_panel_face_key.erase(game.game_id)
				needs_pass = true
		elif art_file != "" and _panel_art_aspect[idx] <= 0.0:
			# The styled card stands over ready art: its art
			# render captured empty at fill time. Evict the
			# cached styled face and retry the art render,
			# bounded; then the styled card stands for good.
			var rkey: String = game.game_id + "|" + art_file
			var spent: int = int(_face_heal_retries.get(rkey, 0))
			if spent < BOARD_TEX_MAX_RETRIES:
				_face_heal_retries[rkey] = spent + 1
				_face_cache_evict(stamped)
				_panel_face_key.erase(game.game_id)
				needs_pass = true
	# GRADFIX17 telemetry: every sweep that asks for a pass,
	# and any sweep whose own probe walk costs real time -
	# the heal reads fresh filesystem probes for all 63
	# window faces, so its cost belongs in the log by name.
	var tel_heal_ms: float = float(Time.get_ticks_usec() - tel_heal_t0) / 1000.0
	if needs_pass or tel_heal_ms >= 8.0:
		_art_event("heal", {
			"col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1,
			"gait": "stepped",
		"nc_roll_dir": _nc_roll_dir, "swing": _swing_active,
			"needs_pass": needs_pass, "cost_ms": tel_heal_ms,
			"mismatch": tel_mismatch, "unreal": tel_unreal,
		})
	if needs_pass:
		_request_window_fill()


## The landing guarantee's settle audit (GRADFIX17 item 1):
## armed the frame travel ends (see _update_pop), it sweeps
## the standing window on the heal's cadence and re-issues
## every face that is not honestly standing, until a fresh
## census reads zero missing or the heal's own bounds say
## the face has had its retries. Per face it applies the
## heal's three tests with ONE addition - the memo
## correction that is this round's conviction: the pipeline
## filter judges by _face_path_memo, which a fill alone
## rewrites, so any face whose ready path changed after its
## memo was written (extraction landed, pair On appeared,
## shot arrived off-window) was permanently filtered out of
## every pass the heal requested. The audit (and the heal's
## first branch, above) rewrites the memo from the fresh
## probe, so the requested pass can reach the face. Bounds,
## consonant with the heal laws: key-changed re-issues are
## never budget-charged (an upgrade, not a retry); unreal
## stamps and styled-over-art retries spend the same
## per-key BOARD_TEX_MAX_RETRIES budget the heal spends;
## the audit itself disarms after GF17_AUDIT_MAX_RUNS sweeps
## on one settle, so a persistently failing capture settles
## on its styled card instead of spinning. The fallback
## solid is never stamped as a real face (the fill's
## reality gate is untouched), and nothing here runs while
## the drum travels - the GF16 travel law stands.
const GF17_AUDIT_MAX_RUNS: int = 40

func _guarantee_audit() -> void:
	if debug_gf17_nc == "noguarantee":
		_gf17_audit_armed = false
		return
	if _panel_window_lo < 0 or _panels.is_empty():
		_gf17_audit_armed = false
		return
	var now: int = Time.get_ticks_msec()
	if now - _gf17_audit_msec < BOARD_TEX_RETRY_MS:
		return
	_gf17_audit_msec = now
	_gf17_audit_runs += 1
	var missing: int = 0
	var actionable: bool = false
	var needs_pass: bool = false
	for idx: int in range(_panels.size()):
		if idx >= _visible_games.size():
			continue
		var cc: int = _grid_coord(idx).x
		if cc < _panel_window_lo or cc > _panel_window_hi:
			continue
		if _tournament and idx < _tournament_rows.size() \
				and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
			continue # state panels wear board faces, not card faces
		var game: GameEntry = _visible_games[idx]
		var quad: ClickableQuad = _panels[idx]
		var tex: Texture2D = quad.current_texture()
		var stamped: String = str(_panel_face_key.get(game.game_id, ""))
		var art_file: String = _face_path_for(game)
		var fav: bool = _store != null and _store.is_favorite(game.game_id)
		var pup: bool = game.is_pup_tagged()
		var want_key: String = game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")
		if stamped != want_key:
			missing += 1
			actionable = true
			_face_path_memo[game.game_id] = art_file # the correction (see above)
			needs_pass = true # an upgrade is ready; never budget-charged
		elif tex == null or tex == _placeholder_tex or not _tex_is_real(tex):
			missing += 1
			var rkey: String = game.game_id + "|" + want_key
			var spent: int = int(_face_heal_retries.get(rkey, 0))
			if spent < BOARD_TEX_MAX_RETRIES:
				actionable = true
				_face_heal_retries[rkey] = spent + 1
				_panel_face_key.erase(game.game_id)
				_face_path_memo[game.game_id] = art_file
				needs_pass = true
		elif art_file != "" and _panel_art_aspect[idx] <= 0.0:
			missing += 1
			var rkey: String = game.game_id + "|" + art_file
			var spent: int = int(_face_heal_retries.get(rkey, 0))
			if spent < BOARD_TEX_MAX_RETRIES:
				actionable = true
				_face_heal_retries[rkey] = spent + 1
				_face_cache_evict(stamped)
				_panel_face_key.erase(game.game_id)
				_face_path_memo[game.game_id] = art_file
				needs_pass = true
	if needs_pass:
		_request_window_fill()
	if missing == 0 or not actionable or _gf17_audit_runs >= GF17_AUDIT_MAX_RUNS:
		_gf17_audit_armed = false
		_gf17_audit_runs = 0
		_on_settle_audit_complete(missing)


## OPTIMIZE round: a settle audit completed (census zero, or
## its budget spent). Two things land here, in order: the
## settle_audit telemetry record - dress_ms is the audit's
## own dress latency, travel end -> census zero (the measure
## GF19 kept as costume_dress; -1 when the budget spent with
## faces still missing) - carrying the residency the settle
## landed under; and, on a clean census only, the eviction
## account. FACECACHE: the account no longer evicts by
## distance (see _evict_after_settle); under the
## debug_opt_nc="evictvis" seam it instead eats the
## window's faces, so the landing census that follows in
## the same settle reads them missing.
func _on_settle_audit_complete(missing: int) -> void:
	var dress_ms: float = -1.0
	if missing == 0 and _settle_travel_end_msec > 0:
		dress_ms = float(Time.get_ticks_msec() - _settle_travel_end_msec)
	var gauge: Dictionary = residency_stats()
	var fields: Dictionary = _telemetry_context()
	fields["event"] = "settle_audit"
	fields["dress_ms"] = dress_ms
	fields["missing"] = missing
	fields["resident_faces"] = int(gauge["resident_faces"])
	fields["resident_bytes"] = int(gauge["resident_bytes"])
	_telemetry_record("settle_audit", fields)
	_settle_travel_end_msec = 0
	if missing == 0 or debug_opt_nc == "evictvis":
		_evict_after_settle()


## FACECACHE round: the eviction pass, reunited. The
## OPTIMIZE round's pass dropped every resident face
## outside the drawn window +/- EVICT_MARGIN_COLS columns
## and cleared those panels' stamps and textures with it -
## distance eviction, and the convicted half of the field
## log's re-render churn (the OPTIMIZE field session
## evicted ~480 faces across 31 settles while residency
## never once reached the 108 cap, so every scroll away
## and back was a fresh ~33 ms composed render and the
## cache branch never fired once in 1,297 applies). That
## law is DELETED. A card leaving the window now drops
## nothing: not its composed texture, not its panel's
## dress, not its stamp, not its decoded image. The only
## evictions left in the building are cap pressure (the
## LRU inside _face_cache_put) and the heal's single-key
## force-evict on its art retry (whose retry render then
## replaces the entry - the cache lives BELOW the GF17
## guarantee, never above it). What remains here is the
## settle-time ACCOUNT: the evict telemetry record still
## lands on a clean census, reporting the cap drops since
## the last record and the residency the settle landed
## under, so the log keeps the shape its readers know.
## The debug_opt_nc="evictvis" seam keeps its meaning by
## restoring the offence against the standing window
## itself: window faces are dropped from the cache and
## their panels cleared, so the landing census that
## follows in the same settle reads them missing and the
## leg fails by name.
func _evict_after_settle() -> void:
	var evicted: int = 0
	if debug_opt_nc == "evictvis":
		if _panel_window_lo < 0:
			return
		for idx: int in range(_panels.size()):
			if idx >= _visible_games.size():
				continue
			var cc: int = _grid_coord(idx).x
			if cc < _panel_window_lo or cc > _panel_window_hi:
				continue
			if _tournament and idx < _tournament_rows.size() \
					and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
				continue # state panels wear board faces, not card faces
			var game: GameEntry = _visible_games[idx]
			var stamped: String = str(_panel_face_key.get(game.game_id, ""))
			if stamped == "":
				continue
			_face_cache_evict(stamped)
			_panel_face_key.erase(game.game_id)
			_face_path_memo.erase(game.game_id)
			evicted += 1
			if _panels[idx].current_texture() != _placeholder_tex:
				_panels[idx].set_texture(_placeholder_tex)
			if idx < _panel_art_aspect.size():
				_panel_art_aspect[idx] = 0.0
		_evicted_total += evicted
		_fc_evict_reported = _evicted_total
	else:
		evicted = _evicted_total - _fc_evict_reported
		_fc_evict_reported = _evicted_total
	_fc_sync_footer()
	var gauge2: Dictionary = residency_stats()
	var fields: Dictionary = _telemetry_context()
	fields["event"] = "evict"
	fields["evicted_faces"] = evicted
	fields["resident_faces"] = int(gauge2["resident_faces"])
	fields["resident_bytes"] = int(gauge2["resident_bytes"])
	_telemetry_record("evict", fields)


## Per-panel face state for the smokes (the sweep driver's
## instrumentation): for every panel in the standing
## window, what its face honestly is right now.
func face_state() -> Array:
	var out: Array = []
	if _panel_window_lo < 0:
		return out
	for idx: int in range(_panels.size()):
		if idx >= _visible_games.size():
			continue
		var cc: int = _grid_coord(idx).x
		if cc < _panel_window_lo or cc > _panel_window_hi:
			continue
		var quad: ClickableQuad = _panels[idx]
		var tex: Texture2D = quad.current_texture()
		out.append({
			"idx": idx,
			"game_id": _visible_games[idx].game_id,
			"title": _visible_games[idx].title,
			"col": cc,
			"key_stamped": _panel_face_key.has(_visible_games[idx].game_id),
			"nc_blanked": _nc_costume_saved.has(idx), ## debug_opt_nc="costume" seam only: this face currently wears the blank swap
			"tex_w": tex.get_width() if tex != null else 0,
			"is_placeholder": tex != null and tex == _placeholder_tex,
			"is_unreal": tex == null or tex == _placeholder_tex or not _tex_is_real(tex),
			"from_art": _panel_art_aspect[idx] > 0.0 if idx < _panel_art_aspect.size() else false,
		})
	return out


## GRADFIX17 (item 1) harness census: for every panel in the
## standing window, whether its face is honestly landed, judged
## by a FRESH probe (the heal's read - never the pipeline's
## memo): a face counts missing when its texture is not real,
## when the fresh face key differs from the stamped key (art
## became ready after the stamp - an upgrade owed), or when
## ready art exists but the standing face is the styled card
## (its art render never landed). A game with no ready art
## whose styled card stands honestly is NOT missing. Returns
## {"total": int, "missing": Array[String] of titles}.
func landing_census() -> Dictionary:
	var missing: Array[String] = []
	var total: int = 0
	var streamed: int = 0 ## OPTIMIZE: stream-ahead is deleted; the key stands at 0 for census readers
	if _panel_window_lo < 0:
		return {"total": 0, "missing": missing, "streamed": 0}
	for idx: int in range(_panels.size()):
		if idx >= _visible_games.size():
			continue
		var cc: int = _grid_coord(idx).x
		if cc < _panel_window_lo or cc > _panel_window_hi:
			continue
		if _tournament and idx < _tournament_rows.size() \
				and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
			continue # state panels wear board faces, not card faces
		total += 1
		var game: GameEntry = _visible_games[idx]
		var quad: ClickableQuad = _panels[idx]
		var tex: Texture2D = quad.current_texture()
		var fresh_key: String = _face_key_for(idx)
		var stamped: String = str(_panel_face_key.get(game.game_id, ""))
		var art_ready: bool = fresh_key.split("|").size() > 1 and fresh_key.split("|")[1] != ""
		var from_art: bool = idx < _panel_art_aspect.size() and _panel_art_aspect[idx] > 0.0
		if tex == null or tex == _placeholder_tex or not _tex_is_real(tex):
			missing.append(game.title)
		elif stamped != fresh_key:
			missing.append(game.title)
		elif art_ready and not from_art:
			missing.append(game.title)
	return {"total": total, "missing": missing, "streamed": streamed}


## The state row's fill (the Tournament redesign): when the
## view is a single state panel - no key, a failed fetch, no
## live challenges - that panel wears the state face at the
## board's size. Challenge panels are cards now and dress
## through _fill_one_face; a challenge's scoreboard stands
## on its card's back (the flip - see _render_card_back).
func _fill_tournament_state_faces(gen: int) -> void:
	for i: int in range(_panels.size()):
		var row: Dictionary = _tournament_rows[i]
		if str(row.get("kind", "")) != "state":
			continue
		var quad: ClickableQuad = _panels[i]
		var spec: Dictionary = RoomSpecs.tournament_state_spec(row.get("lines", []))
		var tex: Texture2D = await _factory.render_texture(spec, RoomSpecs.board_face_px())
		if gen != _gen:
			return
		# GRADFIX15 (item 1): the state face is a board face -
		# only a real capture stamps; a fallback landing leaves
		# the panel's clear texture standing (invisible).
		if _tex_is_real(tex):
			quad.set_texture(tex)
		_panel_art_aspect[i] = 0.0
		if i < _panel_launches.size() and _panel_launches[i] != null:
			var lq: ClickableQuad = _panel_launches[i]
			var owned: bool = str(row.get("kind", "")) == "challenge" and bool(row.get("owned", false))
			lq.visible = owned
			lq.pick_enabled = owned and _mode == "wall"
			if owned:
				var ltex: Texture2D = _btn_tex_cache.get("LAUNCH|a") as Texture2D
				if ltex == null:
					ltex = await _factory.render_texture(
						RoomSpecs.button_spec("LAUNCH", true), Vector2i(512, 164))
					if gen != _gen:
						return
					if ltex != null:
						_btn_tex_cache["LAUNCH|a"] = ltex
				lq.set_texture(ltex)


## Smoke support (the tournament layout legs): render one
## board spec fresh and report its layout in both spaces -
## the face's own row/footer rects (face pixels, from
## CardFace's measured controls) and the same rects converted
## into panel space, alongside the Launch button's panel-
## space rect, so a leg can assert the button and the text
## never share ground. Panel space: metres, origin at the
## panel centre, +x right, +y up, Rect2 position = min corner.
func board_layout_probe(spec: Dictionary) -> Dictionary:
	var tex: Texture2D = await _factory.render_texture(spec, RoomSpecs.board_face_px())
	var m: Dictionary = _factory.face_board_metrics()
	var psize: Vector2 = RoomSpecs.board_panel_size()
	var face_size: Vector2 = m.get("face_size", Vector2(RoomSpecs.board_face_px()))
	var rows_out: Array = []
	for rv: Variant in (m.get("rows", []) as Array):
		var rd: Dictionary = (rv as Dictionary).duplicate()
		rd["panel_rect"] = _face_rect_to_panel(rd["rect"], face_size, psize)
		if rd.has("score_rect"):
			rd["score_panel_rect"] = _face_rect_to_panel(rd["score_rect"], face_size, psize)
		rows_out.append(rd)
	var out: Dictionary = {"texture": tex, "rows": rows_out, "panel_size": psize}
	if m.has("footer"):
		out["footer_panel_rect"] = _face_rect_to_panel(m["footer"], face_size, psize)
		out["footer_face_rect"] = m["footer"] ## GRADFIX10: the plinth in face space too - the ink legs exclude it from the content ink (it is furniture, not content)
	var ly: float = RoomSpecs.board_launch_y()
	out["launch_rect"] = Rect2(
		Vector2(-PANEL_LAUNCH_SIZE.x * 0.5, ly - PANEL_LAUNCH_SIZE.y * 0.5), PANEL_LAUNCH_SIZE)
	return out


## One face-space rect (pixels, origin top-left, +y down)
## in panel space (metres, origin centre, +y up, min-corner
## position) - the two spaces the layout legs compare in.

## ------------------------------------------------------ standing boards (GRADFIX7 item 2)

## A challenge's standing-board content key: the key the
## retired tournie flip back used - content identity plus
## the boards' fetch stamp and the player, so a boards
## refresh re-renders the board under its new key.
func _tournament_board_key(idx: int) -> String:
	if idx < 0 or idx >= _tournament_rows.size():
		return ""
	var row: Dictionary = _tournament_rows[idx] as Dictionary
	if str(row.get("kind", "")) != "challenge":
		return ""
	var ch: WovpChallenge = row["challenge"] as WovpChallenge
	if ch == null:
		return ""
	var pair_state: String = "none"
	if bool(row.get("owned", false)):
		pair_state = "owned" if bool(row.get("build_owned", false)) else "diff"
	# NEXTROUND (item 4): the board's PINemHi best line is
	# part of its content, so the best's identity rides the
	# key - a changed best re-renders the board.
	var pb: Dictionary = _pinemhi_bests.get(PinemhiScores.challenge_key(ch.table_name), {}) as Dictionary
	var pb_state: String = "" if pb.is_empty() else str(pb.get("score_text", ""))
	return "board|" + ch.challenge_id + "|" + str(_wovp_fetched_at) + "|" + _wovp_user_id \
		+ "|" + pair_state + ("|pb:" + pb_state if pb_state != "" else "")


## Seat the standing boards for the standing Tournament
## view: one pooled node per challenge, in its pair's outer
## slot at the board's own size, flush (seat_y 0 - no tilt,
## no radial offset, no companion shift), wearing the
## placeholder until its texture lands asynchronously.
func _seat_tournament_boards() -> void:
	for idx: int in range(_visible_games.size()):
		if _tourn_state_idx(idx):
			_board_nodes.append(null)
			_board_base_pos.append(Vector3.ZERO)
			_board_pop_dir.append(Vector3.ZERO)
			continue
		var row: Dictionary = _tournament_rows[idx] as Dictionary
		var ch: WovpChallenge = row["challenge"] as WovpChallenge
		if ch == null:
			_board_nodes.append(null)
			_board_base_pos.append(Vector3.ZERO)
			_board_pop_dir.append(Vector3.ZERO)
			continue
		var cid: String = ch.challenge_id
		var entry: Dictionary = _board_pool.get(cid, {}) as Dictionary
		var root: MeshInstance3D = entry.get("root") as MeshInstance3D
		var mat: StandardMaterial3D = entry.get("mat") as StandardMaterial3D
		if root == null or mat == null:
			root = MeshInstance3D.new()
			root.name = "TournBoard"
			var qm: QuadMesh = QuadMesh.new()
			qm.size = RoomSpecs.board_panel_size()
			root.mesh = qm
			mat = StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_texture = clear_tex() ## GRADFIX15: not yet rendered = invisible, never a dark slab
			root.material_override = mat
			entry = {"root": root, "mat": mat}
			_board_pool[cid] = entry
		if root.get_parent() != _wall:
			_wall.add_child(root)
		var bc: Vector2i = _board_coord(idx)
		root.transform = _card_transform_at(bc.x, bc.y)
		_board_base_pos.append(root.transform.origin)
		_board_pop_dir.append(root.transform.basis.z.normalized())
		root.visible = true
		var key: String = _tournament_board_key(idx)
		var book: Dictionary = _board_book.get(cid, {}) as Dictionary
		if book.is_empty():
			book = {"key": "", "tex_key": "", "tex_real": false, "render_key": "",
				"retry_key": "", "retries": 0, "retry_msec": 0}
			_board_book[cid] = book
		if str(book.get("key", "")) != key:
			book["key"] = key
			book["render_key"] = ""
			book["retry_key"] = ""
			book["retries"] = 0
			book["retry_msec"] = 0
			if _board_tex_cache.has(key):
				mat.albedo_texture = _board_tex_cache[key] as Texture2D
				book["tex_key"] = key
				book["tex_real"] = true
			else:
				mat.albedo_texture = clear_tex() ## GRADFIX15: no face yet - the board stands invisible
				book["tex_key"] = ""
				book["tex_real"] = false
		elif bool(book.get("tex_real", false)) and _board_tex_cache.has(key):
			mat.albedo_texture = _board_tex_cache[key] as Texture2D
		_board_nodes.append(root)


## Ask for a board fill pass (coalesced, like the window
## fill): the pass renders each standing board whose texture
## is not already honestly standing, through the serial
## TextureFactory. Never awaited by the seat/rebuild path.
func _request_tournament_board_fill() -> void:
	if not _tournament:
		return
	if _board_fill_busy:
		_board_fill_dirty = true
		return
	_run_tournament_board_fill()


func _run_tournament_board_fill() -> void:
	_board_fill_busy = true
	_board_fill_dirty = false
	var gen: int = _gen
	for idx: int in range(_visible_games.size()):
		if gen != _gen:
			break
		await _render_tournament_board(idx)
	_board_fill_busy = false
	if _board_fill_dirty and gen == _gen:
		_run_tournament_board_fill()


## Render ONE standing board (the standing-board render
## function): its spec is RoomSpecs.tournament_board_spec,
## rendered at RoomSpecs.board_face_px() - the seam-
## respecting size, NOT the flip path's BOARD_FACE_PX
## constant - with the spine side toward its card ("right"
## for a board standing on the left, "left" for one on the
## right; "" is NOT "no spine" - CardFace treats every
## non-"left" spine as right, so the explicit value is the
## law). The solidboard NC's bite lives HERE now (it lived
## in _render_card_back, which no longer serves the
## Tournament Room): a solidboard render lands the factory's
## fallback solid and counts it as the board, so the
## blank-board legs fail by name.
func _render_tournament_board(idx: int) -> void:
	if not _tournament or idx < 0 or idx >= _tournament_rows.size() or idx >= _board_nodes.size():
		return
	if _tourn_state_idx(idx):
		return
	var row: Dictionary = _tournament_rows[idx] as Dictionary
	var ch: WovpChallenge = row["challenge"] as WovpChallenge
	if ch == null:
		return
	var cid: String = ch.challenge_id
	var key: String = _tournament_board_key(idx)
	if key == "":
		return
	var book: Dictionary = _board_book.get(cid, {}) as Dictionary
	if book.is_empty():
		return
	if str(book.get("tex_key", "")) == key and bool(book.get("tex_real", false)):
		return
	if str(book.get("render_key", "")) == key:
		return
	if _board_tex_cache.has(key):
		var cached: Texture2D = _board_tex_cache[key] as Texture2D
		var cnode: MeshInstance3D = _board_nodes[idx] as MeshInstance3D
		if cnode != null:
			var cmat: StandardMaterial3D = cnode.material_override as StandardMaterial3D
			if cmat != null:
				cmat.albedo_texture = cached
		book["tex_key"] = key
		book["tex_real"] = true
		return
	book["render_key"] = key
	var spec: Dictionary = RoomSpecs.tournament_board_spec(
		ch, bool(row.get("owned", false)), _wovp_user_id, int(Time.get_unix_time_from_system()),
		bool(row.get("build_owned", false)),
		_pinemhi_bests.get(PinemhiScores.challenge_key(ch.table_name), {}) as Dictionary,
		true) ## ROOMSUBMIT: the standing board names its submit command (Y - SUBMIT A SCORE)
	var bc: Vector2i = _board_coord(idx)
	var cc: Vector2i = _grid_coord(idx)
	spec["spine_side"] = "right" if bc.x < cc.x else "left"
	var tex: Texture2D = await _factory.render_texture(spec, RoomSpecs.board_face_px())
	if str(book.get("render_key", "")) == key:
		book["render_key"] = ""
	if not _tournament or idx >= _tournament_rows.size() or idx >= _board_nodes.size() or _tourn_state_idx(idx):
		return
	var row2: Dictionary = _tournament_rows[idx] as Dictionary
	var ch2: WovpChallenge = row2["challenge"] as WovpChallenge
	if ch2 == null or ch2.challenge_id != cid or _tournament_board_key(idx) != key:
		return
	if tex == null:
		return
	var real: bool = _tex_is_real(tex)
	if debug_gf4_nc == "solidboard" and real:
		tex = TextureFactory.make_solid(Color(0.055, 0.055, 0.095))
		real = true
	if real:
		_board_tex_cache[key] = tex
	# GRADFIX15 (item 1): only a REAL capture is ever stamped
	# on a board. A render that lands the factory's fallback
	# solid leaves the board standing on its clear texture
	# (invisible) and the book's tex_real false, so the heal
	# re-issues it (bounded) - the fallback never stands as a
	# dark slab dressed as a board.
	var node: MeshInstance3D = _board_nodes[idx] as MeshInstance3D
	if node != null:
		var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
		if mat != null and real:
			mat.albedo_texture = tex
	book["key"] = key
	book["tex_key"] = key
	book["tex_real"] = real


## The standing-board heal (GRADFIX6 discipline, N slots):
## once per BOARD_TEX_RETRY_MS, sweep the standing boards
## and re-issue renders for any whose texture is missing or
## unreal - bounded at BOARD_TEX_MAX_RETRIES per key, per
## board. A key change under a standing board (set_wovp_data
## landing while the Tournament Room stands) resets that
## board to the placeholder and re-renders under the new key.
func _heal_tournament_boards() -> void:
	if not _tournament or _board_nodes.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _board_heal_msec < BOARD_TEX_RETRY_MS:
		return
	_board_heal_msec = now
	var needs_pass: bool = false
	for idx: int in range(_board_nodes.size()):
		if idx >= _tournament_rows.size() or _tourn_state_idx(idx):
			continue
		var row: Dictionary = _tournament_rows[idx] as Dictionary
		var ch: WovpChallenge = row["challenge"] as WovpChallenge
		if ch == null:
			continue
		var book: Dictionary = _board_book.get(ch.challenge_id, {}) as Dictionary
		if book.is_empty():
			continue
		var key: String = _tournament_board_key(idx)
		if str(book.get("key", "")) != key:
			book["key"] = key
			book["tex_key"] = ""
			book["tex_real"] = false
			book["render_key"] = ""
			book["retry_key"] = ""
			book["retries"] = 0
			book["retry_msec"] = 0
			var hnode: MeshInstance3D = _board_nodes[idx] as MeshInstance3D
			if hnode != null:
				var hmat: StandardMaterial3D = hnode.material_override as StandardMaterial3D
				if hmat != null:
					hmat.albedo_texture = clear_tex() ## GRADFIX15: a re-keyed board stands invisible until its face lands
			needs_pass = true
			continue
		if str(book.get("tex_key", "")) == key and bool(book.get("tex_real", false)):
			continue
		if str(book.get("render_key", "")) != "":
			continue
		if str(book.get("retry_key", "")) != key:
			book["retry_key"] = key
			book["retries"] = 0
		if int(book.get("retries", 0)) >= BOARD_TEX_MAX_RETRIES:
			continue
		if now - int(book.get("retry_msec", 0)) < BOARD_TEX_RETRY_MS:
			continue
		book["retry_msec"] = now
		book["retries"] = int(book.get("retries", 0)) + 1
		needs_pass = true
	if needs_pass:
		_request_tournament_board_fill()


## Smoke support: the standing boards' state (flip_state()'s
## analogue for GRADFIX7 item 2) - per row, its card's coord,
## its board's coord and side, whether the board stands
## visible, its size and seat, and its texture bookkeeping.
func board_state() -> Array:
	var out: Array = []
	for idx: int in range(_visible_games.size()):
		var cc: Vector2i = _grid_coord(idx)
		if not _tournament or _tourn_state_idx(idx):
			out.append({
				"idx": idx, "challenge_id": "", "card_coord": cc,
				"board_coord": Vector2i(-1, -1), "side": "",
				"board_visible": false, "board_size": RoomSpecs.board_panel_size(),
				"seat_y": 0.0, "texture": null, "texture_real": false,
				"standing_key": "", "texture_key": "",
			})
			continue
		var row: Dictionary = _tournament_rows[idx] as Dictionary
		var ch: WovpChallenge = row["challenge"] as WovpChallenge
		var cid: String = ch.challenge_id if ch != null else ""
		var bc: Vector2i = _board_coord(idx)
		var node: MeshInstance3D = _board_nodes[idx] as MeshInstance3D if idx < _board_nodes.size() else null
		var standing_size: Vector2 = RoomSpecs.board_panel_size()
		if node != null and node.mesh is QuadMesh:
			standing_size = (node.mesh as QuadMesh).size
		var tex: Texture2D = null
		if node != null:
			var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
			if mat != null:
				tex = mat.albedo_texture
		var book: Dictionary = _board_book.get(cid, {}) as Dictionary
		out.append({
			"idx": idx, "challenge_id": cid, "card_coord": cc,
			"board_coord": bc, "side": "left" if bc.x < cc.x else "right",
			"board_visible": node != null and node.visible,
			"board_size": standing_size,
			"seat_y": 0.0, "texture": tex,
			"texture_real": bool(book.get("tex_real", false)),
			"standing_key": str(book.get("key", "")),
			"texture_key": str(book.get("tex_key", "")),
		})
	return out


func _face_rect_to_panel(r: Rect2, face_size: Vector2, panel_size: Vector2) -> Rect2:
	var sx: float = panel_size.x / face_size.x
	var sy: float = panel_size.y / face_size.y
	var x0: float = (r.position.x - face_size.x * 0.5) * sx
	var y_top: float = (face_size.y * 0.5 - r.position.y) * sy
	return Rect2(Vector2(x0, y_top - r.size.y * sy), Vector2(r.size.x * sx, r.size.y * sy))


# ------------------------------------------------------------ interaction

func _refresh_focusables() -> void:
	_focusables.clear()
	if _launching_game_id != "":
		# The load wait is deaf (see begin_launch): the focusable
		# set is EMPTY, so focus navigation has nowhere to land
		# and there is no focused quad for a stray press to fire.
		pass
	elif _placard_up:
		# The placard owns the room: BACK is the only focus stop.
		if _placard_back != null:
			_focusables.append(_placard_back)
	elif _setup_panel_up:
		# The SETUP panel owns the room: its six buttons are
		# the only focus stops (see show_setup_panel).
		if _setup_panel_scan_btn != null:
			_focusables.append(_setup_panel_scan_btn)
		if _setup_panel_dl_btn != null:
			_focusables.append(_setup_panel_dl_btn)
		if _setup_panel_wovp_paste_btn != null:
			_focusables.append(_setup_panel_wovp_paste_btn)
		if _setup_panel_wovp_test_btn != null:
			_focusables.append(_setup_panel_wovp_test_btn)
		if _setup_panel_stars_btn != null:
			_focusables.append(_setup_panel_stars_btn)
		if _setup_panel_wall_btn != null:
			_focusables.append(_setup_panel_wall_btn)
		if _setup_panel_ipdb_btn != null:
			_focusables.append(_setup_panel_ipdb_btn)
		if _setup_panel_back_btn != null:
			_focusables.append(_setup_panel_back_btn)
	elif _submit_panel_up:
		# ROOMSUBMIT: the submit panel owns the room while
		# it stands - its stops are the shot thumbs (newest
		# first), then SEND, then BACK. The big photo quad
		# is a display surface, never a stop: focus moving
		# across the thumbs is what changes it.
		for tq: ClickableQuad in _submit_thumb_quads:
			if tq != null:
				_focusables.append(tq)
		if _submit_send_btn != null:
			_focusables.append(_submit_send_btn)
		if _submit_back_btn != null:
			_focusables.append(_submit_back_btn)
	elif _mode == "detail" and _detail != null:
		_focusables = _detail.get_clickables()
	else:
		# Cards only (Chris's ruling, 2026-10-24): the per-card
		# Launch buttons are NOT focus stops. When they were, a
		# column descent cost two presses per row - card, button,
		# card, button - because the button sits directly below
		# its card in the focus walk. Focus now visits cards and
		# rail stops only: DOWN travels row to row, RIGHT card to
		# card, and the pad starts the focused card with A
		# (see _a_press). The button remains the pointer's
		# target and the card's state label.
		for i: int in range(_panels.size()):
			_focusables.append(_panels[i])
		for k: Variant in _rail_quads.keys():
			var q: ClickableQuad = _rail_quads[k]
			if q.pick_enabled:
				_focusables.append(q)
		# The strip's lit slots are stops too, after the rail's
		# (their row rides under it). Greyed slots are not
		# pickable, so they are not stops - the same rule the
		# rail's page_label follows.
		for skey: String in _strip_slot_keys():
			var sq: ClickableQuad = _strip_quads.get(skey) as ClickableQuad
			if sq != null and sq.visible and sq.pick_enabled:
				_focusables.append(sq)
	if _focused != null and not _focusables.has(_focused):
		_set_focused(null)
	_refresh_quad_states()


func _set_focused(q: ClickableQuad) -> void:
	_focused = q
	_refresh_quad_states()
	# ROOMSUBMIT: on the submit panel, focus IS the verify
	# step - the focused thumb's shot stands large. This is
	# the one door every focus move passes through (stick
	# walk, cycle, landings), so the big photo can never
	# disagree with the frame the player sees.
	if _submit_panel_up and q != null and _submit_thumb_quads.has(q):
		_submit_show_shot(q.payload)


func _refresh_quad_states() -> void:
	var tel_q_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry: the focus-change sweep's cost, timed below
	var hovered: ClickableQuad = _rig.hovered if _rig != null else null
	var all: Array[ClickableQuad] = []
	all.append_array(_panels)
	for lq2: ClickableQuad in _panel_launches:
		if lq2 != null:
			all.append(lq2)
	for blq: ClickableQuad in _panel_back_launches:
		if blq != null:
			all.append(blq)
	for k: Variant in _rail_quads.keys():
		all.append(_rail_quads[k])
	# The strip's slots are focus stops too, so they take
	# visual state like every other stop. The letter-jump
	# round forgot them here: focus could LAND on a letter
	# (the walk, the focusables, the country law all knew
	# the strip) but set_visual_state never reached it, so
	# the letter's frame never lit and the rail's frame went
	# dark in the same step - the highlight "disappeared"
	# exactly at the strip (Chris, 2026-10-27). The NC value
	# "visual" restores that omission for the harness.
	if debug_focus_nc != "visual":
		for sk: Variant in _strip_quads.keys():
			var sq: ClickableQuad = _strip_quads[sk] as ClickableQuad
			if sq != null:
				all.append(sq)
	if _detail != null:
		all.append_array(_detail.get_clickables())
	if _placard_face != null:
		all.append(_placard_face)
	if _placard_back != null:
		all.append(_placard_back)
	if _setup_panel_face != null:
		all.append(_setup_panel_face)
	if _setup_panel_scan_btn != null:
		all.append(_setup_panel_scan_btn)
	if _setup_panel_dl_btn != null:
		all.append(_setup_panel_dl_btn)
	if _setup_panel_wovp_paste_btn != null:
		all.append(_setup_panel_wovp_paste_btn)
	if _setup_panel_wovp_test_btn != null:
		all.append(_setup_panel_wovp_test_btn)
	if _setup_panel_stars_btn != null:
		all.append(_setup_panel_stars_btn)
	if _setup_panel_wall_btn != null:
		all.append(_setup_panel_wall_btn)
	if _setup_panel_ipdb_btn != null:
		all.append(_setup_panel_ipdb_btn)
	if _setup_panel_back_btn != null:
		all.append(_setup_panel_back_btn)
	# ROOMSUBMIT: the submit panel's stops take visual
	# state like every other stop (the letter-strip lesson:
	# a stop set_visual_state never reaches shows no frame,
	# and focus reads as vanished exactly there).
	if _submit_panel_face != null:
		all.append(_submit_panel_face)
	for stq: ClickableQuad in _submit_thumb_quads:
		if stq != null:
			all.append(stq)
	if _submit_send_btn != null:
		all.append(_submit_send_btn)
	if _submit_back_btn != null:
		all.append(_submit_back_btn)
	for q: ClickableQuad in all:
		q.set_visual_state(q == hovered, q == _focused)
	# GRADFIX17 telemetry: this sweep walks every quad in
	# the room on every focus change (once per cruise
	# column) - a slow one names itself.
	var tel_q_ms: float = float(Time.get_ticks_usec() - tel_q_t0) / 1000.0
	if tel_q_ms >= 4.0:
		_art_event("seg", {"seg": "quad_states", "cost_ms": tel_q_ms, "quads": all.size(), "col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1, "nc_roll_dir": _nc_roll_dir})


func _on_hover_changed(_quad: ClickableQuad) -> void:
	_refresh_quad_states()


## The panel a focus-ish quad belongs to: the quad itself when it
## is a card, or the card whose Launch button it is. Anything else
## (rail, detail, banner) owns no card.
func _panel_for(q: ClickableQuad) -> ClickableQuad:
	if q == null:
		return null
	if _panels.has(q):
		return q
	var lidx: int = _panel_launches.find(q)
	if lidx >= 0 and lidx < _panels.size():
		return _panels[lidx]
	var bidx: int = _panel_back_launches.find(q)
	if bidx >= 0 and bidx < _panels.size():
		return _panels[bidx]
	return null


## The one card that should be popped right now: the CENTRED
## card (DOME5's law - on a drum the pop is the shelf's own
## statement of where it stands, not a hover effect; hover
## and pad focus MOVE the centre, in _update_pop's follow
## step, and the pop follows the centre). No pop while the
## detail view or the placard owns the room, and none during
## the load wait - the wall is frozen behind the marquee.
func _pop_target_panel() -> ClickableQuad:
	if _mode != "wall" or _placard_up or _setup_panel_up or _submit_panel_up or _launching_game_id != "":
		return null
	if _centre_index < 0 or _centre_index >= _panels.size():
		return null
	return _panels[_centre_index]


## The centre follows the player's point: the pointer's card
## wins (VR laser and mouse hover both arrive as the rig's
## hover), else the gamepad/keyboard focus's card. Called
## per frame from _update_pop; _set_centre early-outs when
## the centre already stands there, and the swing retargets
## from the drum's current angle, so a sweeping point swings
## the drum with it - input is never gated by the travel.
func _follow_centre() -> void:
	if _mode != "wall" or _placard_up or _setup_panel_up or _submit_panel_up or _launching_game_id != "":
		return
	var hovered: ClickableQuad = _rig.hovered if _rig != null else null
	if _boot_guard:
		# The boot seating guard (see setup): while it
		# stands, the pointer's RESTING hover is not a
		# point - the follow runs on the focus alone,
		# which is the restore's seating. The guard falls
		# to the first genuine act: the hover CHANGES
		# from the resting place recorded when the wall
		# landed (the player pointed somewhere), or the
		# focus or centre was seated by another path
		# (a pad step, a letter pick, a page turn - the
		# input's own seating lands that frame, and the
		# shipped pointer law resumes from the next).
		var released_by_seat: bool = false
		if _focused != _boot_focus_ref or _centre_index != _boot_centre_ref:
			_boot_guard = false
			released_by_seat = true
		elif not _boot_hover_sampled:
			if wall_ready:
				_boot_hover_ref = hovered
				_boot_hover_sampled = true
		elif hovered != _boot_hover_ref:
			_boot_guard = false
		if _boot_guard or released_by_seat:
			hovered = null
	if _nc_roll_dir != 0:
		# While the NC seam's roll stands (debug only), its
		# own drive owns the centre; the follow resumes the
		# frame the roll ends.
		return
	var p: ClickableQuad = _panel_for(hovered)
	if p == null:
		p = _panel_for(_focused)
	if p != null:
		var idx: int = _panels.find(p)
		if idx >= 0 and idx != _centre_index:
			_set_centre(idx)


## Per-frame pop animation, driven from _process.
##
## GRADFIX10 item 2 - the jitter conviction and the fix.
## Chris: "when you highlight a board and it pops up a bit,
## it feels like 2 or 3 frames, kinda jittery. I'd like that
## motion butter smooth." Convicted from the code plus a
## dense trace on the shipped build: the pop was a FIXED
## 0.15 s wall-clock LINEAR ramp - move_toward(amount, want,
## delta / POP_OUT_SEC) - so its visible frame count was
## never a property of the motion, only of the frame pacing
## during those 150 ms: 0.15 x fps-at-that-moment. And the
## pacing during exactly that window is the worst the room
## ever runs, because the same centre change that starts
## the pop also starts the window fill (the new column's
## faces render through the serial factory, one GPU
## readback apiece), the board heal's renders in the
## Tournament view, and the swing. The harness-box trace of
## the shipped pop (motion smoke, base build): frames of
## 106-186 ms inside the pop window, the amount landing in
## TWO steps - [1 ms 0.000] [112 ms 0.652] [298 ms 1.000].
## At a locked 90 Hz the same ramp spans ~13 frames; at any
## hitch it collapses to the 2-3 Chris counted. A linear
## ramp also starts and stops at full speed, so every one
## of those few steps reads as a jump, not a glide.
##
## The fix: the amount now rides a critically damped spring
## (the swing's own smooth-damp form) with velocity carried
## across retargets - a pop interrupted mid-travel bends
## back instead of reversing at full speed - and lands by
## exact snap inside a hair of its target. Its step is
## also CLAMPED (POP_MAX_STEP_SEC): a spring that
## integrates a hitch frame's whole delta faithfully
## fast-forwards through its middle poses (measured: one
## 71 ms fill frame carried the amount to 0.639), so the
## pop integrates at most 1/30 s per frame - under a hitch
## it slows down instead of skipping. The spring's
## core is as quick as the old ramp (90% home in ~POP_OUT_
## SEC) but its ease-in/ease-out tail means a sparse frame
## still lands BETWEEN poses instead of ON the next step:
## no frame ever carries a coarse quantum of the travel.
## The NC seam (PVLDS_GRADFIX10_NC=steppop) restores the
## convicted shape - the applied amount quantised to
## thirds - so the motion smoke's pop-smoothness leg fails
## against it by name.
##
## The Tournament pair (same item): a challenge's standing
## board now rides its card's pop - same amount, same
## spring, offset along the board's own wall normal without
## scaling (the board's text must not grow) - so the pair
## the player highlighted travels as one object instead of
## the card lunging off its board. Boards took no pop at
## all before this round (see the standing-boards section);
## the library has no boards and is untouched by that half.
##
## The transform is written only while the amount is
## actually moving - a resting panel is never touched, so a
## Launch button's activation pulse (a scale tween) never
## fights this. The pop is UNIFORM (DOME5): scale
## POP_OUT_SCALE and a POP_OUT_DISTANCE pull along the
## card's own normal - the true-aspect grow the flat wall
## used is retired (the dome's clearance proof was measured
## on the uniform pop). The Launch button rides its panel
## (it is a child), so it stays glued to the card face and
## clickable while popped.
func _update_pop(delta: float) -> void:
	var tel_pop_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry: the pop block's cost, timed below
	_follow_centre()
	if _panels.is_empty():
		return
	var target: ClickableQuad = _pop_target_panel()
	# The step clamp: the spring integrates at most
	# POP_MAX_STEP_SEC per frame, so a hitch frame (the fill
	# work a centre change starts - the convicted window)
	# stretches the pop's wall time instead of teleporting
	# it past its middle poses.
	var pdelta: float = minf(delta, POP_MAX_STEP_SEC)
	var omega: float = 2.0 / POP_SPRING_TAU
	var x: float = omega * pdelta
	var ex: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	while _panel_pop_vel.size() < _panels.size():
		_panel_pop_vel.append(0.0)
	# OPTIMIZE standing-cost cut: the spring loop SLEEPs at
	# rest. Pre-cut measurement (scratch bench, same driver
	# both times): the loop visited every panel every frame
	# at rest - 700 visits over a 6 s rest window on a
	# 10-card wall, ~116/s, scaling with wall size - doing
	# spring math whose writes its own applied-guard then
	# suppressed. The loop now runs only while awake: a pop
	# target change wakes it, a face landing under a popped
	# card wakes it (see _fill_one_face_sync), a rebuild
	# wakes it, and it puts itself back to sleep the frame
	# every panel stands settled at its target. The flip,
	# the follow and the heals below run regardless - they
	# are not the pop loop.
	if target != _pop_last_target:
		_pop_awake = true
	var sc_at_rest: bool = not _swing_active and _power_phase != 1 and not _art_pipe_busy ## OPTIMIZE standing-cost audit
	var sc_all_settled: bool = true
	for i: int in range(_panels.size() if _pop_awake else 0):
		if sc_at_rest:
			_sc_pop_visits_rest += 1 ## OPTIMIZE standing-cost audit (observation only)
		var want: float = 1.0 if _panels[i] == target else 0.0
		if absf(_panel_pop[i] - want) >= 0.004 or absf(_panel_pop_vel[i]) >= 0.08:
			sc_all_settled = false
		var change: float = _panel_pop[i] - want
		var temp: float = (_panel_pop_vel[i] + omega * change) * pdelta
		_panel_pop_vel[i] = (_panel_pop_vel[i] - omega * temp) * ex
		var amt: float = want + (change + temp) * ex
		if absf(amt - want) < 0.004 and absf(_panel_pop_vel[i]) < 0.08:
			amt = want
			_panel_pop_vel[i] = 0.0
		_panel_pop[i] = amt
		var applied: float = amt
		if debug_gf10_nc == "steppop":
			# NC: the convicted stepping, restored - the
			# applied amount quantised to coarse thirds, so
			# the rendered pop advances in 2-3 jumps.
			applied = clampf(roundf(amt * 3.0) / 3.0, 0.0, 1.0)
		if absf(applied - _panel_pop_applied[i]) < 0.001:
			continue
		_panel_pop_applied[i] = applied
		var q: ClickableQuad = _panels[i]
		q.position = _panel_base_pos[i] + _panel_pop_dir[i] * (POP_OUT_DISTANCE * applied)
		var s: float = lerpf(1.0, POP_OUT_SCALE, applied)
		q.scale = Vector3(s, s, s)
		# The pair ride: this card's standing board (the
		# Tournament view) takes the same offset along its
		# own normal, at the same applied amount.
		if i < _board_nodes.size():
			var bnode: MeshInstance3D = _board_nodes[i] as MeshInstance3D
			if bnode != null and i < _board_base_pos.size():
				bnode.position = (_board_base_pos[i] as Vector3) \
					+ (_board_pop_dir[i] as Vector3) * (POP_OUT_DISTANCE * applied)
	if _pop_awake and sc_all_settled:
		_pop_awake = false
		_pop_last_target = target
	_update_flip(delta)
	# GRADFIX17 (item 1): the landing guarantee's arming - a
	# travel's falling edge (swing or page slide stood last
	# frame, stands no longer) owes the standing window a
	# settle audit. The audit runs BEFORE the heal so its
	# memo corrections ride the heal's own pass request too.
	var gf17_travelling: bool = _swing_active or page_slide_active()
	if gf17_travelling:
		_gf17_was_travelling = true
	elif _gf17_was_travelling:
		_gf17_was_travelling = false
		_gf17_audit_armed = true
		_gf17_audit_runs = 0
		if _settle_travel_end_msec == 0:
			_settle_travel_end_msec = Time.get_ticks_msec() ## OPTIMIZE: the settle audit's dress_ms zero
	# The NC costume seam's beat (debug only; a no-op in
	# production): it engages and releases on the same travel
	# edges the guarantee arms on, and it runs BEFORE the
	# audit below so a falling edge hands the blanked faces
	# back first and the audit then runs on dressed faces.
	_nc_costume_tick()
	if _gf17_audit_armed:
		_guarantee_audit()
	_heal_panel_faces()
	_heal_tournament_boards()
	# GRADFIX17 telemetry: the pop block runs every frame
	# and carries the follow, the flip and both heals - a
	# slow one names itself (its parts have their own
	# segments where they are separately convicted).
	var tel_pop_ms: float = float(Time.get_ticks_usec() - tel_pop_t0) / 1000.0
	if tel_pop_ms >= 8.0:
		_art_event("seg", {"seg": "update_pop", "cost_ms": tel_pop_ms, "col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1, "nc_roll_dir": _nc_roll_dir})


## The machined strip's lift (GRADFIX14 item 1), driven
## from _process beside the pop: exactly ONE section - the
## focused rail stop - rises toward the viewer, and sinks
## back flush as focus moves on. The motion is the pop's
## own discipline, verbatim in miniature (GRADFIX10 item
## 2): a critically damped spring (POP_SPRING_TAU) with
## velocity carried across retargets, its step clamped to
## POP_MAX_STEP_SEC so a hitch frame slows the lift instead
## of skipping its poses, landing by exact snap inside a
## hair of its target. No linear ramp, no second system.
## The lifted GRADIENT swaps at the lift's half-rise (and
## back at its half-fall), so the material change rides the
## motion - the section reads as the bar's own graphite
## rising on a bevel, never as a separate box appearing.
## The page readout is not a stop and never lifts; a card
## or strip focus lifts nothing. Unfocused sections stay
## flush and still: the transform is written only while a
## section's amount is actually moving.
func _update_rail_lift(delta: float) -> void:
	if not _strip_mode() or _rail_quads.is_empty():
		return
	var pdelta: float = minf(delta, POP_MAX_STEP_SEC)
	var omega: float = 2.0 / POP_SPRING_TAU
	var x: float = omega * pdelta
	var ex: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	for k: Variant in _rail_quads.keys():
		var key: String = str(k)
		var quad: ClickableQuad = _rail_quads[k] as ClickableQuad
		if quad == null or not _rail_pop.has(key):
			continue
		var want: float = 1.0 if quad == _focused and key != "page_label" else 0.0
		var cur: float = float(_rail_pop[key])
		var vel: float = float(_rail_pop_vel[key])
		var change: float = cur - want
		var temp: float = (vel + omega * change) * pdelta
		vel = (vel - omega * temp) * ex
		var amt: float = want + (change + temp) * ex
		if absf(amt - want) < 0.004 and absf(vel) < 0.08:
			amt = want
			vel = 0.0
		_rail_pop[key] = amt
		_rail_pop_vel[key] = vel
		var lifted_tex: bool = amt > 0.5
		if lifted_tex != bool(_rail_tex_lifted.get(key, false)):
			_rail_tex_lifted[key] = lifted_tex
			_apply_rail_texture_for(key)
		var applied: float = float(_rail_pop_applied[key])
		if absf(amt - applied) < 0.001:
			continue
		_rail_pop_applied[key] = amt
		quad.position = (_rail_base_pos[key] as Vector3) + (_rail_pop_dir[key] as Vector3) * (RAIL_STRIP_LIFT * amt)


## Strip lift queries (the strip shot hook reads the room
## the way the pop shot reads its subject): a section's
## current lift amount and how far it sits off its flush
## seat.
func rail_lift_amount(key: String) -> float:
	return float(_rail_pop.get(key, 0.0))


func rail_lift_offset(key: String) -> Vector3:
	var quad: ClickableQuad = _rail_quads.get(key) as ClickableQuad
	if quad == null or not _rail_base_pos.has(key):
		return Vector3.ZERO
	return quad.position - (_rail_base_pos[key] as Vector3)


## ------------------------------------------------------ the card flip
##
## The flip (GRADFIX6 item 1 - Chris's design, the original
## concept restored): Y turns the focused card over IN ITS
## SEAT. The front is the art face as always; the back is
## the info the wing and the book used to carry beside the
## card - in the library, RoomSpecs.wing_spec (the table's
## data, and the live board too when the table stands in a
## challenge). (The Tournament Room has NO flip since
## GRADFIX7 item 2: its boards stand open beside their
## cards - see the standing boards section.) What
## the flip replaces, it deletes: no companion panel, no
## borrowed slot, no hinge - the GRADFIX5 field verdict on
## the book was "still off-center, still butting into table
## art's business", and a card's back can be neither.
##
## Mechanics: the turn rides the quad's flip pivot (see
## ClickableQuad) about the card's own vertical centre
## axis. _flip_t walks 0 (front) to 1 (back) at FLIP_SEC
## for the half-turn on a cubic in-out ease; at the
## midpoint the showing side swaps - front furniture hides,
## the back assembly shows - so no mirrored face or label
## ever reads through the turn. The card never leaves its
## seat: the pop's position/scale are the root's, the turn
## is the pivot's, and at mid-flip the card is edge-on
## inside its own slot, so its swept volume stays home
## (the grad census charges exactly that, per centre).
## Input is never gated: a press mid-turn lands on the
## standing state, and the turn itself is one variable
## walking toward its target.
##
## One card wears the turn at a time. The turn closes -
## target back to front - when the centre moves to another
## card, when the view leaves the wall (detail, placard,
## SETUP panel, the load wait), or when the wall rebuilds;
## a snap shut (no animation) happens only on rebuild,
## where the wall itself snaps.

## The flip's NC seam: under PVLDS_GRADFIX6_NC=noflip the
## Y press is inert (the pre-fix world, where Y opened the
## detail view instead) - the flip legs fail by name.
func _flip_disabled() -> bool:
	return OS.get_environment("PVLDS_GRADFIX6_NC") == "noflip"


## Y's new job (see _info_focused_card): turn the focused
## card over, or back. Only a card-mode panel in the plain
## wall flips; the state row has no back, and a board-mode
## panel never reaches here. Starting a turn on a card
## snaps any other card's turn shut first - one back shows
## at a time, and the snap is instant so the new turn owns
## the stage.
func _toggle_flip(idx: int) -> void:
	if _tournament:
		return ## belt and braces (GRADFIX7 item 2): no flip in the Tournament Room, from any caller
	if idx < 0 or idx >= _panels.size():
		return
	var q: ClickableQuad = _panels[idx]
	if q == null or q.flip_pivot() == null:
		return
	if _flip_nodes(idx).is_empty():
		return ## no back to turn to (the Tournament state row wears a board face already)
	if _flip_idx == idx:
		_flip_open = not _flip_open
	else:
		if _flip_idx >= 0:
			_snap_flip_shut()
		_flip_idx = idx
		_flip_open = true
		_flip_key = _card_back_key(idx)
		_flip_tex_key = ""
		_flip_tex_real = false
		_flip_render_key = ""
		_flip_retry_key = ""
		_flip_retries = 0
		# The power-on performs on the FRONT: a performance
		# standing on this card restores before it turns.
		if _power_panel == q or _power_candidate == q:
			_restore_power("flip")
	_refresh_card_back()


## Close the turn (animated): the target returns to the
## front; _update_flip walks it home and clears the state
## when it lands.
func _close_flip() -> void:
	_flip_open = false


## Snap the turn shut with no animation (a wall rebuild:
## the wall itself snaps, so the card does too).
func _snap_flip_shut() -> void:
	if _flip_idx >= 0 and _flip_idx < _panels.size():
		var q: ClickableQuad = _panels[_flip_idx]
		if q != null:
			q.set_flip_angle(0.0)
			_apply_flip_side(_flip_idx, false)
	_flip_idx = -1
	_flip_t = 0.0
	_flip_open = false
	_flip_key = ""
	_flip_tex_key = ""
	_flip_tex_real = false
	_flip_render_key = ""


## The standing back's content key for a panel: the same
## discipline the companions used - content identity plus
## the boards' fetch stamp and the player, so a boards
## refresh re-renders the back under its standing key.
func _card_back_key(idx: int) -> String:
	var game: GameEntry = _visible_games[idx]
	var ch2: WovpChallenge = null
	for cv: Variant in _wovp_challenges:
		var cand: WovpChallenge = cv as WovpChallenge
		if cand != null and cand.table_external_id == game.game_id:
			ch2 = cand
			break
	return "wing|" + game.game_id + "|" + (ch2.challenge_id if ch2 != null else "") \
		+ "|" + str(_wovp_fetched_at) + "|" + _wovp_user_id + "|ipdb" + str(_ipdb_stamp)


## The spec a panel's back renders: the Tournament board
## for a challenge card in the Tournament Room, the wing
## spec (table data, or board + data) in the library -
## with the book's dressing retired: the spine key goes
## (a card's back joins nothing). Through GRADFIX12 the
## footer plinth the wing waived was restored here, because
## the back carried its own Launch button where the board's
## always sat - and the composition centred over the area
## ABOVE that 140 px reservation, so on the standing card
## it rode 70 px high with the button squatting at its base
## (the Buck Rogers back in Chris's capture 20261101-124532:
## extent centre -65 px against the card). GRADFIX13
## (items 1+2): the plinth is stripped, the reservation
## dies with it, the freed height goes to the composition,
## and the back takes the factory's extent correction like
## a standing board (ink_centre) - it centres on the card's
## full extent. Only the plinth NC restores the footer.
func _card_back_spec(idx: int) -> Dictionary:
	var game: GameEntry = _visible_games[idx]
	var now_unix: int = int(Time.get_unix_time_from_system())
	var ch2: WovpChallenge = null
	for cv: Variant in _wovp_challenges:
		var cand: WovpChallenge = cv as WovpChallenge
		if cand != null and cand.table_external_id == game.game_id:
			ch2 = cand
			break
	var spec: Dictionary = RoomSpecs.wing_spec(game, ch2, _wovp_user_id, now_unix,
		_ipdb_facts.get(game.game_id, {}) as Dictionary)
	spec["spine_side"] = ""
	spec["footer_px"] = RoomSpecs.BOARD_FOOTER_PX if _plinth_nc() else 0
	spec["ink_centre"] = not _plinth_nc()
	return spec


## The flipped card's nodes ({} when the panel has no back
## - a board-mode panel, or an index off the wall).
func _flip_nodes(idx: int) -> Dictionary:
	if idx < 0 or idx >= _panels.size():
		return {}
	var game: GameEntry = _visible_games[idx]
	var nodes: Dictionary = _panel_pool.get(game.game_id, {}) as Dictionary
	if nodes.is_empty() or str(nodes.get("mode", "")) != "card":
		return {}
	return nodes


## A real capture is never the factory's fallback: the
## fallback solid is 4x4, every real face renders at its
## spec size (hundreds of pixels). The blank-face heal
## (GRADFIX4 item 6, carried into the flip) keys on this.
func _tex_is_real(tex: Texture2D) -> bool:
	return tex != null and tex.get_width() > 16 and tex.get_height() > 16


## (Re)render the flipped card's back for its standing key:
## a no-op when the applied texture already serves the key
## with a real capture, or when that render is in flight.
## The render is the factory's ordinary async path - it
## never blocks a frame, and the turn never waits for it:
## a back whose face is still landing shows nothing (the
## clear texture - GRADFIX15's frameless law), then the
## content swaps in (the heal below keeps retrying a
## fallback landing, bounded).
func _refresh_card_back() -> void:
	if _flip_idx < 0:
		return
	var nodes: Dictionary = _flip_nodes(_flip_idx)
	if nodes.is_empty():
		return
	if _flip_key == "":
		_flip_key = _card_back_key(_flip_idx)
	if _flip_tex_key == _flip_key and _flip_tex_real:
		return
	if _flip_render_key == _flip_key:
		return
	_flip_render_key = _flip_key
	_render_card_back(_flip_idx, _flip_key)


func _render_card_back(idx: int, key: String) -> void:
	var nodes: Dictionary = _flip_nodes(idx)
	if nodes.is_empty():
		if _flip_render_key == key:
			_flip_render_key = ""
		return
	var spec: Dictionary = _card_back_spec(idx)
	# The back is a CARD face: it renders at the card's own
	# face size (the BACK_FACE_PX constant - the card's
	# aspect, decoupled from the standing board's size by
	# GRADFIX8's widening), never through the state-panel
	# seams (oldlayout/shortpage resize the board-mode
	# state panels, not a card).
	var tex: Texture2D = await _factory.render_texture(spec, RoomSpecs.BACK_FACE_PX)
	if tex == null or idx != _flip_idx or key != _flip_key:
		if _flip_render_key == key:
			_flip_render_key = ""
		return
	_flip_render_key = ""
	var real: bool = _tex_is_real(tex)
	if debug_gf4_nc == "solidboard" and real:
		# NC (PVLDS_GRADFIX4_NC=solidboard): the field's
		# fault, restored on the flip's back - the render
		# lands the factory's fallback solid and the
		# pre-GRADFIX4 bookkeeping counts it as the face, so
		# the heal never re-renders it and the blank-board
		# leg fails by name. Every render lands the solid
		# under the NC (the single-slot bookkeeping reason
		# is in the retired board render's history).
		tex = TextureFactory.make_solid(Color(0.055, 0.055, 0.095))
		real = true
	var bmat: StandardMaterial3D = nodes["back_mat"] as StandardMaterial3D
	# GRADFIX15 (item 1): only a real capture stamps the back
	# (the solidboard NC's counterfeit counts itself real
	# above, as its seam requires). A fallback landing leaves
	# the clear texture standing and tex_real false, so the
	# blank-back heal re-issues the render, bounded - a
	# frameless back never stands as a dark slab.
	if bmat != null and real:
		bmat.albedo_texture = tex
	nodes["back_key"] = key
	nodes["back_tex_real"] = real
	_flip_tex_key = key
	_flip_tex_real = real
	# GRADFIX13 (item 2): no back Launch exists to dress -
	# this tail runs only under the plinth NC, where the
	# minted button wears the same two faces as the front's
	# (the shared button cache), seated on the spec's
	# plinth; in the Tournament Room it stands only for a
	# challenge he owns - the board spec's own law, the
	# pick-side of which _apply_flip_side enforces.
	var blq: ClickableQuad = nodes["back_launch"] as ClickableQuad
	if blq != null:
		var failed: bool = _visible_games[idx].game_id == _failed_game_id
		var blabel: String = "FAILED" if failed else "LAUNCH"
		var bkey: String = blabel + "|" + ("a" if not failed else "p")
		var ltex: Texture2D = _btn_tex_cache.get(bkey) as Texture2D
		if ltex == null:
			ltex = await _factory.render_texture(
				RoomSpecs.button_spec(blabel, not failed), Vector2i(512, 164))
			if ltex != null:
				_btn_tex_cache[bkey] = ltex
		if ltex != null and idx == _flip_idx and key == _flip_key:
			blq.set_texture(ltex)


## The blank-back heal (the GRADFIX4 companions' heal, on
## the flipped card): while a back stands open, if its
## standing key's applied face is missing or a fallback
## solid, re-issue the render - throttled, and bounded per
## key so a truly broken renderer costs five renders, not
## a spin.
func _heal_card_back() -> void:
	if _flip_idx < 0 or not _flip_open or _flip_key == "" or _flip_render_key != "":
		return
	if _flip_tex_key == _flip_key and _flip_tex_real:
		return
	if _flip_retry_key != _flip_key:
		_flip_retry_key = _flip_key
		_flip_retries = 0
	if _flip_retries >= BOARD_TEX_MAX_RETRIES:
		return
	var now: int = Time.get_ticks_msec()
	if now - _flip_retry_msec < BOARD_TEX_RETRY_MS:
		return
	_flip_retry_msec = now
	_flip_retries += 1
	_refresh_card_back()


## The showing side of a panel, applied: past the turn's
## midpoint the BACK stands (front face, frame, plate,
## label and front Launch hidden; back assembly shown, its
## Launch pickable under the standing laws); before it, the
## FRONT stands and the back is hidden and unpickable.
## Called on every midpoint crossing and wherever a
## standing visibility changes underneath a flipped card
## (a face landing re-derives the plate - see _fill_one_face).
func _apply_flip_side(idx: int, back_up: bool) -> void:
	if idx < 0 or idx >= _panels.size():
		return
	var nodes: Dictionary = _flip_nodes(idx)
	var q: ClickableQuad = _panels[idx]
	if nodes.is_empty() or q == null:
		return
	q.set_face_shown(not back_up)
	var frame: MeshInstance3D = nodes.get("frame") as MeshInstance3D
	if frame != null:
		frame.visible = not back_up
	if idx < _panel_plates.size() and _panel_plates[idx] != null:
		# The plate/label follow the face fill's own law on
		# the front (an art face wears them, a title card
		# does not - _fill_one_face owns that fact via the
		# standing face key); the swap only ever ADDS the
		# back's claim: while the back is up both hide.
		var from_art: bool = str(_panel_face_key.get(_visible_games[idx].game_id, "")) != "" \
			and _panel_art_aspect[idx] > 0.0
		if OS.get_environment("PVLDS_GRAD_NC") == "noplate":
			from_art = false ## the nameplate NC's removal stands on both sides of the turn
		_panel_plates[idx].visible = not back_up and from_art
		_panel_labels[idx].visible = not back_up and from_art
	if idx < _panel_launches.size() and _panel_launches[idx] != null:
		_panel_launches[idx].pick_enabled = not back_up and _mode == "wall" \
			and _panels[idx].visible and not (_tournament and not _tournament_launchable(idx))
	var back: Node3D = nodes["back"] as Node3D
	if back != null:
		back.visible = back_up
	var blq: ClickableQuad = nodes["back_launch"] as ClickableQuad
	if blq != null:
		var launchable: bool = not _tournament or _tournament_launchable(idx)
		blq.visible = back_up and launchable
		blq.pick_enabled = back_up and launchable and _mode == "wall" and _panels[idx].visible


## The flip's cubic in-out ease: slow at both ends of the
## turn, honest speed through the edge-on midpoint - the
## "quick, neat" profile (FLIP_SEC for the whole half-turn).
static func flip_ease(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0


## Per-frame flip drive, from _update_pop beside the pop's
## own walk: the closing conditions are read fresh (the
## centre moved, the view left the wall), the progress
## walks toward its target, the pivot turns, and the
## showing side swaps at the midpoint. A resting room with
## no turn standing pays one comparison.
func _update_flip(delta: float) -> void:
	if _flip_idx < 0:
		return
	if _flip_idx >= _panels.size():
		_snap_flip_shut()
		return
	# Closing conditions: the centre left the flipped card,
	# or the room left the plain wall (detail, placard,
	# SETUP panel, the load wait). The turn closes; it never
	# holds the room hostage while doing so.
	if _flip_open and (_centre_index != _flip_idx or _mode != "wall" or _placard_up \
			or _setup_panel_up or _launching_game_id != ""):
		_flip_open = false
	var target: float = 1.0 if _flip_open else 0.0
	if _flip_t != target:
		var was_back: bool = _flip_t >= 0.5
		_flip_t = move_toward(_flip_t, target, delta / FLIP_SEC)
		var q: ClickableQuad = _panels[_flip_idx]
		if q != null:
			q.set_flip_angle(flip_ease(_flip_t) * PI)
			var is_back: bool = _flip_t >= 0.5
			if is_back != was_back:
				_apply_flip_side(_flip_idx, is_back)
	if _flip_t == 0.0 and not _flip_open:
		# The turn is home: clear the standing state (the
		# pivot already rests at 0 and the front stands).
		_flip_idx = -1
		_flip_key = ""
		_flip_tex_key = ""
		_flip_tex_real = false
		_flip_render_key = ""
	elif _flip_open:
		_heal_card_back()


## Smoke support: the flip's standing state - the turned
## card, the turn's progress and angle, which side shows,
## and the back's applied-texture bookkeeping (the heal's
## facts, readable: standing key, applied key, real or
## fallback).
func flip_state() -> Dictionary:
	var out: Dictionary = {
		"active": _flip_idx >= 0,
		"idx": _flip_idx,
		"t": _flip_t,
		"open": _flip_open,
		"angle_deg": 0.0,
		"back_up": _flip_t >= 0.5,
		"standing_key": _flip_key,
		"texture_key": _flip_tex_key,
		"texture_real": _flip_tex_real,
		"centre_index": _centre_index,
	}
	if _flip_idx >= 0 and _flip_idx < _panels.size():
		var q: ClickableQuad = _panels[_flip_idx]
		if q != null:
			out["angle_deg"] = rad_to_deg(q.flip_angle())
			out["game_id"] = _visible_games[_flip_idx].game_id
			var nodes: Dictionary = _flip_nodes(_flip_idx)
			if not nodes.is_empty():
				var back: Node3D = nodes["back"] as Node3D
				out["back_visible"] = back != null and back.visible
				var bmat: StandardMaterial3D = nodes["back_mat"] as StandardMaterial3D
				out["has_back_texture"] = bmat != null and bmat.albedo_texture != null
				out["back_texture"] = bmat.albedo_texture if bmat != null else null
				out["back_launch_pickable"] = (nodes["back_launch"] as ClickableQuad) != null \
					and (nodes["back_launch"] as ClickableQuad).pick_enabled
	return out


func _on_select(quad: ClickableQuad) -> void:
	if quad == null or not quad.pick_enabled:
		return
	_boot_guard = false ## a delivered select is a genuine act: the boot seating guard's work is done (see setup)
	_activate(quad)


func _activate(quad: ClickableQuad) -> void:
	if _setup_panel_up:
		# While the SETUP panel stands, its six buttons are
		# the room: everything else refuses. The pick flags
		# already say so for the pointer; this is the lock for
		# the keyboard/gamepad paths, which activate the
		# focused quad directly.
		match quad.action_id:
			"setup_panel_back":
				quad.pulse()
				hide_setup_panel()
			"setup_panel_scan":
				if not _setup_scanning:
					quad.pulse()
					setup_panel_scan_requested.emit()
			"setup_panel_download":
				if _setup_downloader != null and not _setup_downloader.is_downloading():
					quad.pulse()
					_start_setup_panel_download()
			"setup_panel_ipdb":
				quad.pulse()
				set_setup_panel_message("Re-applying the bundled IPDB snapshot - the coverage line below counts it...")
				setup_panel_ipdb_requested.emit()
			"setup_panel_wovp_paste":
				quad.pulse()
				_paste_wovp_key()
			"setup_panel_wovp_test":
				quad.pulse()
				set_setup_panel_message("Testing the saved WoVP key...")
				wovp_key_test_requested.emit()
			"setup_setting_stars":
				quad.pulse()
				var modes: Array[String] = ["layered", "flat", "off"]
				var next: String = modes[(modes.find(_starfield_mode) + 1) % modes.size()]
				set_starfield_mode(next)
				display_settings_changed.emit()
				_request_setup_panel_render(true)
			"setup_setting_wall_motion":
				quad.pulse()
				set_wall_motion_mode("stepped") ## OPTIMIZE: STEPPED is the only gait - the button stands as the panel's label, its press re-affirms the one mode
				display_settings_changed.emit()
				_request_setup_panel_render(true)
		return
	if _submit_panel_up:
		# ROOMSUBMIT: while the submit panel stands, its
		# stops are the room - the same lock the SETUP panel
		# keeps, for the same reason (the pick flags say it
		# for the pointer; this is the lock for the pad and
		# keyboard paths).
		match quad.action_id:
			"submit_shot":
				quad.pulse()
				_set_focused(quad) ## focus is the selection: the shot stands large (see _set_focused)
			"submit_send":
				quad.pulse()
				_submit_panel_send()
			"submit_back":
				quad.pulse()
				hide_submit_panel()
		return
	if _placard_up:
		# While the placard stands, everything else is inert. The
		# pick flags already say so for the pointer; this is the
		# lock for the keyboard/gamepad paths, which activate the
		# focused quad directly.
		if quad.action_id == "placard_back":
			quad.pulse()
			hide_setup_placard()
		return
	if _launching_game_id != "":
		# The load wait is deaf (see begin_launch): NO quad
		# activates until the wait settles - not EXIT, not SETUP,
		# not a card. Every input path funnels through here, so
		# this one refusal covers pointer, keyboard, and gamepad.
		return
	if _mode == "detail":
		if quad.action_id.begins_with("detail"):
			quad.pulse()
			_detail.handle(quad)
		return
	match quad.action_id:
		"panel":
			var game: GameEntry = _scanner.game_by_id(quad.payload)
			if game != null:
				quad.pulse()
				_open_detail(game)
		"panel_launch":
			var game2: GameEntry = _scanner.game_by_id(quad.payload)
			if game2 != null:
				var build: TableBuild = game2.resolve_default_build(_store)
				if build != null:
					quad.pulse()
					_selected_game_id = game2.game_id
					_persist_view()
					launch_requested.emit(game2, build)
		"rail":
			quad.pulse()
			_handle_rail(quad.payload)
		"letter":
			quad.pulse()
			_jump_to_letter(quad.payload)


## Launch the focused card's default build. Through
## GRADFIX12 this press routed through _activate on the
## card's own Launch quad - the path was literally the
## button's. GRADFIX13 (item 2) strips the plinth, so the
## press now does the button's work directly: the default
## build resolves, the selection persists, and
## launch_requested fires - the same outcome the button's
## "panel_launch" branch of _activate produced, minus the
## quad. (That branch survives for the plinth NC's minted
## buttons, whose pointer clicks still land on it.) The
## tournament law the button's visibility carried is
## applied here instead: a challenge he does not own does
## not launch. Only a PANEL focused in plain wall mode
## counts: rail focus, the detail view, and the SETUP
## placard all leave it inert, and the load wait refuses at
## the poll's deaf gate. A press that lands mid page-slide
## fires the card focus still sits on (the page on screen);
## the slide's pending travel then drops whole at its far
## point, by its own rule.
func _launch_focused_card() -> void:
	if _mode != "wall" or _placard_up or _setup_panel_up or _submit_panel_up or _focused == null:
		return
	var idx: int = _panels.find(_focused)
	if idx < 0 or idx >= _visible_games.size():
		return
	if _tournament and not _tournament_launchable(idx):
		return
	var game: GameEntry = _visible_games[idx]
	if game == null:
		return
	var build: TableBuild = game.resolve_default_build(_store)
	if build == null:
		return
	_selected_game_id = game.game_id
	_persist_view()
	launch_requested.emit(game, build)


## A on the pad (and Enter/Space on the keyboard, A's
## equivalent): the context press. On a wall card, A STARTS
## the card - it routes to _launch_focused_card above
## (Chris's ruling, 2026-10-26: "A should start, Y should be
## more info" - A is the button the thumb expects to mean
## go). Everywhere else A keeps the meaning it always had:
## activate the focused quad - rail stops, detail buttons,
## SETUP panel rows, the placard's BACK.
func _a_press() -> void:
	if _focused == null:
		return
	if _mode == "wall" and not _placard_up and not _setup_panel_up and not _submit_panel_up and _panels.has(_focused):
		_launch_focused_card()
	else:
		_activate(_focused)


## Y on the pad (and KEY_Y on the keyboard): FLIP the
## focused card (GRADFIX6 item 1 - Chris's ruling, 2026-10-31:
## "back to how we originally had the concept: Y button
## flips the card"). The card turns in its seat: the back
## carries the table's data (and its Launch button), a
## second Y turns it back. This replaces Y's More Info
## binding outright - the detail view still stands behind
## the pointer's click on a card, which is where build
## picking lives. Only a PANEL focused in plain wall mode
## counts: rail focus, the detail view, the SETUP panel,
## and the placard all leave Y inert, as does the load wait
## (the poll's deaf gate at the call site). Under the
## noflip NC the press is inert (the pre-flip world).
func _info_focused_card() -> void:
	if _tournament:
		# ROOMSUBMIT: Y in the Tournament Room opens the
		# SUBMIT panel for the focused challenge (see
		# _open_submit_for_focused). GRADFIX7's inertness
		# was about the FLIP - boards stand open beside
		# their cards, nothing needs turning - and the flip
		# stays refused here: no card turns in tournie,
		# ever. Y's new business is the panel, which is not
		# a flip: the board names the command itself
		# ("Y - SUBMIT A SCORE").
		_open_submit_for_focused()
		return
	if _mode != "wall" or _placard_up or _setup_panel_up or _focused == null:
		return
	if not _panels.has(_focused):
		return
	if _flip_disabled():
		return
	_toggle_flip(_panels.find(_focused))


## Rail handling. Page travel (page_prev / page_next) is the
## one branch that does not rebuild: it jumps the centre a
## page of shelf indices and the drum swings to it (see
## _page_travel). after_swap is a press's focus landing, run
## in the press's own frame; pointer and keyboard travel
## pass none.
func _handle_rail(key: String, after_swap: Callable = Callable()) -> void:
	if key.begins_with("filter:") or key == "sort" or key == "page_prev" or key == "page_next":
		# Browsing onward retires the last launch's marks.
		_failed_game_id = ""
		_status_note = ""
	if key.begins_with("filter:"):
		_filter = key.trim_prefix("filter:")
		_letter_net = "" ## a filter press leaves the net view: the wall it rebuilds is the filter's own set
		_exit_tournament() ## and the Tournament Room - the views are alternatives, never layers
		_page = 0
		_centre_index = 0
		_recompute_visible()
		_rebuild_wall()
		_persist_view()
		_land_on_rail_stop(key)
	elif key == "sort":
		var idx: int = SORTS.find(_sort)
		_sort = SORTS[(idx + 1) % SORTS.size()]
		_letter_net = "" ## a sort press leaves the net view too - the net's order was title order by definition
		_exit_tournament()
		_page = 0
		_centre_index = 0
		_recompute_visible()
		_rebuild_wall()
		_persist_view()
		_land_on_rail_stop(key)
	elif key == "tournament":
		if _tournament:
			# Already standing in it: the press is a refresh
			# (the same ask REFRESH makes), focus unmoved.
			tournament_refresh_requested.emit()
			_land_on_rail_stop(key)
		else:
			_enter_tournament()
	elif key == "wovp_refresh":
		# A stop in every view (GRADFIX16 item 1): the press
		# asks Main to re-pull the WoVP boards wherever it is
		# pressed from, and focus lands on the stop pressed.
		tournament_refresh_requested.emit()
		_land_on_rail_stop(key)
	elif key == "page_prev":
		if _page > 0:
			_page_travel(-1, _page_travel_landing(key, after_swap))
	elif key == "page_next":
		if _page < page_count() - 1:
			_page_travel(1, _page_travel_landing(key, after_swap))
	elif key == "desk":
		# SETUP: in the headset the operations live in the room
		# now (the SETUP panel - the view may bend, it may not
		# break); flat, the desk pass takes the viewport as
		# always (Main routes the signal).
		if _xr_enabled:
			show_setup_panel()
		else:
			setup_requested.emit()
	elif key == "exit":
		exit_requested.emit()


## A rail activation keeps focus on the bar (Chris's field
## report, 2026-10-25): a filter or sort press rebuilds the
## wall, and the rebuild drops focus - the next step then
## landed on the first card at the top of the window, and the
## player had to tap tap tap back down to the bar they were
## just using. The landing rule for rail-caused rebuilds:
## focus takes the SAME stop that was activated (the rail is
## persistent furniture, so the quad is the same instance),
## whether the press came from the pad's focus or the pointer.
## Page travel keeps its own landing (the bumper rule), and
## rebuilds with other causes - detail close, launch failure,
## library refresh - keep the landings they already had.
func _land_on_rail_stop(key: String) -> void:
	var rq: ClickableQuad = _rail_quads.get(key) as ClickableQuad
	if rq != null:
		_set_focused(rq)


## The focus landing a page-travel press rides with. A press
## that brings its own (the bumpers') keeps it - focus keeps
## its PLACE across a bumper flip, untouched. A press without
## one (the pad or the pointer activating the arrow itself)
## lands on the arrow that was pressed, at the slide's far
## point: the landing rule above was wired for filter and
## sort in the 2026-10-25 round but never for page travel,
## so an arrow press rebuilt the wall at the far point,
## the rebuild cleared focus to nothing, and the player's
## next step landed on the first card at the top of the
## wall - "tap-tap-tap back down to arrow" (Chris,
## 2026-10-27). The hole is older than the letter round:
## the same shape stands at 25fd4e5 (the rebuild's focus
## clear, the arrow's landingless call, the filter/sort-only
## landing). A clamped press (first/last page) starts no
## slide and no rebuild, so focus never leaves the arrow
## there either. The NC value "pager" drops the landing,
## restoring the hole for the harness.
func _page_travel_landing(key: String, after_swap: Callable) -> Callable:
	if after_swap.is_valid():
		return after_swap
	if debug_focus_nc == "pager":
		return Callable()
	return Callable(self, "_land_on_rail_stop").bind(key)


## X on the pad (and KEY_X on the keyboard): toggle the
## focused card's favorite, through the same store the detail
## view's Favorite quad writes - so the wall, the detail view,
## and the file on disk never disagree - persisted on the
## spot, like the detail toggle. Only a PANEL focused in plain
## wall mode counts: rail focus, the detail view (its own
## Favorite quad owns the toggle there), the SETUP placard,
## and the load wait all leave X inert.
##
## The card's face re-renders in place so the favorite mark
## (the panel face's FAVORITE chip, the art face's star badge)
## appears or clears where the player is looking. The one
## structural case: X-ing OFF a card while browsing the
## FAVORITES filter removes the card from the visible set, so
## the wall recomputes and rebuilds; the landing rule there is
## the panel that took the removed card's slot, clamped to the
## wall's last panel - and if the set emptied, the recompute's
## empty-filter guard has already fallen back to ALL, whose
## first panel takes the focus.
func _toggle_focused_favorite() -> void:
	if _mode != "wall" or _placard_up or _setup_panel_up or _launching_game_id != "" or _focused == null or _tournament:
		# The Tournament Room is a standings surface, not a
		# browsing one: X is inert there (a board face carries
		# no favorite mark to flip, and the in-place re-render
		# would paint a game face over the board).
		return
	var idx: int = _panels.find(_focused)
	if idx < 0:
		return
	if idx >= _visible_games.size():
		return
	var game: GameEntry = _visible_games[idx]
	var now_on: bool = not _store.is_favorite(game.game_id)
	_store.set_favorite(game.game_id, now_on)
	_store.save_to_disk()
	if _filter == "favorites" and not now_on:
		_recompute_visible()
		_rebuild_wall()
		_persist_view()
		if not _panels.is_empty():
			var land: int = mini(idx, _panels.size() - 1)
			_set_centre(land, true)
			_set_focused(_panels[land])
		return
	_rerender_panel_face(idx)


## Re-render one wall panel's face in place (the X favorite
## toggle's feedback): the face key carries the favorite
## flag, so the window fill's one-face path re-renders it -
## same ranking, same strip law, same power-on debt settling
## as any face arrival.
func _rerender_panel_face(idx: int) -> void:
	_fill_one_face(idx, _gen)


## A page change's ride on the drum: the centre jumps one
## page of shelf indices (PAGE_SIZE) and the drum SWINGS to
## it - the flat wall's out-and-back slide is retired with
## the wall itself; travel on a standing wall is always the
## swing now. The press's focus landing runs in the same
## frame (the drum glides under it): the rail/bumper landing
## laws are unchanged, only their timing - there is no far
## point on a drum, because there is no swap. A press that
## lands mid-swing simply retargets the swing.
func _page_travel(step: int, after_swap: Callable) -> void:
	if _mode != "wall" or _placard_up or _setup_panel_up or _launching_game_id != "":
		return
	var target_page: int = clampi(_page + step, 0, page_count() - 1)
	var idx: int = clampi(target_page * PAGE_SIZE, 0, maxi(0, _visible_games.size() - 1))
	_set_centre(idx)
	_persist_view()
	if after_swap.is_valid():
		after_swap.call()
	elif debug_focus_nc == "pager" and not _panels.is_empty():
		# The NC's fault, restated for the drum: the flat
		# wall lost the arrow because its page swap rebuilt
		# the wall and the rebuild cleared focus; the drum
		# has no rebuild in its page travel, so the hole
		# cannot reopen on its own - the control drops the
		# focus itself, and the letters leg must convict
		# the drop by name.
		_set_focused(_panels[0])


## The strip's pickable slots, in drawn order: the ONE list
## (slot_keys) filtered to slots that are laid out (visible)
## and lit (pick_enabled) in the current view - the same
## truth _refresh_focusables admits as focus stops. The NC
## value "greyanchors" drops the pick filter, so the anchor
## math runs over greyed slots too and the letters smoke's
## anchor legs fail by name.
func _strip_pickable_keys() -> Array[String]:
	var out: Array[String] = []
	for key: String in _strip_slot_keys():
		var q: ClickableQuad = _strip_quads.get(key) as ClickableQuad
		if q == null or not q.visible:
			continue
		if debug_focus_nc != "greyanchors" and not q.pick_enabled:
			continue
		out.append(key)
	return out


## A TRIGGER press inside the strip country: focus hops
## to the nearest anchor strictly in the press's direction
## over the pickable slots - first, middle, last
## (LetterIndex.anchor_target owns the math, the middle
## rule included, THE-as-net and the clamp law with it).
## POSITIONAL, NO MEMORY: the anchors are recomputed from
## the standing presence on every press, so a filter
## change between presses is absorbed by the next press
## without any state to go stale. Only strip focus moves -
## the wall never turns - and a press at the far anchor
## clamps, spent, focus staying put.
##
## GRADFIX14 SUPERSESSION (a), stated plainly (Chris,
## 2026-11-01): this hop USED to live on the strip's
## BUMPERS (the bumper-anchors round, 2026-10-28, field-
## passed 2026-10-29 - bumpers on the strip should "move
## you to middle, then end"). Under the unified travel
## grammar the hop MOVES to the triggers, unchanged in
## every other respect; the strip's bumpers become
## single-slot steps (see _bumper_page). The NC value
## "stripanchor" (PVLDS_GF14_NC) puts the hop back on the
## bumpers so the grammar legs fail by name.
func _strip_anchor_step(step: int) -> void:
	var current: String = ""
	for k: Variant in _strip_quads.keys():
		if _strip_quads[k] == _focused:
			current = str(k)
			break
	if current == "":
		return
	var target: String = LetterIndex.anchor_target(_strip_pickable_keys(), current, step)
	if target == "":
		return ## clamped at the far anchor (or a degenerate strip): the press is spent
	var q: ClickableQuad = _strip_quads.get(target) as ClickableQuad
	if q != null:
		_set_focused(q)


## The rail stops focus can actually stand on right now,
## in RAIL_FOCUS_ORDER order: the same admission the
## sideways walk uses (pickable and in the focusable set -
## wovp_refresh stands in every view since GRADFIX16
## item 1). The rail's trigger anchors are computed over
## THIS live list, recomputed on every press, so a view
## change between presses is absorbed with no state to go
## stale (the strip anchors' positional rule, carried to
## the rail).
func _rail_focusable_keys() -> Array[String]:
	var out: Array[String] = []
	for key: String in RAIL_FOCUS_ORDER:
		var q: ClickableQuad = _rail_quads.get(key) as ClickableQuad
		if q != null and q.pick_enabled and _focusables.has(q):
			out.append(key)
	return out


## The rail's anchors (GRADFIX14 item 3): first, middle
## and last of the live rail stops - the middle at index
## (count - 1) / 2 of the list, the wall/strip middle rule
## carried to the rail. Ten stops stand in both views
## since GRADFIX16 item 1 (REFRESH live over the library
## too), and the anchors are filter:all / filter:new /
## exit in both. Fewer than three live stops degenerate
## honestly, exactly as the wall's column anchors do.
func rail_anchor_keys() -> Array[String]:
	var stops: Array[String] = _rail_focusable_keys()
	var out: Array[String] = []
	if stops.is_empty():
		return out
	out.append(stops[0])
	if stops.size() >= 2:
		var mid: String = stops[(stops.size() - 1) / 2]
		if not out.has(mid):
			out.append(mid)
		var last: String = stops[stops.size() - 1]
		if not out.has(last):
			out.append(last)
	return out


## The rail key a quad answers to, or "" when it is not a
## rail quad.
func _rail_key_of_quad(q: ClickableQuad) -> String:
	for k: Variant in _rail_quads.keys():
		if _rail_quads[k] == q:
			return str(k)
	return ""


## A TRIGGER press with a rail stop focused (GRADFIX14
## item 3): focus hops the rail's anchors - first / middle
## / last of the live stops (rail_anchor_keys). The travel
## rule MIRRORS THE WALL'S trigger rule exactly: from a
## non-anchor stop, the nearest anchor STRICTLY in the
## travel direction, wrapping to the far anchor when none
## lies that way; a press while ON an anchor advances to
## the next one, never a no-op, wraps included.
##
## THE RAIL ANALOGUE of the wall law's landing rule,
## stated: the wall's landing preserves the focused ROW
## (band) and the drum centres the column focus lands in.
## The rail is a single row, so there is no band to
## preserve - the landing IS the anchor stop itself, the
## exact quad - and, the mirror image of the wall's
## centre-follows rule, NOTHING follows it: rail focus
## never drives the drum, so the centre index, the swing
## target and the page stand byte-identical across the
## hop, and no filter/sort/view state changes (a hop lands
## ON a stop; it never presses it). With fewer than two
## anchors standing the press is spent (the wall's
## single-column rule, carried over).
func _rail_anchor_step(step: int) -> void:
	var current: String = _rail_key_of_quad(_focused)
	if current == "":
		return
	var stops: Array[String] = _rail_focusable_keys()
	var idx: int = stops.find(current)
	if idx < 0:
		return ## the focused stop is not standing in this view: spent
	var anchors: Array[String] = rail_anchor_keys()
	if anchors.size() < 2:
		return ## nowhere to cycle to: the press is spent
	var target: String = ""
	if step > 0:
		for a: String in anchors:
			if stops.find(a) > idx:
				target = a
				break
		if target == "":
			target = anchors[0] ## wrap: last stop -> first anchor
	else:
		for i: int in range(anchors.size() - 1, -1, -1):
			if stops.find(anchors[i]) < idx:
				target = anchors[i]
				break
		if target == "":
			target = anchors[anchors.size() - 1] ## wrap: first stop -> last anchor
	var q: ClickableQuad = _rail_quads.get(target) as ClickableQuad
	if q != null:
		_set_focused(q)


## A bumper press (GRADFIX14 item 3 - the UNIFIED TRAVEL
## GRAMMAR, Chris, 2026-11-01: "the right bumpers continue
## to navigate the wall while you're down there... If you
## go down to letters, you have to tap-tap-tap through each
## letter"). Controls follow focus - ONE grammar in every
## zone:
## - WALL focus: page travel, UNCHANGED (below): the
##   centre jumps one page of shelf indices (Chris's
##   clarification, 2026-10-24 - the bumpers flip PAGES,
##   never filters; the filters change only via the rail).
##   CLAMPED at both ends, no wrap; focus keeps its PLACE
##   across the flip - a focused panel hands focus to the
##   panel one page over FROM IT (its own index ±
##   PAGE_SIZE, clamped to the shelf's last panel); no
##   focus lands on the first panel of the new centre's
##   window; a clamped press changes nothing at all.
## - RAIL focus: ONE STOP along the rail (the sideways
##   walk's own step, clamps at the rail's ends). The wall
##   does NOT move - no centre, page or filter change.
## - STRIP focus: ONE SLOT along the strip (the sideways
##   walk's own step, greyed slots skipped, clamps at the
##   strip's ends). The wall does NOT move.
## - TOURNAMENT block focus: ONE CARD COLUMN within the
##   block (the pair grid's own sideways step - nearest
##   card column, board columns skipped, band nearest,
##   ends clamp). See the tournament note in the code.
## Inert under the room's standing input law, as shipped:
## the load wait is deaf, the SETUP placard/panel own the
## room, and the detail view is not the wall.
##
## GRADFIX14 SUPERSESSIONS, stated plainly:
## (a) the strip's bumper anchor-hops (field-passed
##     2026-10-29) MOVE to the triggers - strip bumpers
##     are single-slot steps now (NC "stripanchor"
##     restores the hops here);
## (b) rail-focus bumpers STOP driving the wall: the
##     shipped law below kept the rail stop and jumped
##     the centre a page - that branch is gone (NC
##     "railwall" restores it);
## (c) the triggers stop being inert under rail/strip
##     focus - they hop those zones' anchors now (see
##     _trigger_anchor; NC "bartriginert" restores the
##     inertness).
## NOTHING in the bar zone (rail or strip focus) moves
## the wall; nothing on the wall reaches the bar.
func _bumper_page(step: int) -> void:
	if _launching_game_id != "" or _placard_up or _setup_panel_up or _submit_panel_up or _mode != "wall":
		return
	# The strip country spends its bumpers at home
	# (GRADFIX14 supersession (a)): one slot along the
	# strip, the wall untouched. The NC restores the
	# shipped anchor-hop here.
	if _focused != null and _is_strip_quad(_focused):
		if debug_gf14_nc == "stripanchor":
			_strip_anchor_step(step)
			return
		var nq: ClickableQuad = _rail_focus_neighbour(step)
		if nq != null:
			_set_focused(nq)
		return
	# The rail spends its bumpers at home (GRADFIX14
	# supersession (b)): one stop along the rail, the wall
	# untouched. The NC restores the shipped behaviour -
	# the rail branch of the page-travel law below.
	if _focused != null and _is_rail_quad(_focused) and debug_gf14_nc != "railwall":
		var rq: ClickableQuad = _rail_focus_neighbour(step)
		if rq != null:
			_set_focused(rq)
		return
	if _visible_games.is_empty():
		return
	_failed_game_id = ""
	_status_note = ""
	if _focused != null and _panels.has(_focused):
		# TOURNAMENT BUMPERS, stated: today (pre-GRADFIX14)
		# a bumper on a block card ran the page law below -
		# index ± PAGE_SIZE clamped to the block, which on a
		# block smaller than a page is a jump to the far end,
		# not a step. The grammar's consistent form: bumpers
		# step WITHIN the block, one card column (the pair
		# grid's own sideways step, _tourn_side_step), ends
		# clamped, focus following to the stepped column's
		# band-nearest card. The library wall below keeps
		# its page travel untouched.
		if _tournament:
			var tpidx: int = _panels.find(_focused)
			var tnidx: int = _tourn_side_step(tpidx, step)
			if tnidx != tpidx and tnidx >= 0 and tnidx < _panels.size():
				_set_focused(_panels[tnidx])
			return
		var from: int = _panels.find(_focused)
		var target: int = clampi(from + step * PAGE_SIZE, 0, _visible_games.size() - 1)
		if target == from:
			return ## clamped at the shelf's end: the press is spent
		_set_centre(target)
		_set_focused(_panels[target])
		_persist_view()
	elif _focused != null and _is_rail_quad(_focused):
		# Reached only under the NC (supersession (b)'s
		# pre-fix shape): rail focus keeps its stop while
		# the centre jumps a page.
		var target_page: int = clampi(_page + step, 0, page_count() - 1)
		if target_page == _page:
			return
		_set_centre(clampi(target_page * PAGE_SIZE, 0, _visible_games.size() - 1))
		_persist_view()
	else:
		var target_page2: int = clampi(_page + step, 0, page_count() - 1)
		if target_page2 == _page:
			return
		var idx: int = clampi(target_page2 * PAGE_SIZE, 0, _visible_games.size() - 1)
		_set_centre(idx)
		_set_focused(_panels[idx])
		_persist_view()


## The trigger threshold (GRADFIX10 item 4): a joypad
## trigger axis reads DOWN past this value - the same 0.55
## the stick's directional deadzone uses, so the pad's
## analog controls share one "meant it" line.
const TRIGGER_PRESS_THRESHOLD: float = 0.55


## The distinct columns the standing view's CARDS occupy,
## in shelf order: every column of the shelf in the library
## (0 .. _columns-1 - the last may stand partial), and in
## the Tournament view only the pair block's card columns
## (board columns carry no card and are never columns a
## focus can land in).
func _card_columns() -> Array[int]:
	var out: Array[int] = []
	if _tournament:
		var seen: Dictionary = {}
		for i: int in range(_visible_games.size()):
			var c: int = _grid_coord(i).x
			if not seen.has(c):
				seen[c] = true
				out.append(c)
		out.sort()
		return out
	for c: int in range(maxi(0, _columns)):
		out.append(c)
	return out


## The wall anchors over a column list (GRADFIX10 item 4):
## first, middle and last - the middle at index
## (count - 1) / 2 of the list, the letter strip's own
## middle rule (LetterIndex.anchor_keys) carried to the
## wall. Fewer than three distinct columns degenerate
## honestly: two columns give two anchors (no centre
## exists to name), one column gives one.
func _wall_anchor_columns() -> Array[int]:
	var cols: Array[int] = _card_columns()
	var out: Array[int] = []
	if cols.is_empty():
		return out
	out.append(cols[0])
	if cols.size() >= 2:
		var mid: int = cols[(cols.size() - 1) / 2]
		if not out.has(mid):
			out.append(mid)
		var last: int = cols[cols.size() - 1]
		if not out.has(last):
			out.append(last)
	return out


## The standing view's wall anchors (the input smoke reads
## the room's anchors the way the other smokes read theirs).
func wall_anchor_columns() -> Array[int]:
	return _wall_anchor_columns()


## One trigger press's wall-anchor step (GRADFIX10 item 4):
## focus jumps to the next anchor in the press's direction -
## RT steps forward (left -> middle -> right -> wraps to
## left), LT steps backward (right -> middle -> left ->
## wraps to right). FROM A NON-ANCHOR COLUMN the rule is
## the nearest anchor STRICTLY in the travel direction,
## wrapping to the far anchor when none lies that way (the
## strip anchors' positional rule, with wrap in place of
## their clamp - a cycle, Chris's word, never dead-ends).
## A press while ON an anchor advances to the next one,
## never a no-op, wraps included.
##
## LANDING: the focused ROW (band) is kept - the landing
## panel is the anchor column's card on the same band when
## the column has one; at the shelf's edge geometry, where
## the anchor column stands partial (the last column of a
## shelf whose count is not a multiple of the band count),
## the landing is that column's card NEAREST the focused
## band. _set_centre + focus together: per the focus law
## the drum centres the anchor column the focus lands in.
##
## Gating and scope, stated as decisions:
## - The load wait is deaf, the SETUP placard/panel own the
##   room, and the detail view is not the wall: inert there
##   (the bumper law, shared).
## - GRADFIX14 (item 3, the unified travel grammar): the
##   triggers hop the FOCUSED zone's anchors in every
##   zone. A CARD focus rides the wall anchors (below,
##   unchanged). A RAIL focus hops the rail's anchors
##   (first / middle / last of the live rail stops - see
##   _rail_anchor_step for the travel rule and the rail
##   analogue of this landing law). A STRIP focus hops
##   the strip's pickable anchors (see _strip_anchor_
##   step - the hop the bumpers used to own).
##   SUPERSESSION (a): the strip's anchor hop moved from
##   the bumpers to these triggers.
##   SUPERSESSION (c): the triggers STOP being inert
##   under rail/strip focus - the shipped scope note here
##   read "with the rail or a strip slot focused the
##   press is inert", and that is gone (the NC value
##   "bartriginert" restores it). NOTHING in the bar zone
##   moves the wall on a trigger press either: the rail
##   hop lands on a stop (it never presses it) and the
##   strip hop lands on a slot, both with the drum
##   standing byte-identical.
## - TOURNAMENT VIEW (the decision, unchanged): the
##   block's card columns are few (the crew fixture's
##   cards stand in three columns; Chris's live set in
##   two), so three library anchors would degenerate
##   there. The triggers map to the BLOCK'S OWN anchors
##   instead - first / middle / last of the card columns
##   actually standing (two columns: left/right only; one
##   column: no anchors to cycle, the press is spent).
##   Same cycle, same wrap, same band rule, over the
##   block's own geometry - never a fall-through to the
##   library's shelf columns, which do not exist in this
##   view. The grammar reconciles as: anchors = the
##   focused block's own columns.
func _trigger_anchor(step: int) -> void:
	if _launching_game_id != "" or _placard_up or _setup_panel_up or _submit_panel_up or _mode != "wall":
		return
	if _focused == null:
		return
	# The bar countries spend their triggers at home
	# (GRADFIX14 supersession (c)): the rail hops its own
	# anchors, the strip hops its own pickable anchors,
	# and neither moves the wall. The NC restores the
	# shipped inertness under bar focus.
	if _is_rail_quad(_focused):
		if debug_gf14_nc != "bartriginert":
			_rail_anchor_step(step)
		return
	if _is_strip_quad(_focused):
		if debug_gf14_nc != "bartriginert":
			_strip_anchor_step(step)
		return
	var pidx: int = _panels.find(_focused)
	if pidx < 0:
		return ## no country owns this focus (a detail/placard quad): inert
	var anchors: Array[int] = _wall_anchor_columns()
	if anchors.size() < 2:
		return ## a single standing column has nowhere to cycle to
	var coord: Vector2i = _grid_coord(pidx)
	var target_col: int = -1
	if step > 0:
		for a: int in anchors:
			if a > coord.x:
				target_col = a
				break
		if target_col < 0:
			target_col = anchors[0] ## wrap: right end -> left end
	else:
		for i: int in range(anchors.size() - 1, -1, -1):
			if anchors[i] < coord.x:
				target_col = anchors[i]
				break
		if target_col < 0:
			target_col = anchors[anchors.size() - 1] ## wrap: left end -> right end
	var best: int = -1
	var best_d: int = 999999
	for i: int in range(_panels.size()):
		var c2: Vector2i = _grid_coord(i)
		if c2.x != target_col:
			continue
		var d: int = absi(c2.y - coord.y)
		if d < best_d:
			best_d = d
			best = i
	if best < 0 or best == pidx:
		return
	_set_centre(best)
	_set_focused(_panels[best])
	_persist_view()


func _open_detail(game: GameEntry) -> void:
	_mode = "detail"
	_selected_game_id = game.game_id
	_store.touch_recent(game.game_id)
	_persist_view()
	for q: ClickableQuad in _panels:
		q.pick_enabled = false
	for q: ClickableQuad in _panel_launches:
		if q != null:
			q.pick_enabled = false
	for q: ClickableQuad in _panel_back_launches:
		if q != null:
			q.pick_enabled = false
	for k: Variant in _rail_quads.keys():
		_rail_quads[k].pick_enabled = false
	for skey: Variant in _strip_quads.keys():
		var sq: ClickableQuad = _strip_quads[skey] as ClickableQuad
		if sq != null:
			sq.pick_enabled = false
	_detail.show_game(game)
	_set_focused(null)
	_refresh_focusables()


## Detail Play forwards into the same launch path as the card's
## Launch button (default build, or the armed play-once build).
func _on_detail_play(game: GameEntry, build: TableBuild) -> void:
	_selected_game_id = game.game_id
	_persist_view()
	launch_requested.emit(game, build)


# ------------------------------------------------------- setup placard

## SETUP while XR is live (Main routes here): the desk itself is a
## 2D form in the root viewport and cannot reach the headset, so the
## room stays up and this placard stands in it - the explanation,
## plus the way back. While it stands, every other control in the
## room is inert: pick flags down (the snapshot restores them on
## the way out), focus confined to BACK, and _activate refuses
## everything else. A Launch fired blind behind a setup session
## would be a state bug waiting to happen.
func show_setup_placard(message: String = "") -> void:
	_placard_message = message
	if _placard == null:
		_build_placard()
	if not _placard_up:
		_pick_snapshot.clear()
		for q: ClickableQuad in _room_pickables():
			_pick_snapshot[q] = q.pick_enabled
		_placard_up = true
		add_child(_placard)
		ClickableQuad.face_point(_placard, EYE)
		_inert_room_quads()
	_refresh_focusables()
	_set_focused(_placard_back)
	_placard_gen += 1
	_fill_placard_textures(_placard_gen, message)


## The placard's BACK: tear it down, hand the room back, and tell
## Main to close the desk it opened alongside.
func hide_setup_placard() -> void:
	if not _placard_up:
		return
	clear_setup_placard()
	setup_placard_dismissed.emit()


## Silent teardown for Main's own routes (Enter the Room on the
## desk, a fresh room entry): no signal - Main is already driving,
## and entering the room must never find a stale placard standing.
func clear_setup_placard() -> void:
	if not _placard_up:
		return
	_placard_up = false
	_placard_gen += 1
	if _placard != null:
		# Freed, not parked: an out-of-tree holder kept alive
		# orphans its meshes/materials/textures, and the renderer
		# teardown choked on them at exit (exported-build crash,
		# placard round). The detail view frees its quads the
		# same way; a rebuild on the next show costs nothing.
		if _placard.get_parent() != null:
			remove_child(_placard)
		_placard.queue_free()
		_placard = null
		_placard_face = null
		_placard_back = null
	_restore_room_pick_states()
	_set_focused(null)
	_refresh_focusables()


func is_setup_placard_up() -> bool:
	return _placard_up


func setup_placard_back_quad() -> ClickableQuad:
	return _placard_back


func setup_placard_message() -> String:
	return _placard_message


func _build_placard() -> void:
	_placard = Node3D.new()
	_placard.name = "SetupPlacard"
	_placard.position = Vector3(0.0, 1.32, -1.72)
	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	_placard_face = ClickableQuad.new()
	_placard_face.setup("placard_face", "", placeholder, Vector2(1.3, 0.64))
	_placard_face.position = Vector3(0.0, 0.17, 0.0)
	_placard_face.pick_enabled = false
	_placard.add_child(_placard_face)
	_placard_back = ClickableQuad.new()
	_placard_back.setup("placard_back", "", placeholder, Vector2(0.44, 0.15))
	_placard_back.position = Vector3(0.0, -0.30, 0.0)
	_placard.add_child(_placard_back)
	# No face_point here: the holder is oriented in
	# show_setup_placard, once it is inside the tree (look_at on
	# an out-of-tree node just errors and does nothing).


func _fill_placard_textures(gen: int, message: String) -> void:
	var tex: Texture2D = await _factory.render_texture(RoomSpecs.placard_spec(message), Vector2i(1024, 504))
	if gen != _placard_gen or not _placard_up or _placard_face == null:
		return
	_placard_face.set_texture(tex)
	var btex: Texture2D = await _factory.render_texture(RoomSpecs.button_spec("BACK", true), Vector2i(512, 164))
	if gen != _placard_gen or not _placard_up or _placard_back == null:
		return
	_placard_back.set_texture(btex)


## Every quad the placard stands in front of, in one list: the
## pick-state snapshot and the inert sweep share it.
func _room_pickables() -> Array[ClickableQuad]:
	var out: Array[ClickableQuad] = []
	out.append_array(_panels)
	for lq3: ClickableQuad in _panel_launches:
		if lq3 != null:
			out.append(lq3)
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null:
			out.append(rq)
	for skey: Variant in _strip_quads.keys():
		var sq: ClickableQuad = _strip_quads[skey] as ClickableQuad
		if sq != null:
			out.append(sq)
	if _detail != null:
		out.append_array(_detail.get_clickables())
	for blq: ClickableQuad in _panel_back_launches:
		if blq != null:
			out.append(blq)
	return out


func _inert_room_quads() -> void:
	for q: ClickableQuad in _room_pickables():
		q.pick_enabled = false


func _restore_room_pick_states() -> void:
	var handled: Array[ClickableQuad] = []
	for key: Variant in _pick_snapshot.keys():
		if not is_instance_valid(key):
			continue
		var q: ClickableQuad = key as ClickableQuad
		if q == null:
			continue
		q.pick_enabled = bool(_pick_snapshot[key])
		handled.append(q)
	_pick_snapshot.clear()
	# Quads born while the placard stood (a wall rebuild on the
	# launch-failure path) hold no snapshot entry; they take the
	# state the room's current mode would have built them with.
	var launching: bool = _launching_game_id != ""
	for q: ClickableQuad in _panels:
		if not handled.has(q):
			q.pick_enabled = not launching
	for q: ClickableQuad in _panel_launches:
		if q != null and not handled.has(q):
			q.pick_enabled = not launching
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null and not handled.has(rq):
			if launching:
				rq.pick_enabled = false ## the load wait is deaf: no rail quad picks, EXIT/SETUP included
			elif str(k) == "wovp_refresh":
				rq.pick_enabled = _refresh_pickable() ## GRADFIX16 item 1: a REFRESH born behind the placard takes the standing view's state, not the blanket rail reset
			else:
				rq.pick_enabled = str(k) != "page_label"
	# The strip's slots take the state the room's current view
	# would have built them with: pickable exactly when their
	# letter has games in the filter's set (greyed is not a
	# stop), and never during the load wait.
	if not _strip_quads.is_empty():
		var strip_presence: Dictionary = LetterIndex.presence_over(_collect_filtered()) if _scanner != null else {}
		for skey: Variant in _strip_quads.keys():
			var sq: ClickableQuad = _strip_quads[skey] as ClickableQuad
			if sq != null and not handled.has(sq):
				sq.pick_enabled = not launching and sq.visible and strip_presence.has(str(skey))


# ------------------------------------------------------- setup panel

## SETUP while XR is live (the rail routes here): the desk
## pass cannot reach the headset, and the old answer - a
## placard sending the player to the desktop - broke the
## room's standing law (the view may bend, it may not break;
## Chris's ruling, 2026-10-24). The operations live in the
## room now, on one panel in the placard's presentation
## family, front and center at reading distance:
##   SCAN LIBRARY - Main's scan, the desk's own machinery
##     (setup_panel_scan_requested), with its progress on the
##     message line and its landing refreshing the wall
##     behind the panel;
##   the library's health in words on the face - tables
##     found, database matches, the missing-backglass count
##     (the list itself is regenerated by the scan as always;
##     the panel names where it lives and NEVER shell-opens
##     anything - no desktop trips from inside VR);
##   DOWNLOAD VPS DATABASE - the desk's download, shared
##     (VpsDownloader);
##   a message line carrying the last action's outcome in
##     plain words;
##   BACK - closes the panel, focus returns to the rail's
##     SETUP stop.
## Clean and CLEAR (Chris, 2026-10-25 - "make it look clean,
## and CLEAR. People are dumb... though by its nature, VPX
## people are not quite as dumb"): one action per row,
## generous spacing, every row saying what it does and
## showing its state, working faces while work runs - and
## the hobby's own words (VPS, backglass, .vpx) stay.
## Path editing and first-run configuration stay on the
## desktop desk - set-once typing that wants a keyboard -
## and the flat route to it is untouched.
##
## While the panel stands, the room behind it is inert,
## exactly as behind the placard: pick flags down (the
## snapshot restores them on the way out), focus confined
## to the panel's six buttons, _activate refusing
## everything else, launching unreachable, and B / D-pad
## Right acting as BACK - the panel never exits the app.
func show_setup_panel() -> void:
	if _setup_panel == null:
		_build_setup_panel()
	if not _setup_panel_up:
		_pick_snapshot.clear()
		for q: ClickableQuad in _room_pickables():
			_pick_snapshot[q] = q.pick_enabled
		_setup_panel_up = true
		add_child(_setup_panel)
		ClickableQuad.face_point(_setup_panel, EYE)
		_inert_room_quads()
	_refresh_focusables()
	_set_focused(_setup_panel_scan_btn)
	_request_setup_panel_render(true)


## The panel's BACK: tear it down, hand the room back, and
## land focus on the rail's SETUP stop - the stop that
## opened it (the rail-landing rule). The close contract
## (Chris, 2026-10-25): exiting setup ALWAYS lands on the
## Table Select wall - if a scan landed while the panel
## stood, clear_setup_panel has just rebuilt that wall once
## from the new scan; the player never returns to a leftover
## panel, marquee, or placard arrangement.
func hide_setup_panel() -> void:
	if not _setup_panel_up:
		return
	clear_setup_panel()
	_land_on_rail_stop("desk")


## Silent teardown for Main's own routes (a fresh room
## entry): no landing - Main is already driving, and
## entering the room must never find a stale panel standing.
func clear_setup_panel() -> void:
	if not _setup_panel_up:
		return
	_setup_panel_up = false
	_setup_panel_gen += 1
	if _setup_panel != null:
		# Freed, not parked - the placard's rule (see
		# clear_setup_placard): parked holders orphan their
		# meshes at renderer teardown.
		if _setup_panel.get_parent() != null:
			remove_child(_setup_panel)
		_setup_panel.queue_free()
		_setup_panel = null
		_setup_panel_face = null
		_setup_panel_scan_btn = null
		_setup_panel_dl_btn = null
		_setup_panel_wovp_paste_btn = null
		_setup_panel_wovp_test_btn = null
		_setup_panel_ipdb_btn = null
		_setup_panel_back_btn = null
	_restore_room_pick_states()
	_set_focused(null)
	_refresh_focusables()
	if _pending_library != null:
		# The deferred adoption lands exactly once, here, with
		# the panel already down: the wall the player returns
		# to is built from the scan that landed behind the
		# panel - never rebuilt piecemeal behind it while it
		# stood. hide_setup_panel lands the focus on the
		# rail's SETUP stop right after this.
		_adopt_pending_library()


## Panel queries (Main's feeds and the smokes read the panel
## the way the other smokes read their subjects).
func is_setup_panel_up() -> bool:
	return _setup_panel_up


func setup_panel_holder() -> Node3D:
	return _setup_panel


func setup_panel_face_quad() -> ClickableQuad:
	return _setup_panel_face


func setup_panel_scan_quad() -> ClickableQuad:
	return _setup_panel_scan_btn


func setup_panel_download_quad() -> ClickableQuad:
	return _setup_panel_dl_btn


func setup_panel_back_quad() -> ClickableQuad:
	return _setup_panel_back_btn


func setup_panel_wovp_paste_quad() -> ClickableQuad:
	return _setup_panel_wovp_paste_btn


func setup_panel_wovp_test_quad() -> ClickableQuad:
	return _setup_panel_wovp_test_btn


func setup_panel_stars_quad() -> ClickableQuad:
	return _setup_panel_stars_btn


func setup_panel_wall_quad() -> ClickableQuad:
	return _setup_panel_wall_btn


## PASTE KEY: the room's paste field. VR has no keyboard,
## so the field is the clipboard itself - the player copies
## the key on the PC (it is one line in his WoVP profile),
## and this button takes it from there and hands it to Main
## to save. An empty clipboard is a stated outcome, never a
## silent no-op; the key itself is never written anywhere
## here - it passes through this one signal to Main's
## config save.
func _paste_wovp_key() -> void:
	var text: String = DisplayServer.clipboard_get().strip_edges()
	if text == "":
		set_setup_panel_message("The clipboard was empty - copy your WoVP key first, then press PASTE KEY.")
		return
	set_setup_panel_message("WoVP key pasted - saving it...")
	wovp_key_pasted.emit(text)


func setup_panel_message() -> String:
	return _setup_message


func setup_panel_health() -> Dictionary:
	return _setup_health


## The last completed scan's numbers (Main feeds these on
## every scan landing, panel or not): the face renders its
## health rows from them, so a panel opened later already
## knows the library's state.
func set_setup_health(health: Dictionary) -> void:
	_setup_health = health
	if _setup_panel_up:
		_request_setup_panel_render(true)


## The message line. Scan progress ticks arrive once per
## frame from Main's poll - the change guard plus the render
## throttle keep the line fresh without flooding the shared
## factory.
func set_setup_panel_message(text: String) -> void:
	if text == _setup_message:
		return
	_setup_message = text
	if _setup_panel_up:
		_request_setup_panel_render(false)


## Main started the panel's scan (or could not - the caller
## says why on the message line instead).
func set_setup_panel_scanning(on: bool) -> void:
	_setup_scanning = on
	if _setup_panel_up:
		_request_setup_panel_render(true)


## A scan has landed: the health numbers and the outcome
## line land together, and the working state clears. Called
## on every scan landing (the desk's Save & Scan included) -
## the message is simply the last thing that happened.
func apply_setup_panel_scan(health: Dictionary, message: String) -> void:
	_setup_scanning = false
	_setup_health = health
	_setup_message = message
	if _setup_panel_up:
		_request_setup_panel_render(true)


func _start_setup_panel_download() -> void:
	if _setup_downloader == null:
		return
	if _setup_downloader.start_download():
		set_setup_panel_message("Downloading VPS database...")
		_request_setup_panel_render(true)


func _on_setup_panel_download_finished(ok: bool, message: String, _downloaded_path: String) -> void:
	if ok:
		# The bare fact plus this surface's tail - the cache
		# the download stored is the database the next scan
		# resolves to (VpsDatabase.resolve_path).
		set_setup_panel_message(message + " It will be used by the next scan.")
	else:
		set_setup_panel_message(message)
	_request_setup_panel_render(true)


func _build_setup_panel() -> void:
	_setup_panel = Node3D.new()
	_setup_panel.name = "SetupPanel"
	_setup_panel.position = Vector3(0.0, 1.32, -1.72)
	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	_setup_panel_face = ClickableQuad.new()
	_setup_panel_face.setup("setup_panel_face", "", placeholder, Vector2(1.5, 0.8))
	_setup_panel_face.position = Vector3(0.0, 0.38, 0.0)
	_setup_panel_face.pick_enabled = false
	_setup_panel.add_child(_setup_panel_face)
	_setup_panel_scan_btn = ClickableQuad.new()
	_setup_panel_scan_btn.setup("setup_panel_scan", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_scan_btn.position = Vector3(-0.375, -0.24, 0.0)
	_setup_panel.add_child(_setup_panel_scan_btn)
	_setup_panel_dl_btn = ClickableQuad.new()
	_setup_panel_dl_btn.setup("setup_panel_download", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_dl_btn.position = Vector3(0.375, -0.24, 0.0)
	_setup_panel.add_child(_setup_panel_dl_btn)
	# The WoVP row (the Tournament Room round): the key's
	# two acts in the room. PASTE KEY is the paste field and
	# its Save in one button - it reads the key off the PC
	# clipboard and hands it to Main to save; TEST KEY asks
	# Main whose the saved key is. The face's WoVP line says
	# the standing state in words.
	_setup_panel_wovp_paste_btn = ClickableQuad.new()
	_setup_panel_wovp_paste_btn.setup("setup_panel_wovp_paste", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_wovp_paste_btn.position = Vector3(-0.375, -0.5, 0.0)
	_setup_panel.add_child(_setup_panel_wovp_paste_btn)
	_setup_panel_wovp_test_btn = ClickableQuad.new()
	_setup_panel_wovp_test_btn.setup("setup_panel_wovp_test", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_wovp_test_btn.position = Vector3(0.375, -0.5, 0.0)
	_setup_panel.add_child(_setup_panel_wovp_test_btn)
	# The display dial row (the GRAD FIX round; the WING
	# dial retired with the wing itself in GRADFIX6 - the
	# flip has no off state to offer): STARS cycles the
	# starfield's layering. The button's label states the
	# standing value; a press turns the dial one step,
	# applies it in the room at once, and Main persists it
	# (display_settings_changed).
	_setup_panel_stars_btn = ClickableQuad.new()
	_setup_panel_stars_btn.setup("setup_setting_stars", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_stars_btn.position = Vector3(-0.375, -0.76, 0.0)
	_setup_panel.add_child(_setup_panel_stars_btn)
	# The wall-motion dial (GRADFIX10 item 3) shares the
	# display row with STARS: WALL MOTION cycles SMOOTH /
	# STEPPED. Same terms as STARS - the label states the
	# standing value, a press applies it in the room at once
	# and Main persists it (display_settings_changed).
	_setup_panel_wall_btn = ClickableQuad.new()
	_setup_panel_wall_btn.setup("setup_setting_wall_motion", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_wall_btn.position = Vector3(0.375, -0.76, 0.0)
	_setup_panel.add_child(_setup_panel_wall_btn)
	# The last row (CARDBACK/IPDBFIX): RE-APPLY IPDB DATA
	# shares it with BACK - the bundled snapshot's apply
	# is Main's (the signal route, like SCAN), the panel
	# only asks. The row keeps the panel's standing
	# height: nothing hangs lower than BACK always did.
	_setup_panel_ipdb_btn = ClickableQuad.new()
	_setup_panel_ipdb_btn.setup("setup_panel_ipdb", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_ipdb_btn.position = Vector3(-0.375, -1.02, 0.0)
	_setup_panel.add_child(_setup_panel_ipdb_btn)
	_setup_panel_back_btn = ClickableQuad.new()
	_setup_panel_back_btn.setup("setup_panel_back", "", placeholder, Vector2(0.66, 0.16))
	_setup_panel_back_btn.position = Vector3(0.375, -1.02, 0.0)
	_setup_panel.add_child(_setup_panel_back_btn)
	if _setup_downloader == null:
		_setup_downloader = VpsDownloader.new()
		add_child(_setup_downloader)
		_setup_downloader.progress.connect(func(text: String) -> void: set_setup_panel_message(text))
		_setup_downloader.finished.connect(_on_setup_panel_download_finished)
	# No face_point here: the holder is oriented in
	# show_setup_panel, once it is inside the tree (the
	# placard's lesson).


## Panel textures - face plus the six buttons - render
## from current state, generation-guarded like the
## placard's. Renders serialize (the shared factory takes
## one at a time): a state change during a render, or
## inside the 250ms progress throttle, marks pending and
## the follow-up render runs when the live one lands.
func _request_setup_panel_render(immediate: bool) -> void:
	if not _setup_panel_up:
		return
	if _setup_render_in_flight or (not immediate and Time.get_ticks_msec() - _setup_render_msec < 250):
		_setup_render_pending = true
		return
	_setup_render_pending = false
	_setup_render_in_flight = true
	_setup_render_msec = Time.get_ticks_msec()
	_setup_panel_gen += 1
	_fill_setup_panel_textures(_setup_panel_gen)


func _after_setup_render() -> void:
	_setup_render_in_flight = false
	if _setup_render_pending and _setup_panel_up:
		_setup_render_pending = false
		_setup_render_in_flight = true
		_setup_render_msec = Time.get_ticks_msec()
		_setup_panel_gen += 1
		_fill_setup_panel_textures(_setup_panel_gen)


func _fill_setup_panel_textures(gen: int) -> void:
	var face_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.setup_panel_spec(_setup_health, _setup_message), Vector2i(1024, 546))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_face == null:
		_after_setup_render()
		return
	_setup_panel_face.set_texture(face_tex)
	var scan_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("SCANNING..." if _setup_scanning else "SCAN LIBRARY", _setup_scanning), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_scan_btn == null:
		_after_setup_render()
		return
	_setup_panel_scan_btn.set_texture(scan_tex)
	var dl_busy: bool = _setup_downloader != null and _setup_downloader.is_downloading()
	var dl_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("DOWNLOADING..." if dl_busy else "DOWNLOAD VPS DATABASE", dl_busy), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_dl_btn == null:
		_after_setup_render()
		return
	_setup_panel_dl_btn.set_texture(dl_tex)
	var paste_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("PASTE KEY", false), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_wovp_paste_btn == null:
		_after_setup_render()
		return
	_setup_panel_wovp_paste_btn.set_texture(paste_tex)
	var test_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("TEST KEY", false), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_wovp_test_btn == null:
		_after_setup_render()
		return
	_setup_panel_wovp_test_btn.set_texture(test_tex)
	var stars_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("STARS: " + _starfield_mode.to_upper(), false), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_stars_btn == null:
		_after_setup_render()
		return
	_setup_panel_stars_btn.set_texture(stars_tex)
	var wall_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("WALL MOTION: " + _wall_motion_mode.to_upper(), false), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_wall_btn == null:
		_after_setup_render()
		return
	_setup_panel_wall_btn.set_texture(wall_tex)
	var ipdb_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("RE-APPLY IPDB DATA", false), Vector2i(512, 124))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_ipdb_btn == null:
		_after_setup_render()
		return
	_setup_panel_ipdb_btn.set_texture(ipdb_tex)
	var back_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("BACK", true), Vector2i(512, 164))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_back_btn == null:
		_after_setup_render()
		return
	_setup_panel_back_btn.set_texture(back_tex)
	_after_setup_render()


# ------------------------------------------------------- submit panel

## ROOMSUBMIT: submit a WoVP score without leaving the
## room. The player already submits today without removing
## his headset - double-tap to Virtual Desktop's desktop
## view, website form, double-tap back - and the desk flow
## broke that: it asked him to leave the Tournament Room,
## relaunch to the desk, and work a form there. This panel
## puts the send where he already stands: on the challenge
## whose board he is looking at. No desktop trips, no view
## breaks (the standing VR law), headset never comes off.
##
## The mount is the SETUP panel's: the room's proven
## operations-panel grammar. Same seat (front and centre
## at reading distance), same modal discipline - pick
## snapshot/inert/restore, focus confined to the panel's
## stops, generation-guarded factory renders, B / D-pad
## Right as BACK (never an exit), freed on close, never
## parked. The alternative - a panel riding the drum
## beside the focused board - fights the drum's panel
## pool, swing, pop and fill pipeline, and the verify step
## below needs a surface that stands STILL and BIG.
##
## The command is Y on a focused challenge card
## (_info_focused_card's tournament branch): Y is free in
## the Tournament Room (its flip is refused there -
## GRADFIX7: boards stand open, nothing needs turning) and
## its library meaning is "this card's other business",
## which is exactly what submitting is. The standing board
## names the command itself ("Y - SUBMIT A SCORE" on every
## board), because the room has no controls surface to
## list it on.
##
## The panel, top to bottom: the case face (the challenge,
## its deadline, the library standing, the higher-score
## warning with his posted number named); ONE shot standing
## large; the newest screenshots from his screenshots
## folder as a thumb strip; SEND and BACK. FOCUS IS THE
## VERIFY STEP: the focused thumb's shot is the one
## standing large, big enough to read a score and reject a
## blank flicker frame (some tables' LEDs blink by design,
## and a burst of shots holds duds - the pick must be a
## check, not a guess). SEND posts the focused shot
## through Main to WovpClient - the desk's own two-step
## transaction, its refusals, its log (the room's entries
## carry no recorded score: the typed field stays
## desk-only) - and the verdict lands on the face's status
## line in the client's own words.
##
## Every state is honest in words on the face: no key
## saved, folder unset, folder missing, folder empty,
## sending, submitted, refused. No dead panels, no crashes.

func _open_submit_for_focused() -> void:
	if not _tournament or _mode != "wall" or _placard_up or _setup_panel_up or _submit_panel_up:
		return
	if _focused == null or _launching_game_id != "":
		return
	var idx: int = _panels.find(_focused)
	if idx < 0 or idx >= _tournament_rows.size():
		return
	var row: Dictionary = _tournament_rows[idx] as Dictionary
	if str(row.get("kind", "")) != "challenge":
		return
	var ch: WovpChallenge = row["challenge"] as WovpChallenge
	if ch == null:
		return
	show_submit_panel(ch, bool(row.get("owned", false)), bool(row.get("build_owned", false)))


func show_submit_panel(ch: WovpChallenge, owned: bool, build_owned: bool) -> void:
	_submit_challenge = ch
	_submit_challenge_id = ch.challenge_id
	_submit_owned = owned
	_submit_build_owned = build_owned
	_submit_sending = false
	_submit_status = ""
	if not _wovp_has_key:
		_submit_status = "No WoVP key saved - submissions use the same key as the boards. Add it in SETUP."
	# The folder read happens AT OPEN, every open: his
	# shots land minutes before he opens this panel, and a
	# list cached any earlier would lie about the shelf.
	_submit_shots = ShotsFolder.list_shots(_wovp_shots_folder, 5)
	_submit_shots_line = ShotsFolder.panel_line(_wovp_shots_folder)
	_submit_selected_path = ""
	if not _submit_shots.is_empty():
		_submit_selected_path = str((_submit_shots[0] as Dictionary).get("path", ""))
	if _submit_panel == null:
		_build_submit_panel()
	if not _submit_panel_up:
		_pick_snapshot.clear()
		for q: ClickableQuad in _room_pickables():
			_pick_snapshot[q] = q.pick_enabled
		_submit_panel_up = true
		add_child(_submit_panel)
		ClickableQuad.face_point(_submit_panel, EYE)
		_inert_room_quads()
	_refresh_focusables()
	if not _submit_thumb_quads.is_empty():
		_set_focused(_submit_thumb_quads[0]) ## the hook in _set_focused stands its shot large
	elif _submit_send_btn != null:
		_set_focused(_submit_send_btn)
	_request_submit_panel_render(true)


func _build_submit_panel() -> void:
	_submit_panel = Node3D.new()
	_submit_panel.name = "SubmitPanel"
	# SUBMITDIST: the seat is the submit panel's OWN, pushed
	# back from the SETUP family's -1.72 to -2.30 - at -1.72
	# the 1024x532 face plus the 1.06x0.76 photo filled the
	# view ("its in your face", field 2026-11-06). Distance
	# is the only knob: the panel keeps its physical size,
	# and the SETUP panel keeps its own -1.72 seat.
	_submit_panel.position = Vector3(0.0, 1.32, -2.30)
	var placeholder: Texture2D = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	_submit_panel_face = ClickableQuad.new()
	_submit_panel_face.setup("submit_panel_face", "", placeholder, Vector2(1.5, 0.78))
	_submit_panel_face.position = Vector3(0.0, 0.58, 0.0)
	_submit_panel_face.pick_enabled = false
	_submit_panel.add_child(_submit_panel_face)
	_submit_big_quad = ClickableQuad.new()
	_submit_big_quad.setup("submit_photo", "", placeholder, Vector2(1.06, 0.76))
	_submit_big_quad.position = Vector3(0.0, -0.24, 0.0)
	_submit_big_quad.pick_enabled = false
	_submit_panel.add_child(_submit_big_quad)
	_submit_thumb_quads.clear()
	var tx: float = -0.58
	for sv: Variant in _submit_shots:
		var shot: Dictionary = sv as Dictionary
		var tq: ClickableQuad = ClickableQuad.new()
		tq.setup("submit_shot", str(shot.get("path", "")), placeholder, Vector2(0.27, 0.20))
		tq.position = Vector3(tx, -0.78, 0.0)
		_submit_panel.add_child(tq)
		_submit_thumb_quads.append(tq)
		tx += 0.29
	_submit_send_btn = ClickableQuad.new()
	_submit_send_btn.setup("submit_send", "", placeholder, Vector2(0.52, 0.15))
	_submit_send_btn.position = Vector3(-0.28, -1.06, 0.0)
	_submit_panel.add_child(_submit_send_btn)
	_submit_back_btn = ClickableQuad.new()
	_submit_back_btn.setup("submit_back", "", placeholder, Vector2(0.52, 0.15))
	_submit_back_btn.position = Vector3(0.28, -1.06, 0.0)
	_submit_panel.add_child(_submit_back_btn)
	# The photos' textures: the house decode path
	# (TextureFactory.load_art_texture - shared cache,
	# capped at 1024 wide). A thumb and the big view of the
	# same shot are ONE cache entry; the big view loads
	# when its shot is focused (see _submit_show_shot).
	for tq2: ClickableQuad in _submit_thumb_quads:
		var tex: Texture2D = TextureFactory.load_art_texture(tq2.payload)
		if tex != null:
			tq2.set_texture(tex)
			_fit_photo_quad(tq2, tex)
	# No face_point here: the holder is oriented in
	# show_submit_panel, once it is inside the tree (the
	# SETUP panel's lesson).


## Aspect-fit a photo quad inside its box: the quad is
## built at the box size and scaled down on the long axis,
## so a shot is never stretched - what he reads in the big
## view is the shot as the camera took it. (pulse() tweens
## scale from its standing value, so a press keeps the fit.)
func _fit_photo_quad(q: ClickableQuad, tex: Texture2D) -> void:
	if tex == null or tex.get_height() == 0:
		return
	var box: Vector2 = q.quad_size()
	if box.y == 0.0:
		return
	var aspect: float = float(tex.get_width()) / float(tex.get_height())
	var box_aspect: float = box.x / box.y
	if aspect > box_aspect:
		q.scale = Vector3(1.0, box_aspect / aspect, 1.0)
	else:
		q.scale = Vector3(aspect / box_aspect, 1.0, 1.0)


## The verify step's other half: stand a shot large. The
## one caller door is _set_focused (a thumb taking focus),
## plus the panel's open - so the big view can never
## disagree with the frame the player sees.
func _submit_show_shot(path: String) -> void:
	_submit_selected_path = path
	if _submit_big_quad == null:
		return
	var tex: Texture2D = TextureFactory.load_art_texture(path)
	if tex != null:
		_submit_big_quad.set_texture(tex)
		_fit_photo_quad(_submit_big_quad, tex)


## SEND: hand the focused shot to Main (the signal route,
## like the SETUP panel's SCAN). With no shot focused -
## folder unset, missing, or empty - the press is answered
## with the state's own words, never a mute panel and
## never a send.
func _submit_panel_send() -> void:
	if _submit_sending or _submit_challenge_id == "":
		return
	if _submit_selected_path == "":
		_submit_status = _submit_shots_line
		_request_submit_panel_render(true)
		return
	_submit_sending = true
	_submit_status = "Sending your photo to WoVP..."
	_request_submit_panel_render(true)
	wovp_submit_requested.emit(_submit_challenge_id, _submit_selected_path)


## Main's answer door for a room submission (the desk's
## verdicts land on the desk's status line; the room's land
## here): the words stand on the panel's status line
## verbatim - a success is the client's "Submitted -
## awaiting validation.", a refusal carries the server's
## own words inside the client's message (the HTTP400
## surfacing law). A verdict for a panel that has closed,
## or for another challenge, is not this panel's to show -
## the log and the desk still carry it.
func set_wovp_submit_result(_ok: bool, message: String, challenge_id: String) -> void:
	if not _submit_panel_up:
		return
	if challenge_id != "" and challenge_id != _submit_challenge_id:
		return
	_submit_sending = false
	_submit_status = message
	_request_submit_panel_render(true)


## The panel's BACK: tear it down, hand the room back, and
## land focus on the challenge's card - re-resolved by id,
## because a boards refresh may have rebuilt the wall (and
## renumbered the rows) behind the panel. When the
## challenge no longer stands, the landing is the rail's
## TOURNAMENT stop.
func hide_submit_panel() -> void:
	if not _submit_panel_up:
		return
	var cid: String = _submit_challenge_id
	clear_submit_panel()
	for i: int in range(_tournament_rows.size()):
		var row: Dictionary = _tournament_rows[i] as Dictionary
		if str(row.get("kind", "")) == "challenge":
			var ch: WovpChallenge = row["challenge"] as WovpChallenge
			if ch != null and ch.challenge_id == cid and i < _panels.size():
				_set_focused(_panels[i])
				return
	_land_on_rail_stop("tournament")


## Silent teardown for Main's own routes (a fresh room
## entry): no landing - Main is already driving.
func clear_submit_panel() -> void:
	if not _submit_panel_up:
		return
	_submit_panel_up = false
	_submit_panel_gen += 1
	_submit_sending = false
	_submit_challenge = null
	_submit_challenge_id = ""
	_submit_shots = []
	_submit_shots_line = ""
	_submit_selected_path = ""
	_submit_status = ""
	if _submit_panel != null:
		# Freed, not parked - the SETUP panel's rule:
		# parked holders orphan their meshes.
		if _submit_panel.get_parent() != null:
			remove_child(_submit_panel)
		_submit_panel.queue_free()
		_submit_panel = null
		_submit_panel_face = null
		_submit_big_quad = null
		_submit_thumb_quads.clear()
		_submit_send_btn = null
		_submit_back_btn = null
	_restore_room_pick_states()
	_set_focused(null)
	_refresh_focusables()


## Panel queries (Main's feeds and the smokes read the
## panel the way the other smokes read their subjects).
func is_submit_panel_up() -> bool:
	return _submit_panel_up


func submit_panel_holder() -> Node3D:
	return _submit_panel


func submit_panel_face_quad() -> ClickableQuad:
	return _submit_panel_face


func submit_big_quad() -> ClickableQuad:
	return _submit_big_quad


func submit_thumb_quads() -> Array:
	return _submit_thumb_quads.duplicate()


func submit_send_quad() -> ClickableQuad:
	return _submit_send_btn


func submit_back_quad() -> ClickableQuad:
	return _submit_back_btn


func submit_panel_message() -> String:
	return _submit_status


func submit_panel_challenge_id() -> String:
	return _submit_challenge_id


func submit_shots() -> Array:
	return _submit_shots.duplicate()


func submit_selected_path() -> String:
	return _submit_selected_path


## The spec the face renders from, standing state and all
## (the smoke's content read - the warning, the case lines,
## the shots line - without reaching into the panel).
func submit_face_spec() -> Dictionary:
	if _submit_challenge == null:
		return {}
	return RoomSpecs.submit_panel_spec(_submit_challenge, _submit_owned, _submit_build_owned,
		_wovp_user_id, int(Time.get_unix_time_from_system()), _submit_status, _submit_shots_line)


## Panel textures - face plus the two buttons - render
## from current state, generation-guarded like the SETUP
## panel's: renders serialize through the shared factory,
## a state change during a render marks pending, and the
## follow-up runs when the live one lands.
func _request_submit_panel_render(immediate: bool) -> void:
	if not _submit_panel_up:
		return
	if _submit_render_in_flight or (not immediate and Time.get_ticks_msec() - _submit_render_msec < 250):
		_submit_render_pending = true
		return
	_submit_render_pending = false
	_submit_render_in_flight = true
	_submit_render_msec = Time.get_ticks_msec()
	_submit_panel_gen += 1
	_fill_submit_panel_textures(_submit_panel_gen)


func _after_submit_render() -> void:
	_submit_render_in_flight = false
	if _submit_render_pending and _submit_panel_up:
		_submit_render_pending = false
		_submit_render_in_flight = true
		_submit_render_msec = Time.get_ticks_msec()
		_submit_panel_gen += 1
		_fill_submit_panel_textures(_submit_panel_gen)


func _fill_submit_panel_textures(gen: int) -> void:
	if _submit_challenge == null:
		_after_submit_render()
		return
	var face_tex: Texture2D = await _factory.render_texture(
		submit_face_spec(), Vector2i(1024, 532))
	if gen != _submit_panel_gen or not _submit_panel_up or _submit_panel_face == null:
		_after_submit_render()
		return
	_submit_panel_face.set_texture(face_tex)
	var send_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("SENDING..." if _submit_sending else "SEND", true), Vector2i(512, 164))
	if gen != _submit_panel_gen or not _submit_panel_up or _submit_send_btn == null:
		_after_submit_render()
		return
	_submit_send_btn.set_texture(send_tex)
	var back_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("BACK", false), Vector2i(512, 124))
	if gen != _submit_panel_gen or not _submit_panel_up or _submit_back_btn == null:
		_after_submit_render()
		return
	_submit_back_btn.set_texture(back_tex)
	_after_submit_render()


# ------------------------------------------------------- launch states

## A launch is in its load wait (Main owns the wait itself): the
## room goes DEAF for the whole wait - no quad picks, the focusable
## set is empty, _activate refuses everything, EXIT and SETUP
## included. The wait is bounded (Main's hand-off cues, its failure
## path, and the 45s cap), so no cancel control is needed, and none
## is offered.
##
## Why deaf, in full (field root cause, 2026-10-21): this room
## listens to the same gamepad the player plays VPX with, and A is
## both "activate the focused quad" here and the player's plunger
## button there. The old wait deliberately kept EXIT pickable and
## parked focus ON it ("EXIT stays live throughout"), so the
## player's first play press during the load fired EXIT: the
## session disarmed silently, VPX kept loading detached, and the
## player later exited to an editor with no watchdog on duty - the
## "never returns to the interface" failure that survived five
## builds because every switch combination left this path open.
func begin_launch(game: GameEntry) -> void:
	_launching_game_id = game.game_id
	_failed_game_id = ""
	_snap_flip_shut() ## the wall freezes for the wait: no card stands turned behind the marquee
	_status_note = "Launching %s... controls are locked while the table loads" % game.title
	for q: ClickableQuad in _panels:
		q.pick_enabled = false
	for q: ClickableQuad in _panel_launches:
		if q != null:
			q.pick_enabled = false
	for k: Variant in _rail_quads.keys():
		_rail_quads[k].pick_enabled = false
	var detail_open: bool = _detail != null and _detail.is_open()
	if detail_open:
		_detail.set_launching(true)
	_set_focused(null)
	_refresh_focusables()
	# GRADFIX13 (item 2): the wait's LOADING state used to
	# also swap the launching card's plinth texture to
	# "LOADING..." (_swap_launch_textures, deleted with the
	# plinths). The state's standing surfaces are the ones
	# begin_launch already raises: the marquee (wall
	# launches), the status banner's note above, and the
	# detail view's own Play quad (detail launches, via
	# set_launching just above) - the strip drops no state.
	_refresh_banner()
	# The marquee is the WALL's loading display: it stands at
	# the wall's settle depth, behind where the detail panel
	# sits, so a launch begun FROM the detail view raised it
	# straight into the panel's shadow - the year and designer
	# letters lurking behind the info card for the whole wait
	# (field report, 2026-10-26). The detail view carries its
	# own launching state; a detail-initiated wait raises no
	# marquee at all. Wall launches are untouched.
	if not detail_open:
		_raise_marquee(game)


## VPX died during the load, with the launcher still resident to
## say so: the failure lands on the wall (banner note, below)
## and browsing resumes. In detail mode the detail view is
## the visible surface - its Play button is restored and the wall
## rebuilds when it closes, as usual.
## GRADFIX13 (item 2): the failed card's plinth used to be
## re-dressed FAILED here (via _failed_game_id's texture
## swaps in the fill paths). With the plinths stripped, the
## failure's standing surface is the banner note -
## _status_note names the game and the reason, and stands
## until the player browses on (the standing clear points).
## _failed_game_id is kept as the record the note derives
## from, no longer as a texture key.
func end_launch_failed(game: GameEntry, reason: String) -> void:
	_dismiss_marquee()
	_launching_game_id = ""
	_failed_game_id = game.game_id
	_status_note = "Launch failed: %s - %s" % [game.title, reason]
	if _detail != null and _detail.is_open():
		_detail.set_launching(false)
	# GRADFIX14 (item 2): a scan held during the load wait
	# adopts here, as the wait settles back to the wall -
	# the failure's marks are already recorded above, so
	# the adoption's rebuild carries them, and in detail
	# mode the adoption still lands in the data the detail
	# close rebuilds from.
	_adopt_pending_library()
	if _mode == "detail":
		return
	_rebuild_wall()


## Raise the loading marquee for the wait begin_launch just
## started. Line 1 is the year in big display letters; line 2 is
## the designer beneath it. Fallbacks, per the brief: no year ->
## line 1 falls back to the manufacturer (and then to the title);
## no designer -> line 2 falls back to the title. An empty line
## is HIDDEN - never an "Unknown designer" placeholder.
func _raise_marquee(game: GameEntry) -> void:
	_dismiss_marquee()
	_build_marquee()
	var top: String = ""
	if game.year > 0:
		top = str(game.year)
	elif game.manufacturer != "":
		top = game.manufacturer
	var bottom: String = ""
	if not game.designers.is_empty():
		bottom = ", ".join(PackedStringArray(game.designers))
	elif top != game.title:
		bottom = game.title
	if top == "":
		top = game.title
		bottom = ""
	_marquee_year.text = top
	_marquee_name.text = bottom
	_marquee_name.visible = bottom != ""
	_marquee_t = 0.0
	_marquee_up = true
	add_child(_marquee)
	ClickableQuad.face_point(_marquee, EYE)


func _build_marquee() -> void:
	_marquee = Node3D.new()
	_marquee.name = "LoadingMarquee"
	_marquee.position = Vector3(MARQUEE_SETTLE_POS.x, MARQUEE_SETTLE_POS.y, MARQUEE_START_Z)
	_marquee_year = Label3D.new()
	_marquee_year.pixel_size = MARQUEE_PIXEL_SIZE
	_marquee_year.font_size = MARQUEE_YEAR_FONT_SIZE
	_marquee_year.outline_size = MARQUEE_OUTLINE_SIZE
	_marquee_year.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marquee_year.position = Vector3(0.0, MARQUEE_YEAR_Y, 0.0)
	_marquee_year.modulate = Color(MARQUEE_YEAR_COLOR, 0.0)
	_marquee_year.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, 0.0)
	_marquee.add_child(_marquee_year)
	_marquee_name = Label3D.new()
	_marquee_name.pixel_size = MARQUEE_PIXEL_SIZE
	_marquee_name.font_size = MARQUEE_NAME_FONT_SIZE
	_marquee_name.outline_size = MARQUEE_OUTLINE_SIZE
	_marquee_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marquee_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_marquee_name.width = 700.0
	_marquee_name.position = Vector3(0.0, MARQUEE_NAME_Y, 0.0)
	_marquee_name.modulate = Color(MARQUEE_NAME_COLOR, 0.0)
	_marquee_name.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, 0.0)
	_marquee.add_child(_marquee_name)
	# No face_point here: the holder is oriented in _raise_marquee,
	# once it is inside the tree (the placard's lesson).


## Tear the marquee down and hand the wall its opacity back. The
## holder is FREED, not parked - the placard's rule (renderer
## teardown choked on parked holders at exit). On a successful
## hand-off this never runs: the process exits with the marquee
## standing, which is the point - it holds until the wait settles.
## The marquee's current lines, [top, bottom] - the shot hook
## prints them so a harness can assert what the marquee actually
## SAYS (the clean-name rule) instead of eyeballing pixels alone.
## [] while no marquee stands.
func marquee_text() -> Array[String]:
	if not _marquee_up or _marquee_year == null or _marquee_name == null:
		return []
	return [_marquee_year.text, _marquee_name.text]


func _dismiss_marquee() -> void:
	_marquee_up = false
	if _marquee != null:
		if _marquee.get_parent() != null:
			remove_child(_marquee)
		_marquee.queue_free()
		_marquee = null
		_marquee_year = null
		_marquee_name = null
	_apply_wall_alpha(1.0)


## Per-frame marquee animation, driven from _process: the wall
## fades down and stays down; the letters fly from the wall to the
## settle point and hold there with a gentle pulse.
func _update_marquee(delta: float) -> void:
	if not _marquee_up or _marquee == null:
		return
	_marquee_t += delta
	var fade_p: float = clampf(_marquee_t / MARQUEE_FADE_SEC, 0.0, 1.0)
	var fade_e: float = fade_p * fade_p * (3.0 - 2.0 * fade_p)
	_apply_wall_alpha(lerpf(1.0, MARQUEE_WALL_ALPHA, fade_e))
	var fly_p: float = clampf(_marquee_t / MARQUEE_FLY_IN_SEC, 0.0, 1.0)
	var fly_e: float = 1.0 - pow(1.0 - fly_p, 3.0)
	_marquee.position = Vector3(MARQUEE_SETTLE_POS.x, MARQUEE_SETTLE_POS.y,
		lerpf(MARQUEE_START_Z, MARQUEE_SETTLE_POS.z, fly_e))
	# The pulse ramps in across the fly-in (multiplied by fly_p)
	# and the scale eases up from the wall, so neither jumps at
	# the settle point.
	var pulse: float = 1.0 + MARQUEE_PULSE_AMOUNT * sin(_marquee_t * MARQUEE_PULSE_RATE * TAU) * fly_p
	_marquee.scale = Vector3.ONE * pulse * lerpf(0.85, 1.0, fly_e)
	var alpha: float = clampf(_marquee_t / (MARQUEE_FLY_IN_SEC * 0.4), 0.0, 1.0)
	_marquee_year.modulate = Color(MARQUEE_YEAR_COLOR, alpha)
	_marquee_year.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, alpha)
	_marquee_name.modulate = Color(MARQUEE_NAME_COLOR, alpha)
	_marquee_name.outline_modulate = Color(MARQUEE_OUTLINE_COLOR, alpha)


## The wall fade itself: panels, their Launch buttons, the rail,
## and the banner. Change-guarded - _update_marquee calls this
## every frame of the wait. Each card's fade is multiplied by
## its haze (the background stack's fourth layer): the marquee
## dims the whole wall, the haze dims the far columns further.
## The wall-alpha write counter (the hitchhunt smoke reads
## the deltas across its cruises: the write-on-change law's
## structural proof, immune to harness-box pacing).
func alpha_write_count() -> int:
	return _alpha_write_count


## OPTIMIZE round (item 5): the standing-cost audit's account.
## Totals since boot plus per-second rates over the room's
## accumulated at-rest time (see the counter block at
## _alpha_write_count). Rates read 0.0 until a rest stretch
## has accumulated.
func standing_cost_stats() -> Dictionary:
	var rest_s: float = float(_sc_rest_msec) / 1000.0
	if _sc_rest_since > 0:
		rest_s += float(Time.get_ticks_msec() - _sc_rest_since) / 1000.0
	var denom: float = maxf(rest_s, 0.001)
	return {
		"mimic_evals_total": _sc_mimic_evals,
		"mimic_evals_per_sec_at_rest": float(_sc_mimic_evals) / denom,
		"label_reassign_total": _sc_label_reassign,
		"label_reassign_per_sec_at_rest": float(_sc_label_reassign) / denom,
		"alpha_writes_total": _alpha_write_count,
		"alpha_writes_per_sec_at_rest": float(_alpha_write_count) / denom,
		"face_assigns_total": _sc_face_assigns,
		"noop_face_swaps_total": _sc_noop_face_swaps,
		"noop_face_swaps_per_sec_at_rest": float(_sc_noop_face_swaps) / denom,
		"pop_visits_at_rest_total": _sc_pop_visits_rest,
		"pop_visits_per_sec_at_rest": float(_sc_pop_visits_rest) / denom,
		"rest_seconds": rest_s,
	}


## Grow an alpha cache to index i with the never-written
## stamp (-1: every real alpha is >= 0, so the first pass
## always writes).
func _alpha_cache_ensure(cache: Array[float], i: int) -> void:
	while cache.size() <= i:
		cache.append(-1.0)


func _apply_wall_alpha(a: float) -> void:
	# GRADFIX17 (item 2): the pass runs when the global fade
	# moved OR the haze's centre moved - and then writes
	# only the alphas that actually change (see the state
	# block at _alpha_write_count). The pre-fix law, restored
	# by PVLDS_GF17_NC=hazeall, writes everything on both
	# triggers: that per-column write storm is what the
	# hitchhunt smoke's alpha leg fails against by name.
	var nc_all: bool = debug_gf17_nc == "hazeall"
	var centre_col: int = _grid_coord(_centre_index).x if _centre_index >= 0 and _centre_index < _panels.size() else -1
	if not nc_all and absf(a - _wall_alpha_applied) < 0.002 and centre_col == _alpha_haze_centre:
		return
	_wall_alpha_applied = a
	_alpha_haze_centre = centre_col
	for i: int in range(_panels.size()):
		var want_p: float = a * _haze_for(i)
		_alpha_cache_ensure(_panel_alpha_applied, i)
		if nc_all or absf(want_p - _panel_alpha_applied[i]) >= 0.002:
			_panel_alpha_applied[i] = want_p
			_panels[i].set_content_alpha(want_p)
			_alpha_write_count += 1
	for i2: int in range(_panel_launches.size()):
		if _panel_launches[i2] != null:
			var want_l: float = a * _haze_for(i2)
			_alpha_cache_ensure(_launch_alpha_applied, i2)
			if nc_all or absf(want_l - _launch_alpha_applied[i2]) >= 0.002:
				_launch_alpha_applied[i2] = want_l
				_panel_launches[i2].set_content_alpha(want_l)
				_alpha_write_count += 1
	for bi2: int in range(_board_nodes.size()):
		var bnode3: MeshInstance3D = _board_nodes[bi2] as MeshInstance3D
		if bnode3 != null and bi2 < _board_nodes.size():
			var bmat3: StandardMaterial3D = bnode3.material_override as StandardMaterial3D
			if bmat3 != null:
				var want_b: float = a * _haze_for(bi2)
				_alpha_cache_ensure(_board_alpha_applied, bi2)
				if nc_all or absf(want_b - _board_alpha_applied[bi2]) >= 0.002:
					_board_alpha_applied[bi2] = want_b
					bmat3.albedo_color = Color(1.0, 1.0, 1.0, want_b)
					_alpha_write_count += 1
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null:
			var rkey: String = "rail:" + str(k)
			if nc_all or absf(a - float(_alpha_flat_applied.get(rkey, -1.0))) >= 0.002:
				_alpha_flat_applied[rkey] = a
				rq.set_content_alpha(a)
				_alpha_write_count += 1
	for skey: Variant in _strip_quads.keys():
		var sq: ClickableQuad = _strip_quads[skey] as ClickableQuad
		if sq != null:
			var skey2: String = "strip:" + str(skey)
			if nc_all or absf(a - float(_alpha_flat_applied.get(skey2, -1.0))) >= 0.002:
				_alpha_flat_applied[skey2] = a
				sq.set_content_alpha(a)
				_alpha_write_count += 1
	# The status line fades with the wall, and so do the
	# cards' nameplates (plate + label ride their cards).
	# The plates all share one material, so its alpha is
	# set once, here.
	if _status_label != null:
		if nc_all or absf(a - float(_alpha_flat_applied.get("status", -1.0))) >= 0.002:
			_alpha_flat_applied["status"] = a
			_status_label.modulate = Color(0.92, 0.95, 1.0, a)
			_status_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9 * a)
			_alpha_write_count += 1
	if nc_all or absf(a - float(_alpha_flat_applied.get("plate", -1.0))) >= 0.002:
		_alpha_flat_applied["plate"] = a
		_plate_mat().albedo_color = Color(0.0, 0.0, 0.0, 0.66 * a)
		_alpha_write_count += 1
	# The tournie borders fade with the wall too (GRADFIX8
	# item 4): their materials are shared per type, so the
	# global alpha is set once per type here - the same
	# shared-material terms the nameplates already ride.
	for bk: Variant in _border_mats.keys():
		var bkey2: String = "border:" + str(bk)
		if nc_all or absf(a - float(_alpha_flat_applied.get(bkey2, -1.0))) >= 0.002:
			_alpha_flat_applied[bkey2] = a
			(_border_mats[bk] as ShaderMaterial).set_shader_parameter("global_alpha", clampf(a, 0.0, 1.0))
			_alpha_write_count += 1
	for idx: int in range(_panels.size()):
		if idx < _panel_labels.size() and _panel_labels[idx] != null:
			var la: float = a * _haze_for(idx)
			_alpha_cache_ensure(_label_alpha_applied, idx)
			if nc_all or absf(la - _label_alpha_applied[idx]) >= 0.002:
				_label_alpha_applied[idx] = la
				_panel_labels[idx].modulate = Color(0.96, 0.97, 1.0, la)
				_panel_labels[idx].outline_modulate = Color(0.0, 0.0, 0.0, 0.9 * la)
				_alpha_write_count += 1


## Load-wait queries (the lockout smoke reads the room the way the
## placard smoke reads the placard): is a wait in progress, what
## the banner note says, where focus sits, how many focus stops
## exist, and the rail quads by key.
func is_launch_in_wait() -> bool:
	return _launching_game_id != ""


func launch_status_note() -> String:
	return _status_note


func focusable_count() -> int:
	return _focusables.size()


func focused_quad() -> ClickableQuad:
	return _focused


func rail_quad(key: String) -> ClickableQuad:
	var q: Variant = _rail_quads.get(key, null)
	return q as ClickableQuad


## Letter-jump queries (the letters smoke reads the room the
## way the other smokes read theirs): a strip slot by key, the
## standing net ("" when none), and whether a slot is pickable
## in the current view.
func letter_quad(key: String) -> ClickableQuad:
	var q: Variant = _strip_quads.get(key, null)
	return q as ClickableQuad


func active_letter_net() -> String:
	return _letter_net


func strip_slot_pickable(key: String) -> bool:
	var q: ClickableQuad = letter_quad(key)
	return q != null and q.visible and q.pick_enabled


## NEXTROUND (item 1): the colour state the slot's worn face
## was rendered for ("plain" / "dim" / "accent"), or "" when
## the slot has not been dressed yet. The letters smoke's
## strip-colour legs assert the encoding from this record.
func strip_slot_state(key: String) -> String:
	return str(_strip_worn_state.get(key, ""))


## Pop-out queries (the pop shot hook reads the room the way the
## other smokes read theirs): a panel's current pop amount, how
## far it currently sits off its wall-flush position, and the
## panel the shared focus would pop.
func panel_pop_amount(q: ClickableQuad) -> float:
	var idx: int = _panels.find(q)
	if idx < 0:
		return 0.0
	return _panel_pop[idx]


func panel_pop_offset(q: ClickableQuad) -> Vector3:
	var idx: int = _panels.find(q)
	if idx < 0:
		return Vector3.ZERO
	return q.position - _panel_base_pos[idx]


func pop_target() -> ClickableQuad:
	return _pop_target_panel()


## Sizing queries (the shot suites read these): the wall's
## live card size, a panel's recorded art aspect (0 = none),
## and the scale a panel reaches at FULL pop given its art -
## the very numbers _update_pop interpolates toward, so a
## shot can assert the end state without re-deriving it.
func grid_panel_size() -> Vector2:
	return _panel_size


func panel_art_aspect(q: ClickableQuad) -> float:
	var idx: int = _panels.find(q)
	if idx < 0 or idx >= _panel_art_aspect.size():
		return 0.0
	return _panel_art_aspect[idx]


## A panel's full-pop scale: UNIFORM on the dome (DOME5) -
## the flat wall's true-aspect grow is retired; every card
## pops to POP_OUT_SCALE on both axes. The signature stays
## for the shot suites that pin the end state.
func panel_full_pop_scale(q: ClickableQuad) -> Vector2:
	return Vector2(POP_OUT_SCALE, POP_OUT_SCALE)


# ------------------------------------------------------------ power-on mimic

## The power-on's per-frame driver, on _process beside the
## pop and the swing. The performer is chosen from the pop
## target (the room's one shared focus), but only after the
## candidate has RESTED for POWER_SETTLE_SEC - a focus that
## is still travelling (bumper flips, fast stick sweeps)
## never starts a cascade, so the wall stays calm under
## fast navigation. A swing reads as no candidate at
## all; detail, placard, SETUP and launch already null the
## pop target, so every cancel Chris named funnels through
## "the candidate changed (or vanished)": the performer
## restores in the same frame and the new candidate's own
## settle clock starts.
func _update_power(delta: float) -> void:
	var cand: ClickableQuad = _pop_target_panel()
	if _tournament:
		cand = null ## boards are standings, not backglasses: no power-on performance stands on a Tournament panel
	if _swing_active:
		cand = null
	if cand != null and _flip_idx >= 0 and _panels[_flip_idx] == cand and _flip_t > 0.0:
		cand = null ## a turned card shows its back: the power-on performs on fronts only (a flip starting mid-performance restores it - see _toggle_flip)
	if cand != _power_candidate:
		_power_candidate = cand
		_power_candidate_t = 0.0
		if cand != _power_missed:
			_power_missed = null
	else:
		_power_candidate_t += delta
	if _power_panel != null and cand != _power_panel:
		var trigger: String = "focus_moved"
		if _swing_active:
			trigger = "swing"
		elif cand == null:
			trigger = "focus_cleared"
		_restore_power(trigger)
	if _power_panel == null and cand != null and cand != _power_missed and _power_candidate_t >= POWER_SETTLE_SEC:
		_start_power(cand)
	if _power_panel != null and _power_phase == 1:
		_power_t += delta
		_apply_power()
		if _power_t >= POWER_CASCADE_SEC:
			_power_phase = 2
			print("POWER: phase 1->2 game=\"%s\"" % (_power_game.title if _power_game != null else ""))
			_apply_power()


## Start the power-on on a settled card. The mode is chosen
## once, here: a pair card (its flat extraction cached the
## author's On half - GameEntry.pair_on_art) crossfades,
## mode 3; every other card takes the mimic grade, mode 2.
##
## The SUBJECT the performance plays on (the graduation's
## reading of the user's law): the card's resting face is
## the author shot, so the mimic performs on the BACKGLASS
## - the shipped subject from before the shot era - rendered
## once per game and cached in _power_subject_cache (the
## window fill warms the extraction itself; focus time never
## extracts). A table with NO author shot keeps the shipped
## behavior exactly: its resting face IS the backglass (or
## the embedded/title face), and the performance samples
## the face the card already wears. A shot table with no
## backglass at all has nothing to perform on: the shot
## simply stands (marked missed, like a not-ready face).
## Either way the overlay samples a rendered face texture,
## so no extraction or file work ever happens on focus. A
## card whose face texture is somehow not ready is skipped
## for this focus (marked missed), never retried per frame.
func _start_power(panel: ClickableQuad) -> void:
	var game: GameEntry = _scanner.game_by_id(panel.payload) if _scanner != null else null
	var label: String = game.title if game != null else panel.payload
	var face_tex: Texture2D = panel.current_texture()
	if face_tex == null:
		_power_missed = panel
		print("POWER: start game=\"%s\" skipped (face texture not ready)" % label)
		return
	if face_tex == _placeholder_tex:
		# The panel still wears the wall's placeholder: its
		# face has not streamed in. Starting here would bind
		# the overlay to that dark solid for the whole
		# performance - the boot fault, where focus is
		# restored onto the last-played card at setup, before
		# any face has rendered, and the card stood dark
		# until focus moved (Chris, 2026-10-27). Skip like
		# the not-ready case above; the face's arrival in
		# the window fill clears the missed mark and the
		# performance starts on the real face, no input
		# needed.
		_power_missed = panel
		print("POWER: start game=\"%s\" skipped (face still the placeholder)" % label)
		return
	var on_tex: Texture2D = null
	var on_rendered: bool = false
	if game != null:
		var on_path: String = game.pair_on_art()
		if on_path != "":
			if OS.get_environment("PVLDS_GRADFIX12_NC") == "powerbadge":
				# NC (GRADFIX12 item 2): the pre-fix binding -
				# the raw On art rides the overlay, badgeless
				# by construction, and the subject cache below
				# ignores the favourite state - so the xpress
				# smoke's "x-press star:" legs fail by name.
				on_tex = TextureFactory.load_art_texture(on_path)
			else:
				# GRADFIX12 item 2: the crossfade's target is
				# the On half rendered as a face under the
				# CURRENT favourite state (the badge composed
				# on it), cached per state - never the raw art.
				on_tex = _power_on_cached(game)
				if on_tex == null:
					_prepare_power_on(panel, game)
					return
				on_rendered = true
	if on_tex != null and game != null and not game.has_shot_face():
		# GRADFIX8 item 2: a pair card's STANDING face is now
		# its lit On half (GameEntry._standing_face), so the
		# panel's own texture no longer holds the unlit glass
		# this crossfade starts from. Perform on the backglass
		# subject instead - the same Off extraction render the
		# shot-faced path below uses - so the cascade's first
		# instant is the dark glass exactly as before the fix,
		# and only the resting wall changed. (A shot-faced pair
		# card keeps the shipped shape: its overlay starts from
		# the shot it stands in and crossfades to the On half.)
		var pair_subject: Texture2D = _power_subject_cached(game)
		if pair_subject == null:
			_prepare_power_subject(panel, game)
			return
		face_tex = pair_subject
	if on_tex == null and game != null and game.has_shot_face():
		# The shot era's subject rule: perform on the
		# backglass, not on the shot the card rests at.
		if game.backglass_source() == "":
			_power_missed = panel
			print("POWER: start game=\"%s\" skipped (author shot stands; no backglass to perform on)" % label)
			return
		var subject: Texture2D = _power_subject_cached(game)
		if subject == null:
			# Not rendered yet: prepare it off the frame
			# path; the preparation retries the start when
			# it lands, if this card still holds the settle.
			_prepare_power_subject(panel, game)
			return
		face_tex = subject
	_power_panel = panel
	_power_game = game
	_power_t = 0.0
	_power_phase = 1
	_power_pair = on_tex != null
	_power_mode = 3 if _power_pair else 2
	_build_power_overlay(panel, face_tex, on_tex, on_rendered)
	print("POWER: start game=\"%s\" mode=%d %s" % [
		label, _power_mode,
		"pair-crossfade" if _power_pair else "mimic"])
	print("POWER: phase 0->1 game=\"%s\"" % label)
	_apply_power()


## The favourite state a power render must be composed
## under right now (GRADFIX12 item 2): the badge is part of
## a rendered face, so every cached power render is keyed
## by it - a favourite toggle changes the key, the stale
## render stops serving, and the performance re-prepares
## under the new state instead of standing a badgeless (or
## wrongly badged) performance over the toggled face. The
## powerbadge NC collapses the key to false: the pre-fix
## caches that ignored the flag altogether.
func _power_fav_key(game: GameEntry) -> bool:
	if OS.get_environment("PVLDS_GRADFIX12_NC") == "powerbadge":
		return false
	return _store != null and _store.is_favorite(game.game_id)


## The power-on's subject for a shot-faced game: its
## backglass rendered as a face (the same art render the
## card itself would wear without a shot - strip suppressed,
## the nameplate carries the name), cached per game for the
## library adoption. Null while unrendered - or while the
## cached render wears the OTHER favourite state (it was
## composed before a toggle; the performance must not
## stand it over the face the toggle just made).
func _power_subject_cached(game: GameEntry) -> Texture2D:
	var ent: Variant = _power_subject_cache.get(game.game_id, null)
	if ent == null:
		return null
	var arr: Array = ent as Array
	if arr.size() >= 3 and bool(arr[1]) != _power_fav_key(game):
		return null
	return arr[arr.size() - 1] as Texture2D


## The pair crossfade's On half, rendered as a face under
## the current favourite state (GRADFIX12 item 2) - the
## settled overlay of a pair card IS this texture, so the
## badge the player toggled must be composed on it, exactly
## as it is composed on the standing face. Null while
## unrendered or while the cache wears the other state.
func _power_on_cached(game: GameEntry) -> Texture2D:
	var ent: Variant = _power_on_cache.get(game.game_id, null)
	if ent == null:
		return null
	var arr: Array = ent as Array
	if arr.size() >= 3 and bool(arr[1]) != _power_fav_key(game):
		return null
	return arr[arr.size() - 1] as Texture2D


## Render a game's pair On face off the frame path and,
## if its card still holds the settle when the render
## lands, start the performance then (the subject
## preparation's shape, for the crossfade's target).
func _prepare_power_on(panel: ClickableQuad, game: GameEntry) -> void:
	if bool(_power_on_inflight.get(game.game_id, false)):
		return
	var on_path: String = game.pair_on_art()
	if on_path == "":
		return
	_power_on_inflight[game.game_id] = true
	var gen: int = _gen
	var fav: bool = _power_fav_key(game)
	var tex: Texture2D = null
	var src: Texture2D = TextureFactory.load_art_texture(on_path)
	if src != null:
		tex = await _factory.render_texture(RoomSpecs.art_spec(game, src, _store, false), _panel_face_px)
	_power_on_inflight.erase(game.game_id)
	if tex != null and _power_fav_key(game) == fav:
		_power_on_cache[game.game_id] = [on_path, fav, tex]
	if gen != _gen:
		return
	if tex != null and _power_panel == null and _power_candidate == panel and panel != _power_missed:
		_start_power(panel)


## Render a game's power-on subject off the frame path and,
## if its card still holds the settle when the render lands,
## start the performance then. One preparation per game at
## a time; a stale preparation (focus moved, wall rebuilt)
## just leaves the cache warm for the next visit.
func _prepare_power_subject(panel: ClickableQuad, game: GameEntry) -> void:
	if bool(_power_subject_inflight.get(game.game_id, false)):
		return
	_power_subject_inflight[game.game_id] = true
	var gen: int = _gen
	# GRADFIX6 items 2+3: the ready probe only - a cold
	# backglass must not extract synchronously on the focus
	# path (the convicted seat-path block). Ask the warmer
	# forward once per game; the candidate machinery
	# re-prepares while focus rests, and the performance
	# starts when the extraction lands.
	var path: String = game.backglass_face_path_ready()
	if path == "" and game.backglass_source() != "":
		if not _power_prefetch_asked.has(game.game_id):
			_power_prefetch_asked[game.game_id] = true
			art_prefetch_requested.emit([game])
		_power_subject_inflight.erase(game.game_id)
		return
	if path != "":
		_power_prefetch_asked.erase(game.game_id)
	var fav: bool = _power_fav_key(game)
	var tex: Texture2D = null
	if path != "":
		var src: Texture2D = TextureFactory.load_art_texture(path)
		if src != null:
			tex = await _factory.render_texture(RoomSpecs.art_spec(game, src, _store, false), _panel_face_px)
	_power_subject_inflight.erase(game.game_id)
	if tex != null and _power_fav_key(game) == fav:
		# GRADFIX12 item 2: the cache entry carries the
		# favourite state it was composed under (a toggle
		# mid-render must not let a stale badge state land).
		_power_subject_cache[game.game_id] = [path, fav, tex]
	if gen != _gen:
		return
	if tex != null and _power_panel == null and _power_candidate == panel and panel != _power_missed:
		_start_power(panel)


## Build the mimic's one overlay quad over the performing
## card's face: sized to the WHOLE face (a dome face is
## full-bleed art - the nameplate is 3D furniture riding
## above the overlay, not a band painted into the face), and
## sampling the subject's rendered face texture whole. A
## pair card's On texture rides as the shader's second
## source, windowed by the same centered cover rule
## CardFace draws the face with, so the crossfade's two
## pictures register pixel for pixel.
func _build_power_overlay(panel: ClickableQuad, face_tex: Texture2D, on_tex: Texture2D, on_rendered: bool = false) -> void:
	var art_rect: Rect2 = Rect2(0.0, 0.0, float(_panel_face_px.x), float(_panel_face_px.y))
	var face_atlas: AtlasTexture = AtlasTexture.new()
	face_atlas.atlas = face_tex
	face_atlas.region = Rect2(art_rect.position, Vector2(
		minf(art_rect.size.x, float(face_tex.get_width())),
		minf(art_rect.size.y, float(face_tex.get_height()))))
	_power_mat = ShaderMaterial.new()
	_power_mat.shader = MIMIC_SHADER
	# The overlay's rung in the card stack (see
	# _make_card_nodes): it grades the FACE, so it draws after
	# the face (-3) and the plate (-2), under the label (0).
	if OS.get_environment("PVLDS_GRAD_NC") != "nofaceorder":
		_power_mat.render_priority = -1
	_power_mat.set_shader_parameter("face_tex", face_atlas)
	_power_mat.set_shader_parameter("power", 0.0)
	_power_mat.set_shader_parameter("sweep", 0.0)
	_power_mat.set_shader_parameter("has_pair", 0.0)
	if on_tex != null:
		var on_atlas: AtlasTexture = AtlasTexture.new()
		on_atlas.atlas = on_tex
		var ow: float = float(on_tex.get_width())
		var oh: float = float(on_tex.get_height())
		if on_rendered:
			# GRADFIX12 item 2: the On source is already a
			# rendered FACE (CardFace covered it onto the
			# face canvas and composed the badge on it) -
			# it rides whole; cover-windowing it again
			# would crop the badge's corner away.
			on_atlas.region = Rect2(0.0, 0.0, ow, oh)
		else:
			var cover: float = maxf(art_rect.size.x / ow, art_rect.size.y / oh)
			var win: Vector2 = art_rect.size / cover
			on_atlas.region = Rect2((Vector2(ow, oh) - win) * 0.5, win)
		_power_mat.set_shader_parameter("on_tex", on_atlas)
		_power_mat.set_shader_parameter("has_pair", 1.0)
		_power_mat.set_shader_parameter("pair_mix", 0.0)
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(art_rect.size.x / float(_panel_face_px.x) * _panel_size.x,
		art_rect.size.y / float(_panel_face_px.y) * _panel_size.y)
	_power_overlay = MeshInstance3D.new()
	_power_overlay.mesh = qm
	_power_overlay.material_override = _power_mat
	_power_overlay.position = Vector3(
		(art_rect.get_center().x / float(_panel_face_px.x) - 0.5) * _panel_size.x,
		(0.5 - art_rect.get_center().y / float(_panel_face_px.y)) * _panel_size.y,
		0.006)
	panel.add_child(_power_overlay)


## The cascade's current frame, applied: the mimic's
## uniforms from the cascade clock - the catch envelope,
## the sweep front, and (pair cards) the crossfade. Runs
## only while a cascade is live (and once at its settle) -
## a resting room pays nothing for the effect. At settle
## the overlay STANDS (the settled card is the graded
## face, or the author's On image) until focus leaves.
func _apply_power() -> void:
	if _power_mat == null:
		return
	_sc_mimic_evals += 1 ## OPTIMIZE standing-cost audit (observation only)
	_power_mat.set_shader_parameter("power", mimic_power_at(_power_t))
	_power_mat.set_shader_parameter("sweep", clampf(_power_t / MIMIC_SWEEP_SEC, 0.0, 1.0))
	if _power_pair:
		_power_mat.set_shader_parameter("pair_mix", pair_mix_at(_power_t))


## The catch envelope (pure, so the shots can pin it): the
## mimic prototype's stutter keys, lerped - three catches
## across 0.06-0.27 s, a sag dip to 0.62 at 0.34 s, full by
## 0.48 s, held to the cascade's end.
static func mimic_power_at(t: float) -> float:
	var keys: Array = MIMIC_POWER_KEYS
	if t <= float((keys[0] as Array)[0]):
		return float((keys[0] as Array)[1])
	for i: int in range(1, keys.size()):
		var prev: Array = keys[i - 1] as Array
		var cur: Array = keys[i] as Array
		if t <= float(cur[0]):
			var span: float = float(cur[0]) - float(prev[0])
			var f: float = 0.0 if span <= 0.0 else (t - float(prev[0])) / span
			return lerpf(float(prev[1]), float(cur[1]), f)
	return 1.0


## A pair card's crossfade position at cascade time t
## (pure, like the envelope): the Off picture holds
## through the catch, then a smoothstep crossfade
## completes exactly at the cascade's end.
static func pair_mix_at(t: float) -> float:
	if t <= PAIR_MIX_T0:
		return 0.0
	if t >= POWER_CASCADE_SEC:
		return 1.0
	var f: float = (t - PAIR_MIX_T0) / (POWER_CASCADE_SEC - PAIR_MIX_T0)
	return f * f * (3.0 - 2.0 * f)


## Focus left the performer (or a cancel fired): the
## overlay is freed and the card is its normal still
## again - restore is total because exactly one performer
## ever exists. Every restore logs its trigger (the
## field trap: a cascade that dies early should say what
## killed it).
func _restore_power(trigger: String) -> void:
	print("POWER: restore trigger=%s game=\"%s\"" % [
		trigger, _power_game.title if _power_game != null else ""])
	if _power_overlay != null and is_instance_valid(_power_overlay):
		_power_overlay.queue_free()
	_power_reset_state()


## The power state, cleared WITHOUT touching any nodes -
## for _restore_power (after it has cleaned the live one)
## and for wall rebuilds (where the nodes are dying
## anyway).
func _power_reset_state() -> void:
	_power_panel = null
	_power_candidate = null
	_power_candidate_t = 0.0
	_power_phase = 0
	_power_mode = 0
	_power_pair = false
	_power_t = 0.0
	_power_game = null
	_power_overlay = null
	_power_mat = null


## Power-on queries (the mimic shot reads the effect the
## way the other smokes read theirs): the phase (0 idle,
## 1 cascading, 2 settled lit), the performing panel, the
## mode (2 mimic grade, 3 pair crossfade), the cascade
## clock, whether the performance is a pair crossfade, and
## the standing overlay count - which doubles as the
## swap's structural assertion: a performance is ONE
## quad, and no focus ever builds a layer quad or touches
## a layer cache, because that machinery no longer exists.
func power_phase() -> int:
	return _power_phase


func power_panel() -> ClickableQuad:
	return _power_panel


func power_mode() -> int:
	return _power_mode


func power_time() -> float:
	return _power_t


func power_is_pair() -> bool:
	return _power_pair


func power_overlay_count() -> int:
	return 1 if (_power_overlay != null and is_instance_valid(_power_overlay)) else 0


## Graduation queries (the graduation smoke reads the room's
## Stage B surfaces the way the other smokes read theirs):
## the centred shelf index, the background stack's layers
## (with their parents - the world-lock leg), and the flip's
## standing state (see flip_state).
func centre_index() -> int:
	return _centre_index


func drum_node() -> Node3D:
	return _wall


func background_layers() -> Array:
	var out: Array = []
	for n: Node in [_bg_starfield, _bg_starfield_near, _bg_ring]:
		if n != null:
			out.append(n)
	return out




## The bookend-fin census (GRADFIX8 item 5): how many fin
## nodes stand anywhere in the room's subtree, counted by
## the builder's own node names. The fins are REMOVED
## (Chris's order - no builder, no seating, no gating
## remains), so the honest count is zero in both views;
## the grad and tournament smokes assert exactly that.
func bookend_fin_count() -> int:
	var n: int = 0
	for node: Node in find_children("*", "Node", true, false):
		if node.name == "BookendStart" or node.name == "BookendEnd":
			n += 1
	return n


## The wireframe-shell census (GRADFIX9): how many
## wireframe shell nodes stand anywhere in the room's
## subtree, counted by the builder's own node name. The
## shell is REMOVED (Chris's order, 2026-10-31 - no
## builder, no mesh, no field remains), so the honest
## count is zero in both views; the grad and tournament
## smokes assert exactly that.
func wireframe_shell_count() -> int:
	var n: int = 0
	for node: Node in find_children("*", "Node", true, false):
		if node.name == "WireframeShell":
			n += 1
	return n


## The desk bar's standing measurements (GRADFIX5, the
## Console leg's subject): the rail row's total span and the
## strip's, read off the laid-out quads themselves - plus the
## furniture census (every stop and slot the bar must carry).
func bar_state() -> Dictionary:
	var rail_lo: float = 1.0e9
	var rail_hi: float = -1.0e9
	var rail_bottom: float = 1.0e9
	var rail_tile_h: float = 0.0
	for k: Variant in _rail_quads.keys():
		var q: ClickableQuad = _rail_quads[k] as ClickableQuad
		if q == null:
			continue
		var half: float = q.quad_size().x * 0.5
		rail_lo = minf(rail_lo, q.position.x - half)
		rail_hi = maxf(rail_hi, q.position.x + half)
		rail_bottom = minf(rail_bottom, q.position.y - q.quad_size().y * 0.5)
		rail_tile_h = maxf(rail_tile_h, q.quad_size().y)
	var strip_lo: float = 1.0e9
	var strip_hi: float = -1.0e9
	var strip_top: float = -1.0e9
	var strip_count: int = 0
	for k2: Variant in _strip_quads.keys():
		var sq: ClickableQuad = _strip_quads[k2] as ClickableQuad
		if sq == null or not sq.visible:
			continue
		strip_count += 1
		var shalf: float = sq.quad_size().x * 0.5
		strip_lo = minf(strip_lo, sq.position.x - shalf)
		strip_hi = maxf(strip_hi, sq.position.x + shalf)
		strip_top = maxf(strip_top, sq.position.y + sq.quad_size().y * 0.5)
	# GRADFIX14 (item 1): the machined strip's census - the
	# backing bar's count (1 shipped, 0 under tileboxes),
	# the widest gap between neighbouring sections (0
	# shipped, RAIL_GAP under tileboxes), the sections'
	# order + widths read left to right off the laid-out
	# quads, and the lift census (how many sections stand
	# lifted, the greatest lift, and the focused stop's key).
	var rail_sorted: Array = []
	for k3: Variant in _rail_quads.keys():
		var q3: ClickableQuad = _rail_quads[k3] as ClickableQuad
		if q3 != null:
			rail_sorted.append([q3.position.x, str(k3), q3.quad_size().x])
	rail_sorted.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var rail_keys: Array[String] = []
	var rail_widths: Array[float] = []
	var rail_gap_max: float = 0.0
	for i3: int in range(rail_sorted.size()):
		rail_keys.append(str(rail_sorted[i3][1]))
		rail_widths.append(float(rail_sorted[i3][2]))
		if i3 > 0:
			var prev_right: float = float(rail_sorted[i3 - 1][0]) + float(rail_sorted[i3 - 1][2]) * 0.5
			var this_left: float = float(rail_sorted[i3][0]) - float(rail_sorted[i3][2]) * 0.5
			rail_gap_max = maxf(rail_gap_max, this_left - prev_right)
	var rail_lifted: int = 0
	var rail_lift_max: float = 0.0
	for k4: Variant in _rail_base_pos.keys():
		var off: float = rail_lift_offset(str(k4)).length()
		rail_lift_max = maxf(rail_lift_max, off)
		if off > RAIL_STRIP_LIFT * 0.5:
			rail_lifted += 1
	var rail_lift_target: String = ""
	if _focused != null:
		for k5: Variant in _rail_quads.keys():
			if _rail_quads[k5] == _focused:
				rail_lift_target = str(k5)
	return {
		"rail_span": rail_hi - rail_lo if rail_hi > rail_lo else 0.0,
		"strip_span": strip_hi - strip_lo if strip_hi > strip_lo else 0.0,
		"rail_stops": _rail_quads.size(),
		"rail_bar_count": 1 if _rail_bar != null else 0,
		"rail_gap_max": rail_gap_max,
		"rail_keys": rail_keys,
		"rail_widths": rail_widths,
		"rail_lifted": rail_lifted,
		"rail_lift_max": rail_lift_max,
		"rail_lift_target": rail_lift_target,
		"strip_slots": strip_count,
		# Console pass 2 (GRADFIX6 item 4): the tile height
		# and the vertical air between the rows, read off the
		# laid-out quads like the spans - the grad legs bind
		# both (gap >= 0.050 against GRADFIX5's 0.025, tile
		# height <= 0.120 against GRADFIX5's 0.135).
		"rail_tile_h": rail_tile_h,
		"rail_strip_gap": rail_bottom - strip_top if rail_bottom < 1.0e8 and strip_top > -1.0e8 else 0.0,
		"status_size": (_status_plate.mesh as QuadMesh).size if _status_plate != null and _status_plate.mesh is QuadMesh else Vector2.ZERO,
	}


## One card's title-label AABB in world space (the census
## measures labels against occluders in exactly this form).
func panel_label_world_aabb(idx: int) -> AABB:
	if idx < 0 or idx >= _panel_labels.size() or _panel_labels[idx] == null:
		return AABB()
	var l: Label3D = _panel_labels[idx]
	return l.global_transform * l.get_aabb()


## Travel queries (the nav smoke and the shots read the
## room's travel the way the other smokes read their
## subjects): the drum's yaw DEVIATION from its swing target
## in degrees - 0.0 is exact rest at the centred column -
## and whether a swing is live. (The flat wall's slide seam,
## kept under its name: the quantity it always meant was
## "how far the wall stands from rest".)
func page_slide_yaw_deg() -> float:
	if _wall == null:
		return 0.0
	return rad_to_deg(absf(_drum_yaw - _swing_to))


func page_slide_active() -> bool:
	return _swing_active


## Motion queries (GRADFIX10 items 2+3, the motion smoke
## reads the travel the way the nav smoke reads its
## subjects): the drum's current yaw and its standing
## target, in radians, and one standing board's current
## pop offset (its pair card's pop amount drives it - see
## _update_pop).
func drum_yaw_rad() -> float:
	return _drum_yaw


## The drum's yaw in degrees and whether a swing is live
## (GRADFIX12 item 1: the motion smoke's dense traces sample
## the travel through these, at the pacing the box runs).
func drum_yaw_deg() -> float:
	return rad_to_deg(_drum_yaw)


func swing_active() -> bool:
	return _swing_active


## The drum's standing swing velocity, degrees per second
## (the motion traces read it beside the yaw so a velocity
## spike and an external yaw jump are distinguishable).
func swing_velocity_deg_s() -> float:
	return rad_to_deg(_swing_vel)


func swing_target_rad() -> float:
	return _swing_to


func board_pop_offset(idx: int) -> Vector3:
	if idx < 0 or idx >= _board_nodes.size() or idx >= _board_base_pos.size():
		return Vector3.ZERO
	var node: MeshInstance3D = _board_nodes[idx] as MeshInstance3D
	if node == null:
		return Vector3.ZERO
	return node.position - (_board_base_pos[idx] as Vector3)


func _on_detail_closed() -> void:
	_mode = "wall"
	# Favorites / recents may have changed in detail: rebuild the wall.
	_recompute_visible()
	_rebuild_wall()


func _unhandled_input(event: InputEvent) -> void:
	if _launching_game_id != "":
		return ## the load wait is deaf: no focus moves, no activation, no detail escape
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_LEFT:
				_move_focus(Vector2(-1.0, 0.0))
			KEY_RIGHT:
				_move_focus(Vector2(1.0, 0.0))
			KEY_UP:
				_move_focus(Vector2(0.0, -1.0))
			KEY_DOWN:
				_move_focus(Vector2(0.0, 1.0))
			KEY_TAB:
				_cycle_focus(1)
			KEY_Y:
				_info_focused_card() ## keyboard parity with the pad's Y (see _process)
			KEY_X:
				_toggle_focused_favorite() ## keyboard parity with the pad's X (see _process)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_a_press() ## keyboard parity with the pad's A (see _process)
			KEY_ESCAPE:
				if _mode == "detail":
					_detail.handle_escape()


## Scroll telemetry: the witness closes its file (final
## flush + footer) as the room leaves the tree, so a normal
## exit always lands the complete log.
func _exit_tree() -> void:
	_art_stopping = true
	_gen += 1 # the pipeline pass breaks at its next await; no new face starts
	if _scroll_telemetry_started:
		_scroll_telemetry.close()
		_scroll_telemetry_started = false


func _process(delta: float) -> void:
	var tel_proc_t0: int = Time.get_ticks_usec() ## GRADFIX17 telemetry: this frame's room-side segment clock
	# The flat (non-XR) camera is STATIC at the seated viewpoint - the
	# mouse is a pure pointer there, never a look control. A view that
	# drifts with the cursor makes every click target swim (field
	# finding, round 2). XR head tracking owns the view in XR only.
	# Gamepad: the left stick moves focus, A starts the
	# focused card (selects everywhere else), B goes back in
	# the detail view, Y opens the focused card's info, X
	# toggles the focused card's favorite.
	# D-pad movement is NUKED (GRADFIX10 item 5, Chris's
	# order): "the directional pad left can navigate, which
	# is gonna let the player think they can use right
	# directional, which ends game. nuke directional
	# movement." D-pad Left/Up/Down read NOTHING here - the
	# stick (plus bumpers and the triggers' wall anchors) is
	# the only directional navigation on the pad. Keyboard
	# arrows in _unhandled_input are a separate surface and
	# keep their movement.
	# D-pad Right is NOT a focus direction: it is the BACK button,
	# with exactly two meanings in the whole app (the player's
	# ruling, 2026-10-22 - no hold gesture exists anywhere). In
	# play it is VPX's own Exit Game binding: the press lands in
	# the editor and the watchdog's close duty brings the room
	# back. Here in the room, a FRESH press of it quits the app to
	# the desktop - the rail EXIT action, on the pad. The left
	# stick still moves focus in all four directions, right
	# included.
	# The press must also be ARMED (baseline-release arming,
	# field forensics 2026-10-22): a watchdog-relaunched room
	# once exited through this very path with no human press -
	# its controller reconnected mid-relaunch and the button
	# read pressed as the fresh instance polled, manufacturing
	# an edge out of _joy_prev_right's initial false. The exit
	# may fire only on a press edge that occurs AFTER this room
	# instance has observed the button released at least once.
	# A button pressed at the instance's first poll - stuck,
	# reconnect transient, still held from the game - can never
	# fire it, no matter how long it sits pressed; once a
	# released poll is witnessed, fresh presses work at once.
	# During the load wait the room is deaf (see begin_launch): the
	# poll still tracks button state - so a press held through the
	# settle can't resurface as a phantom edge afterwards - but it
	# moves no focus, activates nothing, and escapes nothing. On
	# the SETUP placard the press also does nothing: BACK is the
	# only way off the placard.
	# The loading marquee animates on this same per-frame beat.
	# Scroll telemetry (observation only): start the witness
	# on the room's first visible frame, and snapshot the
	# drum's motion state BEFORE this frame's swing update -
	# the frame record below reads it against the after.
	_telemetry_start_if_needed()
	var telemetry_motion_was_active: bool = _swing_active or _nc_roll_dir != 0 or absf(_swing_vel) > 0.0001
	var telemetry_applied_yaw_before: float = _wall.rotation.y if _wall != null else _drum_yaw
	if _marquee_up:
		_update_marquee(delta)
	_update_background(delta) ## the starfield drift (GRADFIX4 item 5d) - its own beat, ungated
	if _plates_pending:
		# Nameplates re-derive from the labels' live AABBs
		# until every standing card's plate wears its shaped
		# block (the seat-time AABB reads empty - see
		# _refresh_card_plate).
		_plates_pending = not _refresh_all_card_plates()
	if _setup_render_pending and not _setup_render_in_flight and _setup_panel_up:
		# A throttled progress render whose state stopped
		# changing inside its window: run it now (the clock
		# inside _request_setup_panel_render still applies).
		_request_setup_panel_render(false)
	_update_pop(delta)
	_update_rail_lift(delta)
	_update_swing(delta)
	# Scroll telemetry (observation only): one frame record
	# per rendered frame in which the drum was moving when
	# the frame began or still is when its swing update has
	# run - target, actual and applied yaw, velocity, and
	# the driver state that produced them.
	if _scroll_telemetry_started and visible and (telemetry_motion_was_active or _swing_active or _nc_roll_dir != 0 \
			or absf(_swing_vel) > 0.0001 or absf((_wall.rotation.y if _wall != null else _drum_yaw) - telemetry_applied_yaw_before) > 0.0000001):
		var frame_fields: Dictionary = _telemetry_context()
		frame_fields["engine_frame"] = Engine.get_process_frames()
		frame_fields["frame_delta_ms"] = delta * 1000.0
		frame_fields["phase"] = "after_swing_update"
		frame_fields["swing_journey"] = _swing_journey
		frame_fields["swing_cols"] = _swing_cols
		frame_fields["swing_duration_s"] = _swing_duration
		_telemetry_record("frame", frame_fields)
	# GRADFIX17 telemetry: the motion half of this frame's
	# room work (background, plates, pop, swing) as one
	# segment - slow frames name it, so a hitch the art
	# seams did not cause still lands in the log with an
	# address.
	var tel_proc_a_ms: float = float(Time.get_ticks_usec() - tel_proc_t0) / 1000.0
	if tel_proc_a_ms >= 10.0:
		_art_event("seg", {"seg": "process_motion", "cost_ms": tel_proc_a_ms, "col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1, "nc_roll_dir": _nc_roll_dir})
	# OPTIMIZE standing-cost audit: accumulate at-rest time
	# (observation only). Rest = no swing, no pop motion in
	# flight, no power cascade, no pipeline pass.
	var sc_resting: bool = not _swing_active and _nc_roll_dir == 0 and _power_phase != 1 and not _art_pipe_busy
	if sc_resting:
		if _sc_rest_since == 0:
			_sc_rest_since = Time.get_ticks_msec()
	elif _sc_rest_since > 0:
		_sc_rest_msec += Time.get_ticks_msec() - _sc_rest_since
		_sc_rest_since = 0
	_update_power(delta)
	# NEVERBLANK NC (clearfirst) only: the deferred real
	# binds land after their clear dwell. Empty in every
	# production run.
	if not _nb_nc_pending.is_empty():
		var nb_still: Array = []
		for nb_ent: Variant in _nb_nc_pending:
			var nb_arr: Array = nb_ent as Array
			var nb_left: int = int(nb_arr[2]) - 1
			if nb_left <= 0:
				(nb_arr[0] as ClickableQuad).set_texture(nb_arr[1] as Texture2D)
			else:
				nb_arr[2] = nb_left
				nb_still.append(nb_arr)
		_nb_nc_pending = nb_still
	var deaf: bool = _launching_game_id != ""
	var telemetry_cooldown_before: float = _joy_cooldown ## scroll telemetry: the poll's before (read-only)
	var telemetry_roll_before_poll: int = _nc_roll_dir ## scroll telemetry: the NC roll state as this poll began (read-only)
	_joy_cooldown = maxf(0.0, _joy_cooldown - delta)
	_step_rest_timer = maxf(0.0, _step_rest_timer - delta)
	var ax: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ay: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var dir: Vector2 = Vector2.ZERO
	if ax < -0.55:
		dir = Vector2(-1.0, 0.0)
	elif ax > 0.55:
		dir = Vector2(1.0, 0.0)
	elif ay < -0.55:
		dir = Vector2(0.0, -1.0)
	elif ay > 0.55:
		dir = Vector2(0.0, 1.0)
	if debug_input_nc == "dpadmove":
		# The GRADFIX10 negative-control seam (harness env
		# PVLDS_INPUT_NC=dpadmove): restores the pre-nuke
		# binding - D-pad Left/Up/Down OR'd into the focus
		# directions - so the input smoke's dpad-nuke legs
		# fail by name. Empty in every real run.
		if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
			dir = Vector2(-1.0, 0.0)
		elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
			dir = Vector2(0.0, -1.0)
		elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
			dir = Vector2(0.0, 1.0)
	# The NC roll's context law (debug_opt_nc="smoothcruise"
	# only; production never rolls): the roll stands only
	# while its world stands - the plain library wall, no
	# panel or placard up, no load wait, a card focused.
	# Anything else ends it, and the stepped landing settles
	# the drum at the roll's standing target.
	if _nc_roll_dir != 0 and (_mode != "wall" or _tournament or _placard_up or _setup_panel_up \
			or deaf or _focused == null or _panels.find(_focused) < 0):
		_nc_roll_dir = 0
	# The hold bookkeeping: the poll counts the discrete
	# steps of ONE continuous hold (same direction, stick
	# never released). OPTIMIZE: every step of a hold is a
	# discrete _move_focus step at the repeat cadence - a
	# hold is a train of steps, and no step ever arms a
	# cruise. (The count survives for ONE reason: the
	# debug_opt_nc="smoothcruise" seam arms its roll on the
	# hold's second same-direction step.) A release or a
	# direction change ends the hold and the seam's roll.
	if dir == Vector2.ZERO:
		_nc_roll_dir = 0
		_joy_hold_dir = Vector2.ZERO
		_joy_hold_steps = 0
		_joy_step_queued = Vector2.ZERO ## a queued hold-repeat dies with the hold
	elif dir != _joy_hold_dir:
		_nc_roll_dir = 0
		_joy_hold_dir = dir
		_joy_hold_steps = 0
		_joy_step_queued = Vector2.ZERO ## and with a direction change
	# Scroll telemetry (observation only): this poll's step
	# decision, named as the branches below take it. The
	# locals are written by the branches and read only by
	# the record after them - they steer nothing.
	var telemetry_decision: String = "none"
	var telemetry_decision_source: String = "poll"
	var telemetry_decision_reason: String = "stick_neutral" if dir == Vector2.ZERO else "cooldown_active"
	var telemetry_hold_steps_before_decision: int = _joy_hold_steps
	var telemetry_cooldown_at_poll: float = _joy_cooldown
	if dir != Vector2.ZERO and _joy_cooldown <= 0.0:
		var next_cooldown: float = 0.24 ## OPTIMIZE finish: a queue-wait re-checks sooner (assigned at the block's foot)
		if not deaf:
			if _nc_roll_dir != 0:
				telemetry_decision = "none_discrete_step"
				telemetry_decision_source = "nc_roll"
				telemetry_decision_reason = "nc_roll_owns_hold_travel"
				pass ## the NC seam's roll IS this hold's travel: no discrete step fires under it
			elif debug_opt_nc == "smoothcruise" and _joy_hold_steps >= 1 and absf(dir.x) > 0.5 \
					and _mode == "wall" and not _tournament and not _placard_up and not _setup_panel_up \
					and _focused != null and _panels.find(_focused) >= 0:
				# NC seam only: the hold's second same-direction
				# step arms the continuous roll instead of
				# another discrete step - the deleted SMOOTH
				# gait's held-cruise shape, by name.
				telemetry_decision = "begin_nc_roll"
				telemetry_decision_source = "hold_counter"
				telemetry_decision_reason = "second_same_direction_step"
				_nc_roll_dir = 1 if dir.x > 0.0 else -1
				_move_focus(dir)
				_joy_hold_steps += 1
			elif _joy_step_queued == dir and not _swing_active and _step_rest_timer <= 0.0:
				# OPTIMIZE finish: the queued hold-repeat
				# fires - the drum has landed and rested,
				# and the stick still holds the queued
				# direction (the bookkeeping above cleared
				# the queue on any release or change).
				telemetry_decision = "step"
				telemetry_decision_source = "queued_step"
				telemetry_decision_reason = "queued_repeat_fired_after_landing"
				_joy_step_queued = Vector2.ZERO
				_move_focus(dir)
				_joy_hold_steps += 1
			elif _joy_hold_steps >= 1 and (_swing_active or _step_rest_timer > 0.0):
				# OPTIMIZE finish (the hold-cadence fix): a
				# hold-REPEAT never retargets a flying or
				# just-landed drum - that retarget is what
				# blended the step train into one glide (the
				# journey spring never landed between the
				# poll's 0.24 s retargets). The repeat queues
				# instead, and the poll re-checks shortly.
				telemetry_decision = "step_queued"
				telemetry_decision_source = "poll"
				telemetry_decision_reason = "repeat_waits_for_landing"
				_joy_step_queued = dir
				next_cooldown = STEP_QUEUE_RECHECK_SEC
			else:
				telemetry_decision = "step"
				telemetry_decision_source = "move_focus"
				telemetry_decision_reason = "discrete_step_fired"
				_move_focus(dir)
				_joy_hold_steps += 1
		else:
			telemetry_decision = "suppressed"
			telemetry_decision_source = "poll"
			telemetry_decision_reason = "launch_wait_deaf"
		_joy_cooldown = next_cooldown
	# Scroll telemetry (observation only): the poll record -
	# one per rendered frame, at the product's own cadence,
	# with the raw axes exactly as the poll read them.
	if _scroll_telemetry_started and visible:
		var poll_fields: Dictionary = _telemetry_context()
		poll_fields["engine_frame"] = Engine.get_process_frames()
		poll_fields["frame_delta_ms"] = delta * 1000.0
		poll_fields["joy_axis_x"] = ax
		poll_fields["joy_axis_y"] = ay
		poll_fields["dir_x"] = dir.x
		poll_fields["dir_y"] = dir.y
		poll_fields["deadzone_threshold"] = 0.55
		poll_fields["step_decision"] = telemetry_decision
		poll_fields["step_source"] = telemetry_decision_source
		poll_fields["step_reason"] = telemetry_decision_reason
		poll_fields["cooldown_before_s"] = telemetry_cooldown_before
		poll_fields["cooldown_at_poll_s"] = telemetry_cooldown_at_poll
		poll_fields["cooldown_after_s"] = _joy_cooldown
		poll_fields["repeat_cooldown_s"] = 0.24
		poll_fields["hold_steps_before_decision"] = telemetry_hold_steps_before_decision
		poll_fields["hold_steps_after"] = _joy_hold_steps
		poll_fields["nc_roll_dir_before_poll"] = telemetry_roll_before_poll
		poll_fields["nc_roll_dir_after_poll"] = _nc_roll_dir
		poll_fields["deaf"] = deaf
		_telemetry_record("poll", poll_fields)
	var a_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if a_now and not _joy_prev_a and _focused != null and not deaf:
		_a_press()
	_joy_prev_a = a_now
	var b_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	if b_now and not _joy_prev_b and not deaf:
		if _mode == "detail":
			_detail.handle_escape()
		elif _submit_panel_up:
			hide_submit_panel() ## B is BACK on the submit panel - it never exits the tournament from behind the panel
		elif _setup_panel_up:
			hide_setup_panel() ## B is BACK on the SETUP panel too
		elif _tournament and _mode == "wall" and debug_b_nc != "nobexit":
			_b_exit_tournament() ## B leaves the Tournament view for Table Select (GRADFIX4 item 4)
	_joy_prev_b = b_now
	# Y: flip the focused card (GRADFIX6 item 1 - Chris's
	# ruling, 2026-10-31; Y's old More Info binding is
	# retired, the detail view lives on the pointer's card
	# click). Edge only, like A and B; the prev-state update
	# runs even while deaf, so a press held through the load
	# wait can't resurface as a phantom flip on the other
	# side. The mode/focus gating lives in
	# _info_focused_card.
	var y_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	if y_now and not _joy_prev_y and not deaf:
		_info_focused_card()
	_joy_prev_y = y_now
	# X: favorite the focused card (Chris's proposal,
	# 2026-10-25 - flagging a favorite must not cost a trip
	# into the detail view). Same discipline as Y: edge only,
	# the prev-state update runs even while deaf so a press
	# held through the load wait can't resurface as a phantom
	# toggle afterwards; the mode/focus gating lives in
	# _toggle_focused_favorite.
	var x_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	if x_now and not _joy_prev_x and not deaf:
		_toggle_focused_favorite()
	_joy_prev_x = x_now
	# Bumpers (LB/RB): the unified travel grammar's step
	# (GRADFIX14 item 3): wall focus = page travel, the
	# section slide (Chris's banked note, 2026-10-23; his
	# clarification, 2026-10-24: "my intention for bumpers
	# was for the entire section to shift left or right,
	# one page to other"); rail focus = one rail stop;
	# strip focus = one strip slot; tournament block = one
	# card column. One step per fresh press - edge only, no
	# held repeat - and the dispatch + gating (load wait,
	# placard, detail view) lives in _bumper_page.
	# The prev-state updates run even while gated, so a bumper
	# held through a gated stretch can't resurface as a phantom
	# edge on the other side.
	var lb_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	var rb_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	if lb_now and not _joy_prev_lb:
		_bumper_page(-1)
	elif rb_now and not _joy_prev_rb:
		_bumper_page(1)
	_joy_prev_lb = lb_now
	_joy_prev_rb = rb_now
	# Triggers (LT/RT): the focused zone's anchors
	# (GRADFIX10 item 4 - Chris: "the bumpers move left/right
	# one slot. I'm thinking triggers should cycle between
	# left middle right of the entire board"; GRADFIX14
	# item 3 extends the hop to every zone: wall columns,
	# rail stops, strip pickable slots, the tournament
	# block's own columns). An analog axis has no button
	# edge, so
	# the edge is manufactured: the trigger reads DOWN once
	# its value crosses TRIGGER_PRESS_THRESHOLD, a step fires
	# only on the up->down crossing, and it cannot fire again
	# until the value falls back below the threshold (release
	# re-arming - a held trigger never auto-repeats). The
	# prev-state updates run even while deaf, like the
	# bumpers', so a trigger held through the load wait can't
	# resurface as a phantom step afterwards. The landing
	# law lives in _trigger_anchor.
	var lt_down: bool = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_PRESS_THRESHOLD
	var rt_down: bool = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_PRESS_THRESHOLD
	if debug_input_nc != "notrig" and not deaf:
		if lt_down and not _joy_prev_lt:
			_trigger_anchor(-1)
		elif rt_down and not _joy_prev_rt:
			_trigger_anchor(1)
	_joy_prev_lt = lt_down
	_joy_prev_rt = rt_down
	var right_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT)
	if not right_now:
		_joy_right_armed = true ## a witnessed released poll: fresh press edges count from here on
	if right_now and not _joy_prev_right and _joy_right_armed and not deaf:
		if _submit_panel_up:
			hide_submit_panel() ## on the submit panel D-pad Right is BACK - it never exits
		elif _setup_panel_up:
			hide_setup_panel() ## on the SETUP panel the BACK button goes back - it never exits
		elif not _placard_up:
			_handle_rail("exit")
	_joy_prev_right = right_now
	# GRADFIX17 telemetry: the whole _process as one segment
	# (see process_motion above) - the poll half's cost is
	# the difference, and a slow poll names itself here when
	# the motion half was cheap.
	var tel_proc_all_ms: float = float(Time.get_ticks_usec() - tel_proc_t0) / 1000.0
	if tel_proc_all_ms >= 10.0:
		_art_event("seg", {"seg": "process_all", "cost_ms": tel_proc_all_ms, "col": _grid_coord(_centre_index).x if _centre_index >= 0 else -1, "nc_roll_dir": _nc_roll_dir})


func _cycle_focus(step: int) -> void:
	if _focusables.is_empty():
		return
	var idx: int = _focusables.find(_focused)
	idx = (idx + step) % _focusables.size()
	_set_focused(_focusables[idx])


## The control rail's focus stops in their left-to-right build
## order (see _build_rail's defs). page_label builds too but is
## not pickable, so it is not a stop. Sideways travel along the
## rail walks THIS order and nothing else.
const RAIL_FOCUS_ORDER: Array[String] = [
	"filter:all", "filter:vr", "filter:favorites", "filter:recents", "filter:new",
	"sort", "tournament", "wovp_refresh", "desk", "exit",
] ## GRADFIX8 (item 6): no page_prev/page_next - the pager stops are removed (Chris's order); the readout between them was never a stop and stays a readout. GRADFIX11: filter:new joins the walk after filter:recents, matching its seat in _build_rail's defs (Chris's order).


func _is_rail_quad(q: ClickableQuad) -> bool:
	return q != null and _rail_quads.values().has(q)


func _is_strip_quad(q: ClickableQuad) -> bool:
	return q != null and _strip_quads.values().has(q)


## A quad's navigation country: 0 the wall, 1 the rail, 2 the
## strip. Sideways travel never crosses countries (the rail's
## law, extended to the strip when the letter-jump round gave
## the rail a second row). Vertically the ladder is strict:
## the grid steps DOWN to the rail and the strip steps UP to
## it - neither may step past the rail to the other, however
## the projection scores it (the strip's first build let a
## bottom-row DOWN land on a letter, skipping the rail the
## player's DOWN contract promises).
func _focus_country(q: ClickableQuad) -> int:
	if _is_rail_quad(q):
		return 1
	if _is_strip_quad(q):
		return 2
	return 0


## The order the strip's sideways walk visits its slots:
## the ONE list (_strip_slot_keys) - the same order the
## layout draws and the eye sees. The row CLAMPS at both
## ends (the rail's law, kept): a step past either end
## leaves focus where it stands, so every pickable slot is
## reachable by holding one direction from wherever the
## strip is entered. The NC value "striporder" permutes
## this to the pre-fix fiction ("#" first, THE last - the
## order the walk believed before the strip-order fix) so
## the letters smoke's full-strip-walk legs fail by name.
func _strip_walk_order() -> Array:
	if debug_focus_nc == "striporder":
		var perm: Array = ["#"]
		for i: int in range(26):
			perm.append(String.chr(65 + i))
		perm.append("THE")
		return perm
	var out: Array = []
	out.assign(_strip_slot_keys())
	return out


## The next focus stop along the focused quad's own row - the
## rail in RAIL_FOCUS_ORDER, the strip in its layout order -
## skipping stops that are not focusable right now (the
## strip's greyed letters among them). Null at the row's end -
## focus stays put there.
func _rail_focus_neighbour(step: int) -> ClickableQuad:
	if _focused == null:
		return null
	var quads: Dictionary = _rail_quads
	var order: Array = []
	order.assign(RAIL_FOCUS_ORDER)
	if _is_strip_quad(_focused):
		quads = _strip_quads
		order = _strip_walk_order()
	var idx: int = -1
	for i: int in range(order.size()):
		var cand: ClickableQuad = quads.get(str(order[i])) as ClickableQuad
		if cand != null and cand == _focused:
			idx = i
			break
	if idx < 0:
		return null
	var j: int = idx + step
	while j >= 0 and j < order.size():
		var q: ClickableQuad = quads.get(str(order[j])) as ClickableQuad
		if q != null and q.pick_enabled and _focusables.has(q):
			return q
		j += step
	return null


## The trap NC (GRADFIX3 item 3): PVLDS_TOURN_NC=trap
## restores the shipped descent - DOWN from the bottom of a
## column falls through to the screen-projection walk
## instead of taking the deterministic descent edge. Its
## scope is stated plainly: on this box's mono desk camera
## the shipped projection still lands on the bar, so the
## tournament smoke's descent legs pass under the NC too -
## the trap is a headset-camera condition (the walk scored
## through the XR camera's unprojection) that no mono
## camera here reproduces. What the NC restores is the
## DEPENDENCE; the fix removes it, which is the strongest
## statement the evidence supports. Empty in every real
## run.
func _descent_legacy() -> bool:
	return OS.get_environment("PVLDS_TOURN_NC") == "trap"


## The oldseat NC (PVLDS_TOURN_NC=oldseat): the pre-GRADFIX2
## Tournament behaviour's surviving half - the focus walk in
## the Tournament Room used projection scoring instead of
## the drum's grid step. (Its other half - the old standing
## board borrowing the slot right of the centred challenge,
## hiding its card - died with that board in GRADFIX6 and
## stays dead: GRADFIX7's standing boards seat in their own
## pair slots by the layout law, and the tournament smoke's
## no-borrow legs guard those seats.) Empty in every real
## run.
func _tournament_legacy() -> bool:
	return OS.get_environment("PVLDS_TOURN_NC") == "oldseat"


## The descent to the bar (GRADFIX3 item 3): DOWN from the
## bottom of a card column lands on the desk bar - the rail
## stop nearest the card in CAMERA SPACE (the camera's own
## sideways axis), a projection-free measure that holds for
## the headset's camera exactly as for the desk's: which
## stop is "under where you are" is a fact about the room,
## not about a viewport. The bar is always reachable from
## the cards by this edge, in every view that has cards -
## the exit legs judge it from every tournament challenge.
func _descend_to_bar() -> void:
	var cam: Camera3D = _active_camera()
	var from_x: float = 0.0
	if cam != null and _focused != null:
		from_x = (cam.global_transform.affine_inverse() * _focused.global_position).x
	var best: ClickableQuad = null
	var best_d: float = INF
	for key: String in RAIL_FOCUS_ORDER:
		var q: ClickableQuad = _rail_quads.get(key) as ClickableQuad
		if q == null or not q.pick_enabled or not _focusables.has(q):
			continue
		var d: float = 0.0
		if cam != null:
			d = absf((cam.global_transform.affine_inverse() * q.global_position).x - from_x)
		if best == null or d < best_d - 0.001:
			best_d = d
			best = q
	if best != null:
		_set_focused(best)


## The panel standing in a column whose band is nearest a
## preferred band, or -1 when the column holds no panel
## (the trigger anchors' landing shape, shared): at a
## partial column the nearest band takes the landing -
## never a neighbouring column.
func _panel_in_column(col: int, pref_band: int) -> int:
	var best: int = -1
	var best_d: int = 999999
	for i: int in range(_panels.size()):
		var c: Vector2i = _grid_coord(i)
		if c.x != col:
			continue
		var d: int = absi(c.y - pref_band)
		if d < best_d:
			best_d = d
			best = i
	return best


## THE VERTICAL WALL LAW (GRADFIX13 item 4 - the mirror of
## the standing focus law "picks move the wall, never the
## focus"): a purely vertical focus change between the rail
## and the card rows - either direction - NEVER changes the
## drum's seated column. Chris's field report: "when down
## in filter bar, and you bump straight up to table rows,
## it advances the wall one slot to right."
##
## The convicted mechanism: the DESCENT (rows -> rail) has
## been a deterministic graph edge since GRADFIX3
## (_descend_to_bar), but the ASCENT (rail -> rows) had no
## edge of its own - UP from a rail stop fell through to
## the screen-projection walk at the bottom of _move_focus,
## which scores every focusable by its unprojected screen
## position. The rail's stops are spread ~80 degrees of
## azimuth at their near seat while the wall's columns
## pitch 13.5 degrees on the far drum, so a stop's screen
## projection commonly sits under the card one column off
## the seated centre (a stop right of screen centre scores
## the centre+1 column's bottom card best). Focus landed
## there, and _follow_centre - doing exactly its job -
## re-seated the drum on the focused card's column: the
## wall advanced one slot right, on a press that asked
## only to go up. The descent never did this because it
## never passes through the projection walk; the ascent
## was asymmetric with it.
##
## THE ASCENT LANDING RULE (deterministic, projection-
## free, the descent's mirror): UP from any rail stop
## lands on the CENTRE column's card on the centre band -
## the column is the drum's seated centre column (the
## column of _centre_index, the centre the bookkeeping
## committed, even mid-swing) and the band is that centre
## card's own band. There is no remembered "last band":
## the row landed on is the band the wall currently
## declares as its centre, which is the band focus stood
## on when it descended (focus moves the centre), and a
## strip -> rail -> rows climb after other browsing lands
## on the standing centre's band for the same reason. At a
## shelf edge, where the centre column stands PARTIAL and
## holds no card on the centre band, the landing is that
## column's card nearest the centre band (_panel_in_
## column) - the column never yields to a neighbour.
## Because the landing IS the centre card (or its partial-
## column stand-in in the same column), _follow_centre
## finds the centre already standing where focus landed:
## the drum does not move, in either dial position, at
## any pacing. The NC value "oldascent" skips this edge
## and restores the projection ascent for the harness.
func _ascend_to_rows() -> void:
	if _panels.is_empty() or _centre_index < 0 or _centre_index >= _panels.size():
		return
	var centre_coord: Vector2i = _grid_coord(_centre_index)
	var idx: int = _panel_in_column(centre_coord.x, centre_coord.y)
	if idx >= 0:
		_set_focused(_panels[idx])


## A sideways step in the Tournament Room (GRADFIX7 item
## 2): land on the NEAREST CARD COLUMN in that direction -
## board columns are skipped, the ends clamp (no card that
## way = stay). Within the nearest card column, the same
## band wins; an unpaired column's lone card takes the step
## from either band.
func _tourn_side_step(pidx: int, step: int) -> int:
	var cur: Vector2i = _grid_coord(pidx)
	var best_col: int = -1
	for i: int in range(_visible_games.size()):
		var c: Vector2i = _grid_coord(i)
		if step > 0 and c.x <= cur.x:
			continue
		if step < 0 and c.x >= cur.x:
			continue
		if best_col < 0 or absi(c.x - cur.x) < absi(best_col - cur.x):
			best_col = c.x
	if best_col < 0:
		return pidx
	var best: int = pidx
	var best_band_dist: int = 1 << 30
	for i2: int in range(_visible_games.size()):
		var c2: Vector2i = _grid_coord(i2)
		if c2.x != best_col:
			continue
		var bd: int = absi(c2.y - cur.y)
		if bd < best_band_dist:
			best_band_dist = bd
			best = i2
	return best


func _move_focus(dir: Vector2) -> void:
	if _focusables.is_empty():
		return
	if _focused == null or not _focusables.has(_focused):
		_set_focused(_focusables[0])
		return
	# The drum's own stepping (DOME5's navigation): while a
	# CARD holds focus, a sideways step moves one COLUMN along
	# the shelf and a vertical step moves one BAND - grid
	# steps on the index, not projection steps across a
	# curved wall (the projection walk below would score a
	# neighbour two columns away over the adjacent card at
	# the sphere's edge). DOWN from the bottom of a column
	# is the one exit, and since GRADFIX3 it is a graph edge
	# of its own (the descent to the bar, _descend_to_bar):
	# the shipped room let it fall through to the projection
	# walk - the focus graph's only view-dependent edge -
	# and in the headset that edge is the one that died
	# ("cant't exit tournie screen, cant get back down to
	# bar once up top", the user's field report); every
	# projection-independent step worked there, as here. The
	# centre follows focus (see _update_pop), so the drum
	# swings under every step.
	var pidx: int = _panels.find(_focused)
	if pidx >= 0 and _mode == "wall" and (not _tournament or not _tournament_legacy()):
		var coord: Vector2i = _grid_coord(pidx)
		if _tournament:
			# GRADFIX7 item 2: the pair grid's own stepping -
			# sideways lands on the nearest CARD column (board
			# columns skipped, ends clamp); vertical steps run
			# within the card's own column, and DOWN off a
			# column's bottom card is the descent to the bar,
			# exactly as in the library.
			if absf(dir.x) > 0.5:
				var tnidx: int = _tourn_side_step(pidx, 1 if dir.x > 0.0 else -1)
				if tnidx != pidx and tnidx < _panels.size():
					_set_focused(_panels[tnidx])
				return
			if absf(dir.y) > 0.5 and dir.y < 0.0:
				if coord.y > TOURN_BAND0:
					var up_idx: int = _raw_index(coord.x, coord.y - 1)
					if up_idx >= 0 and up_idx < _panels.size():
						_set_focused(_panels[up_idx])
				return
			if absf(dir.y) > 0.5 and dir.y > 0.0:
				if coord.y < TOURN_BAND0 + TOURN_BAND_COUNT - 1:
					var dn_idx: int = _raw_index(coord.x, coord.y + 1)
					if dn_idx >= 0 and dn_idx < _panels.size():
						_set_focused(_panels[dn_idx])
						return
				if not _descent_legacy():
					_descend_to_bar()
				return
		if absf(dir.x) > 0.5:
			var ncol: int = clampi(coord.x + (1 if dir.x > 0.0 else -1), 0, _columns - 1)
			var nidx: int = _index_at(ncol, coord.y)
			if nidx != pidx and nidx < _panels.size():
				_set_focused(_panels[nidx])
			return
		if absf(dir.y) > 0.5 and dir.y < 0.0 and coord.y > 0:
			_set_focused(_panels[_index_at(coord.x, coord.y - 1)])
			return
		if absf(dir.y) > 0.5 and dir.y > 0.0:
			var below: int = _index_at(coord.x, coord.y + 1) if coord.y < 2 else pidx
			if below != pidx:
				_set_focused(_panels[below])
				return
			if not _descent_legacy():
				# The bottom of the column: the descent
				# to the bar (GRADFIX3 item 3) - a graph
				# edge of its own (see _descend_to_bar),
				# not a fall through to the projection
				# walk below.
				_descend_to_bar()
				return
			# The trap NC (PVLDS_TOURN_NC=trap) restores
			# the shipped behaviour: the descent falls
			# through to the projection walk - the one
			# view-dependent edge in the focus graph,
			# and the one the field convicted ("cant't
			# exit tournie screen, cant get back down to
			# bar once up top").
	# The ascent to the rows (GRADFIX13 item 4): UP from a
	# rail stop is a graph edge of its own - the vertical
	# wall law's edge (see _ascend_to_rows) - never a fall
	# through to the projection walk below, whose scoring
	# lands one column off centre and drags the drum with
	# it. The strip's UP is a different edge (strip -> rail,
	# one rung only) and keeps the walk below, whose country
	# rules already bar it from reaching the grid.
	if absf(dir.y) > 0.5 and dir.y < 0.0 and _is_rail_quad(_focused) and _mode == "wall" \
			and debug_gf13_nc != "oldascent":
		_ascend_to_rows()
		return
	# The rail is its own navigation country (Chris's field
	# report, 2026-10-24): a sideways step along the control rail
	# used to be scored against every quad in the room, and the
	# nearest "sideways" quad was as often a bottom-row card as
	# the next placard - filter, up to a title, next filter, up
	# to a title. Sideways travel with the rail focused walks
	# the rail's own order; the card grid is entered from the
	# rail only by stepping UP, and DOWN from the grid's bottom
	# row returns to the rail. A sideways step anywhere else
	# never lands on the rail either.
	var horizontal: bool = absf(dir.x) > 0.5
	if horizontal and (_is_rail_quad(_focused) or _is_strip_quad(_focused)):
		var step: int = 1 if dir.x > 0.0 else -1
		var nq: ClickableQuad = _rail_focus_neighbour(step)
		if nq != null:
			_set_focused(nq)
		return
	var cam: Camera3D = _active_camera()
	if cam == null:
		return
	var from: Vector2 = cam.unproject_position(_focused.global_position)
	var focused_country: int = _focus_country(_focused)
	var best: ClickableQuad = null
	var best_score: float = INF
	for q: ClickableQuad in _focusables:
		if q == _focused or not q.pick_enabled:
			continue
		if horizontal and _focus_country(q) != focused_country:
			continue ## a sideways step never crosses between wall, rail and strip
		if not horizontal and focused_country == 0 and dir.y > 0.5 and _focus_country(q) == 2:
			continue ## the grid steps DOWN to the rail, never past it to the strip (the rail's entry law, one row further)
		if not horizontal and focused_country == 2 and dir.y < -0.5 and _focus_country(q) == 0:
			continue ## the strip steps UP to the rail, never past it to the grid
		var p: Vector2 = cam.unproject_position(q.global_position)
		var delta_v: Vector2 = p - from
		if delta_v.length() < 4.0:
			continue
		if delta_v.dot(dir) <= 2.0:
			continue
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var score: float = delta_v.length() + absf(delta_v.dot(perp)) * 2.0
		if score < best_score:
			best_score = score
			best = q
	if best != null:
		_set_focused(best)
