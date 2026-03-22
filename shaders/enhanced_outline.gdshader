shader_type spatial;
render_mode cull_front, unshaded, blend_add;

uniform vec4 outline_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float outline_width = 0.05;
uniform float pulse_speed = 2.0;
uniform float pulse_amount = 0.3;
uniform float glow_intensity = 3.0;
uniform bool enable_pulse = true;

void vertex() {
	// Animação de pulso
	float pulse = 1.0;
	if (enable_pulse) {
		pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	}

	// Expandir ao longo da normal para criar outline
	float expand = outline_width * pulse;
	VERTEX += NORMAL * expand;
}

void fragment() {
	// Cor base com brilho
	vec3 color = outline_color.rgb * glow_intensity;

	// Adicionar pulso de brilho
	if (enable_pulse) {
		float brightness_pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
		color *= 1.0 + brightness_pulse * 0.6;
	}

	ALBEDO = color;
	EMISSION = color * 1.2; // Emissão forte para brilhar
	ALPHA = outline_color.a;
}
