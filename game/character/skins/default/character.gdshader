shader_type spatial;
// Keep skin softly lit without tiny hat/clothing shadow-map artefacts on the face.
render_mode diffuse_burley, specular_schlick_ggx, shadows_disabled;

#include "res://game/character/art/character_surface.gdshaderinc"
varying vec3 model_position;

void vertex() {
	model_position = VERTEX;
}

void fragment() {
	ALBEDO = character_surface(model_position);
	ROUGHNESS = 0.90;
	SPECULAR = 0.17;
}
