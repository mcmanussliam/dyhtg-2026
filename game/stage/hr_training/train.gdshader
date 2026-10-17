shader_type spatial;
render_mode cull_back;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 room_bounds; // World x/z minimum then maximum. Clip at tunnel entrances.
uniform float metalness = 0.0;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_position.x < room_bounds.x || world_position.z < room_bounds.y ||
		world_position.x > room_bounds.z || world_position.z > room_bounds.w) {
		discard;
	}
	ALBEDO = tint.rgb;
	METALLIC = metalness;
	ROUGHNESS = 0.6;
}
