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
## Medium/Easy's "best move" is still a greedy per-decision evaluator (one
## step at a time, see decide_combo's fallback loop). Hard's "best move" is
## not: decide_combo runs _search_best_combo, a real backtracking search over
## the WHOLE pass chain (see MAX_CHAIN_EXTENSIONS), so Hard can commit to a
## pass that doesn't look best right this instant because it sets up a
## guaranteed goal a couple of touches later — a plain greedy walk would've
## abandoned that line at the first step. _combo_action_score also checks,
## for every shot candidate, whether it hands the opponent an immediate
## scoring line back (see _post_shot_threat_penalty) — this applies to every
## difficulty, not just Hard, since it's the same "is this actually a good
## shot" question the greedy walk was already asking, just answered better.

const MAX_CHAIN_EXTENSIONS := 4 # safety cap on pass-chain length; not a difficulty lever


## Ranks `candidates` by descending `score_fn(candidate)` and returns the ONE
## the AI actually plays, per the difficulty hit-rate documented above. This
## is the single place difficulty changes AI behaviour — every decision below
## funnels through it.
static func _rank_pick(candidates: Array, score_fn: Callable, difficulty: String) -> Variant:
	if candidates.size() == 1:
		return candidates[0]
	# Score each candidate EXACTLY ONCE up front, then sort by the cached
	# value — sort_custom's comparator gets called many times per element
	# (O(n log n) comparisons, most elements involved in several), so calling
	# score_fn straight from the comparator re-evaluates the SAME candidate
	# over and over. That was harmless while every score_fn here was a few
	# arithmetic ops, but once one of them started doing real recursive search
	# work (hundreds of ms), re-scoring it a dozen-plus times during one sort
	# turned a single AI decision into an 11-SECOND freeze — this is the
	# actual fix for that, not a micro-optimization.
	var scores: Array[float] = []
	for c in candidates:
		scores.append(score_fn.call(c))
	var order: Array[int] = []
	for i in candidates.size():
		order.append(i)
	order.sort_custom(func(i, j): return scores[i] > scores[j])
	var scored: Array = []
	for i in order:
		scored.append(candidates[i])
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

	if difficulty == "Hard":
		var best := _search_best_combo(state)
		if not best.is_empty():
			state.begin(best["path"][0])
			for i in range(1, best["path"].size()):
				state.extend(best["path"][i])
			return best["shoot_cell"]
		# Falls through to the greedy walk below only if the search somehow
		# found nothing to play (shouldn't happen — combo_starters() was
		# non-empty and the rules guarantee a shoot target once a chain is
		# open — but better to fall back than return a dead turn).

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


## Whether to HOLD (skip shooting — see MatchState.hold_and_move) instead of
## actually taking `shoot_cell`, which decide_combo has already committed to
## `state.chain` by the time this is called. Shooting is no longer mandatory
## (2026-07-22, "1 action per turn: shoot or hold" redesign) — this is the
## decision layer on top of decide_combo that main.gd's AI turn checks before
## calling execute_combo. Never holds a real goal (never pass that up).
## Otherwise holds when `shoot_cell` looks risky: an opponent piece already
## sits adjacent to where it would land, so an immediate reply is live — a
## light, non-recursive stand-in for _post_shot_threat_penalty's full search,
## since this only needs a yes/no. Holding no longer risks a card by itself
## (see MatchState's "cards / stalling" doc comment — stalling is now caught
## by position-repetition, not a hold streak), so there's nothing here to
## stop the AI from holding several turns running if each one keeps scoring
## as risky.
static func should_hold(state: MatchState, shoot_cell: Vector2i) -> bool:
	var shooter: Vector2i = state.chain[-1]
	var is_goal := state.is_opponent_goal(shoot_cell, state.current) and state.in_opponent_half(shooter, state.current) \
		and not state.is_offside(shooter, state.current)
	if is_goal:
		return false
	for c in state.pieces:
		if state.pieces[c]["team"] != state.current and maxi(absi(c.x - shoot_cell.x), absi(c.y - shoot_cell.y)) == 1:
			return true
	return false


## Caps branching at every fork of the Hard combo search below — both the
## starter choice and every pass fork get pre-ranked by the cheap heuristic
## first (_advance_score / _combo_action_score) and only the top few are
## actually recursed into. Node count grows as roughly BEAM^depth (depth up
## to MAX_CHAIN_EXTENSIONS+1 = 5), and every SHOOT option at EVERY node gets
## the full _post_shot_threat_penalty check (a real DFS via
## team_can_score_next, NOT cheap) — at BEAM=6 that's ~9000 nodes and
## measured ~350-450ms per decide_combo call on a desktop i9 — see
## _rank_pick's doc comment for the other half of that freeze bug. At 3, node
## count drops roughly 25x for a low-tens-of-ms search — this is the mobile
## target platform (see project overview), so "fast on a desktop" was never
## actually the bar. A fork that doesn't even rank in the top 3 by the cheap
## heuristic essentially never wins the full search anyway.
const COMBO_SEARCH_BEAM := 2


## Hard-only (see decide_combo): explores the FULL combo tree via
## backtracking on one scratch clone — every starter, then at every depth up
## to MAX_CHAIN_EXTENSIONS every pass fork, each ending in every shoot option
## — and returns the single best-scoring complete path, not just the
## locally-best next step (see _search_combo_step). {} if there is nothing to
## play (shouldn't happen once combo_starters() is non-empty — the caller
## falls back to the greedy walk in that case).
## Return shape: {"path": Array[Vector2i], "shoot_cell": Vector2i} — path is
## the starter followed by every intermediate pass, exactly what the caller
## needs to replay via begin()/extend() on the real state.
static func _search_best_combo(state: MatchState) -> Dictionary:
	var starters := state.combo_starters()
	if starters.is_empty():
		return {}
	var search: MatchState = state.clone_for_query()
	var best := {"path": [] as Array[Vector2i], "shoot": Vector2i(-1, -1), "value": -INF}
	starters.sort_custom(func(a, b): return _advance_score(state, a) > _advance_score(state, b))
	for starter in starters.slice(0, COMBO_SEARCH_BEAM):
		search.chain = [starter]
		var result := _search_combo_step(search)
		if result["value"] > best["value"]:
			best = result
	if best["shoot"] == Vector2i(-1, -1):
		return {}
	return {"path": best["path"], "shoot_cell": best["shoot"], "value": best["value"]}


## One node of the backtracking search: `search.chain` is the path so far.
## Tries every shoot target (a leaf — ends the chain right here) and, below
## the extension cap, every pass target (recurses one deeper), and returns
## the best {"path","shoot","value"} found anywhere under this node.
## `search.chain` is restored to its value on entry before returning either
## way (append/pop_back around the recursive call), so the caller's own loop
## sees a clean chain to try its next sibling from.
static func _search_combo_step(search: MatchState) -> Dictionary:
	var best := {"path": search.chain.duplicate(), "shoot": Vector2i(-1, -1), "value": -INF}
	# Shoot targets are beam-limited too, by the CHEAP _advance_score alone
	# (no threat check) — a wide-open board can offer 15-20+ shoot cells at a
	# single node, and _combo_action_score's threat check (_post_shot_threat_
	# penalty -> team_can_score_next) measured ~1ms EACH, not the "cheap, no
	# recursion" it looked like on paper — evaluating all of them at every
	# node was the actual multi-hundred-ms cost (see COMBO_SEARCH_BEAM's doc
	# comment). Safe to pre-filter this way: a goal cell is the opponent's
	# goal row, i.e. the maximum possible _advance_score (0, unbeatable), so
	# it always sorts first and is never at risk of being cut.
	var shoot_targets := search.combo_shoot_targets()
	shoot_targets.sort_custom(func(a, b): return _advance_score(search, a) > _advance_score(search, b))
	for cell in shoot_targets.slice(0, COMBO_SEARCH_BEAM):
		var v: float = _combo_action_score(search, cell, true)
		if v > best["value"]:
			best = {"path": search.chain.duplicate(), "shoot": cell, "value": v}
	if search.chain.size() - 1 < MAX_CHAIN_EXTENSIONS:
		# Passes keep the fuller _combo_action_score for pre-ranking (still
		# cheap — is_shoot=false skips the threat check entirely) rather than
		# bare _advance_score, so a pass into an opponent-surrounded cell
		# doesn't out-rank a slightly-less-advanced but safer one before the
		# beam cut even gets a chance to compare their real recursive values.
		var pass_targets := search.combo_pass_targets()
		pass_targets.sort_custom(func(a, b): return _combo_action_score(search, a, false) > _combo_action_score(search, b, false))
		for cell in pass_targets.slice(0, COMBO_SEARCH_BEAM):
			search.chain.append(cell)
			var deeper := _search_combo_step(search)
			if deeper["value"] > best["value"]:
				best = deeper
			search.chain.pop_back()
	return best


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
		var is_goal := state.is_opponent_goal(cell, state.current) and state.in_opponent_half(shooter, state.current) \
				and not state.is_offside(shooter, state.current)
		if is_goal:
			score += 100000.0 # a real goal outweighs every other consideration
		# An own goal was NEVER explicitly penalized before — it only read as
		# "bad" through the incidental _advance_score term (your own goal is
		# about as far as possible from the OPPONENT's goal row). That's not
		# reliable: every other term below (_opponent_adjacent_count,
		# _post_shot_threat_penalty) can rack up bigger penalties on forward
		# options when the team is under real pressure (surrounded, no safe
		# advance), which could let conceding an actual
		# goal outscore a merely-risky one — a human reported exactly this on
		# Easy: the AI autogol'd rather than take a contested forward shot.
		# Own-goal cells stay legal shoot targets (see MatchState.combo_shoot_
		# targets' own comment — "a deliberate/accidental autogol" is real
		# rules-legal), so this can't be an outright ban, just make it
		# properly the worst possible outcome short of a genuine dead end.
		if state.is_own_goal_cell(cell, state.current):
			score -= 200000.0
		if not is_goal:
			score -= _post_shot_threat_penalty(state, cell)
	score -= _opponent_adjacent_count(state, cell) * 200.0 # don't hand it straight back
	# Keep support close. History: 3.0 (original) outweighed _advance_score's
	# 1-point-per-cell reward on almost every real advance, so the AI always
	# "won" by nudging the ball forward the absolute minimum and stopping —
	# the reproducible bug behind a human just spamming End Move seeing the
	# AI shoot the same 1-cell hop forever. Dropped to 0.5 to fix that, which
	# worked under the OLD unlimited-movement rules — but under the capped
	# MAX_MOVE_RANGE (recovery is slow now), 0.5 swung too far the other way:
	# Hard-only simulation (measure_possession_abandon.gd) showed 20% of
	# shots landing >3 tiles from the nearest own piece. Re-measured across
	# 0.5/1.0/1.5/2.0/3.0 (Hard-only, since Hard's ~100% top-pick adherence
	# is the only difficulty that isolates the scoring weight from selection
	# noise): abandonment falls off a cliff between 1.0 (20%) and 1.5 (3%),
	# so 1.5 is the new default — fixes the abandonment problem while
	# staying well short of 3.0's known "won't advance" failure mode.
	score -= _nearest_own_distance(state, cell) * 1.5
	return score


## How exposed a shot landing on `cell` leaves the team: previews the ball
## there (a shot only moves the ball, never a piece, so nothing else needs
## touching) and asks whether the OPPONENT could then score on THEIR very
## next turn — the same deep existence check (team_can_score_next) that
## decide_move's _defense_score already uses to keep a team from wandering
## out of position. Without this a shot that "advances the ball" but hands
## the opponent a free reply scored no worse than a genuinely safe one — this
## was the concrete gap that let a human beat Hard in a handful of turns: the
## AI happily walked into shots a defender never has to work for, then found
## nothing in its OWN mandatory move able to fix the exposure it had just
## created. Flat penalty (exposed vs. safe is the real question here, not a
## matter of degree) — skipped entirely for an actual goal, see the caller.
static func _post_shot_threat_penalty(state: MatchState, cell: Vector2i) -> float:
	var saved_ball := state.ball
	state.ball = cell
	var exposed := team_can_score_next(state, state.opponent(state.current))
	state.ball = saved_ball
	return 8000.0 if exposed else 0.0


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
## (team_can_score_next, see _defense_score): decide_move considers every own
## piece times every direction, so the full candidate list can still run
## into the dozens even with movement capped at MatchState.MAX_MOVE_RANGE.
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
## start a combo on ITS OWN next turn — reaching the ball no longer grants an
## immediate same-turn combo, see MatchState.do_move). Cheap — used both as
## decide_move's final score's base AND, on its own, to pre-filter candidates
## before the expensive defense lookahead (see MAX_DEFENSE_CHECKS).
static func _move_base_score(state: MatchState, m: Dictionary) -> float:
	var to: Vector2i = m["to"]
	return -maxi(absi(to.x - state.ball.x), absi(to.y - state.ball.y))


## _move_base_score plus a (usually dominant) bonus for a move that keeps the
## opponent OFF the scoreboard next turn (see _defense_score). Without the
## defense term the AI only ever chased the ball forward and never noticed it
## was leaving its own net wide open — this was the "conceded in a few moves
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
## stands — i.e. does `team` already have a figure adjacent to the ball (so
## start_turn() opens Phase.COMBO for them), and from there ANY pass chain to
## a clear, onside shot into an empty goal cell. Reaching the ball via a
## reactive MOVE no longer grants a same-turn shot at all (see MatchState.
## do_move) — a team that doesn't already have the ball simply cannot score
## next turn, full stop. An EXISTENCE check over a small graph (<=6
## pieces/side) — cheap — not a search for the opponent's best move.
static func team_can_score_next(state: MatchState, team: String) -> bool:
	for start in state.pieces:
		if state.pieces[start]["team"] == team and maxi(absi(start.x - state.ball.x), absi(start.y - state.ball.y)) == 1:
			if _chain_can_score(state, team, start):
				return true
	return false


const MAX_THREAT_CHAIN_DEPTH := 4 # safety cap on the DFS below, mirrors MAX_CHAIN_EXTENSIONS


## True if a combo starting at `chain_start` can reach a scoring shot, via
## this starter alone or any pass chain onward from it.
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
