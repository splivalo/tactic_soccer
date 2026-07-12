extends SceneTree

## Exercises the goal cinematic on the live match without needing an actual
## goal: activates the goal cam, runs the celebration (keeper dive + hold), and
## checks the view cuts to the cinematic camera and restores to the main one.

func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for i in 5:
		await process_frame

	print("goal_cam exists: ", main._goal_cam != null)
	var gk = main._find_gk("AwayTeam")
	print("found AwayTeam GK: ", gk.name if gk != null else "<none>")

	main._activate_goal_cam(Vector2i(3, 0))
	print("goal cam current after activate: ", main._goal_cam.current)
	print("goal cam pos: ", main._goal_cam.global_position.snapped(Vector3(0.1, 0.1, 0.1)))

	await main._celebrate_goal({"scorer": "HomeTeam"})
	var cam = main.get_node_or_null("Camera3D")
	var restored = cam != null and cam.current and not main._goal_cam.current
	print("main camera restored after celebration: ", restored)
	print("RESULT: ", "PASS" if (main._goal_cam != null and gk != null and restored) else "FAIL")
	quit()
