extends Control
## STUB: formation is still auto-placed by Formations.home()/away() (main.gd).
## Manual placement (pick your own layout, starting from the goalkeeper) is
## the next real feature to build here — this screen just completes the
## splash -> team select -> formation -> match chain end to end for now.

@onready var _back_button: Button = %BackButton
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.TEAM_SELECT))
	_start_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MATCH))
