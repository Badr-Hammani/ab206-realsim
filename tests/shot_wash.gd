extends SceneTree
## Picture of the rotor-wash dust (needs a display): helicopter on the pad, wash forced to full.
var main
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "khouribga"
	root.add_child(main)
	_go()
func _go() -> void:
	for i in 10:
		await process_frame
	main.apply_preset(2)
	main.menu.visible = false
	main._set_paused(false)
	var rw = main.rotor_wash
	rw.set_process(false)
	var hp: Vector3 = main.heli.global_position
	rw.global_position = Vector3(hp.x, main.world.terrain.height_at(hp.x, hp.z) + 0.3, hp.z)
	rw.ring.emitting = true
	rw.cloud.emitting = true
	main.cam_rig.mode = 2
	main.cam_rig.free_pos = hp + Vector3(-22, 7, 18)
	main.cam_rig.free_yaw = deg_to_rad(-50)
	main.cam_rig.free_pitch = deg_to_rad(-14)
	for i in 150:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("/tmp/claude-0/wash.png")
	print("WASH strength at hub 3 m, vi 9: ", rw.wash_strength(3.0, 9.0, 100.0), "  hub 15 m: ", rw.wash_strength(15.0, 9.0, 100.0), "  hub 30 m: ", rw.wash_strength(30.0, 9.0, 100.0))
	quit()
