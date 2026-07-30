extends Node
## Autoload. Persists + applies user audio/haptics preferences (Settings
## modal, opened from the main menu). Volumes are linear 0..1 sliders mapped
## onto the "Music"/"SFX" audio buses (see assets/audio/bus_layout.tres) —
## works immediately even before any actual music/SFX assets exist, since
## anything that later plays through those buses is affected automatically.

const SAVE_PATH := "user://settings.cfg"

var music_volume := 1.0
var sfx_volume := 1.0
var vibration_enabled := true

## Display name shown to online opponents. Lives here (device-local) rather than
## only on the server so a player who loses their anonymous account — Firebase
## deletes those after 30 days of inactivity, see GAME_DESIGN.md §11 — comes
## back with their name intact and never has to type it again.
var player_name := ""

## Country played online. Chosen ahead of time and reused, so a match starts the
## instant an invite is accepted instead of making both players sit through a
## "waiting for opponent to choose" screen (GAME_DESIGN.md §11). Empty = never
## picked; the online screen asks for one. Offline modes ignore this and keep
## choosing per match in team_select.
var player_country := ""


func _ready() -> void:
	_load()
	_apply_audio()


func set_music_volume(v: float) -> void:
	music_volume = v
	_apply_audio()
	_save()


func set_sfx_volume(v: float) -> void:
	sfx_volume = v
	_apply_audio()
	_save()


func set_vibration_enabled(on: bool) -> void:
	vibration_enabled = on
	_save()


## Trimmed and length-capped to match database.rules.json (2..16 chars) — a name
## the rules would reject must never reach the server, or the player just sees a
## failed write with no idea why.
func set_player_name(value: String) -> void:
	player_name = sanitize_name(value).left(16)
	_save()


func has_valid_player_name() -> bool:
	return player_name.length() >= 2


func set_player_country(value: String) -> void:
	player_country = value
	_save()


## Strips line breaks and control characters out of a display name.
##
## Not paranoia: online, this text is typed by a STRANGER and ends up in the
## other player's HUD mid-match. Truncating to a few characters fixes width but
## does nothing about a newline, which breaks the layout regardless of length.
## Applied both when a player sets their own name and before showing someone
## else's.
static func sanitize_name(value: String) -> String:
	var out := ""
	for c in value:
		# Everything below space is a control character (newline, tab, NUL...);
		# 0x7F is DEL.
		var code := c.unicode_at(0)
		if code >= 32 and code != 0x7F:
			out += c
	return out.strip_edges()


## Short haptic buzz, gated on the user's preference. Called from main.gd
## alongside the same moments that already play the whistle/goal SFX (goal,
## offside, yellow/red card) — see there for the actual durations used.
func vibrate(duration_ms: int = 40) -> void:
	if vibration_enabled:
		Input.vibrate_handheld(duration_ms)


func _apply_audio() -> void:
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "vibration_enabled", vibration_enabled)
	cfg.set_value("online", "player_name", player_name)
	cfg.set_value("online", "player_country", player_country)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	vibration_enabled = cfg.get_value("audio", "vibration_enabled", vibration_enabled)
	player_name = cfg.get_value("online", "player_name", player_name)
	player_country = cfg.get_value("online", "player_country", player_country)
