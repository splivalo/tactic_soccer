shader_type canvas_item;

// Fills a shield mask's silhouette (this TextureRect's own alpha, from the
// shield outline PNG assigned as its `texture`) with an external flag image
// instead of a flat modulate colour — see hud.gd's set_team(). Flags are
// landscape while the shield is portrait, so a raw 1:1 UV map would stretch
// them; crop-to-cover instead (centered), so the flag keeps its own
// proportions and just loses its edges instead of getting squashed.
uniform sampler2D flag_texture : source_color, filter_linear;
const float SHIELD_ASPECT = 96.0 / 112.0; // ShieldWrap size, same across all shield instances

void fragment() {
	vec4 mask = texture(TEXTURE, UV);

	vec2 flag_size = vec2(textureSize(flag_texture, 0));
	float flag_aspect = flag_size.x / flag_size.y;
	vec2 uv = UV;
	if (flag_aspect > SHIELD_ASPECT) {
		float scale = SHIELD_ASPECT / flag_aspect;
		uv.x = (uv.x - 0.5) * scale + 0.5;
	} else {
		float scale = flag_aspect / SHIELD_ASPECT;
		uv.y = (uv.y - 0.5) * scale + 0.5;
	}

	vec4 flag = texture(flag_texture, uv);
	COLOR = vec4(flag.rgb, flag.a * mask.a);
}
