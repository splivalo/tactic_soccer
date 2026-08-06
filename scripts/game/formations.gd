class_name Formations
extends RefCounted

## Default starting line-ups for both teams on the 7x10 grid.
## Each piece is a Dictionary: {cell: Vector2i, number: int, role: "gk"|"field"}.
##
## Rule: a team may only stand on its OWN half at kick-off.
##   HOME = near-camera half, rows 5-9 (defends the +Z goal), attacks toward -Z.
##   AWAY = far half,        rows 0-4 (defends the -Z goal), attacks toward +Z.
## GK wears 1, outfield players 2-6.
##
## FOUR outfield since 2026-08-05, down from six, and the reason is not balance.
## Squad size was measured from four to ten a side and possession does not care:
## runs of 26, 27.5, 26.5, 28.6, 27.7 across the whole range, with no trend, and
## match length just as flat. The one thing it does control is how much a player
## has to weigh each turn — 36, 44, 50, 59, 65 choices, dead linear.
##
## Four puts that at 36. Chess sits around 35, which is about the ceiling a
## person can plan against, and this game was asking 50. Nothing else moved.
##
## Shape is 2-1-1: a wide pair at the back, one man on the ball at kickoff, one
## ahead. The man on (3,7) is load-bearing — without him the keeper is the only
## figure beside the kickoff ball, so every match would open with him playing it.

## Near-camera team (rows 5-9).
static func home() -> Array[Dictionary]:
	return [
		{"cell": Vector2i(3, 9), "number": 1, "role": "gk"},
		{"cell": Vector2i(1, 8), "number": 2, "role": "field"},
		{"cell": Vector2i(5, 8), "number": 3, "role": "field"},
		{"cell": Vector2i(3, 7), "number": 4, "role": "field"},
		{"cell": Vector2i(2, 5), "number": 5, "role": "field"},
		{"cell": Vector2i(4, 5), "number": 6, "role": "field"},
	]


## Far team (rows 0-4) — mirror of home.
static func away() -> Array[Dictionary]:
	return [
		{"cell": Vector2i(3, 0), "number": 1, "role": "gk"},
		{"cell": Vector2i(5, 1), "number": 2, "role": "field"},
		{"cell": Vector2i(1, 1), "number": 3, "role": "field"},
		{"cell": Vector2i(3, 2), "number": 4, "role": "field"},
		{"cell": Vector2i(4, 4), "number": 5, "role": "field"},
		{"cell": Vector2i(2, 4), "number": 6, "role": "field"},
	]
