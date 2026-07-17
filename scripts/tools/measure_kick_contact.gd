extends SceneTree

## Measures the REAL foot-strike moment AND the real foot POSITION for "pass"
## and "strike", instead of assuming the ball meets a generic point (the cell
## center) at some guessed time. Plays each clip in real time (same pattern as
## foot_slide_check.gd — seek() outside the engine's per-frame update doesn't
## actually re-pose the skeleton) and samples the right toe bone's position
## every frame, reporting, at the instant of PEAK FORWARD SWING SPEED (the
## ball-strike instant — the foot is moving fastest as it drives through the
## ball, not yet at full stretch):
##   - the time (as a fraction of clip length)
##   - the toe's position in the character ROOT's local space (so main.gd can
##     rotate this by the kicker's facing and add it to the kicker's world
##     position to get the exact point the ball should be at on contact,
##     instead of the theoretical cell center).
const SCENE := "res://scenes/player_rigged.tscn"
const CLIPS := ["pass", "strike"]

var _rig: Node3D
var _ap: AnimationPlayer
var _sk: Skeleton3D
var _toe: int
var _hip: int
var _ci := 0
var _prev_rel: Vector3
var _have_prev := false
var _best_speed := -1.0
var _speed_t := 0.0
var _speed_toe_local: Vector3
var _best_reach := -INF
var _reach_t := 0.0
var _t0 := -1.0
var _frame := 0


func _initialize() -> void:
	_rig = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(_rig)
	_ap = _rig.find_children("*", "AnimationPlayer")[0]
	_sk = _rig.find_children("*", "Skeleton3D")[0]
	_toe = _sk.find_bone("mixamorig_RightToeBase")
	_hip = _sk.find_bone("mixamorig_Hips")
	_ap.root_motion_track = NodePath("Skeleton3D:mixamorig_Hips")  # same as kick()
	_begin()


func _begin() -> void:
	_have_prev = false
	_best_speed = -1.0
	_best_reach = -INF
	_t0 = -1.0
	_frame = 0
	_ap.play(CLIPS[_ci])
	_ap.speed_scale = 1.0


func _toe_local() -> Vector3:
	var toe_world: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(_toe).origin
	return _rig.global_transform.affine_inverse() * toe_world


func _process(delta: float) -> bool:
	_sk.force_update_all_bone_transforms()
	var toe_local := _toe_local()
	var rel: Vector3 = _sk.get_bone_global_pose(_toe).origin - _sk.get_bone_global_pose(_hip).origin
	var t: float = _ap.current_animation_position
	var length: float = _ap.get_animation(CLIPS[_ci]).length
	if _t0 < 0.0:
		_t0 = t
	_frame += 1
	# Skip the first few frames: play() snaps the pose from wherever it was
	# straight to the clip's start, which reads as a fake huge "speed" spike.
	if _have_prev and _frame > 5:
		if delta > 0.0:
			var speed: float = rel.distance_to(_prev_rel) / delta
			if speed > _best_speed:
				_best_speed = speed
				_speed_t = t
				_speed_toe_local = toe_local
		var reach: float = Vector2(rel.x, rel.z).length()
		if reach > _best_reach:
			_best_reach = reach
			_reach_t = t
	_prev_rel = rel
	_have_prev = true
	if t < _t0 or t >= length - 0.02:
		print("%s: length=%.3fs  contact at t=%.3fs (%.1f%%)  toe_local=%s  max-reach t=%.3fs (%.1f%%)"
			% [CLIPS[_ci], length, _speed_t, 100.0 * _speed_t / length, _speed_toe_local,
				_reach_t, 100.0 * _reach_t / length])
		_ci += 1
		if _ci >= CLIPS.size():
			quit()
			return true
		_begin()
	return false
