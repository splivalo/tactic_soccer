extends Control
## Entry screen. Any tap/click/key continues to the main menu.
## Layout/look is yours to redesign in the editor (this script only wires
## the "continue" action — it doesn't care where anything is positioned).

var _going := false


func _unhandled_input(event: InputEvent) -> void:
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
