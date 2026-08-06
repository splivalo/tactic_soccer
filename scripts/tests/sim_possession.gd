extends SceneTree

## Possession metrics for whatever rule variant is compiled in.
##
##   godot --headless -s res://scripts/tests/sim_possession.gd
##
## The appeal is that it isn't a rules change at all: more bodies means fewer
## clear rays, so the blocking that already exists starts to bite. The worry is
## that it hands the attacker exactly as much — another receiver for the chain,
## another player to cover where the ball lands — and options help whoever is
## choosing, which is the attacker. So it gets measured rather than argued.
##
## Formations are built here rather than changed in Formations, so the game is
## untouched by running this.

const MATCHES := 25 # bigger squads are slower to simulate
const MAX_TURNS := 1200
const DIFFICULTY := "Medium"

## Home outfield men in the order they get added, so taking the first N gives a
## squad of N that still looks like a formation rather than a corner of one.
## Four is five-a-side, which is a real format, not an invention. Away is the
## mirror the rest of Formations already uses (x -> 6-x, y -> 9-y).
const HOME_OUTFIELD := [
	Vector2i(1, 8), Vector2i(5, 8),   # a wide pair at the back
	Vector2i(3, 7),                   # the man beside the kickoff spot
	Vector2i(2, 5), Vector2i(4, 5),   # two ahead: the 2-1-2 that ships
]
const HOME_GK := Vector2i(3, 9)


## How many immediate choices the side to move is looking at. The number that
## answers "does this become chaos" — a human reported the old fast version was
## unplayable not because it was unfair but because "it was hard to keep track of
## every possible move". Chess sits around 35 and is about the ceiling a person
## can plan against.
##
## Counted shallow, at the top of the turn: ways to start a chain, plus every
## square every movable figure could go to. Chain continuations are deeper and
## deliberately not counted — this is "how much is in front of me right now".
func _branching(ms: MatchState) -> int:
	var n := 0
	if ms.phase == MatchState.Phase.COMBO:
		n += ms.combo_starters().size()
		for c in ms.own_cells():
			n += ms.move_targets(c).size()
	else:
		for c in ms.move_from_cells():
			n += ms.move_targets(c).size()
	return n


func _initialize() -> void:
	# Underfoot throughout, five outfield a side, matching the game.
	#
	# EVERY flag is set on EVERY run, never left to its default. Three variants
	# once reported identical numbers to the decimal because the flag under test
	# was already true before the first of them started — so all three measured
	# the same rule and the comparison was worthless while looking convincing.
	MatchState.experiment_underfoot = true
	_variant(false, true, false)
	_run("one action per turn", false)
	_variant(true, false, false)
	_run("two actions, order free", false)
	_variant(true, false, true)
	_run("move then kick (ball must be played)", false)
	_variant(true, false, false)
	quit(0)


func _variant(two_actions: bool, no_move_after_kick: bool, move_then_kick: bool) -> void:
	MatchState.experiment_two_actions = two_actions
	MatchState.experiment_no_move_after_kick = no_move_after_kick
	MatchState.experiment_move_then_kick = move_then_kick


func _squad(outfield: int, home: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"cell": _side(HOME_GK, home), "number": 1, "role": "gk"})
	for i in outfield:
		out.append({
			"cell": _side(HOME_OUTFIELD[i], home),
			"number": i + 2,
			"role": "field",
		})
	return out


func _side(cell: Vector2i, home: bool) -> Vector2i:
	return cell if home else Vector2i(6 - cell.x, 9 - cell.y)


func _run(label: String, _variant: bool) -> void:
	var underfoot := MatchState.experiment_underfoot
	var outfield := 5
	# Underfoot starts the ball at the kicking side's midfielder; otherwise on
	# the empty square beside their keeper, as the real game does.
	var home_ball := HOME_GK if underfoot else Vector2i(3, 8) # the keeper kicks off
	var away_ball := _side(HOME_GK, false) if underfoot else Vector2i(3, 1)
	var total_turns := 0
	var finished := 0
	var goals := 0
	var streaks: Array[int] = []
	var chases := 0
	var recoveries := 0
	var was_chasing := {"HomeTeam": false, "AwayTeam": false}
	var blocked_rays := 0.0
	var ray_samples := 0
	var branch_total := 0.0
	var branch_worst := 0

	for m in MATCHES:
		seed(m * 7919)
		var home := _squad(outfield, true)
		var away := _squad(outfield, false)
		var ms := MatchState.new()
		ms.setup(home, away, home_ball, "HomeTeam", 2)
		var turns := 0
		var holder := ""
		var streak := 0
		while ms.score["HomeTeam"] < 2 and ms.score["AwayTeam"] < 2 and turns < MAX_TURNS:
			var on_move := ms.current
			var has_ball := ms.team_has_ball(on_move)
			if has_ball:
				if on_move == holder:
					streak += 1
				else:
					if streak > 0:
						streaks.append(streak)
					holder = on_move
					streak = 1
			if was_chasing[on_move]:
				chases += 1
				if has_ball:
					recoveries += 1
			was_chasing[on_move] = not has_ball
			var b := _branching(ms)
			branch_total += b
			branch_worst = maxi(branch_worst, b)

			turns += 1
			match ms.phase:
				MatchState.Phase.COMBO:
					# How much of the board a chain can still reach. This is the
					# whole theory of the change in one number: if extra bodies
					# don't shrink it, they aren't blocking anything.
					var shoot := AIPlayer.decide_combo(ms, DIFFICULTY)
					if not ms.chain.is_empty():
						blocked_rays += ms.combo_shoot_targets().size()
						ray_samples += 1
					if shoot == Vector2i(-1, -1):
						ms.forfeit()
						continue
					var res := ms.execute_combo(shoot)
					if res["goal"]:
						goals += 1
						if streak > 0:
							streaks.append(streak)
						holder = ""
						streak = 0
						if res["win"]:
							continue
						ms.reset(home, away, home_ball if res["kickoff"] == "HomeTeam" else away_ball, res["kickoff"])
				MatchState.Phase.MOVE:
					var mv := AIPlayer.decide_move(ms, DIFFICULTY)
					if not mv.has("from"):
						ms.forfeit()
						continue
					ms.do_move(mv["from"], mv["to"])
				MatchState.Phase.REMOVE:
					var cell := AIPlayer.decide_removal(ms, DIFFICULTY)
					if cell == Vector2i(-1, -1):
						ms.forfeit()
						continue
					ms.remove_figure(cell)
		if streak > 0:
			streaks.append(streak)
		total_turns += turns
		if ms.score["HomeTeam"] >= 2 or ms.score["AwayTeam"] >= 2:
			finished += 1

	var avg_streak := 0.0
	var longest := 0
	for s in streaks:
		avg_streak += s
		longest = maxi(longest, s)
	if not streaks.is_empty():
		avg_streak /= streaks.size()

	print("\n%s   (%d matches, %s)" % [label.to_upper(), MATCHES, DIFFICULTY])
	print("  possession run      avg %.2f, longest %d" % [avg_streak, longest])
	print("  chasing turn won it %.1f%%  (%d of %d)" \
		% [100.0 * recoveries / maxi(chases, 1), recoveries, chases])
	print("  squares a chain can reach  %.1f" % (blocked_rays / maxf(ray_samples, 1.0)))
	print("  choices per turn    %.0f  (worst %d)   [chess is about 35]" \
		% [branch_total / maxf(total_turns, 1.0), branch_worst])
	print("  turns per match     %.0f" % (float(total_turns) / MATCHES))
	print("  matches finished    %d of %d" % [finished, MATCHES])
	print("  goals               %.2f per match" % (float(goals) / MATCHES))
