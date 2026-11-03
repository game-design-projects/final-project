// The dungeon: walls are black faces whose edges show as lines in the floor's wall colour, dimmer with distance, like
// torchlight that doesn't reach far. The floor and ceiling are only black; the walls' edges show where they meet.
// UV runs 0..1 across one cell's face, so the edge of the face is the line.
// Colours are written as they should look (no sRGB conversion), so a line fades the way a drawn line does over black.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform int kind = 0;                         // 0 wall, 1 floor / ceiling
uniform vec3 line_color = vec3(0.91, 0.89, 0.82);
uniform float line_px = 2.0;                  // line width near, in the view's pixels
uniform float cell = 2.0;                     // world units per cell
uniform float fade_floor = 0.15;              // the dimmest a line gets far away

varying vec3 world_pos;

// 1 within `px` screen pixels of the edge where x (0..1) is 0
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
		float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell - 0.43);
		float fade = clamp(1.15 - z * 0.16, fade_floor, 1.0);
		float px = fade > 0.67 ? line_px : line_px * 0.75;
		// a side edge is shared with the next face, which draws the other half; top and bottom are drawn whole
		float e = max(max(edge_line(UV.y, px), edge_line(1.0 - UV.y, px)), max(edge_line(UV.x, px * 0.5), edge_line(1.0 - UV.x, px * 0.5)));
		col = line_color * fade * e;
	}
	ALBEDO = col;
}
