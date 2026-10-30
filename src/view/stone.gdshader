// The dungeon's walls, floor and ceiling (Dungeon3D), painted rather than textured: flat stone in the floor's
// colors, the joints between blocks drawn as thin darker lines, every corner inked, and the cel light of
// toon.gdshaderinc over it. One material per kind (`kind`: 0 wall, 1 floor, 2 ceiling), the same mesh layout:
//   UV   0..1 across one cell's face (walls: u left to right as you face it, v from the top down)
//   UV2  walls: how dark the ink is on the face's left and right edge (1 at a corner, faint where the wall runs on);
//        floor and ceiling: the cell, for the stones' shading
//   COLOR.r a number of the face's own, so neighbouring blocks differ
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://src/view/toon.gdshaderinc"

uniform int kind = 0;
uniform vec3 stone_color : source_color = vec3(0.45, 0.55, 0.6);
uniform vec3 joint_color : source_color = vec3(0.2, 0.24, 0.28);
uniform vec3 ink_color : source_color = vec3(0.02, 0.02, 0.04);
uniform float ink_px = 1.6;                        // corner lines, in screen pixels
uniform float joint_px = 0.9;

varying vec3 world_pos;
varying vec3 world_normal;
// Flat: the stones' shading is hashed from these, and an interpolated value would come out a hair different on
// every pixel and turn each block into noise
varying flat float face_seed;
varying flat vec2 cell_id;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 on a line `px` screen pixels wide where `x` crosses a whole number
float grid_line(float x, float px) {
	float d = abs(fract(x + 0.5) - 0.5) / max(fwidth(x), 1e-5);
	return 1.0 - smoothstep(px * 0.5, px * 0.5 + 1.0, d);
}

// 1 within `px` screen pixels of the edge where `x` (0..1) is 0
float edge_line(float x, float px) {
	float d = x / max(fwidth(x), 1e-5);
	return 1.0 - smoothstep(px * 0.5, px * 0.5 + 1.0, d);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	face_seed = floor(COLOR.r * 997.0 + 0.5);
	cell_id = floor(UV2 + 0.5);
}

void fragment() {
	vec2 uv = UV;
	float seed = face_seed;
	vec3 base = stone_color;
	float joint = 0.0;
	float ink = 0.0;
	if (kind == 0) {
		// Four courses of blocks, every other course shifted half a block
		float rows = 4.0;
		float row = floor(uv.y * rows);
		float shift = mod(row, 2.0) * 0.5;
		float col_i = floor(uv.x * 2.0 + shift);
		base *= 0.9 + 0.2 * hash2(vec2(row + seed * 0.17, col_i + seed * 0.31));
		joint = max(grid_line(uv.y * rows, joint_px), grid_line(uv.x * 2.0 + shift, joint_px) * step(0.02, fract(uv.y * rows)) * step(fract(uv.y * rows), 0.98));
		// Darker at the foot of the wall and under the ceiling, as a painter would shade the corner
		base *= mix(1.0, 0.72, smoothstep(0.7, 1.0, uv.y)) * mix(0.8, 1.0, smoothstep(0.0, 0.18, uv.y));
		ink = max(max(edge_line(uv.y, ink_px), edge_line(1.0 - uv.y, ink_px)),
				max(edge_line(uv.x, ink_px) * UV2.x, edge_line(1.0 - uv.x, ink_px) * UV2.y));
	} else {
		// Flagstones, two by two to a cell
		vec2 tile = floor(uv * 2.0);
		base *= 0.85 + 0.25 * hash2(cell_id * 2.0 + tile + (kind == 2 ? 7.0 : 0.0));
		joint = max(grid_line(uv.x * 2.0, joint_px), grid_line(uv.y * 2.0, joint_px));
	}
	vec3 col = mix(base, joint_color, joint * 0.85);
	vec3 n = normalize(world_normal);
	col = cel_light(col, n, world_pos, CAMERA_POSITION_WORLD);
	col = mix(col, ink_color, ink);
	ALBEDO = cel_fog(col, world_pos, CAMERA_POSITION_WORLD);
}
