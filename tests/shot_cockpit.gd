extends SceneTree
## Pictures of the M2.30 cockpit panels (needs a display): the instrument panel alone and the
## overhead circuit-breaker console. Run: godot --path . --script res://tests/shot_cockpit.gd -- --out=/tmp/shots
func _initialize() -> void:
	var out := "/tmp/shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "valle"
	root.add_child(main)
	for i in 20:
		await process_frame
	main.reset_cold_dark(true)
	main.systems.battery = true
	main.systems.pull_breaker("IGN ENG")
	for i in 30:
		await process_frame
	main.overhead.open()
	main._set_paused(false)
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/overhead.png")
	main.overhead.close()
	main.reset_on_pad()
	for i in 60:
		await process_frame
	var cl := CanvasLayer.new()
	cl.layer = 50
	root.add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.size = Vector2(1100, 500)
	cl.add_child(bg)
	var p = load("res://scripts/ui/instrument_panel.gd").new()
	p.position = Vector2(20, 20)
	cl.add_child(p)
	for i in 30:
		p.v = main.panel3d.v
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/panel.png")
	quit(0)
