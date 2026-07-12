class_name BoardFx
extends Node3D

## On-pitch feedback effects, all procedural (no external assets):
##  - glow TILE on a cell (soft rounded square, pulsing) — used for both
##    target cells (move/shoot) AND tappable/selected figures, same shape,
##    just different colour, so all feedback reads as one visual language.
##  - energy TRAIL: a flowing dash/dot ribbon through the pass chain, driven by
##    a small shader (not a scrolling texture) so the flow speed is exact and
##    doesn't depend on the runtime texture's wrap mode.
## main.gd calls clear() then add_tile()/set_trail() with WORLD points.
##
## Tuning: these are @export so you can select this node in the Remote scene
## tree while the game is running (Scene dock -> Remote tab, after pressing
## Play) and drag values live to preview. Bake final numbers back here once
## you're happy — Remote edits don't persist after you stop the game.

@export var tile_size := 0.92
@export var pulse_hz := 1.4

@export_group("Trail")
@export var trail_width := 0.16
@export var trail_scroll := 1.6      # flow speed (world units/sec)
@export var dash_period := 0.5       # metres per pattern cycle
@export_range(1.0, 12.0, 0.5) var trail_density := 4.0   # dashes/dots per period
@export_range(0.05, 1.0, 0.01) var trail_fill := 0.55    # how much of each cell is solid
@export_enum("Dash", "Dot") var trail_pattern := 0
@export_range(0.0, 3.0, 0.01) var trail_emission := 0.0  # additive glow brightness
@export_range(0.0, 1.0, 0.01) var trail_rim := 0.6       # brightening near the ribbon's edges

const TILE_Y := 0.03      # height above the pitch surface
const TRAIL_Y := 0.06

var _tile_tex: Texture2D
var _trail_shader: Shader
var _pulse_mats: Array[StandardMaterial3D] = []
var _pulse_base: Array[float] = []
var _trail_mat: ShaderMaterial = null
var _t := 0.0


func _ready() -> void:
	_tile_tex = _make_tile_tex()
	_trail_shader = _make_trail_shader()


func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.6 + 0.4 * sin(_t * TAU * pulse_hz)
	for i in _pulse_mats.size():
		var m := _pulse_mats[i]
		m.albedo_color.a = _pulse_base[i] * pulse
	if _trail_mat != null:
		_trail_mat.set_shader_parameter("time_offset", _t)


func clear() -> void:
	for child in get_children():
		child.queue_free()
	_pulse_mats.clear()
	_pulse_base.clear()
	_trail_mat = null


## Glow tile centred on a cell (world pos = pitch-surface point at the cell).
## Pass `size < 0` (default) to use the exported `tile_size`.
func add_tile(pos: Vector3, color: Color, size := -1.0) -> void:
	var s: float = tile_size if size < 0.0 else size
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(s, s)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := _flat(color, _tile_tex)
	mi.material_override = mat
	mi.position = pos + Vector3(0, TILE_Y, 0)
	add_child(mi)
	_register_pulse(mat, color.a)


## Flowing energy ribbon along a polyline of world points (ball -> chain figures).
func set_trail(points: PackedVector3Array, color: Color) -> void:
	if points.size() < 2:
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var vi := 0
	var acc := 0.0
	for s in points.size() - 1:
		var a := points[s] + Vector3(0, TRAIL_Y, 0)
		var b := points[s + 1] + Vector3(0, TRAIL_Y, 0)
		var dir := b - a
		dir.y = 0.0
		var seg_len := dir.length()
		if seg_len < 0.001:
			continue
		var perp := Vector3(-dir.z, 0.0, dir.x).normalized() * trail_width * 0.5
		verts.append_array([a + perp, a - perp, b + perp, b - perp])
		var u0 := acc
		var u1 := acc + seg_len
		uvs.append_array([Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1)])
		idx.append_array([vi, vi + 2, vi + 1, vi + 1, vi + 2, vi + 3])
		vi += 4
		acc += seg_len

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = _trail_shader
	_trail_mat.set_shader_parameter("base_color", color)
	_trail_mat.set_shader_parameter("time_offset", _t)
	_trail_mat.set_shader_parameter("scroll_speed", trail_scroll)
	_trail_mat.set_shader_parameter("dash_period", maxf(dash_period, 0.001))
	_trail_mat.set_shader_parameter("density", trail_density)
	_trail_mat.set_shader_parameter("width_m", trail_width)
	_trail_mat.set_shader_parameter("fill", trail_fill)
	_trail_mat.set_shader_parameter("pattern_mode", trail_pattern)
	_trail_mat.set_shader_parameter("emission_strength", trail_emission)
	_trail_mat.set_shader_parameter("rim_strength", trail_rim)
	mi.material_override = _trail_mat
	add_child(mi)


# --- internals ---------------------------------------------------------------
func _register_pulse(mat: StandardMaterial3D, base_alpha: float) -> void:
	_pulse_mats.append(mat)
	_pulse_base.append(base_alpha)


func _flat(color: Color, tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	return m


func _make_tile_tex() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var u := (float(x) + 0.5) / s * 2.0 - 1.0
			var v := (float(y) + 0.5) / s * 2.0 - 1.0
			# rounded-square distance (p=4 superellipse)
			var d := pow(pow(absf(u), 4.0) + pow(absf(v), 4.0), 0.25)
			var fill := 1.0 - smoothstep(0.72, 1.0, d)
			var border := smoothstep(0.6, 0.8, d) * (1.0 - smoothstep(0.82, 0.98, d))
			var a := clampf(fill * 0.45 + border, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# Computes the flowing dash/dot pattern live from `time_offset`, instead of
# scrolling a texture's UV — guarantees the flow speed is exact regardless of
# the runtime texture's wrap/repeat setting.
func _make_trail_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float time_offset = 0.0;
uniform float scroll_speed = 1.6;
uniform float dash_period = 0.5;
uniform float density = 4.0;
uniform float fill = 0.55;
uniform float width_m = 0.16;     // ribbon width in metres (for round dots)
uniform int pattern_mode = 0; // 0 = dash, 1 = dot
uniform float emission_strength = 0.0;
uniform float rim_strength = 0.6;

void fragment() {
	float along = (UV.x / dash_period - time_offset * scroll_speed) * density;
	float cell = fract(along);
	float across = UV.y * 2.0 - 1.0; // -1..1 across the ribbon width
	float edge_soft = 0.12;
	float alpha;
	if (pattern_mode == 0) {
		// dash: solid rectangle along the path, soft leading/trailing edges
		float a = smoothstep(0.0, edge_soft, cell) * (1.0 - smoothstep(fill, fill + edge_soft, cell));
		float w = 1.0 - smoothstep(0.85, 1.0, abs(across));
		alpha = a * w;
	} else {
		// dot: measure both axes in real metres so it's a true circle,
		// regardless of how density/width are tuned relative to each other.
		float cell_len_m = dash_period / max(density, 0.001);
		vec2 p = vec2((cell - 0.5) * cell_len_m, across * width_m * 0.5);
		float r = length(p);
		float rad = fill * 0.5 * min(cell_len_m, width_m);
		float edge_m = width_m * 0.18;
		alpha = 1.0 - smoothstep(rad, rad + edge_m, r);
	}
	float rim = 1.0 - smoothstep(0.55, 1.0, abs(across));
	vec3 col = base_color.rgb + rim * rim_strength * 0.35;
	ALBEDO = col;
	ALPHA = alpha * base_color.a;
	EMISSION = col * emission_strength * alpha;
}
"""
	return shader
