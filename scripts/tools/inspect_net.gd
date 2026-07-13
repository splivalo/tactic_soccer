extends SceneTree

## Reports the goal-net meshes so we can pick a dent approach (dense grid ->
## shader vertex displacement; low-poly -> a wobble/scale punch).
func _initialize() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for n in ["goal1_net", "goal2_net"]:
		var node = _find(main, n)
		if node == null:
			print(n, ": <not found>")
			continue
		print("\n== ", n, " (", node.get_class(), ") ==")
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			print("  world pos: ", mi.global_position.snapped(Vector3(0.01, 0.01, 0.01)))
			print("  aabb: ", mi.get_aabb())
			var mesh := mi.mesh
			if mesh != null:
				for s in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(s)
					var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var mat := mi.get_active_material(s)
					print("  surface %d: verts=%d  mat=%s (%s)" % [s, verts.size(),
						mat.resource_name if mat else "<null>", mat.get_class() if mat else "-"])
	quit()


func _find(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for c in node.get_children():
		var r := _find(c, wanted)
		if r != null:
			return r
	return null
