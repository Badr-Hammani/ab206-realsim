extends RefCounted
## "Instructor's hands": a simple hover-hold controller that can fly any subset of the
## controls (collective, pedals, cyclic) while the student flies the rest. This is how
## hover is really taught on dual controls ("you have the collective, I have the rest").
## It is a teaching aid in the simulator, not a model of any real autopilot (the 206B-3
## has none). The same controller is used by the headless tests as a "robot pilot".
##
## Outputs are normalised like controls.gd: lon +1 forward, lat +1 right, coll 0..1, ped +1 right.

var f                                # HeliFDM
var hold := {"coll": false, "ped": false, "cyc": false}
var target := Vector3.ZERO           # ground point to hover over (world x/z used)
var height := 1.0                    # skid height target, m
var heading := 0.0                   # deg
var vz_override := NAN               # m/s vertical speed command (landing / lift-off), NAN = height hold
var vel_cmd_override := Vector2(NAN, NAN)   # body (forward, right) m/s, for hover taxi / turns
var max_speed := 1.5                 # m/s, position loop velocity limit
var vel_gain := 2.5                  # deg of attitude per m/s of velocity error
var att_cmd_override := Vector2(NAN, NAN)   # (pitch, roll) deg, attitude-command mode (training assist)

var coll := 0.0
var lon := 0.0
var lat := 0.0
var ped := 0.0
var _coll_i := 0.0
var _lon_i := 0.0
var _lat_i := 0.0
var _ped_i := 0.0
var _vx_i := 0.0
var _vy_i := 0.0

func _init(fdm) -> void:
	f = fdm

func any() -> bool:
	return hold["coll"] or hold["ped"] or hold["cyc"]

## Bumpless start from the current control positions.
func sync(c_coll: float, c_lon: float, c_lat: float, c_ped: float) -> void:
	coll = c_coll
	lon = c_lon
	lat = c_lat
	ped = c_ped
	_coll_i = c_coll
	_lon_i = c_lon
	_lat_i = c_lat
	_ped_i = c_ped
	_vx_i = 0.0
	_vy_i = 0.0

## Pre-position the cyclic (e.g. to the hover trim before lift-off), as a pilot does.
func preset_cyclic(c_lon: float, c_lat: float) -> void:
	_lon_i = c_lon
	_lat_i = c_lat
	lon = c_lon
	lat = c_lat

## Suggestion mode ("ghost stick"): start every step from the hover trim, no memory.
func reset_to_trim(c_coll: float, c_lon: float, c_lat: float, c_ped: float) -> void:
	_coll_i = c_coll
	_lon_i = c_lon
	_lat_i = c_lat
	_ped_i = c_ped
	_vx_i = 0.0
	_vy_i = 0.0

## Body-frame (forward, right) components of a horizontal world vector.
func body_xy(v: Vector3) -> Vector2:
	var hd := deg_to_rad(f.heading_deg())
	var fwd := Vector2(sin(hd), -cos(hd))
	var right := Vector2(cos(hd), sin(hd))
	var g := Vector2(v.x, v.z)
	return Vector2(g.dot(fwd), g.dot(right))

## Call once per FDM step. Axes that are not held track the student's inputs (given
## here) so that taking an axis over is always bumpless.
func update(dt: float, s_coll: float, s_lon: float, s_lat: float, s_ped: float) -> void:
	# on the ground the cyclic and pedal loops start working once the skids get light
	# (thrust above ~85% of weight), like a pilot correcting during lift-off
	var ground: bool = f.on_ground and f.thrust < 0.85 * f.mass * 9.80665
	# ---- collective: skid height (or commanded vertical speed)
	if hold["coll"]:
		var vz_cmd := clampf((height - f.agl) * 0.9, -0.7, 0.7)
		if not is_nan(vz_override):
			vz_cmd = vz_override
		var e: float = vz_cmd - f.vel.y
		if not f.on_ground or vz_cmd > 0.0:
			_coll_i = clampf(_coll_i + e * 0.10 * dt, 0.0, 1.0)
		coll = clampf(_coll_i + e * 0.06, 0.0, 1.0)
	else:
		coll = s_coll
		_coll_i = s_coll
	# ---- pedals: heading
	if hold["ped"]:
		var herr := wrapf(heading - f.heading_deg(), -180.0, 180.0)
		if not ground:
			_ped_i = clampf(_ped_i + herr * 0.006 * dt, -1.0, 1.0)
		ped = clampf(_ped_i + clampf(herr, -30.0, 30.0) * 0.03 - f.omega.z * 0.8, -1.0, 1.0)
	else:
		ped = s_ped
		_ped_i = s_ped
	# ---- cyclic: position -> velocity -> attitude -> stick
	if hold["cyc"]:
		var perr := body_xy(target - f.pos)
		var vb := body_xy(f.vel)
		var vcmd := (perr * 0.45).limit_length(max_speed)
		if not is_nan(vel_cmd_override.x):
			vcmd = vel_cmd_override
		var ev := vcmd - vb
		if not ground:
			_vx_i = clampf(_vx_i + ev.x * 0.6 * dt, -6.0, 6.0)
			_vy_i = clampf(_vy_i + ev.y * 0.6 * dt, -6.0, 6.0)
		var pitch_cmd := clampf(-(ev.x * vel_gain + _vx_i), -12.0, 10.0)
		var roll_cmd := clampf(ev.y * vel_gain + _vy_i, -12.0, 12.0)
		if not is_nan(att_cmd_override.x):
			# attitude command with a little drift damping: centred stick = level and slowing down
			_vx_i = 0.0
			_vy_i = 0.0
			pitch_cmd = clampf(att_cmd_override.x + vb.x * 3.0, -15.0, 12.0)
			roll_cmd = clampf(att_cmd_override.y - vb.y * 3.0, -15.0, 15.0)
		var pe: float = f.pitch_deg() - pitch_cmd
		var re: float = roll_cmd - f.roll_deg()
		if not ground:
			_lon_i = clampf(_lon_i + pe * 0.012 * dt, -0.8, 0.8)
			_lat_i = clampf(_lat_i + re * 0.012 * dt, -0.8, 0.8)
		lon = clampf(_lon_i + pe * 0.03 + f.omega.y * 1.0, -1.0, 1.0)
		lat = clampf(_lat_i + re * 0.04 - f.omega.x * 0.4, -1.0, 1.0)
		if ground:
			lon = _lon_i
			lat = _lat_i
	else:
		lon = s_lon
		lat = s_lat
		_lon_i = s_lon
		_lat_i = s_lat
		_vx_i = 0.0
		_vy_i = 0.0
