// The lines of every model and prop: the mesh drawn again, pushed out along its normals and showing only its back
// faces (an "inverted hull"), so a line shows wherever a part meets what is behind it: its outline, and the outline
// of every part in front of another, as the line drawings had them. The line is the part's vertex color (one color
// per monster, the wall color for props), dimmed with distance, `ink_px` of the view's pixels wide near or far.
// It is the next_pass of fill.gdshader's material. A part whose vertex alpha is 0.5 gets no line (a wing's
// membrane: two-sided, its "back" would show whole), only its black.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, world_vertex_coords;

#include "res://src/view/line.gdshaderinc"

uniform float ink_px = 2.0;
uniform float view_h = 288.0;                    // the view's height in pixels (Stage3D.H)

varying vec3 world_pos;

void vertex() {
	// World units per view pixel at this distance: the view is 2 tan(fov / 2) d tall, view_h pixels
	float d = length(CAMERA_POSITION_WORLD - VERTEX);
	float per_px = 2.0 * d / (abs(PROJECTION_MATRIX[1][1]) * view_h); // (negative when rendering into a texture)
	VERTEX += normalize(NORMAL) * ink_px * per_px;
	if (abs(COLOR.a - 0.5) < 0.25) {
		VERTEX = vec3(0.0); // no line: every corner at one point, nothing to draw
	}
	world_pos = VERTEX;
}

void fragment() {
	ALBEDO = COLOR.rgb * line_fade(world_pos, CAMERA_POSITION_WORLD);
}
