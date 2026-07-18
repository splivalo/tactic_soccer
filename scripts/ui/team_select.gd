extends Control
## Team select: ONE screen, TWO passes (hotseat). Player 1 picks a country;
## Player 2 then sees the same screen with Player 1's country disabled
## (mirrors the original 2006 game's flow — see the reference screenshot).
## Player 1 is always HomeTeam (bottom of the pitch, left shield in the HUD)
## and Player 2 is always AwayTeam — no side choice, since which physical
## side you're on doesn't affect the match, only which country is which.
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
const COLOR_TAKEN := Color(0.85, 0.16, 0.16, 1.0)  # red, "not available to you"

@onready var _country_grid: GridContainer = %CountryGrid
@onready var _back_button: Button = %BackButton
@onready var _next_button: Button = %NextButton

var _country_buttons: Dictionary = {}  # String country -> TextureButton

var _stage := 0  # 0 = picking for player 1, 1 = picking for player 2
var _p1_country := ""


func _ready() -> void:
	# Every visit here starts a genuinely NEW match — a formation placed for a
	# PREVIOUS game must not carry over and silently skip the placement phase
	# main.gd's _start_placement() checks for.
	GameFlow.player_formation = []
	_collect_country_buttons()
	_back_button.pressed.connect(_on_back_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_refresh_stage()


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


## Selection = yellow border. Disabled (taken by the other player) = dimmed
## flag + red border, so it reads as "off limits" rather than just "picked".
## Both borders are drawn by the same shader edge as the corner chamfer.
func _update_country_visual(country: String) -> void:
	var flag: TextureButton = _country_buttons[country]
	if flag.disabled:
		flag.material.set_shader_parameter("border_width", COUNTRY_BORDER)
		flag.material.set_shader_parameter("border_color", COLOR_TAKEN)
		flag.modulate = Color(0.35, 0.35, 0.35, 0.6)
	elif flag.button_pressed:
		flag.material.set_shader_parameter("border_width", COUNTRY_BORDER)
		flag.material.set_shader_parameter("border_color", COLOR_SELECTED)
		flag.modulate = Color(1, 1, 1, 1)
	else:
		flag.material.set_shader_parameter("border_width", 0.0)
		flag.modulate = Color(1, 1, 1, 1)


## Resets the country picker for the current stage and applies Player 1's
## restriction (disabled country) when it's Player 2's turn.
func _refresh_stage() -> void:
	for country in _country_buttons:
		var b: TextureButton = _country_buttons[country]
		b.button_pressed = false
		b.disabled = false

	if _stage == 1 and _country_buttons.has(_p1_country):
		_country_buttons[_p1_country].disabled = true

	for country in _country_buttons:
		_update_country_visual(country)


func _picked_country() -> String:
	for country in _country_buttons:
		if _country_buttons[country].button_pressed:
			return country
	return ""


func _on_back_pressed() -> void:
	if _stage == 0:
		GameFlow.goto(GameFlow.Screen.MAIN_MENU)
		return
	_stage = 0
	_refresh_stage()
	if _country_buttons.has(_p1_country):
		_country_buttons[_p1_country].button_pressed = true


## Player 1 is always Home, Player 2 is always Away (see class doc).
func _on_next_pressed() -> void:
	var picked_country := _picked_country()
	if picked_country == "":
		return  # nothing picked yet

	if _stage == 0:
		_p1_country = picked_country
		# Single Player has no human "Player 2" — don't make the player
		# configure their OWN opponent, just assign the AI a country and go.
		if GameFlow.single_player:
			_finish_single_player()
			return
		_stage = 1
		_refresh_stage()
		return

	GameFlow.home_country = _p1_country
	GameFlow.away_country = picked_country
	GameFlow.goto(GameFlow.Screen.MATCH) # formation placement now happens in-match, see main.gd


## Random country for the AI (different from the player's pick where
## possible) instead of a second manual pick — see _on_next_pressed.
func _finish_single_player() -> void:
	var choices := _country_buttons.keys()
	choices.erase(_p1_country)
	if choices.is_empty():
		choices = _country_buttons.keys()
	var ai_country: String = choices[randi() % choices.size()]
	GameFlow.home_country = _p1_country
	GameFlow.away_country = ai_country
	GameFlow.goto(GameFlow.Screen.MATCH)
