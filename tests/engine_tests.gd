extends SceneTree
## Headless engine start / shutdown tests (M2.30).
## Run:  godot --headless --path . --script res://tests/engine_tests.gd
## Flies the real checklist with the real systems + flight model and checks what the gauges do.

const DataLoader = preload("res://scripts/core/data_loader.gd")
const HeliFDM = preload("res://scripts/fdm/heli_fdm.gd")
const Systems = preload("res://scripts/aircraft/engine_systems.gd")
const Checklist = preload("res://scripts/core/checklist.gd")

const DT := 1.0 / 120.0

class FlatGround:
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP

class Ctl:
	var throttle := 0.0
	var collective := 0.0

var data = {}
var lines: PackedStringArray = []
var passed = 0
var failed = 0
var f
var s
var c
var verbose := false

func log_line(t: String) -> void:
	print(t)
	lines.append(t)

func check(name: String, ok: bool, detail: String) -> void:
	if ok:
		passed += 1
		log_line("  PASS  %s  (%s)" % [name, detail])
	else:
		failed += 1
		log_line("  FAIL  %s  (%s)" % [name, detail])

func setup(cold := true) -> void:
	f = HeliFDM.new(data)
	f.ground = FlatGround.new()
	f.atmo.wind_speed_kt = 0.0
	f.atmo.gust_intensity = 0.0
	f.pos = Vector3(0, f.cg_height - 0.03, 0)
	f.reset_dynamic_state()
	f._was_on_ground = true
	f.collective = 0.0
	s = Systems.new(f)
	c = Ctl.new()
	if cold:
		s.cold_and_dark()
		f.n1 = 0.0
		f.nr = 0.0
		f.n2 = 0.0

func run(sec: float, cb := Callable()) -> void:
	var n := int(sec / DT)
	for i in n:
		if cb.is_valid():
			cb.call()
		s.pre_step(DT, c)
		f.throttle = c.throttle
		f.collective = c.collective
		f.step(DT)
		s.post_step(DT)
		if verbose and i % int(1.0 / DT) == 0:
			log_line("      t %5.1f  N1 %5.1f  TOT %4.0f  NR %5.1f  N2 %5.1f  TQ %5.1f  lit %s start %s  %s" % [f.sim_time, f.n1, s.tot, f.nr_pct(), f.n2_pct(), f.torque_pct, f.lit, f.starting, ",".join(s.lit_cautions())])

## Normal start by the checklist. Returns a dictionary of what happened.
func normal_start(fuel_n1 := 15.0, release_n1 := 58.0, throttle_during := 0.0) -> Dictionary:
	s.battery = true
	s.fuel_valve = true
	s.hydraulics = true
	s.friction = false
	run(1.0)
	var caut_after_batt: Array = s.lit_cautions()
	s.pull_breaker("FUEL BOOST FWD", false)     # prestart: FUEL BOOST AFT and FWD breakers - in
	s.pull_breaker("FUEL BOOST AFT", false)
	run(1.0)
	s.starter_btn = true
	var rotor_at_25 := -1.0
	var t0: float = f.sim_time
	while f.n1 < fuel_n1 and f.sim_time - t0 < 30.0:
		run(DT)
	s.throttle_closed = false
	c.throttle = throttle_during
	while f.sim_time - t0 < 90.0:
		run(DT)
		if rotor_at_25 < 0.0 and f.n1 >= 25.0:
			rotor_at_25 = f.nr_pct()
		if f.n1 >= release_n1 and s.starter_btn:
			s.starter_btn = false
		if not f.starting and f.lit:
			break
		if not f.lit and not s.starter_btn:
			break
	c.throttle = 0.0
	return {"caut": caut_after_batt, "rotor25": rotor_at_25, "t_idle": f.sim_time - t0}

func test_normal_start() -> void:
	log_line("\n[1] Normal start by the checklist (OAT 15 C, fuel at 15% N1, starter off at 58%)")
	setup()
	var r := normal_start()
	check("battery ON lights ENG OUT, TRANS OIL PRESS, ROTOR LOW RPM", "ENG OUT" in r["caut"] and "TRANS OIL PRESS" in r["caut"] and "ROTOR LOW RPM" in r["caut"], ", ".join(r["caut"]))
	check("light-off at the checklist N1", absf(float(s.ev.get("light_off_n1", 0.0)) - 15.0) < 1.0, "%.1f%%" % float(s.ev.get("light_off_n1", 0.0)))
	check("main rotor turning by 25% N1", float(r["rotor25"]) > 0.3, "NR %.1f%% at 25%% N1" % float(r["rotor25"]))
	check("normal start peak TOT 650-810 C (no exceedance)", s.tot_peak > 650.0 and s.tot_peak < 810.0, "peak %.0f C" % s.tot_peak)
	check("idle reached about 20-45 s after starter engage", r["t_idle"] > 20.0 and r["t_idle"] < 45.0, "%.1f s" % r["t_idle"])
	check("starter released at 58% N1", absf(float(s.ev.get("starter_off_n1", 0.0)) - 58.0) < 1.0, "%.1f%%" % float(s.ev.get("starter_off_n1", 0.0)))
	run(60.0)
	check("stable ground idle after 1 min", f.lit and absf(f.n1 - f.n1_idle) < 2.0, "N1 %.1f%%  TOT %.0f C  NR %.0f%%  oil %.0f psi" % [f.n1, s.tot, f.nr_pct(), s.eng_oil_psi])
	check("ENG OUT light out at idle", not s.cautions["ENG OUT"], ", ".join(s.lit_cautions()))
	# throttle to 70% N1, generator on
	var thr70 := func() -> void:
		c.throttle = clampf(c.throttle + (0.002 if f.n1 < 70.0 else -0.002), 0.0, 1.0)
	run(20.0, thr70)
	s.generator = true
	run(3.0, thr70)
	check("throttle set for 70% N1", absf(f.n1 - 70.0) < 2.0, "N1 %.1f%%  NR %.0f%%" % [f.n1, f.nr_pct()])
	check("generator on line, GEN FAIL out", s.gen_online and not s.cautions["GEN FAIL"], "")
	# run-up: full throttle, governor 100%
	var max_tq := [0.0, ""]
	var full := func() -> void:
		c.throttle = minf(c.throttle + 0.03 * DT, 1.0)
		if f.torque_pct > max_tq[0]:
			max_tq[0] = f.torque_pct
			max_tq[1] = "thr %.2f N1 %.0f NR %.0f gov %.0f" % [c.throttle, f.n1, f.nr_pct(), f.gov_set_pct]
	run(40.0, full)
	s.fdm.gov_set_pct = 100.0
	run(15.0, full)
	check("full throttle, collective down: NR 100% on the governor", absf(f.nr_pct() - 100.0) < 1.5, "NR %.1f%%" % f.nr_pct())
	check("torque stays below 40% during the run-up", max_tq[0] < 40.0, "max %.0f%% at %s" % [max_tq[0], max_tq[1]])
	check("all caution lights out after the run-up", s.lit_cautions().is_empty(), ", ".join(s.lit_cautions()))
	check("running TOT reasonable at flat pitch", s.tot > 380.0 and s.tot < 600.0, "%.0f C" % s.tot)

func test_hot_starts() -> void:
	log_line("\n[2] Hot / bad starts")
	setup()
	s.tot = 300.0
	var r := normal_start()
	check("starting with TOT 300 C (above 150) gives a hotter start", s.tot_peak > 810.0, "peak %.0f C" % s.tot_peak)
	setup()
	normal_start(15.0, 58.0, 0.5)
	check("throttle opened during the start = HOT START above 927 C", s.tot_peak > 927.0 and s.exceedances.size() > 0, "peak %.0f C  %s" % [s.tot_peak, ", ".join(s.exceedances)])
	setup()
	normal_start(15.0, 35.0)
	run(20.0)
	check("starter released at 35% N1: hung / failed start, N1 does not reach idle", f.n1 < 50.0, "N1 %.1f%%  TOT peak %.0f C" % [f.n1, s.tot_peak])
	setup()
	s.battery = true
	s.fuel_valve = true
	s.starter_btn = true
	s.throttle_closed = false      # fuel in BEFORE the starter: light-off at very low N1
	run(40.0, func() -> void:
		if f.n1 > 58.0:
			s.starter_btn = false)
	check("fuel introduced at very low N1 makes a hot start", float(s.ev.get("light_off_n1", 99.0)) < 10.0 and s.tot_peak > 900.0, "light-off %.1f%%  peak %.0f C" % [float(s.ev.get("light_off_n1", 0.0)), s.tot_peak])
	setup()
	s.fuel_valve = true
	s.starter_btn = true
	s.throttle_closed = false
	run(10.0)
	check("no battery: no starter, nothing turns", f.n1 < 0.1 and not f.lit, "N1 %.1f" % f.n1)

func test_shutdown() -> void:
	log_line("\n[3] Shutdown")
	setup(false)
	s.engine_running()
	f.n1 = 70.0
	c.throttle = 1.0
	run(10.0)
	c.throttle = 0.0
	run(30.0)
	var idle_tot: float = s.tot
	s.throttle_closed = true
	run(3.0)
	check("throttle CLOSED: flame-out, ENG OUT light", not f.lit and s.cautions["ENG OUT"], "N1 %.1f" % f.n1)
	var tot0: float = s.tot
	run(20.0)
	check("TOT and N1 reducing", s.tot < tot0 and f.n1 < 20.0, "TOT %.0f -> %.0f C, N1 %.1f%%" % [tot0, s.tot, f.n1])
	run(120.0)
	check("rotor coasts down after shutdown", f.nr_pct() < 40.0, "NR %.1f%% after 2 min" % f.nr_pct())
	s.generator = false
	s.boost = false
	s.battery = false
	run(1.0)
	check("battery OFF: all lights out", s.lit_cautions().is_empty(), "")

func test_checklist() -> void:
	log_line("\n[4] Checklist data and automatic ticks")
	var cl = Checklist.new()
	check("checklist data loads", cl.lists.size() >= 4, "%d lists" % cl.lists.size())
	var n_items := 0
	var bad := []
	for l in cl.lists:
		for it in l["items"]:
			n_items += 1
			if it.has("auto") and not cl.KNOWN_AUTO.has(it["auto"]):
				bad.append(it["auto"])
	check("every automatic item has a known check", bad.is_empty(), "%d items, unknown: %s" % [n_items, ", ".join(bad)])
	setup()
	cl.systems = s
	cl.fdm = f
	cl.start_list("start")
	s.battery = true
	run(0.5)
	cl.update(0.5)
	check("checklist does not tick BATTERY before the earlier items are done", cl.cur > 0 or cl.done_count() == 0, "current item %d" % cl.cur)

func test_breakers() -> void:
	log_line("\n[5] Overhead circuit breakers")
	setup()
	check("cold and dark leaves the FUEL BOOST breakers out (after the preflight fuel sample)", not s.cb_in("FUEL BOOST FWD") and not s.cb_in("FUEL BOOST AFT"), ", ".join(s.breakers_out()))
	s.battery = true
	s.fuel_valve = true
	run(0.5)
	check("boost breakers out + battery: FUEL PUMP light, no fuel pressure", s.cautions["FUEL PUMP"] and s.fuel_psi < 1.0, "%.1f psi" % s.fuel_psi)
	s.pull_breaker("FUEL BOOST AFT", false)
	run(0.5)
	check("one boost pump: pressure in limits but FUEL PUMP light stays on", s.cautions["FUEL PUMP"] and s.fuel_psi >= 4.0, "%.1f psi" % s.fuel_psi)
	s.pull_breaker("FUEL BOOST FWD", false)
	run(0.5)
	check("both boost breakers in: FUEL PUMP light out", not s.cautions["FUEL PUMP"] and s.fuel_psi >= 4.0, "%.1f psi" % s.fuel_psi)
	s.pull_breaker("CAUTION LT")
	run(0.5)
	check("CAUTION LT breaker out: every caution light dark", s.lit_cautions().is_empty(), "")
	s.pull_breaker("CAUTION LT", false)
	s.pull_breaker("IGN ENG")
	s.starter_btn = true
	run(6.0)
	s.throttle_closed = false
	run(15.0)
	check("IGN ENG breaker out: no light-off", not f.lit and f.n1 > 15.0, "N1 %.1f%%" % f.n1)
	s.starter_btn = false
	s.throttle_closed = true
	setup(false)
	s.engine_running()
	s.hydraulics = false
	run(1.0)
	check("hydraulics switch OFF: no boost", not s.hyd_available, "")
	s.pull_breaker("HYD BOOST")
	run(1.0)
	check("HYD BOOST breaker out: boost back ON (solenoid de-energised, RFM)", s.hyd_available, "")

func _initialize() -> void:
	data = DataLoader.load_aircraft()
	verbose = OS.get_environment("AB206_VERBOSE") != ""
	log_line("AB206 REALSIM engine start/shutdown tests  %s" % Time.get_datetime_string_from_system())
	test_normal_start()
	test_hot_starts()
	test_shutdown()
	test_checklist()
	test_breakers()
	log_line("\nRESULT: %d passed, %d failed" % [passed, failed])
	var fa = FileAccess.open("user://engine_test_results.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(lines))
	quit(0 if failed == 0 else 1)
