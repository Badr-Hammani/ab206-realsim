extends SceneTree
## Stress test for the moving map with real rendering (needs a display, not --headless):
## Ultra preset, opens and closes the big map 12 times, zooms from 80 m/px to 0.25 m/px and back,
## pans across the city, GMMK and the mines, and prints memory. Fails if memory keeps climbing.
## Run: godot --path . --script res://tests/map_stress.gd
var main
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "khouribga"
	root.add_child(main)
	_go()

func _mem() -> String:
	return "RAM %d MB, video %d MB" % [OS.get_static_memory_usage() / 1048576, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576]

func _go() -> void:
	for i in 10:
		await process_frame
	main.apply_preset(3)
	main.menu.visible = false
	main._set_paused(false)
	for i in 30:
		await process_frame
	print("start: ", _mem())
	var nm = main.nav_map
	var places := [Vector2(0, 0), Vector2(3900, -2900), Vector2(15000, 9000), Vector2(-30000, -20000), Vector2(35000, 0)]
	var peak := 0
	var first := 0
	for round in 12:
		nm.set_mode(nm.Mode.BIG)
		await process_frame
		nm.follow = false
		nm.big_centre = places[round % places.size()]
		for step in 24:
			nm._zoom_at(nm.big_view.size * 0.5, 0.7 if step < 12 else 1.0 / 0.7)
			nm.big_centre += Vector2(37.0, -21.0) * nm.big_mpp
			await process_frame
		nm.set_mode(nm.Mode.SMALL)
		for i in 5:
			await process_frame
		nm.set_mode(nm.Mode.OFF)
		main._set_paused(false)
		for i in 5:
			await process_frame
		var m := OS.get_static_memory_usage() / 1048576
		peak = maxi(peak, m)
		if round == 1:
			first = m
		print("round %d: %s" % [round, _mem()])
	var grew := peak - first
	print("MAP STRESS %s: 12 open/zoom/close rounds, peak RAM %d MB, growth after round 1: %d MB" % ["PASS" if grew < 150 else "FAIL", peak, grew])
	quit(0 if grew < 150 else 1)
