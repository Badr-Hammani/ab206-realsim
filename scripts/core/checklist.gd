extends RefCounted
## Interactive checklists (M2.30). Loads data/checklists.json and runs one list at a time, in order.
## "auto" items tick themselves when the cockpit really is in that state (switch positions, N1,
## TOT, rotor, events such as the light-off); the others are things you look at or do outside
## the simulation (seat belts, altimeter, rotors clear): you confirm them with Enter or a click.
## Nothing is ticked on a timer alone.

const PATH := "res://data/checklists.json"
const KNOWN_AUTO := [
	"anti_ice_as_required", "anti_ice_off", "battery_off", "battery_on", "boost_off", "boost_pressure",
	"caution_tested", "collective_down", "controls_checked", "elec_off", "eng_out_on", "friction_off",
	"friction_on", "fuel_introduced", "fuel_valve_off", "fuel_valve_on", "generator_off", "generator_on",
	"gov_100", "hyd_checked", "hyd_off", "hyd_on", "idle_1min", "idle_2min", "instruments_static",
	"landed", "landing_light_off", "n1_70", "n1_reducing", "nr_in_limits", "oil_rising",
	"radios_lights_off", "radios_on", "rotor_turning", "start_cautions_on", "starter_on",
	"starter_released", "throttle_closed", "throttle_full", "throttle_past_idle", "tot_150",
	"tot_reducing", "tot_start_ok", "all_but_bat_off", "battery_off_safe", "collective_down_free",
	"cyc_x_hyd_off", "gov_range_checked", "hyd_cycled", "instruments_normal", "n1_idle_check", "nr_100",
	"oils_rising", "radios_off", "rotor_stopped", "rpm_horn_check", "throttle_idle",
	"cbs_in", "cb_ign_out", "cb_hyd_out", "cb_genfield_in", "cb_boost_out",
]

var about := ""
var lists: Array = []
var systems                     # engine_systems.gd
var fdm
var list_id := ""
var cur := 0                    # index of the current item
var state: Array = []           # per item: "" (open), "auto", "confirmed", "skipped"
var t0 := 0.0                   # sim time when the list was started
var log: Array[String] = []     # what happened (for the debrief)

# control travel seen since the list started (for "Flight controls - free and correct")
var _rng := {}
var _rng_hyd := {}              # cyclic travel while the hydraulics are OFF (hydraulics check)
var _gov_lo := 999.0
var _gov_hi := 0.0
var _idle_t := 0.0              # time at idle with the throttle at the idle stop
var _tot_prev := 0.0
var _n1_prev := 0.0

func _init() -> void:
	var fa := FileAccess.open(PATH, FileAccess.READ)
	if fa == null:
		push_warning("checklists.json missing")
		return
	var d = JSON.parse_string(fa.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		about = str(d.get("_about", ""))
		lists = d.get("lists", [])

func find(id: String) -> Dictionary:
	for l in lists:
		if l["id"] == id:
			return l
	return {}

func active() -> bool:
	return list_id != ""

func current_list() -> Dictionary:
	return find(list_id)

func items() -> Array:
	var l := current_list()
	return l.get("items", []) if not l.is_empty() else []

var _saved := {}                # list id -> [cur, state, t0] for lists you switched away from

## Shows a list, continuing where you left it if you looked at it before (panel picker).
func open_list(id: String) -> void:
	if id == list_id:
		return
	if active():
		_saved[list_id] = [cur, state.duplicate(), t0]
	if _saved.has(id):
		list_id = id
		cur = _saved[id][0]
		state = _saved[id][1]
		t0 = _saved[id][2]
		return
	start_list(id)

func start_list(id: String) -> void:
	_saved.erase(id)
	list_id = id
	cur = 0
	state = []
	for it in items():
		state.append("")
	t0 = fdm.sim_time if fdm != null else 0.0
	log.clear()
	_rng = {}
	_rng_hyd = {}
	_gov_lo = 999.0
	_gov_hi = 0.0
	_idle_t = 0.0
	_tot_prev = systems.tot if systems != null else 0.0
	_n1_prev = fdm.n1 if fdm != null else 0.0
	_skip_headings()

func stop() -> void:
	list_id = ""

func finished() -> bool:
	return active() and cur >= items().size()

func done_count() -> int:
	var n := 0
	for s in state:
		if s != "":
			n += 1
	return n

func countable() -> int:
	var n := 0
	for it in items():
		if not it.has("heading"):
			n += 1
	return n

func _skip_headings() -> void:
	var its := items()
	while cur < its.size() and its[cur].has("heading"):
		state[cur] = "auto"
		cur += 1

## Called once per frame with the pilot's control positions.
func note_controls(lon: float, lat: float, coll: float, ped: float) -> void:
	if not active():
		return
	for k in ["lon", "lat", "coll", "ped"]:
		var v: float = {"lon": lon, "lat": lat, "coll": coll, "ped": ped}[k]
		var r: Vector2 = _rng.get(k, Vector2(v, v))
		_rng[k] = Vector2(minf(r.x, v), maxf(r.y, v))
	if systems != null and not systems.hydraulics and fdm.nr_pct() > 90.0:
		for k in ["lon", "lat"]:
			var v2: float = lon if k == "lon" else lat
			var r2: Vector2 = _rng_hyd.get(k, Vector2(v2, v2))
			_rng_hyd[k] = Vector2(minf(r2.x, v2), maxf(r2.y, v2))

func controls_checked() -> bool:
	if _rng.size() < 4:
		return false
	return _rng["lon"].x < -0.7 and _rng["lon"].y > 0.7 and _rng["lat"].x < -0.7 and _rng["lat"].y > 0.7 \
		and _rng["ped"].x < -0.7 and _rng["ped"].y > 0.7 and _rng["coll"].y > 0.6

func update(dt: float) -> void:
	if not active() or systems == null:
		return
	var s = systems
	var f = fdm
	_gov_lo = minf(_gov_lo, f.gov_set_pct)
	_gov_hi = maxf(_gov_hi, f.gov_set_pct) if _gov_lo <= 97.5 else _gov_hi
	if f.lit and not f.starting and f.throttle < 0.02:
		_idle_t += dt
	else:
		_idle_t = 0.0
	var its := items()
	var guard := 0
	while cur < its.size() and guard < 3:
		guard += 1
		var it: Dictionary = its[cur]
		if it.has("heading"):
			_skip_headings()
			continue
		if not it.has("auto"):
			break
		if eval(str(it["auto"])):
			state[cur] = "auto"
			log.append("%5.0f s  %s - %s" % [f.sim_time - t0, it["item"], it["action"]])
			cur += 1
			_skip_headings()
		else:
			break
	_tot_prev = lerpf(_tot_prev, s.tot, clampf(dt / 2.0, 0.0, 1.0))
	_n1_prev = lerpf(_n1_prev, f.n1, clampf(dt / 2.0, 0.0, 1.0))

## You confirm the current item (Enter / click). Automatic items can be skipped this way
## (marked "skipped" so a lesson can see it).
func confirm() -> void:
	var its := items()
	if cur >= its.size():
		return
	var it: Dictionary = its[cur]
	state[cur] = "skipped" if it.has("auto") else "confirmed"
	log.append("%5.0f s  %s - %s (%s)" % [fdm.sim_time - t0, it["item"], it["action"], state[cur]])
	cur += 1
	_skip_headings()

func _ev_since(key: String) -> bool:
	return systems.ev.has(key) and float(systems.ev[key]) >= t0

func eval(key: String) -> bool:
	var s = systems
	var f = fdm
	match key:
		"controls_checked":
			return controls_checked()
		"throttle_closed":
			return s.throttle_closed
		"landing_light_off":
			return not s.landing_light
		"anti_ice_off":
			return not s.anti_ice
		"anti_ice_as_required":
			return s.anti_ice or s.oat_c > 4.4
		"hyd_on":
			return s.hydraulics
		"hyd_off":
			return not s.hydraulics
		"hyd_checked":
			return _ev_since("hyd_check_t")
		"fuel_valve_on":
			return s.fuel_valve
		"fuel_valve_off":
			return not s.fuel_valve
		"instruments_static":
			return f.n1 < 1.0 and f.nr_pct() < 1.0
		"battery_on":
			return s.battery
		"battery_off":
			return not s.battery
		"start_cautions_on":
			return s.cautions["ENG OUT"] and s.cautions["TRANS OIL PRESS"] and s.cautions["ROTOR LOW RPM"]
		"caution_tested":
			return _ev_since("caution_test_t")
		"collective_down":
			return f.collective < 0.03
		"boost_pressure":
			return s.cb_in("FUEL BOOST FWD") and s.cb_in("FUEL BOOST AFT") and s.bus_powered and s.fuel_psi >= 4.0 and not s.cautions["FUEL PUMP"]
		"boost_off":
			return not s.cb_in("FUEL BOOST FWD") and not s.cb_in("FUEL BOOST AFT")
		"cbs_in":
			for b in s.breakers_out():
				if not str(b).begins_with("FUEL BOOST"):
					return false
			return true
		"cb_ign_out":
			return not s.cb_in("IGN ENG")
		"cb_hyd_out":
			return not s.cb_in("HYD BOOST")
		"cb_genfield_in":
			return s.cb_in("GEN FIELD")
		"cb_boost_out":
			return not s.cb_in("FUEL BOOST FWD") and not s.cb_in("FUEL BOOST AFT")
		"tot_150":
			return s.tot <= 150.0
		"starter_on":
			return f.starter or _ev_since("starter_on_t")
		"fuel_introduced":
			return _ev_since("light_off_t")
		"tot_start_ok":
			return f.lit and f.n1 > 35.0 and s.tot_over["927"] <= 1.0
		"rotor_turning":
			return f.nr_pct() > 0.5 and f.n1 >= 25.0
		"oil_rising":
			return s.eng_oil_psi > 5.0
		"starter_released":
			return f.lit and not f.starter and _ev_since("starter_off_t")
		"throttle_past_idle":
			return f.lit and not f.starting and not s.throttle_closed
		"idle_1min":
			return _idle_t >= 60.0
		"idle_2min":
			return _idle_t >= 120.0
		"n1_70":
			return f.lit and f.n1 >= 68.0
		"generator_on":
			return s.generator
		"generator_off":
			return not s.generator
		"radios_on":
			return s.radios
		"radios_lights_off":
			return not s.radios and not s.landing_light
		"throttle_full":
			return f.lit and f.throttle >= 0.98
		"gov_100":
			return f.gov_set_pct >= 99.5
		"friction_off":
			return not s.friction
		"friction_on":
			return s.friction
		"tot_reducing":
			return not f.lit and s.tot < _tot_prev - 1.0 or (not f.lit and s.tot < 150.0)
		"n1_reducing":
			return not f.lit and (f.n1 < _n1_prev - 0.2 or f.n1 < 1.0)
		"eng_out_on":
			return s.cautions["ENG OUT"]
		"nr_in_limits":
			return f.nr_pct() >= 90.0 and f.nr_pct() <= 107.0
		"landed":
			return f.on_ground and f.groundspeed_kt() < 3.0
		"elec_off":
			return not s.battery and not s.generator
		"all_but_bat_off":
			return not s.generator and not s.radios and not s.landing_light and not s.anti_ice
		"battery_off_safe":
			return not s.battery and f.n1 < 1.0
		"collective_down_free":
			return f.collective < 0.03 and not s.friction
		"cyc_x_hyd_off":
			return _rng_hyd.size() == 2 and _rng_hyd["lon"].x < -0.1 and _rng_hyd["lon"].y > 0.1 and _rng_hyd["lat"].x < -0.1 and _rng_hyd["lat"].y > 0.1
		"gov_range_checked":
			return _gov_lo <= 97.5 and _gov_hi >= 99.5
		"hyd_cycled":
			return _ev_since("hyd_cycle_t")
		"instruments_normal":
			return f.lit and f.nr_pct() >= 97.0 and f.nr_pct() <= 100.5 and s.lit_cautions().is_empty()
		"n1_idle_check":
			return f.lit and not f.starting and f.throttle < 0.02 and f.n1 >= 59.5 and f.n1 <= 62.5
		"nr_100":
			return f.lit and f.nr_pct() >= 99.0 and f.nr_pct() <= 101.0
		"oils_rising":
			return s.eng_oil_psi > 30.0 and s.xmsn_oil_psi > 1.0
		"radios_off":
			return not s.radios
		"rotor_stopped":
			return f.nr_pct() < 1.0
		"rpm_horn_check":
			return _ev_since("horn_check_t")
		"throttle_idle":
			return f.lit and f.throttle < 0.02 and not s.throttle_closed
	return false

## Text of the current item for the HUD strip.
func current_text() -> String:
	var its := items()
	if cur >= its.size():
		return "%s complete" % current_list().get("title", "")
	var it: Dictionary = its[cur]
	return "%s - %s" % [it["item"], it["action"]]

func current_is_manual() -> bool:
	var its := items()
	return cur < its.size() and not its[cur].has("auto")
