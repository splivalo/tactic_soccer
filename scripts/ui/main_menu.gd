extends Control
## Main menu (after splash), modeled on the 2006 original's menu.
## "1 Player game" is disabled until there's an AI opponent (see
## docs/TODO.md backlog — not built yet). Everything else routes through
## GameFlow. Layout/look is yours to redesign in the editor — this script
## only wires the buttons below (unique names in the scene).

@onready var _one_player_button: Button = %OnePlayerButton
@onready var _two_player_button: Button = %TwoPlayerButton
@onready var _options_button: Button = %OptionsButton
@onready var _instructions_button: Button = %InstructionsButton
@onready var _credits_button: Button = %CreditsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_one_player_button.disabled = true
	_one_player_button.tooltip_text = "Coming soon — no AI opponent yet"
	_two_player_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.TEAM_SELECT))
	_options_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.OPTIONS))
	_instructions_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.INSTRUCTIONS))
	_credits_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.LEGAL))
	_quit_button.pressed.connect(func(): get_tree().quit())
