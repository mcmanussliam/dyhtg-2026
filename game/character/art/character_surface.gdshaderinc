uniform vec4 skin_colour : source_color = vec4(0.92, 0.88, 0.82, 1.0);
uniform vec4 face_colour : source_color = vec4(0.96, 0.94, 0.90, 1.0);

vec3 character_surface(vec3 model_position) {
	// Colour on the head surface itself: no raised panel or intersecting shells.
	float front = smoothstep(0.10, 0.15, model_position.z);
	vec2 face_uv = vec2(model_position.x / 0.17, (model_position.y - 0.98) / 0.18);
	float panel = (1.0 - smoothstep(0.93, 1.0, length(face_uv))) * front;
	vec2 eye_uv = vec2(model_position.x, (model_position.y - 0.995) * 0.88);
	float left_eye = 1.0 - smoothstep(0.020, 0.026, length(eye_uv - vec2(-0.065, 0.0)));
	float right_eye = 1.0 - smoothstep(0.020, 0.026, length(eye_uv - vec2(0.065, 0.0)));
	float eyes = max(left_eye, right_eye) * front;
	return mix(mix(skin_colour.rgb, face_colour.rgb, panel), vec3(0.002), eyes);
}
