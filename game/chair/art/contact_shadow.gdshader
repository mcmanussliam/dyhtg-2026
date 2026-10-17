shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = vec3(0.02, 0.04, 0.04);
	ALPHA = (1.0 - smoothstep(0.15, 1.0, radius)) * 0.22;
}
