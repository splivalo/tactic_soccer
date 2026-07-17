extends SceneTree

## Calls _begin_goal_drama directly on the default-spawned match, then grabs a
## rendered frame so the decluttered goal-cam composition can be eyeballed.
## Run WITHOUT --headless:
##   godot --path <proj> --resolution 720x1280 --script res://scripts/tools/capture_goal_declutter.gd
const OUT := "res://_goal_declutter.png"

var _main: Node
var _frames := 0
var _fired := false


func _initialize() -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10 and not _fired:
		_fired = true
		var shooter_cell: Vector2i = Vector2i(-1, -1)
		for cell in _main._node_at:
			if _main._state.team_of(cell) == "HomeTeam":
				shooter_cell = cell
				break
		_main._begin_goal_drama(Vector2i(3, 0), "HomeTeam", shooter_cell)
		return false
	if _frames < 20:
		return false
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT, " ", img.get_size())
	return true
