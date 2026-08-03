extends SceneTree

## Measures how hard it is for the side WITHOUT the ball to get it back, at
## whatever MAX_MOVE_RANGE is currently compiled in. Run once per value and
## compare — the constant can't be changed at runtime.
##
##   godot --headless -s res://scripts/tests/_sim_move_range.gd
##
## The question it answers is the one a human actually asked: "the defence can
## barely reach the ball". The metric for that is not goals or match length, it
## is how many turns in a row one side keeps possession before the other side
## takes it — a long average means chasing is hopeless.

const MATCHES := 40
const MAX_TURNS := 1200
const DIFFICULTY := "Medium"  # Hard is deterministic; Medium varies like a human


func _initialize() -> void:
	# Both variants in one process: the move ranges are consts and need a source
	# edit between runs, but the open-space rule is a flag, so baseline and
	# variant see identical seeds and identical AI without me editing anything
	# in between and hoping I put it back.
	_run("baseline")
	MatchState.experiment_open_space = true
	_run("open space required")
	MatchState.experiment_open_space = false
	MatchState.experiment_ball_underfoot = true
	_run("ball underfoot ALONE")
	MatchState.experiment_no_self_collect = true
	_run("ball underfoot + no self-collect")
	MatchState.experiment_ball_underfoot = false
	MatchState.experiment_no_self_collect = false
	quit(0)



func _run(label: String) -> void:
	var runs := 0
	var total_turns := 0
	var finished := 0
	var goals := 0
	## Every completed possession run, in turns held.
	var streaks: Array[int] = []
	## A team started a turn without the ball; did they start their NEXT turn
	## with it? Measured across the team's own turns, not the raw turn counter —
	## checking "am I adjacent now" right after moving answers a different and
	## useless question, since the attacker is usually adjacent too and simply
	## kicks it away again before this team's turn comes round.
	var chases := 0
	var recoveries := 0
	var was_chasing := {"HomeTeam": false, "AwayTeam": false}

	for m in MATCHES:
		seed(m * 7919)
		var ms := MatchState.new()
		ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
		var turns := 0
		var holder := ""
		var streak := 0
		while ms.score["HomeTeam"] < 2 and ms.score["AwayTeam"] < 2 and turns < MAX_TURNS:
			# Sampled at the top of each turn, before anyone acts.
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

			turns += 1
			match ms.phase:
				MatchState.Phase.COMBO:
					var shoot := AIPlayer.decide_combo(ms, DIFFICULTY)
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
						ms.reset(Formations.home(), Formations.away(), Vector2i(3, 8), res["kickoff"])
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
		runs += 1
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

	print("\n%s   (move %d, bonus %d, %d matches, %s)" \
		% [label.to_upper(), MatchState.MAX_MOVE_RANGE, MatchState.BONUS_MOVE_RANGE,
			MATCHES, DIFFICULTY])
	print("  possession run     avg %.2f turns, longest %d" % [avg_streak, longest])
	# What share of turns you actually get to play the ball. A rule that ends the
	# 27-turn monopoly by leaving the ball loose most of the game has not fixed
	# the game, it has replaced one problem with a duller one.
	print("  turns WITH the ball %.1f%%" % (100.0 * (total_turns - chases) / maxi(total_turns, 1)))
	print("  chasing turn won it %.1f%%  (%d of %d)" \
		% [100.0 * recoveries / maxi(chases, 1), recoveries, chases])
	print("  turns per match    %.0f" % (float(total_turns) / maxi(runs, 1)))
	print("  matches finished   %d of %d" % [finished, runs])
	print("  goals              %.2f per match" % (float(goals) / maxi(runs, 1)))

