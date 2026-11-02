// The inside of every model and prop (Monsters3D, Dungeon3D's decorations): black, so that what is behind it is
// hidden and only its lines (ink.gdshader, the next pass) show, the way the wireframe filled faces black before
// stroking them. A part whose vertex alpha is 0 is drawn solid in its vertex color instead, dimmed with distance:
// the dots, slits and cracks the line drawings filled in (pupils, a mouth, a crack of an eye, a crack in a wall).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://src/view/line.gdshaderinc"

uniform float flash = 0.0;                       // 0..1: a hit lights the monster up in its own color

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.a < 0.25 ? COLOR.rgb * line_fade(world_pos, CAMERA_POSITION_WORLD) : vec3(0.0); // (alpha is kept at 8 bits)
	ALBEDO = mix(col, COLOR.rgb, clamp(flash, 0.0, 1.0));
}
