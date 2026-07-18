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
	return best if best != Vector2i(-1, -1) else _safe_shoot_target(state, shoot_targets)


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
## used to pick a starter/pass (advance the chain upfield).
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


## Non-Easy shoot fallback when no immediate goal is on offer: "closest to
## goal" ALONE used to blindly blast the ball to the far end of whatever lane
## was open. Two distinct ways that goes wrong, both scored here: (1) landing
## right next to (or among) the opponent's own defenders — an immediate,
## uncontested combo turn for them; (2) landing so far from EVERY one of the
## AI's own remaining pieces (a long clear lane lets one shot travel many
## cells) that the team can't realistically get back to it before the
## opponent does, even though nothing is guarding it yet. Guarded cells are
## excluded first (heaviest penalty), then cells far from any teammate are
## penalized, and only THEN does distance-to-goal break the tie — advancing
## is worthless if the ball can't be kept. Heaviest of all: a cell that would
## trip the stalling rule (shooting the ball back next to this team's own last
## shooter) is avoided outright — eating a yellow -> red -> sending-off for
## shuffling the ball around is far worse than conceding a little ground. This
## was the whole "the AI keeps getting cards on Hard" problem: it recycled the
## ball among its own figures with no idea that was a foul (see _violates_stall).
static func _safe_shoot_target(state: MatchState, candidates: Array[Vector2i]) -> Vector2i:
	var goal_row := state.opponent_goal_row(state.current)
	var best := candidates[0]
	var best_score := -INF
	for c in candidates:
		var stall := 1 if _violates_stall(state, c) else 0
		var guarded: int = _opponent_adjacent_count(state, c)
		var support := _nearest_own_distance(state, c)
		var dist := absi(c.y - goal_row)
		var score: float = -stall * 100000.0 - guarded * 1000.0 - support * 8.0 - dist
		if score > best_score:
			best_score = score
			best = c
	return best


## True if a shot LANDING on `cell` would trip the stalling rule for the team
## on the move — i.e. this team still has an active "last clean shot" anchor and
## the ball would come to rest within 1 cell of it (mirrors the exact test in
## MatchState.execute_combo). Only meaningful when a reference is live; a fresh
## kickoff or a just-moved shooter clears it (stall_ref_id == -1).
static func _violates_stall(state: MatchState, cell: Vector2i) -> bool:
	if state.stall_ref_id[state.current] == -1:
		return false
	var ref: Vector2i = state.stall_ref_cell[state.current]
	return maxi(absi(ref.x - cell.x), absi(ref.y - cell.y)) <= 1


## How many of the OPPONENT's pieces sit Chebyshev-adjacent to `cell` — i.e.
## how many of them could immediately start a combo if the ball landed there.
static func _opponent_adjacent_count(state: MatchState, cell: Vector2i) -> int:
	var count := 0
	for c in state.pieces:
		if state.pieces[c]["team"] != state.current and maxi(absi(c.x - cell.x), absi(c.y - cell.y)) == 1:
			count += 1
	return count


## Chebyshev distance from `cell` to the NEAREST of the current team's own
## pieces — how far the team would actually have to travel to reclaim/protect
## the ball if it landed there (the shooter itself counts, so this is at
## minimum "how many cells did this shot just travel").
static func _nearest_own_distance(state: MatchState, cell: Vector2i) -> int:
	var best := 1 << 30
	for c in state.pieces:
		if state.pieces[c]["team"] == state.current:
			var d := maxi(absi(c.x - cell.x), absi(c.y - cell.y))
			if d < best:
				best = d
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
	# Hard only: if a stalling anchor is still live (this team's last clean
	# shooter hasn't moved since), converge with THAT figure — moving it both
	# closes on the ball AND clears the anchor (see MatchState.do_move), so the
	# next combo can shoot freely instead of risking a foul. Falls through to
	# the normal "closest figure to the ball" search when it can't legally move.
	var sources := movable
	if difficulty == "Hard" and state.stall_ref_id[state.current] != -1:
		var ref_cell: Vector2i = state.stall_ref_cell[state.current]
		if ref_cell in movable:
			sources = [ref_cell] as Array[Vector2i]
	var best_from := Vector2i(-1, -1)
	var best_to := Vector2i(-1, -1)
	var best_dist := 1 << 30
	for from in sources:
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
