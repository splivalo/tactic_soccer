extends SceneTree
## Throwaway smoke test — time-wasting card on a MOVE expiry.

func _initialize() -> void:
	var home := [
		{"cell": Vector2i(3, 8), "role": "field"},
		{"cell": Vector2i(3, 6), "role": "field"},
	]
	var away := [{"cell": Vector2i(0, 0), "role": "field"}]

	# --- A COMBO expiry must NOT card (you already lose the whole turn).
	var ms := MatchState.new()
	ms.setup(home, away, Vector2i(3, 7), "HomeTeam", 99)
	assert(ms.phase == MatchState.Phase.COMBO)
	ms.forfeit(true)
	assert(ms.last_move_card == "", "COMBO expiry must not book anyone")
	assert(ms.foul_count["HomeTeam"] == 0)
	print("COMBO expiry: no card (correct)")

	# --- A MOVE expiry MUST card: 1st = yellow.
	ms = MatchState.new()
	ms.setup(home, away, Vector2i(3, 7), "HomeTeam", 99)
	assert(ms.begin(Vector2i(3, 8)))
	var target := Vector2i(-1, -1)
	for t in ms.combo_shoot_targets():
		if not ms.is_opponent_goal(t, "HomeTeam") and not ms.is_own_goal_cell(t, "HomeTeam"):
			target = t
			break
	assert(target != Vector2i(-1, -1))
	assert(ms.execute_combo(target)["ok"])
	assert(ms.phase == MatchState.Phase.MOVE)
	ms.forfeit(true)
	assert(ms.last_move_card == "yellow", "MOVE expiry -> yellow, got '%s'" % ms.last_move_card)
	assert(ms.last_card_team == "HomeTeam")
	assert(ms.yellow_card["HomeTeam"])
	assert(ms.current == "AwayTeam", "a yellow still hands the turn over")
	print("MOVE expiry: yellow card, turn passed (correct)")

	# --- 2nd offence = red AND the carded team must remove a figure now.
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.MOVE
	ms._move_is_reactive = true
	ms.forfeit(true)
	assert(ms.last_move_card == "red", "2nd offence -> red, got '%s'" % ms.last_move_card)
	assert(ms.red_card["HomeTeam"])
	assert(ms.phase == MatchState.Phase.REMOVE, "red owes a removal right away")
	assert(ms.current == "HomeTeam", "the carded team serves its own removal")
	assert(ms.pending_removal == "HomeTeam")
	print("2nd MOVE expiry: red card + REMOVE handed back to the offender (correct)")

	# --- A non-timeout forfeit (AI found no legal action) must never card.
	ms = MatchState.new()
	ms.setup(home, away, Vector2i(3, 7), "HomeTeam", 99)
	ms.phase = MatchState.Phase.MOVE
	ms.forfeit()
	assert(ms.last_move_card == "", "a plain forfeit must not book anyone")
	print("plain forfeit(): no card (correct)")

	print("ALL ASSERTIONS PASSED")
	quit()
