// CCTV look for the main menu background.
// Takes a plain screenshot and makes it look like old security footage:
// washed-out grey-green, scanlines, grain, a rolling bright bar, and a
// vignette. static_amount is turned up by the menu script for a burst
// of pure static while the "cameras" switch.

shader_type canvas_item;

// 0 = normal picture, 1 = pure static (used during camera switches).
uniform float static_amount : hint_range(0.0, 1.0) = 0.0;
// How strongly the picture is pushed toward the CCTV grey-green.
uniform float tint_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec3 tint_color : source_color = vec3(0.62, 0.75, 0.66);

// Cheap "random number from a position" - standard shader trick.
float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Each scan row wobbles left/right a tiny bit, like a bad signal.
	float row = floor(uv.y * 360.0);
	uv.x += (rand(vec2(row, floor(TIME * 15.0))) - 0.5) * 0.002;

	vec3 col = texture(TEXTURE, uv).rgb;

	// Turn the colour into a washed grey-green with crushed contrast.
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	grey = clamp((grey - 0.5) * 1.3 + 0.52, 0.0, 1.0);
	col = mix(col, grey * tint_color, tint_strength);

	// Scanlines.
	col *= 0.82 + 0.18 * sin(uv.y * 700.0);

	// A faint bright bar slowly rolling down the screen.
	float bar = fract(uv.y - TIME * 0.05);
	col += 0.04 * smoothstep(0.0, 0.15, bar) * smoothstep(0.3, 0.15, bar);

	// Grain, refreshed every frame.
	float n = rand(uv * vec2(640.0, 360.0) + vec2(TIME * 61.0, TIME * 83.0));
	col += (n - 0.5) * 0.1;

	// The static burst: blends the picture away into pure noise.
	col = mix(col, vec3(n), static_amount);

	// Darker toward the corners so the menu text stays readable.
	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * 1.3;

	COLOR = vec4(col, 1.0);
}
