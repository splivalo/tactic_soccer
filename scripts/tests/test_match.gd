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
	# This suite is the net for the SHIPPED two-part turn — kick, then a bonus
	# move — so it pins the single-action experiment off rather than being
	# rewritten around it. If that experiment is ever adopted, the assertions
	# about the bonus move are what needs revisiting here.
	MatchState.experiment_single_action = false
	MatchState.experiment_unlimited_move = false
	MatchState.experiment_min_kick = false
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

	# remove_figure(): during Phase.REMOVE (after a red card — now triggered by
	# position-repetition/stalling, not a contested-recovery duel, see
	# MatchState's "cards / stalling" doc comment), the carded team removes
	# one of its own figures. Drive the state there directly rather than via
	# a real card trigger — this is only testing remove_figure() itself.
	ms.setup([{"cell": Vector2i(2, 8), "role": "field"}], [{"cell": Vector2i(4, 5), "role": "field"}], Vector2i(3, 5), "HomeTeam", 99)
	ms.phase = MatchState.Phase.REMOVE
	ms.pending_removal = "HomeTeam"
	_check(not ms.remove_figure(Vector2i(9, 9)), "remove_figure fails for an empty cell")
	var removed := ms.remove_figure(Vector2i(2, 8))
	_check(removed, "remove_figure succeeds for the carded team's own figure")
	_check(not ms.pieces.has(Vector2i(2, 8)), "removed figure is gone from pieces")
	_check(ms.pending_removal == "", "pending_removal is cleared after removal")
	_check(ms.current == "AwayTeam", "removal spends the turn (hands it to the opponent)")

	# forfeit(): ran out of time to act — no move made, turn just passes (and
	# drops a pending forced removal rather than leaving the state stuck).
	ms.phase = MatchState.Phase.REMOVE
	ms.pending_removal = ms.current
	var before_forfeit: String = ms.current
	ms.forfeit()
	_check(ms.current == ms.opponent(before_forfeit), "forfeit() hands the turn to the opponent")
	_check(ms.pending_removal == "", "forfeit() clears a pending forced removal")
	_check(ms.chain.is_empty(), "forfeit() leaves no dangling chain")

	# Passing THROUGH your own goalkeeper to a teammate further along must be
	# illegal (rules/igra_pravila.md's "misaligned keeper -> AUTOGOL" rule,
	# generalized): once the ball has been PASSED (not started there) onto a
	# figure standing on one of your own goal cells, that must be the end of
	# the chain — the only legal continuation is the shot itself.
	ms.pieces.clear()
	var top_fig := Vector2i(3, 5)
	var gk_cell := Vector2i(3, 9)   # centre of HomeTeam's own goal (row 9)
	var far_fig := Vector2i(6, 9)   # another figure further along the goal line
	ms.pieces[top_fig] = {"team": "HomeTeam", "role": "field", "id": 10}
	ms.pieces[gk_cell] = {"team": "HomeTeam", "role": "gk", "id": 11}
	ms.pieces[far_fig] = {"team": "HomeTeam", "role": "field", "id": 12}
	ms.ball = Vector2i(3, 6)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(top_fig)
	_check(gk_cell in ms.combo_pass_targets(), "setup: the keeper (centre of goal) is a normal, legal pass target")
	ms.extend(gk_cell)
	_check(ms.chain == [top_fig, gk_cell], "chain now sits with the keeper on his own goal cell")
	_check(ms.combo_pass_targets().is_empty(),
		"no further pass is offered once the ball reaches a figure on your own goal cell (%s)" % [ms.combo_pass_targets()])
	_check(not ms.extend(far_fig), "extend() past the keeper to a further teammate is rejected")
	_check(ms.chain == [top_fig, gk_cell], "chain is unchanged after the rejected extend")
	var gk_shoot_targets := ms.combo_shoot_targets()
	_check(Vector2i(3, 8) in gk_shoot_targets, "the keeper can still shoot normally (e.g. straight up the field) from his own cell")
	_check(not (Vector2i(4, 9) in gk_shoot_targets),
		"...but NOT sideways into the adjacent goal cell — a goalpost blocks that entry angle entirely (%s)" % [gk_shoot_targets])

	# A pass is never offered (either direction) if its straight path crosses
	# one of your OWN empty goal cells first — matches the original rules
	# (rules/igra_pravila.md: "NE MOŽE SUDJELOVATI", not a scored event, just
	# unavailable) taken literally: a figure standing wide on the goal-line
	# row can't reach a MISALIGNED keeper by rolling the ball sideways past
	# an empty slot — this is the exact scenario from the user's screenshot.
	var side_fig := Vector2i(6, 9) # same row as goal, outside it, PAST an empty goal cell from centre
	ms.pieces.clear()
	ms.pieces[gk_cell] = {"team": "HomeTeam", "role": "gk", "id": 11} # centre of goal, (3,9)
	ms.pieces[side_fig] = {"team": "HomeTeam", "role": "field", "id": 12}
	ms.ball = Vector2i(6, 8) # adjacent to side_fig, straight above it
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(side_fig)
	var sideways_targets := ms.combo_pass_targets()
	_check(not (gk_cell in sideways_targets),
		"keeper at centre (3,9) is NOT reachable straight across the goal line from (6,9) — the ray crosses an empty goal cell (4,9) first (%s)" % [sideways_targets])

	# But the SAME keeper is reachable normally from directly in front of him
	# (vertical, no other goal cell crossed) — being on the goal row doesn't
	# make him unreachable in general, only via a path that detours through
	# another empty slot in his own goal first.
	ms.pieces.clear()
	ms.pieces[top_fig] = {"team": "HomeTeam", "role": "field", "id": 10}
	ms.pieces[gk_cell] = {"team": "HomeTeam", "role": "gk", "id": 11}
	ms.ball = Vector2i(3, 6)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(top_fig)
	_check(gk_cell in ms.combo_pass_targets(), "the keeper straight ahead (no crossing) is still a normal, legal pass target")

	# ...and the SAME rule blocks the keeper from rolling it back OUT the
	# other way, even on his very first move of the turn (already holding
	# the ball, e.g. right off a kickoff/save) — matches "niti on njemu"
	# (nor can he [pass] to him) from the user's report. A direction that
	# does NOT cross another goal cell (straight up the field) stays normal.
	var up_field := Vector2i(3, 5)
	ms.pieces.clear()
	ms.pieces[gk_cell] = {"team": "HomeTeam", "role": "gk", "id": 11}
	ms.pieces[far_fig] = {"team": "HomeTeam", "role": "field", "id": 12}  # (6,9), past an empty goal cell
	ms.pieces[up_field] = {"team": "HomeTeam", "role": "field", "id": 13} # (3,5), straight up, nothing crossed
	ms.ball = Vector2i(3, 8)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(gk_cell)
	_check(ms.chain == [gk_cell], "setup: chain starts AT the keeper (he already has the ball)")
	var out_targets := ms.combo_pass_targets()
	_check(not (far_fig in out_targets),
		"keeper rolling it OUT sideways through an empty goal cell is blocked, even on his own first move (%s)" % [out_targets])
	_check(up_field in out_targets, "...but passing straight up the field (no goal cell crossed) stays completely normal")
	_check(ms.extend(up_field), "...and extend() succeeds for the safe direction")

	# A goalpost blocks the ball entering a goal cell from the SIDE entirely —
	# a purely horizontal ray along the goal row can never reach ANY goal
	# cell at all (no autogol, no goal either), whether it's empty, occupied
	# by the keeper, your own net or the opponent's — that entry angle just
	# isn't physically possible. Only a vertical/diagonal approach (actually
	# coming in from the field) can ever land the ball in a goal cell.
	ms.pieces.clear()
	ms.pieces[side_fig] = {"team": "HomeTeam", "role": "field", "id": 12} # (6,9), same row as goal, outside it
	ms.ball = Vector2i(6, 8)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.begin(side_fig)
	var shoot_targets := ms.combo_shoot_targets()
	_check(not (Vector2i(4, 9) in shoot_targets) and not (Vector2i(2, 9) in shoot_targets),
		"no own-goal cell along the row is reachable sideways at all, not even the nearest one (%s)" % [shoot_targets])
	_check(not ms.execute_combo(Vector2i(4, 9))["ok"], "attempting to shoot there is simply illegal — not even an own goal")

	# Same for the OPPONENT's goal row: a lateral approach can't score either.
	ms.pieces.clear()
	ms.pieces[Vector2i(6, 0)] = {"team": "HomeTeam", "role": "field", "id": 13} # opponent's goal row, outside it
	ms.ball = Vector2i(6, 1)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.score = {"HomeTeam": 0, "AwayTeam": 0}
	ms.begin(Vector2i(6, 0))
	var opp_shoot_targets := ms.combo_shoot_targets()
	_check(not (Vector2i(4, 0) in opp_shoot_targets) and not (Vector2i(2, 0) in opp_shoot_targets),
		"no opponent goal cell along the row is reachable sideways either (%s)" % [opp_shoot_targets])
	_check(not ms.execute_combo(Vector2i(4, 0))["ok"], "attempting to shoot there doesn't score — not a legal shot at all")

	# But a genuine (vertical/diagonal) approach into a goal cell must still
	# work exactly as before — this rule only blocks the SIDEWAYS angle.
	ms.pieces.clear()
	ms.pieces[Vector2i(3, 5)] = {"team": "HomeTeam", "role": "field", "id": 14}
	ms.ball = Vector2i(3, 6)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.score = {"HomeTeam": 0, "AwayTeam": 0}
	ms.begin(Vector2i(3, 5))
	_check(Vector2i(3, 9) in ms.combo_shoot_targets(), "straight down the field into the goal (vertical, not sideways) is still a legal target")
	var vert_res := ms.execute_combo(Vector2i(3, 9))
	_check(vert_res["goal"] and vert_res["own_goal"], "...and still a real own goal, exactly as before")

	# MatchState.own_cells()
	ms.pieces.clear()
	ms.pieces[Vector2i(1, 1)] = {"team": "HomeTeam", "role": "field", "id": 0}
	ms.pieces[Vector2i(2, 2)] = {"team": "AwayTeam", "role": "field", "id": 1}
	ms.current = "HomeTeam"
	_check(ms.own_cells() == [Vector2i(1, 1)], "own_cells returns only the current team's figures (%s)" % [ms.own_cells()])

	# Opponent's goal cells are only offered as shoot targets from the opponent's
	# half — from your own half a shot there can never score (see execute_combo),
	# so (matching the original game) they're not selectable at all. Own-goal
	# cells stay targetable from anywhere.
	ms.pieces.clear()
	ms.pieces[Vector2i(3, 6)] = {"team": "HomeTeam", "role": "field", "id": 5}  # own half (row 6)
	ms.ball = Vector2i(3, 5)
	ms.current = "HomeTeam"
	ms.phase = MatchState.Phase.COMBO
	ms.chain = [Vector2i(3, 6)]
	var targets_from_own_half := ms.combo_shoot_targets()
	_check(not (Vector2i(3, 0) in targets_from_own_half),
		"opponent goal (3,0) NOT a shoot target from own half (%s)" % [targets_from_own_half])
	_check(Vector2i(3, 9) in targets_from_own_half,
		"own goal (3,9) still a shoot target from own half (autogol stays possible)")

	ms.pieces.clear()
	ms.pieces[Vector2i(3, 3)] = {"team": "HomeTeam", "role": "field", "id": 6}  # opponent half (row 3)
	ms.ball = Vector2i(3, 4)
	ms.chain = [Vector2i(3, 3)]
	var targets_from_opp_half := ms.combo_shoot_targets()
	_check(Vector2i(3, 0) in targets_from_opp_half,
		"opponent goal (3,0) IS a shoot target from the opponent's half")

	# --- team_has_ball: plain adjacency, opponent count is irrelevant --------
	# Reaching the ball is enough regardless of how many opposing figures are
	# also nearby — it isn't their turn, so there's nothing for them to contest.
	ms.pieces.clear()
	ms.pieces[Vector2i(3, 4)] = {"team": "HomeTeam", "role": "field", "id": 10} # 1 adjacent
	ms.pieces[Vector2i(3, 6)] = {"team": "AwayTeam", "role": "field", "id": 11} # 1 adjacent (tie)
	ms.ball = Vector2i(3, 5)
	_check(ms.team_has_ball("HomeTeam"), "1-1 tie: HomeTeam has the ball")
	_check(ms.team_has_ball("AwayTeam"), "1-1 tie: AwayTeam ALSO has the ball (not exclusive)")
	ms.pieces[Vector2i(4, 5)] = {"team": "AwayTeam", "role": "field", "id": 12} # AwayTeam now 2 adjacent
	_check(ms.team_has_ball("HomeTeam"), "being outnumbered 1-vs-2 no longer denies HomeTeam the ball")
	_check(ms.team_has_ball("AwayTeam"), "AwayTeam (the majority) still has the ball too")

	# --- moves_left: always 1, whether reacting (no ball at all) or taking
	# the mandatory bonus move after your own non-scoring shot ("1 action per
	# turn" redesign, 2026-07-22/23) — either way the turn passes as soon as
	# that single move is made.
	var home2 := [{"cell": Vector2i(3, 9), "role": "gk"}]
	var away2 := [
		{"cell": Vector2i(0, 0), "role": "gk"},
		{"cell": Vector2i(6, 1), "role": "field"},
	]
	ms.setup(home2, away2, Vector2i(3, 5), "HomeTeam", 99) # nobody near the ball at all
	ms.current = "AwayTeam"
	ms.start_turn()
	_check(ms.phase == MatchState.Phase.MOVE and ms.moves_left == 1 and ms._move_is_reactive,
		"reactive MOVE phase grants moves_left = 1")
	var mv1_from: Vector2i = ms.own_cells()[0]
	var mv1_to: Vector2i = ms.move_targets(mv1_from)[0]
	ms.do_move(mv1_from, mv1_to)
	_check(ms.current == "HomeTeam", "the single reactive move spends the turn immediately")

	# The bonus move (right after your OWN non-scoring shot) is likewise just
	# 1 move, and restricted to the shooter itself — see
	# scripts/tools/smoke_test_bonus_move.gd for that restriction's coverage.
	ms.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 99)
	ms.begin(Vector2i(3, 7))
	var non_goal_shot := Vector2i(4, 7)
	ms.execute_combo(non_goal_shot)
	_check(ms.phase == MatchState.Phase.MOVE and ms.moves_left == 1 and not ms._move_is_reactive,
		"bonus post-shot move also gets moves_left = 1")

	# --- Reaching the ball via a MOVE (reactive or bonus) never upgrades into
	# a same-turn combo any more (that instant-attack bonus is gone in the "1
	# action per turn" redesign, see MatchState.do_move's doc comment) — the
	# turn always ends, and it's only on the OTHER team's own next turn that
	# start_turn() checks adjacency and may open Phase.COMBO for them.
	var home3 := [{"cell": Vector2i(6, 9), "role": "gk"}] # far from the ball, irrelevant
	var away3 := [{"cell": Vector2i(3, 3), "role": "field"}] # 2 cells short of adjacency
	ms.setup(home3, away3, Vector2i(3, 5), "HomeTeam", 99)
	ms.current = "AwayTeam"
	ms.start_turn()
	_check(ms.phase == MatchState.Phase.MOVE, "setup: AwayTeam starts this reactive test in Phase.MOVE")
	ms.do_move(Vector2i(3, 3), Vector2i(3, 4)) # now adjacent to the ball (3,5)
	_check(ms.current == "HomeTeam",
		"reaching the ball via the reactive move still ends AwayTeam's turn immediately")
	ms.current = "AwayTeam" # peek: AwayTeam's OWN next turn, ball still at (3,5)
	ms.start_turn()
	_check(ms.phase == MatchState.Phase.COMBO,
		"...but AwayTeam correctly opens Phase.COMBO on its own following turn (now adjacent)")

	# --- time-wasting is booked in EVERY phase (2026-08-01) ---
	# It used to card only an expired MOVE, so two timeouts that looked identical
	# to the player could give different outcomes. One rule now: run out of time,
	# get booked, whatever you were doing.
	var tw := MatchState.new()
	tw.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
	_check(tw.phase == MatchState.Phase.COMBO, "time-waste test opens in COMBO")
	tw.forfeit(true)
	_check(tw.last_move_card == "yellow", "a COMBO that times out is booked")
	_check(tw.last_card_team == "HomeTeam", "...against the team that was on the clock")
	_check(tw.yellow_card["HomeTeam"], "...and the yellow is recorded on them")

	# A forfeit that is NOT a clock expiry still books nobody — that path exists
	# for an AI that finds no legal action (see main.gd's _maybe_ai_turn).
	var nf := MatchState.new()
	nf.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
	nf.forfeit()
	_check(nf.last_move_card == "", "a non-timeout forfeit books nobody")

	if _fail == 0:
		print("TEST_MATCH: ALL PASSED")
	else:
		printerr("TEST_MATCH: %d FAILED" % _fail)
	quit(_fail)
