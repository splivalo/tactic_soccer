shader_type canvas_item;

// Chamfers the corners of a TextureButton/TextureRect's texture at render
// time (alpha mask) — used for the flag icons, so the source PNGs stay
// square. Uses an L1 (not Euclidean) distance so the cut is a flat diagonal
// bevel, matching the StyleBoxFlat corner_detail=1 look used on buttons —
// not a smooth round arc.
//
// Optionally paints a selection border along that SAME chamfer edge (set
// border_width > 0). Because the border and the corner cut share one signed
// distance field, the border is guaranteed to hug the flag edge perfectly —
// a separate StyleBox outline uses different corner math and never lines up.
uniform float radius : hint_range(0.0, 0.5) = 0.12;
uniform float edge_softness : hint_range(0.0, 0.02) = 0.004;
uniform float border_width : hint_range(0.0, 0.3) = 0.0;
uniform vec4 border_color : source_color = vec4(0.97, 0.76, 0.15, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	vec2 d = abs(uv) - (vec2(0.5) - radius);
	vec2 d_pos = max(d, 0.0);
	float dist = (d_pos.x + d_pos.y) + min(max(d.x, d.y), 0.0) - radius;
	float alpha = 1.0 - smoothstep(0.0, edge_softness, dist);

	vec4 tex = texture(TEXTURE, UV);
	// Border band = the outer strip of the shape, dist in [-border_width, 0].
	float border_mask = smoothstep(-border_width - edge_softness, -border_width + edge_softness, dist);
	border_mask *= step(0.0001, border_width);
	vec3 rgb = mix(tex.rgb, border_color.rgb, border_mask);
	COLOR = vec4(rgb, alpha);
}
