extends Control
## Legal/credits screen: title + scrollable rich-text body + Back to menu.
## Body text is authored directly on the Body node in legal_screen.tscn.

@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))
