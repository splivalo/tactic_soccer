shader_type canvas_item;

// Dims a texture toward "unselected" while protecting bright/white pixels
// (pitch lines) from turning grey — a plain modulate multiply darkens
// everything equally, including white lines, which reads as muddy. Here the
// darkening amount scales down the closer a pixel already is to white.
uniform float dim_amount : hint_range(0.0, 1.0) = 0.0; // 0 = full brightness, 1 = max dim
// Horizontal flip done here (not via node scale) so mirroring stays correct
// no matter how the button is sized — used for the Away pitch half.
uniform bool flip_h = false;

void fragment() {
	vec2 uv = UV;
	if (flip_h) {
		uv.x = 1.0 - uv.x;
	}
	vec4 tex_color = texture(TEXTURE, uv);
	float luminance = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	float amount = dim_amount * (1.0 - luminance);
	COLOR = vec4(tex_color.rgb * (1.0 - amount), tex_color.a);
}
