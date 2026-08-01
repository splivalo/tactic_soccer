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


func _ready() -> void:
	_one_player_button.pressed.connect(func():
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
		GameFlow.single_player = false
		GameFlow.reset_online()
		GameFlow.online_mode = true
		GameFlow.online_country_picker = true
		GameFlow.goto(GameFlow.Screen.TEAM_SELECT))
	_options_button.pressed.connect(_open_settings)
	_instructions_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.INSTRUCTIONS))
	_credits_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.LEGAL))
	_quit_button.pressed.connect(func(): get_tree().quit())

	_music_slider.value_changed.connect(Settings.set_music_volume)
	_sfx_slider.value_changed.connect(Settings.set_sfx_volume)
	_vibration_check.toggled.connect(Settings.set_vibration_enabled)
	_settings_close_button.pressed.connect(func(): _settings_modal.visible = false)


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
