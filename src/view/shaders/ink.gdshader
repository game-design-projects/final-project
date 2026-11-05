// The lines of a model or prop: the mesh drawn again, pushed out along its normals, showing only its back faces (an
// "inverted hull"). A line shows wherever a part meets what is behind it: its own outline and the outline of every
// part in front of another. The line is the vertex colour, `ink_px` of the view's pixels wide at any distance.
// A part whose vertex alpha is 0.5 gets no line (a wing's membrane: two-sided, its "back" would show whole), nor one at 0.15
// (a line drawn solid at its own width).
// It is the next pass of solid.gdshader's material.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, world_vertex_coords;

uniform float ink_px = 2.0;
uniform float view_h = 288.0;                 // the view's height in pixels
uniform float cell = 2.0;
uniform float fade_floor = 0.15;

varying vec3 world_pos;

void vertex() {
	// world units per view pixel at this distance (the projection's y scale is negative into a texture)
	float d = length(CAMERA_POSITION_WORLD - VERTEX);
	float per_px = 2.0 * d / (abs(PROJECTION_MATRIX[1][1]) * view_h);
	VERTEX += normalize(NORMAL) * ink_px * per_px;
	if (abs(COLOR.a - 0.5) < 0.25 || abs(COLOR.a - 0.15) < 0.1) {
		VERTEX = vec3(0.0); // no line: every corner at one point, nothing to draw
	}
	world_pos = VERTEX;
}

void fragment() {
	float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell - 0.43);
	ALBEDO = COLOR.rgb * clamp(1.15 - z * 0.16, fade_floor, 1.0);
}
