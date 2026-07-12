class_name Formations
extends RefCounted

## Default starting line-ups for both teams on the 7x10 grid.
## Each piece is a Dictionary: {cell: Vector2i, number: int, role: "gk"|"field"}.
##
## Rule: a team may only stand on its OWN half at kick-off.
##   HOME = near-camera half, rows 5-9 (defends the +Z goal), attacks toward -Z.
##   AWAY = far half,        rows 0-4 (defends the -Z goal), attacks toward +Z.
## Numbers 1-6 (single digits — that's all the number textures we have for now):
## GK wears 1, outfield players 2-6.

## Near-camera team (rows 5-9).
static func home() -> Array[Dictionary]:
	return [
		{"cell": Vector2i(3, 9), "number": 1, "role": "gk"},
		{"cell": Vector2i(5, 8), "number": 2, "role": "field"},
		{"cell": Vector2i(1, 8), "number": 3, "role": "field"},
		{"cell": Vector2i(3, 7), "number": 4, "role": "field"},
		{"cell": Vector2i(4, 6), "number": 5, "role": "field"},
		{"cell": Vector2i(2, 6), "number": 6, "role": "field"},
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
	]
