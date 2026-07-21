extends SceneTree

## Headless unit test for the rank-and-pick AI difficulty system. Run:
##   godot --headless -s res://scripts/tests/test_ai_ranked.gd

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _initialize() -> void:
	_test_rank_pick_determinism()
	_test_rank_pick_statistics()
	_test_avoids_unnecessary_contested_recovery_on_hard()
	_test_ai_defends_open_lane()
	_test_full_ai_vs_ai_match()
	print("\n%s (%d failures)" % ["PASS" if _fail == 0 else "FAIL", _fail])
	quit(_fail)


# --- _rank_pick correctness ---------------------------------------------------
func _test_rank_pick_determinism() -> void:
	var candidates := [10, 5, 30, 1] # score = value itself, sorted desc -> 30,10,5,1
	for _i in range(20):
		var picked = AIPlayer._rank_pick(candidates, func(x): return float(x), "Hard")
		_check(picked == 30, "Hard rank_pick always returns the top-scored candidate (got %s)" % picked)


func _test_rank_pick_statistics() -> void:
	var candidates := [30, 10, 5] # rank0=30 rank1=10 rank2=5
	var trials := 4000

	var hits0 := 0
	for _i in range(trials):
		if AIPlayer._rank_pick(candidates, func(x): return float(x), "Medium") == 30:
			hits0 += 1
	var rate := float(hits0) / trials
	_check(absf(rate - 0.9) < 0.04, "Medium picks rank#1 ~90%% of the time (got %.1f%%)" % (rate * 100.0))

	hits0 = 0
	var hits_low := 0
	for _i in range(trials):
		var p = AIPlayer._rank_pick(candidates, func(x): return float(x), "Easy")
		if p == 30:
			hits0 += 1
		elif p == 10 or p == 5:
			hits_low += 1
	rate = float(hits0) / trials
	_check(absf(rate - 0.7) < 0.04, "Easy picks rank#1 ~70%% of the time (got %.1f%%)" % (rate * 100.0))
	_check(hits0 + hits_low == trials, "Easy's remaining picks land on rank#2/#3 only")


# --- Regression: AI must never walk into an unnecessary contested 50-50 on Hard ---
func _test_avoids_unnecessary_contested_recovery_on_hard() -> void:
	# HomeTeam has 2 ways to react and reach the ball: (2,8)->(2,5) lands
	# directly opposite the AwayTeam figure at (4,5) through the ball (a
	# contested 50-50 — see MatchState.is_contested_recovery), while
	# (3,3)->(3,4) reaches the SAME adjacency just as well with no duel at
	# all. A team should never risk the card when a safe reach exists.
	var home := [
		{"cell": Vector2i(2, 8), "role": "field"},
		{"cell": Vector2i(3, 3), "role": "field"},
	]
	var away := [{"cell": Vector2i(4, 5), "role": "field"}]
	var risky_landings := 0
	for _i in range(20):
		var ms := MatchState.new()
		ms.setup(home, away, Vector2i(3, 5), "HomeTeam", 99)
		var decision := AIPlayer.decide_move(ms, "Hard")
		if decision.has("to") and ms.is_contested_recovery(decision["to"], "HomeTeam"):
			risky_landings += 1
	_check(risky_landings == 0,
		"Hard never picks a contested-50-50 landing cell when a safe reach-the-ball option exists (%d/20 risky)" % risky_landings)


# --- Regression: AI must step into an open shooting lane on its own goal ------
# The threat must be REAL (team_can_score_next, not just "a straight line
# exists") — the shooter has to be a piece that could actually take a shot
# THIS turn: already adjacent to the ball, AND in the opponent's half (rules
# require that to score at all — see MatchState.combo_shoot_targets).
func _test_ai_defends_open_lane() -> void:
	var ms := MatchState.new()
	var home := [
		{"cell": Vector2i(3, 9), "role": "gk"},    # irrelevant, nowhere near the ball
		{"cell": Vector2i(3, 4), "role": "field"},  # already adjacent to the ball, deep in Away's half
	]
	var away := [
		{"cell": Vector2i(4, 0), "role": "gk"},   # off to the side, not on the test lane
		{"cell": Vector2i(2, 3), "role": "field"}, # blocks the only diagonal alternative, keeps Home onside
	]
	ms.setup(home, away, Vector2i(3, 3), "HomeTeam", 99) # ball sits clear on the (3, *) column
	ms.current = "AwayTeam"
	ms.phase = MatchState.Phase.MOVE
	_check(AIPlayer.team_can_score_next(ms, "HomeTeam"),
		"setup: HomeTeam has a real, unblocked shot at (3,4)->(3,0) this test relies on")
	var lane := Board.cells_between(Vector2i(3, 3), Vector2i(3, 0)) # AwayTeam's own goal at col 3
	var mv := AIPlayer.decide_move(ms, "Hard")
	_check(mv.has("from"), "defense test: AI found a legal move")
	if mv.has("from"):
		var to: Vector2i = mv["to"]
		_check(to in lane, "Hard steps into the open shooting lane to block it (moved to %s, lane=%s)" % [to, lane])


# --- Smoke test: a full AI-vs-AI match plays out without errors/infinite loops
func _test_full_ai_vs_ai_match() -> void:
	# win=2 (not the real default of 3) purely so this stays a fast smoke test:
	# Hard now plays real defense (see AIPlayer._post_shot_threat_penalty /
	# _search_best_combo), so a Hard-vs-Hard match between two equally-matched,
	# fully deterministic Hard AIs is a genuine defensive grind — it can easily
	# need well over 400 individual actions to reach a 3rd goal even though
	# it's making steady progress (2 goals inside 400 already). This test only
	# needs to prove the loop terminates cleanly across every phase, not that a
	# full 3-goal match is fast.
	for difficulty in ["Easy", "Medium", "Hard"]:
		var ms := MatchState.new()
		ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
		var turns := 0
		# 1500: Easy/Medium roll randomness each decision (see _rank_pick) so
		# their match length varies run to run — 600 was tight enough to
		# occasionally time out at 1:1 after the own-goal scoring fix (see
		# AIPlayer._combo_action_score's is_own_goal_cell penalty) removed one
		# of the "free" ways a match used to end early (an accidental autogol
		# padding the score same as a real goal). Real goals only now, so
		# matches genuinely take longer — this is a smoke test for "the loop
		# terminates cleanly", not a speed guarantee, hence the generous cap.
		var max_turns := 1500
		while ms.score["HomeTeam"] < 2 and ms.score["AwayTeam"] < 2 and turns < max_turns:
			turns += 1
			match ms.phase:
				MatchState.Phase.COMBO:
					var shoot := AIPlayer.decide_combo(ms, difficulty)
					if shoot == Vector2i(-1, -1):
						ms.forfeit()
						continue
					var res := ms.execute_combo(shoot)
					if res["goal"]:
						if res["win"]:
							continue
						ms.reset(Formations.home(), Formations.away(), Vector2i(3, 8), res["kickoff"])
				MatchState.Phase.MOVE:
					var mv := AIPlayer.decide_move(ms, difficulty)
					if not mv.has("from"):
						ms.forfeit()
						continue
					ms.do_move(mv["from"], mv["to"])
				MatchState.Phase.REMOVE:
					var cell := AIPlayer.decide_removal(ms, difficulty)
					if cell == Vector2i(-1, -1):
						ms.forfeit()
						continue
					ms.remove_figure(cell)
		var finished: bool = ms.score["HomeTeam"] >= 2 or ms.score["AwayTeam"] >= 2
		_check(finished, "%s vs %s: a full match completes within %d turns (score %d:%d after %d turns)" %
			[difficulty, difficulty, max_turns, ms.score["HomeTeam"], ms.score["AwayTeam"], turns])
