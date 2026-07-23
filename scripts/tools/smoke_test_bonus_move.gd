extends SceneTree
## Throwaway smoke test — deleted after use.

func _initialize() -> void:
	var s := load("res://main.gd")
	assert(s != null, "main.gd failed to load/parse")
	print("main.gd OK")

	var home := [
		{"cell": Vector2i(3, 8), "role": "field"},
		{"cell": Vector2i(3, 6), "role": "field"},
	]
	var away := [{"cell": Vector2i(0, 0), "role": "field"}]
	var ms := MatchState.new()
	ms.setup(home, away, Vector2i(3, 7), "HomeTeam", 99)
	assert(ms.begin(Vector2i(3, 8)))
	var targets: Array[Vector2i] = ms.combo_shoot_targets()
	# Pick a non-scoring shoot target (not a goal cell).
	var target := Vector2i(-1, -1)
	for t in targets:
		if not ms.is_opponent_goal(t, "HomeTeam") and not ms.is_own_goal_cell(t, "HomeTeam"):
			target = t
			break
	assert(target != Vector2i(-1, -1))
	var res := ms.execute_combo(target)
	assert(res["ok"])
	assert(not res["goal"])
	print("After non-scoring shot: phase=%s current=%s (expect MOVE, HomeTeam)" \
		% [MatchState.Phase.keys()[ms.phase], ms.current])
	assert(ms.phase == MatchState.Phase.MOVE)
	assert(ms.current == "HomeTeam")
	assert(not ms._move_is_reactive)

	# Bonus move should be legal for the SAME team.
	var mv_targets: Array[Vector2i] = ms.move_targets(Vector2i(3, 6))
	assert(mv_targets.size() > 0)
	var moved := ms.do_move(Vector2i(3, 6), mv_targets[0])
	assert(moved)
	print("After bonus move: phase=%s current=%s (expect COMBO/MOVE, AwayTeam)" \
		% [MatchState.Phase.keys()[ms.phase], ms.current])
	assert(ms.current == "AwayTeam") # turn actually passed now

	# hold_and_move should NOT grant a bonus -- ends turn immediately.
	var ms2 := MatchState.new()
	ms2.setup(home, away, Vector2i(3, 7), "HomeTeam", 99)
	var held := ms2.hold_and_move(Vector2i(3, 6), Vector2i(2, 6))
	assert(held)
	print("After hold (no shot): current=%s (expect AwayTeam, no bonus move)" % ms2.current)
	assert(ms2.current == "AwayTeam")

	print("ALL ASSERTIONS PASSED")
	quit()
