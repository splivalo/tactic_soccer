extends SceneTree

## Checks the tutorial scenario is actually playable. Run:
##   godot --headless -s res://scripts/tests/test_tutorial.gd
##
## Worth its own test because the lesson is hand-placed: if the ball can't
## legally reach the teammate the prompt points at, the tutorial dead-ends on
## step two and the player is stuck being told to do something the rules forbid.
## Every step is walked through the real MatchState here, so the layout can't
## drift out of legality unnoticed.

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _initialize() -> void:
	print("--- test_tutorial ---")
	var ms := MatchState.new()
	ms.setup(Tutorial.home_formation(), Tutorial.away_formation(), Tutorial.BALL, "HomeTeam", 2)
	var t := Tutorial.new()

	# The scenario has to open with the ball already ours, or step one is a lie.
	_check(ms.phase == MatchState.Phase.COMBO, "opens in COMBO — the ball is ours")
	_check(Tutorial.FIRST in ms.combo_starters(), "the player the prompt points at can start")
	_check(t.step == Tutorial.Step.PICK, "starts on the first lesson")

	# Step 1 — pick him up.
	_check(t.allows(Tutorial.BALL), "tapping the ball is allowed, so the mistake can be answered")
	_check(not t.allows(Vector2i(0, 0)), "an unrelated square is ignored")
	_check(ms.begin(Tutorial.FIRST), "begin the chain")
	_check(t.on_action("begin", Tutorial.FIRST), "lesson advances to the straight-line step")

	# Step 2 — the straight line.
	_check(Tutorial.SECOND in ms.combo_pass_targets(),
		"the teammate the prompt points at IS reachable in a straight line")
	_check(ms.extend(Tutorial.SECOND), "connect to him")
	_check(t.on_action("extend", Tutorial.SECOND), "lesson advances to chaining")

	# Step 3 — keep going.
	_check(Tutorial.THIRD in ms.combo_pass_targets(), "a third player is reachable from the second")
	_check(ms.extend(Tutorial.THIRD), "connect to him too")
	_check(t.on_action("extend", Tutorial.THIRD), "lesson advances to the shot")

	# Step 4 — both shots must be legal, and one must be the bad one.
	var shots := ms.combo_shoot_targets()
	_check(Tutorial.SAFE_SHOT in shots, "the safe square is a legal shot")
	_check(Tutorial.RISKY_SHOT in shots, "the risky square is a legal shot too")
	_check(t.refusal(Tutorial.RISKY_SHOT) != "", "the risky one is refused with a reason")
	_check(t.refusal(Tutorial.SAFE_SHOT) == "", "the safe one goes through")

	# The whole point of the risky square: it really is beside the opponent, and
	# the safe one really isn't.
	var them: Vector2i = Tutorial.THEIRS[0]["cell"]
	_check(maxi(absi(Tutorial.RISKY_SHOT.x - them.x), absi(Tutorial.RISKY_SHOT.y - them.y)) <= 1,
		"the risky square really is next to the opponent")
	_check(maxi(absi(Tutorial.SAFE_SHOT.x - them.x), absi(Tutorial.SAFE_SHOT.y - them.y)) > 1,
		"...and the safe one really isn't")

	var res := ms.execute_combo(Tutorial.SAFE_SHOT)
	_check(res["ok"], "the shot resolves")
	_check(t.on_action("shoot", Tutorial.SAFE_SHOT), "lesson advances to the move")

	# Step 5 — the second action of the turn.
	_check(ms.phase == MatchState.Phase.MOVE, "a move is owed after the shot")
	var movers := ms.move_from_cells()
	_check(not movers.is_empty(), "someone can move")
	if not movers.is_empty():
		var from: Vector2i = movers[0]
		var targets := ms.move_targets(from)
		_check(not targets.is_empty(), "that someone has somewhere to go")
		if not targets.is_empty():
			_check(ms.do_move(from, targets[0]), "the move goes through")
			_check(t.on_action("move", targets[0]), "lesson finishes")
	_check(t.finished(), "tutorial reports itself done")

	if _fail == 0:
		print("--- test_tutorial: ALL PASSED ---")
	else:
		printerr("--- test_tutorial: %d FAILED ---" % _fail)
	quit(_fail)
