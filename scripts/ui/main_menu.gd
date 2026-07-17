extends Control
## Main menu (after splash), modeled on the 2006 original's menu.
## Everything routes through GameFlow. Layout/look is yours to redesign in
## the editor — this script only wires the buttons below (unique names in
## the scene).

@onready var _one_player_button: Button = %OnePlayerButton
@onready var _two_player_button: Button = %TwoPlayerButton
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
	_two_player_button.pressed.connect(func():
		GameFlow.single_player = false
		GameFlow.goto(GameFlow.Screen.TEAM_SELECT))
	_options_button.pressed.connect(_open_settings)
	_instructions_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.INSTRUCTIONS))
	_credits_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.LEGAL))
	_quit_button.pressed.connect(func(): get_tree().quit())

	_music_slider.value_changed.connect(Settings.set_music_volume)
	_sfx_slider.value_changed.connect(Settings.set_sfx_volume)
	_vibration_check.toggled.connect(Settings.set_vibration_enabled)
	_settings_close_button.pressed.connect(func(): _settings_modal.visible = false)


func _open_settings() -> void:
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_vibration_check.button_pressed = Settings.vibration_enabled
	_settings_modal.visible = true
