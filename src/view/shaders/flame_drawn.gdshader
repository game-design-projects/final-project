// A hand-drawn torch flame (view/wall_art.gd) on a quad that always faces you, with a face that answers how warm the halls are. Every vertex
// of a quad sits at the flame's foot; UV (-1..1 across, 0..1 up) says which corner it is and UV2.x gives each flame its own moment.
//   eyes 0: none; 1: looks at you, and leans toward you as you come near; 2: looks aside and leans away; 3: arcs, glad; 4: shut
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords;

uniform sampler2D sheet : hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform vec3 accent = vec3(1.0, 0.7, 0.28);
uniform vec2 flame_size = vec2(0.34, 0.58);
uniform vec2 grid = vec2(4.0, 2.0);   // frames across and down
uniform vec2 frame_uv = vec2(0.25, 0.5); // one frame's cell, as a share of the atlas
uniform vec2 pad_uv = vec2(0.0);      // what the atlas leaves before the first frame and between frames
uniform float fps = 11.0;
uniform int eyes = 0;

varying float seed;
varying vec2 corner;
varying float near_you;

void vertex() {
	seed = UV2.x;
	corner = UV;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	float side = (VIEW_MATRIX * vec4(VERTEX, 1.0)).x;
	float dist = length(CAMERA_POSITION_WORLD - VERTEX);
	near_you = 1.0 - smoothstep(1.2, 4.5, dist);
	float lean = 0.0;
	if (eyes == 1 || eyes == 3) {
		lean = -sign(side) * near_you * 0.34;
	} else if (eyes == 2) {
		lean = sign(side) * near_you * 0.3;
	}
	VERTEX += right * (UV.x * flame_size.x * 0.5 + lean * UV.y * UV.y * flame_size.x) + vec3(0.0, 1.0, 0.0) * UV.y * flame_size.y;
}

float pill(vec2 p, float half_h, float r) {
	p.y = abs(p.y) - half_h;
	return length(vec2(p.x, max(p.y, 0.0))) - r;
}

void fragment() {
	float f = floor(TIME * fps + seed * 97.0);
	float n = grid.x * grid.y;
	f = mod(f, n);
	vec2 at = vec2(mod(f, grid.x), floor(f / grid.x));
	vec2 local = vec2(corner.x * 0.5 + 0.5, 1.0 - corner.y);
	vec2 uv = pad_uv + at * (frame_uv + pad_uv) + local * frame_uv;
	vec4 t = texture(sheet, uv);
	vec3 col = accent * mix(0.82, 1.15, corner.y) * t.r;
	float dark = 0.0;
	if (eyes > 0) {
		// the eyes sit on the plain lower belly of the flame
		float px = max(fwidth(corner.y) * flame_size.y, fwidth(corner.x) * flame_size.x * 0.5);
		vec2 p = vec2(corner.x * flame_size.x * 0.5, corner.y * flame_size.y) - vec2(0.0, 0.16);
		float away = eyes == 2 ? (fract(seed * 7.0) < 0.5 ? 0.034 : -0.034) : 0.0;
		float blink = step(0.965, fract(TIME * 0.27 + seed * 13.0));
		float d = 1e3;
		for (int s = 0; s < 2; s++) {
			vec2 e = p - vec2((s == 0 ? -0.05 : 0.05) + away, 0.0);
			if (eyes == 3) {
				float ring = abs(length(e + vec2(0.0, 0.018)) - 0.032) - 0.01;
				d = min(d, e.y < -0.016 ? 1e3 : ring);
			} else if (eyes == 4 || blink > 0.5) {
				d = min(d, pill(e.yx, 0.022, 0.009));
			} else {
				d = min(d, pill(e, 0.03, 0.017));
			}
		}
		// too small to be eyes from far away: they go, rather than shimmer
		dark = (1.0 - smoothstep(-px * 0.5, px * 0.5, d)) * (1.0 - smoothstep(0.022, 0.036, px));
	}
	ALBEDO = mix(col, accent * 0.06, dark);
	ALPHA = t.a;
}
