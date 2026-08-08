class_name Tutorial
extends RefCounted

## The four things a first-time player has to work out, in the order the RULES
## make them happen. Pure logic — no nodes, no drawing. main.gd asks it what is
## allowed and tells it what happened; everything visual stays in the view
## layer, same split as MatchState.
##
## Written from watching someone play for the first time. Their mistakes, in
## order: tapped the BALL expecting to pick it up; kicked it to where the
## opponent could take it; never realised several players could be chained; and
## tapped a teammate expecting a pass when that teammate wasn't on a straight
## line at all.
##
## Three of those four are one misunderstanding: **the ball only travels in
## straight lines**. Not knowing that, the highlighted squares look arbitrary,
## so they stop being read as information. That is why the passing steps are the
## centre of this and why the rays are drawn rather than described.
##
## REBUILT for the move-then-kick turn (2026-08-07). The old lesson opened by
## tapping the man the ball was already under, because a turn used to start with
## the ball. A turn now starts with a MOVE, so the first thing taught is the
## first thing that happens: walk a player onto the loose ball. That also folds
## two old steps into one — stepping on the ball IS taking possession — and
## drops the old trailing move step, because the move is no longer at the end.
##
## Note what is NOT taught: gestures. Tap does everything, so there is nothing
## to learn about how to touch the screen — only about how to read the board.

## Deliberately few figures. The lesson competes with everything else on screen,
## and a full twelve-piece board is mostly noise while you are learning what a
## straight line means.
##
## Every placement here is load-bearing, and the constraint is stricter than it
## looks: the board is drawn EXACTLY as it is in a real match, so the scenario
## cannot lean on the tutorial hiding inconvenient options. At each step the
## game's own highlighting must already point at one answer, or the prompt asks
## a question the board answers twice. test_tutorial checks every one of these
## against the real MatchState — none of it is safe to nudge by eye.
##
## The ball starts LOOSE, on nobody. That is the whole first lesson.
const BALL := Vector2i(3, 7)

## A starts one square above the ball and is the ONLY figure that can reach it:
## B is three squares away (movement reaches two), C is not on a line to it at
## all, and the keeper can only ever land on his own goal cells. So "move that
## player onto the ball" has exactly one answer, even though every figure lights
## up as movable — which is what a real match's MOVE phase looks like.
##
## The keeper sits at (2,9) rather than the middle of his goal: from the ball's
## square (3,9) is a straight line down, so a keeper there would be a second
## legal pass and the straight-line step would have two answers.
const MINE := [
	{"cell": Vector2i(2, 9), "number": 1, "role": "gk"},
	{"cell": Vector2i(3, 6), "number": 4, "role": "field"},   # A — one step above the ball
	{"cell": Vector2i(6, 7), "number": 5, "role": "field"},   # B — straight right of the ball
	{"cell": Vector2i(6, 5), "number": 6, "role": "field"},   # C — straight up from B
]

## One opponent, doing two jobs. Some of C's shooting squares fall beside him and
## others don't — that contrast is the whole of the last step.
##
## The second job matters more than it sounds. The last step accepts any square
## away from him, and if one of those squares were a goal the ball would go in,
## the goal cinematic would play, the sides would kick off again, and the lesson
## would be over two steps early with nothing taught. Scoring is not something to
## forbid with a message — it is the whole point of the game — so the position
## simply doesn't offer it: C stands in his own half, which puts the opponent's
## net out of reach by the ordinary rule, and no other ray from him reaches a
## goal cell either.
const THEIRS := [
	{"cell": Vector2i(5, 2), "number": 5, "role": "field"},
]

const FIRST_FROM := Vector2i(3, 6)  # A, before he collects it
const FIRST := BALL                 # A, standing on the ball
const SECOND := Vector2i(6, 7)      # B
const THIRD := Vector2i(6, 5)       # C
## Both on the SAME ray north out of C, one square apart: the contrast the step
## teaches is then purely about the opponent standing there, not about direction.
const SAFE_SHOT := Vector2i(6, 0)
const RISKY_SHOT := Vector2i(6, 1)  # diagonally off the opponent on (5,2)

## The ball is loose. Nobody has it, and the first move of the lesson is walking
## onto it — which is how possession works in every turn after this one too.
static func ball_start() -> Vector2i:
	return BALL


enum Step { COLLECT, CONNECT, CHAIN, SHOOT, DONE }

var step: int = Step.COLLECT


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


## The section the player is in, and the reason the refusals no longer have to
## argue. Under a heading that says PASS THE BALL, turning away an early kick
## isn't a claim that kicking is against the rules — it is obviously just not
## what this part is about. Before, every "not yet" read as a rule, and it wasn't
## one: in a real game you may kick wherever the rules allow.
##
## The names are the ones the game already owns — the titles of the instruction
## cards this tutorial replaced. PASS THE BALL covers three steps because card 1
## does; a heading that DOESN'T change is how the player knows they are still on
## the same idea.
func title() -> String:
	match step:
		Step.COLLECT:
			return "TAKE POSSESSION"
		Step.CONNECT, Step.CHAIN, Step.SHOOT:
			return "PASS THE BALL"
	return "THAT'S A TURN"


## Split in two on purpose. The RULE goes up top where there is room to wrap;
## the ACTION goes in the footer, which is a single narrow strip — one long
## sentence there simply ran off both edges of the screen.
## Each of these has to fit the strip the HUD bar vacates, at a heading size that
## matches every other screen in the game — so one line, and no clause that is
## only there for rhythm.
func lesson() -> String:
	match step:
		Step.COLLECT:
			return "Step onto the ball and it is yours."
		Step.CONNECT:
			return "The ball only moves in straight lines."
		Step.CHAIN:
			return "A pass can carry on through more players."
		Step.SHOOT:
			# The one genuinely new rule of the move-then-kick turn, and the one
			# a player will otherwise discover by having the turn taken off them.
			return "You can't keep the ball — finish with a kick."
	# Says the shape of every turn from here on, now that both halves have been
	# played once in the order they really happen.
	return "Move first, then play the ball."


## Short enough for the footer. Imperative, one line, no explanation.
func prompt() -> String:
	match step:
		Step.COLLECT:
			return "Move that player onto the ball"
		Step.CONNECT:
			return "Tap the teammate in line"
		Step.CHAIN:
			return "Tap the next one"
		Step.SHOOT:
			return "Kick it to an empty square"
	# DONE still needs a line: the footer stays on screen for a beat after the
	# last kick, and left empty the match's own turn hint filled the gap.
	return "Nice one"


## Cells the player may act on right now. Everything else is ignored, so a
## stray tap can't produce a result that muddles the lesson being taught.
## Empty means "no restriction".
func allowed_cells() -> Array[Vector2i]:
	match step:
		Step.COLLECT:
			# The figure to pick up, and the square to put him on. Both are
			# needed: the move is two taps, and the second one is the ball.
			return [FIRST_FROM, BALL]
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
	# The man holding the ball is ALWAYS tappable, whatever step we are on.
	#
	# Tapping him closes the chain, and that gesture is never gated — it goes
	# through step_back, which asks no permission. Gating the tap that REOPENS it
	# therefore strands the lesson in a state it will not let you leave: the ball
	# at his feet, the turn owing a kick, every square dark, and every further tap
	# refused. Reported exactly that way, and the log showed the tap landing on
	# him with the rules agreeing he was the carrier.
	#
	# Costs the lesson nothing: opening the chain is not a step any more (COLLECT
	# advances on the move), so this can never skip anything ahead.
	if cell == FIRST:
		return true
	var cells := allowed_cells()
	return cells.is_empty() or cell in cells


## Why a permitted-but-wrong choice was refused. Empty = let it through.
##
## Only one kind exists: a kick that parks the ball beside an opponent. Those are
## offered rather than hidden, because "don't leave it there" only means
## something if leaving it there was possible.
## "He is standing right there" said nothing about WHICH he — the player kicking
## or the one waiting. Name the consequence instead of the geometry: the player
## can see who is standing where, what they can't see is what happens next.
func refusal(cell: Vector2i) -> String:
	if step == Step.SHOOT and beside_opponent(cell):
		return "Land it there and they take it off you"
	return ""


## Said when a tap lands on something real but not part of this step. The board
## is the game's own board, so a wrong tap is a fair mistake — answering with
## silence is what made the game feel broken in the first place.
##
## Mid-chain there are two different wrong taps and they need different answers.
## An empty square in a straight line is a KICK: the player read the board
## correctly and just put the ball away a step early. Telling them that isn't in
## line is simply false, and a correction that is wrong about what you did is
## worse than none.
func nudge(cell: Vector2i) -> String:
	match step:
		Step.COLLECT:
			return "Only one player can reach the ball this turn"
		Step.CONNECT, Step.CHAIN:
			if is_mine(cell):
				return "That player is not in line with the ball"
			# The heading above already says PASS THE BALL, so this can simply be
			# the next thing to do rather than a defence of why the kick was
			# turned away.
			return "One more pass first"
	return ""


## Where my players stand at the steps this is asked about — which is AFTER A has
## collected the ball, since nudge() is only consulted from CONNECT onwards. His
## starting square is empty by then and the ball's square is the one he's on.
func is_mine(cell: Vector2i) -> bool:
	if cell == FIRST:
		return true
	for p in MINE:
		if p["cell"] == cell and p["cell"] != FIRST_FROM:
			return true
	return false


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
		Step.COLLECT:
			if kind == "move" and cell == BALL:
				step = Step.CONNECT
		Step.CONNECT:
			if kind == "extend" and cell == SECOND:
				step = Step.CHAIN
		Step.CHAIN:
			if kind == "extend" and cell == THIRD:
				step = Step.SHOOT
		Step.SHOOT:
			if kind == "shoot" and not beside_opponent(cell):
				step = Step.DONE
	return step != before


func finished() -> bool:
	return step == Step.DONE
