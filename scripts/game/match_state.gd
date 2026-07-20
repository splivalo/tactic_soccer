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

# --- cards / stalling ----------------------------------------------------------
# WHEN a violation happens is verified against the original 2006 game's
# decompiled source: holding the ball among your own figures is always
# legal — the violation is shooting the ball back within 1 cell of the
# figure that took your team's own LAST (clean) shot — i.e. "giving it back
# to the same guy" — regardless of which figure takes the new shot. The
# reference is cleared (no violation possible) if that figure has since been
# moved. The ESCALATION deliberately does NOT match the original: 1st =
# yellow only; 2nd, and every one after, = red card AND an immediate figure
# removal in the same breath (matches real football — a red card sends the
# player off there and then, not on some separate later incident). Persist
# for the whole match (partija) — only setup() clears cards/foul_count, not
# reset().
var yellow_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var red_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var foul_count: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}
# The figure (persistent id) that took this team's last CLEAN shot, and the
# cell it was standing on at that moment — the "stalling anchor". -1/none
# means no active reference (cleared after any violation, or if that exact
# figure gets moved — see do_move()). Resets each kickoff (reset()).
var stall_ref_id: Dictionary = {"HomeTeam": -1, "AwayTeam": -1}
var stall_ref_cell: Dictionary = {"HomeTeam": Vector2i(-1, -1), "AwayTeam": Vector2i(-1, -1)}
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
	stall_ref_id = {"HomeTeam": -1, "AwayTeam": -1}
	stall_ref_cell = {"HomeTeam": Vector2i(-1, -1), "AwayTeam": Vector2i(-1, -1)}
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
## functions actually read: pieces, ball, current team, chain, phase, and the
## stalling reference (needed for would_violate_stall to answer correctly
## inside a search clone instead of always seeing a fresh/empty reference).
## Score/cards/timers/moves_left are still NOT copied — no query function
## reads them — so mutate the clone freely, the real state is never touched.
func clone_for_query() -> MatchState:
	var c := MatchState.new()
	c.pieces = pieces.duplicate(true)
	c.ball = ball
	c.current = current
	c.phase = phase
	c.chain = chain.duplicate()
	c.stall_ref_id = stall_ref_id.duplicate()
	c.stall_ref_cell = stall_ref_cell.duplicate()
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


# First figure on each ray from `cell`: a teammate not already in the chain = pass.
func _pass_from(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in Board.DIRS:
		var c: Vector2i = cell + dir
		while Board.in_bounds(c):
			if pieces.has(c):
				if pieces[c]["team"] == current and not (c in chain):
					out.append(c)
				break
			c += dir
	return out


# Empty cells along each ray from `cell` = shoot/land targets.
func _shoot_from(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in Board.DIRS:
		var c: Vector2i = cell + dir
		while Board.in_bounds(c) and not pieces.has(c):
			out.append(c)
			c += dir
	return out


func combo_pass_targets() -> Array[Vector2i]:
	return _pass_from(chain[-1]) if not chain.is_empty() else [] as Array[Vector2i]


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


## True if a shot LANDING on `cell` would trip the stalling rule for the
## CURRENT team right now — mirrors the exact check inside execute_combo(),
## exposed as its own query so UI/AI code can preview it before the shot is
## actually taken (see main.gd's shoot-target colouring). False whenever no
## reference is live (fresh kickoff, or the reference figure has since moved
## — see do_move()), and false for your OWN goal cell: conceding an own goal
## is never a stalling tactic (no team benefits from it), so it's never worth
## piling a card on top of a goal already lost.
func would_violate_stall(cell: Vector2i) -> bool:
	if stall_ref_id[current] == -1:
		return false
	if is_own_goal_cell(cell, current):
		return false
	return _cheby(stall_ref_cell[current], cell) <= 1


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
## {ok, path, goal, scorer, win, kickoff, offside, card, must_remove}.
## Updates state; on a goal the caller should call reset() to kick off
## (kickoff = who restarts).
func execute_combo(shoot_cell: Vector2i) -> Dictionary:
	var res := {
		"ok": false, "path": [] as Array[Vector2i], "goal": false, "scorer": "",
		"win": false, "kickoff": "", "offside": false, "offside_shooter": Vector2i(-1, -1),
		"offside_line_row": -1, "card": "", "must_remove": "", "own_goal": false,
	}
	if phase != Phase.COMBO or chain.is_empty() or not (shoot_cell in combo_shoot_targets()):
		return res
	var shooter: Vector2i = chain[-1]
	var shooter_id: int = pieces[shooter]["id"]
	var path: Array[Vector2i] = [ball]
	path.append_array(chain)
	path.append(shoot_cell)
	res["ok"] = true
	res["path"] = path
	ball = shoot_cell
	chain.clear()

	# Stalling: the new shot lands within 1 cell of the figure that took this
	# team's own last CLEAN shot — "shooting it back near the same guy" —
	# regardless of which figure takes THIS shot. No violation if that
	# reference figure has since moved (stall_ref_id would already be -1;
	# see do_move()). Holding the ball among your own figures is otherwise
	# always fine. 1st = yellow (a warning only). 2nd AND EVERY violation
	# after that = red card AND an immediate figure removal in the same
	# breath — matches how a red card actually works in real football (the
	# player is sent off there and then, not on some LATER third incident).
	# foul_count persists for the whole match (only setup() clears it, not
	# reset() at kickoff — see the field's own doc comment), so a team that
	# keeps fouling after its first red keeps losing figures each time.
	if would_violate_stall(shoot_cell):
		foul_count[current] += 1
		if foul_count[current] == 1:
			yellow_card[current] = true
			res["card"] = "yellow"
		else:
			red_card[current] = true
			res["card"] = "red"
			res["must_remove"] = current
		stall_ref_id[current] = -1
		stall_ref_cell[current] = Vector2i(-1, -1)
	else:
		stall_ref_id[current] = shooter_id
		stall_ref_cell[current] = shooter

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
	elif res["must_remove"] != "":
		phase = Phase.REMOVE
		pending_removal = current
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


## Move a figure. Spends one of moves_left. If this was a REACTIVE move (see
## _move_is_reactive) and you now have the ball — even with a move still left
## — the rest of this turn upgrades straight into a real Phase.COMBO instead
## of forcing (or offering) another move: winning the ball back is the whole
## point of the extra reactive move, so the moment it happens you get to
## actually PLAY it, same turn, instead of the leftover slot going to waste.
## Otherwise hands the turn over once every move is used. True if the move
## was legal.
func do_move(from: Vector2i, to: Vector2i) -> bool:
	if phase != Phase.MOVE or not is_own(from) or not (to in move_targets(from)):
		return false
	var info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = info
	# Moving the figure that's the stalling reference clears it — matches the
	# tutorial: "this counts only when the previous figure has not been
	# moved in the meantime".
	var team: String = info["team"]
	if stall_ref_id[team] == info["id"]:
		stall_ref_id[team] = -1
		stall_ref_cell[team] = Vector2i(-1, -1)
	moves_left -= 1
	if _move_is_reactive and moves_left > 0 and team_has_ball(team):
		# Only upgrades when a move is still left AFTER this one — that
		# leftover slot is what gets "traded in" for the combo (move + shoot
		# = 2 actions, same as anyone who already had the ball). Reaching the
		# ball on your LAST reactive move must NOT also upgrade: you already
		# spent both actions on movement (move + move), so a shot on top
		# would be a 3rd action nobody else ever gets — it just ends the turn
		# normally instead (see the `elif moves_left <= 0` below).
		#
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
