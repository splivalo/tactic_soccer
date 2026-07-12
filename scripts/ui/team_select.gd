extends Control
## Team select: ONE screen, TWO passes (hotseat). Player 1 picks a side +
## country; Player 2 then sees the same screen with Player 1's side forced
## to the opposite and Player 1's country disabled (mirrors the original
## 2006 game's flow — see the reference screenshot).
## Each country in the grid is a small wrapper Control holding a "Flag"
## TextureButton. The flag's rounded_texture shader both chamfers the corners
## AND draws the yellow selection border along that exact same edge (via its
## border_width uniform) — a separate StyleBox outline uses different corner
## math and never lines up, so the border lives in the shader instead. The
## side halves (choose_side.png, mirrored in the luminance_dim shader for
## Away) use a different selection language on purpose — no border, just
## dimmed-when-unselected — so it reads as picking a physical side of the
## pitch rather than an item from a list. All authored directly in the scene
## so it's visible/tunable in the editor — the script just collects the
## nodes and drives selection state.

## UV-space width of the selection border painted by the shader (flag is
## ~140px, so 0.05 ≈ 7px).
const COUNTRY_BORDER := 0.05
const COLOR_SELECTED := Color(0.97, 0.76, 0.15, 1.0)  # yellow, matches buttons
const COLOR_TAKEN := Color(0.85, 0.16, 0.16, 1.0)  # red, "not available to you"

@onready var _title: Label = %Title
@onready var _side_home_button: TextureButton = %SideHomeButton
@onready var _side_away_button: TextureButton = %SideAwayButton
@onready var _country_grid: GridContainer = %CountryGrid
@onready var _back_button: Button = %BackButton
@onready var _next_button: Button = %NextButton

var _country_buttons: Dictionary = {}  # String country -> TextureButton

var _stage := 0  # 0 = picking for player 1, 1 = picking for player 2
var _p1_side := ""
var _p1_country := ""


func _ready() -> void:
	_collect_country_buttons()
	_side_home_button.toggled.connect(func(_pressed: bool): _update_side_visual())
	_side_away_button.toggled.connect(func(_pressed: bool): _update_side_visual())
	_back_button.pressed.connect(_on_back_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_refresh_stage()


func _collect_country_buttons() -> void:
	for wrapper in _country_grid.get_children():
		var country := wrapper.name
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


## Selected = full brightness, unselected = dimmed via the luminance_dim
## shader (see assets/shaders/luminance_dim.gdshader) so the white pitch
## lines stay visible instead of going grey like a plain modulate would. No
## ring here on purpose (see class doc) — even the forced side for Player 2
## should still read as "selected", so this ignores `disabled` entirely.
func _update_side_visual() -> void:
	_side_home_button.material.set_shader_parameter("dim_amount", 0.0 if _side_home_button.button_pressed else 0.7)
	_side_away_button.material.set_shader_parameter("dim_amount", 0.0 if _side_away_button.button_pressed else 0.7)


## Resets both pickers for the current stage and applies Player 1's
## restrictions (forced side, disabled country) when it's Player 2's turn.
func _refresh_stage() -> void:
	_side_home_button.button_pressed = false
	_side_away_button.button_pressed = false
	_side_home_button.disabled = false
	_side_away_button.disabled = false
	for country in _country_buttons:
		var b: TextureButton = _country_buttons[country]
		b.button_pressed = false
		b.disabled = false

	if _stage == 0:
		_title.text = "PLAYER 1"
	else:
		_title.text = "PLAYER 2"
		var p2_side := "AwayTeam" if _p1_side == "HomeTeam" else "HomeTeam"
		_side_home_button.button_pressed = (p2_side == "HomeTeam")
		_side_away_button.button_pressed = (p2_side == "AwayTeam")
		_side_home_button.disabled = true
		_side_away_button.disabled = true
		if _country_buttons.has(_p1_country):
			_country_buttons[_p1_country].disabled = true

	_update_side_visual()
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
	_side_home_button.button_pressed = (_p1_side == "HomeTeam")
	_side_away_button.button_pressed = (_p1_side == "AwayTeam")
	if _country_buttons.has(_p1_country):
		_country_buttons[_p1_country].button_pressed = true


func _on_next_pressed() -> void:
	var picked_country := _picked_country()
	if picked_country == "":
		return  # nothing picked yet
	var picked_side := "HomeTeam" if _side_home_button.button_pressed else "AwayTeam"

	if _stage == 0:
		_p1_side = picked_side
		_p1_country = picked_country
		_stage = 1
		_refresh_stage()
		return

	if _p1_side == "HomeTeam":
		GameFlow.home_country = _p1_country
		GameFlow.away_country = picked_country
	else:
		GameFlow.home_country = picked_country
		GameFlow.away_country = _p1_country
	GameFlow.goto(GameFlow.Screen.FORMATION_SETUP)
