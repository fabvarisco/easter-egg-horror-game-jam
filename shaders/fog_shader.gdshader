shader_type fog;

uniform vec3 fog_color: source_color = vec3(0.2, 0.8, 0.4);
uniform float density_scale: hint_range(0.0, 10.0, 0.01) = 1.0;
uniform float noise_scale: hint_range(0.0, 5.0, 0.01) = 1.5;
uniform float speed: hint_range(0.0, 5.0, 0.01) = 1.0;
uniform float height_falloff: hint_range(0.0, 5.0, 0.01) = 1.5;
uniform float emission: hint_range(0.0, 1.0, 0.01) = 0.5;
uniform vec2 wind = vec2(0.0,1.0);

vec2 hash22(vec2 uv){
	uv = vec2(dot(uv,vec2(127.1,311.7)),
		dot(uv,vec2(269.5,183.3)));
	return 2.0 * fract(sin(uv) * 43758.5453123)- 1.0;
}

float noise(vec2 uv){
	vec2 iuv = fract(uv);
	vec2 fuv = fract(uv);
	vec2 blur = smoothstep(0.0,1.0,fuv);
	return mix (mix(dot(hash22(iuv + vec2(0.0,0.0)),fuv - vec2(0.0,0.0)),
						dot(hash22(iuv + vec2(1.0,0.0)), fuv - vec2(1.0,0.0)),blur.x),
					mix(dot(hash22(iuv + vec2(0.0,1.0)),fuv - vec2(0.0,1.0)),
						dot(hash22(iuv + vec2(1.0,1.0)),fuv - vec2(1.0,1.0)),blur.x),blur.y)+0.5;
}
float fbm(vec2 p){
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2,1.6));
	float f = 0.0;
	f += 0.5 * noise(p); p = m * p;
	f += 0.25 * noise(p); p = m * p;
	f += 0.125 * noise(p); p = m * p;
	f += 0.0625 * noise(p);
	return 0.6 + 0.5 *f;
}
void fog() {
	vec3 p = WORLD_POSITION;
	float shift = TIME * speed + pow(abs(p.y),1.25);
	float noise = fbm(vec2(p.x,p.z)* noise_scale - wind*shift);
	float height_mask = exp(-max(p.y, 0.0)* height_falloff);
	ALBEDO = fog_color;
	DENSITY = clamp(noise * height_mask * density_scale, 0.0, 1.0);
	EMISSION= fog_color * DENSITY * emission;

}
