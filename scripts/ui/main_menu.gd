extends Control
## Main menu (after splash), modeled on the 2006 original's menu.
## Everything routes through GameFlow. Layout/look is yours to redesign in
## the editor — this script only wires the buttons below (unique names in
## the scene).

@onready var _one_player_button: Button = %OnePlayerButton
@onready var _online_button: Button = %OnlineButton
@onready var _options_button: Button = %OptionsButton
@onready var _instructions_button: Button = %InstructionsButton
@onready var _credits_button: Button = %CreditsButton
@onready var _quit_button: Button = %QuitButton

@onready var _settings_modal: Control = %SettingsModal
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _vibration_check: CheckBox = %VibrationCheck
@onready var _settings_close_button: Button = %SettingsCloseButton


## Until the tutorial has been opened once, the two play modes are shown but
## closed. Not out of strictness — the whole reason the tutorial exists is a
## first-time player who bounced off the game without it — but the lock has to
## explain itself, so a tap on a closed mode says why in the button's own label
## and then puts it back. A permanent line of instructions under the menu would
## have cost a row on a screen that already carries six buttons and Legal.
const LOCK_MESSAGE := "Play How to Play first"
const LOCK_MESSAGE_SECONDS := 2.0

## Greyed, not faded. This was alpha, which lets the dark background bleed
## through a yellow button and turns it muddy — so the locked pair read as a
## DIFFERENT yellow rather than as the same button turned down, and the row
## stopped looking like a set. A multiply keeps the hue and only takes the
## brightness.
const LOCK_DIM := Color(0.5, 0.5, 0.5, 1.0)

var _locked := false
var _refusing: Button = null
var _refusing_text := ""

## True once a press has started loading another screen. The match scene takes a
## visible moment to build, and with nothing acknowledging the tap people press
## again — which used to queue a second navigation behind the first.
var _navigating := false


func _ready() -> void:
	# Only for someone who has never opened it. Finishing isn't required: a lock
	# that only lifts on completion traps anyone who backs out mid-tutorial in a
	# menu where the only live button is the one they just left.
	_locked = not Settings.tutorial_seen

	_one_player_button.pressed.connect(func():
		if _refuse(_one_player_button) or _leaving():
			return
		GameFlow.single_player = true
		GameFlow.goto(GameFlow.Screen.DIFFICULTY_SELECT))
	# Two modes only: AI and Online. The local hot-seat entry was dropped on
	# 2026-07-30 once online worked — two people sharing one phone is an edge
	# case, and the button was adding a choice without adding value. The
	# hot-seat LOGIC in main.gd/MatchState is untouched; only the way in is gone.
	# Online goes to country select FIRST, exactly like the single player route
	# does — same screen, same Back/Next. Picking it up front (rather than from
	# a button on the online screen) keeps the two modes consistent and keeps
	# the online screen from growing yet another button.
	_online_button.pressed.connect(func():
		if _refuse(_online_button) or _leaving():
			return
		GameFlow.single_player = false
		GameFlow.reset_online()
		GameFlow.online_mode = true
		GameFlow.online_country_picker = true
		GameFlow.goto(GameFlow.Screen.TEAM_SELECT))
	_options_button.pressed.connect(_open_settings)
	# "Instructions" now runs the tutorial. The cards it replaced described the
	# same three things in words, and words are exactly what a first-time player
	# doesn't read — the tutorial ends on the one card that survived, the general
	# rules, which no single turn can teach.
	#
	# Renamed to match: "Instructions" is the least inviting word available for
	# what is, on a first launch, the only button that does anything. Set here
	# rather than in the scene so main_menu.tscn stays as authored.
	_instructions_button.text = "How to Play"
	_instructions_button.pressed.connect(func():
		if _leaving():
			return
		GameFlow.reset_online()
		GameFlow.single_player = false
		GameFlow.tutorial_mode = true
		GameFlow.player_formation = []
		GameFlow.player_side = "HomeTeam"
		GameFlow.goto(GameFlow.Screen.MATCH))
	_credits_button.pressed.connect(func():
		if _leaving():
			return
		GameFlow.goto(GameFlow.Screen.LEGAL))
	_quit_button.pressed.connect(func(): get_tree().quit())

	_music_slider.value_changed.connect(Settings.set_music_volume)
	_sfx_slider.value_changed.connect(Settings.set_sfx_volume)
	_vibration_check.toggled.connect(Settings.set_vibration_enabled)
	_settings_close_button.pressed.connect(func(): _settings_modal.visible = false)

	if _locked:
		_apply_lock()


## True when a screen change is already under way, so the caller should do
## nothing. The match scene takes a moment to build and the menu gave no sign a
## tap had landed, so people pressed again — and each press queued another
## navigation. The whole row goes dim and stops responding the instant the first
## one lands, which both acknowledges it and makes the repeats harmless.
func _leaving() -> bool:
	if _navigating:
		return true
	_navigating = true
	for b in [_one_player_button, _online_button, _instructions_button,
			_options_button, _credits_button, _quit_button]:
		b.disabled = true
		b.modulate = LOCK_DIM
	return false


## Dims the two closed modes. Nothing is done to How to Play at all: the two
## dead buttons above it already push the eye down to the first live thing, and
## that IS How to Play.
##
## It used to breathe. Fading its alpha put it a tenth away from the locked
## look, so it read as switching itself on and off; brightening instead fixed
## that but left the yellow flashing, which is worse than the problem — a menu
## that pulses while you are reading it. The contrast was doing the work anyway.
##
## The closed buttons stay ENABLED — a disabled Button emits nothing when
## pressed, and a lock that can't be tapped can't explain itself.
func _apply_lock() -> void:
	for b in [_one_player_button, _online_button]:
		b.modulate = LOCK_DIM


## True when the press was a locked one and has been answered — the caller must
## then do nothing else. The message goes IN the button that was pressed: it
## needs no space of its own, nothing on the screen moves, and there is no
## question about which button it refers to.
## Deliberately NOT a coroutine — the caller branches on what it returns, and a
## function that awaits hands back a suspended call rather than a bool.
func _refuse(button: Button) -> bool:
	if not _locked:
		return false
	_restore_refusal() # one at a time, or two buttons read the same line at once
	_refusing = button
	_refusing_text = button.text
	button.text = LOCK_MESSAGE
	get_tree().create_timer(LOCK_MESSAGE_SECONDS).timeout.connect(func():
		if _refusing == button:
			_restore_refusal())
	return true


func _restore_refusal() -> void:
	if _refusing != null:
		_refusing.text = _refusing_text
		_refusing = null


## The main menu is the one screen where back SHOULD leave the game — it is the
## top of the stack, and quit_on_go_back is off now so nothing else does it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _open_settings() -> void:
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_vibration_check.button_pressed = Settings.vibration_enabled
	_settings_modal.visible = true
