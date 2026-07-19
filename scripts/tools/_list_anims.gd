extends SceneTree

func _initialize() -> void:
	var lib := load("res://assets/animations/player_anims.res") as AnimationLibrary
	if lib == null:
		print("FAILED TO LOAD")
		quit(1)
		return
	var names := lib.get_animation_list()
	names.sort()
	for n in names:
		print("ANIM: %s" % n)
	print("TOTAL: %d" % names.size())
	quit()
