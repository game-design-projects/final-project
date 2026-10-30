// The view's last pass (crawler/public/postfx.js, composite stage): put on the TextureRect that shows the
// 448x288 view. The bloom's strength and the scanlines are set per look by postfx.gd (LOOKS: the wireframe's
// "vector", or "cel" for the cel-shaded 3D view, which has no scanlines and glows only where things are lit up). Lines glow like phosphor on an old vector monitor (bloom from postfx_bloom.gdshader's texture),
// the pixels stay sharp instead of blurring when scaled up, rows show faint scanlines, the edges fall off into the
// dark, and the floor's accent color tints the shadows. Game state drives it through a few uniforms (see postfx.gd):
// a red pulse at the edges while the party is in danger (on the heartbeat), a red flash and a split of color when
// someone is hurt, a flash for a critical hit or a kill.
//
// The TextureRect needs texture_filter = LINEAR (PostFx.attach sets it): "sharp bilinear" reads the texture with
// hardware filtering, only inside the blend band at each source pixel's edge.
shader_type canvas_item;

uniform vec2 src_size = vec2(448.0, 288.0);   // the game's own canvas, in pixels
uniform vec2 out_size = vec2(0.0);            // this rect on screen, in physical pixels; 0 measures it per fragment
uniform vec2 bloom_size = vec2(112.0, 72.0);  // the bloom texture, in pixels
uniform sampler2D bloom_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 accent = vec3(1.0, 0.7, 0.28);   // the floor's accent color
uniform float fx_time = 0.0;
uniform float danger = 0.0;                   // 0..1, eased
uniform float pulse = 0.0;                    // 0..1, a heartbeat that decays
uniform float hurt_level = 0.0;               // 0..1, decays
uniform vec4 flash = vec4(0.0);               // rgb, strength
uniform float split = 0.35;                   // chromatic split, in source pixels
uniform float bloom_gain = 1.3;               // how strongly the glow adds (PostFx sets it per look)
uniform float scanlines = 0.07;               // how dark the gaps between the game's rows are (0: none)

// Sharp bilinear: nearest-neighbour pixels with only their edges blended, so a 448-wide canvas scaled to any
// size keeps crisp pixels without shimmering
vec2 sharp(vec2 uv, vec2 scale) {
	vec2 texel = uv * src_size;
	vec2 region = 0.5 - 0.5 / scale;
	vec2 d = fract(texel) - 0.5;
	vec2 f = (d - clamp(d, -region, region)) * scale + 0.5;
	return (floor(texel) + f) / src_size;
}

float rand_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 from_center = uv - 0.5;

	// Output pixels per source pixel: given, or measured from how fast the texture coordinate runs per screen pixel
	vec2 scale = out_size.x > 0.0 ? out_size / src_size : 1.0 / max(fwidth(uv * src_size), vec2(1e-5));
	scale = max(scale, vec2(1.0));

	// Hurt pulls the color channels apart toward the edges
	vec2 shift = from_center * (split / src_size.x) * 2.0;
	vec3 col;
	col.r = texture(TEXTURE, sharp(uv + shift, scale)).r;
	col.g = texture(TEXTURE, sharp(uv, scale)).g;
	col.b = texture(TEXTURE, sharp(uv - shift, scale)).b;

	// Phosphor glow: the bloom texture is already blurred across; blur it down here (9 taps in 5 reads), then warm
	// it a little toward the floor's accent
	vec2 dir = vec2(0.0, 1.0 / bloom_size.y);
	vec3 bloom = texture(bloom_tex, uv).rgb * 0.2270270270;
	bloom += texture(bloom_tex, uv + dir * 1.3846153846).rgb * 0.3162162162;
	bloom += texture(bloom_tex, uv - dir * 1.3846153846).rgb * 0.3162162162;
	bloom += texture(bloom_tex, uv + dir * 3.2307692308).rgb * 0.0702702703;
	bloom += texture(bloom_tex, uv - dir * 3.2307692308).rgb * 0.0702702703;
	col += bloom * mix(vec3(1.0), accent, 0.25) * bloom_gain;

	// Shadows lifted toward the accent: the dark is this floor's dark, not flat black
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col += accent * 0.025 * (1.0 - smoothstep(0.0, 0.35, luma));

	// Danger drains the color (red holds on longest) and closes in a pulsing red edge
	float edge = smoothstep(0.36, 0.8, length(from_center * vec2(1.2, 1.0)));
	col = mix(col, vec3(luma) * vec3(1.15, 0.85, 0.85), danger * 0.35);
	col += vec3(0.6, 0.03, 0.02) * edge * edge * danger * (0.3 + 0.7 * pulse);
	col += vec3(0.9, 0.08, 0.05) * edge * hurt_level * 0.8;

	// Scanlines on the game's own rows, and a soft vignette
	float row = -cos((uv.y * src_size.y) * 6.2831853); // dark between rows, bright through their middle
	col *= 1.0 - scanlines + scanlines * row;
	col *= mix(1.0, 0.68, smoothstep(0.4, 0.9, length(from_center * vec2(1.1, 1.25))));

	col += flash.rgb * flash.a;
	col += (rand_hash(FRAGCOORD.xy + fx_time) - 0.5) / 160.0; // dither: no banding in the dark gradients
	COLOR = vec4(col, 1.0);
}
