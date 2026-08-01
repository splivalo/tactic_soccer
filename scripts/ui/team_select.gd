extends Control
## Team select. ONE pass, always — you only ever choose your OWN country.
##
## It used to run two passes for the local hot-seat (player 1 picked, then the
## screen reset with that country disabled for player 2). Hot-seat left the menu
## on 2026-07-30, so nothing could reach the second pass any more and it was
## removed along with the "this country is taken" state.
##
## Two callers remain:
##   - Single player: you pick, the AI gets a random different country.
##   - Online (GameFlow.online_country_picker): you pick YOUR country, it is
##     saved to Settings and reused for every match. Duplicates are allowed
##     online — two players may both be Croatia, and the guest simply plays in
##     the alternative kit — so there is nothing to coordinate and nothing to
##     grey out (GAME_DESIGN.md §11).
##
## Each country in the grid is a small wrapper Control holding a "Flag"
## TextureButton. The flag's rounded_texture shader both chamfers the corners
## AND draws the yellow selection border along that exact same edge (via its
## border_width uniform) — a separate StyleBox outline uses different corner
## math and never lines up, so the border lives in the shader instead. All
## authored directly in the scene so it's visible/tunable in the editor — the
## script just collects the nodes and drives selection state.

## UV-space width of the selection border painted by the shader (flag is
## ~140px, so 0.05 ≈ 7px).
const COUNTRY_BORDER := 0.05
const COLOR_SELECTED := Color(0.97, 0.76, 0.15, 1.0)  # yellow, matches buttons

@onready var _country_grid: GridContainer = %CountryGrid
@onready var _back_button: Button = %BackButton
@onready var _next_button: Button = %NextButton

var _country_buttons: Dictionary = {}  # String country -> TextureButton

var _for_online := false


func _ready() -> void:
	_for_online = GameFlow.online_country_picker
	if not _for_online:
		# Starting a genuinely NEW match — a formation placed for a PREVIOUS
		# game must not carry over and silently skip the placement phase
		# main.gd's _start_placement() checks for. The online picker is just
		# editing a setting, so it must not wipe anything.
		GameFlow.player_formation = []

	_collect_country_buttons()
	_back_button.pressed.connect(_on_back_pressed)
	_next_button.pressed.connect(_on_next_pressed)

	# Nothing is ever pre-selected, online included. Pre-ticking the country
	# saved from last time was tried and dropped: the choice is the entire point
	# of this screen, and starting it half-made invites tapping Next without
	# looking. Settings.player_country is still remembered — it just doesn't
	# preempt the decision.


func _collect_country_buttons() -> void:
	for wrapper in _country_grid.get_children():
		# String(), not the raw StringName Node.name gives — Array.erase() in
		# _finish_single_player() compares by exact variant type, so a
		# StringName key there never matched the String _p1_country and the
		# AI could end up "randomly" picking the player's own country back.
		var country := String(wrapper.name)
		var flag := wrapper.get_node("Flag") as TextureButton
		# Per-flag material copy so each can toggle its own border independently.
		flag.material = flag.material.duplicate()
		_country_buttons[country] = flag
		flag.toggled.connect(func(_pressed: bool): _update_country_visual(country))
		_update_country_visual(country)


## Selection = yellow border, drawn by the same shader edge as the corner
## chamfer. There is no "taken" state any more: nothing is ever off limits,
## because you only pick for yourself.
func _update_country_visual(country: String) -> void:
	var flag: TextureButton = _country_buttons[country]
	if flag.button_pressed:
		flag.material.set_shader_parameter("border_width", COUNTRY_BORDER)
		flag.material.set_shader_parameter("border_color", COLOR_SELECTED)
	else:
		flag.material.set_shader_parameter("border_width", 0.0)
	flag.modulate = Color(1, 1, 1, 1)


func _picked_country() -> String:
	for country in _country_buttons:
		if _country_buttons[country].button_pressed:
			return country
	return ""


## Back always means the main menu. For online this screen sits BETWEEN the menu
## and the player list, so Back goes back up the stack the player came through,
## and Back from the player list returns here — which is also how the country
## gets changed later, without needing a button for it.
func _on_back_pressed() -> void:
	GameFlow.online_country_picker = false
	GameFlow.goto(GameFlow.Screen.MAIN_MENU)


## Android's back mirrors the on-screen Back button (quit_on_go_back is off, so
## otherwise it would do nothing at all here).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _on_next_pressed() -> void:
	var picked_country := _picked_country()
	if picked_country == "":
		return  # nothing picked yet

	if _for_online:
		# Straight to the pitch. You place your formation first and only THEN
		# look for an opponent — as an overlay on that same board — so there is
		# no waiting once someone accepts (GAME_DESIGN.md §11).
		Settings.set_player_country(picked_country)
		GameFlow.online_country_picker = false
		GameFlow.home_country = picked_country
		GameFlow.player_side = "HomeTeam"
		GameFlow.player_formation = []
		GameFlow.goto(GameFlow.Screen.MATCH)
		return

	_finish_single_player()


## Random country for the AI (different from the player's pick where possible)
## instead of a second manual pick — don't make the player configure their OWN
## opponent.
func _finish_single_player() -> void:
	var mine := _picked_country()
	var choices := _country_buttons.keys()
	choices.erase(mine)
	if choices.is_empty():
		choices = _country_buttons.keys()
	var ai_country: String = choices[randi() % choices.size()]
	GameFlow.home_country = mine
	GameFlow.away_country = ai_country
	GameFlow.goto(GameFlow.Screen.MATCH)
