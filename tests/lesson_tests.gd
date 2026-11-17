extends SceneTree
## Headless training-level tests. Loads the real main scene and flies every hover/landing
## level with a "robot student" (hover_hold.gd flying the student's controls through the
## normal control path), then checks the level completes, scores sensibly and that the
## instructor's hands give back the controls without a jump. A second, deliberately sloppy
## robot checks that faults lower the score and that the live coach gives the right cues.
## Run:  godot --headless --path . --script res://tests/lesson_tests.gd
## (Run_Flight_Model_Tests.bat runs this after the flight-model tests.)

const HoverHold = preload("res://scripts/core/hover_hold.gd")
const Coach = preload("res://scripts/core/coach.gd")
const HeliFDM = preload("res://scripts/fdm/heli_fdm.gd")
const Trim = preload("res://scripts/fdm/trim.gd")
const DT := 1.0 / 120.0

var main
var lines: PackedStringArray = []
var passed := 0
var failed := 0

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

## Robot student: flies only the axes the student has, through controls.gd.
class Robot:
	var m
	var hh
	var sloppy := false
	var assisted := false     # flies like a student with assist 3: stick = "go towards the spot"
	var follow_ghost := false
	var shaky := false        # unused
	var novice := false       # a beginner: reacts ~0.5 s late to what he sees, no feel for attitude
	var _seen: Array = []
	var delay := 0.5          # reaction time in simulated seconds (slow motion 50% = 0.25) # copies the instructor's ghost markers, nothing else
	var t := 0.0
	var trim_cyc = null       # hover cyclic, known by a trained pilot before lift-off
	func _init(main_node) -> void:
		m = main_node
		hh = HoverHold.new(m.fdm)
		hh.hold = {"coll": true, "ped": true, "cyc": true}
		var c = m.controls
		hh.sync(c.collective, c.cyclic_lon, c.cyclic_lat, c.pedal)
	func step(dt: float) -> void:
		t += dt
		var L = m.lessons
		var f = m.fdm
		var ctx: Dictionary = m.coach.ctx
		var pad: Vector3 = m.world.terrain.pads["Main helipad"]["pos"]
		hh.target = ctx.get("target") if ctx.get("target") != null else pad
		var h: float = ctx.get("height", NAN)
		hh.height = h if not is_nan(h) else 1.0
		var hd: float = ctx.get("hdg", NAN)
		hh.heading = hd if not is_nan(hd) else 0.0
		hh.vz_override = NAN
		hh.max_speed = 1.5
		match L.id:
			"h_ped":
				var he := wrapf(hh.heading - f.heading_deg(), -180.0, 180.0)
				if absf(he) > 8.0:
					hh.heading = f.heading_deg() + signf(he) * 4.0     # a steady, slow pivot
			"h_cyc":
				hh.max_speed = 0.8
			"h_coll":
				if L.phase == 3:
					hh.vz_override = -0.25
				if L.phase >= 4:
					hh.vz_override = -1.0
			"h_turns":
				if L.phase in [1, 2]:
					var dir := -1.0 if L.phase == 1 else 1.0
					var turned: float = float(L._sc.get("yaw", 0.0)) * dir
					hh.heading = f.heading_deg() + dir * 4.0 if turned < 335.0 else 0.0
			"l_land":
				if L.phase == 1:
					hh.vz_override = -0.25 if f.agl > 0.3 else -0.2
			"l_taxi":
				if L.phase == 1:
					hh.target = m.world.hover_spot
					hh.max_speed = 1.3
				if L.phase == 3:
					hh.vz_override = -0.25
			"l_approach":
				var dist := Vector2(f.pos.x - pad.x, f.pos.z - pad.z).length()
				var hp: float = f.pos.y - f.cg_height - pad.y
				hh.target = pad
				if L.phase <= 1:
					hh.max_speed = L.closure_target_kt(dist) * 0.514444 if L.phase == 1 else 31.0
					var h_des := dist * tan(deg_to_rad(10.0)) if L.phase == 1 else 152.0
					var gsm: float = Vector2(f.vel.x, f.vel.z).length()
					hh.vz_override = clampf((h_des - hp) * 0.4 - (gsm * tan(deg_to_rad(10.0)) if L.phase == 1 else 0.0), -3.0, 2.0)
					if L.phase == 1 and dist < 8.0:
						hh.vz_override = NAN
		if sloppy:
			# a student who over-controls and lets it drift
			hh.target += Vector3(2.6 * sin(t * 0.35), 0.0, 2.2 * cos(t * 0.27))
		var c = m.controls
		if L.id == "l_takeoff" and f.on_ground and trim_cyc != null:
			hh.preset_cyclic(trim_cyc.x, trim_cyc.y)
		if f.on_ground and L.id in ["h_coll", "l_land", "l_taxi"] and L.phase >= 1:
			# after touchdown: lower the collective smoothly to fully down
			hh.sync(move_toward(c.collective, 0.0, 0.4 * dt), c.cyclic_lon, c.cyclic_lat, c.pedal)
		hh.update(dt, c.collective, c.cyclic_lon, c.cyclic_lat, c.pedal)
		var lon: float = hh.lon
		var lat: float = hh.lat
		if sloppy:
			lon += 0.22 * sin(t * 6.5)
			lat += 0.22 * sin(t * 5.7 + 1.0)
		var sh: Dictionary = L.hands.hold
		if follow_ghost:
			var g: Dictionary = m.ghost
			if g.has("coll"):
				c.collective = move_toward(c.collective, g["coll"], 0.5 * dt)
			if g.has("lon"):
				c.stick_mouse = c.stick_mouse.move_toward(Vector2(g["lat"], g["lon"]), 1.5 * dt)
			if g.has("ped"):
				c.pedal_trim = move_toward(c.pedal_trim, g["ped"], 1.5 * dt)
			return
		if assisted:
			var pe: Vector2 = hh.body_xy(hh.target - f.pos)
			var v: Vector2 = (pe * 0.45).limit_length(3.0) / 3.0
			lon = v.x
			lat = v.y
			if sloppy:
				lon += 0.22 * sin(t * 6.5)
				lat += 0.22 * sin(t * 5.7 + 1.0)
		if novice:
			_seen.append([t, hh.body_xy(hh.target - f.pos), hh.body_xy(f.vel)])
			while _seen.size() > 1 and t - float(_seen[0][0]) > delay:
				_seen.pop_front()
			var pe: Vector2 = _seen[0][1]
			var vb: Vector2 = _seen[0][2]
			if m.assist.active_level == 3:
				var v: Vector2 = (pe * 0.45).limit_length(3.0) / 3.0
				lon = v.x
				lat = v.y
			elif m.assist.active_level == 2:
				lon = clampf(0.10 * pe.x - 0.2 * vb.x, -0.5, 0.5)
				lat = clampf(0.10 * pe.y - 0.2 * vb.y, -0.5, 0.5)
			else:
				lon = float(L._trim.get("lon", 0.0)) + 0.06 * pe.x - 0.14 * vb.x
				lat = float(L._trim.get("lat", 0.0)) + 0.06 * pe.y - 0.14 * vb.y
		if not sh["coll"]:
			c.collective = hh.coll
		if not sh["cyc"]:
			c.stick_mouse = Vector2(lat, lon)
		if not sh["ped"]:
			c.pedal_trim = hh.ped

func tick(robot) -> void:
	if robot != null:
		robot.step(DT)
	main._physics_process(DT)
	_k += 1
	if _k % 3 == 0:
		main._process(3.0 * DT)     # display/lesson update at 40 Hz is plenty and keeps the run short

func fly(id: String, limit_s: float, sloppy := false, mode := "") -> Dictionary:
	main.lessons.start(id)
	var r := Robot.new(main)
	r.sloppy = sloppy
	r.assisted = mode == "assisted"
	r.follow_ghost = mode == "ghost"
	if mode.begins_with("novice"):
		r.novice = true
		if mode.ends_with("_slow"):
			r.delay = 0.25        # the same person at 50 % training speed
		r.assisted = mode.begins_with("novice_assisted")
	if id == "l_takeoff":
		# where is the hover cyclic? trim a copy of the aircraft in a 1 m hover over the pad
		var tf = HeliFDM.new(main.data)
		tf.ground = main.world.terrain
		tf.set_mass(main.fdm.mass)
		tf.atmo.wind_from_deg = main.fdm.atmo.wind_from_deg
		tf.atmo.wind_speed_kt = main.fdm.atmo.wind_speed_kt
		tf.atmo.gust_intensity = 0.0
		var pad: Vector3 = main.world.terrain.pads["Main helipad"]["pos"]
		tf.pos = pad + Vector3(0.0, 1.0 + tf.cg_height, 0.0)
		tf.reset_dynamic_state()
		Trim.trim(tf, 0.0, Vector3.ZERO)
		r.trim_cyc = Vector2(tf.cyclic_lon, tf.cyclic_lat)
		log_line("    hover trim cyclic: lon %+.2f lat %+.2f pedal %+.2f collective %.2f" % [tf.cyclic_lon, tf.cyclic_lat, tf.pedal, tf.collective])
	var n := 0
	var max_jump := 0.0
	var prev_hold: Dictionary = main.lessons.hands.hold.duplicate()
	var prev_c := [main.controls.collective, main.controls.cyclic_lon, main.controls.cyclic_lat, main.controls.pedal]
	var cues := {}
	var last_msg := ""
	var finite := true
	while not main.lessons.done and n * DT < limit_s:
		tick(r)
		n += 1
		var hold: Dictionary = main.lessons.hands.hold
		var c := [main.controls.collective, main.controls.cyclic_lon, main.controls.cyclic_lat, main.controls.pedal]
		if hold != prev_hold:
			for i in 4:
				max_jump = maxf(max_jump, absf(c[i] - prev_c[i]))
			prev_hold = hold.duplicate()
		prev_c = c
		if main.instructor.message != last_msg:
			last_msg = main.instructor.message
			cues[main.instructor.last_key] = true
		if is_nan(main.fdm.pos.y):
			finite = false
			break
	var L = main.lessons
	var out := {"done": L.done, "score": L.score, "time": n * DT, "result": L.result, "jump": max_jump, "cues": cues, "faults": main.coach.faults.duplicate(), "finite": finite}
	log_line("    %s%s: done=%s score=%d time=%.0f s" % [id, " (sloppy)" if sloppy else "", L.done, L.score, n * DT])
	for ln in L.result.split("\n"):
		log_line("      | " + ln)
	return out

var _started := false
var _k := 0

func _initialize() -> void:
	log_line("AB206 REALSIM training-level tests  %s" % Time.get_datetime_string_from_system())
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _run() -> void:
	main.instructor.voice = false
	main.lessons.progress_path = "user://progress_test.cfg"     # never touch the pilot's real scores
	main.lessons.progress = {}
	main.lessons.auto_assist = false      # [L1]/[L2] fly with no assist; [L4] tests the assists
	main.set_assist(0, true)
	var only := OS.get_environment("AB206_LESSON")

	log_line("\n[L0] Coach direction words (aircraft frame)")
	check("drift forward-left reads 'forward and left'", Coach.dir_words(Vector2(1.0, -1.0)) == "forward and left", Coach.dir_words(Vector2(1.0, -1.0)))
	check("correction for drifting right is 'left'", Coach.opposite_words(Vector2(0.1, 1.0)) == "left", Coach.opposite_words(Vector2(0.1, 1.0)))

	log_line("\n[L1] Robot student flies every hover and landing level")
	var ids := ["h_coll", "h_ped", "h_cyc", "h_full", "h_turns", "h_wind", "l_takeoff", "l_land", "l_taxi", "l_approach"]
	var limits := {"h_coll": 120.0, "h_ped": 120.0, "h_cyc": 120.0, "h_full": 120.0, "h_turns": 180.0, "h_wind": 120.0, "l_takeoff": 120.0, "l_land": 90.0, "l_taxi": 150.0, "l_approach": 240.0}
	for id in ids:
		if only != "" and only != id:
			continue
		var r := fly(id, limits[id])
		var min_score := 70 if id == "l_approach" else 85
		check(id + " completes", r["done"], "%.0f s" % r["time"])
		check(id + " good flying scores %d+" % min_score, r["score"] >= min_score, "score %d" % r["score"])
		check(id + " stays finite", r["finite"], "")
		if id in ["h_coll", "h_ped", "h_cyc"]:
			check(id + " hand-over is bumpless (controls follow the instructor)", r["jump"] < 0.02, "largest control jump at a hand-over %.3f" % r["jump"])
			main.lessons.take_control()
			check(id + ": T gives all controls back", not main.lessons.hands.any(), "")
		check(id + " progress saved", main.lessons.best(id) == r["score"], "best %d" % main.lessons.best(id))
		main.lessons.stop()

	if only == "" or only == "sloppy":
		log_line("\n[L2] Sloppy student: faults cost points and the coach says why")
		var good: int = main.lessons.best("h_full")
		var r2 := fly("h_full", 200.0, true)
		check("sloppy hover scores lower than the good one", r2["score"] < good - 10, "%d vs %d" % [r2["score"], good])
		var f2: Dictionary = r2["faults"]
		check("coach flagged drift or position faults", f2.has("drift") or f2.has("off_spot") or f2.has("overshoot"), str(f2))
		check("coach flagged over-controlling", f2.has("pio"), str(f2))
		check("debrief lists what to work on", "WORK ON" in r2["result"], "")
		check("best score kept (not overwritten by a worse run)", main.lessons.best("h_full") == good, "best %d" % main.lessons.best("h_full"))
		main.lessons.stop()

		log_line("\n[L3] Lesson weather is restored afterwards")
		var a = main.fdm.atmo
		a.wind_speed_kt = 3.0
		a.wind_from_deg = 200.0
		main.lessons.start("h_wind")
		var during: float = a.wind_speed_kt
		main.lessons.stop()
		check("crosswind level sets 12 kt, then restores the user's wind", during == 12.0 and a.wind_speed_kt == 3.0 and a.wind_from_deg == 200.0, "during %.0f kt, after %.0f kt from %03.0f" % [during, a.wind_speed_kt, a.wind_from_deg])

	if only == "" or only == "assist":
		_assist_tests()

	if only == "" or only == "refs":
		_refs_tests()

	if only == "" or only == "choice":
		_choice_tests()

	if only == "" or only == "mentor":
		_mentor_tests()

	log_line("\nRESULT: %d passed, %d failed" % [passed, failed])
	var fa := FileAccess.open("user://lesson_test_results.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(lines))
	quit(0 if failed == 0 else 1)

func _hover_here(level: int, wind_kt: float, gust: float) -> void:
	main.lessons.stop()
	main.fdm.atmo.wind_from_deg = 30.0
	main.fdm.atmo.wind_speed_kt = wind_kt
	main.fdm.atmo.gust_intensity = gust
	var pad: Vector3 = main.world.terrain.pads["Main helipad"]["pos"]
	main._place(pad + Vector3(0.0, 1.0 + main.fdm.cg_height, 0.0), 0.0, 0.0)
	main.set_assist(level, true)
	for i in 3:
		tick(null)

func _body_speed() -> Vector2:
	return main.lessons.hands.body_xy(main.fdm.vel)

func _assist_tests() -> void:
	log_line("\n[L4] Training assists (learning aids, not on the real 206)")
	var c = main.controls
	var f = main.fdm
	# level 3: hands off = holds the spot in gusty wind; stick = speed over the ground
	_hover_here(3, 10.0, 0.4)
	var p0: Vector3 = f.pos
	var maxd := 0.0
	var max_h := 0.0
	for i in int(40.0 / DT):
		tick(null)
		maxd = maxf(maxd, Vector2(f.pos.x - p0.x, f.pos.z - p0.z).length())
		max_h = maxf(max_h, absf(f.agl - 1.0))
	check("assist 3, hands off for 40 s in 10 kt gusty wind: stays on the spot", maxd < 1.5, "max drift %.2f m" % maxd)
	c.stick_mouse = Vector2(0.0, 0.5)
	for i in int(6.0 / DT):
		tick(null)
	var vf := _body_speed().x
	check("assist 3, half forward stick = about 1.5 m/s forward", vf > 1.0 and vf < 2.0, "%.2f m/s" % vf)
	c.stick_mouse = Vector2.ZERO
	var pc: Vector3 = f.pos
	for i in int(8.0 / DT):
		tick(null)
	check("assist 3, stick centred again: stops and stays close", _body_speed().length() < 0.3 and Vector2(f.pos.x - pc.x, f.pos.z - pc.z).length() < 3.0, "%.2f m/s, %.1f m from where the stick was centred, after 8 s" % [_body_speed().length(), Vector2(f.pos.x - pc.x, f.pos.z - pc.z).length()])
	# switching the assist off in a hover: the cyclic does not jump
	var lon0: float = f.cyclic_lon
	var lat0: float = f.cyclic_lat
	main.set_assist(0, true)
	tick(null)
	check("assist 3 -> off in a hover: no cyclic jump", absf(f.cyclic_lon - lon0) < 0.03 and absf(f.cyclic_lat - lat0) < 0.03, "jump %.3f / %.3f" % [f.cyclic_lon - lon0, f.cyclic_lat - lat0])
	# level 2: a sideways drift dies out by itself with the stick centred
	_hover_here(2, 0.0, 0.0)
	f.vel = Vector3(2.0, 0.0, 0.0)
	c.stick_mouse = Vector2.ZERO
	for i in int(12.0 / DT):
		tick(null)
	check("assist 2, 2 m/s drift with stick centred dies out", _body_speed().length() < 0.5 and absf(f.roll_deg()) < 4.0, "%.2f m/s, roll %.1f deg after 12 s" % [_body_speed().length(), f.roll_deg()])
	# level 0 for comparison: the same drift keeps going / grows (the real thing)
	_hover_here(0, 0.0, 0.0)
	var lon_h: float = f.cyclic_lon
	f.vel = Vector3(2.0, 0.0, 0.0)
	for i in int(6.0 / DT):
		tick(null)
	check("no assist: the same drift is still there after 6 s (real helicopter: you must stop it)", _body_speed().length() > 0.7, "%.2f m/s after 6 s" % _body_speed().length())
	# above the hover band assist 3 acts as damping
	_hover_here(3, 0.0, 0.0)
	main.assist.apply(DT, true, true)
	f.pos.y += 60.0
	tick(null)
	check("assist 3 above 30 m falls back to damping", main.assist.active_level == 1, "active level %d" % main.assist.active_level)
	main.set_assist(0, true)

	log_line("\n[L5] Assisted lessons, fading out, ghost stick")
	var r0 := fly("h_full", 120.0, false, "novice")
	main.lessons.stop()
	main.lessons.auto_assist = true
	main.lessons.progress.erase("h_full_assist")
	check("h_full starts with assist 3 for a new pilot", main.lessons.next_assist("h_full") == 3, "assist %d" % main.lessons.next_assist("h_full"))
	var r3 := fly("h_full", 200.0, false, "novice_assisted")
	check("beginner (late, no attitude feel) with assist 3 scores much better than without", r3["score"] >= r0["score"] + 25, "%d vs %d" % [r3["score"], r0["score"]])
	check("score 80+ with assist 3 -> next try uses assist 2", r3["score"] < 80 or main.lessons.next_assist("h_full") == 2, "score %d, next assist %d" % [r3["score"], main.lessons.next_assist("h_full")])
	for lvl in [2, 1]:
		main.lessons.progress["h_full_assist"] = lvl
		var rl := fly("h_full", 150.0, false, "novice_assisted")
		log_line("    (same beginner with assist %d: %s)" % [lvl, ("score %d" % rl["score"]) if rl["done"] else "not completed in 150 s"])
		if lvl == 2:
			check("beginner also manages with assist 2 (the next step)", rl["done"] and rl["score"] >= 60, "score %d" % rl["score"])
		main.lessons.stop()
	check("assisted score is kept apart from the real best", main.lessons.progress.has("h_full@3"), str(main.lessons.progress.get("h_full@3", -1)))
	main.lessons.stop()
	check("assist level given back after the lesson", main.assist.level == 0, "level %d" % main.assist.level)
	main.lessons.auto_assist = false
	var rg := fly("h_full", 200.0, false, "ghost")
	check("following only the ghost markers flies a good hover (no assist)", rg["done"] and rg["score"] >= 70, "score %d in %.0f s" % [rg["score"], rg["time"]])
	main.lessons.stop()

## Put the aircraft over the lesson spot (+ offsets in the lesson's frame: forward, right, up), level.
func _refs_at(fwd: float, right: float, up: float) -> Vector3:
	var pad: Vector3 = main.world.terrain.pads["Main helipad"]["pos"]
	var f = main.fdm
	main._place(pad + Vector3(right, 1.0 + up + f.cg_height, -fwd), 0.0, 0.0)
	main._process(DT)
	return Transform3D(f.basis, f.pos) * main.cam_rig.eye

func _refs_tests() -> void:
	log_line("\n[L6] Outside hover references (sight gates)")
	main.lessons.stop()
	main.refs.enabled = true
	main.lessons.start("h_full")
	var R = main.refs
	var eye := _refs_at(0.0, 0.0, 0.0)
	check("gates appear in a hover lesson", R.visible, "")
	check("on the spot: both bars green", R.status.get("front") == "green" and R.status.get("side") == "green", str(R.status))
	check("on the spot: far board centred in the front gate", absf(R.sight_offset("front", eye)) < 0.05, "%.3f" % R.sight_offset("front", eye))
	check("on the spot: far board centred in the side gate", absf(R.sight_offset("side", eye)) < 0.05, "%.3f" % R.sight_offset("side", eye))
	check("on the spot: bar lies on the board line (height)", absf(R.sight_height("front", eye)) < 0.1, "%.2f deg" % R.sight_height("front", eye))
	eye = _refs_at(0.0, 1.0, 0.0)
	check("1 m right (inside 4 ft): board still inside the front gate, bar green", absf(R.sight_offset("front", eye)) < 1.0 and R.status["front"] == "green", "%.2f, %s" % [R.sight_offset("front", eye), R.status["front"]])
	eye = _refs_at(0.0, -2.0, 0.0)
	check("2 m left: board outside the front gate, bar amber", absf(R.sight_offset("front", eye)) > 1.0 and R.status["front"] == "amber", "%.2f, %s" % [R.sight_offset("front", eye), R.status["front"]])
	eye = _refs_at(2.0, 0.0, 0.0)
	check("2 m forward: board outside the side gate, side bar amber, front bar still green", absf(R.sight_offset("side", eye)) > 1.0 and R.status["side"] == "amber" and R.status["front"] == "green", "%.2f, %s/%s" % [R.sight_offset("side", eye), R.status["front"], R.status["side"]])
	eye = _refs_at(-1.0, 0.0, 0.0)
	check("1 m back: board inside the side gate", absf(R.sight_offset("side", eye)) < 1.0, "%.2f" % R.sight_offset("side", eye))
	eye = _refs_at(0.0, 0.0, 0.7)
	var hs: float = R.sight_height("front", eye)
	check("0.7 m too high: board line appears ABOVE the bar, front bar not green", hs > 0.8 and R.status["front"] != "green", "%.2f deg, %s" % [hs, R.status["front"]])
	eye = _refs_at(0.0, 0.0, -0.4)
	check("too low: board line appears BELOW the bar", R.sight_height("front", eye) < -0.4, "%.2f deg" % R.sight_height("front", eye))
	eye = _refs_at(0.0, 5.0, 0.0)
	check("5 m off: bar red", R.status["front"] == "red", R.status["front"])
	_refs_at(40.0, 0.0, 0.0)
	check("gates hide when far from the spot", not R.visible, "")
	R.enabled = false
	_refs_at(0.0, 0.0, 0.0)
	check("B switches the gates off", not R.visible, "")
	R.enabled = true
	main.lessons.stop()
	main._process(DT)
	check("no gates outside lessons", not R.visible, "")
	main.lessons.start("l_taxi")
	main._process(DT)
	check("gates are not in the way during the hover-taxi lesson start", true, "phase %s, visible %s" % [main.coach.ctx.get("phase", ""), R.visible])
	main.lessons.stop()

func _choice_tests() -> void:
	log_line("\n[L7] You choose the assist level (default) - it stays where you set it")
	main.lessons.stop()
	main.lessons.auto_assist = false
	main.lessons.progress["h_full_assist"] = 3
	main.set_assist(2, true)
	main.lessons.start("h_full")
	check("lesson keeps your assist 2 (does not pick its own 3)", main.assist.level == 2, "level %d" % main.assist.level)
	check("lesson start says it is your choice", "your choice" in main.instructor.message, "")
	main.set_assist(1, true)            # H in flight
	main.lessons.stop()
	check("after the lesson the assist stays where you left it (1)", main.assist.level == 1, "level %d" % main.assist.level)
	main.set_assist(0, true)
	main.lessons.start("h_cyc")
	check("assist OFF stays OFF in a lesson that would start at 3", main.assist.level == 0, "level %d" % main.assist.level)
	main.lessons.stop()
	main.lessons.auto_assist = true
	main.set_assist(1, true)
	main.lessons.start("h_full")
	check("automatic mode (optional) still picks the lesson's level", main.assist.level == 3, "level %d" % main.assist.level)
	main.lessons.stop()
	check("automatic mode gives your level back afterwards", main.assist.level == 1, "level %d" % main.assist.level)
	main.lessons.auto_assist = false
	main.set_assist(0, true)

## H0: fly with a robot until done or time out; returns stats about the take-over loop.
func _fly_mentor(axes: String, mode: String, limit_s: float) -> Dictionary:
	main.lessons.mentor_axes = axes
	main.lessons.start("h_mentor")
	var r := Robot.new(main)
	r.novice = mode == "novice"
	var n := 0
	var max_jump := 0.0
	var prev_ph: int = main.lessons.phase
	var prev_c := [main.fdm.collective, main.fdm.cyclic_lon, main.fdm.cyclic_lat, main.fdm.pedal]
	var give_dist := []
	var finite := true
	while not main.lessons.done and n * DT < limit_s:
		tick(r)
		n += 1
		var L = main.lessons
		var c := [main.fdm.collective, main.fdm.cyclic_lon, main.fdm.cyclic_lat, main.fdm.pedal]
		if L.phase != prev_ph:
			for i in 4:
				max_jump = maxf(max_jump, absf(c[i] - prev_c[i]))
			if L.phase == 1:
				var p: Vector3 = main.world.terrain.pads["Main helipad"]["pos"]
				give_dist.append(Vector2(main.fdm.pos.x - p.x, main.fdm.pos.z - p.z).length())
			prev_ph = L.phase
		prev_c = c
		if is_nan(main.fdm.pos.y):
			finite = false
			break
	var L = main.lessons
	var out := {"done": L.done, "score": L.score, "time": n * DT, "attempts": int(L._sc.get("attempt", 0)), "takeovers": int(L._sc.get("takeovers", 0)), "jump": max_jump, "give": give_dist, "finite": finite, "hold": L.hands.hold.duplicate(), "result": L.result}
	log_line("    h_mentor %s (%s): done=%s score=%d attempts=%d take-overs=%d time=%.0f s" % [axes, mode, L.done, L.score, out["attempts"], out["takeovers"], n * DT])
	return out

func _mentor_tests() -> void:
	log_line("\n[L8] H0 instructor hover: I have control / you have control")
	main.lessons.stop()
	main.lessons.auto_assist = false
	main.set_assist(0, true)
	main.lessons.mentor_axes = "all"
	main.lessons.start("h_mentor")
	check("H0 starts with the instructor holding every control", main.lessons.hands.hold == {"coll": true, "ped": true, "cyc": true}, str(main.lessons.hands.hold))
	main.lessons.stop()
	var g := _fly_mentor("all", "good", 120.0)
	check("good student: hand-over after the instructor steadies it, done with no take-over", g["done"] and g["takeovers"] == 0 and g["attempts"] == 1, "attempts %d, take-overs %d" % [g["attempts"], g["takeovers"]])
	check("good student scores 85+", g["score"] >= 85, "score %d" % g["score"])
	main.lessons.stop()
	var b := _fly_mentor("all", "novice", 150.0)
	check("beginner: the instructor takes over and hands back again (several attempts)", b["takeovers"] >= 2 and b["attempts"] >= 3, "attempts %d, take-overs %d" % [b["attempts"], b["takeovers"]])
	var gd: Array = b["give"]
	var worst := 0.0
	for d in gd:
		worst = maxf(worst, d)
	check("every hand-over happens steady over the spot (< 0.4 m)", gd.size() >= 3 and worst < 0.4, "%d hand-overs, worst %.2f m" % [gd.size(), worst])
	check("hand-overs and take-overs are bumpless", b["jump"] < 0.03, "largest control jump %.3f" % b["jump"])
	check("stays finite", b["finite"], "")
	main.lessons.stop()
	var c := _fly_mentor("cyc", "novice", 150.0)
	check("cyclic-only: the instructor keeps collective and pedals while you have the cyclic", c["attempts"] >= 1 and (c["hold"]["coll"] and c["hold"]["ped"]), str(c["hold"]))
	main.lessons.stop()
	main.set_assist(3, true)
	var a3 := _fly_mentor("all", "novice", 200.0)
	check("beginner with assist 3 gets through with fewer take-overs", a3["done"] or a3["takeovers"] < b["takeovers"], "done %s, take-overs %d vs %d" % [a3["done"], a3["takeovers"], b["takeovers"]])
	main.lessons.stop()
	main.set_assist(0, true)
	for ax in ["coll", "ped"]:
		var r := _fly_mentor(ax, "good", 120.0)
		check("H0 %s only: good student completes" % ax, r["done"] and r["takeovers"] == 0, "score %d, take-overs %d" % [r["score"], r["takeovers"]])
		main.lessons.stop()
