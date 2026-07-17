@tool
extends EditorScript
## Regenerates assets/textures/ui/slider_grabber.png (the HSlider handle —
## wired in my_theme.tres under HSlider/icons/grabber).
##
## TO TUNE IT YOURSELF: change FINAL_SIZE (and/or the colors/ring thickness)
## below, then in Godot's Script editor: File -> Run (or Ctrl+Shift+X) with
## this script open. No command line needed — the .png updates in place and
## every slider using it picks up the change immediately.

const FINAL_SIZE := 38       # <- the knob to turn if it's too small/big (was 30, then 44)
const RING_THICKNESS := 0.12 # dark ring width, as a fraction of the radius
const GOLD := Color(0.97, 0.76, 0.15, 1)
const DARK_RING := Color(0.05, 0.1, 0.06, 1)
const SUPERSAMPLE := 4       # renders bigger then shrinks, for a smooth (not jagged) edge


func _run() -> void:
	var size := FINAL_SIZE * SUPERSAMPLE
	var center := size / 2.0
	var outer_r := size * 0.46
	var inner_r := outer_r * (1.0 - RING_THICKNESS)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(center, center))
			var c := Color(0, 0, 0, 0)
			if d <= inner_r:
				c = GOLD
			elif d <= outer_r:
				c = DARK_RING
			img.set_pixel(x, y, c)
	img.resize(FINAL_SIZE, FINAL_SIZE, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://assets/textures/ui/slider_grabber.png")
	print("slider_grabber.png regenerated at %dx%d" % [FINAL_SIZE, FINAL_SIZE])
