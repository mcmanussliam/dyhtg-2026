shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// One floor decal for every infected computer. Each zone is a smooth falloff and the
// zones are summed, so overlapping areas fuse into a single flowing shape. The kernel
// and threshold match ComputerBugsStage.danger_field, which decides who is eliminated.

uniform vec4 zones[16]; // World x, world z, radius in metres, state (0 off, 1 warning, 2 lethal).
uniform vec3 warning_colour : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 lethal_colour : source_color = vec3(1.0, 0.10, 0.08);
const float REACH = 1.35;
const float THRESHOLD = 0.2038; // (1 - 1 / REACH^2)^2

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float total = 0.0;
	float lethal = 0.0;
	for (int i = 0; i < 16; i++) {
		if (zones[i].w < 0.5) {
			continue;
		}
		vec2 offset = world_position.xz - zones[i].xy;
		// A gentle ripple makes the edge feel alive without changing its footprint much.
		float ripple = 1.0 + 0.035 * sin(atan(offset.y, offset.x) * 5.0 + TIME * 1.6 + float(i) * 1.9);
		float d2 = dot(offset, offset) / (ripple * ripple);
		float radius = zones[i].z;
		float falloff = max(1.0 - d2 / (REACH * REACH * radius * radius), 0.0);
		falloff *= falloff;
		total += falloff;
		if (zones[i].w > 1.5) {
			lethal += falloff;
		}
	}
	float body = smoothstep(THRESHOLD * 0.93, THRESHOLD * 1.07, total);
	float edge = smoothstep(THRESHOLD * 1.0, THRESHOLD * 1.5, total) ;
	vec3 colour = mix(warning_colour, lethal_colour, clamp(lethal / max(total, 0.0001), 0.0, 1.0));
	// Brighter rim, calmer middle.
	float alpha = body * mix(0.40, 0.22, edge);
	ALBEDO = colour;
	ALPHA = alpha;
}
