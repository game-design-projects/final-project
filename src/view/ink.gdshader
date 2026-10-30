// The ink line around every model: the mesh drawn again, pushed out along its normals and showing only its back
// faces (an "inverted hull"), so a dark rim shows wherever the model meets what is behind it. It is the next_pass of
// toon.gdshader's material. The line is a deep shade of the part's own color rather than flat black, as in colored
// line art, and it keeps about the same thickness on screen near and far.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, world_vertex_coords;

#include "res://src/view/toon.gdshaderinc"

uniform float ink_width = 0.022;                   // world units at 3 units away
uniform vec3 ink_color : source_color = vec3(0.02, 0.015, 0.03);
uniform float ink_tint = 0.22;                     // how much of the part's color the line keeps

varying vec3 world_pos;

void vertex() {
	vec3 n = normalize(NORMAL);
	float d = length(CAMERA_POSITION_WORLD - VERTEX);
	// A model scaled down (three monsters at once) gets a thinner line, but not in proportion
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += n * ink_width * clamp(d / 3.0, 0.45, 2.5) * mix(1.0, s, 0.5);
	world_pos = VERTEX;
}

void fragment() {
	vec3 col = mix(ink_color, COLOR.rgb * 0.3, ink_tint);
	ALBEDO = cel_fog(col, world_pos, CAMERA_POSITION_WORLD);
}
