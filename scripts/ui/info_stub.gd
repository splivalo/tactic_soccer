extends Control
## Generic placeholder screen: title + body text + a Back button to the main
## menu. Reused by options_screen.tscn / legal_screen.tscn — each just sets
## title_text/body_text differently in its own scene file.

@export var title_text := "Uskoro"
@export_multiline var body_text := ""

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_title.text = title_text
	_body.text = body_text
	_back_button.pressed.connect(_go_back)


## Android's back does the same as the on-screen button. Since
## quit_on_go_back is off (see project.godot) an unhandled back would simply do
## nothing here, which reads as a broken button.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()


func _go_back() -> void:
	GameFlow.goto(GameFlow.Screen.MAIN_MENU)
