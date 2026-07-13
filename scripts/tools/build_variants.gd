extends SceneTree

## Derives pass VARIANTS from the single Soccer Pass clip so a team doesn't play
## one identical motion, WITHOUT any new Mixamo animation:
##   * dampened swings  (rotations slerped toward rest -> gentler, softer poses)
##   * mirrored L/R foot (reflect each bone's rotation across the sagittal plane)
## Then repacks player_rigged.tscn (library is embedded) with the enlarged set.
##
## Mirror correctness is gated: mirroring the ~symmetric idle must return ~idle,
## else the mirror is discarded and we ship only the dampened variants.
## Run: godot --headless --path <proj> --script res://scripts/tools/build_variants.gd

const LIB_PATH := "res://assets/animations/player_anims.res"
const SCENE_PATH := "res://scenes/player_rigged.tscn"
const BASE_FBX := "res://assets/animations/Idle.fbx"
const HIPS_TRACK := "Skeleton3D:mixamorig_Hips"
const SAMPLE_DT := 1.0 / 30.0

var _sk: Skeleton3D
# bone name -> {idx, parent, rest_local_rot (Quaternion), rest_global_rot (Quaternion), mirror (name)}
var _bones := {}


func _initialize() -> void:
	var base := (load(BASE_FBX) as PackedScene).instantiate()
	_sk = _find(base, "Skeleton3D")
	_index_bones()

	var lib := load(LIB_PATH) as AnimationLibrary
	var pass_anim := lib.get_animation("pass")

	# Right-foot swing-strength ladder: gentle tap (heavily damped) -> full swing.
	var pass_soft := _dampen(pass_anim, 0.72)
	var pass_soft2 := _dampen(pass_anim, 0.5)
	lib.add_animation("pass_soft", pass_soft)     # medium
	lib.add_animation("pass_soft2", pass_soft2)   # gentlest
	print("added strength ladder: pass_soft2 (0.5), pass_soft (0.72), pass (1.0)")

	# Left-foot (mirrored) counterparts of the whole ladder + the shot, gated on
	# the idle-symmetry self-check.
	var idle_err := _mirror_symmetry_error(lib.get_animation("idle"))
	print("mirror self-check (mirror(idle) vs idle): mean=%.1f deg" % idle_err)
	if idle_err < 14.0:
		lib.add_animation("pass_L", _mirror(pass_anim))
		lib.add_animation("pass_soft_L", _mirror(pass_soft))
		lib.add_animation("pass_soft2_L", _mirror(pass_soft2))
		lib.add_animation("strike_L", _mirror(lib.get_animation("strike")))
		print("added left-foot mirrors: pass_L, pass_soft_L, pass_soft2_L, strike_L")
	else:
		print("mirror REJECTED (self-check too high) — right foot only")

	ResourceSaver.save(lib, LIB_PATH)
	_repack_scene(base, lib)
	print("variants in library: ", lib.get_animation_list())
	base.free()
	quit()


# --- bone table --------------------------------------------------------------
func _index_bones() -> void:
	for i in _sk.get_bone_count():
		var n := _sk.get_bone_name(i)
		var mirror := n
		if n.contains("Left"):
			mirror = n.replace("Left", "Right")
		elif n.contains("Right"):
			mirror = n.replace("Right", "Left")
		_bones[n] = {
			"idx": i,
			"parent": _sk.get_bone_parent(i),
			"rest_local": _sk.get_bone_rest(i).basis.get_rotation_quaternion(),
			"rest_global": _sk.get_bone_global_rest(i).basis.get_rotation_quaternion(),
			"mirror": mirror,
		}


func _bone_of_track(anim: Animation, t: int) -> String:
	var p := String(anim.track_get_path(t))
	return p.substr(p.find(":") + 1)


# --- dampen: slerp every keyed rotation toward the bone's rest pose -----------
func _dampen(src: Animation, factor: float) -> Animation:
	var a := src.duplicate(true) as Animation
	for t in a.get_track_count():
		var bone := _bone_of_track(a, t)
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and _bones.has(bone):
			var rest: Quaternion = _bones[bone]["rest_local"]
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, rest.slerp(q, factor))
	return a


# --- mirror: reflect the animation across the sagittal (X=0) plane ------------
# Reflection of a rotation across the X-normal plane: (x,y,z,w) -> (x,-y,-z,w).
func _mirror_quat(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)


# Local animated rotation of a bone at time t (its pose rotation, or rest).
func _local_rot(anim: Animation, rot_track: Dictionary, bone: String, t: float) -> Quaternion:
	if rot_track.has(bone):
		return anim.rotation_track_interpolate(rot_track[bone], t)
	return _bones[bone]["rest_local"]


# Computes, for every bone at time t, the MIRRORED local pose rotation.
func _mirrored_locals(anim: Animation, rot_track: Dictionary, t: float) -> Dictionary:
	# 1) original global rotations via FK down the hierarchy.
	var gorig := {}
	# 2) mirrored global rotations.
	var gmir := {}
	var lmir := {}
	# bones are ordered parents-first in the skeleton.
	for i in _sk.get_bone_count():
		var bone := _sk.get_bone_name(i)
		var parent_idx: int = _bones[bone]["parent"]
		var parent_name := _sk.get_bone_name(parent_idx) if parent_idx >= 0 else ""
		var local := _local_rot(anim, rot_track, bone, t)
		var g_parent: Quaternion = gorig[parent_name] if parent_idx >= 0 else Quaternion.IDENTITY
		gorig[bone] = g_parent * local

		# mirror uses the L/R counterpart's delta-from-rest.
		var src: String = _bones[bone]["mirror"]
		var d_src: Quaternion = gorig[src] * _bones[src]["rest_global"].inverse() if gorig.has(src) else _delta(anim, rot_track, src, t)
		var dmir := _mirror_quat(d_src)
		gmir[bone] = dmir * _bones[bone]["rest_global"]
		var gm_parent: Quaternion = gmir[parent_name] if parent_idx >= 0 else Quaternion.IDENTITY
		lmir[bone] = gm_parent.inverse() * gmir[bone]
	return lmir


# Global delta-from-rest for a bone (used when its mirror counterpart comes
# later in the hierarchy and isn't in gorig yet — recompute its FK chain).
func _delta(anim: Animation, rot_track: Dictionary, bone: String, t: float) -> Quaternion:
	var g := Quaternion.IDENTITY
	var chain: Array[String] = []
	var b := bone
	while b != "":
		chain.push_front(b)
		var pidx: int = _bones[b]["parent"]
		b = _sk.get_bone_name(pidx) if pidx >= 0 else ""
	for name in chain:
		g = g * _local_rot(anim, rot_track, name, t)
	return g * _bones[bone]["rest_global"].inverse()


func _mirror(src: Animation) -> Animation:
	var rot_track := {}
	var hip_pos := -1
	for t in src.get_track_count():
		var bone := _bone_of_track(src, t)
		if src.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_track[bone] = t
		elif src.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "mixamorig_Hips":
			hip_pos = t

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_NONE
	# One rotation track per originally-keyed bone.
	var out_track := {}
	for bone in rot_track:
		var idx := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(idx, NodePath("Skeleton3D:" + bone))
		out_track[bone] = idx
	var out_hip := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(out_hip, NodePath(HIPS_TRACK))

	var t := 0.0
	while t <= src.length + 0.0001:
		var lmir := _mirrored_locals(src, rot_track, t)
		for bone in out_track:
			out.rotation_track_insert_key(out_track[bone], t, lmir[bone])
		var hp := src.position_track_interpolate(hip_pos, t) if hip_pos >= 0 else _sk.get_bone_rest(_bones["mixamorig_Hips"]["idx"]).origin
		out.position_track_insert_key(out_hip, t, Vector3(-hp.x, hp.y, hp.z))
		t += SAMPLE_DT
	return out


# Mean per-bone angle (deg) between mirror(idle) and idle — small = correct mirror.
func _mirror_symmetry_error(idle: Animation) -> float:
	var rot_track := {}
	for t in idle.get_track_count():
		if idle.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_track[_bone_of_track(idle, t)] = t
	var total := 0.0
	var count := 0
	var t := 0.0
	while t <= idle.length + 0.0001:
		var lmir := _mirrored_locals(idle, rot_track, t)
		for bone in rot_track:
			var orig: Quaternion = idle.rotation_track_interpolate(rot_track[bone], t)
			var ang := rad_to_deg(orig.angle_to(lmir[bone]))
			total += ang
			count += 1
		t += 0.1
	return total / maxf(count, 1)


# --- repack the rigged scene with the enlarged library -----------------------
func _repack_scene(base: Node, lib: AnimationLibrary) -> void:
	var root := (load(BASE_FBX) as PackedScene).instantiate()
	root.name = "Player"
	var ap: AnimationPlayer = _find(root, "AnimationPlayer")
	for existing in ap.get_animation_library_list():
		ap.remove_animation_library(existing)
	ap.add_animation_library("", lib)
	ap.root_motion_track = NodePath(HIPS_TRACK)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	root.set_script(load("res://scripts/game/player_rig.gd"))
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, SCENE_PATH)
	root.free()


func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
