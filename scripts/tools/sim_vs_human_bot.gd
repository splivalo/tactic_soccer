extends SceneTree
## Throwaway benchmark — head-to-head AIPlayer vs a scripted "human exploit"
## bot, to answer the only question that actually matters: how well does the
## AI hold up against the strategy a real player beat it with?
##
## Symmetric Hard-vs-Hard sims can't answer that — change both sides at once
## and the ratio stays ~50/50 by construction. So the opponent here is FIXED:
## it replays the pattern from a human's console log (2026-07-27), where they
## kept the ball for 12 straight shooting turns and the AI never touched it:
##   land every shot NEXT TO one of your own pieces and NOT next to any of
##   theirs, advancing when that's free.
## Run: godot --headless -s res://scripts/tools/sim_vs_human_bot.gd

const MATCHES_PER_SIDE := 8
const MAX_TURNS := 600
const GOALS_TO_WIN := 3

## Wall-clock cost of the AI's own thinking, accumulated across every real
## decision it makes in these matches — the number that decides whether a
## wider/deeper search is affordable on the mobile target (see
## AIPlayer.COMBO_SEARCH_BEAM).
static var think_usec_total: int = 0
static var think_calls: int = 0
static var think_usec_worst: int = 0


static func _timed(fn: Callable) -> Variant:
	var t0 := Time.get_ticks_usec()
	var out: Variant = fn.call()
	var dt := Time.get_ticks_usec() - t0
	think_usec_total += dt
	think_calls += 1
	think_usec_worst = maxi(think_usec_worst, dt)
	return out


func _initialize() -> void:
	var bot_goals := 0
	var ai_goals := 0
	var decided := 0
	# Play both sides: whoever kicks off has an edge, so split it evenly.
	for i in range(MATCHES_PER_SIDE * 2):
		var bot_team := "HomeTeam" if i % 2 == 0 else "AwayTeam"
		var res := _play_match(bot_team)
		bot_goals += res["bot"]
		ai_goals += res["ai"]
		if res["bot"] >= GOALS_TO_WIN or res["ai"] >= GOALS_TO_WIN:
			decided += 1
	print("\n=== human-exploit bot vs AIPlayer(Hard), %d matches ===" % (MATCHES_PER_SIDE * 2))
	print("  bot goals: %d" % bot_goals)
	print("  AI  goals: %d" % ai_goals)
	print("  matches reaching %d goals: %d/%d" % [GOALS_TO_WIN, decided, MATCHES_PER_SIDE * 2])
	print("  AI think time: %.1f ms avg, %.1f ms worst, over %d decisions (beam=%d)" \
		% [think_usec_total / 1000.0 / maxi(think_calls, 1), think_usec_worst / 1000.0,
			think_calls, AIPlayer.COMBO_SEARCH_BEAM])
	quit()


func _play_match(bot_team: String) -> Dictionary:
	var ms := MatchState.new()
	ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", GOALS_TO_WIN)
	var turns := 0
	while turns < MAX_TURNS \
			and ms.score["HomeTeam"] < GOALS_TO_WIN and ms.score["AwayTeam"] < GOALS_TO_WIN:
		turns += 1
		var is_bot: bool = ms.current == bot_team
		match ms.phase:
			MatchState.Phase.COMBO:
				var res: Dictionary = _bot_combo(ms) if is_bot else _ai_combo(ms)
				if res.is_empty():
					ms.forfeit()
					continue
				if res["goal"]:
					ms.reset(Formations.home(), Formations.away(), Vector2i(3, 8), res["kickoff"])
			MatchState.Phase.MOVE:
				var mv: Dictionary = _bot_move(ms) if is_bot \
					else _timed(func(): return AIPlayer.decide_move(ms, "Hard"))
				if not mv.has("from"):
					ms.forfeit()
					continue
				ms.do_move(mv["from"], mv["to"])
			MatchState.Phase.REMOVE:
				var cell: Vector2i = _bot_removal(ms) if is_bot else AIPlayer.decide_removal(ms, "Hard")
				if cell == Vector2i(-1, -1):
					ms.forfeit()
					continue
				ms.remove_figure(cell)
	var bot_score: int = ms.score[bot_team]
	var ai_score: int = ms.score[ms.opponent(bot_team)]
	return {"bot": bot_score, "ai": ai_score}


func _ai_combo(ms: MatchState) -> Dictionary:
	var shoot: Vector2i = _timed(func(): return AIPlayer.decide_combo(ms, "Hard"))
	if shoot == Vector2i(-1, -1):
		return {}
	if _timed(func(): return AIPlayer.should_hold(ms, shoot)):
		var hold: Dictionary = _timed(func(): return AIPlayer.decide_move(ms, "Hard"))
		if hold.has("from"):
			ms.hold_and_move(hold["from"], hold["to"])
			return {"goal": false, "kickoff": ""}
	return ms.execute_combo(shoot)


## The exploit, exactly as the human played it: single-touch (no pass chains),
## always score if you can, otherwise put the ball where YOUR man is next to
## it and THEIRS isn't.
func _bot_combo(ms: MatchState) -> Dictionary:
	var best_starter := Vector2i(-1, -1)
	var best_cell := Vector2i(-1, -1)
	var best := -INF
	for starter in ms.combo_starters():
		ms.begin(starter)
		for cell in ms.combo_shoot_targets():
			var v := _bot_shot_value(ms, starter, cell)
			if v > best:
				best = v
				best_starter = starter
				best_cell = cell
	if best_cell == Vector2i(-1, -1):
		return {}
	ms.begin(best_starter)
	return ms.execute_combo(best_cell)


func _bot_shot_value(ms: MatchState, shooter: Vector2i, cell: Vector2i) -> float:
	var team: String = ms.current
	if ms.is_opponent_goal(cell, team) and ms.in_opponent_half(shooter, team) and not ms.is_offside(shooter, team):
		return 1000000.0
	if ms.is_own_goal_cell(cell, team):
		return -1000000.0
	var v := -absi(cell.y - ms.opponent_goal_row(team)) * 250.0
	var own_adjacent := false
	for c in ms.pieces:
		var d := maxi(absi(c.x - cell.x), absi(c.y - cell.y))
		if d != 1:
			continue
		if ms.pieces[c]["team"] == team:
			own_adjacent = true
		else:
			v -= 2000.0 # theirs is next to it -> they get it first
	if not own_adjacent:
		v -= 2000.0 # nobody of ours next to it -> the ball is gone
	return v


## Chase: whichever piece can get closest to the ball.
func _bot_move(ms: MatchState) -> Dictionary:
	var best := {}
	var best_d := 1 << 30
	for cell in ms.move_from_cells():
		for to in ms.move_targets(cell):
			var d := maxi(absi(to.x - ms.ball.x), absi(to.y - ms.ball.y))
			if d < best_d:
				best_d = d
				best = {"from": cell, "to": to}
	return best


func _bot_removal(ms: MatchState) -> Vector2i:
	var fallback := Vector2i(-1, -1)
	for c in ms.own_cells():
		fallback = c
		if ms.pieces[c]["role"] != "gk":
			return c
	return fallback
