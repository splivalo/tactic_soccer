extends SceneTree

## Loads the match scene, lets it settle a few frames so players are mid-idle
## (not bind pose), grabs one rendered frame to a PNG, and quits. Run WITHOUT
## --headless (needs a real GPU frame):
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_shot.gd
const OUT := "res://_shot_test.png"

var _frames := 0


func _initialize() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 45:
		return false
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ", img.get_size())
	return true
