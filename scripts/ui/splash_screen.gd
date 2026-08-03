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
		# Always the menu, even on a first launch. Dropping straight into the
		# tutorial put a board with figures on it in front of someone who had
		# started nothing and seen nothing of the app — it read as a match they
		# hadn't asked for. The menu names the game, shows what it offers, and
		# leaves only How to Play open (see main_menu.gd), so the player still
		# ends up in the tutorial — but by tapping it.
		GameFlow.goto(GameFlow.Screen.MAIN_MENU)
