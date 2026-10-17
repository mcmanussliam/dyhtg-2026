shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec4 clothing_colour : source_color = vec4(0.2,0.6,0.4,1.0);
uniform vec4 logo_colour : source_color = vec4(1.0);
uniform int garment_kind = 1;
uniform bool has_logo = false;
uniform sampler2D chest_logo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 garment_position;

void vertex() { garment_position = VERTEX; }

void fragment() {
	vec3 p = garment_position;
	vec3 fabric = clothing_colour.rgb;
	if (garment_kind == 6) {
		float belt = (1.0-smoothstep(0.014,0.022,abs(p.y-0.46)))
			+ (1.0-smoothstep(0.014,0.022,abs(p.y-0.60)));
		float braces = (1.0-smoothstep(0.014,0.022,abs(abs(p.x)-0.145))) * smoothstep(0.60,0.62,p.y);
		fabric = mix(fabric, vec3(0.83,0.86,0.85), clamp(max(belt,braces),0.0,1.0));
	}
	if (has_logo) {
		float width = garment_kind == 2 ? 0.29 : 0.39;
		float logo_height = 0.705;
		vec2 uv = vec2(p.x / width + 0.5, (logo_height - p.y) / (width*0.21428) + 0.5);
		float inside = step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
		float front = smoothstep(0.12,0.20,p.z);
		fabric = mix(fabric, logo_colour.rgb, texture(chest_logo,uv).a * inside * front);
	}
	ALBEDO = fabric;
	ROUGHNESS = 0.94;
	SPECULAR = 0.14;
}
