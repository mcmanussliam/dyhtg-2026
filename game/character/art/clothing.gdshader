shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec4 clothing_colour : source_color = vec4(0.2,0.6,0.4,1.0);
uniform vec4 logo_colour : source_color = vec4(1.0);
uniform int garment_kind = 1;
uniform bool has_logo = false;
uniform sampler2D chest_logo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 garment_position;

void vertex() { garment_position = VERTEX; }

float line(float distance, float width) { return 1.0-smoothstep(width*0.6,width,abs(distance)); }

void fragment() {
	vec3 p = garment_position;
	vec3 fabric = clothing_colour.rgb;
	vec3 shirt = vec3(0.92,0.91,0.87);
	float front = smoothstep(0.12,0.18,p.z);
	float roughness = 0.94;
	if (garment_kind == 8) {
		float seam = line(fract((p.y-0.27)/0.0905+0.5)-0.5, 0.07);
		fabric *= 1.0 - 0.28*seam;
		fabric = mix(fabric, fabric*0.55, line(p.x,0.007)*front);
		roughness = 0.58;
	} else if (garment_kind == 9) {
		float vline = 0.80-0.33*clamp((p.z-0.12)/0.08,0.0,1.0)*clamp(1.0-abs(p.x)/0.15,0.0,1.0);
		float inside = smoothstep(-0.004,0.004,p.y-vline)*front;
		float tie = (1.0-smoothstep(0.016,0.020,abs(p.x)-(0.78-p.y)*0.05))*step(p.y,0.785);
		vec3 placket = mix(shirt, fabric*0.62, tie);
		fabric = mix(fabric, placket, inside);
		for (int i = 0; i < 3; i++) {
			float button = 1.0-smoothstep(0.009,0.013,length(p.xy-vec2(0.0,0.43-float(i)*0.06)));
			fabric = mix(fabric, logo_colour.rgb, button*front*(1.0-inside));
		}
	} else if (garment_kind == 10) {
		fabric = mix(fabric, mix(fabric,vec3(1.0),0.28), smoothstep(0.61,0.625,p.y));
		fabric = mix(fabric, fabric*0.55, line(p.x,0.006)*front);
		roughness = 1.0;
	} else if (garment_kind == 13) {
		float width = 0.021+(0.745-p.y)*0.13;
		float tie = step(abs(p.x),width+0.002)*step(p.y,0.757)*smoothstep(0.13,0.15,p.z);
		float stripe = step(0.5,fract((p.x+p.y)*16.0))*step(p.y,0.71);
		fabric = mix(shirt, mix(fabric,logo_colour.rgb,stripe*0.35), tie);
	} else if (garment_kind == 14) {
		fabric = shirt;
	} else if (garment_kind == 15) {
		fabric = mix(fabric, logo_colour.rgb, step(0.5,fract(p.y*13.0))*0.8);
		roughness = 1.0;
	}
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
	ROUGHNESS = roughness;
	SPECULAR = 0.14;
}
