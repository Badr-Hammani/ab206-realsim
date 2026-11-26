extends SceneTree
## End-to-end test of the flight-manual checklists in the real main scene (M2.30):
## a "robot pilot" does every item of S1 (prestart, starting, run-up) and S2 (shutdown) by
## working the switches and controls only - never by ticking the list - and the lessons must
## complete with a good score. A second, careless start (fuel in too early, throttle open)
## must be caught as a hot start.
## Run:  godot --headless --path . --script res://tests/checklist_lesson_tests.gd

const DT := 1.0 / 120.0

var main
var lines: PackedStringArray = []
var passed := 0
var failed := 0
var _started := false
var _k := 0

func log_line(s: String) -> void:
	print(s)
	lines.append(s)

func check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		log_line("  PASS  %s  (%s)" % [name, detail])
	else:
		failed += 1
		log_line("  FAIL  %s  (%s)" % [name, detail])

func tick() -> void:
	main._physics_process(DT)
	_k += 1
	if _k % 3 == 0:
		main._process(3.0 * DT)

func run(sec: float) -> void:
	for i in int(sec / DT):
		tick()

## The robot pilot: looks at the current checklist item and does what it says with the
## switches / controls (as a pilot would with the J panel and the keys).
func act(careless := false) -> void:
	var cl = main.checklist
	var sy = main.systems
	var c = main.controls
	var f = main.fdm
	if cl.finished() or not cl.active():
		return
	var it: Dictionary = cl.items()[cl.cur]
	var key: String = str(it.get("auto", ""))
	match key:
		"":
			cl.confirm()                      # a look-and-confirm item
		"controls_checked":
			if sy.friction:
				main.set_friction(false)
			var ph := fmod(f.sim_time, 4.0)
			c.stick_mouse = Vector2(1.0 if ph < 1.0 else -1.0, 1.0 if ph < 2.0 and ph >= 1.0 else -1.0) if ph < 3.0 else Vector2.ZERO
			c.pedal_trim = 1.0 if ph < 1.5 else -1.0
			c.collective = 0.7 if ph < 2.0 else 0.0
			if ph >= 3.0:
				c.pedal_trim = 0.0
		"throttle_closed":
			c.stick_mouse = Vector2.ZERO
			c.pedal_trim = 0.0
			c.throttle = 0.0
			if not sy.throttle_closed:
				main.set_throttle_closed(true)
		"landing_light_off":
			sy.landing_light = false
		"anti_ice_off":
			sy.anti_ice = false
		"hyd_on":
			sy.hydraulics = true
		"fuel_valve_on":
			sy.fuel_valve = true
		"generator_off":
			sy.generator = false
		"battery_on":
			sy.battery = true
		"caution_tested":
			sy.caution_test = true
			run(0.3)
			sy.caution_test = false
		"rpm_horn_check":
			c.collective = 0.3
			run(0.5)
			c.collective = 0.0
		"collective_down", "collective_down_free":
			c.collective = 0.0
			if key == "collective_down_free" and sy.friction:
				main.set_friction(false)
		"boost_pressure":
			sy.pull_breaker("FUEL BOOST FWD", false)
			sy.pull_breaker("FUEL BOOST AFT", false)
		"cbs_in":
			for b in sy.breakers_out():
				if not str(b).begins_with("FUEL BOOST"):
					sy.pull_breaker(b, false)
		"starter_on":
			sy.starter_btn = true
		"fuel_introduced":
			sy.starter_btn = true
			if careless or (f.n1 >= sy.light_off_n1() and sy.tot <= 150.0):
				main.set_throttle_closed(false)
				if careless:
					c.throttle = 0.4
		"starter_released":
			if f.n1 >= 58.0:
				sy.starter_btn = false
		"tot_start_ok", "rotor_turning", "oil_rising", "oils_rising", "idle_1min", "n1_idle_check", "tot_reducing", "idle_2min", "rotor_stopped", "nr_100":
			if not careless:
				c.throttle = c.throttle if key == "nr_100" else (0.0 if key in ["idle_1min", "n1_idle_check", "idle_2min"] else c.throttle)
		"n1_70":
			c.throttle = minf(c.throttle + 0.15 * DT, 1.0) if f.n1 < 70.0 else c.throttle
		"generator_on":
			sy.generator = true
		"radios_on":
			sy.radios = true
		"hyd_cycled":
			sy.hydraulics = false
			run(1.0)
			sy.hydraulics = true
		"throttle_full":
			c.throttle = minf(c.throttle + 0.03 * DT, 1.0)
		"gov_range_checked":
			if not cl._gov_lo <= 97.5:
				main.beep_gov(-1.0, DT * 4.0)
			else:
				main.beep_gov(1.0, DT * 4.0)
		"anti_ice_as_required":
			pass
		"hyd_off":
			sy.hydraulics = false
		"cyc_x_hyd_off":
			var ph2 := fmod(f.sim_time, 2.0)
			c.stick_mouse = Vector2(0.2 if ph2 < 1.0 else -0.2, 0.2 if ph2 < 0.5 or ph2 >= 1.5 else -0.2)
		"throttle_idle":
			c.throttle = maxf(c.throttle - 0.3 * DT, 0.0)
		"friction_on":
			main.set_friction(true)
		"radios_off":
			sy.radios = false
		"fuel_valve_off":
			sy.fuel_valve = false
		"all_but_bat_off":
			sy.landing_light = false
			sy.anti_ice = false
			sy.radios = false
		"battery_off_safe":
			if f.n1 < 0.5:
				sy.battery = false
		_:
			pass
	if key != "cyc_x_hyd_off" and key != "controls_checked":
		c.stick_mouse = c.stick_mouse.move_toward(Vector2.ZERO, DT)

func fly_lesson(id: String, limit_s: float, careless := false) -> void:
	main.lessons.start(id)
	var t := 0.0
	while t < limit_s and not main.lessons.done:
		act(careless)
		tick()
		t += DT
	log_line("    %s after %.0f s: score %d   list %s item %d: %s" % [id, t, main.lessons.score, main.checklist.list_id, main.checklist.cur, main.checklist.current_text()])
	for l in str(main.lessons.result).split("\n"):
		log_line("      " + l)

func _initialize() -> void:
	log_line("AB206 REALSIM checklist lesson tests  %s" % Time.get_datetime_string_from_system())
	main = load("res://scenes/main.tscn").instantiate()
	main.map_override = "valle"
	root.add_child(main)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _run() -> void:
	main.instructor.voice = false
	main.lessons.progress_path = "user://progress_test.cfg"
	main.lessons.progress = {}
	main.set_assist(0, true)
	log_line("\n[C1] S1 engine start + run-up, by the book")
	fly_lesson("c_start", 600.0)
	check("S1 completes", main.lessons.done, "stage %s" % str(main.lessons._sc.get("stage", "")))
	check("S1 scores 85+ when flown by the book", main.lessons.score >= 85, "score %d" % main.lessons.score)
	check("engine running at 100% after S1", main.fdm.lit and absf(main.fdm.nr_pct() - 100.0) < 1.5, "NR %.1f%%" % main.fdm.nr_pct())
	check("no caution lights after the run-up", main.systems.lit_cautions().is_empty(), ", ".join(main.systems.lit_cautions()))
	log_line("\n[C2] S2 shutdown, by the book")
	fly_lesson("c_shutdown", 600.0)
	check("S2 completes", main.lessons.done, "")
	check("S2 scores 85+", main.lessons.score >= 85, "score %d" % main.lessons.score)
	check("after S2 the engine is stopped and the battery off", not main.fdm.lit and not main.systems.battery, "")
	log_line("\n[C3] careless start: throttle opened during the start")
	main.lessons.start("c_start")
	var t := 0.0
	while t < 120.0 and not main.systems.fdm.lit:
		act(true)
		tick()
		t += DT
	run(20.0)
	check("careless start is a hot start (TOT above 927 C)", main.systems.tot_peak > 927.0, "peak %.0f C, %s" % [main.systems.tot_peak, ", ".join(main.systems.exceedances)])
	main.lessons.stop()
	log_line("\n[C4] engine-running resets still work")
	main.reset_on_pad()
	run(3.0)
	check("F2 reset: engine running, governor 100%", main.fdm.lit and absf(main.fdm.nr_pct() - 100.0) < 1.0, "NR %.1f%%" % main.fdm.nr_pct())
	main.reset_cold_dark(true)
	run(2.0)
	check("Shift+F2 cold and dark: everything stopped, no lights (battery off)", not main.fdm.lit and main.fdm.nr_pct() < 0.5 and main.systems.lit_cautions().is_empty(), "")
	log_line("\nRESULT: %d passed, %d failed" % [passed, failed])
	var fa = FileAccess.open("user://checklist_test_results.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(lines))
	quit(0 if failed == 0 else 1)
