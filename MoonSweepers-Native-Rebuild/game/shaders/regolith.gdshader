shader_type spatial;
render_mode cull_disabled;

// The recovered macro-detail image contains packed data, not RGB albedo.
uniform sampler2D detail_map : filter_linear_mipmap, repeat_enable;
uniform vec4 surface_tint : source_color = vec4(0.48, 0.48, 0.54, 1.0);
uniform float tile_scale = 1.0;

void fragment() {
	float grain = texture(detail_map, UV * tile_scale).r;
	ALBEDO = surface_tint.rgb * mix(0.80, 1.14, grain);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
