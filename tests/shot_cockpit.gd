extends SceneTree
## Pictures of the M2.30 cockpit (needs a display): the 3D cockpit view, the instrument panel alone,
## the overhead console looked at from the seat and the O breaker panel.
## Run: godot --path . --script res://tests/shot_cockpit.gd -- --out=/tmp/shots
func _snap(path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)

func _initialize() -> void:
	var out := "/tmp/shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "valle"
	root.add_child(main)
	for i in 30:
		await process_frame
	main.reset_on_pad()
	main.hud.visible = false
	for i in 60:
		await process_frame
	await _snap(out + "/cockpit.png")
	main.systems.caution_test = true
	await _snap(out + "/cockpit_test.png")
	main.systems.caution_test = false
	# click the red FUEL VALVE handle where it appears on screen (cursor mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var q: MeshInstance3D = main.heli.panel_quad
	var lp := Vector3((856.0 / 1000.0 - 0.5) * 0.92, (0.5 - 555.0 / 620.0) * 0.57, 0.0)
	var sp: Vector2 = main.cam_rig.cam.unproject_position(q.global_transform * lp)
	var before: bool = main.systems.fuel_valve
	var ok: bool = main._click_panel(sp)
	print("FUEL HANDLE CLICK at %s: hit %s, valve %s -> %s" % [sp, ok, before, main.systems.fuel_valve])
	await _snap(out + "/fuel_off.png")
	main.systems.pull_breaker("IGN ENG")
	main.cam_rig.look_pitch = 60.0
	await _snap(out + "/overhead3d.png")
	main.cam_rig.look_pitch = main.cam_rig.DEFAULT_PITCH
	main.overhead.open()
	await _snap(out + "/overhead.png")
	main.overhead.close()
	var cl := CanvasLayer.new()
	cl.layer = 50
	root.add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.size = Vector2(1100, 700)
	cl.add_child(bg)
	var p = load("res://scripts/ui/instrument_panel.gd").new()
	p.position = Vector2(20, 20)
	cl.add_child(p)
	for i in 20:
		p.v = main.panel3d.v
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/panel.png")
	quit(0)
