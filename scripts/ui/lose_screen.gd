extends Control
## Shown when a match ends and the viewing player was NOT the winner (see
## main.gd's WIN_SCREEN/LOSE_SCREEN routing). Same layout/glow as win_screen,
## minus the confetti — mirrors GameFlow.last_winner/last_score just like it.

@onready var _title: Label = %Title
@onready var _score_label: Label = %ScoreLabel
@onready var _loser_primary: TextureRect = %LoserPrimary
@onready var _loser_secondary: TextureRect = %LoserSecondary
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	var loser: String = _opponent(GameFlow.last_winner)
	var loser_country: String = GameFlow.home_country if loser == "HomeTeam" else GameFlow.away_country
	var kit := CountryKits.get_kit(loser_country, "home")
	_loser_primary.modulate = kit["primary"]
	_loser_secondary.modulate = kit["secondary"]
	_title.text = "YOU LOSE"
	var score: Dictionary = GameFlow.last_score
	_score_label.text = "%d : %d" % [score.get("HomeTeam", 0), score.get("AwayTeam", 0)]
	_back_button.pressed.connect(func(): GameFlow.goto(GameFlow.Screen.MAIN_MENU))


func _opponent(team: String) -> String:
	return "AwayTeam" if team == "HomeTeam" else "HomeTeam"
