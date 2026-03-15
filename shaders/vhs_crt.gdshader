shader_type canvas_item;

// VHS/CRT Effect Shader

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Effect intensities
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float chromatic_aberration : hint_range(0.0, 10.0) = 2.0;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_size : hint_range(0.0, 1.0) = 0.6;
uniform float screen_curvature : hint_range(0.0, 0.1) = 0.02;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.03;
uniform float vertical_jitter : hint_range(0.0, 0.01) = 0.002;
uniform float color_bleed : hint_range(0.0, 1.0) = 0.3;

// Random function
float random(vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Noise function
float noise(vec2 st) {
	vec2 i = floor(st);
	vec2 f = fract(st);
	float a = random(i);
	float b = random(i + vec2(1.0, 0.0));
	float c = random(i + vec2(0.0, 1.0));
	float d = random(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Screen curvature distortion
vec2 curve_uv(vec2 uv) {
	uv = uv * 2.0 - 1.0;
	vec2 offset = abs(uv.yx) * screen_curvature;
	uv = uv + uv * offset * offset;
	uv = uv * 0.5 + 0.5;
	return uv;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float time = TIME;

	// Apply screen curvature
	uv = curve_uv(uv);

	// Check if UV is out of bounds (black border from curvature)
	bool out_of_bounds = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;

	if (out_of_bounds) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
	// Vertical jitter (VHS tracking issues)
	float jitter = (random(vec2(time * 0.1, floor(uv.y * 100.0))) - 0.5) * vertical_jitter;
	uv.x += jitter;

	// Chromatic aberration (RGB separation)
	vec2 pixel_size = vec2(1.0) / vec2(textureSize(screen_texture, 0));
	float r = texture(screen_texture, uv + vec2(chromatic_aberration * pixel_size.x, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(chromatic_aberration * pixel_size.x, 0.0)).b;
	vec3 color = vec3(r, g, b);

	// Color bleed (horizontal blur/smear)
	if (color_bleed > 0.0) {
		vec3 bleed = vec3(0.0);
		for (int i = 1; i <= 3; i++) {
			float offset = float(i) * pixel_size.x * 2.0;
			bleed += texture(screen_texture, uv - vec2(offset, 0.0)).rgb;
		}
		bleed /= 3.0;
		color = mix(color, bleed, color_bleed * 0.3);
	}

	// Scanlines
	float scanline = sin(uv.y * 800.0) * 0.5 + 0.5;
	scanline = pow(scanline, 1.5);
	color *= 1.0 - (scanline * scanline_intensity);

	// Horizontal scanline bands (thicker lines)
	float thick_scanline = sin(uv.y * 200.0 + time * 2.0) * 0.5 + 0.5;
	color *= 1.0 - (thick_scanline * scanline_intensity * 0.3);

	// Static noise
	float static_noise = random(uv * vec2(time * 100.0, time * 100.0));
	color += (static_noise - 0.5) * noise_intensity;

	// Occasional noise lines (VHS artifacts)
	float noise_line = step(0.995, random(vec2(floor(uv.y * 50.0), time * 10.0)));
	color += noise_line * noise_intensity * 2.0;

	// Screen flicker
	float flicker = 1.0 + (random(vec2(time * 15.0, 0.0)) - 0.5) * flicker_intensity;
	color *= flicker;

	// Vignette
	vec2 vignette_uv = uv * (1.0 - uv.xy);
	float vignette = vignette_uv.x * vignette_uv.y * 15.0;
	vignette = pow(vignette, vignette_size);
	color *= mix(1.0 - vignette_intensity, 1.0, vignette);

	// Slight green/blue tint (old CRT look)
	color.r *= 0.95;
	color.g *= 1.0;
	color.b *= 1.02;

	// Clamp final color
	color = clamp(color, 0.0, 1.0);

	COLOR = vec4(color, 1.0);
	}
}
