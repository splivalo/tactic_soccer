class_name Tutorial
extends RefCounted

## The five things a first-time player has to work out, in the order they trip
## over them. Pure logic — no nodes, no drawing. main.gd asks it what is allowed
## and tells it what happened; everything visual stays in the view layer, same
## split as MatchState.
##
## Written from watching someone play for the first time. Their mistakes, in
## order: tapped the BALL expecting to pick it up; kicked it to where the
## opponent could take it; never realised several players could be chained; and
## tapped a teammate expecting a pass when that teammate wasn't on a straight
## line at all.
##
## Three of those four are one misunderstanding: **the ball only travels in
## straight lines**. Not knowing that, the highlighted squares look arbitrary,
## so they stop being read as information. That is why step 2 is the centre of
## this and why the rays are drawn rather than described.
##
## Note what is NOT taught: gestures. Tap does everything (main.gd's _combo_tap
## passes and shoots), so there is nothing to learn about how to touch the
## screen — only about how to read the board.

## Deliberately few figures. The lesson competes with everything else on screen,
## and a full twelve-piece board is mostly noise while you are learning what a
## straight line means.
## Every placement here is load-bearing, and the constraint is stricter than it
## looks: the board is drawn EXACTLY as it is in a real match, so the scenario
## cannot lean on the tutorial hiding inconvenient options. At each step the
## game's own highlighting must already point at one answer, or the prompt asks
## a question the board answers twice.
##
## That rules out two arrangements that look fine on paper. The keeper may not
## stand beside the ball (he would be a second legal way to start), and he may
## not sit on any straight line out of A or B (he would be a second legal pass).
## Hence (1,9) rather than the goalmouth — off his line, but out of the lesson.
const BALL := Vector2i(3, 7)
const MINE := [
	{"cell": Vector2i(1, 9), "number": 1, "role": "gk"},
	{"cell": Vector2i(3, 6), "number": 4, "role": "field"},   # A — beside the ball
	{"cell": Vector2i(5, 6), "number": 5, "role": "field"},   # B — straight right of A
	{"cell": Vector2i(5, 3), "number": 6, "role": "field"},   # C — straight up from B
]
## One opponent, doing two jobs. Some of C's shooting squares fall beside him and
## others don't — that contrast is the whole of step 4. And he stands on the one
## diagonal out of C that runs into the goalmouth, corking it.
##
## That second job matters more than it sounds. Step 4 accepts any square away
## from him, and one of those squares was a goal: the ball went in, the goal
## cinematic played, the sides kicked off again, and the lesson was over three
## steps early with nothing taught. Scoring is not something to forbid with a
## message — it is the whole point of the game — so the position simply doesn't
## offer it here.
##
## C is likewise NOT on a straight line from A: with one, A could pass straight
## past B to C, and the chaining step would have nothing left to teach.
const THEIRS := [
	{"cell": Vector2i(4, 2), "number": 1, "role": "gk"},
]

const FIRST := Vector2i(3, 6)   # A
const SECOND := Vector2i(5, 6)  # B
const THIRD := Vector2i(5, 3)   # C
const SAFE_SHOT := Vector2i(5, 0)
const RISKY_SHOT := Vector2i(4, 3)  # right below the opponent on (4,2)

enum Step { PICK, CONNECT, CHAIN, SHOOT, MOVE, DONE }

var step: int = Step.PICK


static func home_formation() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in MINE:
		out.append(p.duplicate())
	return out


static func away_formation() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in THEIRS:
		out.append(p.duplicate())
	return out


## Split in two on purpose. The RULE goes up top where there is room to wrap;
## the ACTION goes in the footer, which is a single narrow strip — one long
## sentence there simply ran off both edges of the screen.
func lesson() -> String:
	match step:
		Step.PICK:
			return "You have the ball while one of your players stands next to it."
		Step.CONNECT:
			return "The ball travels only in straight lines, until something blocks it."
		Step.CHAIN:
			return "You can connect as many players as you like."
		Step.SHOOT:
			return "The last player must kick the ball away."
		Step.MOVE:
			return "A turn is two things: play the ball, then move a player."
	return "That's it — the rest you'll pick up playing."


## Short enough for the footer. Imperative, one line, no explanation.
func prompt() -> String:
	match step:
		Step.PICK:
			return "Tap that player"
		Step.CONNECT:
			return "Tap the teammate it can reach"
		Step.CHAIN:
			return "Tap the next one"
		Step.SHOOT:
			return "Pick an empty square, not next to an opponent"
		Step.MOVE:
			return "Move any player"
	return ""


## Cells the player may act on right now. Everything else is ignored, so a
## stray tap can't produce a result that muddles the lesson being taught.
## Empty means "no restriction" (the MOVE step hands the board back).
func allowed_cells() -> Array[Vector2i]:
	match step:
		Step.PICK:
			return [FIRST, BALL]  # the ball is allowed so the mistake can be answered
		Step.CONNECT:
			return [SECOND]
		Step.CHAIN:
			return [THIRD]
		Step.SHOOT:
			# No shortlist. Every square the rules allow is on offer, and the ones
			# beside the opponent are turned away by refusal() with the reason.
			# Naming one correct square would teach that square; this teaches the
			# rule, which is the only part that survives leaving the tutorial.
			return []
	return []


func allows(cell: Vector2i) -> bool:
	var cells := allowed_cells()
	return cells.is_empty() or cell in cells


## Why a permitted-but-wrong choice was refused. Empty = let it through.
##
## Only one kind exists: a shot that parks the ball beside an opponent. Those are
## offered rather than hidden, because "don't leave it there" only means
## something if leaving it there was possible.
func refusal(cell: Vector2i) -> String:
	if step == Step.SHOOT and beside_opponent(cell):
		return "He is standing right there — he'd take it straight off you."
	return ""


## Said when a tap lands on something real but not part of this step. The board
## is the game's own board, so a wrong tap is a fair mistake — answering with
## silence is what made the game feel broken in the first place.
func nudge(_cell: Vector2i) -> String:
	match step:
		Step.PICK:
			return "Not him — only a player standing beside the ball can play it."
		Step.CONNECT, Step.CHAIN:
			return "Not there — follow the straight line out of the ball."
	return ""


func beside_opponent(cell: Vector2i) -> bool:
	for p in THEIRS:
		var c: Vector2i = p["cell"]
		if maxi(absi(cell.x - c.x), absi(cell.y - c.y)) <= 1:
			return true
	return false


## Told what the player just did. Returns true if the lesson moved on.
func on_action(kind: String, cell: Vector2i) -> bool:
	var before := step
	match step:
		Step.PICK:
			if kind == "begin" and cell == FIRST:
				step = Step.CONNECT
		Step.CONNECT:
			if kind == "extend" and cell == SECOND:
				step = Step.CHAIN
		Step.CHAIN:
			if kind == "extend" and cell == THIRD:
				step = Step.SHOOT
		Step.SHOOT:
			if kind == "shoot" and not beside_opponent(cell):
				step = Step.MOVE
		Step.MOVE:
			if kind == "move":
				step = Step.DONE
	return step != before


func finished() -> bool:
	return step == Step.DONE
