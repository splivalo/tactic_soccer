extends Control
## Match HUD: team shields (coloured from CountryKits), score, card counts.
## Layout is a plain placeholder — restyle freely in the editor, the script
## only cares about the unique node names below. Run this scene directly
## (F6) to preview it: it ships with Croatia vs Brazil demo values so it's
## never blank when opened alone.

@onready var _home_primary: TextureRect = %HomePrimary
@onready var _home_secondary: TextureRect = %HomeSecondary
@onready var _away_primary: TextureRect = %AwayPrimary
@onready var _away_secondary: TextureRect = %AwaySecondary
@onready var _home_name: Label = %HomeName
@onready var _away_name: Label = %AwayName
@onready var _score_label: Label = %ScoreLabel
@onready var _home_red: Label = %HomeRedCount
@onready var _home_yellow: Label = %HomeYellowCount
@onready var _away_red: Label = %AwayRedCount
@onready var _away_yellow: Label = %AwayYellowCount


## side = "HomeTeam" / "AwayTeam". Colours the shield and sets the 3-letter code.
func set_team(side: String, country: String) -> void:
	var kit := CountryKits.get_kit(country, "home")
	var code := CountryKits.get_code(country)
	var primary: TextureRect = _home_primary if side == "HomeTeam" else _away_primary
	var secondary: TextureRect = _home_secondary if side == "HomeTeam" else _away_secondary
	var name_label: Label = _home_name if side == "HomeTeam" else _away_name
	primary.modulate = kit["primary"]
	secondary.modulate = kit["secondary"]
	name_label.text = code


## score = MatchState.score ({"HomeTeam": int, "AwayTeam": int}).
func update_score(score: Dictionary) -> void:
	_score_label.text = "%d : %d" % [score.get("HomeTeam", 0), score.get("AwayTeam", 0)]


## yellow / red = MatchState.yellow_card / red_card (bool per team — at most
## one of each before a mandatory figure removal kicks in, see rules).
func update_cards(yellow: Dictionary, red: Dictionary) -> void:
	_home_yellow.text = str(int(yellow.get("HomeTeam", false)))
	_home_red.text = str(int(red.get("HomeTeam", false)))
	_away_yellow.text = str(int(yellow.get("AwayTeam", false)))
	_away_red.text = str(int(red.get("AwayTeam", false)))


## Single call point for main.gd's view-refresh — mirrors MatchState in one line.
func refresh(state: MatchState, home_country: String, away_country: String) -> void:
	set_team("HomeTeam", home_country)
	set_team("AwayTeam", away_country)
	update_score(state.score)
	update_cards(state.yellow_card, state.red_card)
