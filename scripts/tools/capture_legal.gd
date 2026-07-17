extends SceneTree

## Loads legal_screen.tscn directly, waits a few frames, grabs one rendered
## frame to a PNG, and quits. Run WITHOUT --headless (needs a real GPU frame):
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_legal.gd
const OUT := "res://_legal_test.png"

var _frames := 0


func _initialize() -> void:
	var screen := (load("res://scenes/ui/legal_screen.tscn") as PackedScene).instantiate()
	get_root().add_child(screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ", img.get_size())
	return true
