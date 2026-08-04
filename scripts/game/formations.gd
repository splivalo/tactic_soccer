class_name Formations
extends RefCounted

## Default starting line-ups for both teams on the 7x10 grid.
## Each piece is a Dictionary: {cell: Vector2i, number: int, role: "gk"|"field"}.
##
## Rule: a team may only stand on its OWN half at kick-off.
##   HOME = near-camera half, rows 5-9 (defends the +Z goal), attacks toward -Z.
##   AWAY = far half,        rows 0-4 (defends the -Z goal), attacks toward +Z.
## Numbers 1-7 (single digits — that's every number texture we have):
## GK wears 1, outfield players 2-7.
##
## Six outfield rather than five since 2026-08-04. Measured: 40 matches at one
## action per turn went from 586 turns to 413, and the turns a player spends
## WITHOUT the ball — the thing that actually reads as the game dragging — from
## 312 per match to 216. Seven outfield is better again (309 / 160) and is what
## to try next; it needs one more shirt-number texture, which is the only reason
## it isn't this.

## Near-camera team (rows 5-9).
static func home() -> Array[Dictionary]:
	return [
		{"cell": Vector2i(3, 9), "number": 1, "role": "gk"},
		{"cell": Vector2i(5, 8), "number": 2, "role": "field"},
		{"cell": Vector2i(1, 8), "number": 3, "role": "field"},
		{"cell": Vector2i(3, 7), "number": 4, "role": "field"},
		{"cell": Vector2i(4, 6), "number": 5, "role": "field"},
		{"cell": Vector2i(2, 6), "number": 6, "role": "field"},
		{"cell": Vector2i(6, 7), "number": 7, "role": "field"},
	]


## Far team (rows 0-4) — mirror of home.
static func away() -> Array[Dictionary]:
	return [
		{"cell": Vector2i(3, 0), "number": 1, "role": "gk"},
		{"cell": Vector2i(1, 1), "number": 2, "role": "field"},
		{"cell": Vector2i(5, 1), "number": 3, "role": "field"},
		{"cell": Vector2i(3, 2), "number": 4, "role": "field"},
		{"cell": Vector2i(2, 3), "number": 5, "role": "field"},
		{"cell": Vector2i(4, 3), "number": 6, "role": "field"},
		{"cell": Vector2i(0, 2), "number": 7, "role": "field"},
	]
