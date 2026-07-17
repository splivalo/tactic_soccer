extends SceneTree

## Loads instructions_screen.tscn, jumps Page1->Page4, and grabs the settled
## end-state (properly frame-synced) to check for any lingering top-clip on
## Page4's title. Run WITHOUT --headless:
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_instructions_slide.gd
const OUT := "res://_slide_end.png"

var _screen: Control = null
var _start_ms := 0
var _pressed := false
var _saved := false


func _initialize() -> void:
	_screen = (load("res://scenes/ui/instructions_screen.tscn") as PackedScene).instantiate()
	get_root().add_child(_screen)


func _process(_delta: float) -> bool:
	if not _pressed:
		_pressed = true
		_start_ms = Time.get_ticks_msec()
		_screen._go_to_page(3, 1)
		return false
	if Time.get_ticks_msec() - _start_ms < 600 or _saved:
		return false
	_saved = true
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	quit()
	return true
