shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 circle_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float circle_radius = 1.5;
uniform float circle_thickness = 0.15;
uniform float pulse_speed = 2.0;
uniform float pulse_amount = 0.2;
uniform float glow_intensity = 3.0;
uniform bool enable_pulse = true;

void fragment() {
	// Calcular distância do centro do quad
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);

	// Animação de pulso
	float pulse = 1.0;
	if (enable_pulse) {
		pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	}

	float radius = circle_radius * pulse;

	// Criar círculo com thickness
	float circle = smoothstep(radius - circle_thickness, radius - circle_thickness + 0.02, dist)
	             - smoothstep(radius, radius + 0.02, dist);

	// Aplicar cor e brilho
	vec3 color = circle_color.rgb * glow_intensity;

	// Adicionar pulso de brilho
	if (enable_pulse) {
		float brightness_pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
		color *= 1.0 + brightness_pulse * 0.5;
	}

	ALBEDO = color;
	EMISSION = color * 0.9;
	ALPHA = circle * circle_color.a;
}
