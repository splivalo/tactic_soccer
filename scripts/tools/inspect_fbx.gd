extends SceneTree

## Headless inspector: dumps skeleton / mesh / material / animation info for
## every imported .fbx under assets/animations, so we know exactly what the
## Mixamo exports contain before wiring them up.
## Run: godot --headless --path <proj> --script res://scripts/tools/inspect_fbx.gd

const DIR := "res://assets/animations/"

func _initialize() -> void:
	var da := DirAccess.open(DIR)
	if da == null:
		push_error("Cannot open %s" % DIR)
		quit()
		return
	for f in da.get_files():
		if not f.to_lower().ends_with(".fbx"):
			continue
		_dump(DIR + f)
	quit()


func _dump(path: String) -> void:
	print("\n==================== ", path, " ====================")
	var ps := load(path) as PackedScene
	if ps == null:
		print("  !! failed to load")
		return
	var root := ps.instantiate()
	_walk(root, 0)
	root.free()


func _walk(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is Skeleton3D:
		var sk := node as Skeleton3D
		var bones := []
		for i in mini(sk.get_bone_count(), 6):
			bones.append(sk.get_bone_name(i))
		extra = " [bones=%d, first: %s]" % [sk.get_bone_count(), ", ".join(bones)]
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mats := []
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i)
				mats.append(mat.resource_name if mat != null else "<null>")
		extra = " [surfaces=%d mats: %s]" % [mats.size(), ", ".join(mats)]
	elif node is AnimationPlayer:
		var ap := node as AnimationPlayer
		var lines := []
		for a in ap.get_animation_list():
			var anim := ap.get_animation(a)
			lines.append("'%s' len=%.3fs tracks=%d" % [a, anim.length, anim.get_track_count()])
		extra = " [anims: %s]" % " | ".join(lines)
	print(indent, node.name, " (", node.get_class(), ")", extra)
	for c in node.get_children():
		_walk(c, depth + 1)
