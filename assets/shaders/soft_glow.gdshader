shader_type canvas_item;

// Soft rounded-rect glow: a true GPU-computed gradient falloff (not stacked
// flat layers, not StyleBoxFlat's hard-edged "shadow"). Drop this material on
// any ColorRect sized to roughly the area you want to glow — every parameter
// below shows up as an editable Shader Parameter in the Inspector.

uniform vec4 glow_color : source_color = vec4(0.97, 0.76, 0.15, 1.0);
uniform vec2 rect_size = vec2(740.0, 860.0); // match the node's actual size
uniform float corner_radius : hint_range(0.0, 300.0) = 60.0;
uniform float glow_softness : hint_range(1.0, 400.0) = 100.0; // fade distance, in px
uniform float max_alpha : hint_range(0.0, 1.0) = 0.4;

float rounded_box_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size;
	float half_extent = min(rect_size.x, rect_size.y) * 0.5;
	float r = min(corner_radius, half_extent);
	vec2 half_size = max(rect_size * 0.5 - glow_softness, vec2(0.0));
	float d = rounded_box_sdf(p, half_size, r);
	float alpha = 1.0 - smoothstep(-glow_softness, glow_softness, d);
	COLOR = vec4(glow_color.rgb, clamp(alpha, 0.0, 1.0) * max_alpha);
}
