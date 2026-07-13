extends SceneTree

## Sets up a real goal (home shoots up into the away net), fires the combo, and
## snapshots several frames so we can see the ball fly into the net and the goal
## camera follow + zoom. Windowed run.

func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for i in 5:
		await process_frame

	var st = main._state
	# Home figure at (3,3) with a clear lane up into the away goal (3,0); an away
	# defender level at (5,3) keeps it onside; away GK off the (3,0) cell.
	st.pieces = {
		Vector2i(3, 3): {"team": "HomeTeam", "role": "field", "id": 1},
		Vector2i(5, 3): {"team": "AwayTeam", "role": "field", "id": 2},
		Vector2i(2, 0): {"team": "AwayTeam", "role": "gk", "id": 3},
	}
	st.ball = Vector2i(3, 4)
	st.current = "HomeTeam"
	st.phase = MatchState.Phase.COMBO
	st.score = {"HomeTeam": 0, "AwayTeam": 0}
	st.begin(Vector2i(3, 3))
	print("(3,0) is a shoot target: ", Vector2i(3, 0) in st.combo_shoot_targets())

	main._do_combo(Vector2i(3, 0))  # fire; flight + goal cam run concurrently

	for i in 6:
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png("res://_goal_%d.png" % i)
		print("shot %d  ball=%s" % [i, main._ball.position.snapped(Vector3(0.1, 0.1, 0.1))])
	quit()
