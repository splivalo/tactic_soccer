class_name AIPlayer
## Pure decision logic for the Single Player opponent — no nodes, no visuals,
## same spirit as MatchState (main.gd executes whatever this decides through
## its normal _do_combo/_apply_move/_remove_at, so the AI's moves animate
## exactly like a human's). Three difficulties, each a progressively less
## random / more forward-looking GREEDY heuristic — not a search/minimax; a
## proper look-ahead AI would be a much bigger project than this pass.

const MAX_AI_PASSES := {"Easy": 0, "Medium": 1, "Hard": 2}


## Builds the chain directly on `state` (via begin/extend, same calls a
## human's taps make) and returns the final shoot cell — caller passes that
## straight to main.gd's _do_combo(shoot_cell) for the real animation.
static func decide_combo(state: MatchState, difficulty: String) -> Vector2i:
	var starters := state.combo_starters()
	if starters.is_empty():
		return Vector2i(-1, -1)
	var starter := starters[randi() % starters.size()]
	if difficulty != "Easy":
		starter = _closest_to_goal(state, starters)
	state.begin(starter)

	var max_passes: int = MAX_AI_PASSES.get(difficulty, 0)
	for _i in range(max_passes):
		if difficulty != "Easy" and _best_shoot_target(state) != Vector2i(-1, -1):
			break # a good shot is already lined up — stop passing, take it
		var pass_targets := state.combo_pass_targets()
		if pass_targets.is_empty():
			break
		if difficulty == "Easy":
			if randf() < 0.5:
				break
			state.extend(pass_targets[randi() % pass_targets.size()])
		else:
			state.extend(_closest_to_goal(state, pass_targets))

	var shoot_targets := state.combo_shoot_targets()
	if shoot_targets.is_empty():
		return Vector2i(-1, -1) # shouldn't happen — rules guarantee one exists
	if difficulty == "Easy":
		return shoot_targets[randi() % shoot_targets.size()]
	var best := _best_shoot_target(state)
	return best if best != Vector2i(-1, -1) else _closest_to_goal(state, shoot_targets)


## Vector2i(-1,-1) if none of the current shoot targets scores right now
## (a real goal, not offside) — otherwise the scoring cell.
static func _best_shoot_target(state: MatchState) -> Vector2i:
	if state.chain.is_empty():
		return Vector2i(-1, -1)
	var shooter := state.chain[-1]
	for cell in state.combo_shoot_targets():
		if state.is_opponent_goal(cell, state.current) and state.in_opponent_half(shooter, state.current) \
				and not state.is_offside(shooter, state.current):
			return cell
	return Vector2i(-1, -1)


## Whichever candidate cell ends up CLOSEST to the opponent's goal row —
## used both to pick a starter/pass (advance the chain upfield) and as the
## non-Easy shoot fallback when no immediate goal is on offer.
static func _closest_to_goal(state: MatchState, candidates: Array[Vector2i]) -> Vector2i:
	var goal_row := state.opponent_goal_row(state.current)
	var best := candidates[0]
	var best_dist := 1 << 30
	for c in candidates:
		var d := absi(c.y - goal_row)
		if d < best_dist:
			best_dist = d
			best = c
	return best


## {"from": Vector2i, "to": Vector2i} — Easy is fully random; Medium mixes
## random with the "close the distance to the ball" heuristic; Hard always
## uses it (naturally converges the AI's pieces on the ball over successive
## MOVE turns, which is what lets them start a combo).
static func decide_move(state: MatchState, difficulty: String) -> Dictionary:
	var movable: Array[Vector2i] = []
	for cell in state.own_cells():
		if not state.move_targets(cell).is_empty():
			movable.append(cell)
	if movable.is_empty():
		return {}
	var use_heuristic := difficulty == "Hard" or (difficulty == "Medium" and randf() < 0.5)
	if not use_heuristic:
		var from: Vector2i = movable[randi() % movable.size()]
		var targets := state.move_targets(from)
		return {"from": from, "to": targets[randi() % targets.size()]}
	var best_from := Vector2i(-1, -1)
	var best_to := Vector2i(-1, -1)
	var best_dist := 1 << 30
	for from in movable:
		for to in state.move_targets(from):
			var d := maxi(absi(to.x - state.ball.x), absi(to.y - state.ball.y))
			if d < best_dist:
				best_dist = d
				best_from = from
				best_to = to
	return {"from": best_from, "to": best_to}


## Which of the carded team's own pieces to permanently remove. Easy picks
## any at random; Medium/Hard avoid sacrificing the goalkeeper when an
## outfield piece is available, and prefer whichever piece is currently
## farthest from the ball (least immediately useful to lose).
static func decide_removal(state: MatchState, difficulty: String) -> Vector2i:
	var candidates := state.own_cells()
	if candidates.is_empty():
		return Vector2i(-1, -1)
	if difficulty == "Easy":
		return candidates[randi() % candidates.size()]
	var outfield: Array[Vector2i] = []
	for c in candidates:
		if state.pieces[c]["role"] != "gk":
			outfield.append(c)
	var pool := outfield if not outfield.is_empty() else candidates
	var best: Vector2i = pool[0]
	var best_dist := -1
	for c in pool:
		var d := maxi(absi(c.x - state.ball.x), absi(c.y - state.ball.y))
		if d > best_dist:
			best_dist = d
			best = c
	return best
