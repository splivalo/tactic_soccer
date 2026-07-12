extends SceneTree

## Headless unit test for MatchState. Run:
##   godot --headless -s res://scripts/tests/test_match.gd
## Verifies the core rules without any clicking.

var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _initialize() -> void:
	var ms := MatchState.new()
	ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)

	# Kick-off: home has the ball (GK 3,9 and mid 3,7 are next to ball 3,8).
	_check(ms.phase == MatchState.Phase.COMBO, "kickoff phase = COMBO")
	_check(ms.team_has_ball("HomeTeam"), "home has the ball")
	var starters := ms.combo_starters()
	_check(Vector2i(3, 9) in starters and Vector2i(3, 7) in starters, "starters incl GK(3,9) & mid(3,7)")

	# Connect from the mid: GK reachable straight down; (4,7) is a free shoot cell.
	_check(ms.begin(Vector2i(3, 7)), "begin chain at mid (3,7)")
	_check(Vector2i(3, 9) in ms.combo_pass_targets(), "can pass mid -> GK")
	_check(Vector2i(4, 7) in ms.combo_shoot_targets(), "empty (4,7) is a shoot cell")
	_check(not (Vector2i(3, 8) in ms.combo_shoot_targets()), "cannot shoot back onto the ball's own cell (3,8)")

	# Goalkeeper stays inside its 3 goal cells.
	var gk_moves := ms.move_targets(Vector2i(3, 9))
	var gk_ok := true
	for c in gk_moves:
		if not ms.is_own_goal_cell(c, "HomeTeam"):
			gk_ok = false
	_check(gk_ok and gk_moves.size() > 0, "GK moves only within its goal (%s)" % [gk_moves])

	# Outfield figures may never step into a goal cell.
	var mid_moves := ms.move_targets(Vector2i(3, 7))
	var no_goal := true
	for c in mid_moves:
		if ms.is_goal_cell(c):
			no_goal = false
	_check(no_goal, "outfield move targets exclude goal cells")

	# Scoring: home figure on the opponent half shoots into the empty opponent goal.
	ms.pieces.clear()
	ms.pieces[Vector2i(2, 1)] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.pieces[Vector2i(3, 0)] = {"team": "AwayTeam", "role": "gk", "id": 1}  # away GK on its goal
	ms.ball = Vector2i(2, 2)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	_check(ms.begin(Vector2i(2, 1)), "begin chain near opponent goal")
	_check(Vector2i(2, 0) in ms.combo_shoot_targets(), "empty goal cell (2,0) is shootable")
	var res := ms.execute_combo(Vector2i(2, 0))
	_check(res["ok"] and res["goal"], "shot into opponent goal = GOAL")
	_check(ms.score["HomeTeam"] == 1, "home score is 1")
	_check(res["kickoff"] == "AwayTeam", "conceding team (away) kicks off")

	# A shot that is NOT a goal must force a MOVE next.
	ms.pieces.clear()
	ms.pieces[Vector2i(3, 5)] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.ball = Vector2i(3, 6)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(Vector2i(3, 5))
	var res2 := ms.execute_combo(Vector2i(3, 4))
	_check(res2["ok"] and not res2["goal"] and ms.phase == MatchState.Phase.MOVE, "non-goal shot -> MOVE phase")

	# Rewind: clicking an already-chosen chain figure truncates back to it,
	# instead of looping back to it as a fresh pass (1->2->3->2).
	ms.pieces.clear()
	var a := Vector2i(3, 7)
	var b := Vector2i(4, 6)
	var c := Vector2i(2, 6)
	ms.pieces[a] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.pieces[b] = {"team": "HomeTeam", "role": "field", "id": 1}
	ms.pieces[c] = {"team": "HomeTeam", "role": "field", "id": 2}
	ms.ball = Vector2i(3, 8)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(a)
	ms.extend(b)
	ms.extend(c)
	_check(ms.chain == [a, b, c], "chain built 1->2->3 (%s)" % [ms.chain])
	_check(ms.rewind(b), "rewind(2) succeeds when 2 is in the chain")
	_check(ms.chain == [a, b], "rewind truncates chain to 1->2 (%s)" % [ms.chain])
	_check(c in ms.combo_pass_targets(), "3 is a fresh pass option again from 2 (not stuck excluded)")
	_check(not ms.rewind(Vector2i(0, 0)), "rewind on a cell not in the chain fails")
	var res3 := ms.execute_combo(Vector2i(5, 6))  # shoot from 2, not through the old 3
	_check(res3["ok"] and res3["path"] == [Vector2i(3, 8), a, b, Vector2i(5, 6)],
		"executed path has no leftover 3 after rewind (%s)" % [res3["path"]])

	# Board.nearest_cell: drag-and-snap targeting (pure geometry, no input needed).
	var cands: Array[Vector2i] = [Vector2i(3, 5), Vector2i(4, 5), Vector2i(2, 6)]
	var w35 := Board.grid_to_world(3, 5)
	var near_35 := Board.nearest_cell(Vector2(w35.x + 0.1, w35.z + 0.05), cands, 1.0)
	_check(near_35 == Vector2i(3, 5), "nearest_cell snaps to the closest candidate (%s)" % [near_35])
	var far_point := Vector2(w35.x + 50.0, w35.z)
	_check(Board.nearest_cell(far_point, cands, 1.0) == Vector2i(-1, -1),
		"nearest_cell returns NO_CELL when nothing is within max_dist")
	_check(Board.nearest_cell(Vector2.ZERO, [], 5.0) == Vector2i(-1, -1),
		"nearest_cell returns NO_CELL for an empty candidate list")

	# Board.ray_vertical_closest: hit-testing a tall figure with a tilted ray
	# (the actual bug — tapping a figure's body raycasts past its base tile).
	# A downward-and-forward ray from above should pass near (5,0,5) at some
	# positive height, not just at y=0.
	var r := Board.ray_vertical_closest(Vector3(5, 10, 0), Vector3(0, -1, 1).normalized(), 5.0, 5.0)
	_check(r["xz_dist"] < 0.01, "ray_vertical_closest finds the column (dist=%.4f)" % r["xz_dist"])
	_check(r["y"] > 0.0 and r["y"] < 10.0, "ray_vertical_closest reports a plausible height (%.2f)" % r["y"])
	var straight_down := Board.ray_vertical_closest(Vector3(0, 5, 0), Vector3.DOWN, 5.0, 5.0)
	_check(straight_down["xz_dist"] > 4.0, "a ray that can't reach the column reports a large distance")

	# Offside: shooter is offside only when ALL outfield opponents are behind
	# them; the goalkeeper doesn't count (it's pinned to the goal line, so
	# including it would make offside impossible to ever trigger).
	ms.pieces.clear()
	var striker := Vector2i(4, 2)
	ms.pieces[striker] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.pieces[Vector2i(3, 0)] = {"team": "AwayTeam", "role": "gk", "id": 1}     # on the goal line
	ms.pieces[Vector2i(1, 4)] = {"team": "AwayTeam", "role": "field", "id": 2} # behind the striker
	ms.ball = Vector2i(3, 3)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(striker)
	_check(ms.is_offside(striker, "HomeTeam"), "offside: GK alone can't cover, all outfield defenders behind")
	_check(ms.offside_line_row("HomeTeam") == 4, "offside_line_row is the last outfield defender's row (%d)" % ms.offside_line_row("HomeTeam"))
	var score_before: int = ms.score["HomeTeam"]
	var res_off := ms.execute_combo(Vector2i(2, 0))
	_check(res_off["ok"] and res_off["offside"] and not res_off["goal"], "offside shot into goal doesn't score")
	_check(res_off["offside_shooter"] == striker, "offside result carries the shooter's cell")
	_check(res_off["offside_line_row"] == 4, "offside result carries the defensive line row")
	_check(ms.score["HomeTeam"] == score_before, "score unchanged after an offside goal attempt")

	# ...but if one defender is level with (or ahead of) the striker, no offside.
	ms.pieces.clear()
	ms.pieces[striker] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.pieces[Vector2i(3, 0)] = {"team": "AwayTeam", "role": "gk", "id": 1}
	ms.pieces[Vector2i(1, 2)] = {"team": "AwayTeam", "role": "field", "id": 2} # level with the striker
	ms.ball = Vector2i(3, 3)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(striker)
	_check(not ms.is_offside(striker, "HomeTeam"), "not offside: a defender level with the striker covers")
	var res_ok := ms.execute_combo(Vector2i(2, 0))
	_check(res_ok["ok"] and res_ok["goal"] and not res_ok["offside"], "onside shot into the empty goal scores")

	# Cards (verified against the original 2006 game's decompiled source):
	# a violation is landing the ball within 1 cell of the figure that took
	# this team's own last CLEAN shot — regardless of which figure shoots
	# THIS time — unless that reference figure has since moved. 3 strikes:
	# 1st=yellow, 2nd=red, 3rd=must remove a figure.
	ms.pieces.clear()
	var fig_a := Vector2i(3, 5)
	var fig_b := Vector2i(3, 1)
	ms.pieces[fig_a] = {"team": "HomeTeam", "role": "field", "id": 7}
	ms.pieces[fig_b] = {"team": "HomeTeam", "role": "field", "id": 8}
	ms.current = "HomeTeam"
	ms.stall_ref_id["HomeTeam"] = -1
	ms.stall_ref_cell["HomeTeam"] = Vector2i(-1, -1)
	ms.yellow_card["HomeTeam"] = false
	ms.red_card["HomeTeam"] = false
	ms.foul_count["HomeTeam"] = 0

	# Shot 1 (fig_a): first ever shot -> just sets the reference, no violation possible yet.
	ms.ball = Vector2i(3, 6); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_a)
	var s1 := ms.execute_combo(Vector2i(1, 5))
	_check(s1["card"] == "" and ms.stall_ref_id["HomeTeam"] == 7 and ms.stall_ref_cell["HomeTeam"] == fig_a,
		"first shot just records the reference figure (fig_a)")

	# Shot 2 (fig_a again): lands FAR from the reference (its own, unmoved
	# cell) -> safe. This is the exact scenario the user flagged: don't
	# punish the same figure shooting again if it's not actually repeating.
	ms.ball = Vector2i(3, 6); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_a)
	var s2 := ms.execute_combo(Vector2i(3, 2))
	_check(s2["card"] == "", "same figure, far landing cell -> not a violation")

	# Shot 3 (fig_b, a DIFFERENT figure): lands next to the reference figure
	# (fig_a, which hasn't moved) -> violation, even though a different
	# figure is shooting. This is exactly what the old "same figure" rule missed.
	ms.ball = Vector2i(3, 2); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_b)
	var s3 := ms.execute_combo(Vector2i(3, 4))
	_check(s3["card"] == "yellow" and ms.yellow_card["HomeTeam"] and ms.foul_count["HomeTeam"] == 1,
		"a different figure landing next to the unmoved reference figure -> yellow card")
	_check(ms.stall_ref_id["HomeTeam"] == -1, "reference clears after a violation (fresh start)")

	# Shot 4 (fig_a): the reference was just cleared, so this is safe again.
	ms.ball = Vector2i(3, 6); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_a)
	var s4 := ms.execute_combo(Vector2i(1, 5))
	_check(s4["card"] == "", "fresh reference after the previous violation cleared it")

	# Shot 5 (fig_b): violates again -> 2nd strike -> red card.
	ms.ball = Vector2i(3, 2); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_b)
	var s5 := ms.execute_combo(Vector2i(3, 4))
	_check(s5["card"] == "red" and ms.red_card["HomeTeam"] and ms.foul_count["HomeTeam"] == 2,
		"2nd violation -> red card (no forced removal yet)")

	# One more clean shot, then a 3rd violation -> forced removal.
	ms.ball = Vector2i(3, 6); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_a)
	ms.execute_combo(Vector2i(1, 5))
	ms.ball = Vector2i(3, 2); ms.phase = MatchState.Phase.COMBO; ms.begin(fig_b)
	var s7 := ms.execute_combo(Vector2i(3, 4))
	_check(s7["must_remove"] == "HomeTeam" and ms.foul_count["HomeTeam"] == 3, "3rd violation -> must remove a figure")
	_check(ms.phase == MatchState.Phase.REMOVE and ms.pending_removal == "HomeTeam",
		"3rd violation forces the carded team to remove a figure")

	_check(not ms.remove_figure(Vector2i(9, 9)), "remove_figure fails for an empty cell")
	var removed := ms.remove_figure(fig_b)
	_check(removed, "remove_figure succeeds for the carded team's own figure")
	_check(not ms.pieces.has(fig_b), "removed figure is gone from pieces")
	_check(ms.pending_removal == "", "pending_removal is cleared after removal")
	_check(ms.current == "AwayTeam", "removal spends the turn (hands it to the opponent)")

	# Moving the reference figure clears it (matches the tutorial text: "this
	# counts only when the previous figure has not been moved in the meantime").
	ms.pieces.clear()
	ms.pieces[fig_a] = {"team": "HomeTeam", "role": "field", "id": 7}
	ms.current = "HomeTeam"
	ms.stall_ref_id["HomeTeam"] = 7
	ms.stall_ref_cell["HomeTeam"] = fig_a
	ms.phase = MatchState.Phase.MOVE
	_check(ms.do_move(fig_a, Vector2i(4, 5)), "move the reference figure")
	_check(ms.stall_ref_id["HomeTeam"] == -1, "moving the reference figure clears the stalling reference")

	# MatchState.own_cells()
	ms.pieces.clear()
	ms.pieces[Vector2i(1, 1)] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.pieces[Vector2i(2, 2)] = {"team": "AwayTeam", "role": "field", "id": 1}
	ms.current = "HomeTeam"
	_check(ms.own_cells() == [Vector2i(1, 1)], "own_cells returns only the current team's figures (%s)" % [ms.own_cells()])

	if _fail == 0:
		print("TEST_MATCH: ALL PASSED")
	else:
		printerr("TEST_MATCH: %d FAILED" % _fail)
	quit(_fail)
