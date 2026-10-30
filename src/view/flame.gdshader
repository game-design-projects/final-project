// Torch flames (Dungeon3D), drawn as the wireframe drew them: an outline of a flame in the floor's accent color, with
// a smaller tongue inside, on a quad that always faces you. Every vertex of a quad sits at the flame's foot; UV (-1..1
// across, 0..1 up) says which corner it is, and UV2.x gives each flame its own flicker. The glow round it is the
// walls' (line.gdshaderinc torch_glow); the bloom does the rest.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, world_vertex_coords;

uniform vec3 accent = vec3(1.0, 0.7, 0.28); // sRGB (line.gdshaderinc)
uniform vec2 flame_size = vec2(0.13, 0.36);
uniform float fps = 24.0;                        // render.gd FLAME_FPS
uniform float line_px = 1.5;

varying float seed;

void vertex() {
	seed = UV2.x;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	VERTEX += right * UV.x * flame_size.x + vec3(0.0, 1.0, 0.0) * UV.y * flame_size.y;
}

// How far inside a teardrop of `height` a point (x across, y up from its foot) is, in screen pixels (negative: out)
float inside_px(float x, float y, float height, float wide) {
	float v = y / height;
	float w = sqrt(max(0.0, v)) * (1.0 - v) * 1.9 * wide;
	float dx = (w - abs(x)) / max(fwidth(x), 1e-5);
	float dy = min(y, height - y) / max(fwidth(y), 1e-5);
	return min(dx, dy);
}

// 1 on the band `line_px` wide just inside an edge
float band(float v) {
	return smoothstep(-0.5, 0.5, v) * (1.0 - smoothstep(line_px - 0.5, line_px + 0.5, v));
}

void fragment() {
	float t = floor(TIME * fps) / fps + seed * 37.0;
	// The flame licks up to a point that sways (render.gd's flicker, by the same two sines)
	float f = sin(t * 11.1 + seed * 40.0) * 0.12 + sin(t * 27.0 + seed * 17.0) * 0.08;
	float x = UV.x - f * UV.y * UV.y * 2.0;
	float outer = inside_px(x, UV.y, 0.86 + f * 0.3, 1.0);
	float inner = inside_px(x, UV.y, 0.5, 0.4);
	float line = max(band(outer), band(inner));
	if (line < 0.05) {
		discard;
	}
	ALBEDO = accent * line;
}
