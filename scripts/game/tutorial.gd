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
const BALL := Vector2i(3, 8)
const MINE := [
	{"cell": Vector2i(3, 9), "number": 1, "role": "gk"},
	{"cell": Vector2i(3, 7), "number": 4, "role": "field"},   # A — beside the ball
	{"cell": Vector2i(5, 7), "number": 5, "role": "field"},   # B — straight right of A
	{"cell": Vector2i(5, 5), "number": 6, "role": "field"},   # C — straight up from B
]
## One opponent, placed so that exactly one of the shooting squares sits beside
## him — that contrast is the whole of step 4.
const THEIRS := [
	{"cell": Vector2i(3, 4), "number": 1, "role": "gk"},
]

const FIRST := Vector2i(3, 7)   # A
const SECOND := Vector2i(5, 7)  # B
const THIRD := Vector2i(5, 5)   # C
const SAFE_SHOT := Vector2i(5, 4)
const RISKY_SHOT := Vector2i(4, 4)  # next to the opponent on (3,4)

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


## One sentence at a time, shown in the footer the placement phase already uses.
## Never a paragraph: this is read mid-action, not studied.
func prompt() -> String:
	match step:
		Step.PICK:
			return "You have the ball while a player stands next to it. Tap that player."
		Step.CONNECT:
			return "The ball only travels in straight lines, until something blocks it. Tap the teammate it can reach."
		Step.CHAIN:
			return "Keep going — connect as many players as you like."
		Step.SHOOT:
			return "The last player must kick the ball away. Don't leave it next to an opponent."
		Step.MOVE:
			return "Every turn is two things: play the ball, then move one player."
	return "That's it. The rest you'll pick up playing."


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
			return [SAFE_SHOT, RISKY_SHOT]
	return []


func allows(cell: Vector2i) -> bool:
	var cells := allowed_cells()
	return cells.is_empty() or cell in cells


## Why a permitted-but-wrong choice was refused. Empty = let it through.
##
## Only one exists: the shot that parks the ball beside an opponent. It is
## offered rather than hidden, because "don't leave it there" only means
## something if leaving it there was possible.
func refusal(cell: Vector2i) -> String:
	if step == Step.SHOOT and cell == RISKY_SHOT:
		return "He is standing right there — he'd take it straight off you."
	return ""


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
			if kind == "shoot" and cell == SAFE_SHOT:
				step = Step.MOVE
		Step.MOVE:
			if kind == "move":
				step = Step.DONE
	return step != before


func finished() -> bool:
	return step == Step.DONE


## Which cell the ray drawing should fan out from, or (-1,-1) for none. Showing
## the eight straight lines from whoever holds the ball is the single most
## useful thing on screen during the middle steps — it turns "why is that one
## lit and not that one" into something you can see rather than be told.
func ray_origin() -> Vector2i:
	match step:
		Step.CONNECT:
			return FIRST
		Step.CHAIN:
			return SECOND
		Step.SHOOT:
			return THIRD
	return Vector2i(-1, -1)
