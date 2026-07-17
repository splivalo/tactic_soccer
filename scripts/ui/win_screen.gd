extends Control
## Shown when a match ends (MatchState.goals_to_win reached). main.gd sets
## GameFlow.last_winner/last_score right before routing here; home_country/
## away_country are already on GameFlow from team select.

const CONFETTI_GOLD := Color("f6c342")
const CONFETTI_WHITE := Color(1, 1, 1)
const CONFETTI_TOTAL := 140 # spread across 4 emitters (gold/white x rect/triangle)
const CONFETTI_LIFETIME := 2.6 # falls for ~this long, then fades out and is gone

@onready var _title: Label = %Title
@onready var _score_label: Label = %ScoreLabel
@onready var _winner_primary: TextureRect = %WinnerPrimary
@onready var _winner_secondary: TextureRect = %WinnerSecondary
@onready var _back_button: Button = %BackButton
@onready var _confetti_layer: Control = %ConfettiLayer


func _ready() -> void:
	var winner: String = GameFlow.last_winner
	var winner_country: String = GameFlow.home_country if winner == "HomeTeam" else GameFlow.away_country
	var kit := CountryKits.get_kit(winner_country, "home")
	_winner_primary.modulate = kit["primary"]
	_winner_secondary.modulate = kit["secondary"]
	_title.text = "YOU WIN"
	var score: Dictionary = GameFlow.last_score
	_score_label.text = "%d : %d" % [score.get("HomeTeam", 0), score.get("AwayTeam", 0)]
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))
	_spawn_confetti()


# --- Confetti -----------------------------------------------------------------
# Fountain burst from screen center: small at launch, growing as they arc up
# and rain back down, fade out near the end. No confetti art in the project,
# so both particle shapes are drawn into tiny textures at runtime instead of
# shipping new assets.
func _spawn_confetti() -> void:
	var rect_tex := _make_rect_texture()
	var tri_tex := _make_triangle_texture()
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	var grow := Curve.new() # starts tiny (like before), grows toward full size as it falls
	grow.add_point(Vector2(0.0, 0.15))
	grow.add_point(Vector2(1.0, 1.0))
	var width: float = size.x if size.x > 0.0 else get_viewport_rect().size.x
	var height: float = size.y if size.y > 0.0 else get_viewport_rect().size.y
	var origin := Vector2(width * 0.5, height * 0.5) # explodes from the middle of the screen
	var quarter := CONFETTI_TOTAL / 4
	for color in [CONFETTI_GOLD, CONFETTI_WHITE]:
		for tex in [rect_tex, tri_tex]:
			_make_confetti_emitter(tex, color, quarter, origin, fade, grow)


func _make_confetti_emitter(tex: Texture2D, color: Color, amount: int, origin: Vector2, fade: Gradient, grow: Curve) -> void:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = CONFETTI_LIFETIME
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = true
	p.position = origin
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 20.0
	p.direction = Vector2(0, -1) # shoots UP first, like a fountain/geyser
	p.spread = 80.0 # wide cone so it sprays out sideways too, not just straight up
	p.gravity = Vector2(0, 600.0) # strong pull back down after the launch
	p.initial_velocity_min = 300.0
	p.initial_velocity_max = 650.0
	p.angular_velocity_min = -280.0
	p.angular_velocity_max = 280.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.9
	p.scale_amount_curve = grow
	p.color = color
	p.color_ramp = fade
	_confetti_layer.add_child(p)
	get_tree().create_timer(CONFETTI_LIFETIME + 0.5).timeout.connect(p.queue_free)


func _make_rect_texture() -> ImageTexture:
	var img := Image.create(10, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _make_triangle_texture() -> ImageTexture:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var half := int(float(y) * 0.5 * (float(w) / float(h)))
		for x in range(w / 2 - half, w / 2 + half + 1):
			if x >= 0 and x < w:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
