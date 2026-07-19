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
	_test_no_unnecessary_stall_card_on_hard()
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


# --- Regression: AI must never trip the stalling foul unnecessarily on Hard ---
func _test_no_unnecessary_stall_card_on_hard() -> void:
	var ms := MatchState.new()
	ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 99)
	# Force a live stalling anchor at the kickoff mid (3,7), matching a real
	# clean-shot scenario, then let Hard decide 30 combos in a row (rebuilding
	# a fresh kickoff each time) and confirm it never plays into it when a
	# non-violating option exists.
	var violations := 0
	for _i in range(30):
		ms.reset(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam")
		ms.stall_ref_id["HomeTeam"] = ms.pieces[Vector2i(3, 7)]["id"]
		ms.stall_ref_cell["HomeTeam"] = Vector2i(3, 7)
		var shoot := AIPlayer.decide_combo(ms, "Hard")
		if shoot != Vector2i(-1, -1) and AIPlayer._violates_stall(ms, shoot):
			violations += 1
	_check(violations == 0, "Hard never trips the stalling foul when a safe option exists (%d/30 violations)" % violations)


# --- Regression: AI must step into an open shooting lane on its own goal ------
func _test_ai_defends_open_lane() -> void:
	var ms := MatchState.new()
	var home := [{"cell": Vector2i(3, 9), "role": "gk"}]
	var away := [
		{"cell": Vector2i(4, 0), "role": "gk"},   # off to the side, not on the test lane
		{"cell": Vector2i(2, 3), "role": "field"}, # one step from the lane, nothing else nearby
	]
	ms.setup(home, away, Vector2i(3, 5), "HomeTeam", 99) # ball sits clear on the (3, *) column
	ms.current = "AwayTeam"
	ms.phase = MatchState.Phase.MOVE
	var lane := Board.cells_between(Vector2i(3, 5), Vector2i(3, 0)) # AwayTeam's own goal at col 3
	var mv := AIPlayer.decide_move(ms, "Hard")
	_check(mv.has("from"), "defense test: AI found a legal move")
	if mv.has("from"):
		var to: Vector2i = mv["to"]
		_check(to in lane, "Hard steps into the open shooting lane to block it (moved to %s, lane=%s)" % [to, lane])


# --- Smoke test: a full AI-vs-AI match plays out without errors/infinite loops
func _test_full_ai_vs_ai_match() -> void:
	for difficulty in ["Easy", "Medium", "Hard"]:
		var ms := MatchState.new()
		ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 3)
		var turns := 0
		var max_turns := 400
		while ms.score["HomeTeam"] < 3 and ms.score["AwayTeam"] < 3 and turns < max_turns:
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
		var finished: bool = ms.score["HomeTeam"] >= 3 or ms.score["AwayTeam"] >= 3
		_check(finished, "%s vs %s: a full match completes within %d turns (score %d:%d after %d turns)" %
			[difficulty, difficulty, max_turns, ms.score["HomeTeam"], ms.score["AwayTeam"], turns])
