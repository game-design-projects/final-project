// A drawn figure standing in the set (view/figure.gd): one frame of its atlas on a quad the stage turns to the camera. The atlas holds the
// line in its colour channel and the silhouette in alpha, so the inside of a body is black and hides what stands behind it, as a
// wireframe model's did. `tint` colours the line; it dims with distance like every line in the set, and thin lines gain as they
// shrink so one far down a corridor still reads. `flash` lights the whole silhouette for a hit.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D sheet : hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform vec4 cell = vec4(0.0, 0.0, 1.0, 1.0); // where the frame is in the atlas: offset, size
uniform vec2 sheet_px = vec2(1024.0);
uniform vec3 tint = vec3(1.0);
uniform float flash = 0.0;
uniform float fade_out = 0.0; // 1 is gone
uniform float cell_size = 2.0;
uniform float fade_floor = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = cell.xy + UV * cell.zw;
	vec4 t = texture(sheet, uv);
	float texels = max(fwidth(uv.x) * sheet_px.x, fwidth(uv.y) * sheet_px.y);
	float gain = 1.0 + clamp(log2(max(texels, 1.0)), 0.0, 4.0) * 0.85;
	float z = max(0.0, length(CAMERA_POSITION_WORLD - world_pos) / cell_size - 0.43);
	float fade = clamp(1.15 - z * 0.16, fade_floor, 1.0);
	vec3 line = t.rgb * gain;
	ALBEDO = mix(min(line, vec3(1.0)) * tint * fade, tint, clamp(flash, 0.0, 1.0));
	ALPHA = clamp(t.a * gain, 0.0, 1.0) * (1.0 - fade_out);
}
