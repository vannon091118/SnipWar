shader_type canvas_item;
// Fog-of-war: softly fades an unexplored planet into the background nebula
// instead of hiding it hard. Applied only while a planet is in FogState.FOG.

// Dark nebula tone matching the starfield background.
uniform vec4 fog_color : source_color = vec4(0.05, 0.07, 0.13, 1.0);
// How strongly the fog hides the planet (1.0 = fully fogged).
uniform float fog_amount : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Soft radial falloff so the fogged planet melts into the nebula
	// without a hard circle edge.
	vec2 centered = UV - vec2(0.5);
	float edge = smoothstep(0.3, 0.5, length(centered));
	vec3 rgb = mix(tex.rgb, fog_color.rgb, fog_amount);
	float alpha = tex.a * (1.0 - fog_amount) * (1.0 - edge * 0.7);
	COLOR = vec4(rgb, alpha);
}
