// Things drawn on the walls (view/wall_art.gd): flat quads, one mesh with one atlas, tinted by their vertex colour. UV2.x is how far along
// the atlas a quad's second drawing is (0: it has none), and it swaps to it now and then while you are near: a skull nods at you, a guilty
// crack looks back at you. UV2.y gives each its own moment.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform sampler2D sheet : hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform float cell_size = 2.0;
uniform float fade_floor = 0.15;
uniform float near = 6.0; // how close you must be for it to notice you

varying vec3 world_pos;
varying vec2 alt;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	alt = UV2;
}

void fragment() {
	float d = length(CAMERA_POSITION_WORLD - world_pos);
	float noticing = step(0.0, near - d) * step(0.55, sin(TIME * 1.1 + alt.y * 40.0));
	vec2 uv = UV + vec2(alt.x * noticing, 0.0);
	vec4 t = texture(sheet, uv);
	float z = max(0.0, d / cell_size - 0.43);
	float fade = clamp(1.15 - z * 0.16, fade_floor, 1.0);
	fade *= mix(0.42, 1.0, smoothstep(0.7, 1.7, d)); // right beside you a drawing is big and thick: it mustn't shout from the edge of the picture
	ALBEDO = t.rgb * COLOR.rgb * fade;
	ALPHA = t.a * COLOR.a;
}
