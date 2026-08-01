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
## The opponent stopped showing up. Not the same as resigning: this is the
## player who closes the app, loses signal, or walks into a lift.
signal opponent_lost(reason: String)
## The shared moment (epoch ms, SERVER time) the current turn runs out. Both
## clients count down to the same instant instead of each timing from whenever
## it happened to learn the turn had started — which is what made one show 18
## seconds while the other showed 10.
signal deadline_changed(deadline_ms: float)

## How often we announce that we are still here, and how long an opponent may go
## quiet before the match is called off. The window is deliberately generous —
## a phone that gets backgrounded or hops between wifi and mobile data goes
## briefly silent all the time, and dropping someone's match for that would be
## far worse than waiting a few extra seconds.
const PRESENCE_SECONDS := 10.0
const OPPONENT_TIMEOUT_SECONDS := 45.0

## Temporary. The log is polled until the SSE stream lands (TODO.md Faza 8B);
## unlike the player list, a match genuinely wants push, so this is a stopgap
## rather than a design choice.
const POLL_SECONDS := 2.0
## Tighter interval used only in the last few seconds of a turn, where lag is
## the difference between "the clock hit zero and play moved on" and "the clock
## hit zero and sat there".
const POLL_NEAR_DEADLINE := 0.5
const NEAR_DEADLINE_SECONDS := 4.0

var room := ""
## How many entries of the log we have already dealt with — ours included.
## Doubles as the sequence number our next append claims.
var applied := 0

## The Firebase client to talk through. Injected rather than reaching for the
## Net autoload directly, so the two-client test can drive two independent
## players — with two different anonymous accounts — inside one process.
var net: Node = null

## Who to watch for. Empty = nobody is being watched (the two-client test drives
## presence itself).
var opponent_uid := ""

var _poll: Timer = null
var _presence_timer: Timer = null
var _busy := false
var _presence_busy := false
var _live := false

## The last presence stamp we saw from the opponent, and how long WE have been
## looking at that same value.
##
## Comparing their server timestamp against our own device clock would drag in
## clock skew — a phone set a minute fast would declare a perfectly healthy
## opponent dead. Watching for the value to CHANGE, and timing that with our own
## elapsed seconds, makes both clocks irrelevant.
var _last_opponent_stamp := ""
var _opponent_quiet_for := 0.0

## Last deadline seen, so the signal only fires on a genuine change.
var _deadline_ms := 0.0


func start(room_code: String, client: Node = null, watch_uid: String = "") -> void:
	room = room_code
	opponent_uid = watch_uid
	applied = 0
	_last_opponent_stamp = ""
	_opponent_quiet_for = 0.0
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

	if opponent_uid != "":
		if _presence_timer == null:
			_presence_timer = Timer.new()
			_presence_timer.wait_time = PRESENCE_SECONDS
			_presence_timer.timeout.connect(func(): _presence_tick())
			add_child(_presence_timer)
		_presence_timer.start()
		_presence_tick()


func stop() -> void:
	_live = false
	if _poll != null:
		_poll.stop()
	if _presence_timer != null:
		_presence_timer.stop()


## Says "still here", then checks whether the opponent has said the same
## recently enough.
##
## This exists because onDisconnect() — the server-side "wipe this when the
## socket drops" primitive — is a realtime-SDK feature and is NOT on the REST
## API we use (§11). Resigning is caught by an explicit action; somebody who
## simply closes the app is caught only here. Without it the other player waits
## for a turn that is never coming.
func _presence_tick() -> void:
	if _presence_busy or not _live or room == "" or opponent_uid == "":
		return
	_presence_busy = true

	await net.db_put("rooms/%s/presence/%s" % [room, net.uid], net.server_timestamp())
	var res: Dictionary = await net.db_get("rooms/%s/presence/%s" % [room, opponent_uid])

	_presence_busy = false
	if not _live:
		return

	if res["ok"] and res["data"] != null:
		var stamp := str(res["data"])
		if stamp != _last_opponent_stamp:
			_last_opponent_stamp = stamp
			_opponent_quiet_for = 0.0
			return

	# Either unchanged or unreadable. Count our OWN elapsed seconds rather than
	# trusting either device's idea of the time.
	_opponent_quiet_for += PRESENCE_SECONDS
	if _opponent_quiet_for >= OPPONENT_TIMEOUT_SECONDS:
		stop()
		opponent_lost.emit("Opponent left the match.")


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
	await _read_deadline()
	_pace_poll()


## Polls faster as the deadline approaches.
##
## A turn ending is the one moment where two seconds of lag is actually visible:
## the countdown reaches zero and then nothing happens until the forfeit is
## fetched. Tightening the interval only in that window cuts the stall to well
## under a second without polling hard for the rest of the match.
func _pace_poll() -> void:
	if _poll == null:
		return
	var wanted := POLL_SECONDS
	if _deadline_ms > 0.0:
		# Typed explicitly: `net` is a plain Node, so the call gives back a
		# Variant and there is nothing to infer from.
		var left: float = (_deadline_ms - net.server_now_ms()) / 1000.0
		if left < NEAR_DEADLINE_SECONDS:
			wanted = POLL_NEAR_DEADLINE
	if not is_equal_approx(_poll.wait_time, wanted):
		_poll.wait_time = wanted


## Piggybacks on the turn poll. One tiny extra read rather than fetching the
## whole room node, which would drag the entire turn log along with it every
## couple of seconds.
func _read_deadline() -> void:
	if not _live or room == "":
		return
	var res: Dictionary = await net.db_get("rooms/%s/deadline_at" % room)
	if not res["ok"] or res["data"] == null:
		return
	var ms := float(res["data"])
	if ms != _deadline_ms:
		_deadline_ms = ms
		deadline_changed.emit(ms)


## Publishes when the current turn runs out. Called by whoever is ON the clock —
## they are the one who decides expiry (see main.gd's _on_turn_timeout), so they
## are also the one who says when it falls due.
func publish_deadline(deadline_ms: float) -> Dictionary:
	if room == "":
		return {"ok": false, "error": "no room"}
	_deadline_ms = deadline_ms
	return await net.db_put("rooms/%s/deadline_at" % room, deadline_ms)


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
