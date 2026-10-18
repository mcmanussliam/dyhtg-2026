shader_type spatial;
// Glossy black beetle, positioned entirely on the GPU. Each instance sits at its mass's
// centre; its offset is stored as a fraction of the mass radius, and the radius comes from
// a uniform. As a mass swells its beetles therefore glide outward smoothly, with no CPU
// re-layout. Per instance: COLOR = (shade, heading, size), CUSTOM = (phase, unit x, unit z, block).

uniform float radii[48]; // Current radius of every mass, in metres.
uniform vec4 room = vec4(-1000.0, -1000.0, 1000.0, 1000.0); // min x, min z, max x, max z.

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	vec2 unit = INSTANCE_CUSTOM.yz;
	int block = int(INSTANCE_CUSTOM.w + 0.5);
	float heading = COLOR.g;
	float size = COLOR.b;
	float radius = radii[block];
	// A slow wander plus a gentle twitch, both smooth, so bugs seem alive without jumping.
	float twitch = sin(TIME * 8.0 + phase);
	vec3 drift = vec3(sin(TIME * 1.1 + phase), 0.0, cos(TIME * 0.9 + phase * 1.3)) * 0.07;
	vec3 local = VERTEX * size;
	local.x *= 1.0 + 0.05 * twitch;
	local.z *= 1.0 - 0.05 * twitch;
	local.y += 0.012 * abs(sin(TIME * 6.0 + phase * 1.7));
	float turn = -heading - 1.5707963 + 0.12 * sin(TIME * 1.7 + phase);
	float cs = cos(turn);
	float sn = sin(turn);
	local = vec3(local.x * cs + local.z * sn, local.y, -local.x * sn + local.z * cs);
	vec3 offset = vec3(unit.x * radius, 0.02, unit.y * radius) + drift;
	vec3 centre = vec3(MODEL_MATRIX[3].x, 0.0, MODEL_MATRIX[3].z);
	vec3 spot = centre + offset;
	// Bugs never crawl off the floor: any that would is shrunk away.
	if (spot.x < room.x || spot.z < room.y || spot.x > room.z || spot.z > room.w) {
		local = vec3(0.0);
	}
	VERTEX = local + offset;
	NORMAL = vec3(NORMAL.x * cs + NORMAL.z * sn, NORMAL.y, -NORMAL.x * sn + NORMAL.z * cs);
}

void fragment() {
	ALBEDO = vec3(COLOR.r, COLOR.r * 1.1, COLOR.r * 1.3);
	METALLIC = 0.55;
	ROUGHNESS = 0.22;
	SPECULAR = 0.9;
}
