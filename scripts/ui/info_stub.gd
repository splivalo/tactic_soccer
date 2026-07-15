extends Control
## Generic placeholder screen: title + body text + "Natrag" to the main menu.
## Reused by options_screen.tscn / legal_screen.tscn — each just sets
## title_text/body_text differently in its own scene file.

@export var title_text := "Uskoro"
@export_multiline var body_text := ""

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_title.text = title_text
	_body.text = body_text
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))
