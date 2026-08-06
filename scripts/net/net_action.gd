extends RefCounted
## Wire format for a single match action, plus the ONE place that applies one to
## a MatchState (GAME_DESIGN.md §11).
##
## Both the networked match and its tests go through here on purpose. If the
## sender and the receiver each grew their own idea of what {"t":"combo"} means,
## the two clients would drift apart in exactly the way the whole
## actions-not-state design exists to prevent.
##
## Cells travel as [x, y] arrays because JSON has no Vector2i.
##
## apply() is also the desync check. It refuses anything the rules refuse, so a
## tampered or stale client cannot push an illegal move into the opponent's
## game: the worst it can do is get itself thrown out of the match. This is the
## only real defence available without an authoritative server — Firebase rules
## guard the DATA but cannot run MatchState (see net.gd).

const NetConfig := preload("res://scripts/net/net_config.gd")


static func cell_to_json(c: Vector2i) -> Array:
	return [c.x, c.y]


static func cell_from_json(v) -> Vector2i:
	if v is Array and v.size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


## A placed formation, for the one exchange that happens before kick-off.
##
## Both clients must build the SAME board. Each only places its own six figures,
## so without swapping them each side would fill the opponent's half with the
## default layout — two different boards, desynced before anyone has moved.
## Cells are already absolute board coordinates (the guest mirrors before
## sending), so the receiver uses them as they are.
static func formation_to_json(layout: Array) -> Array:
	var out := []
	for entry in layout:
		out.append({
			"cell": cell_to_json(entry["cell"]),
			"role": String(entry.get("role", "")),
			"number": int(entry.get("number", 0)),
		})
	return out


static func formation_from_json(data) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (data is Array):
		return out
	for entry in data:
		if not (entry is Dictionary):
			continue
		out.append({
			"cell": cell_from_json(entry.get("cell", null)),
			"role": String(entry.get("role", "")),
			"number": int(entry.get("number", 0)),
		})
	return out


static func combo(chain: Array, shoot: Vector2i) -> Dictionary:
	var out := []
	for c in chain:
		out.append(cell_to_json(c))
	return {"t": "combo", "chain": out, "shoot": cell_to_json(shoot)}


static func move(from: Vector2i, to: Vector2i) -> Dictionary:
	return {"t": "move", "from": cell_to_json(from), "to": cell_to_json(to)}


## A "hold": the team declines the shot and repositions instead
## (MatchState.hold_and_move). Distinct from a plain move because it happens in
## the COMBO phase, not the MOVE phase.
static func hold(from: Vector2i, to: Vector2i) -> Dictionary:
	return {"t": "hold", "from": cell_to_json(from), "to": cell_to_json(to)}


static func remove(cell: Vector2i) -> Dictionary:
	return {"t": "remove", "cell": cell_to_json(cell)}


## Won the ball off the man standing on it. Carries no cell: which of your men
## takes it is decided by MatchState.tackle() the same way on both clients, so
## sending it would only create something for them to disagree about.
static func tackle() -> Dictionary:
	return {"t": "tackle"}


## A pass that ends at a teammate rather than in space.
static func pass_to(cell: Vector2i) -> Dictionary:
	return {"t": "pass", "cell": cell_to_json(cell)}


static func resign() -> Dictionary:
	return {"t": "resign"}


## The player to move ran out of time.
##
## Sent as an action rather than each client timing the turn for itself, which
## is what makes the whole server-clock question go away: only ONE device — the
## one actually on the clock — decides that time is up, and everyone else simply
## receives the result like any other move. Two devices can never disagree about
## whether a turn expired, because only one of them is asked.
static func forfeit() -> Dictionary:
	return {"t": "forfeit"}


## Validates and applies an action to `state`.
##
## Returns {ok, error, result}. `result` carries execute_combo's dictionary for
## combo actions (goal/own_goal/offside flags the visual layer needs) and is
## empty otherwise. ok == false means DESYNC: the caller must abandon the match
## rather than continue, because from here the two clients no longer agree on
## what the board looks like.
static func apply(state, action: Dictionary) -> Dictionary:
	if state == null:
		return _fail("no match state")
	if not (action is Dictionary) or not action.has("t"):
		return _fail("malformed action")

	match String(action["t"]):
		"combo":
			return _apply_combo(state, action)
		"move":
			return _apply_move(state, action, false)
		"hold":
			return _apply_move(state, action, true)
		"remove":
			var cell := cell_from_json(action.get("cell", null))
			if not state.remove_figure(cell):
				return _fail("illegal removal at %s" % cell)
			return _ok({})
		"resign":
			return _ok({"resigned": true})
	return _fail("unknown action type '%s'" % action["t"])


static func _apply_combo(state, action: Dictionary) -> Dictionary:
	var chain = action.get("chain", [])
	if not (chain is Array) or chain.is_empty():
		return _fail("combo without a chain")

	# Rebuilt step by step through the same begin/extend calls a tap makes, so
	# every link is checked against the rules rather than trusted.
	if not state.begin(cell_from_json(chain[0])):
		return _fail("illegal chain start %s" % cell_from_json(chain[0]))
	for i in range(1, chain.size()):
		if not state.extend(cell_from_json(chain[i])):
			return _fail("illegal chain link %s" % cell_from_json(chain[i]))

	var shoot := cell_from_json(action.get("shoot", null))
	if not (shoot in state.combo_shoot_targets()):
		return _fail("illegal shot target %s" % shoot)
	return _ok(state.execute_combo(shoot))


static func _apply_move(state, action: Dictionary, as_hold: bool) -> Dictionary:
	var from := cell_from_json(action.get("from", null))
	var to := cell_from_json(action.get("to", null))
	var done: bool = state.hold_and_move(from, to) if as_hold else state.do_move(from, to)
	if not done:
		return _fail("illegal %s %s -> %s" % ["hold" if as_hold else "move", from, to])
	return _ok({})


static func _ok(result: Dictionary) -> Dictionary:
	return {"ok": true, "error": "", "result": result}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "result": {}}
