// Fullscreen VHS static for the jumpscare. Drawn OVER the 3D view while the
// monster screams in your face: crackling white noise, torn scan lines that
// rip sideways, all flickering. The noise is strongest at the screen edges
// so the screaming face in the middle stays readable.
// "intensity" is driven from entity.gd every frame (it flickers randomly).

shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.5;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Horizontal tearing: whole scan lines rip sideways at random.
	float line = floor(uv.y * 240.0);
	float tear = (rand(vec2(line, floor(TIME * 24.0))) - 0.5) * 0.1 * intensity;
	uv.x += tear;

	// The static itself: coarse white noise, re-rolled constantly.
	float n = rand(floor(uv * vec2(320.0, 240.0)) + vec2(fract(TIME) * 113.0));

	// More static at the edges, less in the middle (keeps the face visible).
	float edge = distance(UV, vec2(0.5)) * 1.7;
	float a = intensity * (0.22 + 0.78 * edge);

	// The whole sheet of static also blinks on and off very fast.
	a *= 0.45 + 0.55 * rand(vec2(floor(TIME * 30.0), 1.0));

	COLOR = vec4(vec3(n), a);
}
