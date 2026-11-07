// The last pass over the picture, like an old vector monitor: lines glow like phosphor (bloom from postfx_bloom.gdshader's
// texture), the pixels stay sharp instead of blurring when scaled up, rows show faint scanlines, the edges fall off into the
// dark, and the run's accent colour tints the shadows. Game state drives it (postfx.gd): a red pulse at the edges and drained
// colour in danger, a red edge and a split of the colours when you are hit, an added flash for a strike or a mercy.
//
// The TextureRect needs linear filtering (postfx.gd sets it): "sharp bilinear" reads the texture with hardware filtering,
// only inside the blend band at each source pixel's edge.
shader_type canvas_item;

uniform vec2 src_size = vec2(448.0, 288.0);   // the picture, in its own pixels
uniform vec2 out_size = vec2(0.0);            // this rect on screen, in physical pixels; 0 measures it per fragment
uniform vec2 bloom_size = vec2(112.0, 72.0);  // the bloom texture, in pixels
uniform sampler2D bloom_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 accent = vec3(1.0, 0.7, 0.28);
uniform float fx_time = 0.0;
uniform float danger : hint_range(0.0, 1.0) = 0.0;  // 0 safe .. 1 about to die
uniform float pulse = 0.0;                          // 0..1, a beat that decays
uniform float hurt_level = 0.0;                     // 1 right after a hit, decays
uniform vec4 flash = vec4(0.0);                     // rgb, strength
uniform float split = 0.35;                         // the colour split, in source pixels
uniform float warmth = 1.0;                         // how warm the halls are (rules/warmth.gd): the cold drains the colour toward a thin blue-grey

// Nearest-neighbour pixels with only their edges blended, so the picture scaled to any size keeps crisp pixels without
// shimmering
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

	// output pixels per source pixel: given, or measured from how fast the texture coordinate runs per screen pixel
	vec2 scale = out_size.x > 0.0 ? out_size / src_size : 1.0 / max(fwidth(uv * src_size), vec2(1e-5));
	scale = max(scale, vec2(1.0));

	// a hit pulls the colour channels apart toward the edges
	vec2 shift = from_center * (split / src_size.x) * 2.0;
	vec3 col;
	col.r = texture(TEXTURE, sharp(uv + shift, scale)).r;
	col.g = texture(TEXTURE, sharp(uv, scale)).g;
	col.b = texture(TEXTURE, sharp(uv - shift, scale)).b;

	// phosphor glow: the bloom texture is already blurred across; blur it down here (9 taps in 5 reads), warmed a little
	// toward the accent
	vec2 dir = vec2(0.0, 1.0 / bloom_size.y);
	vec3 bloom = texture(bloom_tex, uv).rgb * 0.2270270270;
	bloom += texture(bloom_tex, uv + dir * 1.3846153846).rgb * 0.3162162162;
	bloom += texture(bloom_tex, uv - dir * 1.3846153846).rgb * 0.3162162162;
	bloom += texture(bloom_tex, uv + dir * 3.2307692308).rgb * 0.0702702703;
	bloom += texture(bloom_tex, uv - dir * 3.2307692308).rgb * 0.0702702703;
	col += bloom * mix(vec3(1.0), accent, 0.25) * 1.3;

	// shadows lifted toward the accent: the dark is this run's dark, not flat black
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col += accent * 0.025 * (1.0 - smoothstep(0.0, 0.35, luma));

	// the halls going cold take the colour with them, a little at a time
	col = mix(vec3(luma) * vec3(0.9, 0.96, 1.08), col, mix(0.35, 1.0, smoothstep(0.0, 0.46, warmth)));

	// danger drains the colour (red holds on longest) and closes in a pulsing red edge
	float edge = smoothstep(0.36, 0.8, length(from_center * vec2(1.2, 1.0)));
	col = mix(col, vec3(luma) * vec3(1.15, 0.85, 0.85), danger * 0.35);
	col += vec3(0.6, 0.03, 0.02) * edge * edge * danger * (0.3 + 0.7 * pulse);
	col += vec3(0.9, 0.08, 0.05) * edge * hurt_level * 0.8;

	// scanlines on the picture's own rows, and a soft vignette
	float row = -cos((uv.y * src_size.y) * 6.2831853); // dark between rows, bright through their middle
	col *= 0.93 + 0.07 * row;
	col *= mix(1.0, 0.68, smoothstep(0.4, 0.9, length(from_center * vec2(1.1, 1.25))));

	col += flash.rgb * flash.a;
	col += (rand_hash(FRAGCOORD.xy + fx_time) - 0.5) / 160.0; // dither: no banding in the dark gradients
	COLOR = vec4(col, 1.0);
}
