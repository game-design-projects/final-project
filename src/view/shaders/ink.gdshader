// The outline of a model: the mesh drawn again, pushed out along its normals, showing only its back faces (an
// "inverted hull"). A line shows wherever a part meets what is behind it: its own outline and the outline of every
// part in front of another. The line is `ink_px` of the view's pixels wide at any distance.
// It is the next pass of solid.gdshader's material.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, world_vertex_coords;

uniform vec3 tint = vec3(1.0, 0.54, 0.12);
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
	world_pos = VERTEX;
}

void fragment() {
	float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell - 0.43);
	ALBEDO = tint * clamp(1.15 - z * 0.16, fade_floor, 1.0);
}
