extends SceneTree

## Proves the idle foot-slide fix: measures how far the right toe drifts
## horizontally across a full idle loop with root motion OFF (new, feet planted)
## vs the hips treated as root motion ON (old, feet skate). Smaller = planted.
const SCENE := "res://scenes/player_rigged.tscn"
const CLIPS := ["idle_breath", "gk_idle"]

var _ap: AnimationPlayer
var _sk: Skeleton3D
var _toe: int
var _ci := 0
var _rm := false          # current root-motion setting under test
var _lo := Vector2(INF, INF)
var _hi := Vector2(-INF, -INF)
var _t0 := -1.0
var _lines: Array[String] = []


func _initialize() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	_ap = root.find_children("*", "AnimationPlayer")[0]
	_sk = root.find_children("*", "Skeleton3D")[0]
	_toe = _sk.find_bone("mixamorig_RightToeBase")
	_ap.active = true
	_begin()


func _begin() -> void:
	_lo = Vector2(INF, INF)
	_hi = Vector2(-INF, -INF)
	_t0 = -1.0
	_ap.root_motion_track = NodePath("Skeleton3D:mixamorig_Hips") if _rm else NodePath("")
	_ap.play(CLIPS[_ci])
	_ap.seek(0.0, true)


func _process(_delta: float) -> bool:
	_sk.force_update_all_bone_transforms()
	var p := _sk.get_bone_global_pose(_toe).origin
	var xz := Vector2(p.x, p.z)
	_lo = _lo.min(xz)
	_hi = _hi.max(xz)
	var t := _ap.current_animation_position
	if _t0 < 0.0:
		_t0 = t
	# one full loop of this clip captured?
	if t < _t0 or (t >= _ap.get_animation(CLIPS[_ci]).length - 0.02):
		var span := (_hi - _lo)
		_lines.append("%-11s root_motion=%-3s  toe XZ drift = %.3f x %.3f m"
			% [CLIPS[_ci], "ON" if _rm else "off", span.x, span.y])
		# advance: off then on for each clip
		if not _rm:
			_rm = true
		else:
			_rm = false
			_ci += 1
		if _ci >= CLIPS.size():
			print("\n===== FOOT-SLIDE CHECK (smaller = feet planted) =====")
			for l in _lines:
				print(l)
			return true
		_begin()
	return false
