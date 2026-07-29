extends SceneTree
## Throwaway simulation — deleted after use.
## Runs many AI-vs-AI matches and, for every POSSESSION (a continuous spell
## where one team is the one entering Phase.COMBO), tracks whether it ends in:
##   - a GOAL for the possessing team,
##   - an OWN GOAL (possessor scores on itself -- counts as opponent benefit),
##   - a TURNOVER: the other team is the next one to enter Phase.COMBO with no
##     goal in between (recovered the ball, whether instantly via adjacency
##     after the shot/bonus-move, or later via one or more reactive moves).
## Run: godot --headless -s res://scripts/tools/sim_possession_stats.gd

const MATCHES := 10
const MAX_TURNS_PER_MATCH := 250

func _initialize() -> void:
	for difficulty in ["Hard", "Medium", "Easy"]:
		_run_set(difficulty)
	quit()


func _run_set(difficulty: String) -> void:
	var goals := 0
	var own_goals := 0
	var turnovers := 0
	var timeouts := 0
	var total_turns := 0
	var yellows := 0
	var reds := 0

	for m in range(MATCHES):
		var ms := MatchState.new()
		# win=50: unreachable within MAX_TURNS_PER_MATCH, so the turn cap (not
		# a match win) is what stops each run -- keeps sampling possessions
		# across many kickoffs instead of stopping after just 1-2 goals.
		ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 50)
		var possessor := "" # team that opened the CURRENTLY open possession, "" = none yet
		var turns := 0
		while turns < MAX_TURNS_PER_MATCH:
			turns += 1
			# Any action can trigger a stalling card via next_turn() ->
			# start_turn(); tally them by watching foul_count move.
			var fouls_before: int = ms.foul_count["HomeTeam"] + ms.foul_count["AwayTeam"]
			match ms.phase:
				MatchState.Phase.COMBO:
					if ms.current != possessor:
						if possessor != "":
							turnovers += 1 # previous possession ended with no goal
						possessor = ms.current
					var shoot := AIPlayer.decide_combo(ms, difficulty)
					if shoot == Vector2i(-1, -1):
						ms.forfeit()
						continue
					if AIPlayer.should_hold(ms, shoot):
						var hold := AIPlayer.decide_move(ms, difficulty)
						if hold.has("from"):
							ms.hold_and_move(hold["from"], hold["to"])
							continue
						# no legal hold move somehow -- shoot anyway (falls through)
					var res := ms.execute_combo(shoot)
					if res["goal"]:
						if res["scorer"] == possessor:
							goals += 1
						else:
							own_goals += 1
						possessor = ""
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
			if ms.foul_count["HomeTeam"] + ms.foul_count["AwayTeam"] > fouls_before:
				if ms.last_move_card == "red":
					reds += 1
				elif ms.last_move_card == "yellow":
					yellows += 1
		if possessor != "":
			timeouts += 1
		total_turns += turns

	var resolved := goals + own_goals + turnovers
	print("\n=== %s vs %s (%d matches, %d turns total) ===" % [difficulty, difficulty, MATCHES, total_turns])
	print("possessions resolved: %d (+ %d left open at the turn cap)" % [resolved, timeouts])
	if resolved > 0:
		print("  -> GOAL for possessor:      %5d  (%.1f%%)" % [goals, 100.0 * goals / resolved])
		print("  -> OWN GOAL (opp benefits): %5d  (%.1f%%)" % [own_goals, 100.0 * own_goals / resolved])
		print("  -> TURNOVER (opp recovers): %5d  (%.1f%%)" % [turnovers, 100.0 * turnovers / resolved])
	print("stalling cards: %d yellow, %d red  (over %d turns = 1 per %s turns)" \
		% [yellows, reds, total_turns,
			"never" if yellows + reds == 0 else str(total_turns / (yellows + reds))])
