shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 floor_colour : source_color = vec4(0.18039, 0.25098, 0.33333, 1.0);
uniform vec4 storage_colour : source_color = vec4(0.32157, 0.41176, 0.47451, 1.0);
uniform vec4 lounge_colour : source_color = vec4(0.38824, 0.46275, 0.44706, 1.0);
// Match the concrete sides used by the crack maps.
uniform vec4 warning_colour : source_color = vec4(0.447, 0.463, 0.482, 1.0);
uniform float floor_clock = 0.0;
uniform float warning_duration = 1.6;
uniform float units = 0.0232558;
uniform bool instanced = true;
uniform vec2 tile_origin;
varying vec2 map_point;
varying float armed_time;
varying float world_height;

void vertex() {
	map_point = VERTEX.xz / units + (instanced ? INSTANCE_CUSTOM.gb : tile_origin);
	armed_time = instanced ? INSTANCE_CUSTOM.r : -1.0;
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 colour = floor_colour.rgb;
	if (map_point.x >= 875.0 && map_point.x <= 1270.0 && map_point.y >= -191.0 && map_point.y <= 99.0) {
		colour = storage_colour.rgb;
	}
	if (map_point.x >= 880.0 && map_point.x <= 1270.0 && map_point.y >= 765.0 && map_point.y <= 1035.0) {
		colour = lounge_colour.rgb;
	}
	// Untouched panels form one flat floor; warnings change only after contact.
	if (armed_time >= 0.0) {
		float progress = clamp((floor_clock - armed_time) / warning_duration, 0.0, 1.0);
		// A uniform, one-way colour change communicates the remaining warning time.
		vec3 warning = warning_colour.rgb;
		colour = mix(colour, warning, mix(0.25, 1.0, progress));
	}
	ALBEDO = colour * (1.0 - smoothstep(6.0, 18.0, max(-world_height, 0.0)));
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
}
