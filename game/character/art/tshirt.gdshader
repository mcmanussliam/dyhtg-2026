shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://game/character/art/character_surface.gdshaderinc"

uniform sampler2D chest_logo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	vec3 p = model_position;
	float front = smoothstep(0.10, 0.18, p.z);
	// A scoop collar, low hem and short sleeves leave the head, hands and legs bare.
	float collar_height = 0.80 - 0.035 * front * exp(-p.x * p.x / 0.02);
	float collar = 1.0 - smoothstep(collar_height - 0.005, collar_height + 0.005, p.y);
	float hem = smoothstep(0.26, 0.27, p.y);
	float torso = 1.0 - smoothstep(0.29, 0.31, p.z);
	float arm_region = smoothstep(0.20, 0.25, abs(p.x));
	float sleeve_end = smoothstep(0.19, 0.215, p.y - p.z);
	float shirt = mix(1.0, sleeve_end, arm_region) * torso * hem * collar;
	vec3 colour = mix(character_surface(p), vec3(0.115, 0.120, 0.130), shirt);
	// Project onto the chest surface: the print bends with the same seamless body.
	vec2 logo_uv = vec2(p.x / 0.39 + 0.5, (0.705 - p.y) / 0.08357 + 0.5);
	float inside = step(0.0, logo_uv.x) * step(logo_uv.x, 1.0)
		* step(0.0, logo_uv.y) * step(logo_uv.y, 1.0);
	float print_mask = texture(chest_logo, logo_uv).a * inside * front * shirt;
	ALBEDO = mix(colour, vec3(1.0), print_mask);
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
