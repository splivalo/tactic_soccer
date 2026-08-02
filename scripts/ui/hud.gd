extends Control
## Match HUD: team shields (coloured from CountryKits), score, card counts.
## Layout is a plain placeholder — restyle freely in the editor, the script
## only cares about the unique node names below. Run this scene directly
## (F6) to preview it: it ships with Croatia vs Brazil demo values so it's
## never blank when opened alone.

@onready var _home_primary: TextureRect = %HomePrimary
@onready var _away_primary: TextureRect = %AwayPrimary
@onready var _home_name: Label = %HomeName
@onready var _away_name: Label = %AwayName
@onready var _score_label: Label = %ScoreLabel
@onready var _home_red: Label = %HomeRedCount
@onready var _home_yellow: Label = %HomeYellowCount
@onready var _away_red: Label = %AwayRedCount
@onready var _away_yellow: Label = %AwayYellowCount

@onready var _time_label: Label = %TimeLabel
@onready var _timer_pill: Control = %Timer # turn_timer.gd — draws the pill shape behind the icon+text
@onready var _big_countdown: Label = %BigCountdown

@onready var _pause_button: Button = %PauseButton
@onready var _pause_modal: Control = %PauseModal
@onready var _resume_button: Button = %ResumeButton
@onready var _exit_button: Button = %ExitButton

@onready var _footer_dot: Panel = %TurnDot
@onready var _footer_label: Label = %FooterLabel

@onready var _home_frame: TextureRect = _home_primary.get_parent().get_node("Frame")
@onready var _away_frame: TextureRect = _away_primary.get_parent().get_node("Frame")

@onready var _coin_toss: Control = %CoinToss
@onready var _coin_shield: Control = %Shield
@onready var _coin_primary: TextureRect = %Primary
@onready var _coin_code: Label = %CodeLabel

@onready var _announce: Control = %Announce
@onready var _announce_content: Control = %AnnounceContent
@onready var _announce_card_wrap: Control = %AnnounceCard.get_parent()
@onready var _announce_card: Panel = %AnnounceCard
@onready var _announce_label: Label = %AnnounceLabel

const TIMER_COLOR_NORMAL := Color("f7c41c") # matches turn_timer.gd's own default fill_color
const TIMER_COLOR_URGENT := Color(0.85, 0.1, 0.1, 1)
const TIMER_URGENT_AT := 5 # seconds_left at/below which the pill starts blinking red

const BREATH_LEG_TIME := 1.0 # seconds per half-cycle (fade out OR back in), 0.8-1.2s range

var _timer_blink_on := false
var _dot_style: StyleBoxFlat = null # own copy so recoloring the fill never touches the white border
var _announce_card_style: StyleBoxFlat = null # own copy, recolored per card type (yellow/red)
var _breathing_side := "" # which team's shield the breathing tween currently targets
var _breath_tween: Tween = null
var _home_color := Color.WHITE # kit primary colour, kept for the footer turn dot (shield itself is a flag now)
var _away_color := Color.WHITE

## Which logical side the person holding this device plays.
##
## The LEFT shield always belongs to them, mirroring the pitch: their own
## figures are always at the bottom (the camera is spun for the away player, see
## main.gd's _fit_camera), so having their crest on the right would put their
## team in two different places at once. The opponent sees the mirror image on
## their own device, which is the point.
##
## "HomeTeam" offline and for the host, so nothing changes for either of them.
var _local_side := "HomeTeam"


func set_local_side(side: String) -> void:
	_local_side = side


## True when `side` occupies the left-hand slot on THIS device.
func _is_left(side: String) -> bool:
	return side == _local_side


func _ready() -> void:
	_pause_button.pressed.connect(_open_pause_modal)
	_resume_button.pressed.connect(_close_pause_modal)
	_exit_button.pressed.connect(_exit_to_menu)
	_pause_modal.visible = false
	# TurnDot's fill is recolored per-team (see update_turn_hint); its white
	# outline must survive that untouched, so it needs its OWN StyleBoxFlat
	# instance — mutating bg_color on the shared one would affect every user
	# of that resource, and using node `modulate` (the old approach) tinted
	# the border by the same team colour as the fill, making a dark team's
	# colour (e.g. navy) erase the border's contrast entirely.
	_dot_style = (_footer_dot.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	_footer_dot.add_theme_stylebox_override("panel", _dot_style)
	# The scene's own default is visible (no explicit visible=false override in
	# hud.tscn) — only update_timer() hides it once urgent=false, and that
	# never runs before the first turn timer actually starts, so anything
	# shown before then (e.g. the new placement phase) would flash a stray "5".
	_big_countdown.visible = false
	# Each shield needs its OWN ShaderMaterial instance (the .tscn assigns the
	# same shared sub_resource to Home/CoinToss by default) so setting one
	# side's flag_texture uniform never bleeds into another shield.
	_home_primary.material = _home_primary.material.duplicate()
	_away_primary.material = _away_primary.material.duplicate()
	_coin_primary.material = _coin_primary.material.duplicate()
	# Same pattern as the turn dot: the card panel is recolored per yellow/red,
	# so it needs its OWN StyleBoxFlat instance or every user of that shared
	# resource would follow the last colour set.
	_announce_card_style = (_announce_card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	_announce_card.add_theme_stylebox_override("panel", _announce_card_style)


## Android/system back gesture: open the same pause+confirm modal instead of
## quitting straight to the OS.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_open_pause_modal()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _pause_modal.visible:
			_close_pause_modal()
		else:
			_open_pause_modal()
		get_viewport().set_input_as_handled()


func _open_pause_modal() -> void:
	_pause_modal.visible = true


func _close_pause_modal() -> void:
	_pause_modal.visible = false


func _exit_to_menu() -> void:
	GameFlow.goto(GameFlow.Screen.MAIN_MENU)


## Strips the HUD down to the footer for the tutorial.
##
## Shields, score, cards and the clock mean nothing while you are learning what
## a straight line is, and they are four more things competing with the one
## sentence you are meant to read. The footer stays because it is already the
## game's way of talking to the player — the placement phase uses it too, so the
## tutorial isn't inventing a second voice.
##
## Background deliberately STAYS: the tutorial's heading takes over the strip the
## bar vacates, and on bare pitch green that text had nothing behind it.
func show_match_chrome(on: bool) -> void:
	for node_name in ["Bar", "PauseButton"]:
		var node := get_node_or_null(node_name) as CanvasItem
		if node != null:
			node.visible = on


## Longest player name the shield label will show. It is sized for a 3-letter
## country code, and a name may be up to 16 characters.
const MAX_NAME_CHARS := 9


## Online shows the two players' NAMES instead of country codes, because
## duplicate countries are allowed and both sides would otherwise read the same.
##
## The name is truncated AND sanitized: it was typed by a stranger and lands in
## this HUD mid-match, so a line break would wreck the layout no matter how few
## characters were kept. Settings.sanitize_name removes those; this caps width.
func display_label(raw_name: String, fallback_code: String) -> String:
	var clean := Settings.sanitize_name(raw_name)
	if clean == "":
		return fallback_code
	if clean.length() <= MAX_NAME_CHARS:
		return clean
	return clean.left(MAX_NAME_CHARS - 1) + "…"


## side = "HomeTeam" / "AwayTeam". Fills the shield with the country's own
## flag (always visually distinct, unlike jersey colours which can still
## clash across two DIFFERENT match-ups even after resolve_match — see
## shield_flag.gdshader) and sets the 3-letter code. `kit` is still the
## clash-resolved kit (used for the 3D players elsewhere); only its primary
## colour is kept here, for the footer's turn-dot tint — falling back to the
## kit's secondary colour when primary is white/near-white, since a white
## dot has no contrast against its own white outline (see set_footer_text's
## comment on the dot's border).
##
## `label_override` replaces the country code with a player name (online only).
func set_team(side: String, country: String, kit: Dictionary, label_override: String = "") -> void:
	var code := CountryKits.get_code(country)
	if label_override != "":
		code = display_label(label_override, code)
	var primary: TextureRect = _home_primary if _is_left(side) else _away_primary
	var name_label: Label = _home_name if _is_left(side) else _away_name
	var flag_path := CountryKits.get_flag(country)
	if flag_path != "":
		primary.material.set_shader_parameter("flag_texture", load(flag_path))
	name_label.text = code
	var dot_color: Color = kit["secondary"] if CountryKits.is_near_white(kit["primary"]) else kit["primary"]
	if _is_left(side):
		_home_color = dot_color
	else:
		_away_color = dot_color


## score = MatchState.score ({"HomeTeam": int, "AwayTeam": int}).
func update_score(score: Dictionary) -> void:
	# Left number is always the local player's, matching their shield.
	var left := _local_side
	var right := "AwayTeam" if left == "HomeTeam" else "HomeTeam"
	_score_label.text = "%d : %d" % [score.get(left, 0), score.get(right, 0)]


## yellow / red = MatchState.yellow_card / red_card (bool per team — at most
## one of each before a mandatory figure removal kicks in, see rules).
func update_cards(yellow: Dictionary, red: Dictionary) -> void:
	var left := _local_side
	var right := "AwayTeam" if left == "HomeTeam" else "HomeTeam"
	_home_yellow.text = str(int(yellow.get(left, false)))
	_home_red.text = str(int(red.get(left, false)))
	_away_yellow.text = str(int(yellow.get(right, false)))
	_away_red.text = str(int(red.get(right, false)))


## Whole seconds left in the current player's decision (see main.gd's turn
## timer). Called once per whole-second tick, so toggling the blink here
## (rather than on a separate timer) naturally blinks once per second.
## A negative value means "this turn isn't on your clock" — online, only the
## player to move runs a countdown, so the waiting side shows a dash instead of
## a number that would drift out of step with the opponent's.
func update_timer(seconds_left: int) -> void:
	if seconds_left < 0:
		_time_label.text = "—"
		_timer_blink_on = false
		_timer_pill.fill_color = TIMER_COLOR_NORMAL
		_timer_pill.queue_redraw()
		_time_label.add_theme_color_override("font_color", Color.BLACK)
		_big_countdown.visible = false
		return
	_time_label.text = "%d SEC" % seconds_left
	var urgent: bool = seconds_left > 0 and seconds_left <= TIMER_URGENT_AT
	if urgent:
		_timer_blink_on = not _timer_blink_on
	else:
		_timer_blink_on = false
	_timer_pill.fill_color = TIMER_COLOR_URGENT if _timer_blink_on else TIMER_COLOR_NORMAL
	_timer_pill.queue_redraw()
	_time_label.add_theme_color_override("font_color", Color.WHITE if _timer_blink_on else Color.BLACK)
	# Big center-pitch countdown — the small HUD pill blink alone doesn't read
	# as urgent enough. Same threshold, dead simple: just show the number.
	_big_countdown.visible = urgent
	if urgent:
		_big_countdown.text = str(seconds_left)


## Literal footer text + dot colour — used by the pre-match placement/search
## phase (main.gd), which has no MatchState.Phase yet to derive text from the
## way update_turn_hint below does.
func set_footer_text(text: String, dot_color: Color) -> void:
	_footer_label.text = text
	_dot_style.bg_color = dot_color


## side = "HomeTeam"/"AwayTeam", phase = MatchState.Phase — bottom hint bar
## telling the player whose turn it is and what to do (dot tinted with that
## team's kit colour). `intro`, if given, is prefixed once (e.g. the goals-to-
## win reminder shown at kickoff) and dropped again on the next call.
## `moves_left` (MatchState.moves_left) is kept for signature compatibility
## but no longer varies — every MOVE phase is now a single reactive move
## (2026-07-22 "1 action per turn" redesign), so there's nothing left to
## call out differently there.
func update_turn_hint(side: String, phase: int, intro: String = "", _moves_left: int = 1) -> void:
	var code: String = _home_name.text if _is_left(side) else _away_name.text
	var dot_color: Color = _home_color if _is_left(side) else _away_color
	var verb := "plays"
	match phase:
		MatchState.Phase.COMBO:
			verb = "pass, shoot, or move a player"
		MatchState.Phase.MOVE:
			verb = "move a player"
		MatchState.Phase.REMOVE:
			verb = "remove a player (red card)"
	var hint := "%s: %s" % [code, verb]
	_footer_label.text = "%s   —   %s" % [intro, hint] if intro != "" else hint
	_dot_style.bg_color = dot_color
	_breathe_shield(side)


## Soft "breathing" loop on whichever shield is active (full white -> fully
## transparent -> full white, eased, looping) — a quiet "this one" cue instead
## of repeating the team code in text. Fades ALPHA all the way to 0, not just
## a dimmer RGB, so the frame actually appears/disappears rather than merely
## dimming. No-ops if the same side is already breathing (a phase change
## within the same team's turn shouldn't restart/jolt the animation).
func _breathe_shield(side: String) -> void:
	if _breathing_side == side:
		return
	_breathing_side = side
	if _breath_tween != null:
		_breath_tween.kill()
	_home_frame.modulate = Color.WHITE
	_away_frame.modulate = Color.WHITE
	var target: Control = _home_frame if _is_left(side) else _away_frame
	var gone := Color(1.0, 1.0, 1.0, 0.0)
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(target, "modulate", gone, BREATH_LEG_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(target, "modulate", Color.WHITE, BREATH_LEG_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Pre-match coin toss: alternates the big centered shield between the two
## teams' flags/codes while squashing it edge-on (scale.x 1->0->1), slowing
## down each leg so it reads as "spinning down" to a stop — then forces the
## FINAL leg to land on a winner decided up front, regardless of where the
## alternation pattern would otherwise land. No separate "X KICKS OFF!"
## reveal — that label popping in grew the VBox and visibly shunted the
## just-landed shield upward; landing on the winner's flag/code already
## reads as the result. Returns the winning side once it's held long enough
## to read, then hidden.
## `forced_winner` makes the outcome an input rather than a roll. Online MUST
## pass it: each device running its own randi() means host and guest start with
## different teams to move, and the very first turn one of them plays is illegal
## by the other's rules — a desync before anyone has touched the ball.
## `home_label` / `away_label` replace the country codes with player names,
## exactly as the shields do during the match. Online needs it for the same
## reason: duplicate countries are allowed, so a coin landing on "CRO" would say
## nothing about who won it. Passing them also keeps the toss and the HUD
## reading the same way instead of one saying CRO and the other Marko.
func play_coin_toss(home_code: String, away_code: String, home_country: String,
		away_country: String, forced_winner: String = "",
		home_label: String = "", away_label: String = "") -> String:
	var winner: String = forced_winner
	if winner != "HomeTeam" and winner != "AwayTeam":
		winner = "HomeTeam" if randi() % 2 == 0 else "AwayTeam"
	var codes := {
		"HomeTeam": display_label(home_label, home_code) if home_label != "" else home_code,
		"AwayTeam": display_label(away_label, away_code) if away_label != "" else away_code,
	}
	var flags := {
		"HomeTeam": load(CountryKits.get_flag(home_country)) as Texture2D,
		"AwayTeam": load(CountryKits.get_flag(away_country)) as Texture2D,
	}

	_coin_toss.visible = true
	_coin_shield.scale.x = 1.0
	var current_side: String = "HomeTeam" if randi() % 2 == 0 else "AwayTeam"
	_show_coin_side(current_side, codes, flags)

	const FLIP_COUNT := 7
	for i in range(FLIP_COUNT):
		var duration: float = lerp(0.09, 0.32, float(i) / float(FLIP_COUNT - 1))
		var next_side: String = winner if i == FLIP_COUNT - 1 else \
			("AwayTeam" if current_side == "HomeTeam" else "HomeTeam")
		var out_tween := create_tween()
		out_tween.tween_property(_coin_shield, "scale:x", 0.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await out_tween.finished
		_show_coin_side(next_side, codes, flags)
		var in_tween := create_tween()
		in_tween.tween_property(_coin_shield, "scale:x", 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await in_tween.finished
		current_side = next_side

	await get_tree().create_timer(1.1).timeout
	_coin_toss.visible = false
	return winner


func _show_coin_side(side: String, codes: Dictionary, flags: Dictionary) -> void:
	_coin_primary.material.set_shader_parameter("flag_texture", flags[side])
	_coin_code.text = codes[side]


const ANNOUNCE_COLOR := {
	"yellow": Color(0.95, 0.79, 0.1),
	"red": Color(0.82, 0.1, 0.12),
	"offside": Color(1.0, 0.62, 0.05),
}
const ANNOUNCE_TEXT := {"yellow": "YELLOW CARD", "red": "RED CARD", "offside": "OFFSIDE"}


## Big center-pitch flash for a yellow/red card or an offside call — the same
## "you can't miss it" treatment as the coin toss, because the footer hint alone
## reads too quietly for something this consequential. A card shows the coloured
## card graphic + white text; offside hides the card and just flashes the word
## in its own amber. Awaited: main.gd stays _busy while it plays, so it can't
## overlap the next action. kind = "yellow" | "red" | "offside" (anything else
## is a no-op). Safe to await even when a card and something else coincide —
## calls are serialised by the caller.
## `who` names the punished side on the banner ("MARKO — YELLOW CARD").
##
## Without it both players saw an identical, unattributed "YELLOW CARD" and the
## one who had merely been waiting had no way to tell it wasn't theirs. On a
## shared hot-seat screen that was obvious from who was holding the phone;
## online it is not, so the banner has to say.
func play_announcement(kind: String, who: String = "") -> void:
	if not ANNOUNCE_TEXT.has(kind):
		return
	var color: Color = ANNOUNCE_COLOR[kind]
	var is_card: bool = kind != "offside"
	# Hide the WHOLE card slot (not just the panel) for offside — an invisible
	# Control still reserves its custom_minimum_size in the VBox, which was
	# pushing "OFFSIDE" down into the card's text slot instead of centering it.
	_announce_card_wrap.visible = is_card
	if is_card:
		_announce_card_style.bg_color = color
	_announce_label.text = ANNOUNCE_TEXT[kind]
	if who != "":
		_announce_label.text = "%s — %s" % [who, ANNOUNCE_TEXT[kind]]
	_announce_label.add_theme_color_override("font_color", Color.WHITE if is_card else color)
	_announce.visible = true
	_announce.modulate = Color(1, 1, 1, 0)
	# Node sizes are only valid after this frame's container layout — pivot the
	# card (its tilt) and the whole stack (the pop) around their real centres.
	await get_tree().process_frame
	if is_card:
		_announce_card.pivot_offset = _announce_card.size / 2.0
		_announce_card.rotation = deg_to_rad(-7)
	_announce_content.pivot_offset = _announce_content.size / 2.0
	_announce_content.scale = Vector2(0.6, 0.6)
	var pop := create_tween()
	pop.tween_property(_announce, "modulate:a", 1.0, 0.14)
	pop.parallel().tween_property(_announce_content, "scale", Vector2(1.12, 1.12), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_announce_content, "scale", Vector2.ONE, 0.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await pop.finished
	await get_tree().create_timer(0.85).timeout
	var fade := create_tween()
	fade.tween_property(_announce, "modulate:a", 0.0, 0.28)
	await fade.finished
	_announce.visible = false


## Single call point for main.gd's view-refresh — mirrors MatchState in one
## line. Re-derives the SAME clash-resolved kits main.gd's _build_team()
## used for the actual 3D players (resolve_match is a pure function of the
## two country names, so calling it again here always agrees with them).
func refresh(state: MatchState, home_country: String, away_country: String,
		home_label: String = "", away_label: String = "") -> void:
	var kits := CountryKits.resolve_match(home_country, away_country)
	set_team("HomeTeam", home_country, kits["home"], home_label)
	set_team("AwayTeam", away_country, kits["away"], away_label)
	update_score(state.score)
	update_cards(state.yellow_card, state.red_card)
