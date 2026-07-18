shader_type spatial;
render_mode unshaded, cull_front;

// Classic "inverted hull" outline: a second copy of the SAME skinned mesh,
// pushed outward along its own normals and drawn back-face-only, so only the
// silhouette rim peeks out from behind the real (front-face) mesh. Works with
// animation because VERTEX here is already the skinned/posed position — no
// separate re-skinning needed, it just rides along with whatever pose the
// real mesh is in this frame.
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width = 0.015;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
