// The dungeon's walls, floor and ceiling (Dungeon3D), drawn the way the wireframe drew them: black faces, every
// wall face outlined in the floor's wall color, dimmer with distance, 2 pixels wide near and 1.5 from three cells
// on, with the torches' glow on the walls around them. The floor and the ceiling are only black: the walls' edges
// draw where they meet. `kind`: 0 wall, 1 floor, 2 ceiling. UV runs 0..1 across one cell's face.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://src/view/line.gdshaderinc"

uniform int kind = 0;
uniform vec3 line_color = vec3(0.91, 0.89, 0.82); // sRGB (line.gdshaderinc)
uniform float line_px = 2.0;                     // near lines, in the view's pixels

varying vec3 world_pos;

// 1 within `px` screen pixels of the edge where `x` (0..1) is 0
float edge_line(float x, float px) {
	float d = x / max(fwidth(x), 1e-5);
	return 1.0 - smoothstep(px - 0.5, px + 0.5, d);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = vec3(0.0);
	if (kind == 0) {
		float fade = line_fade(world_pos, CAMERA_POSITION_WORLD);
		float px = fade > 0.67 ? line_px : line_px * 0.75; // 0.67 = 1.15 - 3 * 0.16: three cells away
		// A side edge is always shared with the next face (the wall running on, or turning a corner), which draws the
		// other half of the line; the top and bottom meet the black floor and ceiling, so they draw it whole
		float e = max(max(edge_line(UV.y, px), edge_line(1.0 - UV.y, px)), max(edge_line(UV.x, px * 0.5), edge_line(1.0 - UV.x, px * 0.5)));
		col = mix(torch_glow(world_pos), line_color * fade, e);
	}
	ALBEDO = col;
}
