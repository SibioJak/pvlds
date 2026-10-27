shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// The power-on mimic (the swap round): ONE overlay quad over
// the performing card's face, grading the face's own pixels -
// a lamp-catch envelope and a diagonal light sweep applied to
// the printed art, the way light blooms unevenly across a real
// glass. There are no snippet layers: the room holds no bulb
// geometry, only this grade. `power` is the catch envelope
// (0..1, host-driven through its stutters and sag - see
// RoomView.MIMIC_POWER_KEYS); `sweep` drives the diagonal
// front. The per-pixel grade:
//   base x (1 + 0.50*luma^0.75 + 0.90*sat*(0.25 + 0.75*luma))
// plus a 0.40 additive glow above luma 0.70 - with two
// production additions over the prototype:
//
// Soft shoulder: the grade's gain rolls off as the pixel's own
// luma approaches 1 (the `head` factor), and the graded result
// passes a soft-clip knee, so bright printed art (Goonies'
// yellow title ran hot in the prototype) lifts gently instead
// of pinning channels at full.
//
// Pair crossfade: a pair card's `on_tex` is the author's lit
// On image; `pair_mix` crossfades the SOURCE to it across the
// back of the cascade while the synthesized grade retires, so
// the settled card is the On image itself, whole - no
// fragments, no blend of two pictures at rest.
//
// At zero applied grade (power 0, or a completed crossfade)
// the output is the source pixel-for-pixel: the shoulder only
// ever touches the grade's own excess (the `act` blend).

uniform sampler2D face_tex;
uniform sampler2D on_tex;
uniform float power = 0.0;
uniform float sweep = 0.0;
uniform float pair_mix = 0.0;
uniform float has_pair = 0.0;
uniform float lift_lum = 0.50;
uniform float lift_sat = 0.90;
uniform float glow_gain = 0.40;
uniform float glow_knee = 0.70;

float luma709(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Soft shoulder for one channel: identity below the knee,
// then an exponential approach to the cap. The derivative is
// 1 at the knee and falls toward 0 - highlights compress
// instead of clipping, and no graded channel reaches 1.0.
float shoulder(float c) {
	float knee = 0.92;
	float cap = 0.99;
	if (c <= knee) {
		return c;
	}
	float span = cap - knee;
	return knee + span * (1.0 - exp(-(c - knee) / span));
}

void fragment() {
	vec4 base = texture(face_tex, UV);
	vec3 src = base.rgb;
	if (has_pair > 0.5) {
		src = mix(base.rgb, texture(on_tex, UV).rgb, pair_mix);
	}
	float lum = luma709(src);
	float mx = max(src.r, max(src.g, src.b));
	float mn = min(src.r, min(src.g, src.b));
	float sat = mx > 0.001 ? (mx - mn) / mx : 0.0;
	float diag = (UV.x + UV.y) * 0.5;
	float front = clamp((sweep * 1.35 - diag) / 0.35, 0.0, 1.0);
	float e = power * front;
	// Soft shoulder, gain side: full drive in the glass's body
	// (luma up to 0.65), rolling off to a 0.15 floor at white.
	float head = clamp((1.0 - lum) / 0.35, 0.15, 1.0);
	float drive = e * head * (lift_lum * pow(lum, 0.75) + lift_sat * sat * (0.25 + 0.75 * lum));
	float glow = glow_gain * e * head * smoothstep(glow_knee, 1.0, lum);
	if (has_pair > 0.5) {
		drive *= 1.0 - pair_mix;
		glow *= 1.0 - pair_mix;
	}
	vec3 graded = src * (1.0 + drive) + src * glow;
	float act = clamp(drive + glow, 0.0, 1.0);
	vec3 col = mix(src, vec3(shoulder(graded.r), shoulder(graded.g), shoulder(graded.b)), act);
	ALBEDO = col;
	ALPHA = 1.0;
}
