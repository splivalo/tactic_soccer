extends SceneTree

## Drives a real combo, lets the facing settle, then screenshots the board so we
## can eyeball that only players near the ball turned to it and the rest held
## formation (no sunflower spin). Windowed run.
const OUT := "res://_settle.png"


func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for i in 5:
		await process_frame

	var st = main._state
	var starters: Array = st.combo_starters()
	if starters.is_empty():
		print("no starters"); quit(); return
	st.begin(starters[0])
	var passes: Array = st.combo_pass_targets()
	if not passes.is_empty():
		st.extend(passes[0])
	var shoots: Array = st.combo_shoot_targets()
	if shoots.is_empty():
		print("no shoots"); quit(); return
	await main._do_combo(shoots[0])

	# Let the staggered settle-turns finish.
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ball at ", st.ball)
	quit()
