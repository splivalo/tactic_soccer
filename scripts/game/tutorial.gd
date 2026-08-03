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

## Where the ball actually starts, which depends on what possession means.
##
## Beside A under the original rule; UNDER him once the ball belongs to whoever
## stands on it, or the tutorial opens on a board where nobody has it and step
## one asks for something the rules don't allow.
static func ball_start() -> Vector2i:
	return FIRST if MatchState.experiment_ball_underfoot else BALL


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


## The section the player is in, and the reason the refusals no longer have to
## argue. Under a heading that says PASS THE BALL, turning away an early kick
## isn't a claim that kicking is against the rules — it is obviously just not
## what this part is about. Before, every "not yet" read as a rule, and it wasn't
## one: in a real game you may shoot whenever you like, or decline the ball
## entirely and simply move someone (the closing card's HOLD THE BALL).
##
## The names are the ones the game already owns — the titles of the three
## instruction cards this tutorial replaced. PASS THE BALL covers three steps
## because card 1 does ("Chain unlimited passes, then kick into any empty
## square"); a heading that DOESN'T change is how the player knows they are still
## on the same idea.
func title() -> String:
	match step:
		Step.PICK:
			return "TAKE POSSESSION"
		Step.CONNECT, Step.CHAIN, Step.SHOOT:
			return "PASS THE BALL"
		Step.MOVE:
			return "MOVE A PLAYER"
	return "THAT'S A TURN"


## Split in two on purpose. The RULE goes up top where there is room to wrap;
## the ACTION goes in the footer, which is a single narrow strip — one long
## sentence there simply ran off both edges of the screen.
## Each of these has to fit the strip the HUD bar vacates, at a heading size that
## matches every other screen in the game — so one line, and no clause that is
## only there for rhythm.
func lesson() -> String:
	match step:
		Step.PICK:
			if MatchState.experiment_ball_underfoot:
				return "The ball belongs to whoever is standing on it."
			return "You hold the ball if a player stands beside it."
		Step.CONNECT:
			return "The ball only moves in straight lines."
		Step.CHAIN:
			return "A pass can carry on through more players."
		Step.SHOOT:
			# Not "must": a chain can be stepped back out of, and the ball can be
			# declined altogether. Describe the shape instead of imposing it.
			return "A chain ends with a kick into space."
		Step.MOVE:
			# Was "Every turn: play the ball, then move a player", which made
			# playing the ball sound compulsory. It isn't.
			return "Finish the turn by moving a player."
	return "The rest you'll pick up as you play."


## Short enough for the footer. Imperative, one line, no explanation.
func prompt() -> String:
	match step:
		Step.PICK:
			return "Tap that player"
		Step.CONNECT:
			return "Tap the teammate in line"
		Step.CHAIN:
			return "Tap the next one"
		Step.SHOOT:
			return "Kick it to an empty square"
		Step.MOVE:
			return "Move any player"
	# DONE still needs a line: the footer stays on screen for a beat after the
	# last move, and left empty the match's own turn hint filled the gap.
	return "Nice one"


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
## An empty square in a straight line is a SHOT: the player read the board
## correctly and just kicked the ball away a step early. Telling them that isn't
## in line is simply false, and a correction that is wrong about what you did is
## worse than none.
func nudge(cell: Vector2i) -> String:
	match step:
		Step.PICK:
			if MatchState.experiment_ball_underfoot:
				return "Only the player standing on the ball can play it"
			return "Only a player beside the ball can play it"
		Step.CONNECT, Step.CHAIN:
			if is_mine(cell):
				return "That player is not in line with the ball"
			# The heading above already says PASS THE BALL, so this can simply be
			# the next thing to do rather than a defence of why the kick was
			# turned away.
			return "One more pass first"
	return ""


## Nobody has moved yet at the steps this is asked about — the tutorial's only
## move is its last step — so the starting layout is still the live one.
func is_mine(cell: Vector2i) -> bool:
	for p in MINE:
		if p["cell"] == cell:
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
