extends SceneTree

## Headless builder. Takes the Mixamo FBX exports (all share ONE identical
## mixamorig skeleton + the SoccerpPlayer mesh/materials) and produces:
##   1. res://assets/animations/player_anims.res  — one AnimationLibrary with
##      every clip renamed to a clean key and given the right loop mode.
##   2. res://scenes/player_rigged.tscn — Idle.fbx's mesh+skeleton, an
##      AnimationPlayer holding that library, root motion on the hips so the
##      jog/strike don't drift the figure off its grid cell.
## Run: godot --headless --path <proj> --script res://scripts/tools/build_player.gd

const ANIM_DIR := "res://assets/animations/"
const LIB_PATH := "res://assets/animations/player_anims.res"
const SCENE_PATH := "res://scenes/player_rigged.tscn"
const BASE_FBX := "res://assets/animations/Idle.fbx"
const HIPS_TRACK := "Skeleton3D:mixamorig_Hips"

# filename (no ext) -> [clean_key, loop]
const CLIPS := {
	"Idle": ["idle", true],
	"Breathing Idle": ["idle_breath", true],
	"Jog Forward": ["jog", true],
	"Jog Forward Diagonal": ["jog_diag", true],
	"Soccer Pass": ["pass", false],
	"Strike Foward Jog": ["strike", false],
	"Goalkeeper Idle": ["gk_idle", true],
	"Goalkeeper Miss": ["gk_miss", false],
}


func _initialize() -> void:
	var lib := AnimationLibrary.new()
	for fname in CLIPS:
		var key: String = CLIPS[fname][0]
		var loop: bool = CLIPS[fname][1]
		var anim := _extract_anim(ANIM_DIR + fname + ".fbx")
		if anim == null:
			push_error("No animation in %s" % fname)
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		lib.add_animation(key, anim)
		print("  + %-12s <- %-22s len=%.3fs loop=%s" % [key, fname, anim.length, loop])
	var err := ResourceSaver.save(lib, LIB_PATH)
	print("Saved library %s (err=%d)" % [LIB_PATH, err])

	_build_scene(lib)
	quit()


func _extract_anim(path: String) -> Animation:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var anim: Animation = null
	var ap := _find_anim_player(inst)
	if ap != null:
		var names := ap.get_animation_list()
		if names.size() > 0:
			anim = ap.get_animation(names[0]).duplicate() as Animation
	inst.free()
	return anim


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _build_scene(lib: AnimationLibrary) -> void:
	var ps := load(BASE_FBX) as PackedScene
	var root := ps.instantiate()
	root.name = "Player"

	var ap := _find_anim_player(root)
	if ap == null:
		push_error("Base FBX has no AnimationPlayer")
		return
	# Replace the single baked clip with our full library.
	for existing in ap.get_animation_library_list():
		ap.remove_animation_library(existing)
	ap.add_animation_library("", lib)
	# Jog/strike translate the hips forward; treat that as root motion so the
	# mesh animates in place and OUR tween owns the figure's grid position.
	ap.root_motion_track = NodePath(HIPS_TRACK)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE

	# The PlayerRig controller drives this scene's animation set.
	root.set_script(load("res://scripts/game/player_rig.gd"))

	_own_all(root, root)
	var packed := PackedScene.new()
	var perr := packed.pack(root)
	var serr := ResourceSaver.save(packed, SCENE_PATH)
	print("Packed scene %s (pack=%d save=%d)" % [SCENE_PATH, perr, serr])
	root.free()


func _own_all(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		_own_all(c, owner)
