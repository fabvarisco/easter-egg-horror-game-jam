shader_type spatial;
render_mode cull_front, unshaded, blend_add;

uniform vec4 outline_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float outline_width = 1.0;
uniform float pulse_speed = 2.0;
uniform float pulse_amount = 0.3;
uniform float glow_intensity = 2.5;
uniform bool enable_pulse = true;

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);

	// Animação de pulso
	float pulse = 1.0;
	if (enable_pulse) {
		pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	}

	vec2 offset = normalize(clip_normal.xy) / VIEWPORT_SIZE * clip_position.w * outline_width * 2.0 * pulse;

	clip_position.xy += offset;

	POSITION = clip_position;
}

void fragment() {
	// Cor base com brilho
	vec3 color = outline_color.rgb * glow_intensity;

	// Adicionar pulso de brilho
	if (enable_pulse) {
		float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
		color *= 1.0 + pulse * 0.5;
	}

	ALBEDO = color;
	EMISSION = color * 0.8; // Adiciona emissão para brilhar mais

	if (outline_color.a < 1.0) {
		ALPHA = outline_color.a;
	}
}