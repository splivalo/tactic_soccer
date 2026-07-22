class_name MatchState
extends RefCounted

## Pure game logic for Tactic Soccer — NO nodes, NO visuals. Operates only on the
## 7x10 grid (Board) and rules from rules/igra_pravila.md. main.gd is the view:
## it renders pieces/ball and forwards clicks; this decides what is legal and what
## happens. Because it is pure, it is unit-testable headlessly (see tests/).

## MOVE = move a figure; REMOVE = a red-carded team must pick a figure to
## permanently remove before play continues (replaces that turn's move).
enum Phase { COMBO, MOVE, REMOVE }
const GOAL_COLS := [2, 3, 4]

# cell(Vector2i) -> {"team": String, "role": "gk"|"field", "id": int}. `id` is
# a persistent per-figure identity (survives moves) — needed to detect "the
# SAME figure shot twice in a row" for the yellow/red card rule, since figures
# are otherwise only identified by their current cell.
var pieces: Dictionary = {}
var ball: Vector2i = Vector2i.ZERO
var current: String = "HomeTeam"
var phase: int = Phase.MOVE
var chain: Array[Vector2i] = []
var score: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}
var goals_to_win: int = 2
var _next_id: int = 0
# How many MOVE actions are left this Phase.MOVE before the turn passes — 1
# for the mandatory tidy-up move right after your OWN combo (see
# execute_combo), 2 when you're REACTING because you don't have the ball at
# all (see start_turn/team_has_ball below): enough to physically bring a
# SECOND figure in (or the same one via two hops, an "L") within one reaction
# window, so a numbers/reach disadvantage is actually recoverable instead of
# permanently unreachable — see do_move().
var moves_left: int = 1
# True only for the (single) REACTIVE move (you don't have the ball at all —
# see start_turn/do_move). Kept even though it's now always true whenever
# Phase.MOVE is entered (there's no more mandatory post-combo tidy-up move —
# see execute_combo/hold_and_move) — harmless, and cheap insurance against a
# future re-introduction of a second move kind.
var _move_is_reactive: bool = false

## Max cells a figure may slide in one MOVE action (do_move/hold_and_move) —
## deliberately SHORTER than a pass/shot's unlimited range (2026-07-22,
## symmetric "1 action per turn" redesign): with unlimited movement, both a
## reactive recovery AND the recovering team's own next move could each
## cross the whole board in a single hop, so nothing could ever hold space —
## the ball just ping-ponged. Capping MOVEMENT only (passing/shooting stays
## unlimited, that's core to the game) means closing a real gap takes several
## turns of genuine approach, not one hop — measured via simulation at 3 to
## fix the resulting "matches never finish" pathology (avg turns/match 1284
## -> 274, timeouts 5/15 -> 0/15) without hurting reactive recovery odds
## (58.6% -> 72.5%). Tightened to 2 same day, per request — not yet
## re-measured, worth a fresh simulation if matches start dragging again.
const MAX_MOVE_RANGE := 2

# --- cards / stalling --------------------------------------------------------
# 2026-07-22: switched STALLING's trigger from "held the ball 2 turns in a
# row" to actual LOOP DETECTION — a human reported the old trigger almost
# never fired in practice, while a real, worse stalling pattern went totally
# unpunished: two teams repeatedly shuffling the ball between the same couple
# of cells (a shoot/reactive-move cycle that never progresses) could in
# principle repeat forever. Trigger: the exact board position (every piece's
# cell/team/role + the ball's cell + whose COMBO turn it is) has now been
# seen for the 3rd time — see _position_key/_position_counts/
# _check_stalling_repetition, called from start_turn() whenever a team's
# COMBO opens. The team carded is whichever team's COMBO turn that repeated
# position belongs to — i.e. the team that HAS the ball and keeps ending up
# back in the same spot instead of actually progressing (see
# last_card_team) — not necessarily whoever's move/shot just happened to
# trigger the check. Coincidentally hitting the exact same full-board
# position 3 times by chance (rather than an actual repeating cycle) is
# astronomically unlikely given the size of the state space, so a raw
# occurrence count is used instead of tracking strict consecutiveness.
# ESCALATION unchanged: 1st = yellow only; 2nd, and every one after, = red
# card AND an immediate figure removal in the same breath (matches real
# football — sent off there and then). Persists for the whole match
# (partija) — only setup() clears cards/foul_count, not reset().
# UI warning: see would_card_shoot/would_card_move — a shoot or move target
# can only be flagged as "would card" in advance when it hands the OTHER
# team a COMBO turn immediately (no intervening reactive-move decision to
# wait on), since that's the only case where the resulting position (and
# its would-be occurrence count) is actually knowable right now.
var yellow_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var red_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var foul_count: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}
# position-key(String) -> how many times that exact board position has
# occurred at a COMBO-turn start this match — see _check_stalling_repetition.
# Cleared on reset() (a fresh kickoff's positions can never collide with
# pre-goal ones anyway, just bounded memory).
var _position_counts: Dictionary = {}
# "yellow"/"red"/"" — set by _check_stalling_repetition() when a position
# repeated for the 3rd time. Cleared at the start of every start_turn() call
# (i.e. every next_turn()) — main.gd reads this right after calling
# whichever action ended the turn (execute_combo/do_move/hold_and_move/
# remove_figure) to surface the card announcement.
var last_move_card: String = ""
# Which team last_move_card actually belongs to — NOT always whoever's
# action just ran (see the "cards / stalling" comment above): a reactive
# do_move by team X can hand a repeated position straight back to team Y's
# COMBO, carding Y even though X was the one who just acted.
var last_card_team: String = ""
# Team name that must remove a figure (Phase.REMOVE), or "" if none pending.
var pending_removal: String = ""


# --- setup -------------------------------------------------------------------
func setup(home: Array, away: Array, ball_cell: Vector2i, first: String, win: int) -> void:
	score = {"HomeTeam": 0, "AwayTeam": 0}
	goals_to_win = win
	yellow_card = {"HomeTeam": false, "AwayTeam": false}
	red_card = {"HomeTeam": false, "AwayTeam": false}
	foul_count = {"HomeTeam": 0, "AwayTeam": 0}
	reset(home, away, ball_cell, first)


## Re-place both teams + ball (keeps score/cards) and start `first`'s turn.
func reset(home: Array, away: Array, ball_cell: Vector2i, first: String) -> void:
	pieces.clear()
	_next_id = 0
	for p in home:
		pieces[p["cell"]] = {"team": "HomeTeam", "role": p.get("role", "field"), "id": _next_id}
		_next_id += 1
	for p in away:
		pieces[p["cell"]] = {"team": "AwayTeam", "role": p.get("role", "field"), "id": _next_id}
		_next_id += 1
	ball = ball_cell
	current = first
	pending_removal = ""
	_position_counts = {}
	start_turn()


func start_turn() -> void:
	chain.clear()
	last_move_card = ""
	last_card_team = ""
	if team_has_ball(current):
		phase = Phase.COMBO
		_check_stalling_repetition()
	else:
		phase = Phase.MOVE
		moves_left = 1
		_move_is_reactive = true


## A canonical snapshot of "what the board looks like, and whose COMBO turn
## it is" for a given team — every piece's cell/team/role, plus the ball's
## cell, plus `as_team`. Two calls (same or different `as_team`) return the
## same string iff the position (and whose turn it is to act on it) is truly
## identical — see _check_stalling_repetition/would_card_shoot/
## would_card_move.
func _position_key(as_team: String) -> String:
	var parts: Array[String] = []
	for cell in pieces:
		var info: Dictionary = pieces[cell]
		parts.append("%d,%d:%s:%s" % [cell.x, cell.y, info["team"], info["role"]])
	parts.sort()
	return "%d,%d|%s|%s" % [ball.x, ball.y, as_team, ",".join(PackedStringArray(parts))]


## Called from start_turn() right as a team's COMBO opens: counts how many
## times this exact position (see _position_key) has occurred at a COMBO
## start, and cards `current` — the team that HAS the ball right now, i.e.
## the one stuck repeating this spot instead of progressing — the 3rd time
## it recurs. See the "cards / stalling" doc comment up top for the full
## reasoning.
func _check_stalling_repetition() -> void:
	var key := _position_key(current)
	var count: int = _position_counts.get(key, 0) + 1
	_position_counts[key] = count
	if count >= 3:
		_position_counts[key] = 0
		last_move_card = _apply_card(current)
		last_card_team = current
		if pending_removal == current:
			phase = Phase.REMOVE


## True if shooting to `shoot_cell` right now would IMMEDIATELY complete a
## 3rd repeat and card the OPPONENT — i.e. the resulting position (ball at
## shoot_cell, pieces unchanged) already puts the opponent's own figure(s)
## adjacent to the ball, so their COMBO opens the instant this shot lands
## (no intervening reactive move to wait on — see the "cards / stalling" doc
## comment on why that intervening step usually makes this unknowable in
## advance). Read-only: saves/restores `ball`, never mutates real state.
## main.gd uses this to warn on the SPECIFIC shoot target that would trigger
## the card, not the whole shoot-target set.
func would_card_shoot(shoot_cell: Vector2i) -> bool:
	var saved_ball := ball
	ball = shoot_cell
	var next_team := opponent(current)
	var result: bool = false
	if team_has_ball(next_team):
		result = _position_counts.get(_position_key(next_team), 0) + 1 >= 3
	ball = saved_ball
	return result


## True if moving `from` -> `to` right now (ball unchanged — the shared
## shape of both do_move and hold_and_move) would IMMEDIATELY complete a 3rd
## repeat and card the OTHER team — see would_card_shoot's doc comment for
## the same "only knowable when it opens their COMBO with no intervening
## decision" reasoning. Read-only: saves/restores `pieces`, never mutates
## real state. main.gd uses this to warn on the SPECIFIC move target that
## would trigger the card, not the whole move-target set.
func would_card_move(from: Vector2i, to: Vector2i) -> bool:
	if not pieces.has(from):
		return false
	var saved_info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = saved_info
	var next_team := opponent(current)
	var result: bool = false
	if team_has_ball(next_team):
		result = _position_counts.get(_position_key(next_team), 0) + 1 >= 3
	pieces.erase(to)
	pieces[from] = saved_info
	return result


func next_turn() -> void:
	current = opponent(current)
	start_turn()


## A lightweight scratch copy for hypothetical "what if" queries (AI defense
## lookahead — see AIPlayer.team_can_score_next — and AIPlayer's Hard combo
## search, see AIPlayer._search_best_combo). Copies what the combo/move query
## functions actually read: pieces, ball, current team, chain, phase. Score/
## cards/timers/moves_left are still NOT copied — no query function reads
## them — so mutate the clone freely, the real state is never touched.
func clone_for_query() -> MatchState:
	var c := MatchState.new()
	c.pieces = pieces.duplicate(true)
	c.ball = ball
	c.current = current
	c.phase = phase
	c.chain = chain.duplicate()
	return c


## The current team ran out of time to act (COMBO/MOVE/REMOVE) — no move is
## made, the board stays exactly as it is, and the turn simply passes to the
## opponent (a pending forced removal is dropped, same as skipping any other
## decision).
func forfeit() -> void:
	pending_removal = ""
	next_turn()


# --- queries -----------------------------------------------------------------
func opponent(team: String) -> String:
	return "AwayTeam" if team == "HomeTeam" else "HomeTeam"


func team_of(cell: Vector2i) -> String:
	return pieces[cell]["team"] if pieces.has(cell) else ""


func is_own(cell: Vector2i) -> bool:
	return team_of(cell) == current


## Every cell occupied by one of the current team's own figures.
func own_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in pieces:
		if pieces[cell]["team"] == current:
			out.append(cell)
	return out


func _cheby(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## A team "has" the ball the moment one of its own figures is adjacent to it —
## full stop. How many opponent figures also happen to be nearby doesn't
## matter: it isn't their turn regardless, so there's nothing for them to
## contest right now. (An earlier version of this also required not being
## outnumbered there, but that blocked the exact reactive catch-up move it
## was meant to reward — reach the ball and you're entitled to act on it.)
func team_has_ball(team: String) -> bool:
	return _adjacent_count(team) >= 1


## How many of `team`'s figures sit Chebyshev-adjacent to the ball right now.
func _adjacent_count(team: String) -> int:
	var count := 0
	for cell in pieces:
		if pieces[cell]["team"] == team and _cheby(cell, ball) == 1:
			count += 1
	return count


func combo_starters() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in pieces:
		if pieces[cell]["team"] == current and _cheby(cell, ball) == 1:
			out.append(cell)
	return out


# True if `dir` is a pure horizontal step (dy == 0) — the only orientation
# that can ever travel ALONG a goal row instead of into it from the field
# side. A goalpost blocks the ball entering (or leaving) a goal cell from
# the side no matter what's standing there — see _pass_from/_shoot_from.
func _is_lateral(dir: Vector2i) -> bool:
	return dir.y == 0


# First figure on each ray from `cell`: a teammate not already in the chain =
# pass. A goal cell — EITHER net, your own or the opponent's — is a hard
# wall for a horizontal (sideways) ray: the goalpost blocks the ball
# entering or leaving it from the side at all, whoever/whatever is standing
# there, so it's never even checked for a piece along that orientation. For
# any OTHER ray (vertical/diagonal — actually approaching from the field),
# it still works as before: reaching a further empty goal cell blocks
# anything beyond it (passing through a goal-mouth is never offered as an
# option, matching rules/igra_pravila.md's "NE MOŽE SUDJELOVATI" — simply
# unavailable, not a scored event).
func _pass_from(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in Board.DIRS:
		var c: Vector2i = cell + dir
		var lateral := _is_lateral(dir)
		while Board.in_bounds(c):
			if is_goal_cell(c) and lateral:
				break
			if pieces.has(c):
				if pieces[c]["team"] == current and not (c in chain):
					out.append(c)
				break
			if is_goal_cell(c):
				break
			c += dir
	return out


# Empty cells along each ray from `cell` = shoot/land targets. A goal cell is
# a hard wall for a horizontal (sideways) ray — the goalpost blocks a shot
# entering it from the side, so it's never offered as a landing spot that
# way at all (no autogol, no goal, either net — that entry angle simply
# isn't physically possible). For any OTHER ray (actually approaching from
# the field) it's still offered as a landing spot exactly as before (own-
# goal cells stay legal — a deliberate/accidental autogol is real rules-
# legal; an opponent goal cell is still a real scoring shot, subject to the
# usual opponent-half/offside checks) — it just can't sail THROUGH a
# goal-mouth to land somewhere further along the same line.
func _shoot_from(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in Board.DIRS:
		var c: Vector2i = cell + dir
		var lateral := _is_lateral(dir)
		while Board.in_bounds(c) and not pieces.has(c):
			if is_goal_cell(c) and lateral:
				break
			out.append(c)
			if is_goal_cell(c):
				break
			c += dir
	return out


## The goalkeeper is a normal link in the chain — receives AND relays like
## any other figure. 2026-07-22: the earlier "must be the end of the chain"
## restriction was REMOVED — that's a separate concern from the lateral
## goal-entry block (_pass_from/_shoot_from's _is_lateral check, which
## stays): a real goalpost blocks the ball entering/leaving a goal cell from
## the SIDE, but a normal (vertical/diagonal) pass to the keeper followed by
## a normal pass back out is just distribution, same as real football — the
## lateral check already blocks the actual dangerous case (the ball sliding
## through the goal-mouth sideways) on its own, with no need for this extra
## dead-end rule on top of it.
func combo_pass_targets() -> Array[Vector2i]:
	if chain.is_empty():
		return [] as Array[Vector2i]
	return _pass_from(chain[-1])


## Empty cells the last chain figure could shoot to. Excludes the ball's own
## current resting cell — you cannot "shoot" it back to where it already is.
## Also excludes the OPPONENT's goal cells unless the shooter is in the
## opponent's half: from your own half a shot there can never be a goal (see
## execute_combo), so — matching the original 2006 game, which didn't even mark
## those cells as selectable — they're not offered as targets. Your OWN goal
## cells stay targetable from anywhere (a deliberate/accidental autogol).
func combo_shoot_targets() -> Array[Vector2i]:
	if chain.is_empty():
		return [] as Array[Vector2i]
	var shooter: Vector2i = chain[-1]
	var out := _shoot_from(shooter)
	out.erase(ball)
	if not in_opponent_half(shooter, current):
		out = out.filter(func(c): return not is_opponent_goal(c, current))
	return out


# --- combo (pass chain -> shoot) --------------------------------------------
## Start (or restart) the chain on your figure next to the ball. True if valid.
func begin(cell: Vector2i) -> bool:
	if phase == Phase.COMBO and is_own(cell) and _cheby(cell, ball) == 1:
		chain = [cell]
		return true
	return false


## Connect to a teammate on a clear line. True if it was a valid pass target.
func extend(cell: Vector2i) -> bool:
	if phase == Phase.COMBO and cell in combo_pass_targets():
		chain.append(cell)
		return true
	return false


## If `cell` is already part of the chain, truncate back to it — lets the
## player reconsider a later pick without ever revisiting a cell twice
## (chain 1->2->3, click 2 again => chain becomes 1->2, never 1->2->3->2).
## True if `cell` was found (and the chain was truncated to it).
func rewind(cell: Vector2i) -> bool:
	var idx := chain.find(cell)
	if idx == -1:
		return false
	chain.resize(idx + 1)
	return true


## Shoot from the last figure to `shoot_cell`. Returns:
## {ok, path, goal, scorer, win, kickoff, offside, own_goal}. Updates state;
## on a goal the caller should call reset() to kick off (kickoff = who
## restarts). This never sets a "card" field directly, but a non-scoring shot
## DOES end the turn via next_turn() -> start_turn(), which can card whoever's
## COMBO opens next if that hands them a 3rd-repeated position — see
## MatchState.last_move_card/last_card_team, check both right after calling
## this exactly like after a MOVE/hold. This IS this team's whole turn now
## (no more mandatory follow-up move — see hold_and_move's doc comment for
## the "1 action per turn, shoot-or-hold" redesign), so it always ends the
## turn (unless it scored).
func execute_combo(shoot_cell: Vector2i) -> Dictionary:
	var res := {
		"ok": false, "path": [] as Array[Vector2i], "goal": false, "scorer": "",
		"win": false, "kickoff": "", "offside": false, "offside_shooter": Vector2i(-1, -1),
		"offside_line_row": -1, "own_goal": false,
	}
	if phase != Phase.COMBO or chain.is_empty() or not (shoot_cell in combo_shoot_targets()):
		return res
	var shooter: Vector2i = chain[-1]
	var path: Array[Vector2i] = [ball]
	path.append_array(chain)
	path.append(shoot_cell)
	res["ok"] = true
	res["path"] = path
	ball = shoot_cell
	chain.clear()

	# A ball into a goal scores — same rule for either net. Into the opponent's
	# goal (from their half, not offside) you score; into your OWN goal it's an
	# AUTOGOL and the opponent scores. In this piece model the ball only reaches a
	# net by being shot there, so no special keeper-corner geometry is needed.
	var scorer := ""
	if is_opponent_goal(shoot_cell, current) and in_opponent_half(shooter, current):
		if is_offside(shooter, current):
			res["offside"] = true
			res["offside_shooter"] = shooter
			res["offside_line_row"] = offside_line_row(current)
		else:
			scorer = current
	elif is_own_goal_cell(shoot_cell, current):
		scorer = opponent(current)
		res["own_goal"] = true

	if scorer != "":
		score[scorer] += 1
		res["goal"] = true
		res["scorer"] = scorer
		res["win"] = score[scorer] >= goals_to_win
		res["kickoff"] = opponent(scorer)  # the team scored against restarts
	else:
		next_turn()
	return res


## During Phase.REMOVE (after a red card), the carded team permanently
## removes one of its own figures. Spends that team's turn. True if legal.
func remove_figure(cell: Vector2i) -> bool:
	if phase != Phase.REMOVE or pending_removal == "" or not pieces.has(cell):
		return false
	if pieces[cell]["team"] != pending_removal:
		return false
	pieces.erase(cell)
	pending_removal = ""
	next_turn()
	return true


# --- move --------------------------------------------------------------------
## Every cell a figure at `from` could slide to: straight lines (the same 8
## rays a shot travels), stopping at the first occupied cell (another figure
## OR the ball), the board edge, or MAX_MOVE_RANGE cells — whichever comes
## first. Movement is deliberately SHORTER-range than a pass/shot (see
## MAX_MOVE_RANGE's doc comment) — this is what makes the reactive recovery
## a genuine multi-turn approach instead of a one-hop teleport. GKs are
## further filtered to their own goal cells only; outfield figures may never
## land on ANY goal cell.
func move_targets(from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not pieces.has(from):
		return out
	var role: String = pieces[from]["role"]
	var team: String = pieces[from]["team"]
	for dir in Board.DIRS:
		var c: Vector2i = from + dir
		var dist := 1
		while Board.in_bounds(c) and not pieces.has(c) and c != ball and dist <= MAX_MOVE_RANGE:
			if role == "gk":
				if is_own_goal_cell(c, team):
					out.append(c)
			elif not is_goal_cell(c):
				out.append(c)
			c += dir
			dist += 1
	return out


## Shared card escalation: 1st violation this match = yellow only, 2nd and
## every one after = red AND an immediate forced removal (pending_removal) —
## see the "cards / stalling" doc comment up top for why. Returns "yellow"
## or "red" for the caller to relay (see MatchState.last_move_card).
func _apply_card(team: String) -> String:
	foul_count[team] += 1
	if foul_count[team] == 1:
		yellow_card[team] = true
		return "yellow"
	red_card[team] = true
	pending_removal = team
	return "red"


## The REACTIVE move: your only action when you don't have the ball at all.
## Just repositions a figure (MAX_MOVE_RANGE cells) and ends the turn —
## reaching the ball this way never upgrades into a same-turn combo (that
## instant-attack bonus is gone in the "1 action per turn" redesign, see
## hold_and_move's doc comment): if it now leaves your team adjacent to the
## ball, start_turn() will correctly open Phase.COMBO on your own NEXT turn.
## True if the move was legal.
func do_move(from: Vector2i, to: Vector2i) -> bool:
	if phase != Phase.MOVE or not is_own(from) or not (to in move_targets(from)):
		return false
	var info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = info
	next_turn()
	return true


## The OTHER thing you can do with the ball besides shooting: just move a
## figure (any of your own, MAX_MOVE_RANGE cells) and keep the ball exactly
## where it is. This is the "1 action per turn, choose shoot OR move" redesign
## (2026-07-22) — the old rules forced a shot every single time you had the
## ball; this lets a team decline a bad shot without losing the ball outright.
## No card comes from holding itself any more (see the "cards / stalling" doc
## comment up top) — repeatedly holding is just one way a position can end up
## repeating, caught the same way any other stalling loop is. True if the
## move was legal.
func hold_and_move(from: Vector2i, to: Vector2i) -> bool:
	if phase != Phase.COMBO or not is_own(from) or not (to in move_targets(from)):
		return false
	var info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = info
	next_turn()
	return true


# --- goals -------------------------------------------------------------------
func opponent_goal_row(team: String) -> int:
	return 0 if team == "HomeTeam" else Board.ROWS - 1


func own_goal_row(team: String) -> int:
	return Board.ROWS - 1 if team == "HomeTeam" else 0


func is_goal_cell(cell: Vector2i) -> bool:
	return (cell.y == 0 or cell.y == Board.ROWS - 1) and cell.x in GOAL_COLS


func is_own_goal_cell(cell: Vector2i, team: String) -> bool:
	return cell.y == own_goal_row(team) and cell.x in GOAL_COLS


func is_opponent_goal(cell: Vector2i, team: String) -> bool:
	return cell.y == opponent_goal_row(team) and cell.x in GOAL_COLS


# Home attacks toward row 0 (opponent half = rows 0..4); away toward row 9.
func in_opponent_half(cell: Vector2i, team: String) -> bool:
	if team == "HomeTeam":
		return cell.y * 2 < Board.ROWS
	return cell.y * 2 >= Board.ROWS


## True if `shooter` is offside: on the opponent's half, with every OUTFIELD
## opponent figure strictly closer to their own goal than the shooter — i.e.
## none level with or ahead of them. The goalkeeper is excluded: it's pinned
## to its own goal row, so including it would make offside impossible (it
## would always be "level or ahead", per the reference rules screenshot).
func is_offside(shooter: Vector2i, team: String) -> bool:
	if not in_opponent_half(shooter, team):
		return false
	var goal_row := opponent_goal_row(team)
	var shooter_dist := absi(shooter.y - goal_row)
	var has_outfield_opponent := false
	for cell in pieces:
		var info: Dictionary = pieces[cell]
		if info["team"] == team or info["role"] == "gk":
			continue
		has_outfield_opponent = true
		var opp_dist := absi(cell.y - goal_row)
		if opp_dist <= shooter_dist:
			return false
	# With no outfield defenders left at all (e.g. reduced by red cards),
	# there's no defensive line to be "behind" — offside can't apply, or a
	# weakened team could never be scored against at all.
	return has_outfield_opponent


## The row of the opponent's LAST outfield defender (closest to their own
## goal) — this is the offside line an attacker must stay level with or in
## front of. Excludes the goalkeeper, same reasoning as is_offside(). Returns
## -1 if the opponent has no outfield pieces left.
func offside_line_row(team: String) -> int:
	var goal_row := opponent_goal_row(team)
	var best_dist := 1 << 30
	var best_row := -1
	for cell in pieces:
		var info: Dictionary = pieces[cell]
		if info["team"] == team or info["role"] == "gk":
			continue
		var d := absi(cell.y - goal_row)
		if d < best_dist:
			best_dist = d
			best_row = cell.y
	return best_row
