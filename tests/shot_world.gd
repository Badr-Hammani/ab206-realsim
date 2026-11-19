extends SceneTree
## Renders still pictures of the real map from fixed free-camera positions (needs a display, not --headless).
## Run: godot --path . --script res://tests/shot_world.gd -- --out=/tmp/shots [--preset=3]
## Views: GMMK from the south-west, the mine pits east of Khouribga, the plateau edge north.
var VIEWS := [
	["gmmk", Vector3(-1800, 1150, 1600), -40.0, -14.0],
	["mines", Vector3(12500, 1050, 13500), -55.0, -16.0],
	["mines_low", Vector3(14600, 760, 11600), -50.0, -8.0],
	["north_edge", Vector3(2000, 1100, -6000), 0.0, -8.0],
	["boundary", Vector3(6500, 1000, 3000), -90.0, -20.0],
]
func _initialize() -> void:
	var out := "/tmp/shots"
	var preset := 3
	var nohd := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--preset="):
			preset = int(a.substr(9))
		elif a == "--nohd":
			nohd = true
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "khouribga"
	root.add_child(main)
	for i in 10:
		await process_frame
	main.apply_preset(preset)
	if nohd and main.world.hd_ground:
		main.world.hd_ground.set_enabled(false)
	main.menu.visible = false
	main._set_paused(false)
	main.cam_rig.mode = 2
	if "--outer-red" in OS.get_cmdline_user_args():
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.8, 0.1, 0.1)
		main.world.terrain.outer_terrain.material.shader = null
		main.world.terrain.outer_terrain.set("material", red)
		for c in main.world.terrain.outer_terrain.chunks.values():
			c.material_override = red
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			VIEWS = VIEWS.filter(func(v: Array) -> bool: return v[0] == a.substr(7))
	for v in VIEWS:
		main.cam_rig.free_pos = v[1]
		main.cam_rig.free_yaw = deg_to_rad(v[2])
		main.cam_rig.free_pitch = deg_to_rad(v[3])
		for i in 150:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + "/" + v[0] + ".png")
		print("shot ", v[0])
	quit()
