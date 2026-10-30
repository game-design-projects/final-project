// The bloom stage of the view's last pass (crawler/public/postfx.js): keep the bright parts at half size, blur them
// across, and write the result at quarter size (112x72 for the 448x288 view). Runs on a ColorRect inside the small
// SubViewport that PostFx.attach makes; postfx.gdshader blurs it down and adds it to the picture.
//
// The JS did this in two passes (bright -> half-size target, 9-tap gaussian across -> quarter-size target). Here the
// half-size image is never stored: a read of it is one bilinear read of the view (the average of 2x2 pixels) put
// through the soft knee, and the gaussian's taps read it at the same positions the JS did.
shader_type canvas_item;

uniform vec2 src_size = vec2(448.0, 288.0);
uniform sampler2D src_tex : hint_default_black, filter_linear, repeat_disable; // the view; PostFx sets it
uniform vec2 knee = vec2(0.12, 0.7); // what glows: from faint (x) to full (y) brightness; PostFx sets it per look

// The half-size image at the center of one of its pixels (`center` in source pixels, an odd whole number each way)
vec3 bright_px(sampler2D tex, vec2 center) {
	vec3 c = texture(tex, center / src_size).rgb;
	float l = max(c.r, max(c.g, c.b));
	float k = smoothstep(knee.x, knee.y, l); // keep what is bright, as a soft knee
	return c * k;
}

// The half-size image read with bilinear filtering at `q` (source pixels)
vec3 bright_lin(sampler2D tex, vec2 q) {
	vec2 a = q * 0.5 - 0.5;
	vec2 i0 = floor(a);
	vec2 t = a - i0;
	vec2 c = i0 * 2.0 + 1.0;
	vec3 top = mix(bright_px(tex, c), bright_px(tex, c + vec2(2.0, 0.0)), t.x);
	vec3 bot = mix(bright_px(tex, c + vec2(0.0, 2.0)), bright_px(tex, c + vec2(2.0, 2.0)), t.x);
	return mix(top, bot, t.y);
}

void fragment() {
	vec2 p = UV * src_size; // this pixel's center, in source pixels
	// 9-tap gaussian across, as 5 reads between texels; one half-size texel is 2 source pixels
	vec3 c = bright_lin(src_tex, p) * 0.2270270270;
	c += bright_lin(src_tex, p + vec2(1.3846153846 * 2.0, 0.0)) * 0.3162162162;
	c += bright_lin(src_tex, p - vec2(1.3846153846 * 2.0, 0.0)) * 0.3162162162;
	c += bright_lin(src_tex, p + vec2(3.2307692308 * 2.0, 0.0)) * 0.0702702703;
	c += bright_lin(src_tex, p - vec2(3.2307692308 * 2.0, 0.0)) * 0.0702702703;
	COLOR = vec4(c, 1.0);
}
