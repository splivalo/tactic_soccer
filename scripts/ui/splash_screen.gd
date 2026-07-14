extends Control
## Entry screen. Any tap/click/key continues to the main menu.
## Layout/look is yours to redesign in the editor (this script only wires
## the "continue" action — it doesn't care where anything is positioned).
##
## Uses _input (not _unhandled_input): the full-screen Control + its children
## have the default mouse_filter = Stop, so the GUI SWALLOWS taps/clicks before
## they'd reach _unhandled_input. On desktop a key press still slipped through,
## but on a real phone touch is the only input — so it looked dead. _input fires
## for every event before GUI mouse-filtering, so a tap anywhere always works.

var _going := false


func _input(event: InputEvent) -> void:
	if _going:
		return
	var is_continue: bool = false
	if event is InputEventScreenTouch and event.pressed:
		is_continue = true
	elif event is InputEventMouseButton and event.pressed:
		is_continue = true
	elif event is InputEventKey and event.pressed:
		is_continue = true
	if is_continue:
		_going = true
		get_viewport().set_input_as_handled()
		GameFlow.goto(GameFlow.Screen.MAIN_MENU)
