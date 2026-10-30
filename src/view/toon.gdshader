// Cel shading for the monsters and the dungeon's props (Monsters3D, Dungeon3D). The color comes from the mesh's
// vertex colors (MeshKit bakes them, already linear); the lighting is toon.gdshaderinc's bands, plus a rim of light
// on the silhouette and, where UV2.x says so, a hard glossy highlight. A vertex alpha under 0.5 marks a part that
// glows (an eye, a crack of fire): it ignores the light and the fog, and the bloom picks it up.
// The ink outline is a second pass (ink.gdshader as next_pass).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://src/view/toon.gdshaderinc"

uniform float flash = 0.0;                         // 0..1: a hit lights the whole monster up
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float rim = 0.55;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 col;
	if (COLOR.a < 0.5) {
		col = base * 1.6; // glows: no light, no fog
	} else {
		vec3 n = normalize(world_normal);
		vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
		col = cel_light(base, n, world_pos, CAMERA_POSITION_WORLD);
		// A thin rim of light along the silhouette, the painter's back light
		float fres = 1.0 - max(dot(n, v), 0.0);
		col += base * lantern_color * rim * cel_step(0.72, fres) * 0.6;
		// A hard white highlight on glossy parts (a slime's dome), up and to the side the lantern hangs, where a
		// painter would put it
		vec3 h = normalize(v + lantern_dir(world_pos, CAMERA_POSITION_WORLD) + normalize(lantern_offset + vec3(0.0, 1e-3, 0.0)) * 1.6);
		col = mix(col, vec3(1.0), UV2.x * cel_step(0.985, max(dot(n, h), 0.0)));
		col = cel_fog(col, world_pos, CAMERA_POSITION_WORLD);
	}
	ALBEDO = mix(col, flash_color, clamp(flash, 0.0, 1.0));
}
