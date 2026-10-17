shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 wall_colour : source_color = vec4(0.447, 0.463, 0.482, 1.0);
uniform float surface_roughness = 0.8;
uniform float fade_start = 8.0;
uniform float fade_end = 24.0;
varying float world_height;

void vertex() {
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float depth = max(-world_height, 0.0);
	ALBEDO = wall_colour.rgb * (1.0 - smoothstep(fade_start, fade_end, depth));
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.12;
}
