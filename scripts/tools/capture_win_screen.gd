extends SceneTree

## Loads win_screen.tscn directly with sample GameFlow data (as if HomeTeam
## just beat AwayTeam 2:1 in a Croatia vs Brazil match), grabs one frame while
## confetti is still falling and one after it should have faded out. Run
## WITHOUT --headless:
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_win_screen.gd
const OUT_BURST := "res://_win_burst.png"
const OUT_SETTLED := "res://_win_settled.png"

var _start_ms := 0
var _burst_saved := false
var _settled_saved := false


func _initialize() -> void:
	var gf := get_root().get_node("GameFlow")
	gf.home_country = "Croatia"
	gf.away_country = "Brazil"
	gf.last_winner = "HomeTeam"
	gf.last_score = {"HomeTeam": 2, "AwayTeam": 1}
	var screen := (load("res://scenes/ui/win_screen.tscn") as PackedScene).instantiate()
	get_root().add_child(screen)
	_start_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var elapsed := Time.get_ticks_msec() - _start_ms
	if elapsed > 600 and not _burst_saved:
		_burst_saved = true
		get_root().get_texture().get_image().save_png(OUT_BURST)
		print("SAVED ", OUT_BURST)
		return false
	if elapsed > 3500 and not _settled_saved:
		_settled_saved = true
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(OUT_SETTLED)
		print("SAVED ", OUT_SETTLED)
		quit()
		return true
	return false
