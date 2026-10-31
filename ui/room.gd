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
signal launch_requested(game: GameEntry, build: TableBuild) ## card Launch / detail Play - Main owns the launch + exit
signal exit_requested ## rail EXIT: Main disarms the watchdog and quits
signal art_prefetch_requested(games: Array) ## a page settled: Main's warmer should bring the neighbouring pages' art forward
signal tournament_refresh_requested ## the Tournament Room wants its boards (re)fetched: entering the view, or REFRESH pressed - Main owns the WoVP client
signal wovp_key_pasted(api_key: String) ## the SETUP panel's PASTE KEY read a key off the clipboard: Main saves it to the config
signal wovp_key_test_requested ## the SETUP panel's TEST KEY: Main validates the saved key and reports whose it is
signal display_settings_changed ## a SETUP display dial turned (the starfield): Main persists the room's standing values to the config

const PAGE_COLS: int = 4
const PAGE_ROWS: int = 3
const PAGE_SIZE: int = PAGE_COLS * PAGE_ROWS
static var WALL_RADIUS: float = 3.40 ## GRADFIX5 (item 4): the wall pushed back a step from the dome's 3.05 (the user's ask: "push back a bit, fit a few more cards into your central vision"). +0.35 m (+11%): the census's wall measure reads the centre card at 10.72 degrees across against 11.98 on the old radius (same arithmetic both sides), the air between columns grows from ~1.5 to ~2.8 degrees, and every drawn column's frame overflow shrinks - while the column CENTRES stay pitch-fixed at 13.5 degrees, so the step buys size and air, not new columns. The step is also item 1's headroom: the flush book floats 0.30 proud of a 3.40 wall - 3.10 from the eye, the old wall's own distance - so the full-height page spans inside its band pitch. Cards keep their physical size; everything seated on the wall (book, fins, tournament block, pop) derives from this one value and re-seats with it. A static, not a const, so the harness's oldwall NC can restore the shipped geometry wholesale.
static var WALL_LIFT: float = 0.06 ## GRADFIX5 (item 4): the wall's rise with its push-back - the seats ride a sphere around the eye, so the farther wall's bottom band hangs lower; the lift keeps its labels and nameplates on the heights the field-passed build held them at (the census's floor datum is the retired floor slab's old surface).
const EYE: Vector3 = Vector3(0.0, 1.25, 0.0)
const FILTERS: Array[String] = ["all", "vr", "favorites", "recents"]
const FILTER_LABELS: Dictionary = {"all": "ALL", "vr": "VR", "favorites": "FAVORITES", "recents": "RECENTS"}
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
static var MARQUEE_START_Z: float = -3.40 ## fly-in start depth (at the wall - tracks WALL_RADIUS; a static beside it so the oldwall NC restores both)
const MARQUEE_SETTLE_POS: Vector3 = Vector3(0.0, 1.42, -2.30) ## reading distance, on the view axis (retuned 2026-10-22: first pass sat too close)
const MARQUEE_PIXEL_SIZE: float = 0.005 ## Label3D world scale
const MARQUEE_YEAR_FONT_SIZE: int = 110 ## retuned 2026-10-22: 170 read too big in the headset
const MARQUEE_NAME_FONT_SIZE: int = 56 ## the designer/title line (Chris's "date and designer"); 84 -> 56 in the same retune
const MARQUEE_YEAR_Y: float = 0.30 ## year line's offset from the holder's centre
const MARQUEE_NAME_Y: float = -0.34 ## designer/title line's offset
const MARQUEE_PULSE_RATE: float = 1.6 ## settle pulse, cycles per second
const MARQUEE_PULSE_AMOUNT: float = 0.025 ## settle pulse, scale amplitude
const MARQUEE_YEAR_COLOR: Color = Color(1.0, 0.78, 0.25) ## marquee amber
const MARQUEE_NAME_COLOR: Color = Color(0.45, 0.85, 1.0) ## playfield blue
const MARQUEE_OUTLINE_COLOR: Color = Color(0.04, 0.02, 0.0)
const MARQUEE_OUTLINE_SIZE: int = 24

## Card pop-out (Chris, 2026-10-22): the card under the pointer -
## or holding gamepad/keyboard focus - lifts off the wall toward
## the viewer with depth from its neighbours. Only the one card
## is ever popped; focus loss settles it back flush.
const POP_OUT_DISTANCE: float = 0.15 ## metres off the shelf at full pop
const POP_OUT_SCALE: float = 1.04 ## card scale at full pop (DOME5's trim: 1.08 -> 1.04 so the popped frame's top clears the label above - see the dome constants below)
const POP_OUT_SEC: float = 0.15 ## pop in/out travel time, seconds

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
## by name. Nothing dropped: 12 rail stops, 28 strip
## slots (A-Z, THE, #) - bar_state counts them.
const STRIP_LETTER_SIZE: Vector2 = Vector2(0.078, 0.085)
const STRIP_THE_SIZE: Vector2 = Vector2(0.170, 0.085)
const STRIP_GAP: float = 0.010
const STRIP_LETTER_SIZE_WIDE: Vector2 = Vector2(0.095, 0.13) ## the pre-Console strip (the widebar NC's restore)
const STRIP_THE_SIZE_WIDE: Vector2 = Vector2(0.21, 0.13)
const STRIP_GAP_WIDE: float = 0.014
const RAIL_TILE_H: float = 0.115 ## the Console rail's tile height, pass 2 (GRADFIX5 0.135, pre-Console 0.15)
const RAIL_GAP: float = 0.018 ## the Console rail's inter-tile gap (pre-Console 0.035)

## ------------------------------------------------------------ the drum
## The dome's geometry, ported from the field-approved
## prototype (pvlds-dome-prototype, DOME1-DOME5) number for
## number: cards on a sphere of WALL_RADIUS around EYE, in
## three bands; consecutive games run along the TOP band,
## then the middle, then the bottom (column-major: a game's
## column is its index along its band). Only the columns
## within VISIBLE_HALF_COLUMNS of the focused column are
## drawn - the shelf is long (his ~356 games make ~119
## columns, ~1600 degrees of arc) and the ends wear bookend
## fins, gated into the same visibility window (DOME4's law:
## an ungated fin folds back into the forward view mid-shelf
## and paints its amber over card art).
const ROW_ELEVATIONS: Array[float] = [25.0, 5.0, -15.0] ## band elevations in degrees: top, middle, bottom
const ANGLE_STEP_DEG: float = 13.5 ## column pitch, degrees
const VISIBLE_HALF_COLUMNS: int = 10 ## drawn columns either side of the focused column
const CARD_SIZE: Vector2 = Vector2(0.62, 1.08) ## the card face, metres - the author screenshot's portrait shape
const CARD_FRAME_SIZE: Vector2 = Vector2(0.68, 1.10) ## the frame quad behind the face (DOME5's trimmed height)
const CARD_FACE_PX: Vector2i = Vector2i(496, 864) ## card faces render at the card's own aspect (0.574)
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
## Stage B - the background stack (all WORLD-LOCKED; see
## _build_background) and the focused card's flip.
const BG_STAR_RADIUS: float = 30.0 ## the starfield shell's radius around the eye
const BG_WIRE_RADIUS: float = 14.0 ## the lat/long wireframe shell's radius
## (The orbit ring's radius const went with the ring -
## GRADFIX4 item 5e removed it; see _build_background.)
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
## other and against the wireframe shell (14 m), and under
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

var _wall: Node3D  ## the drum: every card + fin rides it; only it rotates
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
var _panel_launches: Array[ClickableQuad] = [] ## per-panel Launch button, parallel to _panels
var _panel_back_launches: Array[ClickableQuad] = [] ## per-panel BACK Launch button (GRADFIX6 item 1: the flipped card's own Launch, on its back), parallel to _panels; null where a panel has no back
var _panel_base_pos: Array[Vector3] = [] ## wall-flush position per panel, parallel to _panels
var _panel_pop_dir: Array[Vector3] = [] ## unit vector from the panel toward the viewer (its wall normal)
var _panel_pop: Array[float] = [] ## current pop amount per panel, 0 flush .. 1 popped
var _panel_pop_applied: Array[float] = [] ## last pop amount written to a panel's transform (write guard)
var _panel_size: Vector2 = PANEL_SIZE ## the standing view's card size: CARD_SIZE, or the Tournament board size
var _panel_face_px: Vector2i = CARD_FACE_PX ## the panel faces' render size (CARD_FACE_PX, or the board's)
var _panel_art_aspect: Array[float] = [] ## per panel: its art's aspect (w/h) once its face lands, 0 = no art (title card)
var _panel_frames: Array[MeshInstance3D] = [] ## per panel: the card's frame quad (prototype geometry; amber while the card is the centre)
var _panel_plates: Array[MeshInstance3D] = [] ## per panel: the nameplate's dark plate behind the title label
var _panel_labels: Array[Label3D] = [] ## per panel: the title label on its nameplate
var _mat_frame_dark: StandardMaterial3D = null ## the cards' shared dark frame material
var _mat_frame_amber: StandardMaterial3D = null ## the centred card's amber frame material (and the fins' edge)
var _mat_plate: StandardMaterial3D = null ## the shared nameplate/status plate material (the marquee fade drives its alpha)
var _window_fill_busy: bool = false ## a window face-fill pass is running (centre changes coalesce through _window_fill_dirty)
var _window_fill_dirty: bool = false
var _power_subject_inflight: Dictionary = {} ## game_id -> true while its power-on subject renders
var _power_prefetch_asked: Dictionary = {} ## game_id -> true once the warmer has been asked for its cold backglass (GRADFIX6)
var _face_heal_retries: Dictionary = {} ## GRADFIX6 item 2: "game_id|art_file" -> art-render retries already spent by the panel heal
var _face_heal_msec: int = 0 ## GRADFIX6 item 2: the panel heal's throttle stamp (one sweep per BOARD_TEX_RETRY_MS)
var _fin_start: Node3D = null ## the shelf's start bookend fin (child of the drum; DOME3/DOME4)
var _fin_end: Node3D = null ## the shelf's end bookend fin
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
var _bg_root: Node3D = null ## the background stack's holder (a Room child - world-locked; the drum is its only moving neighbour)
var _bg_starfield: MeshInstance3D = null
var _bg_starfield_near: MeshInstance3D = null ## the near star shell (the GRAD FIX round's depth layer)
var _starfield_mode: String = "layered" ## the SETUP dial: "layered" | "flat" | "off" (see set_starfield_mode)
var _bg_wireframe: MeshInstance3D = null
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
var _setup_panel_back_btn: ClickableQuad = null
var _setup_panel_up: bool = false
var _setup_panel_gen: int = 0
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
var _strip_quads: Dictionary = {} ## letter key ("A".."Z", "THE", "#") -> ClickableQuad: the alphabet strip, built once with the rail
var _strip_tex_cache: Dictionary = {} ## "key|state" -> Texture2D: every strip slot face ever rendered (the rail cache's pattern)
var _btn_tex_cache: Dictionary = {} ## "label|accent" -> Texture2D: the panels' Launch/Failed button faces - two textures in existence, once rendered per panel per rebuild before the pick-latency fix
var _face_tex_cache: Dictionary = {} ## "game_id|art_path|fav" -> [Texture2D, art_aspect]: rendered panel faces (the pick-latency fix - a revisit re-rendered every face from scratch)
var _face_cache_order: Array[String] = [] ## the face cache's LRU order (oldest first)
const FACE_CACHE_MAX: int = 96 ## the drawn window is 63 faces; the cache holds it plus a swing's worth of margin
var _strip_has_number: bool = false ## the library holds a non-letter title, so the "#" slot is laid out (see _refresh_strip)
var _letter_net: String = "" ## "" | "THE" | "#": the standing net view - the wall shows exactly that net's games, in title order (see _jump_to_letter)
var _tournament: bool = false ## the Tournament Room view stands: the wall shows WoVP challenge boards, not the library (see _build_tournament_rows)
var _tournament_rows: Array = [] ## the standing view's rows, aligned 1:1 with _visible_games: {"kind": "challenge"|"state", "challenge", "game", "owned", "lines"}
var _wovp_has_key: bool = false ## Main's word on the config: a WoVP key is saved
var _wovp_user_id: String = "" ## whose key it is (validate-apikey's answer, or the cache's) - how the wall knows which row is HIS
var _wovp_challenges: Array = [] ## the last-good boards (Array of WovpChallenge), live or from the disk cache
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
var _drum_yaw: float = 0.0 ## the drum's current yaw, radians (== _swing_to at rest)
var _panel_pool: Dictionary = {} ## game_id -> {root, launch, frame, plate, label, mode, plate_done}: card nodes built once per library adoption and re-seated per view (a rebuild that freed and rebuilt 300+ cards would tax every letter pick - the pick-latency law)
var _plates_pending: bool = false ## a rebuild stood new cards: their nameplates re-derive from the labels' live AABBs until every one settles (see _refresh_card_plate)
var _panel_face_key: Dictionary = {} ## game_id -> the face key its standing texture was filled for ("" = never filled)
var _panel_window_lo: int = -1 ## the drawn window's first COLUMN (visibility + face fill range), -1 = none yet
var _panel_window_hi: int = -1 ## the drawn window's last COLUMN
var _power_subject_cache: Dictionary = {} ## game_id -> [backglass path, Texture2D]: rendered power-on subjects (the backglass face, rendered once per game per library)
var _focusables: Array[ClickableQuad] = []
var _focused: ClickableQuad = null
var _joy_cooldown: float = 0.0
var _joy_prev_a: bool = false
var _joy_prev_b: bool = false
var _joy_prev_y: bool = false ## Y edge tracking: open the focused card's info (see _process)
var _joy_prev_x: bool = false ## X edge tracking: favorite the focused card (see _process)
var _joy_prev_lb: bool = false ## bumper edge tracking: the section slide's page travel (see _process)
var _joy_prev_rb: bool = false
var _joy_prev_right: bool = false ## D-pad Right edge tracking: the room's BACK-out press (see _process)
var _joy_right_armed: bool = false ## baseline-release arming: set once THIS room instance has observed D-pad Right released; until then no right-press edge can exit (see _process)


func setup(factory: TextureFactory, scanner: LibraryScanner, store: StateStore, xr_enabled: bool) -> void:
	_factory = factory
	_scanner = scanner
	_store = store
	_xr_enabled = xr_enabled
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
	# Cached faces belong to the old library's truth (titles,
	# build counts, art can all change under a game_id across
	# a rescan): they die with the library that minted them.
	_face_tex_cache.clear()
	_face_cache_order.clear()
	_power_subject_cache.clear()
	_free_panel_pool()
	_recompute_visible()
	_page = 0
	_centre_index = 0
	_rebuild_wall()


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
	_scanner = scanner
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
## banked by the user 2026-10-29): a far starfield shell, a
## faint latitude/longitude wireframe shell, and ONE tilted
## orbit ring - plus the haze the far window columns wear
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
## alone, static, "off" no stars. The wireframe shell and
## the orbit ring are structure, not stars - the dial never
## touches them. Every layer stays parented to the room
## (world space, centred on the eye): the drift is a
## rotation about the viewer, never a slide with the view.
func set_starfield_mode(mode: String) -> void:
	_starfield_mode = mode if ["layered", "flat", "off"].has(mode) else "layered"
	_apply_starfield_mode()


func starfield_mode() -> String:
	return _starfield_mode


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
	# The wireframe shell: latitude/longitude lines drawn
	# as line geometry on a nearer sphere - the dome's own
	# ghost, faint enough to read as depth, not structure.
	var wire: MeshInstance3D = MeshInstance3D.new()
	wire.name = "WireframeShell"
	wire.mesh = _wireframe_mesh()
	var wm: StandardMaterial3D = StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.albedo_color = Color(0.38, 0.48, 0.72, 0.13)
	wire.material_override = wm
	wire.position = EYE
	_bg_root.add_child(wire)
	_bg_wireframe = wire
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


## The wireframe shell's line geometry: meridians every 15
## degrees, parallels every 15 from -75 to +75, on
## BG_WIRE_RADIUS around the eye.
func _wireframe_mesh() -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	for mi: int in range(24):
		var lon: float = deg_to_rad(float(mi) * 15.0)
		var prev: Vector3 = Vector3.ZERO
		for si: int in range(65):
			var lat: float = deg_to_rad(-90.0 + float(si) * (180.0 / 64.0))
			var p: Vector3 = Vector3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon)) * BG_WIRE_RADIUS
			if si > 0:
				verts.append(prev)
				verts.append(p)
			prev = p
	for li: int in range(11):
		var lat2: float = deg_to_rad(-75.0 + float(li) * 15.0)
		var prev2: Vector3 = Vector3.ZERO
		for si2: int in range(65):
			var lon2: float = deg_to_rad(float(si2) * (360.0 / 64.0))
			var p2: Vector3 = Vector3(cos(lat2) * sin(lon2), sin(lat2), -cos(lat2) * cos(lon2)) * BG_WIRE_RADIUS
			if si2 > 0:
				verts.append(prev2)
				verts.append(p2)
			prev2 = p2
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


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
func set_wovp_data(d: Dictionary) -> void:
	_wovp_has_key = bool(d.get("has_key", false))
	_wovp_user_id = str(d.get("user_id", ""))
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


func tournament_active() -> bool:
	return _tournament


## The standing view's rows (the smoke's read of the wall's
## own truth): aligned with _visible_games while the
## Tournament Room stands, empty otherwise.
func tournament_rows() -> Array:
	return _tournament_rows.duplicate()


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
## against the scanner's match data (the version id rides
## along in the challenge; the join is game-level in this
## round - the build the wall launches is his default).
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
		rows.append({"kind": "challenge", "challenge": ch, "game": game, "owned": owned, "lines": []})
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


func _grid_coord(index: int) -> Vector2i:
	if debug_grid_nc == "rowmajor":
		return Vector2i(index % _columns, index / _columns)
	if _tournament:
		return Vector2i(TOURN_BLOCK_COL0 + index / TOURN_BAND_COUNT,
			TOURN_BAND0 + index % TOURN_BAND_COUNT)
	return Vector2i(index / BAND_COUNT, index % BAND_COUNT)


## The unclamped shelf index at a grid place, under the
## standing mapping - the raw material _index_at clamps.
func _raw_index(col: int, row: int) -> int:
	if debug_grid_nc == "rowmajor":
		return row * _columns + col
	if _tournament:
		return (col - TOURN_BLOCK_COL0) * TOURN_BAND_COUNT + (row - TOURN_BAND0)
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
## in front, the Launch button - and the card's BACK (a
## holder turned PI on the pivot: its own frame, its info
## face, its own Launch button), which the flip shows
## instead of the front past the turn's midpoint (GRADFIX6
## item 1). Board mode mints the bare board panel at the
## board's own size (its face carries its own text; no
## plate, no label, no frame, no back - the state row has
## nothing to flip to).
func _make_card_nodes(game: GameEntry, mode: String) -> Dictionary:
	var size: Vector2 = RoomSpecs.board_panel_size() if mode == "board" else CARD_SIZE
	var q: ClickableQuad = ClickableQuad.new()
	q.setup("panel", game.game_id, _placeholder_tex, size)
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
		# at the turn's edge-on instant), Launch at +0.020 on
		# the board face's reserved plinth (RoomSpecs.
		# board_launch_y - the back IS a board-sized face).
		# Hidden and unpickable until the flip's midpoint swap
		# (see _apply_flip_side).
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
		bface.material_override = bmat
		bface.position = Vector3(0.0, 0.0, 0.001)
		back.add_child(bface)
		nodes["back"] = back
		nodes["back_mat"] = bmat
		var blq: ClickableQuad = ClickableQuad.new()
		blq.setup("panel_launch", game.game_id, _placeholder_tex, PANEL_LAUNCH_SIZE)
		blq.position = Vector3(0.0, RoomSpecs.board_launch_y(), 0.020)
		blq.pick_enabled = false
		back.add_child(blq)
		nodes["back_launch"] = blq
		nodes["back_key"] = "" ## the content key this card's back texture was rendered for ("" = never)
		nodes["back_tex_real"] = false ## the back's standing texture is a real capture, not the fallback solid
	var lq: ClickableQuad = ClickableQuad.new()
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
	# default 0, and the Launch pair on top. The NC seam
	# PVLDS_GRAD_NC=nofaceorder restores the undeclared stack.
	if OS.get_environment("PVLDS_GRAD_NC") != "nofaceorder":
		q.set_stack_order(-4, -3)
		lq.set_stack_order(0, 1)
	return nodes


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
func _apply_card_plate(nodes: Dictionary, aabb: AABB) -> void:
	var plate: MeshInstance3D = nodes["plate"] as MeshInstance3D
	var block_h: float = maxf(LABEL_STRIP_SIZE.y, aabb.size.y + 0.034)
	var block_cy: float = LABEL_STRIP_Y + aabb.position.y + aabb.size.y * 0.5
	var pq: QuadMesh = plate.mesh as QuadMesh
	if pq != null:
		pq.size = Vector2(LABEL_STRIP_SIZE.x, block_h)
	plate.position = Vector3(0.0, block_cy, 0.005)
	var lq: ClickableQuad = nodes["launch"] as ClickableQuad
	var plate_bottom: float = block_cy - block_h * 0.5
	lq.position = Vector3(0.0, PANEL_LAUNCH_Y_TOP if plate_bottom < -0.40 else PANEL_LAUNCH_Y, 0.020)


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


## The shelf's bookend fins (DOME3): a dark slab with an amber
## edge, three amber bars at the band heights, and a mark -
## diamond for the opening end, square for the closing one.
## They stand one column past each end of the shelf and obey
## the card visibility window (DOME4's gating law, in
## _refresh_window): an ungated fin folds back into the
## forward view mid-shelf and paints over card art.
func _make_bookend(display_col: int, is_start: bool) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "BookendStart" if is_start else "BookendEnd"
	root.transform = _card_transform_at(display_col, 1)
	_make_card_quad(root, Vector2(0.42, 3.10), Vector3(0.0, 0.0, -0.006), _frame_mat(true))
	_make_card_quad(root, Vector2(0.36, 3.04), Vector3.ZERO, _frame_mat(false))
	for bar_y: float in [-1.11, 0.0, 1.11]:
		_make_card_quad(root, Vector2(0.36, 0.06), Vector3(0.0, bar_y, 0.006), _frame_mat(true))
	var mark: MeshInstance3D = _make_card_quad(root, Vector2(0.20, 0.20), Vector3(0.0, 0.0, 0.012), _frame_mat(true))
	if is_start:
		mark.rotation.z = PI * 0.25
	return root


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
	_centre_index = clamped
	_page = _centre_index / PAGE_SIZE
	if snap or _wall == null:
		_drum_yaw = target
		_swing_vel = 0.0
		_swing_active = false
		_swing_journey = false
		if _wall != null:
			_wall.rotation.y = target
	elif target != _swing_to or not _swing_active:
		if absf(target - _drum_yaw) < 0.0001 and absf(_swing_vel) < 0.001:
			_drum_yaw = target
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
			# held scroll builds to a cruise rather than
			# settling between steps.
			if _swing_active and absf(_swing_vel) > 0.05 \
					and signf(target - _drum_yaw) == signf(_swing_vel):
				_swing_journey = true
			_swing_to = target
			var cols: float = absf(target - _drum_yaw) / deg_to_rad(ANGLE_STEP_DEG)
			_swing_cols = cols
			_swing_duration = clampf(0.14 + 0.055 * sqrt(maxf(cols, 1.0)), SWING_MIN_SEC, SWING_MAX_SEC)
			_swing_active = true
	if changed:
		_refresh_window()
		_refresh_card_frames()
		_request_window_fill()
		# No companion follows the centre any more (the flip
		# replaced the wing/board): a centre change is one of
		# the flip's closing conditions, and _update_flip
		# reads it per frame - no hook needed here.


## Per-frame swing drive, from _process: a critically damped
## spring (the classic smooth-damp form) carries the drum to
## its target, velocity included. The prototype's per-step
## cubic ease-out restarted its curve at every retarget, so a
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
## snaps onto it, at rest, like it always did.
func _update_swing(delta: float) -> void:
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
	_wall.rotation.y = _drum_yaw


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
			f.material_override = _frame_mat(idx == _centre_index)


## The drawn window: cards within VISIBLE_HALF_COLUMNS of the
## centred column are visible (and, in plain browsing, pickable);
## the rest are dark and inert. The fins obey the same window
## (DOME4): the start fin shows while the centred column is
## within 9 of it, the end fin mirrored.
func _refresh_window() -> void:
	var n: int = _visible_games.size()
	if n == 0 or _panels.is_empty():
		_panel_window_lo = -1
		_panel_window_hi = -1
		return
	var fc: int = _grid_coord(_centre_index).x
	_panel_window_lo = maxi(0, fc - VISIBLE_HALF_COLUMNS)
	_panel_window_hi = mini(_columns - 1, fc + VISIBLE_HALF_COLUMNS)
	var browsing: bool = _mode == "wall" and not _placard_up and not _setup_panel_up and _launching_game_id == ""
	for idx: int in range(_panels.size()):
		var c: int = _grid_coord(idx).x
		var vis: bool = c >= _panel_window_lo and c <= _panel_window_hi
		_panels[idx].visible = vis
		if browsing:
			_panels[idx].pick_enabled = vis
			if idx < _panel_launches.size():
				_panel_launches[idx].pick_enabled = vis and not (_tournament and not _tournament_launchable(idx))
	if _fin_start != null:
		_fin_start.visible = fc <= VISIBLE_HALF_COLUMNS - 1
	if _fin_end != null:
		_fin_end.visible = fc >= _columns - VISIBLE_HALF_COLUMNS
	# The haze follows the centre (see _haze_for): re-apply
	# the standing wall fade with the new centre's factors.
	var keep_alpha: float = _wall_alpha_applied
	_wall_alpha_applied = -1.0
	_apply_wall_alpha(keep_alpha)


## Whether a Tournament panel may launch: only a challenge row
## he owns (a state row and a not-owned board carry no launch
## at all - the fill also hides their buttons; this is the
## pick-side of the same law).
func _tournament_launchable(idx: int) -> bool:
	if idx < 0 or idx >= _tournament_rows.size():
		return false
	var row: Dictionary = _tournament_rows[idx] as Dictionary
	return str(row.get("kind", "")) == "challenge" and bool(row.get("owned", false))


func _rebuild_wall() -> void:
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
	_gen += 1
	var gen: int = _gen
	wall_ready = false
	_swing_active = false
	_swing_vel = 0.0
	_swing_journey = false
	# Standing cards return to the pool (they are NOT freed:
	# a rebuild re-seats the same nodes at the new view's
	# places, faces and all - freeing and re-minting 300+
	# cards per letter pick is the pick-latency tax the pool
	# exists to refuse). The fins are the view's own and die
	# with it; the banner is Room furniture now (built once,
	# below) and never rides the drum.
	for q: ClickableQuad in _panels:
		if q != null and is_instance_valid(q) and q.get_parent() == _wall:
			_wall.remove_child(q)
	if _fin_start != null:
		_fin_start.queue_free()
		_fin_start = null
	if _fin_end != null:
		_fin_end.queue_free()
		_fin_end = null
	_panels.clear()
	_panel_launches.clear()
	_panel_back_launches.clear()
	_panel_base_pos.clear()
	_panel_pop_dir.clear()
	_panel_pop.clear()
	_panel_pop_applied.clear()
	_panel_art_aspect.clear()
	_panel_frames.clear()
	_panel_plates.clear()
	_panel_labels.clear()
	_panel_window_lo = -1
	_panel_window_hi = -1
	_wall_alpha_applied = 1.0 ## fresh quads start opaque; the marquee fade re-applies from there
	_set_focused(null)

	_placeholder_tex = TextureFactory.make_solid(Color(0.07, 0.07, 0.11))
	_panel_size = CARD_SIZE
	_panel_face_px = CARD_FACE_PX
	if _tournament:
		# The block's own extent: pad columns + the two-band
		# block (GRADFIX4 item 3 - see TOURN_BLOCK_COL0).
		_columns = TOURN_BLOCK_COL0 + maxi(1, int(ceil(float(maxi(1, _visible_games.size())) / float(TOURN_BAND_COUNT))))
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
		_panel_pop_applied.append(0.0)
		_panel_art_aspect.append(0.0)
		_panel_frames.append(nodes.get("frame") as MeshInstance3D)
		_panel_plates.append(nodes.get("plate") as MeshInstance3D)
		_panel_labels.append(nodes.get("label") as Label3D)
		_seat_card(idx, nodes)
	# The bookends, one column past each end of the shelf.
	# The Tournament view stands WITHOUT them (GRADFIX3,
	# the user's order: "nuke the orange pillars framing
	# tournie tables") - its shelf is a handful of
	# challenges, and the fins framed it like a stadium it
	# is not. The library keeps its fins (DOME3
	# field-passed; the DOME4 window gating below is
	# untouched and null-safe).
	if not _visible_games.is_empty() and not _tournament:
		_fin_start = _make_bookend(-1, true)
		_wall.add_child(_fin_start)
		_fin_end = _make_bookend(_columns, false)
		_wall.add_child(_fin_end)
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
	# REFRESH is the one stop whose pick state is not a
	# constant: it lives only while the Tournament Room
	# stands (the blanket reset above would otherwise arm
	# it over the library wall).
	var refresh_q: ClickableQuad = _rail_quads.get("wovp_refresh") as ClickableQuad
	if refresh_q != null:
		refresh_q.pick_enabled = _tournament
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
	# row wholesale.
	var defs: Array = []
	if _console_wide():
		defs = [
			["filter:all", 0.30], ["filter:vr", 0.24], ["filter:favorites", 0.44], ["filter:recents", 0.40],
			["sort", 0.46], ["tournament", 0.44], ["page_prev", 0.18], ["page_label", 0.28], ["page_next", 0.18],
			["wovp_refresh", 0.32], ["desk", 0.32], ["exit", 0.28],
		]
	else:
		defs = [
			["filter:all", 0.194], ["filter:vr", 0.156], ["filter:favorites", 0.285], ["filter:recents", 0.259],
			["sort", 0.298], ["tournament", 0.285], ["page_prev", 0.117], ["page_label", 0.182], ["page_next", 0.117],
			["wovp_refresh", 0.207], ["desk", 0.207], ["exit", 0.182],
		]
	var gap: float = 0.035 if _console_wide() else RAIL_GAP
	var tile_h: float = 0.15 if _console_wide() else RAIL_TILE_H
	var total: float = 0.0
	for d: Variant in defs:
		total += float(d[1]) + gap
	total -= gap
	var x: float = -total * 0.5
	for d: Variant in defs:
		var key: String = str(d[0])
		var w: float = float(d[1])
		var q: ClickableQuad = _make_quad(_rail, "rail", key, placeholder, Vector2(w, tile_h), Vector3(x + w * 0.5, y, z))
		if key == "page_label" or key == "wovp_refresh":
			# page_label is a readout, never a stop. REFRESH is
			# a stop only while the Tournament Room stands (see
			# _rebuild_wall) - refreshing boards you are not
			# looking at is not a rail job.
			q.pick_enabled = false
		_rail_quads[key] = q
		x += w + gap


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
	_status_text = _banner_line()
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
	elif key == "page_prev":
		label = "<"
	elif key == "page_next":
		label = ">"
	elif key == "page_label":
		label = "%d / %d" % [_page + 1, page_count()]
	elif key == "desk":
		label = "SETUP"
	elif key == "exit":
		label = "EXIT"
	return [label, accent]


func _rail_cache_key(label: String, accent: bool) -> String:
	return label + ("|a" if accent else "|p")


## Dress every rail quad from the texture cache, in this call -
## no awaits. A cache hit is the button's real rendered face,
## so the rail is fully dressed in the rebuild's own frame. A
## miss keeps whatever face the quad already wears (the
## standing rail never falls back to the placeholder again)
## until the async fill renders that label - once, ever.
func _apply_rail_textures() -> void:
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
	if _scanner != null:
		lib_presence = LetterIndex.presence_over(_scanner.games)
		presence = LetterIndex.presence_over(_collect_filtered())
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
	_apply_strip_textures(presence)


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
			quad.set_texture(_strip_tex_cache[ck] as Texture2D)


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
## [Texture2D, art_aspect] and renews the entry's place.
func _face_cache_get(key: String) -> Array:
	if not _face_tex_cache.has(key):
		return []
	_face_cache_order.erase(key)
	_face_cache_order.push_back(key)
	return _face_tex_cache[key] as Array


## The panel face cache's LRU write: past FACE_CACHE_MAX
## the oldest faces are dropped (their games simply
## re-render on a later visit - a miss is a cost, never a
## wrong face, because the key carries the game's art path,
## favorite flag and PuP flag (GRADFIX6 item 5: a face
## rendered before the db match lands must not serve forever
## without its PuP badge), and a fresh library clears the
## cache).
func _face_cache_put(key: String, tex: Texture2D, aspect: float) -> void:
	_face_tex_cache[key] = [tex, aspect]
	_face_cache_order.erase(key)
	_face_cache_order.push_back(key)
	while _face_cache_order.size() > FACE_CACHE_MAX:
		var old: String = _face_cache_order.pop_front()
		_face_tex_cache.erase(old)


## Drop one cached face (the panel heal's art retry: the
## styled card cached under an art key must not re-serve
## itself when the heal asks for the art render again).
func _face_cache_evict(key: String) -> void:
	_face_tex_cache.erase(key)
	_face_cache_order.erase(key)


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
	var strip_presence: Dictionary = LetterIndex.presence_over(_collect_filtered()) if _scanner != null else {}
	for skey: String in _strip_slot_keys():
		var squad: ClickableQuad = _strip_quads.get(skey) as ClickableQuad
		if squad == null:
			continue
		var ls: Array = _strip_label_state(skey, strip_presence)
		var sck: String = str(ls[0]) + "|" + str(ls[1])
		if _strip_tex_cache.has(sck):
			squad.set_texture(_strip_tex_cache[sck] as Texture2D)
			continue
		var spx: Vector2i = Vector2i(500, 250) if skey == "THE" else Vector2i(229, 250) ## the Console pads' own aspect (pass 2: 0.170/0.085 and 0.078/0.085), so the glyphs are not stretched (GRADFIX5's rule, GRADFIX6's numbers)
		bench_renders += 1
		var stex: Texture2D = await _factory.render_texture(RoomSpecs.letter_spec(str(ls[0]), str(ls[1])), spx)
		if gen != _gen:
			return
		_strip_tex_cache[sck] = stex
		squad.set_texture(stex)
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
func _request_window_fill() -> void:
	if _window_fill_busy:
		_window_fill_dirty = true
		return
	_run_window_fill()


func _run_window_fill() -> void:
	_window_fill_busy = true
	_window_fill_dirty = false
	var gen: int = _gen
	await _fill_window_faces(gen)
	_window_fill_busy = false
	if _window_fill_dirty and gen == _gen:
		_run_window_fill()


func _fill_window_faces(gen: int) -> void:
	if _panel_window_lo < 0:
		return
	var order: Array[int] = []
	var centre_col: int = _grid_coord(_centre_index).x
	for dist: int in range(0, centre_col + VISIBLE_HALF_COLUMNS + 1):
		for c: int in [centre_col - dist, centre_col + dist]:
			if dist == 0 and c != centre_col:
				continue
			if c < _panel_window_lo or c > _panel_window_hi:
				continue
			for row: int in range(3):
				var idx: int = _raw_index(c, row)
				if idx >= 0 and idx < _panels.size():
					order.append(idx)
	for idx: int in order:
		if gen != _gen:
			return
		# A fast sweep moves the window mid-pass (centre
		# changes do not bump the generation): never spend a
		# render on a card the window has already left.
		var cc: int = _grid_coord(idx).x
		if cc < _panel_window_lo or cc > _panel_window_hi:
			continue
		await _fill_one_face(idx, gen)
	if gen == _gen:
		wall_ready = true
		# The window is dressed: ask Main's warmer to bring
		# the columns just outside it forward, so a swing
		# lands on warm art even mid-warm-up. GRADFIX6 widens
		# the ask from one column to two - the fill path no
		# longer extracts inline, so the warmer's lookahead
		# is the only thing standing between a fast sweep and
		# a wall of title cards.
		var near: Array = []
		for c: int in [_panel_window_lo - 2, _panel_window_lo - 1, _panel_window_hi + 1, _panel_window_hi + 2]:
			if c < 0 or c >= _columns:
				continue
			for row: int in range(3):
				var idx: int = _raw_index(c, row)
				if idx >= 0 and idx < _visible_games.size():
					near.append(_visible_games[idx])
		if not near.is_empty():
			art_prefetch_requested.emit(near)


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


## One card's face: the author shot first (GameEntry's
## ranking), then the shipped fallback chain - rendered
## WITHOUT the art's baked name strip: the nameplate's plate
## + label is the card's name now (the DOME5 geometry put the
## title there), and a second name painted into the art would
## fight it. The favorite star stays inside the rendered
## face, exactly as the shipped art_spec draws it.
func _fill_one_face(idx: int, gen: int) -> void:
	if idx < 0 or idx >= _panels.size() or idx >= _visible_games.size():
		return
	if _tournament and idx < _tournament_rows.size() \
			and str((_tournament_rows[idx] as Dictionary).get("kind", "")) == "state":
		return # the state panel wears its board face (see _fill_tournament_state_faces), never a card face
	var game: GameEntry = _visible_games[idx]
	var quad: ClickableQuad = _panels[idx]
	var art_file: String = _face_path_for(game)
	var fav: bool = _store != null and _store.is_favorite(game.game_id)
	var pup: bool = game.is_pup_tagged()
	var fkey: String = game.game_id + "|" + art_file + "|" + ("fav" if fav else "") + "|" + ("pup" if pup else "")
	if str(_panel_face_key.get(game.game_id, "")) == fkey:
		return  # already wearing exactly this face
	var tex: Texture2D = null
	var art_aspect: float = 0.0
	var from_art: bool = false
	var cached_face: Array = _face_cache_get(fkey)
	if not cached_face.is_empty():
		tex = cached_face[0] as Texture2D
		art_aspect = float(cached_face[1])
		from_art = art_aspect > 0.0
	else:
		if art_file != "":
			var art_tex: Texture2D = TextureFactory.load_art_texture(art_file)
			if art_tex != null:
				art_aspect = float(art_tex.get_width()) / float(art_tex.get_height())
				tex = await _factory.render_texture(RoomSpecs.art_spec(game, art_tex, _store, false), _panel_face_px)
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
			tex = await _factory.render_texture(RoomSpecs.panel_spec(game, _store), _panel_face_px)
			from_art = false
		if gen != _gen:
			return
		if tex != null and (_tex_is_real(tex) or _blackface_nc(game)):
			_face_cache_put(fkey, tex, art_aspect if from_art else 0.0)
		elif tex != null:
			# The styled card's own capture failed too: stamp
			# nothing, cache nothing - the placeholder stands
			# and the heal retries (bounded per face key).
			tex = null
	if tex == null:
		return
	quad.set_texture(tex)
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
	if _panel_pop[idx] > 0.0:
		# The card is already popped (focus rested while its
		# face streamed in): force the pop transform to
		# re-apply next frame.
		_panel_pop_applied[idx] = -1.0
	if idx < _panel_launches.size():
		var failed: bool = game.game_id == _failed_game_id
		# The Launch/Failed button has exactly two faces in
		# existence; they are cached like the rail's.
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
			# A challenge card he does not own carries no
			# Launch: there is nothing on it to press (the
			# pick-side of the same law lives in
			# _refresh_window via _tournament_launchable).
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
func _heal_panel_faces() -> void:
	if _panel_window_lo < 0 or _panels.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	if now - _face_heal_msec < BOARD_TEX_RETRY_MS:
		return
	_face_heal_msec = now
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
			_fill_one_face(idx, _gen) # an upgrade is ready (or the face never landed) - the fill's own key check does the rest; never budget-charged
		elif tex == null or tex == _placeholder_tex or not _tex_is_real(tex):
			# Stamped as this face, yet not honestly standing
			# (a rebuild re-dressed the pooled panel, a race):
			# restamp and refill, bounded per face key.
			var rkey: String = game.game_id + "|" + want_key
			var spent: int = int(_face_heal_retries.get(rkey, 0))
			if spent < BOARD_TEX_MAX_RETRIES:
				_face_heal_retries[rkey] = spent + 1
				_panel_face_key.erase(game.game_id)
				_fill_one_face(idx, _gen)
		elif art_file != "" and _panel_art_aspect[idx] <= 0.0:
			# The styled card stands over ready art: its art
			# render captured empty at fill time. Retry it,
			# bounded; then the styled card stands for good.
			var rkey: String = game.game_id + "|" + art_file
			var spent: int = int(_face_heal_retries.get(rkey, 0))
			if spent < BOARD_TEX_MAX_RETRIES:
				_face_heal_retries[rkey] = spent + 1
				_face_cache_evict(stamped)
				_panel_face_key.erase(game.game_id)
				_fill_one_face(idx, _gen)


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
			"tex_w": tex.get_width() if tex != null else 0,
			"is_placeholder": tex != null and tex == _placeholder_tex,
			"is_unreal": tex == null or tex == _placeholder_tex or not _tex_is_real(tex),
			"from_art": _panel_art_aspect[idx] > 0.0 if idx < _panel_art_aspect.size() else false,
		})
	return out


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
		quad.set_texture(tex)
		_panel_art_aspect[i] = 0.0
		if i < _panel_launches.size():
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
	var ly: float = RoomSpecs.board_launch_y()
	out["launch_rect"] = Rect2(
		Vector2(-PANEL_LAUNCH_SIZE.x * 0.5, ly - PANEL_LAUNCH_SIZE.y * 0.5), PANEL_LAUNCH_SIZE)
	return out


## One face-space rect (pixels, origin top-left, +y down)
## in panel space (metres, origin centre, +y up, min-corner
## position) - the two spaces the layout legs compare in.
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
		if _setup_panel_back_btn != null:
			_focusables.append(_setup_panel_back_btn)
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


func _refresh_quad_states() -> void:
	var hovered: ClickableQuad = _rig.hovered if _rig != null else null
	var all: Array[ClickableQuad] = []
	all.append_array(_panels)
	all.append_array(_panel_launches)
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
	if _setup_panel_back_btn != null:
		all.append(_setup_panel_back_btn)
	for q: ClickableQuad in all:
		q.set_visual_state(q == hovered, q == _focused)


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
	if _mode != "wall" or _placard_up or _setup_panel_up or _launching_game_id != "":
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
	if _mode != "wall" or _placard_up or _setup_panel_up or _launching_game_id != "":
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
	var p: ClickableQuad = _panel_for(hovered)
	if p == null:
		p = _panel_for(_focused)
	if p != null:
		var idx: int = _panels.find(p)
		if idx >= 0 and idx != _centre_index:
			_set_centre(idx)


## Per-frame pop animation, driven from _process: each panel's
## amount walks toward 1 (the centred card) or 0 at POP_OUT_SEC
## pace, and the transform is written only while the amount is
## actually moving - a resting panel is never touched, so a
## Launch button's activation pulse (a scale tween) never fights
## this. The pop is UNIFORM (DOME5): scale POP_OUT_SCALE and a
## POP_OUT_DISTANCE pull along the card's own normal - the
## true-aspect grow the flat wall used is retired (the dome's
## clearance proof was measured on the uniform pop). The Launch
## button rides its panel (it is a child), so it stays glued to
## the card face and clickable while popped.
func _update_pop(delta: float) -> void:
	_follow_centre()
	if _panels.is_empty():
		return
	var target: ClickableQuad = _pop_target_panel()
	var step: float = delta / POP_OUT_SEC
	for i: int in range(_panels.size()):
		var want: float = 1.0 if _panels[i] == target else 0.0
		var amt: float = move_toward(_panel_pop[i], want, step)
		_panel_pop[i] = amt
		if absf(amt - _panel_pop_applied[i]) < 0.001:
			continue
		_panel_pop_applied[i] = amt
		var q: ClickableQuad = _panels[i]
		q.position = _panel_base_pos[i] + _panel_pop_dir[i] * (POP_OUT_DISTANCE * amt)
		var s: float = lerpf(1.0, POP_OUT_SCALE, amt)
		q.scale = Vector3(s, s, s)
	_update_flip(delta)
	_heal_panel_faces()


## ------------------------------------------------------ the card flip
##
## The flip (GRADFIX6 item 1 - Chris's design, the original
## concept restored): Y turns the focused card over IN ITS
## SEAT. The front is the art face as always; the back is
## the info the wing and the book used to carry beside the
## card - in the library, RoomSpecs.wing_spec (the table's
## data, and the live board too when the table stands in a
## challenge); in the Tournament Room, the challenge's full
## TR3 scoreboard (RoomSpecs.tournament_board_spec). What
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
	if _tournament and idx < _tournament_rows.size():
		var row: Dictionary = _tournament_rows[idx] as Dictionary
		if str(row.get("kind", "")) == "challenge":
			var ch: WovpChallenge = row["challenge"] as WovpChallenge
			if ch != null:
				return "board|" + ch.challenge_id + "|" + str(_wovp_fetched_at) + "|" + _wovp_user_id \
					+ "|" + ("owned" if bool(row.get("owned", false)) else "none")
	var ch2: WovpChallenge = null
	for cv: Variant in _wovp_challenges:
		var cand: WovpChallenge = cv as WovpChallenge
		if cand != null and cand.table_external_id == game.game_id:
			ch2 = cand
			break
	return "wing|" + game.game_id + "|" + (ch2.challenge_id if ch2 != null else "") \
		+ "|" + str(_wovp_fetched_at) + "|" + _wovp_user_id


## The spec a panel's back renders: the Tournament board
## for a challenge card in the Tournament Room, the wing
## spec (table data, or board + data) in the library -
## with the book's dressing retired: the spine key goes
## (a card's back joins nothing) and the footer plinth the
## wing waived is restored, because the back carries its
## own Launch button where the board's always sat.
func _card_back_spec(idx: int) -> Dictionary:
	var game: GameEntry = _visible_games[idx]
	var now_unix: int = int(Time.get_unix_time_from_system())
	if _tournament and idx < _tournament_rows.size():
		var row: Dictionary = _tournament_rows[idx] as Dictionary
		if str(row.get("kind", "")) == "challenge":
			var ch: WovpChallenge = row["challenge"] as WovpChallenge
			if ch != null:
				var bspec: Dictionary = RoomSpecs.tournament_board_spec(
					ch, bool(row.get("owned", false)), _wovp_user_id, now_unix)
				bspec["spine_side"] = ""
				return bspec
	var ch2: WovpChallenge = null
	for cv: Variant in _wovp_challenges:
		var cand: WovpChallenge = cv as WovpChallenge
		if cand != null and cand.table_external_id == game.game_id:
			ch2 = cand
			break
	var spec: Dictionary = RoomSpecs.wing_spec(game, ch2, _wovp_user_id, now_unix)
	spec["spine_side"] = ""
	spec["footer_px"] = RoomSpecs.BOARD_FOOTER_PX
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
## a back whose art is still landing shows the page's
## ground, then the content swaps in (the heal below keeps
## retrying a fallback landing, bounded).
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
	# face size (the BOARD_FACE_PX constant), never through
	# the state-panel seams (oldlayout/shortpage resize the
	# board-mode state panels, not a card).
	var tex: Texture2D = await _factory.render_texture(spec, RoomSpecs.BOARD_FACE_PX)
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
	if bmat != null:
		bmat.albedo_texture = tex
	nodes["back_key"] = key
	nodes["back_tex_real"] = real
	_flip_tex_key = key
	_flip_tex_real = real
	# The back's Launch wears the same two faces as the
	# front's (the shared button cache), seated on the
	# spec's plinth; in the Tournament Room it stands only
	# for a challenge he owns - the board spec's own law,
	# the pick-side of which _apply_flip_side enforces.
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


## Launch the focused card's default build. This is the pad's
## answer to the Launch button now that the button is no longer
## a focus stop - the press routes through _activate on the
## card's own Launch quad, so the path is literally the
## button's: the button pulses, the default build resolves,
## the selection persists, and launch_requested fires. Only a
## PANEL focused in plain wall mode counts: rail focus, the
## detail view, and the SETUP placard all leave it inert, and
## the load wait refuses twice over - the poll's deaf gate at
## the call site, then _activate's own refusal. A press that
## lands mid page-slide fires the card focus still sits on
## (the page on screen); the slide's pending travel then
## drops whole at its far point, by its own rule.
func _launch_focused_card() -> void:
	if _mode != "wall" or _placard_up or _setup_panel_up or _focused == null:
		return
	var idx: int = _panels.find(_focused)
	if idx < 0 or idx >= _panel_launches.size():
		return
	_activate(_panel_launches[idx])


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
	if _mode == "wall" and not _placard_up and not _setup_panel_up and _panels.has(_focused):
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
		if _tournament:
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


## A bumper press inside the strip country (the bumper-
## anchors round, 2026-10-28 - Chris: bumpers on the strip
## should "move you to middle, then end. One to two taps
## instead of a bunch"): focus steps to the nearest anchor
## strictly in the press's direction over the pickable
## slots - first, middle, last (LetterIndex.anchor_target
## owns the math, the middle rule included). POSITIONAL,
## NO MEMORY: the anchors are recomputed from the standing
## presence on every press, so a filter change between
## presses is absorbed by the next press without any state
## to go stale. Only strip focus moves - the wall's page
## never turns - and a press at the far anchor clamps,
## spent, focus staying put.
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


## A bumper press's page travel: the centre jumps one page
## of shelf indices (Chris's clarification, 2026-10-24 - the
## bumpers flip PAGES, never filters; the filters change only
## via the rail). CLAMPED at both ends, no wrap, and page
## state persists exactly as a rail press's does. Inert under
## the room's standing input law: the load wait is deaf, the
## SETUP placard owns the room, and the detail view is not
## the wall.
##
## Focus rule (stated for the smoke to assert): focus keeps
## its PLACE across the flip. A focused panel hands focus to
## the panel one page over FROM IT (its own index ± PAGE_SIZE,
## clamped to the shelf's last panel - on the drum a panel IS
## its shelf place, so "the same place" is the index law, not
## a slot on a page); a focused rail stop keeps its stop (the
## rail is persistent furniture - the quad never moves); no
## focus lands on the first panel of the new centre's window.
## A clamped press changes nothing at all.
func _bumper_page(step: int) -> void:
	if _launching_game_id != "" or _placard_up or _setup_panel_up or _mode != "wall":
		return
	# The strip country spends its bumpers at home (the
	# bumper-anchors round, 2026-10-28 - see
	# _strip_anchor_step): while a strip slot holds focus,
	# LB/RB step between the strip's anchors and the wall
	# does NOT turn a page. On the wall or the rail the
	# bumpers keep the page-travel law below, untouched.
	if _focused != null and _is_strip_quad(_focused):
		_strip_anchor_step(step)
		return
	if _visible_games.is_empty():
		return
	_failed_game_id = ""
	_status_note = ""
	if _focused != null and _panels.has(_focused):
		var from: int = _panels.find(_focused)
		var target: int = clampi(from + step * PAGE_SIZE, 0, _visible_games.size() - 1)
		if target == from:
			return ## clamped at the shelf's end: the press is spent
		_set_centre(target)
		_set_focused(_panels[target])
		_persist_view()
	elif _focused != null and _is_rail_quad(_focused):
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


func _open_detail(game: GameEntry) -> void:
	_mode = "detail"
	_selected_game_id = game.game_id
	_store.touch_recent(game.game_id)
	_persist_view()
	for q: ClickableQuad in _panels:
		q.pick_enabled = false
	for q: ClickableQuad in _panel_launches:
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
	out.append_array(_panel_launches)
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
		if not handled.has(q):
			q.pick_enabled = not launching
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null and not handled.has(rq):
			if launching:
				rq.pick_enabled = false ## the load wait is deaf: no rail quad picks, EXIT/SETUP included
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
		var pending: LibraryScanner = _pending_library
		_pending_library = null
		_scanner = pending
		refresh_library()


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
	_setup_panel_back_btn = ClickableQuad.new()
	_setup_panel_back_btn.setup("setup_panel_back", "", placeholder, Vector2(0.5, 0.16))
	_setup_panel_back_btn.position = Vector3(0.0, -1.02, 0.0)
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
	var back_tex: Texture2D = await _factory.render_texture(
		RoomSpecs.button_spec("BACK", true), Vector2i(512, 164))
	if gen != _setup_panel_gen or not _setup_panel_up or _setup_panel_back_btn == null:
		_after_setup_render()
		return
	_setup_panel_back_btn.set_texture(back_tex)
	_after_setup_render()


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
		q.pick_enabled = false
	for k: Variant in _rail_quads.keys():
		_rail_quads[k].pick_enabled = false
	var detail_open: bool = _detail != null and _detail.is_open()
	if detail_open:
		_detail.set_launching(true)
	_set_focused(null)
	_refresh_focusables()
	_swap_launch_textures()
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
## say so: the failure lands on the wall (FAILED button, banner
## note) and browsing resumes. In detail mode the detail view is
## the visible surface - its Play button is restored and the wall
## rebuilds when it closes, as usual.
func end_launch_failed(game: GameEntry, reason: String) -> void:
	_dismiss_marquee()
	_launching_game_id = ""
	_failed_game_id = game.game_id
	_status_note = "Launch failed: %s - %s" % [game.title, reason]
	if _detail != null and _detail.is_open():
		_detail.set_launching(false)
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
func _apply_wall_alpha(a: float) -> void:
	if absf(a - _wall_alpha_applied) < 0.002:
		return
	_wall_alpha_applied = a
	for i: int in range(_panels.size()):
		_panels[i].set_content_alpha(a * _haze_for(i))
	for i2: int in range(_panel_launches.size()):
		_panel_launches[i2].set_content_alpha(a * _haze_for(i2))
	for k: Variant in _rail_quads.keys():
		var rq: ClickableQuad = _rail_quads[k] as ClickableQuad
		if rq != null:
			rq.set_content_alpha(a)
	for skey: Variant in _strip_quads.keys():
		var sq: ClickableQuad = _strip_quads[skey] as ClickableQuad
		if sq != null:
			sq.set_content_alpha(a)
	# The status line fades with the wall, and so do the
	# cards' nameplates (plate + label ride their cards).
	# The plates all share one material, so its alpha is
	# set once, here.
	if _status_label != null:
		_status_label.modulate = Color(0.92, 0.95, 1.0, a)
		_status_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9 * a)
	_plate_mat().albedo_color = Color(0.0, 0.0, 0.0, 0.66 * a)
	for idx: int in range(_panels.size()):
		if idx < _panel_labels.size() and _panel_labels[idx] != null:
			var la: float = a * _haze_for(idx)
			_panel_labels[idx].modulate = Color(0.96, 0.97, 1.0, la)
			_panel_labels[idx].outline_modulate = Color(0.0, 0.0, 0.0, 0.9 * la)


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
	if game != null:
		var on_path: String = game.pair_on_art()
		if on_path != "":
			on_tex = TextureFactory.load_art_texture(on_path)
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
	_build_power_overlay(panel, face_tex, on_tex)
	print("POWER: start game=\"%s\" mode=%d %s" % [
		label, _power_mode,
		"pair-crossfade" if _power_pair else "mimic"])
	print("POWER: phase 0->1 game=\"%s\"" % label)
	_apply_power()


## The power-on's subject for a shot-faced game: its
## backglass rendered as a face (the same art render the
## card itself would wear without a shot - strip suppressed,
## the nameplate carries the name), cached per game for the
## library adoption. Null while unrendered.
func _power_subject_cached(game: GameEntry) -> Texture2D:
	var ent: Variant = _power_subject_cache.get(game.game_id, null)
	if ent == null:
		return null
	return (ent as Array)[1] as Texture2D


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
	var tex: Texture2D = null
	if path != "":
		var src: Texture2D = TextureFactory.load_art_texture(path)
		if src != null:
			tex = await _factory.render_texture(RoomSpecs.art_spec(game, src, _store, false), _panel_face_px)
	_power_subject_inflight.erase(game.game_id)
	if tex != null:
		_power_subject_cache[game.game_id] = [path, tex]
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
func _build_power_overlay(panel: ClickableQuad, face_tex: Texture2D, on_tex: Texture2D) -> void:
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
	for n: Node in [_bg_starfield, _bg_starfield_near, _bg_wireframe, _bg_ring]:
		if n != null:
			out.append(n)
	return out




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
	return {
		"rail_span": rail_hi - rail_lo if rail_hi > rail_lo else 0.0,
		"strip_span": strip_hi - strip_lo if strip_hi > strip_lo else 0.0,
		"rail_stops": _rail_quads.size(),
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


func _swap_launch_textures() -> void:
	var gen: int = _gen
	for i: int in range(_panel_launches.size()):
		if i >= _visible_games.size():
			break
		var game: GameEntry = _visible_games[i]
		var is_this: bool = game.game_id == _launching_game_id
		var tex: Texture2D = await _factory.render_texture(
			RoomSpecs.button_spec("LOADING..." if is_this else "LAUNCH", is_this), Vector2i(512, 164))
		if gen != _gen:
			return
		_panel_launches[i].set_texture(tex)


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


func _process(delta: float) -> void:
	# The flat (non-XR) camera is STATIC at the seated viewpoint - the
	# mouse is a pure pointer there, never a look control. A view that
	# drifts with the cursor makes every click target swim (field
	# finding, round 2). XR head tracking owns the view in XR only.
	# Gamepad: left stick / d-pad moves focus, A starts the
	# focused card (selects everywhere else), B goes back in
	# the detail view, Y opens the focused card's info, X
	# toggles the focused card's favorite.
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
	_update_swing(delta)
	_update_power(delta)
	var deaf: bool = _launching_game_id != ""
	_joy_cooldown = maxf(0.0, _joy_cooldown - delta)
	var ax: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ay: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var dir: Vector2 = Vector2.ZERO
	if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT) or ax < -0.55:
		dir = Vector2(-1.0, 0.0)
	elif ax > 0.55:
		dir = Vector2(1.0, 0.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP) or ay < -0.55:
		dir = Vector2(0.0, -1.0)
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN) or ay > 0.55:
		dir = Vector2(0.0, 1.0)
	if dir != Vector2.ZERO and _joy_cooldown <= 0.0:
		if not deaf:
			_move_focus(dir)
		_joy_cooldown = 0.24
	var a_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if a_now and not _joy_prev_a and _focused != null and not deaf:
		_a_press()
	_joy_prev_a = a_now
	var b_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	if b_now and not _joy_prev_b and not deaf:
		if _mode == "detail":
			_detail.handle_escape()
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
	# Bumpers (LB/RB): page travel, the section slide (Chris's
	# banked note, 2026-10-23; his clarification, 2026-10-24:
	# "my intention for bumpers was for the entire section to
	# shift left or right, one page to other"). One page per
	# fresh press - edge only, no held repeat - and the gating
	# (load wait, placard, detail view) lives in _bumper_page.
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
	var right_now: bool = Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT)
	if not right_now:
		_joy_right_armed = true ## a witnessed released poll: fresh press edges count from here on
	if right_now and not _joy_prev_right and _joy_right_armed and not deaf:
		if _setup_panel_up:
			hide_setup_panel() ## on the SETUP panel the BACK button goes back - it never exits
		elif not _placard_up:
			_handle_rail("exit")
	_joy_prev_right = right_now


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
	"filter:all", "filter:vr", "filter:favorites", "filter:recents",
	"sort", "tournament", "page_prev", "page_next", "wovp_refresh", "desk", "exit",
]


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
## the drum's grid step. (Its other half - the standing
## board borrowing the slot right of the centred challenge,
## hiding its card - is DELETED with the board itself in
## GRADFIX6: the flip has no slot to borrow, so no NC can
## restore it; the tournament smoke's no-borrow legs now
## pass on every build and guard the flip instead.) Empty
## in every real run.
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
