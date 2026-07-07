// LCD screen shader for the camcorder's flip-out screen.
// It takes the "camera feed" (rendered by a second camera into a SubViewport)
// and dirties it up with the VHS look, then shows it on the little screen.
// Because it is "unshaded" the screen stays bright even in a dark room,
// and EMISSION makes it glow slightly like a real LCD.

shader_type spatial;
render_mode unshaded, cull_disabled;

// The picture coming from the camcorder's recording camera.
uniform sampler2D feed_tex : source_color, filter_linear;

// VHS knobs (same idea as before, just on the small screen now).
uniform float aberration = 1.2;
uniform float scanline_strength = 0.10;
uniform float grain_strength = 0.08;
uniform float vignette_strength = 0.45;
uniform float screen_glow = 0.5;
uniform float brightness = 1.3;  // lifts the screen so it reads in a dark room
uniform float night_vision : hint_range(0.0, 1.0) = 0.22;  // subtle green camcorder tint

// If the picture comes out mirrored or upside down, flip these in the editor.
uniform bool flip_x = false;
uniform bool flip_y = false;

// 1 = screen switched on, 0 = dead black glass (camera lowered / battery empty).
// Set from camcorder.gd every frame.
uniform float screen_on : hint_range(0.0, 1.0) = 1.0;

float rand(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	if (flip_x) { uv.x = 1.0 - uv.x; }
	if (flip_y) { uv.y = 1.0 - uv.y; }

	// Colour splitting.
	vec2 off = vec2(aberration / 500.0, 0.0);
	float r = texture(feed_tex, uv + off).r;
	float g = texture(feed_tex, uv).g;
	float b = texture(feed_tex, uv - off).b;
	vec3 col = vec3(r, g, b);

	// Scanlines.
	float scan = sin(uv.y * 400.0) * 0.5 + 0.5;
	col -= scan * scanline_strength;

	// Grain.
	float grain = rand(uv + fract(TIME)) * grain_strength;
	col += grain - grain_strength * 0.5;

	// Vignette.
	float vig = distance(uv, vec2(0.5));
	col *= 1.0 - vig * vignette_strength;

	// Subtle night-vision: gently push the picture toward green and lift the
	// darks a touch, like a cheap camcorder's low-light mode. Kept mild.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 nv = vec3(lum * 0.45, lum * 1.05, lum * 0.45);
	col = mix(col, nv, night_vision);

	// Faint neutral backlight so the LCD always looks switched on, even when the
	// footage it is showing is almost black (dark room).
	col += vec3(0.022, 0.024, 0.022);
	col *= brightness;

	// Screen off = dead dark glass: the picture and the backlight both go.
	col = mix(vec3(0.004, 0.004, 0.005), col, screen_on);

	ALBEDO = col;
	EMISSION = col * screen_glow * screen_on;
}
