extends SceneTree
## One-off generator for the gold-pill button textures used by my_theme_gold.tres
## (Button/styles/normal|hover|pressed|disabled — StyleBoxTexture).
## Bakes a rounded rect with a real vertical gradient + a thin all-round rim
## + a thicker solid border band along the bottom edge (StyleBoxFlat can't
## do gradients; a baked texture can).
##
## SIZE is deliberately small relative to TEXTURE_MARGIN (see my_theme_gold.tres,
## texture_margin_* = 40): with a 9-slice, only the fixed top/bottom margin
## bands are shown 1:1 — the middle stretches. Keeping SIZE close to
## 2*TEXTURE_MARGIN means the visible top/bottom bands cover MOST of the
## gradient's dynamic range, so the stretched middle (which is a narrow,
## low-contrast slice) doesn't visually dilute/wash out the gradient on a
## tall button. (First version used SIZE=128, which let the flat-looking
## middle third dominate on real button sizes — this fixes that.)
##
## Rerun after tweaking the constants below:
##   godot --headless -s res://scripts/tools/gen_button_textures.gd
## Then re-import (--headless --editor --quit-after 15) so Godot picks up
## the new PNGs before the theme references them.

const SIZE := 100
const CORNER_RADIUS := 36.0
const RIM_WIDTH := 4.0  ## thin border all the way around

func _sdf_rounded_box(p: Vector2, half_size: Vector2, r: float) -> float:
	var q: Vector2 = p.abs() - half_size + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


func _make_texture(path: String, top_color: Color, bottom_color: Color, rim_color: Color, bottom_border_color: Color, bottom_border_height: float) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := Vector2(SIZE / 2.0, SIZE / 2.0)
	for y in range(SIZE):
		var t := float(y) / float(SIZE - 1)
		var base_col := top_color.lerp(bottom_color, smoothstep(0.0, 1.0, t))
		var in_bottom_border := float(SIZE - y) <= bottom_border_height
		for x in range(SIZE):
			var p := Vector2(x + 0.5, y + 0.5) - half
			var d := _sdf_rounded_box(p, half, CORNER_RADIUS)
			var col := base_col
			if in_bottom_border:
				col = bottom_border_color
			elif d > -RIM_WIDTH:
				col = rim_color
			col.a = clampf(0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, col)
	var err := img.save_png(path)
	print(path, " -> ", err)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/textures/ui")

	# top, bottom, thin rim (all sides), thick bottom band, bottom band height
	_make_texture("res://assets/textures/ui/button_normal.png",
		Color(1.0, 0.95, 0.6), Color(0.82, 0.52, 0.06),
		Color(0.32, 0.14, 0.04), Color(0.5, 0.24, 0.05), 16.0)
	_make_texture("res://assets/textures/ui/button_hover.png",
		Color(1.0, 0.98, 0.75), Color(0.95, 0.62, 0.1),
		Color(0.36, 0.17, 0.05), Color(0.56, 0.29, 0.06), 16.0)
	_make_texture("res://assets/textures/ui/button_pressed.png",
		Color(0.78, 0.5, 0.08), Color(0.66, 0.4, 0.05),
		Color(0.24, 0.1, 0.03), Color(0.38, 0.17, 0.03), 8.0)
	_make_texture("res://assets/textures/ui/button_disabled.png",
		Color(0.68, 0.65, 0.57), Color(0.5, 0.47, 0.4),
		Color(0.28, 0.26, 0.22), Color(0.32, 0.29, 0.24), 16.0)

	print("button textures generated")
	quit()
