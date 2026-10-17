shader_type spatial;
uniform vec4 paint : source_color = vec4(0.75, 0.075, 0.06, 1.0);
varying float height;

void vertex() {
	height = VERTEX.y;
}

void fragment() {
	float band = smoothstep(0.20, 0.203, height) * (1.0 - smoothstep(0.312, 0.315, height));
	ALBEDO = mix(paint.rgb, vec3(0.94, 0.67, 0.045), band);
	METALLIC = 0.10;
	ROUGHNESS = 0.44;
}
