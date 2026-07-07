// Full-screen "retro" post effect for the whole game view.
// It sits on an invisible quad glued to the main camera and repaints
// every pixel: distance fog, animated noise in the fog, crushed colour
// count (PSX look) and a dither pattern to hide the colour banding.
// Only the MAIN camera sees it (the quad is on render layer 2, which the
// camcorder's feed camera culls) — the LCD keeps its own VHS shader.

shader_type spatial;
render_mode cull_disabled, unshaded;

// Pictures Godot hands us for free: how far away each pixel is, and the
// screen image rendered so far.
uniform sampler2D depth_texture : source_color, hint_depth_texture;
uniform sampler2D screen_texture : source_color, hint_screen_texture, repeat_disable, filter_nearest;

// Fog: far pixels fade into fog_color.
uniform bool enable_fog = true;
uniform vec3 fog_color : source_color;
uniform vec3 noise_color : source_color;
uniform float fog_distance : hint_range(1, 6000) = 100;
uniform float fog_fade_range : hint_range(1, 6000) = 50;

// Noise: the fog crawls with TV-static made from fog_color + noise_color.
uniform bool enable_noise = true;
uniform float noise_time_fac : hint_range(0.1, 10) = 4;

// Colour limit: fewer colour steps = old-console look.
uniform bool enable_color_limitation = true;
uniform int color_levels : hint_range(2, 256) = 32;

// Dither: checker-ish pattern that softens the colour banding.
uniform bool enable_dithering = true;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

// Simple brightness lift so the retro pass doesn't swallow the dark scene.
uniform float brightness : hint_range(0.5, 2.0) = 1.0;

float hashOld12(vec2 p){
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453 + (sin((TIME)) / noise_time_fac)) ;
}
vec3 color_mix(vec3 a, vec3 b, float f ){
	f = clamp(abs(f), 0,1);
	float invf = 1.0 - f;
	return (a*f) + (b*invf);
}
vec3 quantize_color(vec3 color, int levels) {
    float quantizer = float(levels - 1);
    return floor(color * quantizer + 0.5) / quantizer;
}
// 4x4 Bayer pattern: gives every pixel on screen a fixed value 0..1
// in a tiny repeating grid. Used to nudge colours before rounding.
float dither_threshold(vec2 position) {
    int x = int(mod(position.x, 4.0));
    int y = int(mod(position.y, 4.0));
    int index = x + y * 4;
    float dithering[16] = float[](
        0.0, 0.5, 0.125, 0.625,
        0.75, 0.25, 0.875, 0.375,
        0.1875, 0.6875, 0.0625, 0.5625,
        0.9375, 0.4375, 1.0, 0.8125
    );
    return dithering[index];
}
void vertex() {
	// Stretch the quad over the entire screen, no matter where it sits.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment(){
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	vec2 screen_coords = SCREEN_UV * 2.0 - 1.0;
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(screen_coords, depth);

	// Turn the depth value into "metres from the camera".
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;

	float linear_depth = -view.z;

	// 1 = close (no fog), 0 = far (full fog).
	float depth_mask_inv = clamp((linear_depth - (fog_distance - fog_fade_range)) / fog_fade_range, 0.0, 1.0);

	vec3 final_color = screen_color;

	if (enable_noise){
		vec3 twocolornoise = color_mix(fog_color, noise_color, hashOld12(screen_coords));
		final_color = color_mix(twocolornoise, final_color, depth_mask_inv);
	}
	if (enable_fog){
		final_color = color_mix(fog_color, final_color, depth_mask_inv);
	}
	// --- PS1 colour crush, done the old-school way ---
	// Godot gives us colours in LINEAR space, where dark pixels are tiny
	// numbers — rounding them there crushes everything to black (deep-fried).
	// So we hop into gamma space (what your eyes/screen see) first, dither,
	// THEN round, then hop back.
	vec3 gamma_color = pow(max(final_color, vec3(0.0)), vec3(1.0 / 2.2));

	gamma_color *= brightness;

	if (enable_dithering){
		// Nudge each pixel up/down by up to one colour step before rounding.
		// The rounding then flips neighbouring pixels differently — that's
		// the classic PS1 dither pattern instead of ugly banding.
		float step_size = 1.0 / float(color_levels - 1);
		gamma_color += (dither_threshold(FRAGCOORD.xy) - 0.5) * step_size * dither_strength;
	}
	if (enable_color_limitation){
		gamma_color = quantize_color(gamma_color, color_levels);
	}

	// Back to linear space, which is what ALBEDO expects.
	final_color = pow(max(gamma_color, vec3(0.0)), vec3(2.2));
	ALBEDO = final_color;
}
