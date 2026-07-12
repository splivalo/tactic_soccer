extends SceneTree

## One-off check that BoardFx's trail shader actually compiles.
## Run: godot --headless -s res://scripts/tests/test_shader.gd

func _initialize() -> void:
	var fx := BoardFx.new()
	root.add_child(fx)
	await process_frame
	await process_frame
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 1)])
	fx.set_trail(pts, Color(0.4, 0.9, 1.0, 0.9))
	fx.trail_pattern = 1
	fx.set_trail(pts, Color(1.0, 0.6, 0.1, 0.9))
	await process_frame
	print("SHADER_TEST: trail built without error")
	quit(0)
