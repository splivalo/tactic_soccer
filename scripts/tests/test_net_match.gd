extends SceneTree

## Two-client turn sync, end to end over the REAL database. Run:
##   godot --headless -s res://scripts/tests/test_net_match.gd
##
## Needs internet. This is the test that actually answers "does an online match
## work", because it is the only one that can: it signs in as TWO separate
## anonymous players in one process, puts them in a room, and has them play
## alternating turns at each other through Firebase — each side validating and
## applying the other's action against its OWN MatchState.
##
## What it proves that no single-client test can:
##   1. an action crosses the network and lands intact
##   2. after each exchange both MatchStates agree — same side to move, same
##      ball, same score. That agreement IS the whole actions-not-state design;
##      if it ever fails, the two players are looking at different games.
##   3. an illegal action from the opponent is REFUSED rather than applied
##   4. writing a turn index that already exists is refused, so a confused or
##      tampered client desyncs itself instead of corrupting the match

const NetScript := preload("res://scripts/net/net.gd")
const NetMatchScript := preload("res://scripts/net/net_match.gd")
const NetAction := preload("res://scripts/net/net_action.gd")

const MAX_RUNTIME := 120.0

var _fail := 0
var _done := false
var _started := false
var _elapsed := 0.0

var _net_a: Node = null
var _net_b: Node = null
var _match_a: Node = null
var _match_b: Node = null
var _state_a: MatchState = null
var _state_b: MatchState = null
var _room := ""
var _inbox_b: Array = []
var _inbox_a: Array = []


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _initialize() -> void:
	print("--- test_net_match (needs internet) ---")
	_net_a = NetScript.new()
	# Client B must NOT touch the cached identity: it needs an account of its
	# own, and it must not overwrite the developer's real one on the way.
	_net_b = NetScript.new()
	_net_b.use_token_cache = false
	root.add_child(_net_a)
	root.add_child(_net_b)

	_match_a = NetMatchScript.new()
	_match_b = NetMatchScript.new()
	root.add_child(_match_a)
	root.add_child(_match_b)
	_match_a.action_received.connect(func(a): _inbox_a.append(a))
	_match_b.action_received.connect(func(a): _inbox_b.append(a))


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	_elapsed += delta
	if not _done and _elapsed > MAX_RUNTIME:
		printerr("  FAIL: timed out after %.0f s" % MAX_RUNTIME)
		_fail += 1
		_finish()
	return _done


func _run() -> void:
	# --- sign in as two different players ---
	var a: Dictionary = await _net_a.sign_in()
	var b: Dictionary = await _net_b.sign_in()
	_check(a["ok"] and b["ok"], "both clients signed in")
	if not (a["ok"] and b["ok"]):
		return _finish()
	_check(_net_a.uid != _net_b.uid, "they are genuinely different players")

	# --- room ---
	_room = "M%05d" % (randi() % 100000)
	var made: Dictionary = await _net_a.db_patch("rooms/%s" % _room, {
		"host": _net_a.uid, "created_at": _net_a.server_timestamp(), "state": "playing"})
	var joined: Dictionary = await _net_b.db_patch("rooms/%s" % _room, {"guest": _net_b.uid})
	_check(made["ok"] and joined["ok"], "host created the room and guest joined")

	# --- identical starting position on both sides ---
	_state_a = MatchState.new()
	_state_b = MatchState.new()
	for s in [_state_a, _state_b]:
		s.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
	_match_a.start(_room, _net_a)
	_match_b.start(_room, _net_b)
	_check(_state_a.current == _state_b.current, "both start with the same side to move")

	# --- A (Home) plays a combo, B receives and applies it ---
	# Same opening the offline rule test uses: connect mid -> keeper, shoot out.
	var chain := [Vector2i(3, 7), Vector2i(3, 9)]
	_state_a.begin(chain[0])
	_state_a.extend(chain[1])
	var shots := _state_a.combo_shoot_targets()
	_check(not shots.is_empty(), "host has a legal shot to play")
	if shots.is_empty():
		return _finish()
	var shot: Vector2i = shots[0]
	var action := NetAction.combo(chain, shot)

	# Rebuild A's state so the action is applied through the SAME code path the
	# receiver uses — otherwise the test would prove nothing about apply().
	_state_a.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
	var applied_a: Dictionary = NetAction.apply(_state_a, action)
	_check(applied_a["ok"], "host applies its own combo locally%s"
		% ("" if applied_a["ok"] else " -> " + applied_a["error"]))

	var sent: Dictionary = await _match_a.send_action(action)
	_check(sent["ok"], "combo appended to the turn log%s"
		% ("" if sent["ok"] else " -> " + sent["error"]))

	await _await_inbox(_inbox_b, 1, "guest receives the combo")
	if _inbox_b.is_empty():
		return _finish()

	var applied_b: Dictionary = NetAction.apply(_state_b, _inbox_b[0])
	_check(applied_b["ok"], "guest validates and applies it%s"
		% ("" if applied_b["ok"] else " -> " + applied_b["error"]))
	_check_states_agree("after the host's combo")

	# --- B answers, A receives ---
	var move_from := _state_b.move_from_cells()
	_check(not move_from.is_empty(), "guest has a legal reply")
	if move_from.is_empty():
		return _finish()
	var from: Vector2i = move_from[0]
	var targets := _state_b.move_targets(from)
	if targets.is_empty():
		return _finish()
	var reply := NetAction.move(from, targets[0])
	var applied_b2: Dictionary = NetAction.apply(_state_b, reply)
	_check(applied_b2["ok"], "guest applies its own move locally")
	var sent_b: Dictionary = await _match_b.send_action(reply)
	_check(sent_b["ok"], "reply appended at the next index")

	await _await_inbox(_inbox_a, 1, "host receives the reply")
	if not _inbox_a.is_empty():
		var applied_a2: Dictionary = NetAction.apply(_state_a, _inbox_a[0])
		_check(applied_a2["ok"], "host validates and applies it")
		_check_states_agree("after the guest's reply")

	# --- an illegal action must be REFUSED, not applied ---
	var nonsense := NetAction.move(Vector2i(0, 0), Vector2i(6, 9))
	var before := _state_a.current
	var refused: Dictionary = NetAction.apply(_state_a, nonsense)
	_check(not refused["ok"], "an illegal opponent action is refused (%s)" % refused["error"])
	_check(_state_a.current == before, "...and the refused action changed nothing")

	# --- claiming an index that already exists must fail ---
	# This is what stops a stale or tampered client from quietly rewriting a
	# turn that has already been played.
	var stomp: Dictionary = await _net_a.db_put("rooms/%s/turns/0" % _room, {
		"by": _net_a.uid, "action": NetAction.resign(), "at": _net_a.server_timestamp()})
	_check(not stomp["ok"], "overwriting an existing turn is refused (code %d)" % stomp["code"])

	# --- replay: a rejoining client rebuilds from the log alone ---
	var fresh := MatchState.new()
	fresh.setup(Formations.home(), Formations.away(), Vector2i(3, 8), "HomeTeam", 2)
	var log_res: Dictionary = await _net_b.db_get("rooms/%s/turns" % _room)
	var replayed := 0
	if log_res["ok"]:
		var log := NetMatchScript.normalize_log(log_res["data"])
		var i := 0
		while log.has(str(i)):
			var entry = log[str(i)]
			if entry is Dictionary and entry.get("action", null) is Dictionary:
				if NetAction.apply(fresh, entry["action"])["ok"]:
					replayed += 1
			i += 1
	_check(replayed == 2, "a fresh client replays the whole log (%d turns)" % replayed)
	_check(fresh.current == _state_a.current and fresh.score == _state_a.score,
		"...and lands in the same position as the players")

	# --- two actions in one poll must arrive, in order ---
	# A single turn writes TWO entries (combo, then the compulsory move), so one
	# poll routinely returns both. They have to come out separately and in the
	# order they were played; delivering them together is what let the receiver
	# start replaying the second one mid-animation of the first.
	_inbox_a.clear()
	await _match_b.send_action(NetAction.remove(Vector2i(1, 1)))
	await _match_b.send_action(NetAction.remove(Vector2i(2, 2)))
	await _await_inbox(_inbox_a, 2, "host receives both actions from one turn")
	if _inbox_a.size() >= 2:
		_check(NetAction.cell_from_json(_inbox_a[0].get("cell")) == Vector2i(1, 1)
			and NetAction.cell_from_json(_inbox_a[1].get("cell")) == Vector2i(2, 2),
			"...and in the order they were played")

	# --- formations must survive the swap intact ---
	# Each client only ever places its OWN six figures. Without exchanging them
	# both sides fill the opponent's half with the default layout, and the two
	# boards differ before anyone has moved — which is a desync dressed up as a
	# working match.
	var layout: Array[Dictionary] = Formations.home()
	var wrote: Dictionary = await _net_a.db_put("rooms/%s/formations/%s" % [_room, _net_a.uid],
		NetAction.formation_to_json(layout))
	_check(wrote["ok"], "a player can publish their own formation%s"
		% ("" if wrote["ok"] else " -> " + wrote["error"]))

	var read_back: Dictionary = await _net_b.db_get("rooms/%s/formations/%s" % [_room, _net_a.uid])
	var parsed := NetAction.formation_from_json(read_back["data"])
	_check(parsed.size() == layout.size(),
		"opponent reads back all %d figures (got %d)" % [layout.size(), parsed.size()])
	var cells_match := parsed.size() == layout.size()
	for i in mini(parsed.size(), layout.size()):
		if parsed[i]["cell"] != layout[i]["cell"]:
			cells_match = false
	_check(cells_match, "every cell survived the round trip unchanged")

	var forge: Dictionary = await _net_b.db_put("rooms/%s/formations/%s" % [_room, _net_a.uid],
		NetAction.formation_to_json(Formations.away()))
	_check(not forge["ok"],
		"nobody can overwrite somebody else's formation (code %d)" % forge["code"])

	# --- presence: a live opponent registers, a silent one is noticed ---
	# Written directly rather than by running the 10s timer, so the test checks
	# the LOGIC (does a changed stamp read as alive) without waiting a minute.
	var beat: Dictionary = await _net_b.db_put(
		"rooms/%s/presence/%s" % [_room, _net_b.uid], _net_b.server_timestamp())
	_check(beat["ok"], "a player can announce presence in their own room slot")

	var seen: Dictionary = await _net_a.db_get("rooms/%s/presence/%s" % [_room, _net_b.uid])
	_check(seen["ok"] and seen["data"] != null, "the opponent can read that heartbeat")
	var first_stamp := str(seen["data"])

	var intruder: Dictionary = await _net_a.db_put(
		"rooms/%s/presence/%s" % [_room, _net_b.uid], _net_a.server_timestamp())
	_check(not intruder["ok"],
		"nobody can fake somebody else's heartbeat (code %d)" % intruder["code"])

	var again: Dictionary = await _net_a.db_get("rooms/%s/presence/%s" % [_room, _net_b.uid])
	_check(again["ok"] and str(again["data"]) == first_stamp,
		"a silent opponent's stamp does NOT change — which is what raises the alarm")

	_finish()


## Both clients must agree on everything that matters. This is the assertion the
## whole design exists to satisfy.
func _check_states_agree(when: String) -> void:
	_check(_state_a.current == _state_b.current, "%s: same side to move" % when)
	_check(_state_a.phase == _state_b.phase, "%s: same phase" % when)
	_check(_state_a.ball == _state_b.ball, "%s: ball in the same cell" % when)
	_check(_state_a.score == _state_b.score, "%s: same score" % when)


## Polls until the expected number of actions has arrived, rather than sleeping
## a fixed amount — a slow network would otherwise make this test flaky.
func _await_inbox(inbox: Array, want: int, label: String) -> void:
	var waited := 0.0
	while inbox.size() < want and waited < 30.0:
		await create_timer(0.5).timeout
		waited += 0.5
	_check(inbox.size() >= want, "%s (waited %.1fs)" % [label, waited])


func _finish() -> void:
	if _match_a != null:
		_match_a.stop()
	if _match_b != null:
		_match_b.stop()
	if _fail == 0:
		print("--- test_net_match: ALL PASSED ---")
	else:
		printerr("--- test_net_match: %d FAILED ---" % _fail)
	_done = true
