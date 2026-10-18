shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Black bug mush, drawn as an ordinary world-space surface: a floor decal, plus a material
// overlay on large furniture and walls. Depth testing and draw order therefore keep
// characters and spray on top of it.
// Every landed clump is a smooth falloff and the falloffs are summed, so clumps that meet
// flow together. The kernel and threshold match ComputerBugsStage.danger_field, which
// decides who is eliminated. Cheap by design: no trigonometry in the zone loop, early outs,
// and and no per-pixel bug drawing: the beetles are real instances.

uniform vec4 zones[48]; // World x, world z (metres), 1 / reach^2, per-clump seed.
uniform int zone_count = 0;
const float THRESHOLD = 0.2038; // (1 - 1 / REACH^2)^2 with REACH 1.35.
varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

void vertex() {
	// Sit a hair above the surface it covers, to avoid z-fighting.
	vec3 normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + normal * 0.004;
	world_normal = normal;
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	vec3 world = world_position;
	float total = 0.0;
	for (int i = 0; i < 48; i++) {
		if (i >= zone_count) {
			break;
		}
		vec2 offset = world.xz - zones[i].xy;
		float falloff = 1.0 - dot(offset, offset) * zones[i].z;
		if (falloff > 0.0) {
			total += falloff * falloff;
		}
	}
	// Higher surfaces need more mass, so it climbs furniture and walls from the bottom up.
	float climb = 1.0 + world.y * 0.16;
	if (total < THRESHOLD * 0.8 * climb) {
		discard;
	}
	// Surface coordinates follow the plane being covered, so walls are not stretched.
	vec3 n = abs(normalize(world_normal));
	vec2 surface = world.xz;
	if (n.y < max(n.x, n.z)) {
		surface = n.x > n.z ? vec2(world.z, world.y) : vec2(world.x, world.y);
	}
	// Noise nudges the threshold so the boundary is ragged and mushy.
	float grain = value_noise(surface * 3.0 + vec2(TIME * 0.25, -TIME * 0.18));
	float edge_threshold = THRESHOLD * (0.88 + 0.24 * grain) * climb;
	float body = smoothstep(edge_threshold * 0.96, edge_threshold * 1.06, total);
	if (body <= 0.002) {
		discard;
	}
	// Dark, damp mush: just lighter than the beetles on it so they stand out against it.
	float slick = value_noise(surface * 5.0 - vec2(TIME * 0.2, 0.0));
	vec3 colour = vec3(0.034, 0.036, 0.042) + vec3(0.05, 0.055, 0.06) * slick * grain;
	ALBEDO = colour * (0.85 + 0.15 * n.y);
	ALPHA = body * 0.97;
}
