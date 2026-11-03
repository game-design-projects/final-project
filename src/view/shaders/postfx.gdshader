// The last pass over the picture, like a vector monitor: a soft glow around the lines, faint scanlines, a darker
// edge, a red pulse at the edge when you are in danger, a split of the colours when you are hit, and a flash.
shader_type canvas_item;

uniform float danger : hint_range(0.0, 1.0) = 0.0;  // 0 safe .. 1 about to die
uniform float hurt : hint_range(0.0, 1.0) = 0.0;    // 1 right after a hit, fades to 0
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0); // rgb colour, a strength
uniform vec3 accent = vec3(1.0, 0.7, 0.28);         // tints the glow
uniform float pulse = 0.0;                          // 0..1, a beat

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(TEXTURE, 0));
	float split = hurt * 2.5;
	vec3 base = vec3(
		texture(TEXTURE, UV + vec2(split, 0.0) * px).r,
		texture(TEXTURE, UV).g,
		texture(TEXTURE, UV - vec2(split, 0.0) * px).b);
	// glow: the average of a ring of neighbours, added back
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		glow += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px * 2.0).rgb;
	}
	glow = glow / 8.0;
	vec3 col = base + glow * 0.55 * mix(vec3(1.0), accent, 0.35);
	// scanlines
	float scan = 0.88 + 0.12 * sin(UV.y * float(textureSize(TEXTURE, 0).y) * 3.14159);
	col *= scan;
	// darker edges, and the danger pulse in red
	vec2 d = UV - 0.5;
	float edge = clamp(dot(d, d) * 1.6, 0.0, 1.0);
	col *= 1.0 - edge * 0.55;
	col += vec3(0.9, 0.05, 0.05) * edge * danger * (0.35 + 0.35 * sin(TIME * 5.0 + pulse * 3.0));
	col = mix(col, flash.rgb, flash.a);
	COLOR = vec4(col, 1.0);
}
