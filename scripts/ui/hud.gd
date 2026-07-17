extends Control
## Match HUD: team shields (coloured from CountryKits), score, card counts.
## Layout is a plain placeholder — restyle freely in the editor, the script
## only cares about the unique node names below. Run this scene directly
## (F6) to preview it: it ships with Croatia vs Brazil demo values so it's
## never blank when opened alone.

@onready var _home_primary: TextureRect = %HomePrimary
@onready var _home_secondary: TextureRect = %HomeSecondary
@onready var _away_primary: TextureRect = %AwayPrimary
@onready var _away_secondary: TextureRect = %AwaySecondary
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

const TIMER_COLOR_NORMAL := Color("f7c41c") # matches turn_timer.gd's own default fill_color
const TIMER_COLOR_URGENT := Color(0.85, 0.1, 0.1, 1)
const TIMER_URGENT_AT := 5 # seconds_left at/below which the pill starts blinking red

const BREATH_LEG_TIME := 1.0 # seconds per half-cycle (fade out OR back in), 0.8-1.2s range
# Grey, not gold (gold read as a smudge) — and NOT as dark as the earlier 0.35
# attempt: the frame PNG has a baked-in bevel (darker shadow side), and at
# 0.35 that shadow side multiplied down into the black HUD background and
# visually vanished. 0.6 was confirmed safe but too subtle; 0.5 is the
# stronger-but-still-safe middle ground — verify the shadow side stays
# visible before pushing any lower.
const BREATH_DIM := 0.5

var _timer_blink_on := false
var _dot_style: StyleBoxFlat = null # own copy so recoloring the fill never touches the white border
var _breathing_side := "" # which team's shield the breathing tween currently targets
var _breath_tween: Tween = null


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


## side = "HomeTeam" / "AwayTeam". Colours the shield and sets the 3-letter code.
func set_team(side: String, country: String) -> void:
	var kit := CountryKits.get_kit(country, "home")
	var code := CountryKits.get_code(country)
	var primary: TextureRect = _home_primary if side == "HomeTeam" else _away_primary
	var secondary: TextureRect = _home_secondary if side == "HomeTeam" else _away_secondary
	var name_label: Label = _home_name if side == "HomeTeam" else _away_name
	primary.modulate = kit["primary"]
	secondary.modulate = kit["secondary"]
	name_label.text = code


## score = MatchState.score ({"HomeTeam": int, "AwayTeam": int}).
func update_score(score: Dictionary) -> void:
	_score_label.text = "%d : %d" % [score.get("HomeTeam", 0), score.get("AwayTeam", 0)]


## yellow / red = MatchState.yellow_card / red_card (bool per team — at most
## one of each before a mandatory figure removal kicks in, see rules).
func update_cards(yellow: Dictionary, red: Dictionary) -> void:
	_home_yellow.text = str(int(yellow.get("HomeTeam", false)))
	_home_red.text = str(int(red.get("HomeTeam", false)))
	_away_yellow.text = str(int(yellow.get("AwayTeam", false)))
	_away_red.text = str(int(red.get("AwayTeam", false)))


## Whole seconds left in the current player's decision (see main.gd's turn
## timer). Called once per whole-second tick, so toggling the blink here
## (rather than on a separate timer) naturally blinks once per second.
func update_timer(seconds_left: int) -> void:
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
func update_turn_hint(side: String, phase: int, intro: String = "") -> void:
	var code: String = _home_name.text if side == "HomeTeam" else _away_name.text
	var dot_color: Color = _home_primary.modulate if side == "HomeTeam" else _away_primary.modulate
	var verb := "plays"
	match phase:
		MatchState.Phase.COMBO:
			verb = "pass or shoot"
		MatchState.Phase.MOVE:
			verb = "move a player"
		MatchState.Phase.REMOVE:
			verb = "remove a player (red card)"
	var hint := "%s: %s" % [code, verb]
	_footer_label.text = "%s   —   %s" % [intro, hint] if intro != "" else hint
	_dot_style.bg_color = dot_color
	_breathe_shield(side)


## Soft "breathing" brightness loop on whichever shield is active (full white
## -> dim grey -> full white, eased, looping) — a quiet "this one" cue instead
## of repeating the team code in text. No-ops if the same side is already
## breathing (a phase change within the same team's turn shouldn't
## restart/jolt the animation).
func _breathe_shield(side: String) -> void:
	if _breathing_side == side:
		return
	_breathing_side = side
	if _breath_tween != null:
		_breath_tween.kill()
	_home_frame.modulate = Color.WHITE
	_away_frame.modulate = Color.WHITE
	var target: Control = _home_frame if side == "HomeTeam" else _away_frame
	var dim := Color(BREATH_DIM, BREATH_DIM, BREATH_DIM, 1.0)
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(target, "modulate", dim, BREATH_LEG_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(target, "modulate", Color.WHITE, BREATH_LEG_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Single call point for main.gd's view-refresh — mirrors MatchState in one line.
func refresh(state: MatchState, home_country: String, away_country: String) -> void:
	set_team("HomeTeam", home_country)
	set_team("AwayTeam", away_country)
	update_score(state.score)
	update_cards(state.yellow_card, state.red_card)
