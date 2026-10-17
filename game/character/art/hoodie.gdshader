shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://game/character/art/character_surface.gdshaderinc"
varying vec3 model_position;
void vertex() { model_position = VERTEX; }
void fragment() {
	vec3 p = model_position;
	float collar = 1.0 - smoothstep(0.805, 0.825, p.y);
	float hem = smoothstep(0.24, 0.26, p.y);
	float hands = 1.0 - smoothstep(0.32, 0.35, p.z);
	float cloth = collar * hem * hands;
	vec3 fabric = clothing_colour.rgb;
	// A subtly darker kangaroo pocket follows the existing body surface.
	float pocket = (1.0-smoothstep(0.14,0.16,abs(p.x))) * smoothstep(0.30,0.31,p.y)
		* (1.0-smoothstep(0.43,0.44,p.y)) * smoothstep(0.16,0.20,p.z);
	ALBEDO = mix(character_surface(p), fabric * (1.0 - pocket * 0.07), cloth);
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
