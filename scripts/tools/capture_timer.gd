extends SceneTree

## Loads main.tscn, waits ~4s of REAL wall-clock time (the engine here runs
## uncapped, so counting frames instead would pass in well under a second),
## grabs one rendered frame to a PNG so the HUD countdown label can be checked
## visually. Run WITHOUT --headless:
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_timer.gd
const OUT := "res://_timer_test.png"

var _start_ms := 0


func _initialize() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _start_ms < 10500:
		return false
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ", img.get_size())
	return true
