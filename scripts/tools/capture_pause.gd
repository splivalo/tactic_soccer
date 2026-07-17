extends SceneTree

## Loads main.tscn, waits for it to settle, simulates pressing the HUD pause
## button, waits a frame, grabs one rendered frame to a PNG, and quits.
## Run WITHOUT --headless:
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_pause.gd
const OUT := "res://_pause_test.png"

var _main: Node = null
var _frames := 0
var _pressed := false


func _initialize() -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30 and not _pressed:
		_pressed = true
		var hud := _main.get_node("HUD/Hud")
		var btn: Button = hud.get_node("%PauseButton")
		btn.pressed.emit()
		return false
	if _frames < 40:
		return false
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ", img.get_size())
	return true
