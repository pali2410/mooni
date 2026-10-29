shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D eye_sheet : filter_linear, repeat_disable;
uniform vec4 eye_color : source_color = vec4(0.55, 0.93, 1.0, 1.0);

void fragment() {
	// Source _EyeStyle 0: the top-left cell of the original four-by-four sheet.
	float mask = texture(eye_sheet, UV * 0.25).r;
	if (mask < 0.015) discard;
	ALBEDO = eye_color.rgb;
	ALPHA = mask;
}
