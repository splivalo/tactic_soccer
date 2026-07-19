extends SceneTree

func _find(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _find(c, name)
		if r != null:
			return r
	return null

func _initialize() -> void:
	var scene := load("res://assets/models/stadium.glb") as PackedScene
	var inst := scene.instantiate()
	var field := _find(inst, "field") as MeshInstance3D
	var lines := _find(inst, "field_lines") as MeshInstance3D
	if field == null or lines == null:
		print("MISSING: field=%s lines=%s" % [field, lines])
		quit(1)
		return
	var f_aabb := field.get_aabb()
	var f_xf := field.global_transform
	var f_min := f_xf * f_aabb.position
	var f_max := f_xf * (f_aabb.position + f_aabb.size)
	print("field local aabb: pos=%s size=%s" % [f_aabb.position, f_aabb.size])
	print("field WORLD bounds: min=%s max=%s (size=%s)" % [f_min, f_max, f_max - f_min])

	var l_aabb := lines.get_aabb()
	var l_xf := lines.global_transform
	var l_min := l_xf * l_aabb.position
	var l_max := l_xf * (l_aabb.position + l_aabb.size)
	print("field_lines local aabb: pos=%s size=%s" % [l_aabb.position, l_aabb.size])
	print("field_lines WORLD bounds: min=%s max=%s (size=%s)" % [l_min, l_max, l_max - l_min])

	print("field_lines transform: %s" % lines.transform)
	print("field transform: %s" % field.transform)

	var diff_min := l_min - f_min
	var diff_max := f_max - l_max
	print("inset from field edge: min-side=%s max-side=%s" % [diff_min, diff_max])
	quit()
