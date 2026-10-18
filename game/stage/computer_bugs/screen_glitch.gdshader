shader_type spatial;
render_mode unshaded, cull_disabled;
// A corrupted monitor: scrolling red static with bright green bug-code streaks.

void fragment() {
	float row = floor(UV.y * 14.0 - TIME * 3.0);
	float streak = step(0.62, fract(sin(row * 91.7) * 437.5));
	float shift = fract(sin(row * 12.9 + floor(TIME * 6.0)) * 43758.5);
	float band = step(0.5, fract(UV.x * 9.0 + shift));
	vec3 dark = vec3(0.30, 0.02, 0.03);
	vec3 bright = vec3(0.25, 1.0, 0.3);
	ALBEDO = mix(dark, bright, streak * band);
}
