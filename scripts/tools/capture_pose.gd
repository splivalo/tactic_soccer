extends SceneTree

## Renders the 'pass' clip at the windup-skip start (0.42) through contact (~0.55)
## so we can confirm the kick begins as a natural leg-coming-through, not a snap.
const SCENE := "res://scenes/player_rigged.tscn"
const TIMES := [0.42, 0.49, 0.56]

var _ap: AnimationPlayer
var _frames := 0
var _ci := 0


func _initialize() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	_ap = root.find_children("*", "AnimationPlayer")[0]

	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.look_at_from_position(Vector3(2.2, 1.4, 3.0), Vector3(0, 0.9, 0), Vector3.UP)
	cam.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.5
	get_root().add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.25)
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	e.ambient_light_energy = 1.0
	env.environment = e
	get_root().add_child(env)

	_ap.play("pass")
	_ap.seek(TIMES[0], true)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("res://_pose_t%d.png" % int(TIMES[_ci] * 100))
	print("SAVED t=%.2f" % TIMES[_ci])
	_ci += 1
	if _ci >= TIMES.size():
		return true
	_ap.play("pass")
	_ap.seek(TIMES[_ci], true)
	_frames = 0
	return false
