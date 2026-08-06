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
	# The lesson is authored for a turn that OPENS on the ball, so it is checked
	# against that turn. Under experiment_move_then_kick the turn opens on a
	# move instead and step one ("tap the player on the ball") is no longer the
	# first thing that happens — the tutorial needs its steps reordered, and its
	# hand-placed board re-verified, before that rule can ship. Recorded here
	# rather than hidden: this pin is a debt, not a fix.
	MatchState.experiment_move_then_kick = false
	var ms := MatchState.new()
	ms.setup(Tutorial.home_formation(), Tutorial.away_formation(), Tutorial.ball_start(), "HomeTeam", 2)
	var t := Tutorial.new()

	# The scenario has to open with the ball already ours, or step one is a lie.
	_check(ms.phase == MatchState.Phase.COMBO, "opens in COMBO — the ball is ours")
	_check(Tutorial.FIRST in ms.combo_starters(), "the player the prompt points at can start")
	_check(t.step == Tutorial.Step.PICK, "starts on the first lesson")

	# The heading is what lets the refusals stop arguing: under PASS THE BALL,
	# turning away an early kick is obviously "not this part" rather than a claim
	# that kicking is against the rules. That only works if the three passing
	# steps share one heading and the others don't — a heading that changed every
	# step would say nothing about which idea you are still on.
	var titles := {}
	for s in Tutorial.Step.values():
		t.step = s
		titles[s] = t.title()
		_check(t.title() != "", "step %s is named" % Tutorial.Step.keys()[s])
	t.step = Tutorial.Step.PICK
	_check(titles[Tutorial.Step.CONNECT] == titles[Tutorial.Step.CHAIN] \
		and titles[Tutorial.Step.CHAIN] == titles[Tutorial.Step.SHOOT],
		"the three passing steps share one heading")
	_check(titles[Tutorial.Step.PICK] != titles[Tutorial.Step.CONNECT] \
		and titles[Tutorial.Step.MOVE] != titles[Tutorial.Step.SHOOT],
		"...and the heading changes when the idea does")

	# Step 1 — pick him up.
	#
	# The board is drawn EXACTLY as a real match draws it (the tutorial hides no
	# options — see tutorial.gd's layout note), so "one answer" has to be true of
	# the position itself, not of what the tutorial chooses to highlight. If the
	# keeper also stood beside the ball, the prompt would point at one player
	# while the game lit two.
	_check(ms.combo_starters().size() == 1,
		"exactly one player can start — the board answers the prompt once")
	_check(t.allows(Tutorial.ball_start()), "tapping the ball is allowed, so the mistake can be answered")
	_check(not t.allows(Vector2i(0, 0)), "an unrelated square is ignored")
	_check(t.nudge(Vector2i(0, 0)) != "", "a wrong tap is answered, not met with silence")
	_check(ms.begin(Tutorial.FIRST), "begin the chain")
	_check(t.on_action("begin", Tutorial.FIRST), "lesson advances to the straight-line step")

	# Step 2 — the straight line. Same rule: one blue option, or the prompt lies.
	var first_targets := ms.combo_pass_targets()
	_check(Tutorial.SECOND in first_targets,
		"the teammate the prompt points at IS reachable in a straight line")
	_check(first_targets.size() == 1, "...and he is the ONLY one reachable")
	# Mid-chain, an empty square IS reachable in a straight line — it's a shot.
	# Answering that with "not in line with the ball" is factually wrong about
	# what the player just did, which is worse than saying nothing.
	var early_shot := ms.combo_shoot_targets()
	_check(not early_shot.is_empty(), "a shot is available mid-chain, so the mistake is reachable")
	if not early_shot.is_empty():
		_check(t.nudge(early_shot[0]) != t.nudge(Tutorial.THIRD),
			"kicking early and picking an off-line player get different answers")
		_check(not t.is_mine(early_shot[0]), "...because one of them is an empty square")

	_check(ms.extend(Tutorial.SECOND), "connect to him")
	_check(t.on_action("extend", Tutorial.SECOND), "lesson advances to chaining")

	# Step 3 — keep going. The third player must NOT have been reachable from the
	# first, or the player could have skipped straight to him and this step would
	# have had nothing left to teach.
	_check(not (Tutorial.THIRD in first_targets),
		"the third player was NOT reachable from the first — the chain is needed")
	_check(Tutorial.THIRD in ms.combo_pass_targets(), "a third player is reachable from the second")
	_check(ms.extend(Tutorial.THIRD), "connect to him too")
	_check(t.on_action("extend", Tutorial.THIRD), "lesson advances to the shot")

	# Step 4 — the shot teaches a RULE, not a square: any target away from the
	# opponent is accepted, any target beside him is refused with the reason. So
	# the position has to offer both kinds.
	var shots := ms.combo_shoot_targets()
	var safe_count := 0
	var risky_count := 0
	for s in shots:
		if t.beside_opponent(s):
			risky_count += 1
		else:
			safe_count += 1
	_check(safe_count > 0, "there is somewhere safe to put the ball")
	_check(risky_count > 0, "...and somewhere that hands it straight over")

	# And NONE of them may be a goal. Step 4 accepts any square away from the
	# opponent, so a reachable goalmouth ends the tutorial three steps early —
	# ball in, cinematic, kickoff, lesson over. The position has to rule it out,
	# since "don't score" is not a lesson worth teaching.
	var scoring := 0
	for s in shots:
		if ms.is_goal_cell(s):
			scoring += 1
	_check(scoring == 0, "no shot from here can find a goal and cut the lesson short")
	_check(Tutorial.SAFE_SHOT in shots, "the named safe square is a legal shot")
	_check(Tutorial.RISKY_SHOT in shots, "the named risky square is a legal shot too")
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
