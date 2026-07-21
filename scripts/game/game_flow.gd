extends Node
## Autoload. Owns "where are we in the app" + settings chosen on menu screens
## (team/side/country) so screen scenes can hand off to each other without
## knowing about one another directly. main.gd reads the settings here (if
## set) and otherwise falls back to its own @export defaults, so main.tscn
## still works fine when run standalone in the editor.

enum Screen { SPLASH, MAIN_MENU, DIFFICULTY_SELECT, TEAM_SELECT, OPTIONS, INSTRUCTIONS, LEGAL, MATCH, WIN_SCREEN, LOSE_SCREEN }

const SCENE_PATHS := {
	Screen.SPLASH: "res://scenes/ui/splash_screen.tscn",
	Screen.MAIN_MENU: "res://scenes/ui/main_menu.tscn",
	Screen.DIFFICULTY_SELECT: "res://scenes/ui/difficulty_screen.tscn",
	Screen.TEAM_SELECT: "res://scenes/ui/team_select.tscn",
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
# Set by main.gd's in-match placement phase (see _start_placement); empty =
# not placed yet, so main.gd falls back to Formations.home()/away().
var player_formation: Array[Dictionary] = []

# Set by main_menu.gd (Single Player vs Online) and difficulty_screen.gd.
# ai_difficulty only matters when single_player is true.
var single_player: bool = false
var ai_difficulty: String = "Medium" # "Easy" / "Medium" / "Hard"

# Set by main.gd right before routing to WIN_SCREEN (goals_to_win reached).
var last_winner: String = "" # "HomeTeam" / "AwayTeam"
var last_score: Dictionary = {"HomeTeam": 0, "AwayTeam": 0}


func goto(screen: int) -> void:
	if screen == Screen.MATCH:
		_fade_out_music()
	elif screen == Screen.WIN_SCREEN:
		_play_result_sfx(WIN_SOUND)
	elif screen == Screen.LOSE_SCREEN:
		_play_result_sfx(LOSE_SOUND)
	get_tree().call_deferred("change_scene_to_file", SCENE_PATHS[screen])


func reset_selection() -> void:
	home_country = ""
	away_country = ""
	player_side = "HomeTeam"
	player_formation = []
	single_player = false
	ai_difficulty = "Medium"


# --- Global UI tap SFX ---------------------------------------------------------
# One sound, everywhere: rather than wiring every screen's buttons by hand
# (and forgetting the next one), this autoload hooks EVERY BaseButton
# (Button, CheckBox, OptionButton, ...) the instant it enters ANY scene, for
# the whole app's lifetime — since GameFlow itself is one of the very first
# nodes alive (autoload), this is already listening before the splash
# screen's own buttons ever exist. Deliberately does NOT cover in-match
# board taps (selecting a figure/cell) — those go through main.gd's own
# raw touch/mouse handling (_on_press/_on_release), never a Button node, so
# they're untouched here; this is menu/UI chrome only, as asked for.
const TAP_SOUND: AudioStream = preload("res://assets/audio/sfx/tap.mp3")
@export_range(-24.0, 24.0, 0.5) var tap_sfx_volume_db := 0.0

var _tap_sfx: AudioStreamPlayer = null


# --- Menu background music ------------------------------------------------------
# Plays continuously from the moment the app launches (splash) through the
# WHOLE pre-match menu flow (main menu, team select, difficulty, instructions,
# options — every screen goto() can route to except MATCH) — lives on this
# autoload, not on splash_screen.gd, specifically so it survives
# change_scene_to_file() without cutting out and restarting at every screen
# change. Fades out and stops the moment the real match starts (see goto()) —
# continuous menu music playing under an actual match felt wrong to carry
# over unasked, so this stops there; nothing plays in its place yet.
const INTRO_MUSIC := preload("res://assets/audio/music/intro.mp3")
@export_range(-24.0, 24.0, 0.5) var music_volume_db := 0.0

var _music: AudioStreamPlayer = null


# --- Match result stings ---------------------------------------------------------
# Short win/lose musical cues, played once, right when goto() routes to the
# corresponding screen. main.gd already resolves perspective before calling
# goto() (WIN_SCREEN only happens when GameFlow.player_side is the actual
# scorer — see main.gd's _after_combo), so no perspective logic needed here.
# "Music" bus, not "SFX" — these are melodic stings like intro/crowd, not a
# gameplay feedback cue. A dedicated one-shot player: not _music (owns the
# continuous intro/crowd loop, would get clobbered mid-loop), not _tap_sfx
# (a much more frequent, unrelated trigger).
const WIN_SOUND: AudioStream = preload("res://assets/audio/music/win.mp3")
const LOSE_SOUND: AudioStream = preload("res://assets/audio/music/lose.mp3")
@export_range(-24.0, 24.0, 0.5) var result_sfx_volume_db := 5.0

var _result_sfx: AudioStreamPlayer = null


func _ready() -> void:
	_tap_sfx = AudioStreamPlayer.new()
	_tap_sfx.bus = &"SFX"
	add_child(_tap_sfx)
	get_tree().node_added.connect(_on_node_added)

	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.stream = INTRO_MUSIC
	# Mutate the loop flag through the PLAYER's stream (a plain var), not the
	# preloaded INTRO_MUSIC const directly — GDScript's static checker treats
	# a property write through a const reference as an error even though the
	# underlying Resource itself isn't actually immutable.
	if _music.stream is AudioStreamMP3:
		(_music.stream as AudioStreamMP3).loop = true
	_music.volume_db = music_volume_db
	add_child(_music)
	_music.play()

	_result_sfx = AudioStreamPlayer.new()
	_result_sfx.bus = &"Music"
	add_child(_result_sfx)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(_play_tap)


func _play_tap() -> void:
	_tap_sfx.stream = TAP_SOUND
	_tap_sfx.volume_db = tap_sfx_volume_db
	_tap_sfx.play()


func _fade_out_music() -> void:
	if _music == null or not _music.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -80.0, 0.4)
	tw.tween_callback(_music.stop)


func _play_result_sfx(stream: AudioStream) -> void:
	if _result_sfx == null or stream == null:
		return
	_result_sfx.stream = stream
	_result_sfx.volume_db = result_sfx_volume_db
	_result_sfx.play()
