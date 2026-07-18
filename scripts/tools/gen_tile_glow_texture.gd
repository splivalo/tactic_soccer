extends SceneTree

## One-off: bakes the rounded-square PNG used by the "own team" ground tile
## glow (OwnTeamTileGlow, see add_player_tile_glow.gd) — the EXACT SAME
## superellipse shape as BoardFx's own tap/move/shoot tile glow
## (scripts/visuals/board_fx.gd _make_tile_tex), so the two visually read as
## the same shape family and the marker sits naturally under those tiles when
## both land on one cell.
## Run: godot --headless -s res://scripts/tools/gen_tile_glow_texture.gd --path <project>
## Then import once: godot --headless --editor --quit --path <project>

const TEX_PATH := "res://assets/textures/effects/player_tile_glow.png"
const TEX_SIZE := 64


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/textures/effects")
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var u := (float(x) + 0.5) / TEX_SIZE * 2.0 - 1.0
			var v := (float(y) + 0.5) / TEX_SIZE * 2.0 - 1.0
			# rounded-square distance (p=4 superellipse) — identical formula to
			# BoardFx._make_tile_tex, for a matching shape.
			var d := pow(pow(absf(u), 4.0) + pow(absf(v), 4.0), 0.25)
			var fill := 1.0 - smoothstep(0.72, 1.0, d)
			var border := smoothstep(0.6, 0.8, d) * (1.0 - smoothstep(0.82, 0.98, d))
			var a := clampf(fill * 0.45 + border, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var err := img.save_png(TEX_PATH)
	print("saved ", TEX_PATH, " -> ", err)
	quit(0)
