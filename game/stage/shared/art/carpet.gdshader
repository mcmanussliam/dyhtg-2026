shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec4 light_blue : source_color = vec4(0.49, 0.71, 0.88, 1.0);
uniform vec4 dark_blue : source_color = vec4(0.20, 0.37, 0.55, 1.0);
uniform vec4 side_grey : source_color = vec4(0.28, 0.29, 0.31, 1.0);
uniform float platform_depth = 24.0;
uniform float tile_size = 1.2;
varying vec3 local_position;
varying float top_surface;

void vertex() {
	local_position = VERTEX;
	top_surface = max(NORMAL.y, 0.0);
}

void fragment() {
	vec2 grid = local_position.xz * (3.14159265 / tile_size);
	float pattern = sin(grid.x) * sin(grid.y);
	float aa = max(fwidth(pattern), 0.0001);
	float checker = smoothstep(-aa, aa, pattern);
	vec3 top = mix(light_blue.rgb, dark_blue.rgb, checker);
	float depth = max(platform_depth * 0.5 - local_position.y, 0.0);
	vec3 side = side_grey.rgb * (1.0 - smoothstep(1.5, 7.0, depth));
	ALBEDO = mix(side, top, smoothstep(0.2, 0.9, top_surface));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
