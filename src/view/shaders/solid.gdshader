// The inside of a model or prop (built with mesh_kit.gd): black, so what is behind it is hidden and only its lines
// (ink.gdshader, the next pass) show. A part whose vertex alpha is 0 is drawn solid in its vertex colour instead, dimmed
// with distance (pupils, mouths, slits, a crack in a wall). `flash` lights everything up in its colour, for a hit.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform float flash = 0.0;
uniform float cell = 2.0;
uniform float fade_floor = 0.15;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell - 0.43);
	float fade = clamp(1.15 - z * 0.16, fade_floor, 1.0);
	vec3 col = COLOR.a < 0.25 ? COLOR.rgb * fade : vec3(0.0); // (alpha is kept at 8 bits)
	ALBEDO = mix(col, COLOR.rgb, clamp(flash, 0.0, 1.0));
}
