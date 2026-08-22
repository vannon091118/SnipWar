shader_type canvas_item;

// Colour quantisation to a fixed number of levels plus a deterministic
// halftone dot pattern in darker regions for the paper-comic look.
uniform int cell_shading_levels = 4;
uniform float halftone_density = 0.5;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float levels = float(max(cell_shading_levels, 2));
	vec3 quantized = floor(base.rgb * levels) / max(levels - 1.0, 1.0);
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float dots = step(0.5, fract(sin(dot(floor(UV * 48.0), vec2(12.9898, 78.233))) * 43758.5453));
	float shade = dots * (1.0 - lum) * halftone_density * 0.12;
	COLOR = vec4(quantized - shade, base.a);
}
