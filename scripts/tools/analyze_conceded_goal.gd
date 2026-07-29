extends SceneTree
## Throwaway forensics — reconstructs the position from a human's console log
## at the moment BEFORE the AI's last reactive move, and asks the only
## question that settles "was that goal earned, or was the AI dumb?": was
## there ANY legal Away move that would have denied HomeTeam a goal on the
## very next turn? Uses the AI's own threat search (team_can_score_next), so
## the answer is in exactly the terms the AI itself reasons in.
##
## Reconstruction: Away is untouched Formations.away() walked forward through
## every "MOVE:" line in the log. Home was hand-placed by the human, so only
## the pieces the log actually shows moving are known for certain; the rest
## are parked deep in Home's own half where they cannot touch these lanes.
## Extra Home pieces could only ADD scoring routes, never remove one, so an
## "unstoppable" verdict here is a lower bound.
## Run: godot --headless -s res://scripts/tools/analyze_conceded_goal.gd

func _initialize() -> void:
	var ms := MatchState.new()
	# 2026-07-29 log, ball on (4,4), just before Away played (2,2) -> (3,3).
	# Away = Formations.away() after its logged moves:
	#   (4,3)->(2,5)  (5,1)->(5,3)->(6,4)  (2,3)->(2,2)
	var away := [
		{"cell": Vector2i(3, 0), "role": "gk"},    # never moved
		{"cell": Vector2i(1, 1), "role": "field"}, # never moved
		{"cell": Vector2i(3, 2), "role": "field"}, # never moved
		{"cell": Vector2i(2, 5), "role": "field"},
		{"cell": Vector2i(6, 4), "role": "field"},
		{"cell": Vector2i(2, 2), "role": "field"}, # the piece about to move
	]
	# Home, as far as the log pins it down: (0,5)->(1,4)->(1,3),
	# (5,5)->(5,4)->(5,3), (5,7)->(6,6); GK + two more never moved.
	var home := [
		{"cell": Vector2i(3, 9), "role": "gk"},
		{"cell": Vector2i(5, 3), "role": "field"}, # on the ball -- the eventual shooter
		{"cell": Vector2i(1, 3), "role": "field"},
		{"cell": Vector2i(6, 6), "role": "field"},
		{"cell": Vector2i(2, 8), "role": "field"}, # never moved -- parked at home
		{"cell": Vector2i(4, 8), "role": "field"}, # never moved -- parked at home
	]
	ms.setup(home, away, Vector2i(4, 4), "AwayTeam", 99)
	ms.current = "AwayTeam"
	ms.phase = MatchState.Phase.MOVE
	ms._move_is_reactive = true

	print("Ball on %s. AwayTeam to make its reactive move." % [ms.ball])
	print("Can HomeTeam score next turn as things stand? %s\n" \
		% AIPlayer.team_can_score_next(ms, "HomeTeam"))

	var total := 0
	var saves: Array[String] = []
	for from in ms.own_cells():
		for to in ms.move_targets(from):
			total += 1
			var sim: MatchState = ms.clone_for_query()
			sim.pieces.erase(from)
			sim.pieces[to] = ms.pieces[from]
			if not AIPlayer.team_can_score_next(sim, "HomeTeam"):
				saves.append("%s -> %s" % [from, to])
	print("Checked every legal Away move: %d of them." % total)
	if saves.is_empty():
		print(">>> NOT ONE prevents HomeTeam from scoring next turn.")
		print(">>> The goal was EARNED -- no defensive move existed.")
	else:
		print(">>> %d move(s) WOULD have denied the goal:" % saves.size())
		for s in saves:
			print("      %s" % s)
		print(">>> The AI had a save available and missed it.")

	var decision := AIPlayer.decide_move(ms, "Hard")
	print("\nAI's actual pick here: %s -> %s   (the log shows (2, 2) -> (3, 3))" \
		% [decision.get("from", "?"), decision.get("to", "?")])
	quit()
