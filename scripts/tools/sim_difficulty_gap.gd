extends SceneTree
## Throwaway check — with all three difficulties now sharing ONE evaluator and
## differing only in how often they act on it (see AIPlayer.decide_combo), is
## there still a real gap between them? Plays each pairing head to head, both
## sides, and reports goals. Hard should beat Easy clearly; if the three end
## up level, "tolerance" isn't buying enough separation and the percentages
## need widening.
## Run: godot --headless -s res://scripts/tools/sim_difficulty_gap.gd

const MATCHES_PER_SIDE := 6
const MAX_TURNS := 600
const GOALS_TO_WIN := 3

func _initialize() -> void:
	for pair in [["Hard", "Easy"], ["Hard", "Medium"], ["Medium", "Easy"]]:
		var a: String = pair[0]
		var b: String = pair[1]
		var a_goals := 0
		var b_goals := 0
		for i in range(MATCHES_PER_SIDE * 2):
			# Alternate who kicks off so neither side keeps that edge.
			var res := _play(a, b) if i % 2 == 0 else _play(b, a)
			if i % 2 == 0:
				a_goals += res[0]
				b_goals += res[1]
			else:
				a_goals += res[1]
				b_goals += res[0]
		print("%-6s vs %-6s over %d matches:  %d : %d" \
			% [a, b, MATCHES_PER_SIDE * 2, a_goals, b_goals])
	quit()


## `home_diff` kicks off. Returns [home_goals, away_goals].
func _play(home_diff: String, away_diff: String) -> Array:
	var ms := MatchState.new()
	ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", GOALS_TO_WIN)
	var turns := 0
	while turns < MAX_TURNS \
			and ms.score["HomeTeam"] < GOALS_TO_WIN and ms.score["AwayTeam"] < GOALS_TO_WIN:
		turns += 1
		var diff: String = home_diff if ms.current == "HomeTeam" else away_diff
		match ms.phase:
			MatchState.Phase.COMBO:
				var shoot := AIPlayer.decide_combo(ms, diff)
				if shoot == Vector2i(-1, -1):
					ms.forfeit()
					continue
				if AIPlayer.should_hold(ms, shoot):
					var hold := AIPlayer.decide_move(ms, diff)
					if hold.has("from"):
						ms.hold_and_move(hold["from"], hold["to"])
						continue
				var res := ms.execute_combo(shoot)
				if res["goal"]:
					ms.reset(Formations.home(), Formations.away(), Vector2i(3, 8), res["kickoff"])
			MatchState.Phase.MOVE:
				var mv := AIPlayer.decide_move(ms, diff)
				if not mv.has("from"):
					ms.forfeit()
					continue
				ms.do_move(mv["from"], mv["to"])
			MatchState.Phase.REMOVE:
				var cell := AIPlayer.decide_removal(ms, diff)
				if cell == Vector2i(-1, -1):
					ms.forfeit()
					continue
				ms.remove_figure(cell)
	return [ms.score["HomeTeam"], ms.score["AwayTeam"]]
