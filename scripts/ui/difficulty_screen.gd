extends Control
## Single Player only — picks GameFlow.ai_difficulty, then on to team select
## (still choosing countries/kits same as local 2P; the AI just plays
## whichever side isn't GameFlow.player_side). Back returns to the main menu.

@onready var _easy_button: Button = %EasyButton
@onready var _medium_button: Button = %MediumButton
@onready var _hard_button: Button = %HardButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_easy_button.pressed.connect(_pick.bind("Easy"))
	_medium_button.pressed.connect(_pick.bind("Medium"))
	_hard_button.pressed.connect(_pick.bind("Hard"))
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))


func _pick(difficulty: String) -> void:
	GameFlow.ai_difficulty = difficulty
	GameFlow.goto(GameFlow.Screen.TEAM_SELECT)
