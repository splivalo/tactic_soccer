extends SceneTree

## Captures the match from the goal cinematic camera so we can eyeball the
## composition (side angle, height, background blur). Windowed run.
const OUT := "res://_shot_goalcam.png"

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		# Cut to the cinematic angle on the away goal (row 0).
		_main._activate_goal_cam(Vector2i(3, 0))
	if _frames < 40:
		return false
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ", img.get_size())
	return true
