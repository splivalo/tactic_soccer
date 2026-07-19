extends SceneTree

## Verifies AUTOGOL: a figure that shoots into its OWN goal concedes — the
## opponent scores and restarts. Run:
##   godot --headless -s res://scripts/tests/test_autogol.gd

func _initialize() -> void:
	var ms := MatchState.new()
	ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)

	# Minimal scenario: one HomeTeam field figure with a clear line straight down
	# into its OWN goal cell (3,9) (Home's own-goal row = ROWS-1).
	ms.pieces = {Vector2i(3, 6): {"team": "HomeTeam", "role": "field", "id": 99}}
	ms.ball = Vector2i(3, 5)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.score = {"HomeTeam": 0, "AwayTeam": 0}

	var began := ms.begin(Vector2i(3, 6))
	var own_goal := Vector2i(3, 9)
	print("begin=%s  own-goal (3,9) is a shoot target: %s" % [began, own_goal in ms.combo_shoot_targets()])

	var res := ms.execute_combo(own_goal)
	print("goal=%s own_goal=%s scorer=%s kickoff=%s score=%s"
		% [res["goal"], res["own_goal"], res["scorer"], res["kickoff"], ms.score])

	var pass_ok: bool = (res["goal"] and res["own_goal"]
		and res["scorer"] == "AwayTeam" and res["kickoff"] == "HomeTeam"
		and ms.score["AwayTeam"] == 1 and ms.score["HomeTeam"] == 0)
	print("RESULT: ", "PASS" if pass_ok else "FAIL")

	print("\n--- wrong-corner scenario (matches the rulebook diagram) ---")
	# Keeper (GK) parked in the CENTRE goal cell (3,9). A defender at (5,6) has
	# two options: pass up to a teammate at (5,3) (straight line), OR shoot
	# diagonally toward the goal's LEFT corner (2,9) — empty, since the keeper
	# isn't there and no outfield piece may ever stand in a goal cell. That
	# corner should be a SHOOT target (not a pass target: nobody stands there)
	# and landing the ball there must concede — exactly "dodavanje/ispucavanje
	# u krivi korner = autogol", reproduced with no special-case geometry code.
	ms.pieces = {
		Vector2i(3, 9): {"team": "HomeTeam", "role": "gk", "id": 1},
		Vector2i(5, 6): {"team": "HomeTeam", "role": "field", "id": 2},
		Vector2i(5, 3): {"team": "HomeTeam", "role": "field", "id": 3},
	}
	ms.ball = Vector2i(4, 6)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.score = {"HomeTeam": 0, "AwayTeam": 0}
	ms.begin(Vector2i(5, 6))
	var corner := Vector2i(2, 9)
	var shoot_targets := ms.combo_shoot_targets()
	var pass_targets := ms.combo_pass_targets()
	_check2(Vector2i(5, 3) in pass_targets, "straight pass to the teammate (5,3) is offered")
	_check2(corner in shoot_targets, "empty wrong-side corner (2,9) is a SHOOT target")
	_check2(not (corner in pass_targets), "...but NOT a pass target (nobody actually stands there)")

	var res2 := ms.execute_combo(corner)
	print("shoot into (2,9): goal=%s own_goal=%s scorer=%s score=%s"
		% [res2["goal"], res2["own_goal"], res2["scorer"], ms.score])
	_check2(res2["goal"] and res2["own_goal"] and res2["scorer"] == "AwayTeam" and ms.score["AwayTeam"] == 1,
		"shooting the wrong corner concedes (AwayTeam scores)")

	print("\n--- an own goal must NOT also trigger a stalling card ---")
	# No team ever "stalls" by conceding — piling a card on top of a goal
	# already lost would just be a double penalty for something that was
	# never a cynical time-wasting tactic. See MatchState.would_violate_stall.
	ms.pieces = {Vector2i(3, 6): {"team": "HomeTeam", "role": "field", "id": 99}}
	ms.ball = Vector2i(3, 5)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.score = {"HomeTeam": 0, "AwayTeam": 0}
	ms.foul_count["HomeTeam"] = 0
	ms.stall_ref_id["HomeTeam"] = 99
	ms.stall_ref_cell["HomeTeam"] = Vector2i(3, 8) # Chebyshev-1 from the own-goal cell (3,9)
	ms.begin(Vector2i(3, 6))
	var res3 := ms.execute_combo(Vector2i(3, 9)) # own goal, ALSO next to the live stalling reference
	print("shoot into own goal next to stall ref: goal=%s own_goal=%s card=%s foul_count=%d"
		% [res3["goal"], res3["own_goal"], res3["card"], ms.foul_count["HomeTeam"]])
	_check2(res3["goal"] and res3["own_goal"], "shot into own goal (3,9) still concedes as normal")
	_check2(res3["card"] == "", "...but does NOT also trigger a stalling card, even though it's next to the reference")
	_check2(ms.foul_count["HomeTeam"] == 0, "foul_count stays unchanged — an own goal never counts as a violation")

	quit()


var _fail2 := 0
func _check2(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail2 += 1
		printerr("  FAIL: %s" % label)
