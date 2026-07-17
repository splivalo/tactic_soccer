extends SceneTree

## Loads lose_screen.tscn directly with sample GameFlow data (as if the
## viewing player is HomeTeam/Croatia and AwayTeam/Brazil just won 2:1), grabs
## one frame. Run WITHOUT --headless:
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_lose_screen.gd
const OUT := "res://_lose_test.png"

var _frames := 0


func _initialize() -> void:
	var gf := get_root().get_node("GameFlow")
	gf.home_country = "Croatia"
	gf.away_country = "Brazil"
	gf.player_side = "HomeTeam"
	gf.last_winner = "AwayTeam"
	gf.last_score = {"HomeTeam": 1, "AwayTeam": 2}
	var screen := (load("res://scenes/ui/lose_screen.tscn") as PackedScene).instantiate()
	get_root().add_child(screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	return true
