class_name AIPlayer
## Pure decision logic for the Single Player opponent — no nodes, no visuals,
## same spirit as MatchState (main.gd executes whatever this decides through
## its normal _do_combo/_apply_move/_remove_at, so the AI's moves animate
## exactly like a human's).
##
## Difficulty is ONE lever, applied uniformly everywhere a decision is made
## (combo starter, each pass-or-shoot step, move, removal): every legal option
## is scored and ranked, then the AI's ACTUAL pick is rolled against the rank
## by difficulty — not "smarter heuristics" per difficulty, the exact same
## evaluation every time, just a different hit-rate on its own #1 choice:
##   Hard   = 100% the best move, every time — this is meant to be a real
##            challenge (like the 2006 original this is a clone of, which was
##            hard enough to beat that winning against it felt earned).
##   Medium = 90% best move, 10% second-best.
##   Easy   = 70% best move, 30% second- or third-best (whichever exist).
## Still a greedy per-decision evaluator, not a search/minimax — a proper
## look-ahead AI would be a much bigger project than this pass.

const MAX_CHAIN_EXTENSIONS := 4 # safety cap on pass-chain length; not a difficulty lever


## Ranks `candidates` by descending `score_fn(candidate)` and returns the ONE
## the AI actually plays, per the difficulty hit-rate documented above. This
## is the single place difficulty changes AI behaviour — every decision below
## funnels through it.
static func _rank_pick(candidates: Array, score_fn: Callable, difficulty: String) -> Variant:
	if candidates.size() == 1:
		return candidates[0]
	var scored := candidates.duplicate()
	scored.sort_custom(func(a, b): return score_fn.call(a) > score_fn.call(b))
	var roll := randf()
	var idx := 0
	match difficulty:
		"Hard":
			idx = 0
		"Medium":
			idx = 0 if roll < 0.9 else 1
		_: # Easy
			if roll < 0.7:
				idx = 0
			else:
				var lower: Array[int] = []
				if scored.size() > 1:
					lower.append(1)
				if scored.size() > 2:
					lower.append(2)
				idx = lower[randi() % lower.size()] if not lower.is_empty() else 0
	return scored[mini(idx, scored.size() - 1)]


## Builds the chain directly on `state` (via begin/extend, same calls a
## human's taps make) and returns the final shoot cell — caller passes that
## straight to main.gd's _do_combo(shoot_cell) for the real animation.
##
## Each step gathers EVERY legal action available right now — every shoot
## target (ends the combo) together with every pass target (extends it) — as
## one ranked list, so "the best move" always means the single
## highest-scoring option out of ALL of them, not "shoot if a goal's on, else
## always keep passing."
static func decide_combo(state: MatchState, difficulty: String) -> Vector2i:
	var starters := state.combo_starters()
	if starters.is_empty():
		return Vector2i(-1, -1)
	var starter: Vector2i = _rank_pick(starters, func(c): return _advance_score(state, c), difficulty)
	state.begin(starter)

	for _i in range(MAX_CHAIN_EXTENSIONS):
		var actions: Array[Dictionary] = []
		for c in state.combo_shoot_targets():
			actions.append({"cell": c, "shoot": true})
		for c in state.combo_pass_targets():
			actions.append({"cell": c, "shoot": false})
		if actions.is_empty():
			break
		var chosen: Dictionary = _rank_pick(actions,
			func(a): return _combo_action_score(state, a["cell"], a["shoot"]), difficulty)
		if chosen["shoot"]:
			return chosen["cell"]
		state.extend(chosen["cell"])

	# Extension cap hit — the rules guarantee a shoot target always exists once
	# a chain is open, so just take the best of whatever's on offer now.
	var shoot_targets := state.combo_shoot_targets()
	if shoot_targets.is_empty():
		return Vector2i(-1, -1) # shouldn't happen
	return _rank_pick(shoot_targets, func(c): return _combo_action_score(state, c, true), difficulty)


## Progress-toward-goal only — used to rank starters, where there's nothing
## to score yet besides "how far upfield is this."
static func _advance_score(state: MatchState, cell: Vector2i) -> float:
	return -absi(cell.y - state.opponent_goal_row(state.current))


## Scores ONE candidate action at the current chain decision point — either
## "shoot to `cell` now" (is_shoot=true, ending the combo) or "pass to `cell`"
## (extending the chain) — on a SHARED scale so shoot and pass options are
## ranked fairly against each other.
static func _combo_action_score(state: MatchState, cell: Vector2i, is_shoot: bool) -> float:
	var score: float = _advance_score(state, cell)
	if is_shoot:
		var shooter: Vector2i = state.chain[-1]
		if state.is_opponent_goal(cell, state.current) and state.in_opponent_half(shooter, state.current) \
				and not state.is_offside(shooter, state.current):
			score += 100000.0 # a real goal outweighs every other consideration
		# Never worth a card/removal risk unless it's the goal above — see
		# _violates_stall (this was the "AI keeps getting carded" bug: it used
		# to recycle the ball among its own figures with no idea that was a foul).
		if _violates_stall(state, cell):
			score -= 5000.0
	score -= _opponent_adjacent_count(state, cell) * 200.0 # don't hand it straight back
	score -= _nearest_own_distance(state, cell) * 3.0      # keep support close
	return score


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


## {"from": Vector2i, "to": Vector2i} — every legal (from,to) pair across every
## movable figure is scored and ranked together (see _move_score), same
## difficulty hit-rate as decide_combo.
static func decide_move(state: MatchState, difficulty: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for cell in state.own_cells():
		for to in state.move_targets(cell):
			candidates.append({"from": cell, "to": to})
	if candidates.is_empty():
		return {}
	return _rank_pick(candidates, func(m): return _move_score(state, m), difficulty)


## Primarily "does this close the distance to the ball" (so the team can
## start combos) — plus a bonus for moving whichever figure is the team's
## live stalling anchor (see MatchState.stall_ref_id): that move both closes
## on the ball AND clears the anchor (see MatchState.do_move), unblocking free
## shooting on the team's next combo turn — and a (usually dominant) bonus for
## stepping into an open shooting lane on the team's OWN goal right now (see
## _defense_score). Without that last term the AI only ever chased the ball
## forward and never noticed it was leaving its own net wide open — this was
## the "conceded in a few moves because nobody defended" problem.
static func _move_score(state: MatchState, m: Dictionary) -> float:
	var to: Vector2i = m["to"]
	var score: float = -maxi(absi(to.x - state.ball.x), absi(to.y - state.ball.y))
	if state.stall_ref_id[state.current] != -1 and m["from"] == state.stall_ref_cell[state.current]:
		score += 50.0
	score += _defense_score(state, to)
	return score


## How much moving to `to` would help defend the goal RIGHT NOW: a bonus for
## landing ON a CURRENTLY CLEAR straight lane (horizontal/vertical/diagonal —
## the same lines a shot can travel) between the ball and one of the team's
## own goal cells — i.e. stepping into the path of a shot that could score
## THIS INSTANT if left alone. Scaled by 1/distance-to-ball so a block right
## next to the ball (which also shuts every lane THROUGH that cell, not just
## this one) outweighs a block far down the same lane. Zero whenever no such
## open lane exists, so it never distorts ordinary ball-chasing play.
static func _defense_score(state: MatchState, to: Vector2i) -> float:
	var best := 0.0
	for gx in MatchState.GOAL_COLS:
		var goal_cell := Vector2i(gx, state.own_goal_row(state.current))
		if not Board.is_straight(state.ball, goal_cell):
			continue
		if not Board.path_clear(state.ball, goal_cell, state.pieces):
			continue # already blocked by someone, or no clean line to begin with
		if not (to in Board.cells_between(state.ball, goal_cell)):
			continue
		var d := maxi(absi(to.x - state.ball.x), absi(to.y - state.ball.y))
		best = maxf(best, 300.0 / maxf(float(d), 1.0))
	return best


## Which of the carded team's own pieces to permanently remove — every own
## figure is scored and ranked (see _removal_score), same difficulty hit-rate.
static func decide_removal(state: MatchState, difficulty: String) -> Vector2i:
	var candidates := state.own_cells()
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return _rank_pick(candidates, func(c): return _removal_score(state, c), difficulty)


## Never the goalkeeper if an outfield figure is available (a heavy penalty,
## not a hard exclusion — it still gets picked if it's the only figure left),
## and prefer whichever figure is currently farthest from the ball (least
## immediately useful to lose).
static func _removal_score(state: MatchState, cell: Vector2i) -> float:
	var score: float = maxi(absi(cell.x - state.ball.x), absi(cell.y - state.ball.y))
	if state.pieces[cell]["role"] == "gk":
		score -= 10000.0
	return score
