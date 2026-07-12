extends SceneTree

## Headless exercise of the kick-synced combo: builds a real pass+shoot on the
## live match and awaits _do_combo, verifying the ball ends on the shoot cell and
## the board unlocks. No rendering needed — timers/tweens/animation all advance.

func _initialize() -> void:
	_run()


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for i in 5:
		await process_frame

	var st = main._state
	if st == null:
		print("FAIL: no match state"); quit(); return
	var starters: Array = st.combo_starters()
	print("combo starters: ", starters)
	if starters.is_empty():
		print("FAIL: no combo starters at kickoff"); quit(); return

	# Prefer a starter that can reach a shoot target; extend one pass if we can.
	st.begin(starters[0])
	var passes: Array = st.combo_pass_targets()
	print("pass targets from starter: ", passes)
	if not passes.is_empty():
		st.extend(passes[0])
		print("extended chain to: ", passes[0])

	var shoots: Array = st.combo_shoot_targets()
	print("shoot targets: ", shoots.slice(0, 6), " (", shoots.size(), " total)")
	if shoots.is_empty():
		print("FAIL: no shoot targets"); quit(); return

	var target = shoots[0]
	var before = main._ball.position
	print("ball before: ", before, "  chain: ", st.chain)
	await main._do_combo(target)
	var after = main._ball.position
	var want = main._ball_world(target)
	var err = after.distance_to(want)
	print("ball after:  ", after, "  target world: ", want, "  err=%.3f" % err)
	print("busy after combo: ", main._busy)
	print("RESULT: ", "PASS" if err < 0.05 and not main._busy else "FAIL")
	quit()
