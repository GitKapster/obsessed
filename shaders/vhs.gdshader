// VHS / found-footage post-process effect.
// This runs on a full-screen ColorRect that sits on top of everything.
// It grabs whatever the camera already drew (the "screen texture")
// and dirties it up to look like an old camcorder tape.

shader_type canvas_item;

// Grab the image the game already rendered this frame.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Knobs you can tweak in the editor to make the effect stronger/weaker.
uniform float aberration = 1.5;        // colour splitting at the edges
uniform float scanline_strength = 0.12; // dark horizontal TV lines
uniform float grain_strength = 0.09;    // moving film noise
uniform float vignette_strength = 0.5;  // dark corners
uniform float opacity : hint_range(0.0, 1.0) = 1.0; // how strongly the effect is applied (used to fade in/out)

// Cheap random number from a screen position. Used for the grain.
float rand(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// 1. Chromatic aberration: pull the red and blue channels apart a little.
	vec2 offset = vec2(aberration / 1000.0, 0.0);
	float r = texture(screen_tex, uv + offset).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - offset).b;
	vec3 col = vec3(r, g, b);

	// 2. Scanlines: subtract a thin dark line pattern based on screen height.
	float scan = sin(uv.y * 800.0) * 0.5 + 0.5;
	col -= scan * scanline_strength;

	// 3. Grain: add animated noise so it shimmers like tape.
	float grain = rand(uv + fract(TIME)) * grain_strength;
	col += grain - grain_strength * 0.5;

	// 4. Vignette: darken the corners based on distance from the centre.
	float vig = distance(uv, vec2(0.5));
	col *= 1.0 - vig * vignette_strength;

	// Fade the whole effect in/out. At opacity 0 the overlay is invisible
	// and you see the clean world; at 1 you see the full VHS feed.
	COLOR = vec4(col, opacity);
}
