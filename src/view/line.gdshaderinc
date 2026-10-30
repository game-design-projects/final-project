// What every 3D surface of the view shares: the wireframe's look, rendered from real geometry. Every surface is
// black; what shows is lines, in one color (each floor's wall color, each monster's own), and they dim with distance
// the way render.gd's _fog dimmed them ("torchlight that doesn't reach far"). Torches glow on the walls around them
// in the floor's accent, as render.gd's radial gradient did. Stage3D sets the uniforms, the same on every material.
//
// Colors are sRGB, uniforms included (no source_color hint): the Compatibility renderer shows what the shaders write
// as it is, so a line fades as the wireframe's did when drawn with an alpha over black.

#define MAX_TORCHES 10

uniform vec4 torches[MAX_TORCHES];               // xyz: a flame; w: how bright it flickers now (0 = no torch)
uniform vec3 torch_color = vec3(1.0, 0.7, 0.28);
uniform float cell = 2.0;                        // world units per cell (Dungeon3D.CELL)
uniform float eye_back = 0.43;                   // how far behind your cell's near edge the camera is, in cells

// How bright a line is at world position `p` seen from `cam`: render.gd's _fog, by the cells between the near edge
// of your cell and the point
float line_fade(vec3 p, vec3 cam) {
	float z = max(0.0, length(cam - p) / cell - eye_back);
	return clamp(1.15 - z * 0.16, 0.15, 1.0);
}

// The torches' glow at `p`: the accent at a third at the flame, falling off to nothing a little over half a wall away
vec3 torch_glow(vec3 p) {
	float g = 0.0;
	for (int i = 0; i < MAX_TORCHES; i++) {
		vec4 t = torches[i];
		if (t.w > 0.0) {
			g += 0.33 * clamp(1.0 - length(t.xyz - p) / 1.35, 0.0, 1.0) * t.w;
		}
	}
	return torch_color * min(g, 0.6);
}
