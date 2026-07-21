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
# True only for a REACTIVE move phase (you didn't have the ball at all — see
# start_turn); false for the mandatory 1-move tidy-up right after your own
# combo. do_move() checks this to decide whether reaching the ball mid-phase
# should upgrade the rest of your turn into a real COMBO (reactive only — see
# do_move's doc comment for why the mandatory case must NEVER do this: it
# would let a team guard its own ball with its tidy-up move and combo again
# immediately, forever, which is exactly the "impossible to win the ball
# back" problem this whole reactive-move system exists to fix).
var _move_is_reactive: bool = false
# True while the CURRENT combo/shot exists only because a reactive move just
# reached the ball (see do_move's upgrade). Every team gets exactly 2 actions
# a turn: an attacker's is combo-then-move, a defender's is either 2 reactive
# moves, or 1 reactive move to reach the ball THEN the combo/shot — never
# both. execute_combo() checks this to skip the mandatory tidy-up move when
# the shot itself was already the 2nd action, instead of granting a 3rd.
var _combo_from_reactive: bool = false

# --- cards / 50-50 duel ----------------------------------------------------------
# This does NOT match the original 2006 game (which carded stalling — shooting
# the ball back near your own last shooter). Deliberately replaced: with the
# 2-actions-a-turn/reactive-move rules already in place, a team almost never
# gets to hold the ball among its own figures for long enough to actually
# stall (measured empirically at ~0.5% of shots in real AI-vs-AI play), so
# that trigger had become nearly dead weight while ball recovery itself
# carries no risk at all. The new trigger: winning back a contested 50-50 —
# your recovering figure lands in the ONE cell directly opposite an opponent
# figure, straight through the ball, on any of the 4 axes (like challenging
# for a real loose ball) — see is_contested_recovery(). ESCALATION: 1st =
# yellow only (the move itself still spends its action, but the reward — the
# upgrade into a combo, see do_move() — is withheld, same as a real foul
# never earning you the ball); 2nd, and every one after, = red card AND an
# immediate figure removal in the same breath (matches real football — sent
# off there and then, not on some separate later incident). Persists for the
# whole match (partija) — only setup() clears cards/foul_count, not reset().
var yellow_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var red_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var foul_count: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}
# "yellow"/"red"/"" — set by do_move() when the move it just performed was a
# carded contested recovery (see is_contested_recovery/_apply_card). Cleared
# at the start of every do_move() call — main.gd reads this right after
# calling do_move() to surface the yellow/red card announcement.
var last_move_card: String = ""
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
	start_turn()


func start_turn() -> void:
	chain.clear()
	_combo_from_reactive = false
	if team_has_ball(current):
		phase = Phase.COMBO
	else:
		phase = Phase.MOVE
		moves_left = 2 # reacting to not having the ball at all — see the field's doc comment
		_move_is_reactive = true


func next_turn() -> void:
	current = opponent(current)
	start_turn()


## A lightweight scratch copy for hypothetical "what if" queries (AI defense
## lookahead — see AIPlayer.team_can_score_next — and AIPlayer's Hard combo
## search, see AIPlayer._search_best_combo). Copies what the combo/move query
## functions actually read: pieces, ball, current team, chain, phase — enough
## for is_contested_recovery() too, since it only reads pieces/ball. Score/
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


## Once the ball has been PASSED (not started there) onto one of your own
## goal cells — only ever the goalkeeper; outfield figures can never stand
## there, see move_targets — it may not be relayed any further: the only
## legal continuation from there is the shot itself (execute_combo). This is
## the "misaligned keeper" danger from the original rules (rules/igra_
## pravila.md, "dodavanje golmanu... AUTOGOL") generalized — the goal line is
## never a safe waypoint to bounce the ball through to a teammate further
## along, only a place the keeper can receive and then clear FROM. Doesn't
## apply when the chain STARTS there (chain.size() == 1): that's the
## goalkeeper already holding the ball (straight off a kickoff or a save)
## safely distributing it out, which must stay legal.
func combo_pass_targets() -> Array[Vector2i]:
	if chain.is_empty():
		return [] as Array[Vector2i]
	if chain.size() > 1 and is_own_goal_cell(chain[-1], current):
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


# The 4 axis-pairs through the ball (its center): straight up/down, both
# diagonals, straight left/right. A recovering figure at `cell` and an
# opponent are a "50-50 through the ball" whenever they sit on exactly
# opposite ends of one of these axes with the ball itself in the middle.
const _DUEL_AXES := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]

## True if `team`'s figure landing on `cell` (a reactive move reaching the
## ball — see do_move()) is a contested 50-50: the ball sits directly between
## `cell` and an opponent figure, on any of the 4 axes through it. Exposed as
## its own query (not just inline in do_move()) so UI/AI code can preview it
## before the move is actually taken — see main.gd's move-target colouring
## and AIPlayer's avoidance of these cells.
func is_contested_recovery(cell: Vector2i, team: String) -> bool:
	var opp := opponent(team)
	for dir in _DUEL_AXES:
		if cell == ball - dir and pieces.has(ball + dir) and pieces[ball + dir]["team"] == opp:
			return true
		if cell == ball + dir and pieces.has(ball - dir) and pieces[ball - dir]["team"] == opp:
			return true
	return false


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
## restarts). Cards never come from a shot — see do_move()/is_contested_
## recovery() for the only trigger — so there's no "card"/"must_remove" field
## here; check MatchState.last_move_card after a MOVE instead.
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
	elif _combo_from_reactive:
		# This combo only happened because a reactive move reached the ball —
		# that move WAS this turn's 1st action, this shot its 2nd. Every team
		# gets exactly 2 actions a turn (see _combo_from_reactive's doc
		# comment); granting a mandatory tidy-up move on top would hand a
		# defender who just won the ball back a 3rd action a team that
		# already held the ball outright never gets.
		_combo_from_reactive = false
		next_turn()
	else:
		# Mandatory follow-up move — the ONLY point in the whole turn a team
		# holding the ball ever gets to reposition a figure at all (while you
		# have the ball, start_turn() always forces Phase.COMBO, never MOVE).
		# Without this, a team that keeps winning the ball back would never
		# move a single piece except the one it just shot with — formation
		# would freeze solid for as long as you keep attacking. Just 1 — this
		# isn't the reactive case, so no need to close a numbers/reach gap.
		phase = Phase.MOVE
		moves_left = 1
		_move_is_reactive = false
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
## OR the ball) or the board edge — mirrors Board.reachable_from, not just a
## single step. Figures move at the SAME range as a shot for exactly the
## reason a shot has that range: without it, a team that just launched the
## ball across the whole pitch in one action could never be chased down by
## the side that doesn't have it (which only ever gets one MOVE per turn) —
## the ball would permanently outrun any defence. GKs are further filtered to
## their own goal cells only; outfield figures may never land on ANY goal cell.
func move_targets(from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not pieces.has(from):
		return out
	var role: String = pieces[from]["role"]
	var team: String = pieces[from]["team"]
	for dir in Board.DIRS:
		var c: Vector2i = from + dir
		while Board.in_bounds(c) and not pieces.has(c) and c != ball:
			if role == "gk":
				if is_own_goal_cell(c, team):
					out.append(c)
			elif not is_goal_cell(c):
				out.append(c)
			c += dir
	return out


## Shared card escalation: 1st violation this match = yellow only, 2nd and
## every one after = red AND an immediate forced removal (pending_removal) —
## see the "cards / 50-50 duel" doc comment up top for why. Returns "yellow"
## or "red" for the caller to relay (see MatchState.last_move_card).
func _apply_card(team: String) -> String:
	foul_count[team] += 1
	if foul_count[team] == 1:
		yellow_card[team] = true
		return "yellow"
	red_card[team] = true
	pending_removal = team
	return "red"


## Move a figure. Spends one of moves_left. If this was a REACTIVE move (see
## _move_is_reactive) and you now have the ball — even with a move still left
## — the rest of this turn upgrades straight into a real Phase.COMBO instead
## of forcing (or offering) another move: winning the ball back is the whole
## point of the extra reactive move, so the moment it happens you get to
## actually PLAY it, same turn, instead of the leftover slot going to waste.
## UNLESS the recovery itself is a contested 50-50 (see is_contested_
## recovery()) — that's a foul, carded on the same yellow/red ladder as
## anything else, and a foul never earns you the reward you fouled for: no
## upgrade this turn, the move just spends itself like a plain reposition
## (a 2nd+ violation goes further still, forcing Phase.REMOVE before either
## side plays on). Otherwise hands the turn over once every move is used.
## True if the move was legal.
func do_move(from: Vector2i, to: Vector2i) -> bool:
	if phase != Phase.MOVE or not is_own(from) or not (to in move_targets(from)):
		return false
	var info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = info
	var team: String = info["team"]
	last_move_card = ""
	moves_left -= 1
	if _move_is_reactive and moves_left > 0 and team_has_ball(team):
		# Only upgrades when a move is still left AFTER this one — that
		# leftover slot is what gets "traded in" for the combo (move + shoot
		# = 2 actions, same as anyone who already had the ball). Reaching the
		# ball on your LAST reactive move must NOT also upgrade: you already
		# spent both actions on movement (move + move), so a shot on top
		# would be a 3rd action nobody else ever gets — it just ends the turn
		# normally instead (see the `elif moves_left <= 0` below).
		if is_contested_recovery(to, team):
			last_move_card = _apply_card(team)
			if pending_removal == team:
				phase = Phase.REMOVE
			return true
		# Auto-begin the chain on the figure that JUST reached the ball (it's
		# always exactly the piece that made this true — a move can only ever
		# flip team_has_ball by making `to` newly adjacent, since `from` no
		# longer holds a piece to count). Without this, the chain was empty
		# and needed an extra tap just to (re)select the obvious figure
		# before a pass/shoot tap would register at all — reaching the ball
		# should let the very next tap play it, not merely permit selecting it.
		chain = [to]
		phase = Phase.COMBO
		_combo_from_reactive = true
	elif moves_left <= 0:
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
