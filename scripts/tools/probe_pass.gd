extends SceneTree

## Probes the 'pass' clip: are its tracks directly key-editable (not compressed),
## what types/paths, and do Left/Right bone counterparts exist? Decides how we
## build dampened + mirrored variants.
const LIB := "res://assets/animations/player_anims.res"

func _initialize() -> void:
	var lib := load(LIB) as AnimationLibrary
	var anim := lib.get_animation("pass")
	print("pass length=%.3f tracks=%d" % [anim.length, anim.get_track_count()])
	var pos := 0
	var rot := 0
	var other := 0
	var sample_ok := false
	for t in anim.get_track_count():
		var ty := anim.track_get_type(t)
		if ty == Animation.TYPE_POSITION_3D:
			pos += 1
		elif ty == Animation.TYPE_ROTATION_3D:
			rot += 1
		else:
			other += 1
	# Try reading + writing a rotation key on the first rotation track.
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var kc := anim.track_get_key_count(t)
			if kc > 0:
				var v = anim.track_get_key_value(t, 0)
				print("first rot track path=", anim.track_get_path(t), " keys=", kc, " key0=", v)
				sample_ok = true
			break
	print("pos_tracks=%d rot_tracks=%d other=%d  key-editable=%s" % [pos, rot, other, sample_ok])
	# Left/Right bone name check from the track paths.
	var names := {}
	for t in anim.get_track_count():
		var p := String(anim.track_get_path(t))
		var bone := p.substr(p.find(":") + 1)
		names[bone] = true
	var pairs := 0
	for b in names:
		if b.contains("Left"):
			var r: String = b.replace("Left", "Right")
			if names.has(r):
				pairs += 1
	print("bones=%d  Left/Right pairs=%d  sample bones=%s" % [names.size(), pairs, str(names.keys()).substr(0, 200)])
	quit()
