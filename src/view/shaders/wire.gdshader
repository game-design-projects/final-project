// The dungeon: walls are black faces whose edges show as lines in the floor's wall colour, dimmer with distance, like
// torchlight that doesn't reach far; the nearest torches glow on the walls round them in the accent colour. The floor and
// ceiling are only black; the walls' edges show where they meet.
// UV runs 0..1 across one cell's face, so the edge of the face is the line.
// Colours are written as they should look (no sRGB conversion), so a line fades the way a drawn line does over black.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform int kind = 0;                         // 0 wall, 1 floor / ceiling
uniform vec3 line_color = vec3(0.91, 0.89, 0.82);
uniform float line_px = 2.0;                  // line width near, in the view's pixels
uniform float cell = 2.0;                     // world units per cell
uniform float fade_floor = 0.15;              // the dimmest a line gets far away
uniform vec4 torches[10];                     // xyz: a flame; w: how bright it flickers now (0 = no torch). stage.gd sets them
uniform vec3 torch_color = vec3(1.0, 0.7, 0.28);
uniform float drawn = 0.0;                    // 0 the plain wire, 1 hand-drawn brick and flagstone joints (the feature hand-drawn)
uniform float warmth = 1.0;                   // how warm the halls are (rules/warmth.gd): the joints go as it falls, and at 0 only the wire is left

varying vec3 world_pos;

// 1 within `px` screen pixels of the edge where x (0..1) is 0
float edge_line(float x, float px) {
	float d = x / max(fwidth(x), 1e-5);
	return 1.0 - smoothstep(px - 0.5, px + 0.5, d);
}

// The torches' glow at `p`: the accent at a third at the flame, falling off to nothing a little over half a wall away
vec3 torch_glow(vec3 p) {
	float g = 0.0;
	for (int i = 0; i < 10; i++) {
		vec4 t = torches[i];
		if (t.w > 0.0) {
			g += 0.33 * clamp(1.0 - length(t.xyz - p) / 1.35, 0.0, 1.0) * t.w;
		}
	}
	return torch_color * min(g, 0.6);
}

float hash1(float n) {
	return fract(sin(n * 91.3458) * 47453.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A line `px` pixels wide along whole numbers of v; it fades out before its rows get close enough to shimmer
float joint(float v, float px) {
	float w = max(fwidth(v), 1e-5);
	float d = min(fract(v), 1.0 - fract(v)) / w;
	return (1.0 - smoothstep(px - 0.5, px + 0.5, d)) * (1.0 - smoothstep(0.1, 0.3, w));
}

// Courses of stone in running bond, drawn by a slightly unsteady hand: a course (along y) has its own offset, a stone its own length,
// and now and then a joint is left out. `p` is in stones.
float masonry(vec2 p, float px, float seed) {
	vec2 q = p + vec2(sin(p.y * 2.3 + seed) * 0.018, sin(p.x * 1.7 + seed) * 0.03 + sin(p.x * 5.1) * 0.008);
	float course = floor(q.y);
	float along = q.x + 0.5 * mod(course, 2.0) + hash1(course + seed) * 0.24;
	float stone = floor(along);
	float bed = joint(q.y, px) * step(0.14, hash2(vec2(floor(q.x * 1.5), course + seed)));
	float nudged = along + (hash2(vec2(stone, course)) - 0.5) * 0.3;
	float upright = joint(nudged, px) * step(0.2, hash2(vec2(floor(nudged + 0.5), course + seed + 3.0)));
	return max(bed, upright);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = vec3(0.0);
	if (kind == 0) {
		float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell - 0.43);
		float fade = clamp(1.15 - z * 0.16, fade_floor, 1.0);
		float px = fade > 0.67 ? line_px : line_px * 0.75;
		// a side edge is shared with the next face, which draws the other half; top and bottom are drawn whole
		float seam = max(edge_line(UV.x, px * 0.5), edge_line(1.0 - UV.x, px * 0.5));
		vec3 glow = torch_glow(world_pos);
		float stones = 0.0;
		if (drawn > 0.5) {
			float drawn_in = smoothstep(0.02, 0.32, warmth);
			stones = masonry(vec2((world_pos.x + world_pos.z) / 1.0, world_pos.y / 0.4251), px * 0.5, 0.0) * drawn_in * (1.0 - smoothstep(3.0, 7.0, z));
			glow += line_color * 0.018 * warmth * fade; // the stone itself holds a little light
			seam *= mix(1.0, 0.6, drawn_in); // among the stones a cell's edge needn't shout
		}
		float e = max(max(edge_line(UV.y, px), edge_line(1.0 - UV.y, px)), seam);
		col = mix(mix(glow, line_color * fade, stones * 0.5), line_color * fade, e);
	} else if (drawn > 0.5) {
		bool below = world_pos.y < 0.5;
		float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell - 0.43);
		float fade = clamp(1.15 - z * 0.16, fade_floor, 1.0);
		float flags = masonry(world_pos.xz * vec2(0.92, 1.15) + (below ? vec2(0.0) : vec2(0.37, 0.61)), 0.9, below ? 7.0 : 13.0) * smoothstep(0.02, 0.32, warmth) * (1.0 - smoothstep(1.6, 5.0, z));
		col = mix(torch_glow(world_pos) * 0.45, line_color * fade, flags * (below ? 0.36 : 0.22));
	}
	ALBEDO = col;
}
