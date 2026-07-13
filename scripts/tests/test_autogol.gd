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
	quit()
