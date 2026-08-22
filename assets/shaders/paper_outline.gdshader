shader_type canvas_item;

// Thick comic-style outline: samples neighbouring texels and colours the
// silhouette ring with the outline colour while keeping the sprite interior.
uniform vec4 outline_color : source_color = vec4(0.1, 0.1, 0.15, 1.0);
uniform float outline_width = 2.0;
uniform float pixel_size = 0.002;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float silhouette = 0.0;
	vec2 step = vec2(pixel_size) * outline_width;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			silhouette = max(silhouette, texture(TEXTURE, UV + vec2(float(i), float(j)) * step).a);
		}
	}
	vec3 col = mix(outline_color.rgb, base.rgb, base.a);
	COLOR = vec4(col, silhouette);
}
