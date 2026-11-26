extends RefCounted
## Bell 206B-3 cockpit systems for the start / run-up / shutdown checklists (M2.30):
## switches, electrical bus, fuel, starter, throttle CLOSED (cut-off) position, TOT, oil and fuel
## pressures, caution lights and exceedance recording.
##
## Sources (see docs/DATA_SOURCES.md and data/checklists.json):
##  - Procedures and the start numbers (light-off at 15% N1 above 7 C / 13% from -18 to +7 C /
##    12% below -18 C, starter release at 58% N1, rotor turning by 25% N1, TOT 150 C or below before
##    the start, idle 1 minute, 70% N1, governor 97-100%) come from the Bell 206 checklist the
##    student supplied (helicopter.daviesgarden.com). TOT and torque limits likewise.
##  - Emergency actions (throttle CLOSED, fuel valve OFF, BATT OFF ...) from the student's
##    AgustaBell AB206 flight manual E-AB206-250-1 Section 3.
##  - Everything marked SIMULATION below (TOT curve, pressures, fuel burn, light thresholds) is an
##    estimate chosen to behave like the real engine on the gauges; it is not manufacturer data.

var fdm

# ------------------------------------------------------------------ switches
var battery := true
var generator := true
var fuel_valve := true
var boost := true
var hydraulics := true
var anti_ice := false
var landing_light := false
var radios := true
var friction := false
var caution_test := false         # press-to-test (held)
var starter_btn := false          # starter button (held)
var throttle_closed := false      # twist grip rolled past the idle stop to CLOSED (fuel cut off)

# ------------------------------------------------------- overhead circuit breakers (M2.30)
## The 206B-3 overhead console. Bell BHT-206B3-FM-1 names these breakers in its procedures
## (source "FM"): FUEL BOOST AFT / FWD (preflight + prestart: the boost pumps have no switch, they
## run whenever their breakers are in and the bus is powered), CAUTION LT, FUEL VALVE, IGN ENG
## (engine fire during start: "IGN ENG circuit breaker - Out"), HYD BOOST (hydraulic failure:
## "HYD BOOST circuit breaker - Out; if power is not restored - In"), PA SYST.
## GEN FIELD comes from the AB206 E-AB206-250-1 electrical emergency ("Generator field circuit
## breaker - check IN"). The others ("TYPICAL") are breakers a 206 overhead normally carries; the
## manual does not list them. The manual has NO drawing of the overhead console, so the
## arrangement on screen is a SIMULATION layout until we copy a photo of the real one.
## [name, group, source, what pulling it does in the sim]
const BREAKERS := [
	["START", "ENGINE", "TYPICAL", "starter dead"],
	["IGN ENG", "ENGINE", "FM", "no ignition: no light-off (a running engine keeps running)"],
	["FUEL VALVE", "ENGINE", "FM", "fuel valve stays where it is (switch has no effect)"],
	["GOV", "ENGINE", "TYPICAL", "governor RPM beep switch dead"],
	["ENG ANTI ICE", "ENGINE", "TYPICAL", "anti-ice valve fails OPEN (anti-ice on, TOT +15 C)"],
	["FUEL BOOST FWD", "FUEL", "FM", "forward boost pump off (FUEL PUMP light)"],
	["FUEL BOOST AFT", "FUEL", "FM", "aft boost pump off (FUEL PUMP light)"],
	["FUEL QTY", "FUEL", "TYPICAL", "fuel quantity gauge reads zero"],
	["GEN FIELD", "ELECTRICAL", "AB206 FM", "generator off line (GEN FAIL)"],
	["CAUTION LT", "ELECTRICAL", "FM", "all caution lights dark (they cannot warn you)"],
	["INST LT", "ELECTRICAL", "TYPICAL", "no effect in the sim"],
	["HYD BOOST", "FLIGHT", "FM", "hydraulic solenoid de-energised: hydraulics ON whatever the switch says"],
	["PITOT HTR", "FLIGHT", "TYPICAL", "no effect in the sim"],
	["LDG LT", "LIGHTS", "TYPICAL", "landing light off"],
	["ANTI COLL", "LIGHTS", "TYPICAL", "no effect in the sim"],
	["NAV LT", "LIGHTS", "TYPICAL", "no effect in the sim"],
	["COMM", "AVIONICS", "TYPICAL", "radios off"],
	["NAV", "AVIONICS", "TYPICAL", "radios off"],
	["PA SYST", "AVIONICS", "FM", "no effect in the sim"],
]
var cb := {}                      # breaker name -> true = IN (pushed), false = OUT (pulled)

# ------------------------------------------------------------------ outputs
var bus_powered := true
var gen_online := true
var tot := 0.0                    # turbine outlet temperature, deg C
var eng_oil_psi := 0.0
var xmsn_oil_psi := 0.0
var fuel_psi := 0.0
var eng_oil_c := 15.0             # SIMULATION oil temperatures (warm up with running time)
var xmsn_oil_c := 15.0
var gen_amps := 0.0               # SIMULATION generator load (ammeter)
var fuel_lb := 400.0              # SIMULATION default load (206B-3 tank ~91 US gal = ~610 lb)
var hyd_available := true
var cautions := {}                # name -> lit (true also while press-to-test is held)
var oat_c := 15.0

# ------------------------------------------------------------- start record
## What happened during the last start / shutdown (read by the checklist and the lessons).
var ev := {}
var tot_peak := 0.0               # highest TOT since the last start began
var tot_over := {"738": 0.0, "810": 0.0, "927": 0.0}   # seconds above each limit (this start/flight)
var exceedances: Array[String] = []
var starter_time := 0.0           # seconds the starter has been engaged in this attempt

# Thresholds (RFM = Bell BHT-206B3-FM-1; GEN ONLINE = SIMULATION estimate)
const ENG_OUT_N1 := 55.0          # ENG OUT warning below this N1 (RFM Section 3: "N1 less than 55%")
const GEN_ONLINE_N1 := 50.0       # generator comes on line above this N1
const TRANS_OIL_MIN := 30.0       # TRANS OIL PRESS caution below this, psi (RFM Section 1: 30 psi minimum)
const LOW_FUEL_LB := 134.0        # FUEL LOW light: about 20 US gal (RFM Section 3, S/N 4110 and prior) x 6.7 lb/gal
const CAUTION_NAMES := ["ENG OUT", "ROTOR LOW RPM", "TRANS OIL PRESS", "GEN FAIL", "FUEL PUMP", "HYD PRESS", "FUEL LOW", "TOT"]

var _was_lit := true
var _was_starter := false
var _light_n1 := 0.0
var _start_peak := 0.0
var _hung := 0.0
var _tot_red_t810 := 0.0
var _tot_red_t927 := 0.0
var horn := false                # ROTOR LOW RPM audio on
var hyd_failed := false           # failure injection (hydraulic pump)
var _valve_frozen := true
var starter_cycle := 0           # starter engagements since the starter cooled for 30 min (SIMULATION bookkeeping)
var _starter_rest := 1800.0

func _init(f) -> void:
	fdm = f
	oat_c = _oat()
	tot = 420.0
	for n in CAUTION_NAMES:
		cautions[n] = false
	all_breakers_in()

func all_breakers_in() -> void:
	for b in BREAKERS:
		cb[b[0]] = true

func cb_in(name: String) -> bool:
	return bool(cb.get(name, true))

## Breakers pulled at the moment (for the checklist "Circuit breakers - In").
func breakers_out() -> Array:
	var out := []
	for b in BREAKERS:
		if not cb_in(b[0]):
			out.append(b[0])
	return out

func pull_breaker(name: String, out := true) -> void:
	if cb.has(name):
		cb[name] = not out

func _oat() -> float:
	return fdm.atmo.temperature_k(fdm.pos.y) - 273.15

## Engine running, everything on (the old default start, and every flying lesson).
func engine_running() -> void:
	battery = true
	generator = true
	fuel_valve = true
	boost = true
	hydraulics = true
	radios = true
	anti_ice = false
	friction = false
	starter_btn = false
	caution_test = false
	throttle_closed = false
	all_breakers_in()
	fdm.lit = true
	fdm.starting = false
	fdm.starter = false
	fdm.fuel_available = true
	fdm.gov_set_pct = 100.0
	oat_c = _oat()
	tot = _running_tot()
	eng_oil_c = oat_c + 60.0
	xmsn_oil_c = oat_c + 50.0
	_was_lit = true
	ev = {}
	tot_peak = tot
	tot_over = {"738": 0.0, "810": 0.0, "927": 0.0}
	exceedances.clear()
	_tot_red_t810 = 0.0
	_tot_red_t927 = 0.0

## Cold and dark: engine stopped and cool, rotor stopped, every switch OFF, throttle CLOSED.
func cold_and_dark(hot_engine := false) -> void:
	battery = false
	generator = false
	fuel_valve = false
	boost = false
	hydraulics = false
	radios = false
	anti_ice = false
	landing_light = false
	friction = true
	starter_btn = false
	caution_test = false
	throttle_closed = true
	all_breakers_in()
	# the preflight fuel-sump drain ends with the FUEL BOOST breakers OUT (FM page 2-5); the
	# prestart check pushes them back in
	cb["FUEL BOOST FWD"] = false
	cb["FUEL BOOST AFT"] = false
	fdm.lit = false
	fdm.starting = false
	fdm.starter = false
	fdm.fuel_available = false
	fdm.n1 = 0.0
	fdm.nr = 0.0
	fdm.n2 = 0.0
	fdm.engaged = true
	fdm.gov_set_pct = 97.0
	oat_c = _oat()
	tot = 260.0 if hot_engine else oat_c
	eng_oil_c = 60.0 if hot_engine else oat_c
	xmsn_oil_c = 55.0 if hot_engine else oat_c
	_was_lit = false
	ev = {}
	tot_peak = tot
	tot_over = {"738": 0.0, "810": 0.0, "927": 0.0}
	exceedances.clear()
	starter_time = 0.0
	_tot_red_t810 = 0.0
	_tot_red_t927 = 0.0

func engine_out() -> bool:
	return not fdm.lit or fdm.n1 < ENG_OUT_N1

## Called by main every physics frame BEFORE fdm.step().
func pre_step(dt: float, controls) -> void:
	oat_c = _oat()
	gen_online = generator and fdm.lit and fdm.n1 > GEN_ONLINE_N1
	bus_powered = battery or gen_online
	if throttle_closed:
		controls.throttle = 0.0
	# breakers: what pulling them does
	gen_online = gen_online and cb_in("GEN FIELD")
	bus_powered = battery or gen_online
	if not cb_in("FUEL VALVE"):
		fuel_valve = _valve_frozen
	_valve_frozen = fuel_valve
	boost = bus_powered and (cb_in("FUEL BOOST FWD") or cb_in("FUEL BOOST AFT"))
	if not cb_in("ENG ANTI ICE"):
		anti_ice = true
	if not cb_in("LDG LT"):
		landing_light = false
	if not cb_in("COMM") or not cb_in("NAV"):
		radios = false
	fdm.ignition = bus_powered and cb_in("IGN ENG")
	fdm.fuel_available = fuel_valve and not throttle_closed and fuel_lb > 0.0
	fdm.starter = starter_btn and battery and cb_in("START")
	if fdm.starter:
		starter_time += dt
	# Bell 206: the solenoid valve is energised to turn the hydraulics OFF, so with the HYD BOOST
	# breaker pulled (or no power) the boost stays ON (RFM Section 3, hydraulic power failure)
	var hyd_on: bool = hydraulics or not cb_in("HYD BOOST") or not bus_powered
	hyd_available = hyd_on and fdm.nr_pct() > 40.0 and not hyd_failed   # pump driven by the transmission

## Called by main every physics frame AFTER fdm.step().
func post_step(dt: float) -> void:
	var n1: float = fdm.n1
	# --- events for the checklist / lessons
	if fdm.starter and not _was_starter:
		if _starter_rest < 60.0 and starter_cycle > 0 and not exceedances.has("starter re-engaged before 60 s cooling"):
			exceedances.append("starter re-engaged before 60 s cooling")
		starter_cycle += 1
		if starter_cycle > 3 and not exceedances.has("more than 3 starter cycles without 30 min cooling"):
			exceedances.append("more than 3 starter cycles without 30 min cooling")
		_starter_rest = 0.0
		ev["starter_on_t"] = fdm.sim_time
		ev["starter_on_tot"] = tot
		ev.erase("starter_off_n1")
		starter_time = 0.0
		if not fdm.lit:
			tot_peak = tot
			tot_over = {"738": 0.0, "810": 0.0, "927": 0.0}
			_hung = 0.0
	if _was_starter and not fdm.starter:
		ev["starter_off_n1"] = n1
		ev["starter_off_t"] = fdm.sim_time
	_was_starter = fdm.starter
	if fdm.lit and not _was_lit:
		_light_n1 = n1
		ev["light_off_n1"] = n1
		ev["light_off_tot"] = tot
		ev["light_off_throttle"] = fdm.throttle
		ev["light_off_t"] = fdm.sim_time
		ev.erase("idle_t")
		_start_peak = _start_peak_for(n1, tot)
	if not fdm.lit and _was_lit:
		ev["flameout_t"] = fdm.sim_time
		ev["flameout_n1"] = n1
	_was_lit = fdm.lit
	if caution_test and bus_powered and cb_in("CAUTION LT"):
		ev["caution_test_t"] = fdm.sim_time
	if bus_powered and cautions.get("ROTOR LOW RPM", false) and horn:
		ev["horn_up_t"] = fdm.sim_time
	if ev.has("horn_up_t") and fdm.collective < 0.03 and bus_powered and not horn and fdm.sim_time - float(ev["horn_up_t"]) < 60.0:
		ev["horn_check_t"] = fdm.sim_time
	if not hydraulics:
		ev["hyd_sw_off_t"] = fdm.sim_time
	elif ev.has("hyd_sw_off_t") and fdm.sim_time - float(ev["hyd_sw_off_t"]) < 30.0:
		ev["hyd_cycle_t"] = fdm.sim_time
	if not hydraulics and fdm.nr_pct() > 90.0:
		ev["hyd_off_t"] = fdm.sim_time
	elif hydraulics and ev.has("hyd_off_t") and fdm.sim_time - float(ev["hyd_off_t"]) < 60.0:
		ev["hyd_check_t"] = fdm.sim_time
	if fdm.lit and not fdm.starting and not ev.has("idle_t"):
		ev["idle_t"] = fdm.sim_time
	if fdm.lit and fdm.throttle > 0.02 and not ev.has("throttle_open_t") and ev.has("idle_t"):
		ev["throttle_open_t"] = fdm.sim_time
	# --- TOT (SIMULATION)
	var target: float
	var tau := 2.0
	if fdm.lit and fdm.starting:
		# peak just after light-off, falling as airflow increases towards idle
		var k := clampf((n1 - _light_n1) / maxf(45.0 - _light_n1, 1.0), 0.0, 1.0)
		target = lerpf(_start_peak, 470.0, k)
		if not fdm.starter and n1 < 50.0:
			_hung += dt
			target += minf(_hung * 40.0, 400.0)       # hung start: TOT keeps climbing
		target += fdm.throttle * 900.0                # extra fuel with the throttle opened during the start
		tau = 1.2
	elif fdm.lit:
		target = _running_tot()
		tau = 3.0
	else:
		target = oat_c
		tau = 20.0 if fdm.n1 > 5.0 else 120.0          # motoring / spool-down airflow cools much faster
	tot += (target - tot) * clampf(dt / tau, 0.0, 1.0)
	if fdm.starter or fdm.starting:
		tot_peak = maxf(tot_peak, tot)
	for lim in [738, 810, 927]:
		if tot > lim:
			tot_over[str(lim)] += dt
	_tot_red_t810 = _tot_red_t810 + dt if tot > 812.0 else 0.0
	_tot_red_t927 = _tot_red_t927 + dt if tot >= 927.0 else 0.0
	if (fdm.starter or fdm.starting) and tot_over["810"] > 10.0 and not exceedances.has("start TOT: more than 10 s between 810 and 927 C"):
		exceedances.append("start TOT: more than 10 s between 810 and 927 C")
	# starter limits (RFM Section 1, battery start): 40 s ON / 60 s OFF / 40 s ON / 60 s OFF / 40 s ON / 30 min OFF
	if fdm.starter:
		if starter_time > 40.0 and not exceedances.has("starter engaged more than 40 s"):
			exceedances.append("starter engaged more than 40 s")
	else:
		_starter_rest += dt
		if _starter_rest >= 1800.0:
			starter_cycle = 0
	if tot > 927.0 and not exceedances.has("TOT above 927 C"):
		exceedances.append("TOT above 927 C")
	if tot_over["927"] > 1.0 and not exceedances.has("HOT START: more than 1 s above 927 C"):
		exceedances.append("HOT START: more than 1 s above 927 C")
	if fdm.torque_pct > 100.0 and not exceedances.has("torque above 100%"):
		exceedances.append("torque above 100%")
	# --- pressures (SIMULATION)
	# SIMULATION: inside the RFM limits at every N1 (50 psi min below 76.5%, 90 to 94.2%, 115 above, 130 max)
	eng_oil_psi = 125.0 * clampf(n1 / 100.0, 0.0, 1.05)
	var eng_target: float = oat_c + (55.0 + 15.0 * fdm.gas_power(n1, 1.0) / fdm.p_engine_rated if fdm.lit else 0.0)
	eng_oil_c = lerpf(eng_oil_c, eng_target, clampf(dt / 240.0, 0.0, 1.0))
	var xm_target: float = oat_c + 50.0 * clampf(fdm.nr_pct() / 100.0, 0.0, 1.0)
	xmsn_oil_c = lerpf(xmsn_oil_c, xm_target, clampf(dt / 300.0, 0.0, 1.0))
	if gen_online:
		var charge: float = 40.0 * exp(-maxf(fdm.sim_time - float(ev.get("idle_t", -1000.0)), 0.0) / 90.0)
		gen_amps = 18.0 + (8.0 if radios else 0.0) + (15.0 if landing_light else 0.0) + (5.0 if anti_ice else 0.0) + charge
	else:
		gen_amps = 0.0
	xmsn_oil_psi = 50.0 * pow(clampf(fdm.nr_pct() / 100.0, 0.0, 1.1), 1.5)
	var pumps := (1 if cb_in("FUEL BOOST FWD") else 0) + (1 if cb_in("FUEL BOOST AFT") else 0)
	fuel_psi = ((5.0 + 1.5 * pumps) if bus_powered and pumps > 0 and fuel_valve else 0.0)   # SIMULATION
	# --- fuel burn (SIMULATION: ~30 lb/h at idle to ~190 lb/h at take-off power)
	if fdm.lit:
		var frac: float = fdm.gas_power(n1, 1.0) / fdm.p_engine_rated
		fuel_lb = maxf(fuel_lb - (30.0 + 210.0 * frac) / 3600.0 * dt, 0.0)
	# --- caution lights (need electrical power)
	var on := {
		"ENG OUT": engine_out(),
		"ROTOR LOW RPM": fdm.nr_pct() < fdm._v("low_rpm_warning_pct"),
		"TRANS OIL PRESS": xmsn_oil_psi < TRANS_OIL_MIN,
		"GEN FAIL": not gen_online,
		"FUEL PUMP": not (cb_in("FUEL BOOST FWD") and cb_in("FUEL BOOST AFT")),   # one or both pumps off
		"HYD PRESS": not hyd_available,
		"FUEL LOW": fuel_lb < LOW_FUEL_LB,
		# red TOT light (fitted to some helicopters): 812-927 C for 10 s, or 927 C or more for 1 s
		"TOT": _tot_red_t810 >= 10.0 or _tot_red_t927 >= 1.0 or exceedances.has("TOT light"),
	}
	if (_tot_red_t810 >= 10.0 or _tot_red_t927 >= 1.0) and not exceedances.has("TOT light"):
		exceedances.append("TOT light")
	# horn (ROTOR LOW RPM audio): not with the collective full down (RFM prestart check)
	horn = bus_powered and (caution_test or bool(on["ROTOR LOW RPM"])) and fdm.collective > 0.03
	var lamps: bool = bus_powered and cb_in("CAUTION LT")
	for n in CAUTION_NAMES:
		cautions[n] = lamps and (caution_test or bool(on[n]))

func _running_tot() -> float:
	# SIMULATION: ~400 C at ground idle, ~720 C at max continuous torque (85%), ~780 C at 100%
	var frac: float = fdm.gas_power(fdm.n1, 1.0) / fdm.p_engine_rated
	return 400.0 + 500.0 * frac + (oat_c - 15.0) * 1.2 + (15.0 if anti_ice and fdm.lit else 0.0)   # RFM: TOT rises when anti-icing is switched on

## SIMULATION: start TOT peak. A normal start peaks around 700-760 C. Fuel introduced early
## (low N1), a hot engine (TOT above 150 C) or a high OAT make it hotter.
func _start_peak_for(n1: float, tot_now: float) -> float:
	var p := 800.0
	if n1 < 12.0:
		p += (12.0 - n1) * 90.0
	p += maxf(tot_now - 150.0, 0.0) * 1.4
	p += maxf(oat_c - 15.0, 0.0) * 1.5
	return p

## Light-off N1 the checklist asks for at this OAT.
func light_off_n1() -> float:
	if oat_c > 7.0:
		return 15.0
	if oat_c >= -18.0:
		return 13.0
	return 12.0

## Short engine/system readout for the HUD and the systems panel.
func summary() -> String:
	return "TOT %3.0f C   ENG OIL %3.0f psi   TRANS OIL %2.0f psi   FUEL %3.0f lb  %s psi   BUS %s   GOV %3.0f%%" % [tot, eng_oil_psi, xmsn_oil_psi, fuel_lb, "%2.0f" % fuel_psi, "ON" if bus_powered else "OFF", fdm.gov_set_pct]

func lit_cautions() -> Array:
	var a := []
	for n in CAUTION_NAMES:
		if cautions[n]:
			a.append(n)
	return a
