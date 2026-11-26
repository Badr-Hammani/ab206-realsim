extends RefCounted
## AB206 REALSIM flight dynamics model (FDM) for the Bell 206B-3.
##
## A six-degree-of-freedom rigid body with:
##  - main rotor: blade-element thrust with uniform momentum inflow (Heffley & Mnich,
##    NASA CR-177476 "minimum-complexity helicopter simulation math model" style),
##    first-order tip-path-plane flapping, flapback and transverse-flow terms,
##    ground effect (Hayden), blade-stall thrust limit, induced + profile power,
##  - teetering hub: no hub moment, control power only from thrust-vector tilt
##    (so control authority fades at low rotor thrust, as on the real aircraft),
##  - tail rotor with the same thrust/inflow model, driven from the main gearbox,
##  - fuselage drag, rotor-wash download, horizontal stabilizer, vertical fin,
##  - free-turbine engine (N1 gas producer, N2 power turbine), N2 governor with
##    collective anticipation, throttle, freewheel (sprag) clutch so the rotor can
##    autorotate with the engine at idle (needle split),
##  - rotor rpm from a torque balance on the rotor inertia,
##  - skid contact with spring/damper and friction against terrain and buildings.
##
## Internally forces/moments are computed in the aerodynamic body frame
## (x forward, y right, z down). Position and orientation use Godot world axes
## (X east, Y up, Z south) so the visuals use the state directly.
##
## Everything here is a model: see docs/FLIGHT_MODEL.md for the limits.

const Atmosphere = preload("res://scripts/fdm/atmosphere.gd")

const G := 9.80665
const KT := 0.514444
const FT := 0.3048
const HP := 745.7

# ----------------------------------------------------------------- parameters
var p := {}                     # raw values from the data file
var mass := 1200.0
var inertia := Vector3(1300, 3600, 3000)   # aero body Ixx, Iyy, Izz

var R := 5.08
var A := 81.07
var omega100 := 41.26
var sigma := 0.041
var a_lift := 5.7
var cd0 := 0.0085
var kappa := 1.15
var tau_flap := 0.077
var I_rotor := 800.0
var I_pt := 20.0
var theta_min := 0.0
var theta_max := 0.24
var cyc_lon := 0.17
var cyc_lat := 0.12
var cyc_rig := 0.05
var cyc_rig_lat := 0.02
var mast_tilt := 0.087
var hub_h := 1.65
var flap_stop := 0.17

var tr_R := 0.825
var tr_A := 2.14
var tr_gear := 6.47
var tr_sigma := 0.093
var tr_arm := 6.0
var tr_h := 0.9
var tr_pitch_left := 0.35
var tr_pitch_right := -0.14

var f_x := 0.95
var f_y := 6.0
var f_z := 4.0
var hs_S := 0.9
var hs_arm := 4.6
var hs_inc := -0.035
var vf_S := 0.9
var vf_arm := 5.8
var vf_inc := 0.052

var p_loss := 6000.0
var q100 := 5730.0             # rotor-shaft torque that reads 100% on the torque meter
var p_engine_rated := 313000.0
var n1_idle := 62.0
var n1_max := 105.0
var n1_zero_power := 60.4
var n1_accel := 10.0
var gov_kp := 220.0
var gov_ki := 120.0

var contact_points: Array[Vector3] = []    # Godot body coordinates
var cg_height := 1.15

# ------------------------------------------------------------------ controls
var collective := 0.0   # 0 = full down, 1 = full up
var cyclic_lon := 0.0   # +1 = full forward stick
var cyclic_lat := 0.0   # +1 = full right stick
var pedal := 0.0        # +1 = full right pedal
var throttle := 1.0     # 0 = idle, 1 = full open (governor in control)

# ------------------------------------------------- engine start / shutdown (M2.30)
## Set every step by engine_systems.gd (switches, fuel valve, throttle CLOSED position, starter).
## Defaults = engine running, so the flight-model tests and the "engine running" start are unchanged.
var lit := true                     # combustion running in the gas producer
var ignition := true                 # igniter powered (IGN ENG breaker in, bus powered) - M2.30
var fuel_available := true          # fuel valve ON, fuel pressure, throttle NOT in the closed (cut-off) position
var starter := false                # starter-generator motoring the gas producer (needs electrical power)
var starting := false               # light-off done, accelerating to ground idle
var gov_set_pct := 100.0            # N2 governor setting (GOV RPM beep switch, 97-100%)
const STARTER_N1 := 24.0            # SIMULATION: N1 the starter alone can motor to (estimated)
const LIGHT_OFF_MIN_N1 := 8.0
const STALL_Q := 900.0              # SIMULATION: extra free-turbine torque at zero N2, N.m (tuned: ground idle NR ~55-60%)       # SIMULATION: below this the igniter cannot light the fuel (estimated)

# --------------------------------------------------------------------- state
var pos := Vector3.ZERO            # CG, Godot world
var vel := Vector3.ZERO            # world m/s
var basis := Basis.IDENTITY        # body -> world (Godot body: x right, y up, z back)
var omega := Vector3.ZERO          # aero body rates p (roll), q (pitch), r (yaw), rad/s
var nr := 41.26                    # rotor speed rad/s
var n2 := 41.26                    # power turbine speed (rotor-equivalent rad/s)
var engaged := true                # freewheel clutch engaged
var n1 := 85.0                     # gas producer %
var gov_int := 0.0
var a1 := 0.0                      # TPP aft tilt relative to shaft (rad)
var b1 := 0.0                      # TPP right tilt relative to shaft (rad)
var vi := 8.0                      # main rotor induced velocity m/s
var vi_tr := 10.0
var sim_time := 0.0

var atmo = Atmosphere.new()
var ground = null                  # object with height_at(x, z) and normal_at(x, z)

# ------------------------------------------------------------------- outputs
var thrust := 0.0
var tr_thrust := 0.0
var torque_pct := 0.0
var q_clutch := 0.0
var p_main := 0.0
var p_tail := 0.0
var ge_factor := 1.0               # induced velocity ratio IGE/OGE (1 = no ground effect)
var hub_agl := 10.0
var agl := 10.0                    # skid height above ground
var mu := 0.0
var ct_sigma := 0.0
var a1_ss := 0.0
var b1_ss := 0.0
var rho := 1.225
var wind := Vector3.ZERO
var air_body := Vector3.ZERO       # aero body air-relative velocity of CG
var on_ground := false
var contact_count := 0
var touchdown_sink := 0.0          # sink rate at last touchdown m/s
var touchdown_event := false
var max_contact_force := 0.0
var tail_strike := false
var mast_bump := false
var stalled := false
var vrs := 0.0                      # vortex ring state intensity 0..1
var vrs_enabled := true             # tests compare with/without
var force_world := Vector3.ZERO
var moment_body := Vector3.ZERO
var last_step_usec := 0

var _was_on_ground := false
var _anchors: Array = [null, null, null, null, null]

func _init(data: Dictionary) -> void:
	p = data
	_apply_data()

func _v(key: String) -> float:
	return float(p[key]["value"])

func _apply_data() -> void:
	R = _v("main_rotor_diameter_m") * 0.5
	A = PI * R * R
	omega100 = _v("rotor_rpm_100pct") * TAU / 60.0
	var b := _v("blade_count")
	sigma = b * _v("blade_chord_m") / (PI * R)
	a_lift = _v("blade_lift_slope_per_rad")
	cd0 = _v("blade_cd0")
	kappa = _v("induced_power_factor")
	tau_flap = 16.0 / (_v("lock_number") * omega100)
	I_rotor = _v("rotor_polar_inertia_kgm2")
	I_pt = _v("power_turbine_inertia_kgm2")
	theta_min = deg_to_rad(_v("collective_pitch_min_deg"))
	theta_max = deg_to_rad(_v("collective_pitch_max_deg"))
	cyc_lon = deg_to_rad(_v("cyclic_long_range_deg"))
	cyc_lat = deg_to_rad(_v("cyclic_lat_range_deg"))
	cyc_rig = deg_to_rad(_v("cyclic_rig_aft_deg"))
	cyc_rig_lat = deg_to_rad(_v("cyclic_rig_left_deg"))
	mast_tilt = deg_to_rad(_v("mast_forward_tilt_deg"))
	hub_h = _v("hub_height_above_cg_m")
	flap_stop = deg_to_rad(_v("mast_bumping_flap_deg"))
	tr_R = _v("tail_rotor_diameter_m") * 0.5
	tr_A = PI * tr_R * tr_R
	tr_gear = _v("tail_rotor_rpm_100pct") / _v("rotor_rpm_100pct")
	tr_sigma = 2.0 * _v("tail_rotor_chord_m") / (PI * tr_R)
	tr_arm = _v("tail_rotor_arm_m")
	tr_h = _v("tail_rotor_height_m")
	tr_pitch_left = deg_to_rad(_v("tail_pitch_full_left_deg"))
	tr_pitch_right = deg_to_rad(_v("tail_pitch_full_right_deg"))
	f_x = _v("fuselage_drag_area_m2")
	f_y = _v("fuselage_side_area_m2")
	f_z = _v("fuselage_vertical_area_m2")
	hs_S = _v("hstab_area_m2")
	hs_arm = _v("hstab_arm_m")
	hs_inc = deg_to_rad(_v("hstab_incidence_deg"))
	vf_S = _v("vfin_area_m2")
	vf_arm = _v("vfin_arm_m")
	vf_inc = deg_to_rad(_v("vfin_incidence_deg"))
	p_loss = _v("drivetrain_loss_kw") * 1000.0
	q100 = _v("torque_100pct_definition") * HP / omega100
	p_engine_rated = _v("engine_rated_power_shp") * HP
	n1_idle = _v("n1_idle_pct")
	n1_max = _v("n1_max_pct")
	n1_accel = _v("n1_accel_pct_per_s")
	gov_kp = _v("governor_kp")
	gov_ki = _v("governor_ki")
	cg_height = _v("cg_height_above_skids_m")
	# N1 at which power-turbine output reaches zero: chosen so idle gives ~2.5 kW,
	# which leaves N2 at ~70% when unloaded (needle split in autorotation).
	var ratio := pow(2500.0 / p_engine_rated, 1.0 / 1.5)
	n1_zero_power = (n1_idle - ratio * 100.0) / (1.0 - ratio)
	var ht := _v("skid_half_track_m")
	var fr := _v("skid_front_m")
	var rr := _v("skid_rear_m")
	contact_points = [
		Vector3(-ht, -cg_height, -fr), Vector3(ht, -cg_height, -fr),
		Vector3(-ht, -cg_height, rr), Vector3(ht, -cg_height, rr),
		Vector3(0.0, -cg_height * 0.15, tr_arm + 0.2),   # tail stinger
	]
	set_mass(_v("default_gross_weight_kg"))

func set_mass(kg: float) -> void:
	mass = clampf(kg, 700.0, 1600.0)
	var s := mass / 1200.0
	inertia = Vector3(_v("inertia_xx_kgm2"), _v("inertia_yy_kgm2"), _v("inertia_zz_kgm2")) * (0.5 + 0.5 * s)

# ------------------------------------------------------------ frame helpers
static func to_aero(v: Vector3) -> Vector3:
	return Vector3(-v.z, v.x, -v.y)

static func from_aero(a: Vector3) -> Vector3:
	return Vector3(a.y, -a.z, -a.x)

func world_to_aero(v: Vector3) -> Vector3:
	return to_aero(basis.transposed() * v)

func aero_to_world(a: Vector3) -> Vector3:
	return basis * from_aero(a)

func ground_height(x: float, z: float) -> float:
	if ground == null:
		return 0.0
	return ground.height_at(x, z)

func ground_normal(x: float, z: float) -> Vector3:
	if ground == null:
		return Vector3.UP
	return ground.normal_at(x, z)

# ------------------------------------------------------------- engine curve
func gas_power(n1_pct: float, density_ratio: float) -> float:
	var x := clampf((n1_pct - n1_zero_power) / (100.0 - n1_zero_power), 0.0, 1.3)
	return p_engine_rated * pow(x, 1.5) * clampf(density_ratio, 0.3, 1.3)

func n1_for_power(power: float, density_ratio: float) -> float:
	var x := pow(maxf(power, 0.0) / (p_engine_rated * clampf(density_ratio, 0.3, 1.3)), 1.0 / 1.5)
	return n1_zero_power + x * (100.0 - n1_zero_power)

## Free-turbine output torque (rotor-shaft equivalent) at power-turbine speed w.
func pt_torque(n1_pct: float, w: float, density_ratio: float) -> float:
	var pg := gas_power(n1_pct, density_ratio) if lit else 0.0
	if lit and n1_pct < n1_idle:
		# SIMULATION: below ground idle the gas flow still turns the free turbine a little, so the
		# main rotor starts to turn during the start (checklist: "main rotor turning by 25% N1")
		pg = maxf(pg, 2500.0 * pow(clampf((n1_pct - 15.0) / (n1_idle - 15.0), 0.0, 1.0), 2.0))
	var x := clampf(w / omega100, 0.0, 1.5)
	var q := pg / omega100 * (2.0 - x) - 150.0 * x * x
	if lit:
		# M2.30 SIMULATION: free-turbine stall torque. At low power-turbine speed (rotor starting or
		# at ground idle) the gas flow gives much more torque than near 100%; it fades out by 70% N2,
		# so the needle split in autorotation (N2 ~70-75% at idle) and all flight numbers are unchanged.
		q += STALL_Q * clampf((n1_pct - 12.0) / (n1_idle - 12.0), 0.0, 1.0) * pow(clampf(1.0 - x / 0.7, 0.0, 1.0), 1.5)
	return q

# ----------------------------------------------------------- aerodynamics
## Computes forces and moments for the current state and controls.
## Also returns rotor aerodynamic torque in out["q_rotor"] (rotor + tail + losses).
func compute_aero(out: Dictionary) -> void:
	var alt := pos.y
	rho = atmo.density(alt)
	var gh := ground_height(pos.x, pos.z)
	agl = pos.y - cg_height - gh
	wind = atmo.wind_at(maxf(agl, 0.0) + cg_height)
	air_body = world_to_aero(vel - wind)
	var w := omega                       # aero body rates

	var F := Vector3.ZERO
	var M := Vector3.ZERO
	var omr := maxf(nr, 1.0)
	var vtip := omr * R

	# ---------------- main rotor
	var r_hub := Vector3(0.0, 0.0, -hub_h)
	var v_hub := air_body + w.cross(r_hub)
	var tilt_fwd := mast_tilt - a1
	var n_up := Vector3(sin(tilt_fwd) * cos(b1), sin(b1), -cos(tilt_fwd) * cos(b1)).normalized()
	var w_r := -v_hub.dot(n_up)          # +ve = air coming up through the disc
	var v_inplane_vec := v_hub + n_up * w_r
	var v_inplane := v_inplane_vec.length()
	mu = v_inplane / vtip
	var theta75 := lerpf(theta_min, theta_max, clampf(collective, 0.0, 1.0))

	# ground effect (Hayden power ratio, applied to induced velocity) fading with airspeed
	var hub_world := pos + basis * Vector3(0.0, hub_h, 0.0)
	hub_agl = maxf(hub_world.y - ground_height(hub_world.x, hub_world.z), 0.3)
	var zr := maxf(hub_agl / R, 0.45)
	var k_hayden := minf(1.0, 1.0 / (0.9926 + 0.0379 * pow(2.0 / zr, 2.0)))
	var fade := 1.0 / (1.0 + pow(v_inplane / 12.0, 2.0))
	ge_factor = 1.0 - (1.0 - k_hayden) * fade

	var K := rho * a_lift * sigma * A * vtip / 4.0
	var wb := w_r + vtip * theta75 * (2.0 / 3.0 + mu * mu)
	var T := 0.0
	var v := vi
	for i in 8:
		T = (wb - v) * K
		var vhat2 := v_inplane * v_inplane + w_r * (w_r - 2.0 * v)
		var th := T / (2.0 * rho * A)
		var vi2 := sqrt(vhat2 * vhat2 * 0.25 + th * th) - vhat2 * 0.5
		var v_new := sqrt(maxf(vi2, 0.0)) * ge_factor
		v = lerpf(v, v_new, 0.6)
	vi = v
	T = (wb - vi) * K
	# ---- vortex ring state (VRS)
	# Momentum theory has no valid solution when the rotor descends into its own wake at
	# descent rates of roughly 0.3-2 x the hover induced velocity vh. There we use the
	# empirical curve fitted to flight/wind-tunnel data (Young 1978, as given in Leishman,
	# Principles of Helicopter Aerodynamics, ch. 2): vi/vh = k + k1 x + k2 x^2 + k3 x^3 + k4 x^4,
	# x = Vc/vh (negative in descent), k = 1.15, k1 = -1.125, k2 = -1.372, k3 = -1.718, k4 = -0.655
	# (k is the induced power factor, so the curve meets hover at 1.15 vh). The extra induced flow costs thrust
	# and power, and the wake breaking down adds thrust and moment fluctuations (amplitude
	# estimated). Forward or sideways speed above ~1 vh blows the wake away (Vuichard / forward
	# cyclic recovery). The envelope edges are estimates.
	vrs = 0.0
	var vh := sqrt(maxf(T, 0.0) / (2.0 * rho * A))
	if vh > 2.0 and vrs_enabled:
		var x := -w_r / vh
		var m := v_inplane / vh
		var env := clampf((-x - 0.25) / 0.35, 0.0, 1.0) * clampf((x + 2.0) / 0.4, 0.0, 1.0)
		var fade_v := clampf(1.0 - (m - 0.3) / 0.7, 0.0, 1.0)
		vrs = env * fade_v * ge_factor
		if vrs > 0.0:
			var poly := 1.15 - 1.125 * x - 1.372 * x * x - 1.718 * x * x * x - 0.655 * x * x * x * x
			var vi_emp := vh * poly * ge_factor
			vi = lerpf(vi, maxf(vi, vi_emp), vrs)
			var turb := sin(sim_time * 7.3) * 0.5 + sin(sim_time * 12.9 + 1.7) * 0.3 + sin(sim_time * 3.1 + 0.4) * 0.2
			T = (wb - vi) * K * (1.0 + 0.10 * vrs * turb)
			M += Vector3(sin(sim_time * 5.3 + 0.9), sin(sim_time * 4.1 + 2.3), 0.0) * (900.0 * vrs)
	# blade stall: thrust coefficient over solidity saturates
	var ct_s_raw := T / (rho * A * sigma * vtip * vtip)
	var ct_s_max := 0.135
	stalled = ct_s_raw > ct_s_max
	if ct_s_raw > ct_s_max:
		ct_s_raw = ct_s_max + (ct_s_raw - ct_s_max) * 0.15
	if ct_s_raw < -0.06:
		ct_s_raw = -0.06
	ct_sigma = ct_s_raw
	T = ct_s_raw * rho * A * sigma * vtip * vtip
	thrust = T

	var cd := cd0 + 1.8 * pow(maxf(ct_sigma - 0.09, 0.0), 2.0) * 10.0
	var p_prof := rho * A * pow(vtip, 3.0) * sigma * cd / 8.0 * (1.0 + 4.65 * mu * mu)
	var p_ind := T * (kappa * vi - w_r)
	p_main = p_ind + p_prof
	var h_force := 0.25 * sigma * cd * rho * A * vtip * vtip * mu
	var f_mr := n_up * T
	if v_inplane > 0.01:
		f_mr -= v_inplane_vec / v_inplane * h_force
	F += f_mr
	M += r_hub.cross(f_mr)

	# steady-state flapping targets: cyclic (feathering = flapping), flapback, transverse flow
	var lam := (vi - w_r) / vtip
	var flapback := mu * (8.0 / 3.0 * theta75 - 2.0 * lam) / (1.0 - 0.5 * mu * mu)
	var transverse := mu * (1.1 * vi / vtip + 4.0 / 3.0 * 0.035) / (1.0 + 0.5 * mu * mu)
	# flapback acts along the in-plane wind direction, transverse flow 90 deg to it
	var ux := 1.0
	var uy := 0.0
	if v_inplane > 0.5:
		ux = v_inplane_vec.x / v_inplane
		uy = v_inplane_vec.y / v_inplane
	else:
		flapback = 0.0
		transverse = 0.0
	a1_ss = -cyclic_lon * cyc_lon + cyc_rig + flapback * ux + transverse * uy
	b1_ss = cyclic_lat * cyc_lat - cyc_rig_lat + transverse * ux - flapback * uy
	mast_bump = sqrt(a1 * a1 + b1 * b1) > flap_stop

	# ---------------- tail rotor (on the tail, thrust pushes the tail to the right)
	var r_tr := Vector3(-tr_arm, 0.0, -tr_h)
	var v_tr := air_body + w.cross(r_tr)
	var tr_omega := omr * tr_gear
	var tr_vtip := tr_omega * tr_R
	var tr_wr := -v_tr.y                         # air flowing against the induced flow
	var tr_inplane := sqrt(maxf(v_tr.length_squared() - tr_wr * tr_wr, 0.0))
	var tr_mu := tr_inplane / tr_vtip
	var ped := clampf(pedal, -1.0, 1.0)
	var tr_theta := lerpf(tr_pitch_left, tr_pitch_right, (ped + 1.0) * 0.5)
	var tr_K := rho * a_lift * tr_sigma * tr_A * tr_vtip / 4.0
	var tr_wb := tr_wr + tr_vtip * tr_theta * (2.0 / 3.0 + tr_mu * tr_mu)
	var tT := 0.0
	var tv := vi_tr
	for i in 6:
		tT = (tr_wb - tv) * tr_K
		var tvh2 := tr_inplane * tr_inplane + tr_wr * (tr_wr - 2.0 * tv)
		var tth := tT / (2.0 * rho * tr_A)
		var tvi2 := sqrt(tvh2 * tvh2 * 0.25 + tth * tth) - tvh2 * 0.5
		var tv_abs := sqrt(maxf(tvi2, 0.0))
		tv = lerpf(tv, tv_abs * signf(tT) if absf(tT) > 1.0 else tv_abs, 0.6)
	vi_tr = tv
	tT = (tr_wb - vi_tr) * tr_K
	tT = clampf(tT, -0.12 * rho * tr_A * tr_sigma * tr_vtip * tr_vtip, 0.12 * rho * tr_A * tr_sigma * tr_vtip * tr_vtip)
	tr_thrust = tT
	var tr_prof := rho * tr_A * pow(tr_vtip, 3.0) * tr_sigma * 0.010 / 8.0 * (1.0 + 4.65 * tr_mu * tr_mu)
	p_tail = absf(tT) * absf(kappa * vi_tr) - tT * tr_wr + tr_prof
	var f_tr := Vector3(0.0, tT, 0.0)
	F += f_tr
	M += r_tr.cross(f_tr)

	# ---------------- fuselage
	var wash := clampf(1.0 - v_inplane / 15.0, 0.0, 1.0)
	var u := air_body.x
	var vs := air_body.y
	var wz := air_body.z - 2.0 * vi * wash
	var half_rho := 0.5 * rho
	F += Vector3(-half_rho * f_x * absf(u) * u, -half_rho * f_y * absf(vs) * vs, -half_rho * f_z * absf(wz) * wz)
	var V2 := air_body.length_squared()
	var alpha_f := atan2(air_body.z, maxf(absf(u), 0.1))
	M.y += half_rho * V2 * 1.2 * sin(2.0 * alpha_f) * 0.5 * clampf(absf(u) / 10.0, 0.0, 1.0)
	# rotational damping of the fuselage/tail surfaces at low speed (estimated)
	M += Vector3(-120.0 * w.x, -400.0 * w.y, -900.0 * w.z)

	# ---------------- horizontal stabilizer (rotor wash hits it in the 5-35 m/s band)
	var r_hs := Vector3(-hs_arm, 0.0, -0.2)
	var v_hs := air_body + w.cross(r_hs)
	var hs_wash := clampf((v_inplane - 4.0) / 8.0, 0.0, 1.0) * clampf((35.0 - v_inplane) / 15.0, 0.0, 1.0)
	var w_hs := v_hs.z - 2.0 * vi * hs_wash * 0.7
	var vhs2 := v_hs.x * v_hs.x + w_hs * w_hs
	if vhs2 > 1.0:
		var a_hs := atan2(w_hs, absf(v_hs.x)) + hs_inc
		var cl := 3.5 * clampf(a_hs, -0.35, 0.35)
		var lift := half_rho * vhs2 * hs_S * cl
		var f_hs := Vector3(0.0, 0.0, -lift)
		F += f_hs
		M += r_hs.cross(f_hs)

	# ---------------- vertical fin
	var r_vf := Vector3(-vf_arm, 0.0, -0.8)
	var v_vf := air_body + w.cross(r_vf)
	var vvf2 := v_vf.x * v_vf.x + v_vf.y * v_vf.y
	if vvf2 > 1.0:
		var beta := atan2(v_vf.y, absf(v_vf.x))
		var cy := 3.0 * clampf(vf_inc * clampf(v_vf.x / 20.0, 0.0, 1.0) - beta, -0.4, 0.4)
		var side := half_rho * vvf2 * vf_S * cy
		var f_vf := Vector3(0.0, side, 0.0)
		F += f_vf
		M += r_vf.cross(f_vf)

	# ---------------- drive torque reaction (counter-clockwise rotor seen from above)
	M.z += q_clutch

	out["F"] = F
	out["M"] = M
	out["q_load"] = (p_main + p_tail + p_loss * pow(omr / omega100, 2.0)) / omr   # M2.30: losses fall with rpm (rotor can turn at idle)

# ------------------------------------------------- engine start / flame-out
## Gas producer (N1) when the engine is not simply running: starter motoring, light-off,
## acceleration to ground idle, flame-out and spool-down. SIMULATION model (estimated rates):
## a normal start takes about 25-35 s from light-off to idle, like the 250-C20 start the
## checklist describes (light-off at 12-15% N1, starter released at 58% N1).
func _step_start(dt: float, thr: float) -> void:
	if lit and not fuel_available:
		lit = false                       # throttle closed / fuel valve off: flame-out
		starting = false
	if not lit:
		if starter:
			n1 += (STARTER_N1 - n1) / 3.0 * dt if n1 < STARTER_N1 else -n1 / 8.0 * dt
			if fuel_available and ignition and n1 >= LIGHT_OFF_MIN_N1:
				lit = true                    # igniter (energised with the starter) lights the fuel
				starting = n1 < n1_idle - 1.0
		else:
			n1 -= maxf(n1 / 7.0, 0.6) * dt     # spool-down
		n1 = maxf(n1, 0.0)
		return
	if starting:
		var rate: float
		if starter:
			rate = clampf(2.3 - (n1 - 15.0) * 0.015, 1.3, 2.3)
		elif n1 >= 50.0:
			rate = 1.1                        # self-sustaining above about 50% N1
		else:
			rate = -0.8                       # starter released too early: hung start, N1 decays
		rate += thr * 4.0                     # throttle opened past idle during the start = more fuel
		n1 = maxf(n1 + rate * dt, 0.0)
		if n1 >= n1_idle - 1.0:
			starting = false
		elif n1 < LIGHT_OFF_MIN_N1 and not starter:
			lit = false                       # the start has failed
			starting = false
	elif starter and n1 < 70.0:
		n1 += 0.3 * dt                        # starter still engaged at idle (starter limits!)

# ------------------------------------------------------------- integration
func step(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var out := {}
	atmo.step_turbulence(dt, air_body.length(), maxf(agl, 0.0))
	compute_aero(out)
	var F_aero: Vector3 = out["F"]
	var M_aero: Vector3 = out["M"]
	var q_load: float = out["q_load"]

	# ---------------- engine, governor and freewheel
	var dens_ratio := (atmo.pressure_pa(pos.y) / 101325.0) / sqrt(atmo.temperature_k(pos.y) / 288.15)
	var thr := clampf(throttle, 0.0, 1.0)
	_step_start(dt, thr)
	var n1_cmd := n1_idle
	var gov_w := omega100 * gov_set_pct / 100.0
	if not lit or starting:
		gov_int = 0.0
	elif thr >= 0.98:
		var err := (gov_w - n2) / omega100
		gov_int = clampf(gov_int + err * gov_ki * dt, -40.0, 60.0)
		var p_ff := lerpf(30000.0, 230000.0, pow(clampf(collective, 0.0, 1.0), 1.3))
		n1_cmd = n1_for_power(p_ff, dens_ratio) + gov_kp * err + gov_int
	else:
		gov_int = move_toward(gov_int, 0.0, 5.0 * dt)
		n1_cmd = lerpf(n1_idle, n1_max, thr / 0.98)
		if lit and not starting:
			# M2.30: the N2 governor also limits a part-open throttle (it only ever reduces fuel), so
			# opening the twist grip on the ground brings the rotor up to the governor setting
			# instead of overshooting it
			var err_p := (gov_w - n2) / omega100
			var p_ff_p := lerpf(30000.0, 230000.0, pow(clampf(collective, 0.0, 1.0), 1.3))
			n1_cmd = minf(n1_cmd, n1_for_power(p_ff_p, dens_ratio) + gov_kp * err_p + gov_int)
	if lit and not starting:
		n1_cmd = clampf(n1_cmd, n1_idle, minf(n1_max, lerpf(n1_idle, n1_max + 1.0, thr)))
		var dn1 := clampf((n1_cmd - n1) / 0.6, -2.0 * n1_accel, n1_accel)
		n1 = clampf(n1 + dn1 * dt, 0.0, 110.0)

	var q_pt := pt_torque(n1, n2, dens_ratio)
	if engaged:
		var acc := (q_pt - q_load) / (I_rotor + I_pt)
		var qc := q_pt - I_pt * acc
		if qc < 0.0 and q_pt < q_load:
			engaged = false
			q_clutch = 0.0
		else:
			q_clutch = qc
			nr += acc * dt
			n2 = nr
	if not engaged:
		q_clutch = 0.0
		# M2.30: bearing / seal friction that only matters at low rotor rpm (shutdown coast-down),
		# so the rotor really stops instead of slowing forever. Zero above 60% NR (no effect in flight).
		var q_fric := 90.0 * clampf(1.0 - nr / (0.6 * omega100), 0.0, 1.0) * clampf(nr / 0.3, 0.0, 1.0)
		nr += (-(q_load + q_fric) / I_rotor) * dt
		n2 += (q_pt / I_pt) * dt
		n2 = maxf(n2, 0.0)
		if n2 >= nr:
			# re-engage: conserve angular momentum of rotor + turbine
			var w_common := (I_rotor * nr + I_pt * n2) / (I_rotor + I_pt)
			nr = w_common
			n2 = w_common
			engaged = true
	nr = maxf(nr, 0.0)
	torque_pct = q_clutch / q100 * 100.0

	# ---------------- flapping (first-order tip-path-plane lag, disc tends to stay in space)
	a1 += ((a1_ss - a1) / tau_flap - omega.y) * dt
	b1 += ((b1_ss - b1) / tau_flap - omega.x) * dt
	var fl := sqrt(a1 * a1 + b1 * b1)
	if fl > flap_stop * 1.3:
		a1 *= flap_stop * 1.3 / fl
		b1 *= flap_stop * 1.3 / fl

	# ---------------- forces to world, gravity, ground
	var F_world := aero_to_world(F_aero) + Vector3(0.0, -mass * G, 0.0)
	var M_body := M_aero
	var gnd := _ground_contact()
	F_world += gnd[0]
	M_body += gnd[1]
	force_world = F_world
	moment_body = M_body

	# ---------------- rigid body integration (semi-implicit Euler)
	vel += F_world / mass * dt
	pos += vel * dt
	var Iw := Vector3(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z)
	var gyro := omega.cross(Iw)
	var wdot := Vector3((M_body.x - gyro.x) / inertia.x, (M_body.y - gyro.y) / inertia.y, (M_body.z - gyro.z) / inertia.z)
	omega += wdot * dt
	var wg := from_aero(omega)
	var ang := wg.length() * dt
	if ang > 1e-9:
		basis = (basis * Basis(wg.normalized(), ang)).orthonormalized()
	sim_time += dt
	last_step_usec = Time.get_ticks_usec() - t0

## Spring/damper skid contact. Returns [force_world, moment_body_aero].
func _ground_contact() -> Array:
	var f_tot := Vector3.ZERO
	var m_world := Vector3.ZERO
	var wg_world := basis * from_aero(omega)
	var count := 0
	var sink_now := 0.0
	max_contact_force = 0.0
	tail_strike = false
	var k := mass * G / 4.0 / 0.035          # ~3.5 cm static deflection per skid point
	var c := 2.0 * 0.7 * sqrt(k * mass / 4.0)
	for i in contact_points.size():
		var r_w := basis * contact_points[i]
		var pt := pos + r_w
		var h := ground_height(pt.x, pt.z)
		var pen := h - pt.y
		if pen <= 0.0:
			_anchors[i] = null
			continue
		count += 1
		if i == 4:
			tail_strike = true
		var n := ground_normal(pt.x, pt.z)
		var vp := vel + wg_world.cross(r_w)
		var vn := vp.dot(n)
		sink_now = maxf(sink_now, -vn)
		var fn := maxf(k * minf(pen, 0.4) - c * vn, 0.0)
		max_contact_force = maxf(max_contact_force, fn)
		# tangential friction: stick (spring to an anchor point) or slide (Coulomb, mu 0.6)
		var vt := vp - n * vn
		if _anchors[i] == null:
			_anchors[i] = pt
		var d: Vector3 = pt - _anchors[i]
		d -= n * d.dot(n)
		var ft := -d * 60000.0 - vt * 3000.0
		var fmax := 0.6 * fn
		if ft.length() > fmax:
			ft = ft.normalized() * fmax
			# sliding: drag the anchor along so the spring force equals the friction limit
			_anchors[i] = pt + (ft + vt * 3000.0) / 60000.0
		if ft.length() > fmax * 1.0001:
			ft = ft.normalized() * fmax
		var f := n * fn + ft
		f_tot += f
		m_world += r_w.cross(f)
	contact_count = count
	on_ground = count > 0
	touchdown_event = false
	if on_ground and not _was_on_ground:
		touchdown_sink = sink_now
		touchdown_event = true
	_was_on_ground = on_ground
	# moment: world -> Godot body -> aero
	var m_body := to_aero(basis.transposed() * m_world)
	return [f_tot, m_body]

# ------------------------------------------------------------ convenience
func heading_deg() -> float:
	var f := -basis.z
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)

func pitch_deg() -> float:
	return rad_to_deg(asin(clampf(-basis.z.y, -1.0, 1.0)))

func roll_deg() -> float:
	return rad_to_deg(atan2(-basis.x.y, basis.y.y))

func ias_kt() -> float:
	return maxf(air_body.x, 0.0) * sqrt(rho / 1.225) / KT

func groundspeed_kt() -> float:
	return Vector2(vel.x, vel.z).length() / KT

func nr_pct() -> float:
	return nr / omega100 * 100.0

func n2_pct() -> float:
	return n2 / omega100 * 100.0

## Slip ball (inclinometer), in g: + = ball to the RIGHT. It shows the lateral specific force
## (what you feel on the seat): "step on the ball" - ball left = left pedal.
## SIMPLIFICATION: this flight model's fuselage side force is small, so in forward flight a pure
## specific-force ball would hardly move with sideslip. A sideslip term (fading in from ~0 to 30 kt)
## is added so that about 5 deg of sideslip moves the ball one ball width (0.06 g), like a real cockpit.
func ball_g() -> float:
	var sf := world_to_aero((force_world + Vector3(0.0, mass * G, 0.0)) / mass)
	var beta := rad_to_deg(atan2(air_body.y, maxf(absf(air_body.x), 0.1)))
	var fade := clampf(air_body.x / (30.0 * KT), 0.0, 1.0)
	return clampf(-sf.y / G + 0.012 * beta * fade, -0.5, 0.5)

func vs_fpm() -> float:
	return vel.y / FT * 60.0

## Places the aircraft with the given attitude.
func set_attitude(heading: float, pitch: float, roll: float) -> void:
	basis = Basis.from_euler(Vector3(deg_to_rad(pitch), -deg_to_rad(heading), -deg_to_rad(roll)), EULER_ORDER_YXZ)

func reset_dynamic_state() -> void:
	omega = Vector3.ZERO
	nr = omega100
	n2 = omega100
	engaged = true
	a1 = 0.0
	b1 = 0.0
	vi = 7.0
	vi_tr = 10.0
	gov_int = 0.0
	_was_on_ground = false
	touchdown_event = false
	_anchors = [null, null, null, null, null]
