shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha;

varying float opacity;

void vertex() {
	opacity = COLOR.a;
}

void fragment() {
	// Keep a readable sphere gradient even against the bright pastel floor.
	float shade = 0.66 + 0.32 * max(dot(normalize(NORMAL), normalize(vec3(-0.4, 0.6, 1.0))), 0.0);
	ALBEDO = vec3(0.94, 0.98, 0.99) * shade;
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
	ALPHA = opacity * smoothstep(0.0, 0.28, abs(normalize(NORMAL).z));
}
