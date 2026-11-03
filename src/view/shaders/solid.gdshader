// The inside of a model: black, so what is behind it is hidden and only its outline (ink.gdshader, the next pass)
// shows. A part with `flat_color` on is drawn solid in the tint instead (pupils, mouths, slits). `flash` lights the
// whole model up in its tint, for a hit.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 tint = vec3(1.0, 0.54, 0.12);
uniform bool flat_color = false;
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
	vec3 col = flat_color ? tint * fade : vec3(0.0);
	ALBEDO = mix(col, tint, clamp(flash, 0.0, 1.0));
}
