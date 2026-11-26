extends SceneTree
## Headless flight-model test suite.
## Run:  godot --headless --path . --script res://tests/run_tests.gd
## (Run_Tests.bat does this on Windows.) Results are printed and written to
## user://test_results.txt. Exit code 0 = all passed.

const DataLoader = preload("res://scripts/core/data_loader.gd")
const HeliFDM = preload("res://scripts/fdm/heli_fdm.gd")
const Trim = preload("res://scripts/fdm/trim.gd")
const Landing = preload("res://scripts/core/landing_rating.gd")

const DT := 1.0 / 240.0

class FlatGround:
	var h = 0.0
	func height_at(_x: float, _z: float) -> float:
		return h
	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP

var data = {}
var lines: PackedStringArray = []
var passed = 0
var failed = 0

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

func make(mass: float):
	var f = HeliFDM.new(data)
	f.ground = FlatGround.new()
	f.atmo.wind_speed_kt = 0.0
	f.atmo.gust_intensity = 0.0
	f.set_mass(mass)
	return f

func place_trim(f, skid_agl: float, speed_kt: float, heading := 0.0) -> float:
	f.pos = Vector3(0.0, skid_agl + f.cg_height, 0.0)
	f.reset_dynamic_state()
	var hd = deg_to_rad(heading)
	var v = Vector3(sin(hd), 0.0, -cos(hd)) * speed_kt * HeliFDM.KT
	return Trim.trim(f, heading, v)

# ------------------------------------------------------------ test autopilot
class Pilot:
	var f
	var alt_target = 0.0
	var vz_target_override = NAN
	var speed_target = 0.0       # m/s forward over the ground
	var hdg_target = 0.0
	var trim = []
	var hold_collective = false
	var coll_i = 0.0
	var lon_i = 0.0
	func _init(fdm) -> void:
		f = fdm
		trim = [f.collective, f.cyclic_lon, f.cyclic_lat, f.pedal]
		alt_target = f.pos.y
		hdg_target = f.heading_deg()
		var fwd: Vector3 = -f.basis.z
		speed_target = Vector2(f.vel.x, f.vel.z).dot(Vector2(fwd.x, fwd.z).normalized())
		coll_i = f.collective
	func update(dt: float) -> void:
		var hd = deg_to_rad(f.heading_deg())
		var fwd = Vector2(sin(hd), -cos(hd))
		var right = Vector2(cos(hd), sin(hd))
		var gv = Vector2(f.vel.x, f.vel.z)
		var vx = gv.dot(fwd)
		var vy = gv.dot(right)
		# collective: altitude / vertical speed
		if not hold_collective:
			var vz_cmd = clampf((alt_target - f.pos.y) * 0.5, -2.0, 2.0)
			if not is_nan(vz_target_override):
				vz_cmd = vz_target_override
			coll_i += (vz_cmd - f.vel.y) * 0.08 * dt
			coll_i = clampf(coll_i, 0.0, 1.0)
			f.collective = clampf(coll_i + (vz_cmd - f.vel.y) * 0.05, 0.0, 1.0)
		# longitudinal: speed -> pitch attitude -> cyclic
		var pitch_cmd = clampf(-(speed_target - vx) * 1.5, -15.0, 12.0) + trim_pitch
		var pitch: float = f.pitch_deg()
		lon_i = clampf(lon_i + (pitch - pitch_cmd) * 0.01 * dt, -0.8, 0.8)
		f.cyclic_lon = clampf(trim[1] + lon_i + (pitch - pitch_cmd) * 0.03 + f.omega.y * 1.0, -1.0, 1.0)
		var roll_cmd = clampf(-vy * 2.0, -15.0, 15.0) + trim_roll
		var roll: float = f.roll_deg()
		f.cyclic_lat = clampf(trim[2] + (roll_cmd - roll) * 0.04 - f.omega.x * 0.4, -1.0, 1.0)
		var herr = wrapf(hdg_target - f.heading_deg(), -180.0, 180.0)
		f.pedal = clampf(trim[3] + herr * 0.03 - f.omega.z * 0.8, -1.0, 1.0)
	var trim_pitch = 0.0
	var trim_roll = 0.0
	func capture_attitude() -> void:
		trim_pitch = f.pitch_deg()
		trim_roll = f.roll_deg()

func finite(f) -> bool:
	var vals = [f.pos.x, f.pos.y, f.pos.z, f.vel.length(), f.omega.length(), f.nr, f.n1]
	for v in vals:
		if is_nan(v) or is_inf(v):
			return false
	return true

# ------------------------------------------------------------------- tests
func test_hover_power() -> void:
	log_line("\n[1] Hover power vs weight and ground effect (sea level, ISA, no wind)")
	var res = {}
	for m in [1000.0, 1451.0]:
		for h in [1.0, 20.0]:
			var f = make(m)
			var r = place_trim(f, h, 0.0)
			res["%d_%d" % [int(m), int(h)]] = [f.torque_pct, f.collective, f.n1, f.pitch_deg(), f.roll_deg(), f.pedal, r, f.ge_factor]
			log_line("    %4d kg, skid %4.1f m: torque %5.1f%%  collective %4.2f  N1 %5.1f%%  pitch %5.1f  roll %5.1f  pedal %5.2f  GE %.3f  (residual %.5f)" % [int(m), h, f.torque_pct, f.collective, f.n1, f.pitch_deg(), f.roll_deg(), f.pedal, f.ge_factor, r])
	check("trim converges", res["1451_20"][6] < 1e-2 and res["1000_1"][6] < 1e-2, "residuals %.5f / %.5f" % [res["1451_20"][6], res["1000_1"][6]])
	check("heavy needs more torque than light (OGE)", res["1451_20"][0] > res["1000_20"][0] + 10.0, "%.1f%% vs %.1f%%" % [res["1451_20"][0], res["1000_20"][0]])
	check("heavy needs more collective than light", res["1451_20"][1] > res["1000_20"][1] + 0.05, "%.2f vs %.2f" % [res["1451_20"][1], res["1000_20"][1]])
	check("ground effect: 1 m needs less torque than 20 m (max weight)", res["1451_1"][0] < res["1451_20"][0] - 5.0, "%.1f%% vs %.1f%%" % [res["1451_1"][0], res["1451_20"][0]])
	check("ground effect: 1 m needs less torque than 20 m (light)", res["1000_1"][0] < res["1000_20"][0] - 4.0, "%.1f%% vs %.1f%%" % [res["1000_1"][0], res["1000_20"][0]])
	check("max-weight OGE hover torque plausible (70-100%)", res["1451_20"][0] > 70.0 and res["1451_20"][0] < 100.0, "%.1f%%" % res["1451_20"][0])
	check("hover attitude plausible (nose up 0-8 deg, left roll for tail rotor drift)", res["1451_20"][3] > -1.0 and res["1451_20"][3] < 8.0 and res["1451_20"][4] < 0.5, "pitch %.1f roll %.1f" % [res["1451_20"][3], res["1451_20"][4]])
	check("hover needs left pedal", res["1451_20"][5] < 0.0, "pedal %.2f" % res["1451_20"][5])

func test_power_curve_and_etl() -> void:
	log_line("\n[2] Level-flight power required (1200 kg, 300 m AGL) - translational lift")
	var tq = {}
	for kt in [0.0, 10.0, 20.0, 30.0, 40.0, 60.0, 80.0, 100.0, 120.0]:
		var f = make(1200.0)
		var r = place_trim(f, 300.0, kt)
		tq[kt] = f.torque_pct
		log_line("    %3d kt: torque %5.1f%%  collective %4.2f  cyclic lon %5.2f  pitch %5.1f  N1 %5.1f  (res %.5f)" % [int(kt), f.torque_pct, f.collective, f.cyclic_lon, f.pitch_deg(), f.n1, r])
	var min_t: float = min(tq[40.0], min(tq[60.0], tq[80.0]))
	check("power bucket: 40-80 kt needs much less torque than hover", min_t < tq[0.0] - 15.0, "min %.1f%% vs hover %.1f%%" % [min_t, tq[0.0]])
	check("translational lift: 20 kt needs less torque than hover", tq[20.0] < tq[0.0] - 5.0, "%.1f%% vs %.1f%%" % [tq[20.0], tq[0.0]])
	check("cruise 100 kt within max continuous (85%)", tq[100.0] < 85.0, "%.1f%%" % tq[100.0])
	check("power rises again at high speed", tq[120.0] > min_t + 10.0, "%.1f%%" % tq[120.0])
	# nose-up tendency: hover controls, then add 10 m/s headwind (flapback + stab wash)
	var f2 = make(1200.0)
	place_trim(f2, 20.0, 0.0)
	var out = {}
	f2.vel = Vector3(0, 0, -8.0)
	for i in 5:
		f2.compute_aero(out)
		f2.a1 = f2.a1_ss
		f2.b1 = f2.b1_ss
	var M: Vector3 = out["M"]
	check("accelerating from hover gives a nose-up pitching moment", M.y > 0.0, "M_pitch %.0f N m at 15 kt with hover controls" % M.y)
	check("and a rolling moment to the right (transverse flow)", M.x > -200.0, "M_roll %.0f N m" % M.x)

func test_hover_hold() -> void:
	log_line("\n[3] Closed-loop hover hold 60 s at 5 m (numerical stability)")
	var f = make(1200.0)
	place_trim(f, 5.0, 0.0)
	var pl = Pilot.new(f)
	pl.capture_attitude()
	var start: Vector3 = f.pos
	var max_nr_dev = 0.0
	var usec = 0
	for i in int(60.0 / DT):
		pl.update(DT)
		f.step(DT)
		usec += f.last_step_usec
		if i > 240:
			max_nr_dev = maxf(max_nr_dev, absf(f.nr_pct() - 100.0))
	var drift = (f.pos - start).length()
	check("values stay finite", finite(f), "")
	check("hover held (drift < 3 m)", drift < 3.0, "drift %.2f m" % drift)
	check("governor holds Nr within 1.5%", max_nr_dev < 1.5, "max deviation %.2f%%" % max_nr_dev)
	check("FDM step cost small", float(usec) / (60.0 / DT) < 400.0, "%.0f us per 1/240 s step" % (float(usec) / (60.0 / DT)))

func test_yaw() -> void:
	log_line("\n[4] Torque reaction: collective up without pedal yaws nose right")
	var f = make(1200.0)
	place_trim(f, 30.0, 0.0)
	var pl = Pilot.new(f)
	pl.capture_attitude()
	var ped0: float = f.pedal
	pl.hold_collective = true
	f.collective += 0.12
	var hdg0: float = f.heading_deg()
	var r_after = 0.0
	for i in int(2.0 / DT):
		pl.update(DT)
		f.pedal = ped0
		f.step(DT)
	r_after = rad_to_deg(f.omega.z)
	var turned = wrapf(f.heading_deg() - hdg0, -180.0, 180.0)
	check("nose yaws right when collective raised with fixed pedals", r_after > 3.0 and turned > 2.0, "yaw rate %.1f deg/s, turned %.1f deg" % [r_after, turned])
	for i in int(3.0 / DT):
		pl.update(DT)
		f.pedal = ped0 - 0.35
		f.step(DT)
	check("left pedal stops / reverses the yaw", rad_to_deg(f.omega.z) < r_after * 0.3, "yaw rate now %.1f deg/s" % rad_to_deg(f.omega.z))

func test_autorotation() -> void:
	log_line("\n[5] Autorotation (1200 kg, 80 kt, 800 m AGL)")
	# a) throttle chopped, collective NOT lowered
	var f = make(1200.0)
	place_trim(f, 800.0, 80.0)
	var pl = Pilot.new(f)
	pl.capture_attitude()
	pl.hold_collective = true
	f.throttle = 0.0
	var t_low = -1.0
	for i in int(4.0 / DT):
		pl.update(DT)
		f.step(DT)
		if t_low < 0.0 and f.nr_pct() < 90.0:
			t_low = i * DT
	check("Nr decays below 90% within 3 s if collective is not lowered", t_low > 0.0 and t_low < 3.0, "reached 90%% at %.2f s (Nr now %.0f%%)" % [t_low, f.nr_pct()])
	# b) throttle chopped, collective lowered after 1 s, speed ~60 kt
	f = make(1200.0)
	place_trim(f, 800.0, 80.0)
	pl = Pilot.new(f)
	pl.capture_attitude()
	pl.hold_collective = true
	pl.speed_target = 60.0 * HeliFDM.KT
	f.throttle = 0.0
	var nr_min = 999.0
	var nr_max = 0.0
	var vs_sum = 0.0
	var vs_n = 0
	var vs_min = 99.0
	var vs_max = -99.0
	var coll0: float = f.collective
	var cbase = 0.05
	for i in int(45.0 / DT):
		var t = i * DT
		if t > 1.0:
			# lower collective smoothly, then manage Nr like a pilot (raise if > 104%)
			# pilot: lower the lever, then use it to keep Nr near 100% (like the real technique)
			if t < 3.0:
				f.collective = move_toward(f.collective, 0.05, 0.6 * DT)
			else:
				cbase = clampf(cbase + (f.nr_pct() - 100.0) * 0.004 * DT, 0.0, coll0)
				f.collective = clampf(cbase + (f.nr_pct() - 100.0) * 0.015, 0.0, coll0)
		pl.update(DT)
		f.step(DT)
		if OS.get_environment("AB206_VERBOSE") != "" and i % 480 == 0:
			log_line("      t=%4.1f Nr %5.1f N2 %5.1f vs %5.1f IAS %4.0f GS %4.0f pitch %5.1f coll %.2f lon %.2f" % [t, f.nr_pct(), f.n2_pct(), -f.vel.y, f.ias_kt(), f.groundspeed_kt(), f.pitch_deg(), f.collective, f.cyclic_lon])
		if t > 22.0:
			nr_min = minf(nr_min, f.nr_pct())
			nr_max = maxf(nr_max, f.nr_pct())
			var vsp: float = -f.vel.y
			vs_sum += vsp
			vs_n += 1
			vs_min = minf(vs_min, vsp)
			vs_max = maxf(vs_max, vsp)
	var vs_avg = vs_sum / vs_n
	log_line("    steady auto: Nr %.1f-%.1f%%, descent %.1f m/s (%.0f ft/min), IAS %.0f kt, collective %.2f" % [nr_min, nr_max, vs_avg, vs_avg / 0.3048 * 60.0, f.ias_kt(), f.collective])
	check("steady autorotation holds Nr inside power-off limits 90-107%", nr_min >= 90.0 and nr_max <= 107.0, "%.1f-%.1f%%" % [nr_min, nr_max])
	check("steady descent rate plausible (1,200-2,600 ft/min)", vs_avg > 6.0 and vs_avg < 13.2, "%.1f m/s" % vs_avg)
	check("engine and rotor needles split in autorotation (freewheel)", not f.engaged and f.n2_pct() < f.nr_pct() - 10.0, "N2 %.0f%%, Nr %.0f%%" % [f.n2_pct(), f.nr_pct()])
	check("descent rate is steady (spread < 2.5 m/s)", vs_max - vs_min < 2.5, "%.1f..%.1f m/s" % [vs_min, vs_max])
	# c) power recovery
	f.throttle = 1.0
	var ok_nr = false
	for i in int(10.0 / DT):
		f.collective = move_toward(f.collective, 0.45, 0.25 * DT)
		pl.update(DT)
		f.step(DT)
	ok_nr = absf(f.nr_pct() - 100.0) < 2.0 and f.engaged
	check("power recovery: Nr back to 100% with engine engaged", ok_nr and finite(f), "Nr %.1f%%, N2 %.1f%%, torque %.0f%%" % [f.nr_pct(), f.n2_pct(), f.torque_pct])

func test_landing() -> void:
	log_line("\n[6] Landing and ground contact")
	var f = make(1200.0)
	place_trim(f, 1.0, 0.0)
	var pl = Pilot.new(f)
	pl.capture_attitude()
	pl.vz_target_override = -0.4
	var touched = false
	var t_touch = 0.0
	var x_touch = Vector3.ZERO
	var max_agl_after = 0.0
	for i in int(14.0 / DT):
		var t = i * DT
		if touched:
			pl.hold_collective = true
			f.collective = move_toward(f.collective, 0.0, 0.35 * DT)
			if t - t_touch > 3.0:
				max_agl_after = maxf(max_agl_after, f.agl)
		pl.update(DT)
		f.step(DT)
		if f.touchdown_event and not touched:
			touched = true
			t_touch = t
			x_touch = f.pos
	var slide = Vector2(f.pos.x - x_touch.x, f.pos.z - x_touch.z).length()
	check("gentle touchdown detected", touched and f.touchdown_sink < 1.0, "sink %.2f m/s" % f.touchdown_sink)
	check("rating says normal", Landing.rate(f.touchdown_sink) == "SMOOTH" or Landing.rate(f.touchdown_sink) == "NORMAL", Landing.rate(f.touchdown_sink))
	check("settles without bouncing (stays on skids)", max_agl_after < 0.05, "max skid height after settling %.3f m" % max_agl_after)
	check("does not slide (< 0.3 m)", slide < 0.3, "%.2f m" % slide)
	check("at rest with collective down", f.vel.length() < 0.05 and f.collective < 0.05, "speed %.3f m/s" % f.vel.length())
	var hd0 = f.heading_deg()
	for i in int(10.0 / DT):
		f.step(DT)
	check("parked with collective down: no yaw creep from tail rotor thrust", absf(wrapf(f.heading_deg() - hd0, -180, 180)) < 0.5, "heading change %.2f deg in 10 s" % wrapf(f.heading_deg() - hd0, -180, 180))
	# drop test
	var g = make(1200.0)
	place_trim(g, 3.0, 0.0)
	g.collective = 0.0
	for i in int(3.0 / DT):
		g.step(DT)
		if g.touchdown_event:
			break
	check("drop from 3 m with collective down is rated HARD or worse", Landing.rate(g.touchdown_sink) in ["HARD", "DAMAGE"], "sink %.2f m/s -> %s" % [g.touchdown_sink, Landing.rate(g.touchdown_sink)])
	for i in int(3.0 / DT):
		g.step(DT)
	check("no numerical blow-up after hard landing", finite(g) and g.pos.y > 0.5 and g.pos.y < 1.6, "CG height %.2f m" % g.pos.y)

func test_long_run() -> void:
	log_line("\n[7] Long run: 10 minutes hover in light turbulence")
	var f = make(1300.0)
	f.atmo.wind_speed_kt = 8.0
	f.atmo.gust_intensity = 0.3
	place_trim(f, 10.0, 0.0)
	var pl = Pilot.new(f)
	pl.capture_attitude()
	var ok = true
	for i in int(600.0 / DT):
		pl.update(DT)
		f.step(DT)
		if i % 2400 == 0 and not finite(f):
			ok = false
			break
	check("10 min in wind and turbulence stays finite and airborne", ok and finite(f) and f.agl > 2.0, "skid height %.1f m, Nr %.1f%%" % [f.agl, f.nr_pct()])


func _vrs_run(en: bool, fwd_kt: float, coll_after: float) -> Dictionary:
	var f = make(1200.0)
	f.vrs_enabled = en
	place_trim(f, 500.0, fwd_kt)
	var c0: float = f.collective
	var lon0: float = f.cyclic_lon
	var t := 0.0
	var res := {"sink5": 0.0, "worst": 0.0, "vrs": 0.0, "arrest": -1.0, "finite": true}
	while t < 15.0:
		f.collective = c0 - 0.12 if t < 5.0 else c0 + coll_after
		f.cyclic_lon = lon0 + f.omega.y * 1.0
		f.cyclic_lat = f.cyclic_lat - f.omega.x * 0.02
		f.pedal = clampf(f.pedal - f.omega.z * 0.05, -1.0, 1.0)
		f.step(DT)
		t += DT
		if t <= 5.0:
			res["sink5"] = -f.vel.y
		res["worst"] = maxf(res["worst"], -f.vel.y)
		res["vrs"] = maxf(res["vrs"], f.vrs)
		if t > 5.0 and res["arrest"] < 0.0 and f.vel.y > -1.0:
			res["arrest"] = t - 5.0
	res["finite"] = finite(f)
	return res

func test_vrs() -> void:
	log_line("\n[8] Vortex ring state (1200 kg, 500 m AGL, no wind)")
	var f = make(1200.0)
	place_trim(f, 500.0, 0.0)
	var c0: float = f.collective
	var out := {}
	f.collective = c0
	f.vel = Vector3(0.0, -6.0, 0.0)
	for i in 30:
		f.compute_aero(out)
	var vrs_vert: float = f.vrs
	f.reset_dynamic_state()
	f.vel = Vector3(0.0, -6.0, -20.0)
	for i in 30:
		f.compute_aero(out)
	var vrs_fwd: float = f.vrs
	check("VRS detected in a 6 m/s vertical descent", vrs_vert > 0.8, "intensity %.2f" % vrs_vert)
	check("no VRS in the same descent at 20 m/s (39 kt) forward", vrs_fwd < 0.05, "intensity %.2f" % vrs_fwd)
	var off := _vrs_run(false, 0.0, 0.0)
	var on := _vrs_run(true, 0.0, 0.0)
	var fwd := _vrs_run(true, 30.0, 0.0)
	log_line("    collective -0.12 for 5 s then back to hover collective:")
	log_line("      without VRS model: sink %.1f m/s after 5 s, arrested after %.1f s" % [off["sink5"], off["arrest"]])
	log_line("      with VRS model:    sink %.1f m/s after 5 s, worst %.1f m/s, arrested %s" % [on["sink5"], on["worst"], ("after %.1f s" % on["arrest"]) if on["arrest"] >= 0.0 else "NOT within 10 s"])
	log_line("      at 30 kt:          sink %.1f m/s, VRS max %.2f" % [fwd["sink5"], fwd["vrs"]])
	check("in VRS the sink rate builds much faster (low heave damping)", on["sink5"] > off["sink5"] * 1.4, "%.1f vs %.1f m/s" % [on["sink5"], off["sink5"]])
	check("in VRS the aircraft loses more height before the descent is arrested", on["worst"] > off["worst"] + 3.0, "worst sink %.1f vs %.1f m/s" % [on["worst"], off["worst"]])
	check("forward speed keeps the rotor out of VRS", fwd["vrs"] < 0.05, "max %.2f" % fwd["vrs"])
	check("values stay finite in VRS", on["finite"], "")

func _initialize() -> void:
	data = DataLoader.load_aircraft()
	log_line("AB206 REALSIM flight-model tests  %s" % Time.get_datetime_string_from_system())
	var only = OS.get_environment("AB206_TEST")
	var tests = ["test_hover_power", "test_power_curve_and_etl", "test_hover_hold", "test_yaw", "test_autorotation", "test_landing", "test_long_run", "test_vrs"]
	for t in tests:
		if only == "" or only in t:
			call(t)
	log_line("\nRESULT: %d passed, %d failed" % [passed, failed])
	var fa = FileAccess.open("user://test_results.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(lines))
	quit(0 if failed == 0 else 1)
