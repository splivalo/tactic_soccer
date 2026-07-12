extends SceneTree

## Measures the rigged player: model height (for player_scale) and the
## foot-contact moment in each kick clip (when the boot meets the ball -> when
## the ball should launch). Samples from _process so the node is really in the
## tree and the AnimationMixer actually applies poses.
const SCENE := "res://scenes/player_rigged.tscn"
const KICKS := ["pass", "strike"]

var _root: Node3D
var _ap: AnimationPlayer
var _sk: Skeleton3D
var _toe: int
var _ci := 0
var _phase := 0            # 0=measure height, 1=sampling kicks, 2=done
var _peak_reach := -INF
var _peak_t := 0.0
var _peak_speed := -INF
var _peak_speed_t := 0.0
var _prev := Vector3.ZERO
var _prev_t := -1.0
var _lines: Array[String] = []


func _initialize() -> void:
	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(_root)
	_ap = _root.find_children("*", "AnimationPlayer")[0]
	_sk = _root.find_children("*", "Skeleton3D")[0]
	_toe = _sk.find_bone("mixamorig_RightToeBase")
	_ap.active = true


func _toe_reach() -> Vector3:
	_sk.force_update_all_bone_transforms()
	return _sk.get_bone_global_pose(_toe).origin


func _process(_delta: float) -> bool:
	if _phase == 0:
		_ap.play("idle")
		_ap.seek(0.0, true)
		_sk.force_update_all_bone_transforms()
		var lo := INF
		var hi := -INF
		for b in _sk.get_bone_count():
			var y := _sk.get_bone_global_pose(b).origin.y
			lo = minf(lo, y); hi = maxf(hi, y)
		_lines.append("Anims: %s" % str(_ap.get_animation_list()))
		_lines.append("Height = %.3f m" % (hi - lo))
		_phase = 1
		_begin_clip()
		return false

	# phase 1: sample the active kick clip once per frame
	var clip: String = KICKS[_ci]
	var t := _ap.current_animation_position
	var p := _toe_reach()
	var reach := Vector2(p.x, p.z).length()
	if reach > _peak_reach:
		_peak_reach = reach; _peak_t = t
	if _prev_t >= 0.0 and t > _prev_t:
		var spd := (p - _prev).length() / (t - _prev_t)
		if spd > _peak_speed:
			_peak_speed = spd; _peak_speed_t = t
	_prev = p; _prev_t = t

	var dur := _ap.get_animation(clip).length
	if not _ap.is_playing() or t >= dur - 0.001:
		_lines.append("%-7s len=%.3f  contact(peak-reach) t=%.3f (%.0f%%)  peak-speed t=%.3f (%.0f%%)"
			% [clip, dur, _peak_t, 100.0 * _peak_t / dur, _peak_speed_t, 100.0 * _peak_speed_t / dur])
		_ci += 1
		if _ci >= KICKS.size():
			print("\n========== SUMMARY ==========")
			for l in _lines:
				print(l)
			return true
		_begin_clip()
	return false


func _begin_clip() -> void:
	_peak_reach = -INF; _peak_t = 0.0
	_peak_speed = -INF; _peak_speed_t = 0.0
	_prev_t = -1.0
	_ap.play(KICKS[_ci])
	_ap.seek(0.0, true)
