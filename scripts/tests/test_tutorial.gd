extends SceneTree

## Checks the tutorial scenario is actually playable. Run:
##   godot --headless -s res://scripts/tests/test_tutorial.gd
##
## Worth its own test because the lesson is hand-placed: if the ball can't
## legally reach the teammate the prompt points at, the tutorial dead-ends and
## the player is stuck being told to do something the rules forbid. Every step is
## walked through the real MatchState here, so the layout can't drift out of
## legality unnoticed.

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _initialize() -> void:
	print("--- test_tutorial ---")
	# The lesson is authored for the turn the game actually plays: a move first,
	# then the ball. Set explicitly rather than inherited, so this never silently
	# checks the scenario against a different rule than the one it was built for.
	MatchState.experiment_underfoot = true
	MatchState.experiment_two_actions = true
	MatchState.experiment_move_then_kick = true

	var ms := MatchState.new()
	ms.setup(Tutorial.home_formation(), Tutorial.away_formation(), Tutorial.ball_start(), "HomeTeam", 2)
	var t := Tutorial.new()

	# The scenario has to open on a MOVE with the ball belonging to nobody, or
	# the first lesson — walk onto it — is a lie.
	_check(ms.phase == MatchState.Phase.MOVE, "opens in MOVE — a turn starts with one")
	_check(not ms.pieces.has(ms.ball), "the ball starts loose, on nobody")
	_check(t.step == Tutorial.Step.COLLECT, "starts on the first lesson")

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
	t.step = Tutorial.Step.COLLECT
	_check(titles[Tutorial.Step.CONNECT] == titles[Tutorial.Step.CHAIN] \
		and titles[Tutorial.Step.CHAIN] == titles[Tutorial.Step.SHOOT],
		"the three passing steps share one heading")
	_check(titles[Tutorial.Step.COLLECT] != titles[Tutorial.Step.CONNECT] \
		and titles[Tutorial.Step.SHOOT] != titles[Tutorial.Step.DONE],
		"...and the heading changes when the idea does")

	# Step 1 — walk onto it.
	#
	# The board is drawn EXACTLY as a real match draws it (the tutorial hides no
	# options — see tutorial.gd's layout note), so "one answer" has to be true of
	# the position itself. Every own figure is listed as movable, exactly as in a
	# real MOVE phase; what must be unique is who can actually REACH the ball.
	var reachers: Array[Vector2i] = []
	for c in ms.move_from_cells():
		if Tutorial.BALL in ms.move_targets(c):
			reachers.append(c)
	_check(reachers.size() == 1, "exactly one player can reach the ball — the prompt has one answer")
	_check(reachers.size() == 1 and reachers[0] == Tutorial.FIRST_FROM,
		"...and he is the one the prompt points at")
	_check(t.allows(Tutorial.FIRST_FROM) and t.allows(Tutorial.BALL),
		"both taps the move needs are allowed")
	_check(not t.allows(Vector2i(0, 0)), "an unrelated square is ignored")
	_check(t.nudge(Vector2i(0, 0)) != "", "a wrong tap is answered, not met with silence")
	_check(ms.do_move(Tutorial.FIRST_FROM, Tutorial.BALL), "walk him onto the ball")
	_check(t.on_action("move", Tutorial.BALL), "lesson advances to the straight-line step")

	# Collecting it must open the ball half of the SAME turn — that is the rule
	# the whole lesson order is built on.
	_check(ms.phase == MatchState.Phase.COMBO, "picking it up opens the ball half of the turn")
	_check(ms.current == "HomeTeam", "...and it is still the same team's turn")
	var starters := ms.combo_starters()
	_check(starters.size() == 1 and starters[0] == Tutorial.FIRST,
		"the man on the ball is the only one who can open a chain")
	_check(ms.begin(Tutorial.FIRST), "open the chain on him")

	# Step 2 — the straight line. One blue option, or the prompt lies.
	var first_targets := ms.combo_pass_targets()
	_check(Tutorial.SECOND in first_targets,
		"the teammate the prompt points at IS reachable in a straight line")
	_check(first_targets.size() == 1, "...and he is the ONLY one reachable")
	# Mid-chain, an empty square IS reachable in a straight line — it's a kick.
	# Answering that with "not in line with the ball" is factually wrong about
	# what the player just did, which is worse than saying nothing.
	var early_shot := ms.combo_shoot_targets()
	_check(not early_shot.is_empty(), "a kick is available mid-chain, so the mistake is reachable")
	if not early_shot.is_empty():
		_check(t.nudge(early_shot[0]) != t.nudge(Tutorial.THIRD),
			"kicking early and picking an off-line player get different answers")
		_check(not t.is_mine(early_shot[0]), "...because one of them is an empty square")
	_check(t.is_mine(Tutorial.FIRST), "the man who collected it counts as mine where he now stands")
	_check(not t.is_mine(Tutorial.FIRST_FROM), "...and not where he used to")

	_check(ms.extend(Tutorial.SECOND), "connect to him")
	_check(t.on_action("extend", Tutorial.SECOND), "lesson advances to chaining")

	# Step 3 — keep going. The third player must NOT have been reachable from the
	# ball, or the player could have skipped straight to him and this step would
	# have had nothing left to teach.
	_check(not (Tutorial.THIRD in first_targets),
		"the third player was NOT reachable from the ball — the chain is needed")
	_check(Tutorial.THIRD in ms.combo_pass_targets(), "a third player is reachable from the second")
	_check(ms.extend(Tutorial.THIRD), "connect to him too")
	_check(t.on_action("extend", Tutorial.THIRD), "lesson advances to the kick")

	# Step 4 — the kick teaches a RULE, not a square: any target away from the
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

	# And NONE of them may be a goal. The step accepts any square away from the
	# opponent, so a reachable goalmouth ends the tutorial two steps early — ball
	# in, cinematic, kickoff, lesson over. The position has to rule it out, since
	# "don't score" is not a lesson worth teaching.
	var scoring := 0
	for s in shots:
		if ms.is_goal_cell(s):
			scoring += 1
	_check(scoring == 0, "no kick from here can find a goal and cut the lesson short")
	_check(Tutorial.SAFE_SHOT in shots, "the named safe square is a legal kick")
	_check(Tutorial.RISKY_SHOT in shots, "the named risky square is a legal kick too")
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
	_check(res["ok"], "the kick resolves")
	_check(not res["goal"], "...without scoring")
	_check(t.on_action("shoot", Tutorial.SAFE_SHOT), "lesson finishes")
	_check(t.finished(), "tutorial reports itself done")

	# And the kick ends the turn, because the move half went first. If it didn't,
	# the lesson would stop with the board still owing the player an action and
	# nothing on screen asking for one.
	_check(ms.current == "AwayTeam", "the kick ends the turn — the move was already spent")

	if _fail == 0:
		print("--- test_tutorial: ALL PASSED ---")
	else:
		printerr("--- test_tutorial: %d FAILED ---" % _fail)
	quit(_fail)
