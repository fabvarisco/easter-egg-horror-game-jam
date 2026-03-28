shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 sphere_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float pulse_speed = 2.0;
uniform float pulse_amount = 0.15;
uniform float glow_intensity = 5.0;
uniform float fresnel_power = 2.0;
uniform float base_alpha = 0.6;
uniform bool enable_pulse = true;
uniform bool enable_scanlines = true;
uniform float scanline_density = 20.0;
uniform float scanline_speed = 1.0;

void vertex() {
	// Expandir vértices para criar a esfera ao redor
	float pulse = 1.0;
	if (enable_pulse) {
		pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	}

	VERTEX = VERTEX * pulse;
}

void fragment() {
	// Efeito Fresnel - brilha mais nas bordas
	vec3 normal = normalize(NORMAL);
	vec3 view = normalize(VIEW);
	float fresnel = pow(1.0 - abs(dot(normal, view)), fresnel_power);

	// Cor base com brilho
	vec3 color = sphere_color.rgb * glow_intensity;

	// Adicionar pulso de brilho
	float brightness_pulse = 1.0;
	if (enable_pulse) {
		brightness_pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);
		color *= brightness_pulse;
	}

	// Scanlines animadas para efeito high-tech
	float scanlines = 1.0;
	if (enable_scanlines) {
		float scan = sin((UV.y * scanline_density + TIME * scanline_speed) * 3.14159 * 2.0);
		scanlines = 0.8 + scan * 0.2;
		color *= scanlines;
	}

	// Intensificar o fresnel
	float final_fresnel = pow(fresnel, 0.8); // Suavizar um pouco para ser mais visível
	color *= (0.3 + final_fresnel * 0.7); // Garantir que tenha cor base visível

	ALBEDO = color;
	EMISSION = color * 1.5; // Emissão muito forte
	ALPHA = (final_fresnel * 0.7 + 0.3) * base_alpha * brightness_pulse;
}
