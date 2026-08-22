shader_type canvas_item;

// Subtle paper-grain noise + vignette. Applied on a full-screen ColorRect
// at the highest CanvasLayer to unify all visuals beneath it.

uniform float grain_strength : hint_range(0.0, 0.15) = 0.04;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_radius : hint_range(0.2, 1.0) = 0.65;
uniform float vignette_softness : hint_range(0.01, 0.5) = 0.25;

// Cheap hash-based noise — no texture needed.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Paper grain: high-frequency stipple that varies per pixel but is stable
	// across frames (no TIME uniform → deterministic, zero flicker).
	float grain = (hash(floor(UV * SCREEN_PIXEL_SIZE * 0.5)) - 0.5) * grain_strength;

	// Vignette: darkens toward the screen edges.
	vec2 center = UV - 0.5;
	float dist = length(center);
	float vig = smoothstep(vignette_radius, vignette_radius + vignette_softness, dist);
	float vignette_darken = vig * vignette_strength;

	// Combine: grain adds subtle texture, vignette darkens edges.
	// Use multiply so the grain modulates existing brightness.
	COLOR = vec4(vec3(1.0 - vignette_darken + grain), 0.0);
}
