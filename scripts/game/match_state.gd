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
# How many MOVE actions are left this Phase.MOVE before the turn passes —
# always 1 (both the post-shot bonus move and the reactive move are single
# moves; see _move_is_reactive for which one is which).
var moves_left: int = 1

## MEASUREMENT ONLY, all off by default (2026-08-05). The ball sits at a man's
## FEET rather than on an empty square beside him, so possession is something you
## do — walk onto it — rather than something that happens to whoever is nearby
## when their turn starts.
##
##   underfoot     the ball occupies the holder's square; a loose ball on an
##                 empty square belongs to nobody until someone steps on it
##   no_self_collect   the bonus move after a kick may not land on the ball, so
##                 the kicker cannot simply collect his own clearance
## TRIED AND REMOVED TWICE, both on 2026-08-06. First a held ball travelling
## with its carrier; then, once "dribbling" turned out to mean taking the ball
## off a man you stand beside, a tackle. The tackle worked and was still wrong to
## play: nothing on the board says a figure beside the carrier is about to do
## anything, so the ball changed hands with no warning you could read in advance.
## A rule you cannot see coming is not tactics, it is noise.
##
## ON for playtesting (2026-08-06). Measured against the shipped rule over 25
## matches: possession runs 23.6 -> 3.3, recovery 19.4% -> 33.6%, and the number
## the whole investigation was about — match length — 402 turns down to 95.
##
## no_self_collect stays OFF: measured, it makes both worse. Nudging the ball a
## square and stepping back onto it costs the entire bonus move and gains no
## ground, so it limits itself without a rule.
##
## Set experiment_underfoot false to get the shipped rule back.
static var experiment_underfoot := true
static var experiment_no_self_collect := false

## Nothing follows a kick — the turn ends with it. ON at a human's request, to
## be played rather than argued about.
##
## What it measured, so the numbers are on the record: match length 115 turns
## down to 60, and turns per goal 45 down to 27. Both move AWAY from the stated
## complaint, which was that goals come too easily and matches end too soon.
## Possession runs collapse from 4.97 to 1.78 with it.
static var experiment_no_move_after_kick := false

## ON for playtesting (2026-08-06). A turn is TWO things and the order is the
## player's: move one figure, and play the ball if you have it. Reaching a loose
## ball with your move therefore lets you play it in the SAME turn instead of
## standing over it for a full round, which is the dead feeling this answers.
##
## It also removes a rule rather than adding one: "declining the ball" is gone,
## because a move is now just a move and whether you also play the ball is a
## separate half of the same turn.
##
## This is close to a shape abandoned long ago for being hard to keep track of,
## and that fear now has a number against it. Measured against the one-action
## turn: choices per turn 53 -> 55, so it is NOT the flood that was feared —
## the old version had no underfoot rule and a fuller pitch. Recovery 37.6% ->
## 50.3%, possession runs 1.78 -> 2.75, match length 60 -> 71 turns.
static var experiment_two_actions := true

## ON for playtesting (2026-08-06). The two halves of the turn get a FIXED
## order — move a figure, then play the ball — and playing it stops being
## optional: stand on the ball and you must kick it before your turn ends.
##
## Standing on the ball and simply stopping was the hole underneath the whole
## balance investigation. Possession could not be contested at all (nobody can
## step onto an occupied square), and nothing obliged the holder to ever risk a
## kick, so he kept it until he chose not to — which is the 27-possession run.
##
## Fixing the order is what does the work, and it does three things at once:
##
##   * Your turn always ENDS with the ball loose in space, so the opponent's
##     move is always a live race for it. Possession is contested every single
##     turn instead of whenever the holder feels like it.
##   * The kicker cannot chase his own kick — his move is already behind him.
##     That is experiment_no_self_collect for free, with no extra rule.
##   * "Declining the ball" disappears, and so does hold_and_move. A turn is
##     one sentence: move a man, then play the ball if you are on it.
##
## The chain is untouched. You still stand on the ball, still string as many
## teammates together as you like, and it still ends with a kick into space.
static var experiment_move_then_kick := true

## Both consumed per turn under experiment_two_actions. Meaningless otherwise.
var _ball_used := false
var _move_used := false

## TRIED AND REMOVED, 2026-08-06: a pass that ENDS at the teammate, one per
## turn, instead of a chain. It was aimed at the real complaint — two actions
## plus tackling made a turn feel hectic — and it did calm it, by deleting the
## chain. That is not a trade worth making. Chaining several players into one
## kick is the thing this game has that no other board game does; it is what the
## whole tutorial is built around and what the first instruction card promises.
## Whatever answers the hectic feel has to leave the chain standing.
##
## See start_turn. Off by default; measurement only.
static var experiment_defender_two_moves := false

## The milder dose of the same idea: two moves of ONE square instead of one move
## of two. Total ground covered is unchanged — what the defender gains is the
## thing the attacker already has and he doesn't, which is being able to touch
## two different players in a turn. Full two-square doses overshot badly
## (possession runs 27.6 -> 1.58, recovery 17% -> 72%), so this separates
## flexibility from speed to see which of the two was doing the work.
static var experiment_defender_split_move := false
# 2026-07-23: re-introduced (was tried, then removed during the "1 action
# per turn" redesign, now being tested again with the rest of that redesign
# in place — see the "cards / stalling" doc comment for what else changed
# meanwhile). True for the REACTIVE move (you don't have the ball at all —
# see start_turn/do_move); false for the BONUS move a team gets right after
# its own non-scoring shot (see execute_combo) — shooting now costs a little
# more than choosing to hold (hold_and_move stays a single action, no bonus
# move), which is the whole point: it's meant to reward actually taking the
# risk to advance instead of leaving safe lateral possession with no
# downside. Both kinds share the exact same move_targets/do_move mechanics
# (same MAX_MOVE_RANGE), but WHO may move differs — see _bonus_move_shooter
# and do_move. Defaults to true (the permissive, general case: any own
# figure) rather than false — execute_combo is the only place that ever
# flips it to false, right before opening its own narrow bonus-move window,
# so any OTHER path into Phase.MOVE (start_turn's reactive branch, or a test/
# query building a MOVE state by hand without going through either) safely
# falls back to "any figure" instead of silently restricting to whatever
# _bonus_move_shooter happens to hold (2026-07-27: a hand-built Phase.MOVE
# state that skipped both start_turn() and execute_combo() was tripping the
# bonus-move restriction with no shooter ever set).
var _move_is_reactive: bool = true
# The figure that just took the non-scoring shot which opened this BONUS
# move (see execute_combo) — only that same figure may take the bonus move
# (do_move enforces this whenever not _move_is_reactive). 2026-07-27:
# restricted from "any own figure" because a team could shoot a throwaway
# ball just to unlock a free full-range reposition of an UNRELATED figure
# (e.g. a defender across the pitch) on top of the shot itself — tying the
# bonus move to the shooter closes that off while still letting the shooter
# follow up/run onto a rebound, which is the intended use. Meaningless
# outside a bonus move (_move_is_reactive == true), untouched by reset().
var _bonus_move_shooter: Vector2i = Vector2i(-1, -1)

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

# --- cards -------------------------------------------------------------------
# There is exactly ONE bookable offence: TIME-WASTING — letting the clock run
# out instead of playing your turn (see forfeit). Any phase: until 2026-08-01
# only an expired MOVE was booked, so two identical-looking timeouts could give
# different outcomes with nothing on screen to explain why, and it read as a
# bug. One rule that always applies beats a finer one nobody can see.
#
# History, so nobody re-invents a dead rule: three different stalling triggers
# were tried and all three were removed. "Ball returned to the figure that
# last shot it" (the original 2006 rule, verified against its decompiled
# source) fired on ~0.5% of shots. "Contested 50-50 recovery" was dropped with
# the turn redesign. "The same board position recurs" survived longest but was
# abandoned 2026-07-28: it fired 0-2 times per 2500 turns, and a player could
# neither see it coming nor understand it afterwards, because the thing being
# compared is the position of all twelve figures plus the ball rather than any
# decision they made. Its one real job was breaking infinite loops — which
# only ever mattered in AI-vs-AI simulation, a matchup the shipped game never
# runs (GameFlow is 1P human-vs-AI or 2P hot-seat).
# Time-wasting replaces it precisely because it is the opposite on every
# count: the countdown is on screen, the offence is a choice the player makes,
# and it is a bookable offence in real football too.
#
# ESCALATION: 1st = yellow only; 2nd, and every one after, = red card AND an
# immediate figure removal in the same breath (matches real football — sent
# off there and then). Counted per TEAM, not per figure — a deliberate
# simplification for a side of six. Persists for the whole match (partija) —
# only setup() clears cards/foul_count, not reset().
var yellow_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var red_card: Dictionary = {"HomeTeam": false, "AwayTeam": false}
var foul_count: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}
# "yellow"/"red"/"" — set by forfeit() when a MOVE's clock ran out. Cleared at
# the start of every start_turn() call (i.e. every next_turn()) — main.gd
# reads this right after calling whichever action ended the turn
# (execute_combo/do_move/hold_and_move/remove_figure/forfeit) to surface the
# card announcement.
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
	start_turn()


func start_turn() -> void:
	chain.clear()
	last_move_card = ""
	last_card_team = ""
	_ball_used = false
	_move_used = false
	if experiment_move_then_kick:
		if team_has_ball(current) and _ball_is_playable():
			# Already at your feet when the turn BEGINS — which only happens at
			# a restart, since every other turn ends with the ball kicked into
			# space. Then there is nothing to walk to and nothing to decide: you
			# just put it back in play, and that is the whole turn.
			#
			# Demanding a move first made the kick-off a trap. The obvious tap is
			# the man holding the ball, and moving HIM steps off it — his only
			# squares are the other two goal cells — so the ball was abandoned
			# loose in your own goalmouth and the turn ended with no kick at all.
			# Spending the move here is what stops that: there is no move to take
			# and none is offered.
			phase = Phase.COMBO
			_move_used = true
		else:
			# The ordinary turn: the move comes first, and do_move opens the
			# COMBO afterwards if it left you standing on the ball.
			phase = Phase.MOVE
			moves_left = 1
			_move_is_reactive = true
	elif team_has_ball(current):
		phase = Phase.COMBO
	else:
		phase = Phase.MOVE
		# EXPERIMENT (2026-08-04, measurement only). The side WITH the ball takes
		# two actions a turn — the chain-and-kick, then a move — while the side
		# without it takes one. That asymmetry has never been stated out loud and
		# is the plainest reason the attacker is permanently a step ahead: he
		# plays at double the tempo. This gives the defender the same two, which
		# makes the rule SHORTER to state (every turn is two actions, no
		# exception) rather than adding anything.
		moves_left = 2 if (experiment_defender_two_moves or experiment_defender_split_move) else 1
		_move_is_reactive = true


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
##
## `timed_out` marks a REAL clock expiry, as opposed to the caller simply
## having no legal action to take, and books the team for time-wasting —
## but ONLY in Phase.MOVE. Sitting out a MOVE is a net GAIN: the shot (or
## the reactive turn) is already behind you, and there are positions where
## every legal move breaks up a shape you would rather keep, so running the
## clock down is a real, rational way to dodge the one action the rules
## oblige you to take. That is exactly what a time-wasting booking is for.
## Letting a COMBO expire, by contrast, costs you the whole turn and usually
## the ball with it — punishment enough, and far more often a player who
## genuinely thought too long than anyone playing for time (2026-07-28).
## Callers that forfeit for any other reason must leave it false.
func forfeit(timed_out: bool = false) -> void:
	# EVERY clock expiry is booked, whatever phase it happened in (2026-08-01).
	# It used to card only a MOVE that ran out, which meant identical-looking
	# timeouts sometimes carded and sometimes didn't, with nothing on screen
	# explaining the difference — players simply read it as broken. A single
	# rule, "run out of time and you are booked", is worth more than the finer
	# distinction it replaces.
	var carding: bool = timed_out
	var offender := current
	pending_removal = ""
	if carding:
		# Book BEFORE next_turn(), which clears last_move_card as it opens the
		# other side's turn — then restore the announcement afterwards so
		# main.gd still finds it (same channel every other card uses).
		var card := _apply_card(offender)
		var removal_due: bool = pending_removal == offender
		next_turn()
		last_move_card = card
		last_card_team = offender
		if removal_due:
			# A red still owes a figure: hand the turn back so the carded team
			# serves it immediately, exactly like every other red.
			current = offender
			pending_removal = offender
			phase = Phase.REMOVE
		return
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
## Tried and rejected (2026-08-03): "the ball belongs to whoever is standing ON
## it", to answer a player finding the defence could never reach it. It worked on
## paper — possession runs 27.1 -> 3.5, recovery 17.4% -> 35.9%, matches a fifth
## the length — and was rejected in the hand, because a ball at a figure's feet
## simply isn't visible enough to play from. Measurements and the whole
## implementation are in git around this date if it is ever worth revisiting; the
## visibility is the thing that would have to be solved first, not the rule.
## Also tried and rejected (2026-08-04): one action per turn, with nothing
## following a kick. It did what it was built for — possession runs 27 down to 6
## — and broke something more important, which took a human two matches to name
## and is obvious once said: the post-kick move is how an attack ADVANCES.
##
## Without it a turn is either a kick, which keeps the ball but moves no player
## up the pitch, or a move, which advances a man but leaves the ball sitting
## where the defender can reach it. So possession bought nothing: seven turns of
## kicking with the ball never leaving rows 5-6, and the single attempt to go
## forward lost it immediately. The team with the ball could not progress and the
## team without it could not be hurt.
##
## Second time this conclusion has been reached from the other direction, which
## is the note worth leaving: the two-part turn is not clutter, it is the only
## thing that lets you keep the ball AND get somewhere with it.
func team_has_ball(team: String) -> bool:
	if experiment_underfoot:
		return pieces.has(ball) and pieces[ball]["team"] == team
	return _adjacent_count(team) >= 1


## How many of `team`'s figures sit Chebyshev-adjacent to the ball right now.
func _adjacent_count(team: String) -> int:
	var count := 0
	for cell in pieces:
		if pieces[cell]["team"] == team and _cheby(cell, ball) == 1:
			count += 1
	return count


## How far up the pitch a cell is for the side to move — bigger is nearer the
## goal they attack.
func advance_of(cell: Vector2i) -> int:
	return (Board.ROWS - 1 - cell.y) if current == "HomeTeam" else cell.y


func _advance(cell: Vector2i) -> int:
	return advance_of(cell)


func combo_starters() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if experiment_underfoot:
		# Exactly one man can ever open a chain: the one it is under.
		if pieces.has(ball) and pieces[ball]["team"] == current:
			out.append(ball)
		return out
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
##
## Also tried and rejected (2026-08-03): refusing squares one of your own figures
## already stands next to, so the ball had to be kicked into real space. It cut
## possession runs from 27 to 5.8 and nearly tripled the recovery rate, but the
## rule read as arbitrary — you cannot see why a square is closed without
## counting your own players around it.
## Also tried and rejected (2026-08-04): a kick had to travel at least as far as
## a player can run, aimed at the 58.7% of kicks that go exactly ONE square and
## keep possession 97.5% of the time. Rejected on feel, not effect — the run it
## was played against was the shortest yet — because a square you are standing
## next to being unavailable reads as arbitrary no matter how it is justified.
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
	if phase != Phase.COMBO or not is_own(cell):
		return false
	var holds := cell == ball if experiment_underfoot else _cheby(cell, ball) == 1
	if holds:
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


## Drops just the LAST figure from the chain — for tapping the chain's
## current END again (the ACTIVE figure, the one just picked), meaning
## "reconsider that last choice" rather than rewind()'s "jump back to an
## earlier one". Empties the chain entirely when it only had one figure
## (chain 1, tap 1 again => chain []; chain 1->2, tap 2 again => chain [1],
## NOT a no-op the way rewind(chain[-1]) would be). True if there was
## anything to step back from.
func step_back() -> bool:
	if chain.is_empty():
		return false
	chain.resize(chain.size() - 1)
	return true


## Shoot from the last figure to `shoot_cell`. Returns:
## {ok, path, goal, scorer, win, kickoff, offside, own_goal}. Updates state;
## on a goal the caller should call reset() to kick off (kickoff = who
## restarts). This never sets a "card" field directly, but a non-scoring shot
## opens a BONUS Phase.MOVE for the SAME team right after (see
## _move_is_reactive's doc comment, 2026-07-23) — that move's own do_move()
## call is what actually ends the turn via next_turn() -> start_turn(),
## which can card whoever's COMBO opens next if that hands them a 3rd-
## repeated position — see MatchState.last_move_card/last_card_team, check
## both right after calling THAT move, not this one. hold_and_move (declining
## to shoot) stays a single action with no bonus move — only an actual shot
## does this.
func execute_combo(shoot_cell: Vector2i) -> Dictionary:
	var res := {
		"ok": false, "path": [] as Array[Vector2i], "goal": false, "scorer": "",
		"win": false, "kickoff": "", "offside": false, "offside_shooter": Vector2i(-1, -1),
		"offside_line_row": -1, "own_goal": false,
	}
	if phase != Phase.COMBO or chain.is_empty() or not (shoot_cell in combo_shoot_targets()):
		return res
	# A non-scoring shot opens the bonus MOVE for the SAME team, so it does
	# NOT pass through next_turn()/start_turn() — which is the only other
	# place these get cleared. Without clearing them here, a card booked on
	# the PREVIOUS turn (forfeit sets them after its own next_turn, so they
	# survive on purpose) was still sitting there when the next combo
	# finished, and main.gd announced the very same yellow a second time —
	# a human saw exactly that in a real match (2026-07-29).
	last_move_card = ""
	last_card_team = ""
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
	elif experiment_two_actions:
		# The ball half of the turn is spent. If the move half already went, the
		# turn is over; otherwise it stays yours and you still owe a move.
		_ball_used = true
		if _move_used:
			next_turn()
		else:
			phase = Phase.MOVE
			moves_left = 1
			_move_is_reactive = true # any figure, full range — it is a normal move
	elif experiment_no_move_after_kick:
		next_turn()
	else:
		# Didn't score (including offside) — the shooting team stays
		# `current` and gets ONE bonus move (do_move, same MAX_MOVE_RANGE)
		# before the turn actually passes. Deliberately does NOT go through
		# next_turn()/start_turn() — this is still the same team's turn, not
		# a new one, so there's nothing to check a stalling repeat against
		# yet (that happens when do_move() eventually calls next_turn()).
		phase = Phase.MOVE
		moves_left = 1
		_move_is_reactive = false
		_bonus_move_shooter = shooter # do_move only accepts this figure — see its doc comment
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
## EXPERIMENT (2026-07-27): how far the BONUS move after a non-scoring shot
## may travel, as an alternative to restricting WHO may take it. Trading the
## "shooter only, MAX_MOVE_RANGE cells" rule for "any figure, but only this
## far" keeps the original exploit shut (one cell is far too little to
## re-shape a defence for free) while restoring the off-the-ball run — a
## second player breaking toward where the ball is going, which is both more
## natural football and more expressive. Cost: the shooter can no longer
## chase its OWN shot two cells, so possession is less sticky for everyone —
## which is exactly what needs measuring before this is adopted.
const BONUS_MOVE_RANGE := 1


## How far the figure moving right now may travel: the reduced
## BONUS_MOVE_RANGE during a post-shot bonus move, otherwise the normal
## MAX_MOVE_RANGE (reactive moves and hold_and_move both keep full range).
## Also tried and rejected (2026-08-04): unlimited movement, on the theory that
## the defender is permanently a turn behind a ball that relocates every turn.
## It did the opposite of the old warning — matches got much SHORTER, 28 turns
## for two goals against 40-plus for one — but it rewarded improvisation over
## planning, which is the exact failure the one-action turn exists to prevent.
## Possession runs stayed at nine either way, so it never bought what it was for.
func current_move_range() -> int:
	if experiment_defender_split_move and phase == Phase.MOVE and _move_is_reactive:
		return 1 # two of these instead of one full-length move
	if phase == Phase.MOVE and not _move_is_reactive:
		return BONUS_MOVE_RANGE
	return MAX_MOVE_RANGE


func move_targets(from: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not pieces.has(from):
		return out
	var role: String = pieces[from]["role"]
	var team: String = pieces[from]["team"]
	var reach := current_move_range()
	# Underfoot: a loose ball is what you are walking TO, so it stops being a
	# wall and becomes a destination — but you stop on it, you don't run over it.
	# And the man who just kicked may be barred from collecting his own
	# clearance, which is the only rule the whole system needs to work.
	var ball_is_wall := not experiment_underfoot
	var ball_barred := experiment_no_self_collect and phase == Phase.MOVE and not _move_is_reactive
	for dir in Board.DIRS:
		var c: Vector2i = from + dir
		var dist := 1
		while Board.in_bounds(c) and not pieces.has(c) and dist <= reach:
			var is_ball := c == ball
			if is_ball and (ball_is_wall or ball_barred):
				break
			if role == "gk":
				if is_own_goal_cell(c, team):
					out.append(c)
			elif not is_goal_cell(c):
				out.append(c)
			if is_ball:
				break
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
## When this is instead the BONUS move after your own non-scoring shot
## (_move_is_reactive == false), only the figure that took that shot
## (_bonus_move_shooter) may move — see its doc comment for why. True if the
## move was legal.
func do_move(from: Vector2i, to: Vector2i) -> bool:
	# One move a turn: without this the same figure could be walked twice, which
	# is what an unguarded hold_and_move was quietly allowing.
	if not can_move():
		return false
	if phase != Phase.MOVE or not is_own(from) or not (to in move_targets(from)):
		return false
	# EXPERIMENT (2026-07-27): the "only the shooter may take the bonus move"
	# restriction is replaced by BONUS_MOVE_RANGE (see current_move_range) —
	# any figure may take it, but only one cell. Kept here, commented, so the
	# two variants can be swapped back and forth while they're being measured.
	#if not _move_is_reactive and from != _bonus_move_shooter:
	#	return false
	var info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = info
	# moves_left was dead weight until now — every MOVE phase was a single move
	# and this called next_turn() unconditionally. It is what the defender's
	# second move rides on, so it is actually counted.
	moves_left -= 1
	if _move_is_reactive and moves_left > 0:
		return true # same team, another move still owed
	if experiment_two_actions:
		# The move half is spent. If we now stand on the ball the turn carries on
		# into its other half — walking onto a loose ball and playing it is one
		# turn, which is the whole point of two actions.
		_move_used = true
		if not _ball_used and team_has_ball(current) and _ball_is_playable():
			phase = Phase.COMBO
			chain.clear()
			return true
		next_turn()
		return true
	next_turn()
	return true


## Is there anything at all the man on the ball could do with it — a teammate to
## reach, or a square to kick into?
##
## Boxed in on every one of the eight rays there is not, and under
## experiment_move_then_kick that would leave the turn parked in a COMBO with no
## legal action, waiting on a clock. Nowhere to go is not a foul; the turn just
## ends and the ball stays where it is.
func _ball_is_playable() -> bool:
	if not pieces.has(ball):
		return false
	return not (_pass_from(ball).is_empty() and _shoot_from(ball).is_empty())


## Which of your own figures may currently take a Phase.MOVE action: every
## figure during a REACTIVE move, but only the shooter during a BONUS move
## (see do_move). UI/AI should use this instead of own_cells() whenever
## picking a figure for a real Phase.MOVE (NOT for hold_and_move, which
## still allows any own figure — see its doc comment).
func move_from_cells() -> Array[Vector2i]:
	# EXPERIMENT (2026-07-27): see do_move — the bonus move is now limited by
	# RANGE rather than by identity, so every own figure is selectable again.
	#if phase == Phase.MOVE and not _move_is_reactive:
	#	return [_bonus_move_shooter]
	if not can_move():
		return [] as Array[Vector2i] # the move half of the turn is spent
	return own_cells()


## The OTHER thing you can do with the ball besides shooting: just move a
## figure (any of your own, MAX_MOVE_RANGE cells) and keep the ball exactly
## where it is — the old rules forced a shot every single time you had the
## ball; this lets a team decline a bad shot without losing the ball outright.
## Always exactly ONE action, unlike a real shot (execute_combo), which now
## also grants a bonus follow-up move (2026-07-23) — deliberately asymmetric:
## shooting (taking the risk to actually advance) costs a bit more than
## playing it safe, which is the point (see execute_combo's doc comment).
## No card comes from holding itself (see the "cards / stalling" doc comment
## up top) — repeatedly holding is just one way a position can end up
## repeating, caught the same way any other stalling loop is. True if the
## move was legal.
## True while the move half of this turn is still owed. Always true outside the
## two-action turn, where a move is the only thing a MOVE phase is for.
func can_move() -> bool:
	return not (experiment_two_actions and _move_used)


func hold_and_move(from: Vector2i, to: Vector2i) -> bool:
	if experiment_move_then_kick:
		# There is no move to take from COMBO any more: the move is the FIRST
		# half of the turn and is always already spent by the time a COMBO opens.
		return false
	# This is the SECOND way to move a figure — the one taken from Phase.COMBO —
	# and it never checked whether the turn's move had already been spent. Under
	# a two-action turn that let a player move a man, come back to COMBO, move
	# another, come back to COMBO, without limit: a whole match's worth of
	# repositioning inside one turn. Seen in a real log as several MOVE lines
	# between two identical "TURN: HomeTeam phase=COMBO".
	if not can_move():
		return false
	if phase != Phase.COMBO or not is_own(from) or not (to in move_targets(from)):
		return false
	var info: Dictionary = pieces[from]
	pieces.erase(from)
	pieces[to] = info
	if experiment_two_actions:
		# There is no "declining the ball" any more — a move is just a move, and
		# whether you also play the ball is a separate half of the same turn.
		_move_used = true
		if not _ball_used and team_has_ball(current):
			phase = Phase.COMBO
			chain.clear()
			return true
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
