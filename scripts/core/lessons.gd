extends RefCounted
## Graded training levels (pause menu > Lessons). Every objective is checked against the
## flight-model state; nothing completes on a timer alone.
##
## Stationary hover is taught "part-task", the way instructors do it on dual controls:
## the instructor's hands (hover_hold.gd) fly some controls while you fly one, then you get
## them all. Take-off and landing levels then build on that.
##
## Tolerances: the "ACS" figures are from the FAA Private Pilot Helicopter Airman
## Certification Standards FAA-S-ACS-15 (Nov 2023): hover height +/- half of the hover height,
## position within 4 ft (1.2 m), heading +/-10 deg, touchdown within 4 ft of the point.
## Everything else (pass boxes, sink-rate ratings, score weights) is a simulator choice.
## Your school's standards and your instructor always come first.

const Landing = preload("res://scripts/core/landing_rating.gd")
const HoverHold = preload("res://scripts/core/hover_hold.gd")
const HeliFDM = preload("res://scripts/fdm/heli_fdm.gd")
const Trim = preload("res://scripts/fdm/trim.gd")

## Training assist each level starts with (see training_assist.gd). Score 80+ and the next try
## uses one level less, until you fly it with no assist at all. H1/H2: the instructor has the cyclic.
const START_ASSIST := {"h_cyc": 3, "h_full": 3, "h_turns": 2, "h_wind": 2, "l_takeoff": 2, "l_land": 2, "l_taxi": 2, "l_approach": 1}
const STEP_DOWN_SCORE := 80

const PROGRESS_PATH := "user://progress.cfg"
const ACS_POS := 1.2192          # 4 ft
const PASS_POS := 3.0            # simulator pass box, m
const HOVER_H := 1.0             # training hover skid height, m (about 3 ft; your school may use 2-5 ft)

## id, menu title, description, group
const LIST := [
	["h_mentor", "H0  Instructor hover: I have control / you have control", "Like the real first lesson: the instructor steadies it over the spot and gives you the controls. Lose it and the instructor takes over, brings it back and gives it to you again - until you hold it 30 s.", 0],
	["h_coll", "H1  Collective: hold the height", "The instructor flies cyclic and pedals. You fly only the collective: hold 1 m, climb to 2 m, back to 1 m, then set it down.", 0],
	["h_ped", "H2  Pedals: hold the heading", "The instructor flies collective and cyclic. You fly the pedals: hold 360, pivot to 270, back to 360.", 0],
	["h_cyc", "H3  Cyclic: hold the spot", "The instructor flies collective and pedals. You fly the cyclic: stay over the spot, move 5 m right and back.", 0],
	["h_full", "H4  Full hover: all controls", "You have all the controls: 1 m, over the spot, heading 360, for 40 s.", 0],
	["h_turns", "H5  Hovering turns", "360 deg pivot turns left and right over the spot, stopping on heading 360 (ACS: within 10 deg).", 0],
	["h_wind", "H6  Hover in a gusty crosswind", "12 kt from the right with gusts. Hold the hover for 30 s.", 0],
	["l_takeoff", "L1  Vertical take-off to a hover", "From the pad: lift off smoothly with no drift and no aft movement, and settle at 1 m.", 1],
	["l_land", "L2  Vertical landing from a hover", "From a 1 m hover: descend vertically onto the spot, soft and with no movement, then collective fully down.", 1],
	["l_taxi", "L3  Hover-taxi to a spot and land", "Hover-taxi 22 m north along the line to the yellow spot, stop over it and land on it.", 1],
	["l_approach", "L4  Normal approach to the pad", "From 500 ft and 60 kt: fly a ~10 deg approach, slow down progressively, avoid vortex ring state, end in a hover over the pad.", 1],
	["transit", "E1  Pad to Field LZ", "Take off, fly 1.5 km north to the Field LZ and land on it.", 2],
	["vrs", "E2  Vortex ring state", "Get into VRS on purpose at a safe height, recognise it, recover with forward cyclic.", 2],
	["auto", "E3  Autorotation to the ground", "Simulated engine failure at 2,500 ft: autorotate and land without power.", 2],
]
const GROUPS := ["Stationary hover (part-task, then full)", "Take-off and landing", "Other exercises"]

const TIPS := {
	"drift": "Drift: the aircraft goes where the disc tilts. Small cyclic pressure, then take it out early.",
	"off_spot": "Position: pick two outside references (one far ahead, one to the side) to see drift sooner.",
	"overshoot": "Overshooting: start removing the correction halfway back to the spot.",
	"pio": "Over-controlling: freeze, then smaller and slower inputs. Pressure, not movement.",
	"high": "Height: tiny collective changes and wait 1-2 s for the result.",
	"low": "Height: tiny collective changes and wait 1-2 s for the result.",
	"climb": "Height: look outside at the horizon to notice climb/sink early.",
	"sink": "Height: look outside at the horizon to notice climb/sink early.",
	"hdg_r": "Heading: pick a reference straight ahead on the horizon and keep the nose on it.",
	"hdg_l": "Heading: pick a reference straight ahead on the horizon and keep the nose on it.",
	"yaw": "Yaw: stop a swing early with a small pedal input, then neutralise.",
	"couple": "Collective and pedals go together: up = left pedal, down = right pedal.",
	"sink_fast": "Touchdown: slow the descent in the last metre; arrive below 0.5 m/s.",
	"td_drift": "Touchdown: zero movement over the ground before the skids touch (dynamic rollover).",
	"coll_down": "After touchdown: collective fully down, smoothly, cyclic centred.",
	"app_high": "Approach angle: lower the collective a little earlier when the pad rises in the windscreen.",
	"app_low": "Approach angle: raise collective when the pad sinks in the windscreen; do not drag in low.",
	"app_fast": "Closure: walking/jogging pace over the last 50 m; slow down progressively with aft cyclic.",
	"app_slow": "Closure: keep some airspeed until the last 100-200 m; low speed + high sink = VRS risk.",
	"vrs": "Approach: keep the descent below ~300-500 ft/min whenever airspeed is below ~20 kt.",
	"taxi_fast": "Hover-taxi: no faster than a brisk walk.",
	"taxi_track": "Track: keep the line under the aircraft centre; correct with small lateral cyclic.",
}

var main
var hands                      # HoverHold - the instructor's hands
var coach                      # coach.gd, set by main
var id := ""
var phase := 0
var t := 0.0
var pt := 0.0                  # time in the current phase
var objective := ""            # shown on the HUD
var result := ""               # debrief text when finished
var done := false
var score := -1
var progress := {}             # id -> best score
var progress_path := PROGRESS_PATH
var guide := {}                # hover guide data for the HUD
var assist                     # training_assist.gd, set by main
var auto_assist := false       # true: lessons choose the assist level and fade it out; false: the pilot chooses (H / menu) and it stays
var lesson_assist := 0         # assist level used for this attempt (highest used)
var ghost_hh                   # instructor's suggestion ("ghost stick"), never applied
var _trim := {}                # hover trim for this lesson (collective, cyclic, pedal)
var _user_assist := -1
var _acc := 0.0
var _stats := {}
var _sc := {}
var _saved_weather = null
var _spot := Vector3.ZERO
var _pad := Vector3.ZERO
var mentor_axes := "all"       # H0: which controls you get: all / cyc / coll / ped
const MENTOR_HOLD := 30.0      # H0: seconds you must hold it without a take-over
const MENTOR_AXES := {"all": ["all controls", "You have control."], "cyc": ["the cyclic", "You have the cyclic."], "coll": ["the collective", "You have the collective."], "ped": ["the pedals", "You have the pedals."]}

func _init() -> void:
	_load_progress()

func lesson_title() -> String:
	for l in LIST:
		if l[0] == id:
			return l[1]
	return ""

static func grade(s: int) -> String:
	if s >= 90:
		return "A - at ACS standard"
	if s >= 75:
		return "B - good"
	if s >= 60:
		return "C - pass"
	return "D - repeat"

## Best score flown with NO assist (the real standard).
func best(lesson_id: String) -> int:
	return int(progress.get(lesson_id, -1))

## Assist level the next attempt will start with.
func next_assist(lesson_id: String) -> int:
	return int(progress.get(lesson_id + "_assist", START_ASSIST.get(lesson_id, 0)))

func best_assisted(lesson_id: String) -> String:
	for l in [1, 2, 3]:
		if progress.has("%s@%d" % [lesson_id, l]):
			return "%d with assist %d" % [int(progress["%s@%d" % [lesson_id, l]]), l]
	return ""

## Hover trim (what a trained pilot "knows"): trims a copy of the aircraft in a 1 m hover over
## the spot in this lesson's wind. Used for the ghost stick.
func _compute_trim(spot: Vector3) -> void:
	var tf = HeliFDM.new(main.data)
	tf.ground = main.world.terrain
	tf.set_mass(main.fdm.mass)
	tf.atmo.wind_from_deg = main.fdm.atmo.wind_from_deg
	tf.atmo.wind_speed_kt = main.fdm.atmo.wind_speed_kt
	tf.atmo.gust_intensity = 0.0
	tf.atmo.temp_offset_c = main.fdm.atmo.temp_offset_c
	tf.pos = spot + Vector3(0.0, HOVER_H + tf.cg_height, 0.0)
	tf.reset_dynamic_state()
	Trim.trim(tf, 0.0, Vector3.ZERO)
	_trim = {"coll": tf.collective, "lon": tf.cyclic_lon, "lat": tf.cyclic_lat, "ped": tf.pedal}

## Ghost stick: where the instructor would put YOUR controls right now (only the axes you fly).
func suggest(dt: float) -> Dictionary:
	if id == "" or done or _trim.is_empty() or coach == null:
		return {}
	var ph: String = coach.ctx.get("phase", "off")
	if ph in ["off", "approach", ""]:
		return {}
	var f = main.fdm
	if ghost_hh == null:
		ghost_hh = HoverHold.new(f)
	var g = ghost_hh
	g.hold = {"coll": true, "ped": true, "cyc": true}
	var tgt = coach.ctx.get("target")
	g.target = tgt if tgt != null else (main.world.hover_spot if ph == "taxi" else f.pos)
	var h: float = coach.ctx.get("height", NAN)
	g.height = h if not is_nan(h) else f.agl
	var hd: float = coach.ctx.get("hdg", NAN)
	g.heading = hd if not is_nan(hd) else f.heading_deg()
	g.vz_override = -0.3 if ph == "land" else NAN
	g.max_speed = 1.3
	g.reset_to_trim(_trim["coll"], _trim["lon"], _trim["lat"], _trim["ped"])
	g.update(dt, 0.0, 0.0, 0.0, 0.0)
	var out := {}
	if not hands.hold["coll"]:
		out["coll"] = g.coll
	if not hands.hold["ped"]:
		out["ped"] = g.ped
	if not hands.hold["cyc"]:
		if assist != null and assist.active_level == 3:
			var pe: Vector2 = g.body_xy(g.target - f.pos)
			var v := (pe * 0.45).limit_length(3.0) / 3.0
			out["lon"] = v.x
			out["lat"] = v.y
		elif assist == null or assist.active_level < 2:
			out["lon"] = g.lon
			out["lat"] = g.lat
	return out

# -------------------------------------------------------------------- helpers
func _set_hands(coll: bool, ped: bool, cyc: bool) -> void:
	hands.hold = {"coll": coll, "ped": ped, "cyc": cyc}
	var c = main.controls
	hands.sync(c.collective, c.cyclic_lon, c.cyclic_lat, c.pedal)
	hands.vz_override = NAN
	hands.vel_cmd_override = Vector2(NAN, NAN)

func _owner_text() -> String:
	if not hands.any():
		return "YOU have all controls."
	var me := []
	var him := []
	for k in [["coll", "collective"], ["ped", "pedals"], ["cyc", "cyclic"]]:
		if hands.hold[k[0]]:
			him.append(k[1])
		else:
			me.append(k[1])
	return "YOU: %s    instructor: %s" % [", ".join(me) if me.size() > 0 else "-", ", ".join(him)]

func _weather(from_deg: float, kt: float, gust: float) -> void:
	var a = main.fdm.atmo
	if _saved_weather == null:
		_saved_weather = [a.wind_from_deg, a.wind_speed_kt, a.gust_intensity]
	a.wind_from_deg = from_deg
	a.wind_speed_kt = kt
	a.gust_intensity = gust

func _restore_weather() -> void:
	if _saved_weather != null:
		var a = main.fdm.atmo
		a.wind_from_deg = _saved_weather[0]
		a.wind_speed_kt = _saved_weather[1]
		a.gust_intensity = _saved_weather[2]
		_saved_weather = null

func _hover_place(spot: Vector3, h: float, hdg := 0.0) -> void:
	main._place(spot + Vector3(0.0, h + main.fdm.cg_height, 0.0), hdg, 0.0)

func _ctx(ph: String, target, h: float, hdg: float, tol_pos := ACS_POS, tol_h := 0.5, tol_hdg := 10.0) -> void:
	coach.ctx = {"phase": ph, "target": target, "height": h, "hdg": hdg, "tol_pos": tol_pos, "tol_h": tol_h, "tol_hdg": tol_hdg,
		"student": {"coll": not hands.hold["coll"], "ped": not hands.hold["ped"], "cyc": not hands.hold["cyc"]}}
	guide = {"target": target, "height": h, "tol_h": tol_h, "hdg": hdg, "tol_hdg": tol_hdg, "tol_pos": ACS_POS, "pass_pos": PASS_POS, "owner": _owner_text()}

func _track(key: String, ok: bool, dt: float) -> void:
	_sc[key + "_t"] = float(_sc.get(key + "_t", 0.0)) + dt
	if ok:
		_sc[key + "_ok"] = float(_sc.get(key + "_ok", 0.0)) + dt

func _frac(key: String) -> float:
	var tt: float = _sc.get(key + "_t", 0.0)
	return float(_sc.get(key + "_ok", 0.0)) / tt if tt > 0.0 else 0.0

func _maxs(key: String, v: float) -> void:
	_sc[key] = maxf(float(_sc.get(key, -1e9)), v)

func _rms(key: String, e: float, dt: float) -> void:
	_sc[key + "_s2"] = float(_sc.get(key + "_s2", 0.0)) + e * e * dt
	_sc[key + "_st"] = float(_sc.get(key + "_st", 0.0)) + dt

func _rmsv(key: String) -> float:
	var tt: float = _sc.get(key + "_st", 0.0)
	return sqrt(float(_sc.get(key + "_s2", 0.0)) / tt) if tt > 0.0 else 0.0

## 1 at or below `good`, 0 at or above `bad`, linear in between.
static func ramp(v: float, good: float, bad: float) -> float:
	return clampf((bad - v) / (bad - good), 0.0, 1.0)

static func td_score(sink: float) -> float:
	if sink <= 0.3:
		return 1.0
	if sink <= 0.5:
		return 0.85
	if sink <= 1.0:
		return 0.55
	if sink <= 1.5:
		return 0.3
	return 0.0

static func bar(v: float, total: float) -> String:
	var n := int(clampf(v / maxf(total, 0.01), 0.0, 1.0) * 20.0)
	return "[" + "#".repeat(n) + "-".repeat(20 - n) + "] %.0f / %.0f s" % [minf(v, total), total]

func _err(f, spot: Vector3, h: float, hdg: float) -> Dictionary:
	return {"dist": Vector2(f.pos.x - spot.x, f.pos.z - spot.z).length(), "h": f.agl - h,
		"hdg": wrapf(f.heading_deg() - hdg, -180.0, 180.0)}

func _in_box(e: Dictionary, pos_tol: float, h_tol: float, hdg_tol := 10.0) -> bool:
	return float(e["dist"]) <= pos_tol and absf(float(e["h"])) <= h_tol and absf(float(e["hdg"])) <= hdg_tol

func _next(text := "", speech := "") -> void:
	phase += 1
	pt = 0.0
	_acc = 0.0
	if text != "":
		main.instructor.force(text, speech)

# ---------------------------------------------------------------------- start
func start(lesson_id: String) -> void:
	if id != "":
		stop()
	id = lesson_id
	phase = 0
	t = 0.0
	pt = 0.0
	_acc = 0.0
	_sc = {}
	_stats = {"max_tq": 0.0, "nr_low": 0.0, "nr_high": 0.0, "max_drift": 0.0, "h_err": 0.0, "n": 0}
	done = false
	score = -1
	result = ""
	guide = {}
	coach.reset()
	_pad = main.world.terrain.pads["Main helipad"]["pos"]
	_spot = _pad
	_set_hands(false, false, false)
	var I = main.instructor
	match id:
		"h_mentor":
			_weather(0.0, 5.0, 0.15)
			_hover_place(_pad, HOVER_H)
			_mentor_take("")
			_sc["attempt"] = 0
			_sc["takeovers"] = 0
			_sc["best"] = 0.0
			I.force("H0 - INSTRUCTOR HOVER (%s). \"I have control.\" I steady the helicopter over the spot, 1 m, heading 360, then give you %s. Keep the SAME references and the same height. If it gets away from you I take it back, bring it back to the spot and give it to you again. Hold it %d s to finish." % [MENTOR_AXES[mentor_axes][0], MENTOR_AXES[mentor_axes][0], int(MENTOR_HOLD)], "I have control. I will steady it, then give it to you.")
		"h_coll":
			_weather(0.0, 4.0, 0.1)
			_hover_place(_pad, HOVER_H)
			_set_hands(false, true, true)
			I.force("H1 - COLLECTIVE ONLY. I have the cyclic and pedals; you have the collective. Hold the skids 1 m above the pad. Watch the horizon and the pad edge: tiny, slow collective movements (W/S or wheel), then wait for the helicopter to respond.", "You have the collective. Hold one metre.")
		"h_ped":
			_weather(0.0, 4.0, 0.1)
			_hover_place(_pad, HOVER_H)
			_set_hands(true, false, true)
			I.force("H2 - PEDALS ONLY. I have the collective and the cyclic; you have the pedals (A/D, trim Q/E). Keep the nose on heading 360: pick a point on the horizon straight ahead and keep it there.", "You have the pedals. Hold heading three six zero.")
		"h_cyc":
			_weather(0.0, 5.0, 0.15)
			_hover_place(_pad, HOVER_H)
			_set_hands(true, true, false)
			I.force("H3 - CYCLIC ONLY. I have the collective and pedals; you have the cyclic. Stay over the pad centre. The cyclic is the hardest: tiny pressures, and expect a lag of about a second before the aircraft moves.", "You have the cyclic. Stay over the spot.")
		"h_full":
			_weather(0.0, 5.0, 0.15)
			_hover_place(_pad, HOVER_H)
			I.force("H4 - FULL HOVER. You have control: all three. Hold 1 m over the pad centre, heading 360. Scan outside: horizon for attitude and heading, pad edge for height and drift.", "You have control.")
		"h_turns":
			_weather(0.0, 5.0, 0.1)
			_hover_place(_pad, HOVER_H)
			I.force("H5 - HOVERING TURNS. Stabilise first. Then turn LEFT 360 deg over the spot at a steady, slow rate (about 90 deg every 5-6 s) and stop on 360. Then the same to the RIGHT. Expect the turn to need different pedal and collective as the wind moves around you.", "You have control. Stabilise first.")
		"h_wind":
			_weather(90.0, 12.0, 0.45)
			_hover_place(_pad, HOVER_H)
			I.force("H6 - GUSTY CROSSWIND. 12 kt from the right with gusts. Hold 1 m over the spot, heading 360. Expect to hold some right cyclic into the wind, and react to each gust early and gently.", "You have control. Wind from the right, gusting.")
		"l_takeoff":
			_weather(0.0, 5.0, 0.1)
			main.reset_on_pad()
			I.force("L1 - VERTICAL TAKE-OFF. Collective fully down, cyclic centred. Raise the collective slowly. As the skids get light, the nose wants to yaw right - left pedal - and the aircraft may want to slide: small cyclic to stay exactly on the spot. Lift off vertically to a 1 m hover with NO aft movement. Tip: in this simulation the hover cyclic position is a little AFT and slightly LEFT of centre - ease it there as the skids get light.", "Raise the collective slowly. Left pedal as the skids get light.")
		"l_land":
			_weather(0.0, 5.0, 0.1)
			_hover_place(_pad, HOVER_H)
			I.force("L2 - VERTICAL LANDING. First stabilise your hover over the pad centre.", "Stabilise the hover.")
		"l_taxi":
			_weather(0.0, 5.0, 0.1)
			_spot = main.world.hover_spot
			_hover_place(_pad, HOVER_H)
			I.force("L3 - HOVER-TAXI. Stabilise at 1 m, heading 360. You will hover-taxi 22 m straight ahead along the yellow line to the yellow spot, at no more than a brisk walk, then stop over it and land on it.", "Stabilise the hover, heading three six zero.")
		"l_approach":
			_weather(0.0, 8.0, 0.15)
			main._place(_pad + Vector3(0.0, 152.0 + main.fdm.cg_height, 1300.0), 0.0, 60.0)
			I.force("L4 - NORMAL APPROACH. 500 ft above the pad, 60 kt, the pad is straight ahead. Fly level for now. When the pad is about 10 deg below you I will call it: then lower the collective to start the descent and keep the pad fixed in the same place in your windscreen.", "Fly level. I will call the approach.")
		"transit":
			main.reset_on_pad()
			I.force("LESSON - PAD TO FIELD LZ. Lift to a hover, then accelerate north (heading 360) through translational lift, climb to about 300 ft, and approach the Field LZ 1.5 km ahead. Arrive slow and land on it.")
		"vrs":
			main._place(_pad + Vector3(0.0, 450.0 + main.fdm.cg_height, 400.0), 0.0, 0.0)
			I.force("LESSON - VORTEX RING STATE (about 1,500 ft above the valley, hovering, no airspeed). Lower the collective and let the aircraft sink VERTICALLY faster than about 800 ft/min with less than 10 kt. Watch for buffet and a sink rate that keeps growing.")
		"auto":
			main.reset_autorotation()
	# training assist for this attempt (faded out as you get better)
	if _user_assist < 0 and assist != null:
		_user_assist = assist.level
	if assist != null and auto_assist and START_ASSIST.has(id):
		main.set_assist(next_assist(id), true)
	elif assist != null and auto_assist and id in ["h_coll", "h_ped"]:
		main.set_assist(0, true)
	lesson_assist = assist.level if assist != null else 0
	if assist != null and id != "" and auto_assist and assist.level > 0:
		I.force(I.message + "\n\nTRAINING ASSIST %d - %s (not on the real 206). Score %d+ and the next try uses less assist. H changes it." % [assist.level, assist.name(), STEP_DOWN_SCORE])
	elif assist != null and id != "" and not (id in ["transit", "vrs", "auto"]):
		I.force(I.message + "\n\nTRAINING ASSIST: %s - your choice, it stays as you set it. H changes it any time (Off / 1 / 2 / 3)." % (assist.name() if assist.level > 0 else "OFF (real 206)"))
	_trim = {}
	if id in ["h_mentor", "h_coll", "h_ped", "h_cyc", "h_full", "h_turns", "h_wind", "l_takeoff", "l_land", "l_taxi"]:
		_compute_trim(_pad)
	# instructor hands: hover over the starting spot, heading 360, 1 m
	hands.target = _pad
	hands.height = HOVER_H
	hands.heading = 0.0
	if id in ["transit", "vrs", "auto"]:
		coach.ctx = {"phase": "off"}
	main.controls.phone_release()

func stop() -> void:
	_restore_weather()
	if _user_assist >= 0 and assist != null and auto_assist:
		main.set_assist(_user_assist, true)     # automatic mode borrowed the assist: give yours back
	_user_assist = -1
	if hands != null:
		hands.hold = {"coll": false, "ped": false, "cyc": false}
	id = ""
	objective = ""
	guide = {}
	if coach != null:
		coach.ctx = {}

func active() -> bool:
	return id != ""

## "I have control" -> the student takes every control (T key after a part-task level).
func take_control() -> void:
	if hands.any():
		hands.hold = {"coll": false, "ped": false, "cyc": false}
		main.controls.phone_release()
		main.instructor.force("You have control (all controls).", "You have control.")
		if guide.has("owner"):
			guide["owner"] = _owner_text()

func update(dt: float, touchdown: bool, sink: float) -> void:
	if id == "" or done:
		return
	t += dt
	pt += dt
	if assist != null:
		lesson_assist = maxi(lesson_assist, assist.level)
	var f = main.fdm
	_stats["max_tq"] = maxf(_stats["max_tq"], f.torque_pct)
	match id:
		"h_mentor":
			_h_mentor(dt, f)
		"h_coll":
			_h_coll(dt, f, touchdown, sink)
		"h_ped":
			_h_ped(dt, f)
		"h_cyc":
			_h_cyc(dt, f)
		"h_full", "h_wind":
			_h_full(dt, f)
		"h_turns":
			_h_turns(dt, f)
		"l_takeoff":
			_l_takeoff(dt, f, touchdown)
		"l_land":
			_l_land(dt, f, touchdown, sink)
		"l_taxi":
			_l_taxi(dt, f, touchdown, sink)
		"l_approach":
			_l_approach(dt, f, touchdown, sink)
		"transit":
			_transit(dt, f, touchdown, sink)
		"vrs":
			_vrs(dt, f)
		"auto":
			_auto(dt, f, touchdown, sink)

# --------------------------------------------------------------------- finish
func _finish(text: String) -> void:
	done = true
	result = text
	objective = lesson_title() + " - COMPLETE\n" + text + "\n(Esc > Lessons to repeat or try another)"
	main.instructor.force("Lesson complete. " + text)
	if coach != null:
		coach.ctx = {"phase": "off"}

func _finish_scored(s: float, lines: Array, keep_hands := false) -> void:
	score = int(round(clampf(s, 0.0, 100.0)))
	var key := id if lesson_assist == 0 else "%s@%d" % [id, lesson_assist]
	var prev := int(progress.get(key, -1))
	if score > prev:
		progress[key] = score
	var assist_note := ""
	if lesson_assist > 0:
		assist_note = "   (with training assist %d)" % lesson_assist
		if not auto_assist:
			if score >= STEP_DOWN_SCORE:
				assist_note += "\nGood - when you feel ready, try assist %s (H)." % ("OFF" if lesson_assist == 1 else str(lesson_assist - 1))
		elif score >= STEP_DOWN_SCORE and START_ASSIST.has(id):
			progress[id + "_assist"] = lesson_assist - 1
			assist_note += "\nWell done - next try uses assist %d%s." % [lesson_assist - 1, " (none: the real thing!)" if lesson_assist == 1 else ""]
		elif START_ASSIST.has(id):
			assist_note += "\nScore %d+ to move down to assist %d." % [STEP_DOWN_SCORE, lesson_assist - 1]
	_save_progress()
	var txt := "SCORE %d / 100   grade %s%s%s\n" % [score, grade(score), "   NEW BEST" if score > prev and prev >= 0 else "", assist_note]
	txt += "\n".join(lines)
	# coach notes: the faults that came up most often
	var keys := []
	for k in coach.faults:
		if TIPS.has(k):
			keys.append(k)
	keys.sort_custom(func(a, b): return int(coach.faults[a]) > int(coach.faults[b]))
	var seen := {}
	var notes := []
	for k in keys:
		var tip: String = TIPS[k]
		if seen.has(tip):
			continue
		seen[tip] = true
		notes.append("- " + tip + " (x%d)" % int(coach.faults[k]))
		if notes.size() >= 3:
			break
	if notes.size() > 0:
		txt += "\nWORK ON:\n" + "\n".join(notes)
	done = true
	result = txt
	objective = lesson_title() + " - DEBRIEF\n" + txt + "\n" + ("T = take all controls.   " if keep_hands else "") + "Esc > Lessons for the next level or to repeat."
	main.instructor.force("Lesson complete - score %d, grade %s." % [score, grade(score).split(" ")[0]], "Lesson complete. Score %d." % score)
	if keep_hands:
		# "I have control": the instructor keeps the aircraft in a hover until you press T
		var c = main.controls
		hands.hold = {"coll": true, "ped": true, "cyc": true}
		hands.sync(c.collective, c.cyclic_lon, c.cyclic_lat, c.pedal)
		hands.target = main.fdm.pos
		hands.height = maxf(main.fdm.agl, 0.8) if not main.fdm.on_ground else 0.0
		hands.heading = main.fdm.heading_deg()
		if main.fdm.on_ground:
			hands.hold = {"coll": false, "ped": false, "cyc": false}
	coach.ctx = {"phase": "off"}
	guide["owner"] = _owner_text()

# ------------------------------------------------- H0 instructor take-over loop
## "I have control": the instructor's hands take the controls exactly where they are (no jump,
## also when a training assist was moving the cyclic) and fly back to the spot.
func _mentor_take(reason: String) -> void:
	var f = main.fdm
	hands.hold = {"coll": true, "ped": true, "cyc": true}
	hands.sync(f.collective, f.cyclic_lon, f.cyclic_lat, f.pedal)
	hands.vz_override = NAN
	hands.vel_cmd_override = Vector2(NAN, NAN)
	hands.target = _pad
	hands.height = HOVER_H
	hands.heading = 0.0
	if reason != "":
		main.instructor.force("I HAVE CONTROL. %s\nI bring it back over the spot and steady it; then you try again." % reason, "I have control.")

## "You have control": release the student's axes (the controls are already where the
## instructor had them - linked dual controls - so nothing jumps).
func _mentor_give() -> void:
	var a := mentor_axes
	hands.hold = {"coll": not (a == "all" or a == "coll"), "ped": not (a == "all" or a == "ped"), "cyc": not (a == "all" or a == "cyc")}
	main.controls.phone_release()
	_sc["attempt"] = int(_sc.get("attempt", 0)) + 1
	var tip := ""
	match a:
		"cyc": tip = "Tiny pressures and wait - it moves about a second later."
		"coll": tip = "Tiny collective changes, then wait 1-2 s for the height to change."
		"ped": tip = "Keep the nose on the same point on the horizon."
		_: tip = "Same picture outside: references ahead and to the side, horizon steady."
	main.instructor.force("YOU HAVE CONTROL (%s) - attempt %d. Hold this spot and this height. %s" % [MENTOR_AXES[a][0], int(_sc["attempt"]), tip], MENTOR_AXES[a][1])

func _mentor_reason(f, e: Dictionary) -> String:
	var gs: float = Vector2(f.vel.x, f.vel.z).length()
	if float(e["dist"]) > PASS_POS:
		return "You drifted %.1f m %s of the spot." % [e["dist"], coach.dir_words(hands.body_xy(f.pos - _pad))]
	if f.on_ground:
		return "The skids touched the ground."
	if float(e["h"]) < -0.6:
		return "Too low (%.1f m)." % f.agl
	if float(e["h"]) > 1.3:
		return "Too high (%.1f m)." % f.agl
	if absf(float(e["hdg"])) > 30.0:
		return "The nose swung %.0f deg %s." % [absf(e["hdg"]), "right" if float(e["hdg"]) > 0.0 else "left"]
	if absf(f.pitch_deg()) > 15.0 or absf(f.roll_deg()) > 15.0:
		return "Attitude too steep (pitch %+.0f, roll %+.0f deg)." % [f.pitch_deg(), f.roll_deg()]
	if gs > 2.5:
		return "Moving too fast over the ground (%.1f m/s)." % gs
	return ""

func _h_mentor(dt: float, f) -> void:
	var e := _err(f, _pad, HOVER_H, 0.0)
	var gs: float = Vector2(f.vel.x, f.vel.z).length()
	var line := ""
	if phase == 0:
		# instructor flies: back to the spot, then steady
		_ctx("hover", _pad, HOVER_H, 0.0)
		coach.ctx = {"phase": "off"}         # no coaching while the instructor flies
		var steady: bool = _in_box(e, 0.4, 0.15, 4.0) and gs < 0.25 and f.omega.length() < 0.06 and not f.on_ground
		_acc = _acc + dt if steady else 0.0
		line = "I HAVE CONTROL - steadying over the spot... watch the picture outside: this is what you keep."
		if _acc >= 2.5 and pt >= 3.0:
			_acc = 0.0
			phase = 1
			pt = 0.0
			_mentor_give()
	else:
		_ctx("hover", _pad, HOVER_H, 0.0)
		var why := _mentor_reason(f, e)
		_track("acs", _in_box(e, ACS_POS, 0.5), dt)
		_rms("pos", e["dist"], dt)
		_maxs("maxd", e["dist"])
		if why != "":
			_sc["best"] = maxf(float(_sc.get("best", 0.0)), _acc)
			_sc["takeovers"] = int(_sc.get("takeovers", 0)) + 1
			_mentor_take("%s You held it %.0f s." % [why, _acc])
			_acc = 0.0
			phase = 0
			pt = 0.0
			return
		_acc += dt
		line = "YOU HAVE CONTROL (%s) - hold it!" % MENTOR_AXES[mentor_axes][0]
		if _acc >= MENTOR_HOLD:
			_sc["best"] = maxf(float(_sc.get("best", 0.0)), _acc)
			var n: int = int(_sc.get("takeovers", 0))
			var s: float = 30.0 * ramp(float(n), 0.0, 8.0) + 50.0 * _frac("acs") + 20.0 * ramp(_rmsv("pos"), 0.5, 2.5)
			_finish_scored(s, ["You held it %.0f s on attempt %d (%d take-over%s by the instructor)." % [MENTOR_HOLD, int(_sc["attempt"]), n, "" if n == 1 else "s"],
				"While you had control: inside the ACS box (1.2 m, half height, 10 deg) %.0f%% of the time, position RMS %.2f m." % [_frac("acs") * 100.0, _rmsv("pos")],
				"Next: %s" % ("try it with all controls (Esc > H0 > All)." if mentor_axes != "all" else "H4 full hover on your own, then fewer assists.")], true)
			return
	guide["owner"] = _owner_text()
	objective = "H0 - INSTRUCTOR HOVER (%s)   attempt %d   take-overs %d\n%s\nheight %.1f m (aim 1.0)   spot %.1f m (take-over at 3 m)   heading %03.0f\n%s   best %.0f s" % [MENTOR_AXES[mentor_axes][0], int(_sc.get("attempt", 0)), int(_sc.get("takeovers", 0)), line, f.agl, e["dist"], f.heading_deg(), bar(_acc if phase == 1 else 0.0, MENTOR_HOLD), float(_sc.get("best", 0.0))]

# ---------------------------------------------------------------- H1 collective
func _h_coll(dt: float, f, touchdown: bool, sink: float) -> void:
	var stages := [[1.0, 15.0, "Hold 1 m"], [2.0, 8.0, "Climb to 2 m and hold"], [1.0, 8.0, "Back down to 1 m and hold"]]
	if phase < 3:
		var h: float = stages[phase][0]
		var need: float = stages[phase][1]
		var tol := 0.5 * h                       # ACS: +/- half of the hover height
		_ctx("hover", null, h, NAN, ACS_POS, tol)
		var e: float = f.agl - h
		var ok: bool = absf(e) <= tol and not f.on_ground
		if ok:
			_sc["entered"] = true
		if bool(_sc.get("entered", false)):
			_track("h", ok, dt)
			_track("ht", absf(e) <= 0.25 * h, dt)
			_rms("he", e / h, dt)
		if ok:
			_acc += dt
		objective = "H1 - COLLECTIVE   step %d/4: %s\n%s\nskid height %.2f m (aim %.1f, ACS band %.1f-%.1f)   VS %+.0f ft/min   torque %.0f%%\n%s" % [phase + 1, stages[phase][2], _owner_text(), f.agl, h, h - tol, h + tol, f.vs_fpm(), f.torque_pct, bar(_acc, need)]
		if _acc >= need:
			_sc["entered"] = false
			match phase:
				0: _next("Good. Now climb to 2 m: raise the collective a touch, then take most of it out again as you arrive so you stop at 2 m. Notice the torque rise.", "Climb to two metres.")
				1: _next("Now back down to 1 m: lower the collective slightly, then stop the descent at 1 m. Notice the torque drop in ground effect.", "Back down to one metre.")
				2: _next("Now set it down on the pad: lower the collective very slowly; I keep it level and over the spot. Aim for a touchdown you barely feel.", "Now land. Very slowly.")
	elif phase == 3:
		_ctx("land", null, NAN, NAN)
		objective = "H1 - COLLECTIVE   step 4/4: set it down softly\n%s\nskid height %.2f m   vertical speed %+.0f ft/min (%.2f m/s)\naim: below 0.3 m/s at touchdown, then collective fully down" % [_owner_text(), f.agl, f.vs_fpm(), f.vel.y]
		if touchdown:
			_sc["sink"] = sink
			_next()
	else:
		objective = "H1 - COLLECTIVE\nOn the ground. Collective fully down now (%.0f%%)." % (main.controls.collective * 100.0)
		if main.controls.collective < 0.08 or pt > 6.0:
			var s: float = 55.0 * _frac("h") + 25.0 * _frac("ht") + 20.0 * td_score(float(_sc["sink"]))
			_finish_scored(s, ["Height inside the ACS band %.0f%% of the time (inside half of it %.0f%%), RMS error %.0f%% of the target." % [_frac("h") * 100.0, _frac("ht") * 100.0, _rmsv("he") * 100.0],
				"Touchdown %.2f m/s (%s)." % [_sc["sink"], Landing.rate(_sc["sink"])]], true)

# ------------------------------------------------------------------- H2 pedals
func _h_ped(dt: float, f) -> void:
	var stages := [[0.0, 12.0, "Hold heading 360"], [270.0, 6.0, "Pivot LEFT to 270 and hold"], [0.0, 6.0, "Pivot RIGHT back to 360 and hold"]]
	var hdg: float = stages[phase][0]
	var e := wrapf(f.heading_deg() - hdg, -180.0, 180.0)
	var ok: bool = absf(e) <= 10.0
	var r := absf(rad_to_deg(f.omega.z))
	if ok:
		_sc["reached"] = true
	var turning: bool = not bool(_sc.get("reached", false))
	_ctx("turn" if turning else "hover", null, NAN, hdg)
	if turning:
		_maxs("rate", r)
		if r > 30.0:
			coach.cue("yaw", "Turning fast (%.0f deg/s). Slow the turn: about 90 deg in 5 s." % r, "", 6.0)
	else:
		_track("hdg", ok, dt)
		_track("hdgt", absf(e) <= 5.0, dt)
		_maxs("over", absf(e))
		if ok:
			_acc += dt
	objective = "H2 - PEDALS   step %d/3: %s\n%s\nheading %03.0f (aim %03.0f, ACS +/-10)   error %+.0f   yaw rate %.0f deg/s\n%s" % [phase + 1, stages[phase][2], _owner_text(), f.heading_deg(), hdg, e, r, bar(_acc, stages[phase][1])]
	if _acc >= stages[phase][1]:
		_sc["reached"] = false
		match phase:
			0: _next("Good. Now pivot LEFT to 270: a little LEFT pedal to start the turn, then ease it off before 270 so the nose stops on it.", "Turn left to two seven zero.")
			1: _next("Now RIGHT back to 360. Right pedal reduces tail rotor thrust - torque does part of the work, so the turn starts quickly.", "Turn right to three six zero.")
			2:
				var rate_f := ramp(float(_sc.get("rate", 0.0)), 30.0, 60.0)
				var s: float = 60.0 * _frac("hdg") + 20.0 * _frac("hdgt") + 20.0 * rate_f
				_finish_scored(s, ["Heading within 10 deg %.0f%% of the hold time (within 5 deg %.0f%%). Worst error while holding %.0f deg." % [_frac("hdg") * 100.0, _frac("hdgt") * 100.0, _sc.get("over", 0.0)],
					"Fastest turn rate %.0f deg/s (aim below 30)." % _sc.get("rate", 0.0)], true)

# ------------------------------------------------------------------- H3 cyclic
func _h_cyc(dt: float, f) -> void:
	var right := Vector3(1.0, 0.0, 0.0)        # heading 360: right = east
	var stages := [[_pad, 20.0, "Stay over the pad centre"], [_pad + right * 5.0, 8.0, "Move 5 m to the RIGHT (sideways) and hold"], [_pad, 8.0, "Back LEFT to the centre and hold"]]
	var spot: Vector3 = stages[phase][0]
	_ctx("hover", spot, NAN, NAN)
	var d := Vector2(f.pos.x - spot.x, f.pos.z - spot.z).length()
	if d <= PASS_POS:
		_sc["entered"] = true
	if bool(_sc.get("entered", false)):
		_track("p3", d <= PASS_POS, dt)
		_track("pa", d <= ACS_POS, dt)
		_maxs("maxd", d)
		if d <= PASS_POS:
			_acc += dt
	objective = "H3 - CYCLIC   step %d/3: %s\n%s\ndistance from the spot %.1f m (ACS 1.2 m, pass 3 m)   ground speed %.1f kt\n%s" % [phase + 1, stages[phase][2], _owner_text(), d, f.groundspeed_kt(), bar(_acc, stages[phase][1])]
	if _acc >= stages[phase][1]:
		_sc["entered"] = false
		match phase:
			0: _next("Good. Now move 5 m to the RIGHT, sideways, keeping the nose on 360: a little right cyclic, and start taking it out halfway there.", "Move five metres right.")
			1: _next("Now back LEFT to the pad centre, same technique.", "Back to the centre.")
			2:
				var s: float = 40.0 * _frac("p3") + 40.0 * _frac("pa") + 20.0 * ramp(float(_sc.get("maxd", 0.0)), ACS_POS, 4.5)
				_finish_scored(s, ["Within 1.2 m (ACS) %.0f%% of the time, within 3 m %.0f%%. Largest drift %.1f m." % [_frac("pa") * 100.0, _frac("p3") * 100.0, _sc.get("maxd", 0.0)]], true)

# ---------------------------------------------------------- H4 / H6 full hover
func _h_full(dt: float, f) -> void:
	var need := 40.0 if id == "h_full" else 30.0
	_ctx("hover", _pad, HOVER_H, 0.0)
	var e := _err(f, _pad, HOVER_H, 0.0)
	var pass_ok: bool = _in_box(e, PASS_POS, 0.5) and not f.on_ground
	_track("pass", pass_ok, dt)
	_track("acs", _in_box(e, ACS_POS, 0.5), dt)
	_rms("pos", e["dist"], dt)
	_maxs("maxd", e["dist"])
	if pass_ok:
		_acc += dt
	var w: Vector3 = f.wind
	objective = "%s\n%s\nheight %.1f m (0.5-1.5)   spot %.1f m (ACS 1.2, pass 3)   heading %03.0f (+/-10)\nwind %.0f kt from %03.0f\n%s" % [lesson_title(), _owner_text(), f.agl, e["dist"], f.heading_deg(), Vector2(w.x, w.z).length() / 0.514444, f.atmo.wind_from_deg, bar(_acc, need)]
	if _acc >= need:
		var s: float = 35.0 * _frac("pass") + 45.0 * _frac("acs") + 20.0 * ramp(_rmsv("pos"), 0.5, 2.5)
		_finish_scored(s, ["All three inside the ACS box (1.2 m, half height, 10 deg) %.0f%% of the time; inside the pass box %.0f%%." % [_frac("acs") * 100.0, _frac("pass") * 100.0],
			"Position RMS %.2f m, largest %.1f m. Lesson time %.0f s for %.0f s in the box." % [_rmsv("pos"), _sc.get("maxd", 0.0), t, need]])

# -------------------------------------------------------------- H5 hover turns
func _h_turns(dt: float, f) -> void:
	var e := _err(f, _pad, HOVER_H, 0.0)
	var r := rad_to_deg(f.omega.z)
	match phase:
		0:
			_ctx("hover", _pad, HOVER_H, 0.0)
			if _in_box(e, PASS_POS, 0.5):
				_acc += dt
			objective = "H5 - HOVERING TURNS   step 1/3: stabilise over the spot\n%s\n%s" % [_owner_text(), bar(_acc, 5.0)]
			if _acc >= 5.0:
				_sc["yaw"] = 0.0
				_sc["prev"] = f.heading_deg()
				_next("Now turn LEFT through a full 360, slowly and steadily, staying over the spot. Stop on 360.", "Turn left, three sixty.")
		1, 2:
			var dir := -1.0 if phase == 1 else 1.0
			var dh := wrapf(f.heading_deg() - float(_sc["prev"]), -180.0, 180.0)
			_sc["prev"] = f.heading_deg()
			_sc["yaw"] = float(_sc["yaw"]) + dh
			var turned := float(_sc["yaw"]) * dir
			var finishing: bool = turned > 300.0
			_ctx("turn" if not finishing else "hover", _pad, HOVER_H, 0.0 if finishing else NAN)
			_track("pa", e["dist"] <= ACS_POS, dt)
			_track("p3", e["dist"] <= PASS_POS, dt)
			_track("h", absf(float(e["h"])) <= 0.5, dt)
			_maxs("rate", absf(r))
			if turned < -45.0:
				coach.cue("wrong_way", "Wrong way - this turn is to the %s." % ("LEFT" if phase == 1 else "RIGHT"), "", 6.0)
			if absf(r) > 45.0:
				coach.cue("yaw", "Too fast (%.0f deg/s). A steady, slow turn: about 90 deg in 5 s." % absf(r), "", 6.0)
			if finishing and absf(float(e["hdg"])) <= 10.0 and absf(r) < 3.0:
				_acc += dt
			objective = "H5 - HOVERING TURNS   step %d/3: %s 360\n%s\nturned %.0f / 360 deg   rate %.0f deg/s   spot %.1f m (ACS 1.2)   height %.1f m\nstop on 360 within 10 deg: %s" % [phase + 1, "LEFT" if phase == 1 else "RIGHT", _owner_text(), clampf(turned, 0.0, 400.0), absf(r), e["dist"], f.agl, bar(_acc, 3.0)]
			if _acc >= 3.0:
				_sc["stop%d" % phase] = absf(float(e["hdg"]))
				_sc["yaw"] = 0.0
				if phase == 1:
					_next("Good. Now the same to the RIGHT.", "Now turn right, three sixty.")
				else:
					var stop_f := 0.5 * (ramp(float(_sc["stop1"]), 2.0, 10.0) + ramp(float(_sc["stop2"]), 2.0, 10.0))
					var s: float = 40.0 * _frac("pa") + 20.0 * _frac("p3") + 20.0 * _frac("h") + 20.0 * stop_f
					_finish_scored(s, ["During the turns: within 1.2 m of the pivot point %.0f%% (ACS), within 3 m %.0f%%, height in band %.0f%%." % [_frac("pa") * 100.0, _frac("p3") * 100.0, _frac("h") * 100.0],
						"Stopped %.0f deg and %.0f deg from 360. Fastest yaw rate %.0f deg/s." % [_sc["stop1"], _sc["stop2"], _sc.get("rate", 0.0)]])

# ------------------------------------------------------------ L1 take-off
func _l_takeoff(dt: float, f, touchdown: bool) -> void:
	var fwd := Vector2(0.0, -1.0)      # heading 360
	match phase:
		0:
			_ctx("liftoff", _pad, NAN, 0.0)
			objective = "L1 - VERTICAL TAKE-OFF   step 1/2: lift off\n%s\ncollective %.0f%%   torque %.0f%%   heading %03.0f\nRaise the collective slowly; left pedal as torque rises; stay on the spot." % [_owner_text(), main.controls.collective * 100.0, f.torque_pct, f.heading_deg()]
			if f.on_ground and main.controls.collective > 0.15:
				_maxs("gnd_yaw", absf(wrapf(f.heading_deg(), -180.0, 180.0)))
			if not f.on_ground and f.agl > 0.05:
				_sc["lo_pos"] = f.pos
				_sc["lo_t"] = t
				_next("Light on the skids - airborne. Keep it coming up slowly to 1 m, exactly over the spot.", "Airborne. Up to one metre.")
		1:
			var lo: Vector3 = _sc["lo_pos"]
			var since := t - float(_sc["lo_t"])
			var off := Vector2(f.pos.x - lo.x, f.pos.z - lo.z)
			if since < 5.0:
				_maxs("drift", off.length())
				_maxs("aft", -off.dot(fwd))
				_maxs("hdg", absf(wrapf(f.heading_deg(), -180.0, 180.0)))
				_maxs("climb", f.vel.y)
			if since < 10.0:
				_maxs("balloon", f.agl)
			_ctx("hover", _pad, HOVER_H, 0.0)
			var e := _err(f, _pad, HOVER_H, 0.0)
			if _in_box(e, PASS_POS, 0.5) and not f.on_ground:
				_acc += dt
			if touchdown and since > 1.0:
				_sc["relift"] = int(_sc.get("relift", 0)) + 1
				main.instructor.say("l1_down", "You touched down again. Lift off again smoothly - one continuous, slow collective movement.", 6.0)
			objective = "L1 - VERTICAL TAKE-OFF   step 2/2: settle at 1 m over the spot\n%s\nheight %.2f m   drift from lift-off point %.1f m   heading %03.0f\n%s" % [_owner_text(), f.agl, off.length(), f.heading_deg(), bar(_acc, 8.0)]
			if _acc >= 8.0:
				var s: float = 25.0 * ramp(float(_sc.get("drift", 0.0)), 0.6, 3.0) + 15.0 * ramp(float(_sc.get("aft", 0.0)), 0.3, 1.5) + 20.0 * ramp(float(_sc.get("hdg", 0.0)), 5.0, 15.0) + 20.0 * ramp(float(_sc.get("climb", 0.0)), 0.6, 1.5) + 20.0 * ramp(float(_sc.get("balloon", 0.0)), 1.8, 3.0) - 10.0 * int(_sc.get("relift", 0))
				_finish_scored(s, ["First 5 s after lift-off: drift %.1f m (ACS: within 1.2 m), aft movement %.1f m (ACS: none), heading change %.0f deg (ACS: 10)." % [_sc.get("drift", 0.0), maxf(float(_sc.get("aft", 0.0)), 0.0), _sc.get("hdg", 0.0)],
					"Peak climb rate %.1f m/s (smooth: below 0.6). Highest point %.1f m (aim 1 m).%s" % [_sc.get("climb", 0.0), _sc.get("balloon", 0.0), (" Touched down again %d time(s)." % int(_sc["relift"])) if _sc.has("relift") else ""]])

# ------------------------------------------------------------ L2 landing
## Shared vertical-landing logic; returns true when finished (results in _sc).
func _land_phase(dt: float, f, touchdown: bool, sink: float, spot: Vector3, title: String, step: String) -> bool:
	if not bool(_sc.get("td", false)):
		_ctx("land", spot, NAN, 0.0)
		var d := Vector2(f.pos.x - spot.x, f.pos.z - spot.z).length()
		_maxs("ld_d", d)
		_maxs("ld_hdg", absf(wrapf(f.heading_deg(), -180.0, 180.0)))
		objective = "%s   %s\n%s\nheight %.2f m   sink %.2f m/s (%+.0f ft/min)   spot %.1f m   ground speed %.1f kt\naim: below 0.3 m/s, within 1.2 m, no movement" % [title, step, _owner_text(), f.agl, -f.vel.y, f.vs_fpm(), d, f.groundspeed_kt()]
		if touchdown:
			_sc["td"] = true
			_sc["sink"] = sink
			_sc["td_d"] = d
			_sc["td_gs"] = f.groundspeed_kt()
			_sc["td_t"] = t
			_sc["air"] = 0.0
		return false
	_ctx("land", spot, NAN, NAN)
	if not f.on_ground:
		_sc["air"] = float(_sc["air"]) + dt
		if float(_sc["air"]) > 0.3 and not _sc.has("relift"):
			_sc["relift"] = true
			main.instructor.say("relift", "You lifted off again after touchdown. Once the skids are down, keep the collective going down.", 6.0)
	objective = "%s\nOn the ground: collective fully down, smoothly (%.0f%%)." % [title, main.controls.collective * 100.0]
	if (main.controls.collective < 0.05 and f.on_ground) or t - float(_sc["td_t"]) > 8.0:
		_sc["coll_late"] = main.controls.collective >= 0.05
		return true
	return false

func _land_score() -> Array:
	var s: float = 35.0 * td_score(float(_sc["sink"])) + 20.0 * ramp(float(_sc["td_d"]), ACS_POS, PASS_POS) + 15.0 * ramp(float(_sc["td_gs"]), 0.5, 3.0) + 10.0 * ramp(float(_sc.get("ld_hdg", 0.0)), 5.0, 15.0) + (0.0 if _sc.has("relift") else 10.0) + (0.0 if bool(_sc.get("coll_late", false)) else 10.0)
	var lines := ["Touchdown %.2f m/s (%s), %.1f m from the spot (ACS: within 1.2 m), ground speed %.1f kt." % [_sc["sink"], Landing.rate(_sc["sink"]), _sc["td_d"], _sc["td_gs"]],
		"Heading kept within %.0f deg during the descent.%s%s" % [_sc.get("ld_hdg", 0.0), " Lifted off again after touchdown." if _sc.has("relift") else "", " Collective was not fully down within 8 s." if bool(_sc.get("coll_late", false)) else ""]]
	return [s, lines]

func _l_land(dt: float, f, touchdown: bool, sink: float) -> void:
	match phase:
		0:
			_ctx("hover", _pad, HOVER_H, 0.0)
			if _in_box(_err(f, _pad, HOVER_H, 0.0), PASS_POS, 0.5):
				_acc += dt
			objective = "L2 - VERTICAL LANDING   step 1/2: stabilise the hover\n%s\n%s" % [_owner_text(), bar(_acc, 4.0)]
			if _acc >= 4.0:
				_next("Now land vertically on the pad centre. Lower the collective very slightly and keep the same small corrections. In the last half-metre slow the descent even more - and keep the nose on 360.", "Now land vertically. Very gently.")
		1:
			if _land_phase(dt, f, touchdown, sink, _pad, "L2 - VERTICAL LANDING", "step 2/2: land on the spot"):
				var r := _land_score()
				_finish_scored(r[0], r[1])

# ------------------------------------------------------------ L3 hover taxi
func _l_taxi(dt: float, f, touchdown: bool, sink: float) -> void:
	match phase:
		0:
			_ctx("hover", _pad, HOVER_H, 0.0)
			if _in_box(_err(f, _pad, HOVER_H, 0.0), PASS_POS, 0.5):
				_acc += dt
			objective = "L3 - HOVER-TAXI   step 1/4: stabilise\n%s\n%s" % [_owner_text(), bar(_acc, 3.0)]
			if _acc >= 3.0:
				_next("Hover-taxi forward along the yellow line: slight forward cyclic to start moving, no faster than a brisk walk, then keep a constant speed and height. Stop over the yellow spot.", "Hover taxi forward to the yellow spot.")
		1:
			_ctx("taxi", null, HOVER_H, 0.0)
			var lat: float = f.pos.x - _spot.x
			var togo: float = f.pos.z - _spot.z
			var gs: float = f.groundspeed_kt()
			var ok: bool = absf(lat) <= ACS_POS and absf(f.agl - HOVER_H) <= 0.5 and absf(wrapf(f.heading_deg(), -180.0, 180.0)) <= 10.0
			_track("taxi", ok, dt)
			_maxs("vmax", gs)
			if gs > 5.0:
				coach.cue("taxi_fast", "Too fast for a hover-taxi (%.0f kt). Ease back to a brisk walk." % gs, "", 5.0)
			elif absf(lat) > ACS_POS:
				coach.cue("taxi_track", "You are %.1f m %s of the line. Small %s cyclic to get back on it." % [absf(lat), "right" if lat > 0.0 else "left", "left" if lat > 0.0 else "right"], "", 5.0)
			if togo < 8.0 and togo > 1.0 and gs > 2.5:
				coach.cue("taxi_stop", "Spot coming up - start slowing down now with a little aft cyclic.", "overshoot", 6.0)
			if togo < -PASS_POS:
				coach.cue("taxi_past", "You passed the spot - come back to it slowly.", "", 6.0)
			objective = "L3 - HOVER-TAXI   step 2/4: taxi along the line to the spot\n%s\nto go %.1f m   off the line %.1f m (ACS 1.2)   speed %.1f kt (max 5)   height %.1f m" % [_owner_text(), togo, lat, gs, f.agl]
			if Vector2(f.pos.x - _spot.x, f.pos.z - _spot.z).length() < 1.5 and gs < 1.0:
				_next("Stop. Hold the hover exactly over the spot.", "Hold over the spot.")
		2:
			_ctx("hover", _spot, HOVER_H, 0.0)
			var e := _err(f, _spot, HOVER_H, 0.0)
			_track("spot", e["dist"] <= ACS_POS, dt)
			if _in_box(e, PASS_POS, 0.5):
				_acc += dt
			objective = "L3 - HOVER-TAXI   step 3/4: hold over the spot\n%s\nspot %.1f m (ACS 1.2)\n%s" % [_owner_text(), e["dist"], bar(_acc, 5.0)]
			if _acc >= 5.0:
				_next("Now land on the spot.", "Now land on the spot.")
		3:
			if _land_phase(dt, f, touchdown, sink, _spot, "L3 - HOVER-TAXI", "step 4/4: land on the spot"):
				var r := _land_score()
				var s: float = 0.4 * float(r[0]) + 35.0 * _frac("taxi") + 10.0 * ramp(float(_sc.get("vmax", 0.0)), 5.0, 9.0) + 15.0 * _frac("spot")
				var lines: Array = ["Taxi: on the line, at height and heading %.0f%% of the time; top speed %.1f kt (max 5)." % [_frac("taxi") * 100.0, _sc.get("vmax", 0.0)], "Over the spot within 1.2 m %.0f%% of the hold." % [_frac("spot") * 100.0]]
				lines.append_array(r[1])
				_finish_scored(s, lines)

# ------------------------------------------------------------ L4 normal approach
## Simulator guideline: progressive slow-down to about jogging pace (~5 kt) over the last 50 m.
static func closure_target_kt(dist_m: float) -> float:
	return clampf(dist_m / 12.0, 5.0, 60.0)

func _l_approach(dt: float, f, touchdown: bool, sink: float) -> void:
	var dist := Vector2(f.pos.x - _pad.x, f.pos.z - _pad.z).length()
	var hp: float = f.pos.y - f.cg_height - _pad.y      # skid height above the pad
	var ang := rad_to_deg(atan2(hp, maxf(dist, 1.0)))
	var gs: float = f.groundspeed_kt()
	var ias: float = f.ias_kt()
	if f.vs_fpm() < -500.0 and ias < 20.0 and f.agl > 5.0:
		_sc["vrs_t"] = float(_sc.get("vrs_t", 0.0)) + dt
		coach.cue("vrs", "Sink above 500 ft/min below 20 kt - vortex ring state risk! Reduce the descent rate or keep more airspeed.", "", 6.0)
	match phase:
		0:
			_ctx("approach", null, NAN, NAN)
			guide = {}
			objective = "L4 - NORMAL APPROACH   step 1/3: level, inbound\npad %.0f m ahead, %.1f deg below (start at 10)\nIAS %.0f kt   height above pad %.0f ft" % [dist, ang, ias, hp / 0.3048]
			if ang >= 10.0:
				_next("NOW: the pad is 10 deg below. Lower the collective to start the descent, keep the pad at the same spot in the windscreen, and start slowing down progressively.", "Start the approach now.")
			elif dist < 150.0:
				_next("You are too close to start a normal approach - carry on, but next time start the descent when the pad is 10 deg below.")
		1:
			_ctx("approach", null, NAN, NAN)
			guide = {}
			var tgt := closure_target_kt(dist)
			if dist > 60.0:
				var ae := ang - 10.0
				_track("ang", absf(ae) <= 2.0, dt)
				if ae > 2.5:
					coach.cue("app_high", "High on the approach (%.0f deg). Lower the collective a little." % ang, "", 6.0)
				elif ae < -2.5:
					coach.cue("app_low", "Low on the approach (%.0f deg). Raise the collective a little - do not drag in low." % ang, "", 6.0)
				if gs > tgt + 12.0:
					coach.cue("app_fast", "Closing too fast for this distance (%.0f kt, about %.0f is right). Slow down with a little aft cyclic." % [gs, tgt], "", 7.0)
				elif gs < tgt - 15.0 and dist > 150.0:
					coach.cue("app_slow", "Slow for this distance (%.0f kt). Keep some airspeed until the last 100-200 m." % gs, "", 7.0)
			if ias < 20.0 and ias > 10.0 and dist < 250.0 and not _sc.has("etl_said"):
				_sc["etl_said"] = true
				main.instructor.say("l4_etl", "Losing translational lift (below about 15-20 kt): the rotor now needs more power. Be ready to raise the collective - with left pedal - to stop the sink.", 60.0, 9.0, "Losing translational lift. More power, left pedal.")
			if dist < 50.0 and not _sc.has("gs50"):
				_sc["gs50"] = gs
			objective = "L4 - NORMAL APPROACH   step 2/3: hold ~10 deg, slow down progressively\npad %.0f m   angle %.1f deg (aim 10 +/-2)   ground speed %.0f kt (guide %.0f)\nIAS %.0f kt   VS %+.0f ft/min   torque %.0f%%" % [dist, ang, gs, tgt, ias, f.vs_fpm(), f.torque_pct]
			if dist < 6.0 and f.agl < 3.0 and gs < 3.0:
				_next("Terminate: come to a stabilised 1 m hover over the pad centre.", "Hover over the pad.")
			elif touchdown:
				_sc["td_d"] = dist
				_sc["td_gs"] = gs
				_l4_score(true)
		2:
			_ctx("hover", _pad, HOVER_H, 0.0)
			var e := _err(f, _pad, HOVER_H, 0.0)
			if _in_box(e, PASS_POS, 0.5):
				_acc += dt
			objective = "L4 - NORMAL APPROACH   step 3/3: stabilised hover over the pad\nspot %.1f m (ACS 1.2)   height %.1f m\n%s" % [e["dist"], f.agl, bar(_acc, 3.0)]
			if _acc >= 3.0:
				_sc["td_d"] = e["dist"]
				_l4_score(false)
			elif touchdown:
				_sc["td_d"] = e["dist"]
				_sc["td_gs"] = gs
				_l4_score(true)

func _l4_score(landed: bool) -> void:
	var d: float = _sc.get("td_d", 99.0)
	var gs50: float = _sc.get("gs50", 0.0)
	var s: float = 30.0 * _frac("ang") + 15.0 * ramp(float(_sc.get("vrs_t", 0.0)), 0.0, 3.0) + 25.0 * ramp(d, ACS_POS, PASS_POS * 3.0) + 15.0 * ramp(gs50, 10.0, 20.0) + 15.0 * ramp(float(_stats["max_tq"]), 100.0, 110.0)
	var lines := ["Approach angle within 10 +/-2 deg %.0f%% of the time. Ground speed 50 m out: %.0f kt (aim 10 or less)." % [_frac("ang") * 100.0, gs50],
		"%s %.1f m from the pad centre (ACS: within 1.2 m)%s." % ["Landed" if landed else "Hover established", d, (", %.1f kt at touchdown" % float(_sc.get("td_gs", 0.0))) if landed else ""],
		"Time in the VRS danger zone (sink > 500 ft/min below 20 kt): %.1f s. Max torque %.0f%%%s." % [_sc.get("vrs_t", 0.0), _stats["max_tq"], " - over the 100% limit!" if float(_stats["max_tq"]) > 100.0 else ""]]
	_finish_scored(s, lines)

# ------------------------------------------------------------ other exercises (M2)
func _pad_offset(f, pad: String) -> Vector2:
	var pp: Vector3 = main.world.terrain.pads[pad]["pos"]
	return Vector2(f.pos.x - pp.x, f.pos.z - pp.z)

func _transit(dt: float, f, touchdown: bool, sink: float) -> void:
	var off := _pad_offset(f, "Field LZ")
	var dist := off.length()
	var brg := fposmod(rad_to_deg(atan2(-off.x, off.y)), 360.0)
	var r: float = main.world.terrain.pads["Field LZ"]["radius"]
	if phase == 0:
		if not f.on_ground and f.agl > 3.0:
			phase = 1
	objective = "E1 - PAD TO FIELD LZ\nField LZ: %.0f m, bearing %03.0f (heading now %03.0f)\nIAS %.0f kt   height %.0f ft AGL   torque %.0f%% (max %.0f%%)" % [dist, brg, f.heading_deg(), f.ias_kt(), f.agl / 0.3048, f.torque_pct, _stats["max_tq"]]
	if phase == 1 and touchdown:
		if dist < r:
			var gs: float = f.groundspeed_kt()
			var ok: bool = sink < 1.5 and gs < 3.0
			_finish("Landed on the Field LZ %.0f m from centre after %.0f s. Touchdown %.2f m/s (%s), ground speed %.1f kt%s. Max torque %.0f%%%s." % [dist, t, sink, Landing.rate(sink), gs, "" if ok else " - too fast, aim for <1.5 m/s and no forward speed", _stats["max_tq"], " (over the 100% limit!)" if _stats["max_tq"] > 100.0 else ""])
		elif dist > 60.0:
			main.instructor.say("transit_off", "You touched down %.0f m from the Field LZ. Lift again and land on the LZ." % dist, 8.0)

func _vrs(dt: float, f) -> void:
	var ias: float = f.ias_kt()
	match phase:
		0:
			objective = "E2 - VORTEX RING STATE\n1) Descend vertically: lower collective, keep IAS below 10 kt.\nSink %.0f ft/min   IAS %.0f kt   VRS intensity %.0f%%" % [-f.vs_fpm(), ias, f.vrs * 100.0]
			if f.vrs > 0.5:
				_acc += dt
			else:
				_acc = maxf(_acc - dt, 0.0)
			if _acc > 2.0:
				phase = 1
				_stats["h_entry"] = f.pos.y
				_stats["t_entry"] = t
				main.instructor.force("YOU ARE IN VORTEX RING STATE: the rotor is descending into its own downwash. Sink rate builds, the aircraft shakes, and more collective only adds power without stopping the descent. RECOVER: forward cyclic to gain airspeed (or lateral cyclic), then use collective once you have forward speed.", "Vortex ring state. Forward cyclic.")
		1:
			objective = "E2 - VORTEX RING STATE\n2) RECOVER: forward cyclic, fly out of your own downwash.\nIAS %.0f kt (need > 20)   sink %.0f ft/min (need < 300)   VRS %.0f%%\nHeight lost so far: %.0f ft" % [ias, -f.vs_fpm(), f.vrs * 100.0, (float(_stats["h_entry"]) - f.pos.y) / 0.3048]
			if ias > 20.0 and f.vs_fpm() > -300.0 and f.vrs < 0.05:
				_finish("Recovered from VRS in %.0f s, losing %.0f ft. On a real helicopter VRS is avoided by never combining low airspeed (<~20 kt) with descent rates above ~300-500 ft/min while power is applied - especially on steep approaches and downwind." % [t - float(_stats["t_entry"]), (float(_stats["h_entry"]) - f.pos.y) / 0.3048])
			if f.agl < 30.0:
				_finish("Ground reached before recovery - start the recovery earlier (and in real life, at a much greater height).")

func _auto(dt: float, f, touchdown: bool, sink: float) -> void:
	var nr: float = f.nr_pct()
	if not f.on_ground:
		if nr < 90.0:
			_stats["nr_low"] += dt
		if nr > 107.0:
			_stats["nr_high"] += dt
	objective = "E3 - AUTOROTATION\nKeep NR 90-107%% (now %.0f%%)   IAS 55-65 kt (now %.0f)\nThrottle must stay at idle. Flare at about 50-100 ft, cushion with collective.\nNR low %.1f s   high %.1f s" % [nr, f.ias_kt(), _stats["nr_low"], _stats["nr_high"]]
	if f.throttle > 0.5 and not f.on_ground:
		_finish("Power recovery made (throttle opened). That is a valid choice in training - for the full exercise, keep the throttle at idle to the ground.")
		return
	if touchdown:
		var gs: float = f.groundspeed_kt()
		_finish("Engine-off touchdown at %.2f m/s (%s), ground speed %.0f kt. NR below 90%% for %.1f s, above 107%% for %.1f s." % [sink, Landing.rate(sink), gs, _stats["nr_low"], _stats["nr_high"]])

# ------------------------------------------------------------------ progress
func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(progress_path) != OK:
		return
	if cf.has_section("best"):
		for k in cf.get_section_keys("best"):
			progress[k] = int(cf.get_value("best", k, -1))

func _save_progress() -> void:
	var cf := ConfigFile.new()
	for k in progress:
		cf.set_value("best", k, progress[k])
	cf.save(progress_path)
