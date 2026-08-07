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
## "Best move" means the same thing at every difficulty (2026-07-27): every
## one of them runs _search_best_combo, a real backtracking search over the
## WHOLE pass chain (see MAX_CHAIN_EXTENSIONS), so any of them can commit to
## a pass that doesn't look best right this instant because it sets up a
## guaranteed goal a couple of touches later. Difficulty never makes the AI
## evaluate worse, only act on its own findings less reliably — and exactly
## once per turn, not compounding at every link of the chain.
## _combo_action_score also checks,
## for every shot candidate, whether it hands the opponent an immediate
## scoring line back (see _post_shot_threat_penalty) — this applies to every
## difficulty, not just Hard, since it's the same "is this actually a good
## shot" question the greedy walk was already asking, just answered better.

const MAX_CHAIN_EXTENSIONS := 4 # safety cap on pass-chain length; not a difficulty lever

## How often Medium/Easy actually play the line the search picked as best —
## their whole difference from Hard, which has no tolerance for error at all
## (see _rank_pick). 2026-07-27: these were 0.9/0.7 and produced no measurable
## gap once every difficulty shared one evaluator — Medium finished LEVEL with
## Hard head to head (24:22 over 12 matches). One slightly-worse shot in ten,
## chosen from a list where the runner-up is usually nearly as good, simply
## isn't enough to lose a match. Retuned against sim_difficulty_gap.gd, which
## is the tool to re-run if these are ever touched again.
const TOP_PICK_MEDIUM := 0.65
const TOP_PICK_EASY := 0.30


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
			idx = 0 if roll < TOP_PICK_MEDIUM else 1
		_: # Easy
			if roll < TOP_PICK_EASY:
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
	# ONE brain for every difficulty (2026-07-27): the same full-tree search
	# runs regardless, and difficulty only decides how often the AI actually
	# plays what that search found — Hard 0% tolerance for error, Medium/Easy
	# progressively more (see _rank_pick). Until now Hard alone got the
	# search while Medium/Easy ran a separate, dumber greedy walk AND rolled
	# the difficulty dice at every link of the chain, so their mistakes
	# compounded several times per turn: they weren't "the same player making
	# the occasional error", they were a different, worse player. Every
	# improvement to the evaluation now lands on all three difficulties
	# equally, which is the whole point of having one evaluator.
	var candidates := _search_best_combo(state)
	if candidates.is_empty():
		return Vector2i(-1, -1) # rules guarantee a shoot target once a chain opens
	var chosen: Dictionary = _rank_pick(candidates, func(c): return c["value"], difficulty)
	state.begin(chosen["path"][0])
	for i in range(1, chosen["path"].size()):
		state.extend(chosen["path"][i])
	return chosen["shoot"]


## Whether to HOLD (skip shooting — see MatchState.hold_and_move) instead of
## actually taking `shoot_cell`, which decide_combo has already committed to
## `state.chain` by the time this is called. Shooting is no longer mandatory
## (2026-07-22, "1 action per turn: shoot or hold" redesign) — this is the
## decision layer on top of decide_combo that main.gd's AI turn checks before
## calling execute_combo. Never holds a real goal (never pass that up).
##
## 2026-07-27: this used to be a crude yes/no ("is an opponent already
## adjacent to shoot_cell") with no real comparison to what holding would
## actually be worth — it could never recognize "this shot is merely
## mediocre, and consolidating first is the better play," only "this exact
## shot is an immediate disaster." Now it scores the shot exactly like the
## combo search would (_combo_action_score) and compares it against the best
## available hold (_best_hold_value), on the same point scale — a genuine
## "is advancing worth it right now, or is this a turn to build up instead"
## comparison, which is what taking a bad Hard AI apart by patiently holding
## and repositioning support actually exploits (see
## scripts/tools/sim_possession_stats.gd).
static func should_hold(state: MatchState, shoot_cell: Vector2i) -> bool:
	var shooter: Vector2i = state.chain[-1]
	var is_goal := state.is_opponent_goal(shoot_cell, state.current) and state.in_opponent_half(shooter, state.current) \
		and not state.is_offside(shooter, state.current)
	if is_goal:
		return false
	var shoot_value := _combo_action_score(state, shoot_cell, true)
	return _best_hold_value(state) > shoot_value


## Best achievable value from declining to shoot and repositioning one figure
## instead (see hold_and_move) — every own figure, every reachable cell,
## scored by _hold_action_score, same shared "how many opponents in play,
## how exposed does this leave us" language _combo_action_score uses, so
## should_hold's comparison is apples-to-apples. -INF if somehow no move
## exists (shouldn't happen — MAX_MOVE_RANGE always leaves at least the
## figure's own current cell's neighbors reachable for any real formation).
static func _best_hold_value(state: MatchState) -> float:
	var candidates: Array[Dictionary] = []
	for cell in state.own_cells():
		for to in state.move_targets(cell):
			candidates.append({"from": cell, "to": to})
	if candidates.is_empty():
		return -INF
	# Same expense/cap discipline as decide_move (see MAX_DEFENSE_CHECKS):
	# _hold_action_score clones the state AND runs team_can_score_next (a real
	# DFS) per candidate, and every own piece times every direction runs into
	# the dozens — this is called on EVERY combo turn, on a mobile target, and
	# an uncapped version of exactly this pattern is what once turned a single
	# AI decision into an 11-second freeze (see _rank_pick). Pre-rank cheaply
	# by "does this bring a man nearer the ball" and only pay the real price
	# on the most promising handful.
	candidates.sort_custom(func(a, b):
		return _cheby(a["to"], state.ball) < _cheby(b["to"], state.ball))
	var best := -INF
	for m in candidates.slice(0, MAX_DEFENSE_CHECKS):
		var v := _hold_action_score(state, m["from"], m["to"])
		if v > best:
			best = v
	return best


static func _cheby(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Value of moving `from` -> `to` INSTEAD of shooting (the ball stays exactly
## where it is): starts from the SAME baseline a shot would (_advance_score of
## the ball's cell — unchanged here, since a hold never moves the ball), then
## applies the same threat/adjacency/support terms _combo_action_score does,
## with the same 0-baseline/negative-if-bad sign convention as
## _post_shot_threat_penalty (NOT a positive bonus for being safe — a shot
## that's merely safe scores near its plain _advance_score, not thousands of
## points above one that's also safe; that mismatch was the 2026-07-27 bug
## that made the AI hold on almost every turn, see should_hold's doc comment).
##
## The handover term is the one that really decides this: a hold leaves the
## ball EXACTLY where it is, so if an opponent is already standing next to it,
## their turn opens with team_has_ball() true and they simply take it —
## holding there is a guaranteed giveaway, not a safe option. It has to cost
## the same SHOT_HANDOVER_PENALTY a shot pays for the same outcome, or the
## comparison is rigged: at the old flat 200 (vs a shot's 2000), declining to
## shoot looked cheap precisely when it was worst, and a human's log showed
## the AI gifting them possession twice in one match exactly this way.
static func _hold_action_score(state: MatchState, from: Vector2i, to: Vector2i) -> float:
	var sim: MatchState = state.clone_for_query()
	sim.pieces.erase(from)
	sim.pieces[to] = state.pieces[from]
	var score: float = _advance_score(state, state.ball) * ADVANCE_WEIGHT
	if team_can_score_next(sim, state.opponent(state.current)):
		score -= 8000.0
	if _opponent_adjacent_count(sim, state.ball) > 0:
		score -= SHOT_HANDOVER_PENALTY
	score -= _nearest_own_distance(sim, state.ball) * 1.5
	return score


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


## Explores the FULL combo tree via backtracking on one scratch clone — every
## starter, then at every depth up to MAX_CHAIN_EXTENSIONS every pass fork,
## each ending in every shoot option (see _search_combo_step) — and returns
## EVERY complete line it evaluated, best first. Returning the whole ranked
## list rather than just the winner is what lets a single search serve all
## three difficulties: decide_combo hands it to _rank_pick, which drops to
## the 2nd- or 3rd-best line as often as the difficulty says it should.
## Empty only if there is nothing to play (combo_starters() was empty).
## Entry shape: {"path": Array[Vector2i], "shoot": Vector2i, "value": float} —
## path is the starter followed by every intermediate pass, exactly what the
## caller needs to replay via begin()/extend() on the real state.
static func _search_best_combo(state: MatchState) -> Array[Dictionary]:
	var starters := state.combo_starters()
	if starters.is_empty():
		return []
	var search: MatchState = state.clone_for_query()
	var out: Array[Dictionary] = []
	starters.sort_custom(func(a, b): return _advance_score(state, a) > _advance_score(state, b))
	for starter in starters.slice(0, COMBO_SEARCH_BEAM):
		search.chain = [starter]
		_search_combo_step(search, out)
	out.sort_custom(func(a, b): return a["value"] > b["value"])
	# Collapse to one line per SHOOT CELL, keeping the best way to reach each.
	# The tree produces several routes that finish on the same cell (different
	# starter, different pass order), and they are the same decision as far as
	# the board is concerned. Left in, they crowd the ranking with near-clones,
	# which quietly broke difficulty: Medium's "10% of the time take the
	# second-best line" was usually picking a cosmetic variant of the best one,
	# and it measured level with Hard (21:23 head to head) instead of below it.
	# Deduplicated, rank #2 is a genuinely different shot, so a mistake costs
	# what it should.
	var seen := {}
	var distinct: Array[Dictionary] = []
	for entry in out:
		var cell: Vector2i = entry["shoot"]
		if seen.has(cell):
			continue
		seen[cell] = true
		distinct.append(entry)
	return distinct


## One node of the backtracking search: `search.chain` is the path so far.
## Appends every shoot target it evaluates (a leaf — the chain ends there) to
## `out` and, below the extension cap, recurses one deeper per pass target,
## so `out` ends up holding every complete line in the tree. `search.chain`
## is restored to its value on entry before returning (append/pop_back around
## the recursive call), so the caller's own loop sees a clean chain to try
## its next sibling from.
static func _search_combo_step(search: MatchState, out: Array[Dictionary]) -> void:
	# Shoot targets are beam-limited too — a wide-open board can offer 15-20+
	# at a single node, and _combo_action_score's threat check
	# (_post_shot_threat_penalty -> team_can_score_next) measured ~1ms EACH,
	# not the "cheap, no recursion" it looked like on paper — evaluating all
	# of them at every node was the actual multi-hundred-ms cost (see
	# COMBO_SEARCH_BEAM's doc comment).
	#
	# The pre-filter therefore skips ONLY that DFS (skip_threat) and keeps
	# every other term. 2026-07-27: it used to rank by bare _advance_score,
	# i.e. purely "how far upfield does this land" — so the only shots that
	# ever reached full evaluation were the two most advanced ones, and
	# SHOT_HANDOVER_PENALTY (added the same day) could never save a candidate
	# it had already discarded. A human's log caught the result exactly: from
	# (0,6) the AI fired the ball to (5,9) on the opponent's goal line with
	# its nearest man 4 cells away and a 2-cell move to close it, and the
	# opposing keeper simply stepped across and took it. Ranking by the same
	# scoring the search itself uses fixes that at the root.
	var shoot_targets := search.combo_shoot_targets()
	var ranked: Array[Dictionary] = []
	for cell in shoot_targets:
		ranked.append({"cell": cell, "cheap": _combo_action_score(search, cell, true, true)})
	ranked.sort_custom(func(a, b): return a["cheap"] > b["cheap"])
	for entry in ranked.slice(0, COMBO_SEARCH_BEAM):
		var cell: Vector2i = entry["cell"]
		out.append({
			"path": search.chain.duplicate(),
			"shoot": cell,
			"value": _combo_action_score(search, cell, true),
		})
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
			_search_combo_step(search, out)
			search.chain.pop_back()


## Progress-toward-goal only — used to rank starters, where there's nothing
## to score yet besides "how far upfield is this."
static func _advance_score(state: MatchState, cell: Vector2i) -> float:
	return -absi(cell.y - state.opponent_goal_row(state.current))


## Scores ONE candidate action at the current chain decision point — either
## "shoot to `cell` now" (is_shoot=true, ending the combo) or "pass to `cell`"
## (extending the chain) — on a SHARED scale so shoot and pass options are
## ranked fairly against each other.
##
## `skip_threat` omits _post_shot_threat_penalty, the one genuinely expensive
## term (a real DFS, ~1ms a call). Everything else here is plain adjacency/
## distance arithmetic, so the skipped version is the honest cheap PROXY of
## the full score — which is exactly what a beam pre-filter needs, so that
## the candidates it keeps are the ones the full evaluation would also like
## (see _search_combo_step).
static func _combo_action_score(state: MatchState, cell: Vector2i, is_shoot: bool,
		skip_threat: bool = false) -> float:
	var score: float = _advance_score(state, cell) * ADVANCE_WEIGHT
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
			if not skip_threat:
				score -= _post_shot_threat_penalty(state, cell)
				score += _own_threat_bonus(state, cell) # build an attack, don't just advance
			score -= _shot_handover_penalty(state, cell)
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


## Points per cell of progress toward the opponent's goal in
## _combo_action_score. 2026-07-27: raw _advance_score is 1 point per cell,
## which was worth essentially NOTHING next to the risk terms beside it
## (hundreds to thousands) — the AI was scored almost purely on what could go
## wrong, so every added safety term pushed it further toward doing nothing at
## all (at 1/cell, adding SHOT_HANDOVER_PENALTY froze Hard-vs-Hard into a
## goalless 1500-turn stalemate). Wanting the ball upfield has to be able to
## outbid caution sometimes, or "smart" just means "paralyzed": at 250, a
## SHOT_HANDOVER_PENALTY (2000) is worth ~8 cells of progress, so the AI will
## concede possession only for a genuinely decisive advance, and its quarter
## rate (500, shooter can chase it down) for a routine 2-cell one.
const ADVANCE_WEIGHT := 250.0

## Weight of simply LOSING THE BALL with this shot — see
## _shot_handover_penalty. Deliberately below _post_shot_threat_penalty's 8000
## (conceding an actual scoring chance is still worse than a plain handover)
## and far below a real goal's 100000, but far ABOVE the per-cell terms: who
## has the ball next turn is a yes/no outcome, not a matter of degree, and
## scoring it as a gentle slope was exactly the bug (see below).
const SHOT_HANDOVER_PENALTY := 2000.0


## Does this shot hand the ball to the opponent? Possession is NOT exclusive
## (MatchState.team_has_ball is plain adjacency) and turn order decides who
## actually plays it, so the real question for a shot is: at the start of each
## side's next turn, who is standing next to where the ball lands?
##   - An opponent adjacent to `cell` => THEIR turn comes first and they open
##     a combo on it: the ball is gone. Full penalty.
##   - Otherwise one of our own pieces adjacent => we keep playing it on our
##     own next turn no matter what they do in between. No penalty.
##   - Otherwise the shooter alone can still chase it down with its bonus
##     move (execute_combo grants exactly one, restricted to the shooter since
##     2026-07-27) => usually recoverable. Quarter penalty.
##   - Otherwise nobody is near it: a genuine giveaway. Full penalty.
## 2026-07-27: before this, "stay near your own support" was ONLY the gentle
## _nearest_own_distance slope below (1.5/cell), which a mere 2 cells of
## _advance_score could outbid — so the AI routinely fired the ball into
## space and handed over possession for a sliver of forward progress. A human
## beat Hard by doing the exact opposite, every single turn: land it next to
## your own man and away from theirs, and the AI never touches the ball again.
static func _shot_handover_penalty(state: MatchState, cell: Vector2i) -> float:
	if _opponent_adjacent_count(state, cell) > 0:
		return SHOT_HANDOVER_PENALTY
	for c in state.pieces:
		if state.pieces[c]["team"] == state.current \
				and maxi(absi(c.x - cell.x), absi(c.y - cell.y)) == 1:
			return 0.0
	# Chebyshev stand-in for "could the bonus move still put someone next to
	# it" — move_targets is straight-line-and-blockable so this slightly
	# over-estimates, fine for a heuristic that only scales a penalty. Uses
	# BONUS_MOVE_RANGE and considers EVERY own figure, matching the rule
	# under test (any figure, one cell — see MatchState.current_move_range).
	for c in state.pieces:
		if state.pieces[c]["team"] == state.current \
				and maxi(absi(c.x - cell.x), absi(c.y - cell.y)) <= MatchState.BONUS_MOVE_RANGE + 1:
			return SHOT_HANDOVER_PENALTY * 0.25
	return SHOT_HANDOVER_PENALTY


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
## (team_can_score_next, see _defense_score).
##
## 2026-07-29: was 16, pre-ranked by _move_base_score — i.e. "how much closer
## to the ball does this get me". That is precisely the WRONG filter for
## finding a defensive move, because a block is not near the ball, it is on
## the line between the ball and your own goal, typically several cells away.
## A human's log caught it exactly: with the ball on (4,4) the AI had FIVE
## moves that denied the goal outright — a keeper slide to (2,0), and four
## ways to plug (3,1)/(4,2) on the shooting diagonal — every one of them
## 2-4 cells from the ball, so every one of them was cut by the pre-filter
## before anything looked at it, and the AI played a chase move and conceded
## (verified in scripts/tools/analyze_conceded_goal.gd).
##
## The cap now sits above any realistic candidate count (every own piece times
## eight directions times MatchState.MAX_MOVE_RANGE, minus blocked rays, runs
## to ~50-60), so in practice every candidate really is checked. It stays as a
## cap rather than being deleted purely as a guard against a pathological
## position: at ~1ms per check this is tens of ms per decision, comfortably
## inside the AI_THINK_TIME pause main.gd already waits out.
const MAX_DEFENSE_CHECKS := 128

## {"from": Vector2i, "to": Vector2i} — every legal (from,to) pair across every
## movable figure is scored and ranked together (see _move_score), same
## difficulty hit-rate as decide_combo.
static func decide_move(state: MatchState, difficulty: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for cell in state.move_from_cells():
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
	var dist := maxi(absi(to.x - state.ball.x), absi(to.y - state.ball.y))
	# Landing ON the ball is not "one square better" than landing beside it, it
	# is a different kind of move: under move-then-kick it buys the whole ball
	# half of the turn, and under underfoot it is the only way possession ever
	# changes hands at all. Scored as plain distance it was worth ONE point
	# against a 400-point defensive term, so the AI would step off its own ball
	# to tidy up a shape — which is exactly what it did with its first move of a
	# real match, abandoning the kickoff in its own goalmouth.
	var collects: bool = MatchState.experiment_underfoot and to == state.ball \
		and not state.pieces.has(state.ball)
	return (COLLECT_BONUS if collects else 0.0) - dist


## Worth more than _defense_score's 400, because a defensive shape you hold
## while the opponent has the ball is worth less than simply having the ball.
const COLLECT_BONUS := 900.0


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
	if MatchState.experiment_underfoot:
		# Possession is standing ON the ball, not beside it. Asking for
		# adjacency here asked the question backwards on both sides: it read a
		# man merely NEXT to the ball as a live threat, and the man actually
		# holding it as none at all.
		if state.pieces.has(state.ball) and state.pieces[state.ball]["team"] == team:
			if _chain_can_score(state, team, state.ball):
				return true
		# And under move-then-kick a loose ball is a threat to whoever can walk
		# onto it, because collecting it opens the ball half of the SAME turn.
		# Treating that as safe is what let the AI leave a loose ball sitting in
		# a scoring position, one step from an opponent.
		if MatchState.experiment_move_then_kick and not state.pieces.has(state.ball):
			for start in state.pieces:
				if state.pieces[start]["team"] != team:
					continue
				if not (state.ball in state.move_targets(start)):
					continue
				var after: MatchState = state.clone_for_query()
				after.pieces[state.ball] = after.pieces[start]
				after.pieces.erase(start)
				if _chain_can_score(after, team, state.ball):
					return true
		return false
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


## Bonus for a shot that doesn't just move the ball forward but leaves a
## SCORING THREAT standing for next turn — the thing the AI had no concept of
## at all until 2026-07-27. It measured only "how far upfield did the ball
## get" and "will I still have it", so it shoved the ball toward the goal and
## then had to invent an attack from scratch every single turn.
##
## A human beat Hard by doing the one thing it never tried: arranging TWO
## separate scoring lines into two different goal cells at once. The defender
## gets a single move, so it can close one lane or the other, never both —
## the goal is already unstoppable a full turn before it is scored (verified
## on the real position in scripts/tools/analyze_conceded_goal.gd: of all 60
## legal defensive moves, not one saved it). Counting DISTINCT reachable goal
## cells is exactly that idea: one route is a chance the defence can still
## kill, two routes is a won position.
const THREAT_BONUS := 1500.0
const DOUBLE_THREAT_BONUS := 6000.0


## Value of the attacking position left behind if the ball ends up on `cell`.
## Temporarily previews the ball there (a shot moves nothing else), same trick
## _post_shot_threat_penalty uses.
static func _own_threat_bonus(state: MatchState, cell: Vector2i) -> float:
	var saved_ball := state.ball
	state.ball = cell
	var routes := _count_scoring_routes(state, state.current)
	state.ball = saved_ball
	if routes >= 2:
		return DOUBLE_THREAT_BONUS
	if routes == 1:
		return THREAT_BONUS
	return 0.0


## How many DISTINCT goal cells `team` could score into on its next turn —
## the breadth of the threat, not merely whether one exists (which is what
## team_can_score_next answers). Same reachability rules as _search_chain.
static func _count_scoring_routes(state: MatchState, team: String) -> int:
	var cells := {}
	for start in state.pieces:
		if state.pieces[start]["team"] == team \
				and maxi(absi(start.x - state.ball.x), absi(start.y - state.ball.y)) == 1:
			var s: MatchState = state.clone_for_query()
			s.current = team
			s.phase = MatchState.Phase.COMBO
			s.chain = [start]
			_collect_scoring_cells(s, cells)
	return cells.size()


static func _collect_scoring_cells(s: MatchState, out: Dictionary) -> void:
	var shooter: Vector2i = s.chain[-1]
	for shoot_cell in s.combo_shoot_targets():
		if s.is_opponent_goal(shoot_cell, s.current) and not s.is_offside(shooter, s.current):
			out[shoot_cell] = true
	if s.chain.size() >= MAX_THREAT_CHAIN_DEPTH:
		return
	for next_cell in s.combo_pass_targets():
		s.chain.append(next_cell)
		_collect_scoring_cells(s, out)
		s.chain.pop_back()


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
