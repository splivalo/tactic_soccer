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


## Short haptic buzz, gated on the user's preference. Nothing calls this yet
## (no goal/card haptics wired up) — ready for whenever that's added.
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
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	vibration_enabled = cfg.get_value("audio", "vibration_enabled", vibration_enabled)
