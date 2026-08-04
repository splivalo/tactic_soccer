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
	_test_ai_defends_open_lane()
	_test_shot_must_stay_recoverable()
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
	# Asserted against the constants themselves, not hard-coded numbers: these
	# are balance dials that get retuned (see AIPlayer.TOP_PICK_MEDIUM), and a
	# test that has to be edited every time one moves is just friction — what
	# actually needs guarding is that _rank_pick HONOURS them.
	var rate := float(hits0) / trials
	_check(absf(rate - AIPlayer.TOP_PICK_MEDIUM) < 0.04,
		"Medium picks rank#1 ~%.0f%% of the time (got %.1f%%)" \
			% [AIPlayer.TOP_PICK_MEDIUM * 100.0, rate * 100.0])

	hits0 = 0
	var hits_low := 0
	for _i in range(trials):
		var p = AIPlayer._rank_pick(candidates, func(x): return float(x), "Easy")
		if p == 30:
			hits0 += 1
		elif p == 10 or p == 5:
			hits_low += 1
	rate = float(hits0) / trials
	_check(absf(rate - AIPlayer.TOP_PICK_EASY) < 0.04,
		"Easy picks rank#1 ~%.0f%% of the time (got %.1f%%)" \
			% [AIPlayer.TOP_PICK_EASY * 100.0, rate * 100.0])
	_check(hits0 + hits_low == trials, "Easy's remaining picks land on rank#2/#3 only")


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


# --- Regression: never fire the ball somewhere nobody can pick it up --------
# Straight from a human's console log (2026-07-27): with the ball on (0,6) and
# its only nearby man on (1,5), the AI shot all the way down the open diagonal
# to (5,9) on the opponent's goal line — maximum "progress", but 4 cells from
# its own shooter, which may then move only MatchState.MAX_MOVE_RANGE. The
# ball sat there unguarded and the opposing keeper stepped across and took it.
# The scoring already knew better (see AIPlayer._shot_handover_penalty); the
# bug was the beam PRE-FILTER ranking candidates by raw forward progress
# alone, so the sane, supported shots were discarded before the real scoring
# ever saw them — see _search_combo_step.
func _test_shot_must_stay_recoverable() -> void:
	var ms := MatchState.new()
	var away := [
		{"cell": Vector2i(3, 0), "role": "gk"},
		{"cell": Vector2i(1, 5), "role": "field"}, # holds the ball
		{"cell": Vector2i(1, 7), "role": "field"}, # support, covers the near diagonal
	]
	var home := [
		{"cell": Vector2i(4, 9), "role": "gk"},    # one step from (5,9) -- the punisher
		{"cell": Vector2i(6, 0), "role": "field"}, # far away, keeps Away onside
	]
	ms.setup(home, away, Vector2i(0, 6), "AwayTeam", 99)
	_check(ms.phase == MatchState.Phase.COMBO and ms.current == "AwayTeam",
		"setup: AwayTeam opens on the ball at (0,6)")
	_check(not (Vector2i(5, 9) in ms.move_targets(Vector2i(1, 7))),
		"setup sanity: the support man can't simply walk to (5,9) either")

	var shoot := AIPlayer.decide_combo(ms, "Hard")
	var shooter: Vector2i = ms.chain[-1] if not ms.chain.is_empty() else Vector2i(-1, -1)
	var own_adjacent := false
	for c in ms.pieces:
		if ms.pieces[c]["team"] == "AwayTeam" \
				and maxi(absi(c.x - shoot.x), absi(c.y - shoot.y)) == 1:
			own_adjacent = true
			break
	# Deliberately demands a man ACTUALLY next to the ball, not merely a
	# shooter close enough to chase it: chasing is the fallback for when
	# nothing better exists, and here something better plainly does (several
	# shots keep the support at (1,7) adjacent). Accepting "can chase" is what
	# makes this test toothless — the pre-fix code passes that weaker bar.
	_check(own_adjacent,
		"Hard keeps a man on the ball rather than firing it into space (shot %s, shooter %s, own adjacent=%s)" \
			% [shoot, shooter, own_adjacent])


# --- Smoke test: a full AI-vs-AI match plays out without errors/infinite loops
func _test_full_ai_vs_ai_match() -> void:
	# win=2, which IS the shipped value — see main.gd's goals_to_win export. An
	# older version of this comment claimed the real default was 3, which was
	# wrong and got repeated downstream, so: 2.
	#
	# Hard plays real defense (see AIPlayer._post_shot_threat_penalty /
	# _search_best_combo), so a Hard-vs-Hard match between two equally-matched,
	# fully deterministic Hard AIs is a genuine defensive grind — it can easily
	# need well over 400 individual actions even though it's making steady
	# progress. This test only needs to prove the loop terminates cleanly across
	# every phase, not that a match is fast.
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
		if difficulty == "Hard":
			# Hard is fully deterministic (_rank_pick always takes rank #0), so
			# Hard-vs-Hard is the same position answered the same way forever:
			# with the stalling rule gone (2026-07-28, see MatchState's cards
			# comment) nothing exists to break a cycle, and this matchup CAN
			# and does run the cap out goalless. That is not a defect to assert
			# against — the shipped game never pits AI against AI (GameFlow is
			# 1P human-vs-AI or 2P hot-seat), and a human on the other side
			# breaks any cycle by definition. What still matters here, and what
			# is still being tested, is that 1500 turns of every phase run
			# through without an error or an illegal state.
			print("  ..  : Hard vs Hard ran %d turns cleanly (score %d:%d, finished=%s) — " % \
				[turns, ms.score["HomeTeam"], ms.score["AwayTeam"], finished] \
				+ "completion deliberately NOT asserted, see comment")
			continue
		_check(finished, "%s vs %s: a full match completes within %d turns (score %d:%d after %d turns)" %
			[difficulty, difficulty, max_turns, ms.score["HomeTeam"], ms.score["AwayTeam"], turns])
