extends SceneTree
## Pictures of the photo-detected buildings and trees (needs a display; HD tiles from a local server:
## python3 tests/tile_server.py 8765 <copy of hd_cache>). Run with -- --hd-url=http://127.0.0.1:8765/tile.jpg?%d/%d/%d --out=DIR
var VIEWS := [
	["dense_oblique", Vector2(2700, -3300), 140.0, -60.0, -28.0],
	["dense_low", Vector2(2850, -3450), 45.0, -80.0, -14.0],
	["garden_low", Vector2(3550, -1450), 60.0, -45.0, -20.0],
	["city_high", Vector2(2000, -1200), 450.0, -50.0, -22.0],
]
func _initialize() -> void:
	var out := "/tmp/shots"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "khouribga"
	root.add_child(main)
	for i in 10:
		await process_frame
	main.apply_preset(3)
	main.menu.visible = false
	main.hud.visible = false
	main._set_paused(false)
	main.cam_rig.mode = 2
	main.instructor.message = ""
	for v in VIEWS:
		if only != "" and not (v[0] in only.split(",")):
			continue
		var p: Vector2 = v[1]
		var gy: float = main.world.terrain._grid_height(p.x, p.y)
		main.cam_rig.free_pos = Vector3(p.x, gy + float(v[2]), p.y)
		main.cam_rig.free_yaw = deg_to_rad(v[3])
		main.cam_rig.free_pitch = deg_to_rad(v[4])
		for i in int(OS.get_environment("SHOT_FRAMES") if OS.get_environment("SHOT_FRAMES") != "" else "260"):
			await process_frame
		root.get_viewport().get_texture().get_image().save_jpg(out + "/" + v[0] + ".jpg", 0.9)
		print("shot ", v[0], " hd ", main.world.hd_ground.describe())
	quit()
