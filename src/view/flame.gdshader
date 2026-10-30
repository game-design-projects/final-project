// Torch flames (Dungeon3D): flat, two-tone flames drawn on quads that always face you, the way an animated
// film paints fire over a 3D set. Every vertex of a quad sits at the flame's foot; UV (-1..1 across, 0..1 up) says
// which corner it is, and UV2.x gives each flame its own flicker. Lit by nothing: they are the light (the bloom
// makes them glow). `accent` is the floor's accent color.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, world_vertex_coords;

uniform vec3 accent : source_color = vec3(1.0, 0.7, 0.28);
uniform vec3 core : source_color = vec3(1.0, 0.96, 0.82);
uniform vec2 flame_size = vec2(0.13, 0.36);
uniform float fps = 12.0;                          // flames move in steps, like drawn frames

varying float seed;

void vertex() {
	seed = UV2.x;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	VERTEX += right * UV.x * flame_size.x + vec3(0.0, 1.0, 0.0) * UV.y * flame_size.y;
}

void fragment() {
	float t = floor(TIME * fps) / fps + seed * 37.0;
	vec2 p = vec2(UV.x, UV.y); // x -1..1, y 0 (foot) .. 1 (tip)
	// A teardrop: wide at the foot, licking up to a point that sways
	float sway = sin(t * 9.0 + seed * 11.0) * 0.18 + sin(t * 23.0) * 0.07;
	float x = p.x - sway * p.y * p.y;
	float height = 0.82 + 0.18 * sin(t * 13.0 + seed * 5.0);
	float y = p.y / height;
	float width = sqrt(max(0.0, y)) * (1.0 - y) * 1.9;
	float outer = step(abs(x), width) * step(y, 1.0);
	float inner = step(abs(x), width * 0.5) * step(y, 0.62);
	if (outer < 0.5) {
		discard;
	}
	ALBEDO = mix(accent * 1.5, core * 1.6, inner);
}
