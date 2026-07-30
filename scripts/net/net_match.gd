extends Node
## Turn sync for an online match (GAME_DESIGN.md §11).
##
## Transports ACTIONS, not state. Both clients run the same deterministic
## MatchState and exchange only what was done:
##     {"t":"combo","chain":[[3,7],[3,4]],"shoot":[3,1]}
##     {"t":"move","from":[2,6],"to":[2,3]}
##     {"t":"remove","cell":[4,8]}
##     {"t":"resign"}
## The receiving client feeds them through the very same functions a tap would
## call, so a networked opponent animates exactly like a human or the AI — it is
## simply a third source of input (§10, and main.gd's _maybe_ai_turn).
##
## Turns live in an APPEND-ONLY log at rooms/{code}/turns/{seq}. That choice
## does a lot of work for free: reconnecting is "replay the log from 0", two
## clients can never conflict (database.rules.json refuses a write to a seq that
## already exists), and each turn is one small write.
##
## This node knows nothing about the rules. It cannot: Firebase rules can't run
## MatchState, and neither can a transport layer. Whoever consumes
## action_received MUST validate the action against its own MatchState before
## applying it, and treat a rejection as a desync rather than trying to patch it
## up — see the class docs in net.gd for how the three layers divide up.

const NetConfig := preload("res://scripts/net/net_config.gd")

## An action the opponent played, already in log order. The consumer validates
## and applies it.
signal action_received(action: Dictionary)
## Our own append was refused because that sequence number already existed —
## the two clients disagree about how far the game has got.
signal desync(reason: String)
signal sync_failed(reason: String)

## Temporary. The log is polled until the SSE stream lands (TODO.md Faza 8B);
## unlike the player list, a match genuinely wants push, so this is a stopgap
## rather than a design choice.
const POLL_SECONDS := 2.0

var room := ""
## How many entries of the log we have already dealt with — ours included.
## Doubles as the sequence number our next append claims.
var applied := 0

## The Firebase client to talk through. Injected rather than reaching for the
## Net autoload directly, so the two-client test can drive two independent
## players — with two different anonymous accounts — inside one process.
var net: Node = null

var _poll: Timer = null
var _busy := false
var _live := false


func start(room_code: String, client: Node = null) -> void:
	room = room_code
	applied = 0
	_live = true
	if client != null:
		net = client
	if net == null:
		net = get_node_or_null("/root/Net")
	if _poll == null:
		_poll = Timer.new()
		_poll.wait_time = POLL_SECONDS
		_poll.timeout.connect(func(): _tick())
		add_child(_poll)
	_poll.start()


func stop() -> void:
	_live = false
	if _poll != null:
		_poll.stop()


## Appends one of OUR actions to the log.
##
## The write is refused if that sequence number already exists — which can only
## mean the opponent believes it is their turn while we believe it is ours. That
## is a desync, and it is reported rather than retried at the next index:
## appending anyway would leave the two clients playing different games while
## both think everything is fine.
func send_action(action: Dictionary) -> Dictionary:
	if room == "":
		return {"ok": false, "error": "no room"}

	var res: Dictionary = await net.db_put("rooms/%s/turns/%d" % [room, applied], {
		"by": net.uid,
		"action": action,
		"at": net.server_timestamp(),
	})
	if not res["ok"]:
		desync.emit("could not append turn %d: %s" % [applied, res["error"]])
		return res

	applied += 1
	return res


func _tick() -> void:
	if _busy or not _live or room == "":
		return
	_busy = true
	var res: Dictionary = await net.db_get("rooms/%s/turns" % room)
	_busy = false

	if not res["ok"]:
		sync_failed.emit(res["error"])
		return
	_drain(normalize_log(res["data"]))


## Firebase hands the log back as a JSON ARRAY rather than an object whenever
## the keys happen to be contiguous integers starting at 0 — which is exactly
## what an append-only log always looks like. Punch one hole in it and the same
## data comes back as an object with string keys instead.
##
## Both shapes must be handled. Checking only for a Dictionary made the log read
## as permanently empty, so turns were written correctly and simply never
## arrived at the other player.
static func normalize_log(data) -> Dictionary:
	var out := {}
	if data is Dictionary:
		for k in data:
			out[str(k)] = data[k]
	elif data is Array:
		for i in data.size():
			if data[i] != null:
				out[str(i)] = data[i]
	return out


## Walks the log forward from wherever we stopped. Deliberately index-driven
## rather than "react to whatever arrived": a poll can return several new turns
## at once (a slow network, a backgrounded app), and they must be applied in
## order, exactly once each.
func _drain(log: Dictionary) -> void:
	while _live:
		var key := str(applied)
		if not log.has(key):
			return
		var entry = log[key]
		applied += 1
		if not (entry is Dictionary):
			continue
		# Our own turns are already reflected locally — we applied them the
		# moment the player acted, which is why the game never waits for a
		# round trip to feel responsive.
		if String(entry.get("by", "")) == net.uid:
			continue
		var action = entry.get("action", null)
		if action is Dictionary:
			action_received.emit(action)


## Replays the whole log from the start — used when rejoining a match in
## progress. Same code path as normal play, because the log makes "catch up" and
## "keep up" the same operation.
func replay_from_start() -> Dictionary:
	applied = 0
	var res: Dictionary = await net.db_get("rooms/%s/turns" % room)
	if not res["ok"]:
		return res
	_drain(normalize_log(res["data"]))
	return res
