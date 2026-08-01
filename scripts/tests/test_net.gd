extends SceneTree

## Headless end-to-end check of the Firebase layer. Run:
##   godot --headless -s res://scripts/tests/test_net.gd
##
## Unlike the other tests here this one TALKS TO THE REAL DATABASE over the
## network — it is not a pure unit test and needs internet. That is the point:
## it verifies three things no offline test can, in one pass.
##   1. anonymous auth works from Godot's plain REST client (no Firebase SDK)
##   2. reads/writes reach the Realtime Database and come back intact
##   3. the security rules are actually LIVE — it deliberately attempts two
##      writes that must be REJECTED, and fails if they succeed
##
## Cleans up after itself: the probe player record is deleted at the end.

const NetScript := preload("res://scripts/net/net.gd")

## Hard stop. Without it, any crash inside the _run() coroutine leaves _done
## false forever and the headless process spins until something kills it — which
## is exactly what happened the first time this test was run.
const MAX_RUNTIME := 60.0

var _fail := 0
var _done := false
var _started := false
var _elapsed := 0.0
var _net: Node = null


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  : %s" % label)
	else:
		_fail += 1
		printerr("  FAIL: %s" % label)


func _initialize() -> void:
	print("--- test_net (needs internet) ---")
	# Instantiated by hand rather than via the Net autoload: with `-s` the
	# script IS the main loop, so relying on autoload registration would make
	# the test depend on something it isn't trying to prove.
	_net = NetScript.new()
	root.add_child(_net)


func _process(delta: float) -> bool:
	# Started on the first frame, NOT from _initialize(): during _initialize the
	# tree isn't up yet, so the HTTPRequest nodes Net creates fail their
	# is_inside_tree() check and request() returns ERR_UNCONFIGURED.
	if not _started:
		_started = true
		_run()

	_elapsed += delta
	if not _done and _elapsed > MAX_RUNTIME:
		printerr("  FAIL: test timed out after %.0f s" % MAX_RUNTIME)
		_fail += 1
		_finish()
	return _done


func _run() -> void:
	# --- 1. anonymous sign-in ---
	var auth: Dictionary = await _net.sign_in()
	_check(auth["ok"], "anonymous sign-in (%s)" % ("uid " + str(_net.uid) if auth["ok"] else auth["error"]))
	if not auth["ok"]:
		return _finish()
	_check(_net.uid != "", "uid is not empty")

	var me: String = "players/%s" % _net.uid

	# --- 2. write a valid player record ---
	# Shaped to satisfy database.rules.json: name 2-16 chars, status from the
	# allowed pair, last_seen a number. last_seen uses the SERVER clock sentinel
	# rather than the device clock (see Net.server_timestamp).
	var record := {
		"name": "probe",
		"status": "idle",
		"country": "Croatia",
		"last_seen": _net.server_timestamp(),
	}
	var put: Dictionary = await _net.db_put(me, record)
	_check(put["ok"], "write own player record%s" % ("" if put["ok"] else " -> " + put["error"]))

	# --- 3. read it back ---
	var got: Dictionary = await _net.db_get(me)
	var data = got["data"]
	_check(got["ok"] and data is Dictionary, "read own player record back")
	if data is Dictionary:
		_check(data.get("name", "") == "probe", "name survived the round trip")
		# The list draws each player's flag from this, so it has to be an
		# allowed field — "$other": false refuses anything not named in the rules.
		_check(data.get("country", "") == "Croatia", "country is published for the flag")
		_check(data.get("last_seen", 0) is float or data.get("last_seen", 0) is int,
			"server timestamp resolved to a number (%s)" % str(data.get("last_seen")))

	# --- 4. rules must REJECT an unknown field ($other: validate false) ---
	var bogus: Dictionary = await _net.db_put(me, {
		"name": "probe",
		"status": "idle",
		"last_seen": _net.server_timestamp(),
		"is_admin": true,
	})
	_check(not bogus["ok"], "rules reject an unknown field (got code %d)" % bogus["code"])

	# --- 5. rules must REJECT writing someone else's record ---
	var intruder: Dictionary = await _net.db_put("players/somebody-else", {
		"name": "intruder",
		"status": "idle",
		"last_seen": _net.server_timestamp(),
	})
	_check(not intruder["ok"], "rules reject writing another player's node (got code %d)" % intruder["code"])

	# --- 6. the player list is readable while signed in ---
	var list: Dictionary = await _net.db_get("players")
	_check(list["ok"], "player list is readable%s" % ("" if list["ok"] else " -> " + list["error"]))

	# --- 6b. the clock offset, which the shared turn deadline rests on ---
	# Stored deadlines are in SERVER time, so a device has to know how far its
	# own clock is out or it reads them wrong by exactly that much.
	var synced: Dictionary = await _net.sync_clock()
	_check(synced["ok"], "clock sync round trip%s"
		% ("" if synced["ok"] else " -> " + synced["error"]))
	if synced["ok"]:
		var drift: float = absf(_net.server_now_ms() - Time.get_unix_time_from_system() * 1000.0)
		_check(drift < 600000.0,
			"device clock is within 10 min of the server (off by %.1fs)" % (drift / 1000.0))
		var ahead: float = _net.server_now_ms() - Time.get_unix_time_from_system() * 1000.0
		print("        (this machine is %.0f ms off the server)" % ahead)

	# --- 7. rooms: a PATCH of individual fields must pass, a PUT of the whole
	# room must NOT. database.rules.json grants .write on the room's FIELDS and
	# deliberately never on the room node itself, because in RTDB a .write on a
	# parent hands out everything below it — including turns, which must stay
	# append-only. This is the check that keeps that design honest.
	var code := "T%05d" % (randi() % 100000)
	var room_patch: Dictionary = await _net.db_patch("rooms/%s" % code, {
		"host": _net.uid,
		"created_at": _net.server_timestamp(),
		"state": "lobby",
	})
	_check(room_patch["ok"], "room created field-by-field via PATCH%s"
		% ("" if room_patch["ok"] else " -> " + room_patch["error"]))

	var room_put: Dictionary = await _net.db_put("rooms/%s" % code, {"host": _net.uid})
	_check(not room_put["ok"], "whole-room PUT is refused (got code %d)" % room_put["code"])

	var join: Dictionary = await _net.db_patch("rooms/%s" % code, {"guest": _net.uid})
	_check(join["ok"], "guest can claim the empty guest slot%s"
		% ("" if join["ok"] else " -> " + join["error"]))

	# --- 8. invites ---
	var invite: Dictionary = await _net.db_put("invites/some-other-uid/%s" % _net.uid, {
		"from_name": "probe",
		"room": code,
		"created_at": _net.server_timestamp(),
	})
	_check(invite["ok"], "invite written to another player's inbox%s"
		% ("" if invite["ok"] else " -> " + invite["error"]))

	var own_inbox: Dictionary = await _net.db_get("invites/%s" % _net.uid)
	_check(own_inbox["ok"], "own invite inbox is readable")

	var peek: Dictionary = await _net.db_get("invites/some-other-uid")
	_check(not peek["ok"], "reading someone else's inbox is refused (got code %d)" % peek["code"])

	var unsend: Dictionary = await _net.db_delete("invites/some-other-uid/%s" % _net.uid)
	_check(unsend["ok"], "sender can withdraw their own invite")

	# --- 9. clean up ---
	var gone: Dictionary = await _net.db_delete(me)
	_check(gone["ok"], "probe record deleted")

	# The creator may clear their own claim, so an abandoned room can be tidied
	# up and a code reused. (This FAILS until the updated rules in
	# firebase/database.rules.json are published — they were write-once before.)
	var room_gone: Dictionary = await _net.db_delete("rooms/%s/host" % code)
	_check(room_gone["ok"], "the room's creator can clear their own claim%s"
		% ("" if room_gone["ok"] else " -> " + room_gone["error"]))

	# But a played turn stays put, forever. That is the deliberate trade: the
	# append-only rule is what makes the log tamper-proof, and loosening it so
	# finished matches could be swept up would also let a client rewrite
	# history. Integrity wins; see TODO.md Faza 8E for what that costs.
	var a_turn: Dictionary = await _net.db_put("rooms/%s/turns/0" % code, {
		"by": _net.uid, "action": {"t": "resign"}, "at": _net.server_timestamp()})
	_check(a_turn["ok"], "a turn can be appended")
	var rewrite: Dictionary = await _net.db_delete("rooms/%s/turns/0" % code)
	_check(not rewrite["ok"],
		"a played turn can never be deleted, even by the room's creator (code %d)" % rewrite["code"])

	_finish()


func _finish() -> void:
	if is_instance_valid(_net):
		_net.queue_free()
	if _fail == 0:
		print("--- test_net: ALL PASSED ---")
	else:
		printerr("--- test_net: %d FAILED ---" % _fail)
	_done = true
