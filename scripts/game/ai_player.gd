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
		# Never worth a card/removal risk unless it's the goal above (this was
		# the "AI keeps getting carded" bug: it used to recycle the ball among
		# its own figures with no idea that was a foul) — see
		# MatchState.would_violate_stall.
		if state.would_violate_stall(cell):
			score -= 5000.0
	score -= _opponent_adjacent_count(state, cell) * 200.0 # don't hand it straight back
	score -= _nearest_own_distance(state, cell) * 3.0      # keep support close
	return score


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


## Cap on how many candidates get the EXPENSIVE defense lookahead
## (team_can_score_next, see _defense_score): unlimited sliding movement can
## give a single piece dozens of destinations, and decide_move considers
## every own piece — the full candidate list can run into the hundreds.
## Cheaply pre-rank by _move_base_score first and only spend the lookahead on
## the most promising handful; a candidate that's already a poor chase/
## reposition by that measure wouldn't win rank_pick over a safe one anyway.
const MAX_DEFENSE_CHECKS := 16

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
	candidates.sort_custom(func(a, b): return _move_base_score(state, a) > _move_base_score(state, b))
	var top: Array[Dictionary] = candidates.slice(0, MAX_DEFENSE_CHECKS)
	return _rank_pick(top, func(m): return _move_score(state, m), difficulty)


## Primarily "does this close the distance to the ball" (so the team can
## start combos) — plus a bonus for moving whichever figure is the team's
## live stalling anchor (see MatchState.stall_ref_id): that move both closes
## on the ball AND clears the anchor (see MatchState.do_move), unblocking free
## shooting on the team's next combo turn. Cheap — used both as decide_move's
## final score's base AND, on its own, to pre-filter candidates before the
## expensive defense lookahead (see MAX_DEFENSE_CHECKS).
static func _move_base_score(state: MatchState, m: Dictionary) -> float:
	var to: Vector2i = m["to"]
	var score: float = -maxi(absi(to.x - state.ball.x), absi(to.y - state.ball.y))
	if state.stall_ref_id[state.current] != -1 and m["from"] == state.stall_ref_cell[state.current]:
		score += 50.0
	return score


## _move_base_score plus a (usually dominant) bonus for a move that keeps the
## opponent OFF the scoreboard next turn (see _defense_score). Without that
## term the AI only ever chased the ball forward and never noticed it was
## leaving its own net wide open — this was the "conceded in a few moves
## because nobody defended" problem.
static func _move_score(state: MatchState, m: Dictionary) -> float:
	return _move_base_score(state, m) + _defense_score(state, m)


## How much move `m` helps keep the opponent OFF the scoreboard next turn:
## simulate it on a scratch copy (MatchState.clone_for_query), then check
## whether the opponent could still score on THEIR very next turn
## (team_can_score_next). A move that closes off every scoring path this
## finds scores far above one that still leaves one open — a flat bonus (not
## distance-scaled) since "safe" vs "exposed" is the whole question, not a
## matter of degree. Zero for every candidate only when the opponent already
## has an unstoppable shot no matter what the AI does here; the other
## _move_score terms still differentiate those.
static func _defense_score(state: MatchState, m: Dictionary) -> float:
	var sim: MatchState = state.clone_for_query()
	sim.pieces.erase(m["from"])
	sim.pieces[m["to"]] = state.pieces[m["from"]]
	if team_can_score_next(sim, state.opponent(state.current)):
		return 0.0
	return 400.0


## True if `team` could score on their VERY NEXT turn from `state` as it
## stands — i.e. does a legal path actually exist: a piece already adjacent
## to the ball, or one whose OWN first move reaches adjacency (only the FIRST
## of a team's 2 reactive moves can upgrade into a shot — see
## MatchState.do_move/_combo_from_reactive; reaching the ball on the 2nd/last
## one never grants a shot, so it isn't a real threat), then ANY pass chain
## from there to a clear, onside shot into an empty goal cell. An
## EXISTENCE check over a small graph (<=6 pieces/side) — cheap — not a
## search for the opponent's best move.
static func team_can_score_next(state: MatchState, team: String) -> bool:
	for start in _reach_ball_chains(state, team):
		if _chain_can_score(state, team, start):
			return true
	return false


## Every single-cell chain-start `team` could begin a combo from this turn:
## pieces already adjacent to the ball, plus — for each piece NOT adjacent —
## every cell its own first slide could reach that lands adjacent.
static func _reach_ball_chains(state: MatchState, team: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in state.pieces:
		if state.pieces[cell]["team"] != team:
			continue
		if maxi(absi(cell.x - state.ball.x), absi(cell.y - state.ball.y)) == 1:
			out.append(cell)
			continue
		for target in state.move_targets(cell):
			if maxi(absi(target.x - state.ball.x), absi(target.y - state.ball.y)) == 1:
				out.append(target)
	return out


const MAX_THREAT_CHAIN_DEPTH := 4 # safety cap on the DFS below, mirrors MAX_CHAIN_EXTENSIONS


## True if a combo starting at `chain_start` (hypothetical — the piece isn't
## actually moved there in `state`, see _reach_ball_chains) can reach a
## scoring shot, via this starter alone or any pass chain onward from it.
static func _chain_can_score(state: MatchState, team: String, chain_start: Vector2i) -> bool:
	var s: MatchState = state.clone_for_query()
	s.current = team
	s.phase = MatchState.Phase.COMBO
	s.chain = [chain_start]
	return _search_chain(s)


static func _search_chain(s: MatchState) -> bool:
	var shooter: Vector2i = s.chain[-1]
	for shoot_cell in s.combo_shoot_targets():
		if s.is_opponent_goal(shoot_cell, s.current) and not s.is_offside(shooter, s.current):
			return true
	if s.chain.size() >= MAX_THREAT_CHAIN_DEPTH:
		return false
	for next_cell in s.combo_pass_targets():
		s.chain.append(next_cell)
		if _search_chain(s):
			return true
		s.chain.pop_back()
	return false


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
