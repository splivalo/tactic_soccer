extends SceneTree

## Renders the rigged player frozen at a kick's contact frame for a few clips,
## so we can eyeball that the mirrored pass is a clean left-footed kick (not a
## twisted pose). Own camera + light; windowed run.
const SCENE := "res://scenes/player_rigged.tscn"
const CLIPS := ["pass", "pass_mirror", "pass_soft2"]
const CONTACT := 0.64

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
	get_root().add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	get_root().add_child(env)

	_ap.play(CLIPS[0])
	_ap.seek(CONTACT, true)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("res://_pose_%s.png" % CLIPS[_ci])
	print("SAVED _pose_%s.png" % CLIPS[_ci])
	_ci += 1
	if _ci >= CLIPS.size():
		return true
	_ap.play(CLIPS[_ci])
	_ap.seek(CONTACT, true)
	_frames = 0
	return false
