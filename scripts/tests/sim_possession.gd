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

const MATCHES := 40
const MAX_TURNS := 1200
const DIFFICULTY := "Medium"

## Spare bodies, kept off the existing men's lines so each adds a figure rather
## than simply walling one lane. Home defends rows 5-9, away rows 0-4.
const SPARE_HOME := [
	{"cell": Vector2i(6, 7), "number": 7, "role": "field"},
	{"cell": Vector2i(0, 7), "number": 8, "role": "field"},
]
const SPARE_AWAY := [
	{"cell": Vector2i(0, 2), "number": 7, "role": "field"},
	{"cell": Vector2i(6, 2), "number": 8, "role": "field"},
]


func _initialize() -> void:
	# The rules as they actually stand — two-part turn, six outfield a side.
	# Only the defender's action count varies.
	_run("defender: one move of two (shipped)", 1)
	MatchState.experiment_defender_two_moves = true
	_run("defender: two moves of two", 1)
	MatchState.experiment_defender_two_moves = false
	MatchState.experiment_defender_split_move = true
	_run("defender: two moves of one", 1)
	MatchState.experiment_defender_split_move = false
	quit(0)


func _squad(base: Array[Dictionary], spare: Array, extra: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in base:
		out.append(p.duplicate())
	for i in extra:
		out.append((spare[i] as Dictionary).duplicate())
	return out


func _run(label: String, extra: int) -> void:
	var total_turns := 0
	var finished := 0
	var goals := 0
	var streaks: Array[int] = []
	var chases := 0
	var recoveries := 0
	var was_chasing := {"HomeTeam": false, "AwayTeam": false}
	var blocked_rays := 0.0
	var ray_samples := 0

	for m in MATCHES:
		seed(m * 7919)
		var home := _squad(Formations.home(), SPARE_HOME, extra)
		var away := _squad(Formations.away(), SPARE_AWAY, extra)
		var ms := MatchState.new()
		ms.setup(home, away, Vector2i(3, 8), "HomeTeam", 2)
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
						ms.reset(home, away, Vector2i(3, 8), res["kickoff"])
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
	print("  turns per match     %.0f" % (float(total_turns) / MATCHES))
	print("  matches finished    %d of %d" % [finished, MATCHES])
	print("  goals               %.2f per match" % (float(goals) / MATCHES))
