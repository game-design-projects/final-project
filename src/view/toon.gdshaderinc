// The cel lighting every 3D surface of the view shares (toon.gdshader, stone.gdshader, ink.gdshader): light comes
// in flat bands with hard edges, the way a 2D painter would shade, so the 3D world reads as a drawing.
//
// Two lights, both worked out here rather than by the engine (the Compatibility renderer would draw the scene once
// more per light): the party's lantern, which sits at the camera, and up to MAX_TORCHES torches on the walls near
// you (Stage3D picks them every frame). Shadows lean toward `shade_tint` instead of going grey, and the dark falls
// off into `fog_color` with distance. Every color uniform is set by Stage3D, the same on every material.

#define MAX_TORCHES 10
#define EXPOSURE 0.86

uniform vec3 lantern_color : source_color = vec3(1.0, 0.93, 0.8);
uniform float lantern_reach = 17.0;          // world units: past this the lantern's light is gone
uniform vec3 lantern_offset = vec3(0.0);     // where the lantern hangs from the camera (Stage3D: up and to the left)
uniform vec3 torch_color : source_color = vec3(1.0, 0.7, 0.28);
uniform vec4 torches[MAX_TORCHES];           // xyz: a flame's position; w: its strength now (0 = no torch)
uniform float torch_reach = 2.6;
uniform vec3 shade_tint : source_color = vec3(0.42, 0.4, 0.62);
uniform vec3 fog_color : source_color = vec3(0.0);
uniform float fog_near = 4.0;
uniform float fog_far = 17.0;

// A soft step one screen pixel wide: hard edges that do not crawl
float cel_step(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return smoothstep(edge - w, edge + w, x);
}

// Light in three bands: shade, half-lit, lit
float cel_bands(float x) {
	return mix(mix(0.0, 0.55, cel_step(0.1, x)), 1.0, cel_step(0.42, x));
}

// Toward the lantern from world position `p` (the camera at `cam`)
vec3 lantern_dir(vec3 p, vec3 cam) {
	return normalize(cam + lantern_offset - p);
}

// The color of a surface with base color `base`, normal `n`, at world position `p`, seen from `cam`
vec3 cel_light(vec3 base, vec3 n, vec3 p, vec3 cam) {
	float dist = length(cam - p);
	vec3 l = lantern_dir(p, cam);
	// The lantern: brightest where a surface faces you, fading with distance
	float fall = clamp(1.0 - dist / lantern_reach, 0.0, 1.0);
	float lan = cel_bands(sqrt(max(dot(n, l), 0.0)) * fall * 1.25);
	// The torches: pools of warm light with a hard rim
	float tor = 0.0;
	for (int i = 0; i < MAX_TORCHES; i++) {
		vec4 t = torches[i];
		if (t.w <= 0.0) {
			continue;
		}
		vec3 d = t.xyz - p;
		float r = length(d);
		float k = clamp(1.0 - r / torch_reach, 0.0, 1.0);
		tor += k * k * (0.35 + 0.65 * max(dot(n, d / max(r, 1e-4)), 0.0)) * t.w;
	}
	float pool = mix(0.0, 0.5, cel_step(0.08, tor)) + 0.5 * cel_step(0.3, tor);
	vec3 shade = base * shade_tint * 0.55;
	vec3 col = mix(shade, base * lantern_color, lan);
	col = mix(col, max(col, base * torch_color * 1.25), pool);
	// Lit surfaces stop short of full white, so only what glows (flames, eyes of fire) reaches the bloom
	return col * EXPOSURE;
}

// Distance into the dark
vec3 cel_fog(vec3 col, vec3 p, vec3 cam) {
	return mix(col, fog_color, smoothstep(fog_near, fog_far, length(cam - p)));
}
