shader_type canvas_item;
render_mode blend_premul_alpha;

uniform float eliminated : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 portrait = texture(TEXTURE, UV);
	// Retain the viewport transparency and premultiplied colour at the crop edge.
	vec3 colour = portrait.rgb;
	float grey = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour = mix(colour, vec3(grey) * 0.55, eliminated);
	float radius = length((UV - vec2(0.5)) * 2.0);
	float edge = max(fwidth(radius), 0.001);
	float mask = 1.0 - smoothstep(1.0 - edge, 1.0, radius);
	COLOR = vec4(colour * mask, portrait.a * mask);
}
