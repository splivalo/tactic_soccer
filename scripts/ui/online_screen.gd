extends Control
## Online screen: presence + invites (TODO.md Faza 8, GAME_DESIGN.md §11).
##
## Shown as an OVERLAY on the match scene, over the pitch the player has just
## placed their formation on — not as a screen of its own. That is why it has a
## translucent scrim instead of a background: the board you are about to play on
## stays visible behind it, and when someone accepts the overlay simply goes
## away and the match begins right there. No scene change, no second load.
##
## It therefore never navigates. It reports what happened through match_ready /
## cancelled and lets main.gd decide what to do next.
##
## Flow: enter a name -> publish yourself -> see who else is online -> invite
## someone -> they accept -> both end up in the same room -> match_ready.
##
## Nobody is ever dropped into a game without agreeing: an invite is an offer
## the other side must Accept, and it expires on its own if ignored.
##
## What is NOT here yet: country selection and the actual networked match. The
## room is the handshake those will be built on.
##
## Everything polls rather than streams. That is deliberate for the player list
## (a live subscription pushes every join/leave to every viewer, so traffic
## grows with the SQUARE of the player count — §11) and merely temporary for
## invites and the room, which switch to the SSE stream when match sync lands.
##
## Layout is a placeholder like the other scenes/ui/ screens — styled by the
## author in the editor, this script only wires behaviour.

const NetConfig := preload("res://scripts/net/net_config.gd")

## An opponent accepted: room code, their name, their country, and whether we
## are the host (host keeps the home kit — see GameFlow.online_is_host).
signal match_ready(room: String, opponent_name: String, opponent_country: String, is_host: bool)
## The player backed out before finding anyone.
signal cancelled

## No I/O/0/1 — codes get read aloud and typed by hand.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6

const POLL_SECONDS := 3.0

## SafeArea's own bottom margin in the scene, restored once the on-screen
## keyboard goes away.
const BASE_MARGIN_BOTTOM := 60

## Padding inside a player row's card, equal on all four sides so the Invite
## button sits the same distance from every edge.
const ROW_PADDING := 18
## How long an unanswered invite stays live. Long enough to notice a prompt,
## short enough that a forgotten one doesn't haunt the other player's screen.
const INVITE_TIMEOUT_SECONDS := 60.0

enum Stage { NAME, LIST, WAITING, ROOM }

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _status: Label = %StatusLabel
@onready var _empty_label: Label = %EmptyLabel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _name_panel: Control = %NamePanel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_ok: Button = %NameOkButton
## Refresh / Change name live OUTSIDE ListPanel, above the status line, so the
## status line ends up directly on top of the list it describes ("here's who you
## are and how many of you there are — and below, here they are"). It can't just
## be moved INTO the list panel instead: the same label carries the error
## messages and the "enter your name" prompt, and would vanish with the panel.
@onready var _list_buttons: Control = %ListButtons
@onready var _list_panel: Control = %ListPanel
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _refresh_button: Button = %RefreshButton
@onready var _change_name_button: Button = %ChangeNameButton
@onready var _invite_panel: Control = %InvitePanel
@onready var _invite_label: Label = %InviteLabel
@onready var _accept_button: Button = %AcceptButton
@onready var _decline_button: Button = %DeclineButton
@onready var _room_panel: Control = %RoomPanel
@onready var _room_label: Label = %RoomLabel
@onready var _leave_button: Button = %LeaveButton
@onready var _back_button: Button = %BackButton

var _stage := Stage.NAME
var _heartbeat: Timer = null
var _poll: Timer = null
var _busy := false

## Invite we sent, waiting on.
var _sent_room := ""
var _sent_to_uid := ""
var _sent_to_name := ""
var _sent_at := 0.0

## Invite we received and are showing.
var _incoming_from_uid := ""
var _incoming_from_name := ""
var _incoming_room := ""

var _room_code := ""
var _room_opponent := ""


func _ready() -> void:
	_name_ok.pressed.connect(_on_name_confirmed)
	_name_edit.text_submitted.connect(func(_t: String): _on_name_confirmed())
	_refresh_button.pressed.connect(_refresh_list)
	_change_name_button.pressed.connect(_show_name_entry)
	_accept_button.pressed.connect(_on_accept_pressed)
	_decline_button.pressed.connect(_on_decline_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_heartbeat = Timer.new()
	_heartbeat.wait_time = NetConfig.HEARTBEAT_SECONDS
	_heartbeat.timeout.connect(func(): _publish_me())
	add_child(_heartbeat)

	_poll = Timer.new()
	_poll.wait_time = POLL_SECONDS
	_poll.timeout.connect(func(): _tick())
	add_child(_poll)

	# Asked here, at the moment it's needed. Deliberately not buried in Settings:
	# nobody looks there first, and then Online would just fail with nothing to
	# explain why.
	if Settings.has_valid_player_name():
		_go_online()
	else:
		_show_name_entry()


# --- Stage handling ------------------------------------------------------------

func _set_stage(stage: int) -> void:
	_stage = stage
	_name_panel.visible = stage == Stage.NAME
	_list_buttons.visible = stage == Stage.LIST
	_list_panel.visible = stage == Stage.LIST
	_invite_panel.visible = false  # overlays LIST/WAITING when one arrives
	_room_panel.visible = stage == Stage.ROOM

	# Only the name field ever raises the on-screen keyboard, so only that stage
	# needs to watch for it.
	set_process(stage == Stage.NAME)
	if stage != Stage.NAME:
		_safe_area.add_theme_constant_override("margin_bottom", BASE_MARGIN_BOTTOM)


## Lifts the whole screen above the on-screen keyboard.
##
## Android draws the keyboard OVER the app rather than resizing it, so the
## Connect button below the text field ended up underneath it and could not be
## pressed at all. Godot reports the keyboard's height, and the layout simply
## grows its bottom margin by that much.
##
## The height comes back in real SCREEN pixels while the UI is laid out in the
## project's 1080x1920 viewport units, so it has to be scaled — without that the
## correction is wrong by whatever the device's stretch factor happens to be.
func _process(_delta: float) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	var window_h := float(DisplayServer.window_get_size().y)
	if window_h <= 0.0:
		return
	var scale := get_viewport_rect().size.y / window_h
	var inset := int(round(DisplayServer.virtual_keyboard_get_height() * scale))
	_safe_area.add_theme_constant_override("margin_bottom", BASE_MARGIN_BOTTOM + inset)


func _show_name_entry() -> void:
	_set_stage(Stage.NAME)
	_poll.stop()
	_name_edit.text = Settings.player_name
	_name_edit.grab_focus()
	_status.text = "Enter the name other players will see (2-16 characters)."


func _on_name_confirmed() -> void:
	var typed := _name_edit.text.strip_edges()
	if typed.length() < 2:
		_status.text = "Name must be at least 2 characters."
		return
	Settings.set_player_name(typed)
	_go_online()


func _go_online() -> void:
	_set_stage(Stage.LIST)
	_status.text = "Connecting..."

	var auth: Dictionary = await Net.sign_in()
	if not auth["ok"]:
		_status.text = "Sign-in failed: %s" % auth["error"]
		return

	await _publish_me()
	_heartbeat.start()
	_poll.start()
	await _refresh_list()


# --- Presence ------------------------------------------------------------------

## Publishes/refreshes our presence. This IS the heartbeat: without
## onDisconnect() on the REST API (§11) a record only counts as online while
## last_seen keeps moving.
func _publish_me(status: String = "") -> void:
	if Net.uid == "":
		return
	if status == "":
		status = "in_match" if _stage == Stage.ROOM else "idle"
	var res: Dictionary = await Net.db_put("players/%s" % Net.uid, {
		"name": Settings.player_name,
		"status": status,
		"last_seen": Net.server_timestamp(),
	})
	if not res["ok"]:
		_status.text = "Could not publish presence: %s" % res["error"]


func _refresh_list() -> void:
	if _busy or _stage != Stage.LIST:
		return
	_busy = true
	_refresh_button.disabled = true

	var res: Dictionary = await Net.db_get("players")

	_refresh_button.disabled = false
	_busy = false

	if not res["ok"]:
		_status.text = "Could not load player list: %s" % res["error"]
		return

	for child in _player_list.get_children():
		child.queue_free()

	var others := 0
	if res["data"] is Dictionary:
		# Firebase timestamps are epoch MILLISECONDS, not seconds.
		var now_ms := Time.get_unix_time_from_system() * 1000.0
		for other_uid in res["data"]:
			if other_uid == Net.uid:
				continue
			var rec = res["data"][other_uid]
			if not (rec is Dictionary):
				continue
			# Stale entries are filtered, not deleted — they belong to someone
			# else. The window is generous because this compares the DEVICE
			# clock against a SERVER stamp, and a skewed phone clock must not
			# wrongly hide live players.
			var age := now_ms - float(rec.get("last_seen", 0))
			if age > NetConfig.PRESENCE_STALE_SECONDS * 1000.0:
				continue
			_player_list.add_child(_make_row(String(other_uid), rec))
			others += 1

	# The empty state lives OUTSIDE the scroll area so it can sit centred in the
	# whole panel. Inside a ScrollContainer a child only ever gets its minimum
	# height, so it would cling to the top no matter how it's aligned.
	_empty_label.visible = others == 0
	_scroll.visible = others > 0

	_status.text = "You: %s   —   online: %d" % [Settings.player_name, others + 1]


## One row = a MiniCard. That style is already defined in my_theme.tres (dark
## panel, green border) and is exactly what a list entry wants, so rows look
## like the rest of the game instead of like bare text.
func _make_row(other_uid: String, rec: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"MiniCard"

	# The SAME value on all four sides. With different horizontal and vertical
	# padding the Invite button sat further from the card's right edge than from
	# its top and bottom, which reads as the button having slipped out of place
	# rather than as deliberate spacing.
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, ROW_PADDING)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	var who := Label.new()
	who.text = String(rec.get("name", "?"))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# The theme's default label size (42) reads as small next to the game's
	# chunky buttons (75). Names are the point of this screen, so they get a
	# size in between, plus the same dark outline the buttons use.
	who.add_theme_font_size_override("font_size", 60)
	who.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	who.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.02, 1))
	who.add_theme_constant_override("outline_size", 8)
	row.add_child(who)

	var invite := Button.new()
	invite.custom_minimum_size = Vector2(300, 110)
	# Secondary style (flat green, no chunky border) rather than the primary
	# yellow one. Refresh / Change name / Back are the screen's main actions and
	# keep the primary look; if every per-row button matched them the screen
	# turns into a wall of identical yellow blocks with no hierarchy.
	invite.theme_type_variation = &"ArrowButton"
	invite.add_theme_font_size_override("font_size", 46)
	var busy := String(rec.get("status", "idle")) != "idle"
	# A player already in a match gets a disabled button rather than no button:
	# "they're busy" is information, a missing control is just confusing.
	invite.text = "In match" if busy else "Invite"
	invite.disabled = busy
	invite.pressed.connect(func(): _send_invite(other_uid, String(rec.get("name", "?"))))
	row.add_child(invite)

	return card


# --- Inviting ------------------------------------------------------------------

func _send_invite(to_uid: String, to_name: String) -> void:
	if _busy:
		return
	_busy = true

	var code := _new_room_code()
	# PATCH, not PUT of the whole room: database.rules.json grants .write on the
	# individual room FIELDS and deliberately not on the room node itself (a
	# parent .write would hand out everything below it, including turns). A
	# multi-field update is checked field by field, so it passes.
	# The country goes into the room as a plain announcement, not a negotiation:
	# duplicates are allowed, and the guest simply plays in the alternative kit.
	var room: Dictionary = await Net.db_patch("rooms/%s" % code, {
		"host": Net.uid,
		"host_country": Settings.player_country,
		"created_at": Net.server_timestamp(),
		"state": "lobby",
	})
	if not room["ok"]:
		_busy = false
		_status.text = "Could not create room: %s" % room["error"]
		return

	var sent: Dictionary = await Net.db_put("invites/%s/%s" % [to_uid, Net.uid], {
		"from_name": Settings.player_name,
		"room": code,
		"created_at": Net.server_timestamp(),
	})
	_busy = false
	if not sent["ok"]:
		_status.text = "Could not send invite: %s" % sent["error"]
		return

	_sent_room = code
	_sent_to_uid = to_uid
	_sent_to_name = to_name
	_sent_at = Time.get_unix_time_from_system()
	_set_stage(Stage.WAITING)
	_status.text = "Invite sent to %s. Waiting for an answer..." % to_name


func _new_room_code() -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


func _cancel_sent_invite() -> void:
	if _sent_to_uid != "":
		await Net.db_delete("invites/%s/%s" % [_sent_to_uid, Net.uid])
	_sent_room = ""
	_sent_to_uid = ""
	_sent_to_name = ""


# --- Polling -------------------------------------------------------------------

## One timer drives every "has anything changed" check, so the screen never has
## several overlapping requests in flight.
func _tick() -> void:
	if _busy:
		return
	match _stage:
		Stage.LIST:
			await _check_incoming_invite()
		Stage.WAITING:
			await _check_invite_answered()
		_:
			pass


func _check_incoming_invite() -> void:
	if _incoming_from_uid != "":
		return  # already showing one
	_busy = true
	var res: Dictionary = await Net.db_get("invites/%s" % Net.uid)
	_busy = false
	if not res["ok"] or not (res["data"] is Dictionary):
		return

	var now_ms := Time.get_unix_time_from_system() * 1000.0
	for from_uid in res["data"]:
		var inv = res["data"][from_uid]
		if not (inv is Dictionary):
			continue
		# Expired invites are cleaned up instead of shown — the sender has long
		# since given up waiting.
		if now_ms - float(inv.get("created_at", 0)) > INVITE_TIMEOUT_SECONDS * 1000.0:
			await Net.db_delete("invites/%s/%s" % [Net.uid, from_uid])
			continue
		_incoming_from_uid = String(from_uid)
		_incoming_from_name = String(inv.get("from_name", "?"))
		_incoming_room = String(inv.get("room", ""))
		_invite_label.text = "%s wants to play against you." % _incoming_from_name
		_invite_panel.visible = true
		return


func _check_invite_answered() -> void:
	if Time.get_unix_time_from_system() - _sent_at > INVITE_TIMEOUT_SECONDS:
		await _cancel_sent_invite()
		_set_stage(Stage.LIST)
		_status.text = "%s did not answer." % _sent_to_name
		await _refresh_list()
		return

	_busy = true
	var res: Dictionary = await Net.db_get("rooms/%s/guest" % _sent_room)
	_busy = false
	if res["ok"] and res["data"] != null:
		await _enter_room(_sent_room, _sent_to_name, _sent_to_uid, true)


# --- Answering an invite -------------------------------------------------------

func _on_accept_pressed() -> void:
	if _busy or _incoming_room == "":
		return
	_busy = true
	var joined: Dictionary = await Net.db_patch("rooms/%s" % _incoming_room, {
		"guest": Net.uid,
		"guest_country": Settings.player_country,
		"state": "playing",
	})
	if joined["ok"]:
		await Net.db_delete("invites/%s/%s" % [Net.uid, _incoming_from_uid])
	_busy = false

	if not joined["ok"]:
		_status.text = "Could not join room: %s" % joined["error"]
		return

	var code := _incoming_room
	var who := _incoming_from_name
	var from_uid := _incoming_from_uid
	_clear_incoming()
	await _enter_room(code, who, from_uid, false)


func _on_decline_pressed() -> void:
	if _busy:
		return
	_busy = true
	await Net.db_delete("invites/%s/%s" % [Net.uid, _incoming_from_uid])
	_busy = false
	_clear_incoming()
	_status.text = "Invite declined."


func _clear_incoming() -> void:
	_incoming_from_uid = ""
	_incoming_from_name = ""
	_incoming_room = ""
	_invite_panel.visible = false


# --- Room ----------------------------------------------------------------------

## Opponent found. Reads their country off the room and their NAME off
## /players/{uid} — the name is deliberately not duplicated into the room, since
## it already lives in the presence record and copying it there would mean
## widening the database rules for nothing.
func _enter_room(code: String, opponent: String, opponent_uid: String, is_host: bool) -> void:
	_room_code = code
	_room_opponent = opponent
	_set_stage(Stage.ROOM)
	_room_label.text = "Match found\nYou vs %s" % opponent
	_status.text = "Starting..."

	# Marks us busy so nobody invites a player who is already in a match.
	await _publish_me("in_match")

	var country := ""
	var room_res: Dictionary = await Net.db_get("rooms/%s" % code)
	if room_res["ok"] and room_res["data"] is Dictionary:
		var key := "guest_country" if is_host else "host_country"
		country = String(room_res["data"].get(key, ""))

	var name_res: Dictionary = await Net.db_get("players/%s/name" % opponent_uid)
	var shown := opponent
	if name_res["ok"] and name_res["data"] != null:
		shown = String(name_res["data"])

	_heartbeat.stop()
	_poll.stop()
	match_ready.emit(code, Settings.sanitize_name(shown), country, is_host)


func _on_leave_pressed() -> void:
	# The room record itself is left behind: database.rules.json makes host and
	# created_at write-once, so it cannot be deleted yet. Harmless (a few dozen
	# bytes) and noted for when the room rules get tightened in Faza B.
	_room_code = ""
	_room_opponent = ""
	_set_stage(Stage.LIST)
	await _publish_me("idle")
	await _refresh_list()


func _on_back_pressed() -> void:
	# Best-effort tidy-up. Nothing depends on it — our record goes stale on its
	# own — but leaving promptly beats lingering in everyone's list for the next
	# two and a half minutes.
	_heartbeat.stop()
	_poll.stop()
	if _stage == Stage.WAITING:
		await _cancel_sent_invite()
	if Net.uid != "":
		await Net.db_delete("players/%s" % Net.uid)
	cancelled.emit()
