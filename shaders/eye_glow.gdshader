shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D flare_texture : source_color;
uniform vec4 eye_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float intensity : hint_range(1.0, 10.0) = 3.0;
uniform float pulse_speed : hint_range(0.0, 4.0) = 1.5;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.2;

void fragment() {
    vec4 tex = texture(flare_texture, UV);

    // Pulso sutil de intensidade
    float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;

    vec3 color = tex.rgb * eye_color.rgb * intensity * pulse;
    float alpha = tex.a * eye_color.a;

    ALBEDO = color;
    EMISSION = color;
    ALPHA = alpha;
}
