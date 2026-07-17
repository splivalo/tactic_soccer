extends Node
## Autoload. Owns "where are we in the app" + settings chosen on menu screens
## (team/side/country) so screen scenes can hand off to each other without
## knowing about one another directly. main.gd reads the settings here (if
## set) and otherwise falls back to its own @export defaults, so main.tscn
## still works fine when run standalone in the editor.

enum Screen { SPLASH, MAIN_MENU, TEAM_SELECT, FORMATION_SETUP, OPTIONS, INSTRUCTIONS, LEGAL, MATCH, WIN_SCREEN, LOSE_SCREEN }

const SCENE_PATHS := {
	Screen.SPLASH: "res://scenes/ui/splash_screen.tscn",
	Screen.MAIN_MENU: "res://scenes/ui/main_menu.tscn",
	Screen.TEAM_SELECT: "res://scenes/ui/team_select.tscn",
	Screen.FORMATION_SETUP: "res://scenes/ui/formation_setup.tscn",
	Screen.OPTIONS: "res://scenes/ui/options_screen.tscn",
	Screen.INSTRUCTIONS: "res://scenes/ui/instructions_screen.tscn",
	Screen.LEGAL: "res://scenes/ui/legal_screen.tscn",
	Screen.MATCH: "res://main.tscn",
	Screen.WIN_SCREEN: "res://scenes/ui/win_screen.tscn",
	Screen.LOSE_SCREEN: "res://scenes/ui/lose_screen.tscn",
}

# Empty string = unset -> main.gd keeps its own @export default.
var home_country: String = ""
var away_country: String = ""
var player_side: String = "HomeTeam"

# Set by main.gd right before routing to WIN_SCREEN (goals_to_win reached).
var last_winner: String = "" # "HomeTeam" / "AwayTeam"
var last_score: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}


func goto(screen: int) -> void:
	get_tree().call_deferred("change_scene_to_file", SCENE_PATHS[screen])


func reset_selection() -> void:
	home_country = ""
	away_country = ""
	player_side = "HomeTeam"
