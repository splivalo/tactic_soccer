shader_type spatial;
// Emissive-white net (matches the original look) that BULGES near a hit point,
// so a scored ball visibly pushes the netting out and it springs back.
render_mode cull_disabled, unshaded;

uniform vec3 hit_point;                       // world-space impact point
uniform float hit_strength = 0.0;             // animated 0 -> peak -> 0
uniform float hit_radius = 0.7;               // world units of affected netting
uniform vec3 push_dir = vec3(0.0, 0.0, -1.0); // where the ball shoves the net
uniform vec4 net_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float infl = smoothstep(hit_radius, 0.0, distance(world, hit_point)) * hit_strength;
	// Net has no rotation/scale, so a world-space push maps straight to local.
	VERTEX += normalize(push_dir) * infl;
}

void fragment() {
	ALBEDO = net_color.rgb;
}
