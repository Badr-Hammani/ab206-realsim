extends RefCounted
## Training assists for learning to hover - "training wheels" that you fade out.
## NONE of these exist on the real Bell 206B-3 (it has no stability augmentation or autopilot);
## they are there so you can learn one thing at a time, then switch them off.
##
##  Level 3  HOVER HOLD   cyclic = ground speed (max ~6 kt). Centre the stick and the aircraft
##                        stops and holds the spot. Pedals damped.
##  Level 2  ATTITUDE     cyclic = attitude (full stick = 12 deg). Centre the stick and it levels
##                        itself and the drift slowly dies. Pedals damped.
##  Level 1  DAMPING      rate damping and, in the hover, a gentle pull back to level: it no
##                        longer wobbles by itself, but you still fly the stick positions yourself.
##  Level 0  OFF          the real thing.
##
## Levels 2 and 3 only work in a low hover (below 30 m and 15 kt); above that they act as level 1,
## with a bumpless hand-back of the cyclic.

const HoverHold = preload("res://scripts/core/hover_hold.gd")
const NAMES := ["OFF (real 206)", "DAMPING", "ATTITUDE HOLD", "HOVER HOLD"]
const SHORT := ["OFF", "1 damping", "2 attitude", "3 hover hold"]

var level := 0
var active_level := 0          # what is really applied this moment (2/3 fall back to 1 outside the hover)
var fdm
var controls
var hh                         # attitude / velocity controller for levels 2-3
var _on := false
var _center_t := 0.0
var _captured := false

func _init(f, c) -> void:
	fdm = f
	controls = c
	hh = HoverHold.new(f)
	hh.hold = {"coll": false, "ped": false, "cyc": true}
	hh.vel_gain = 4.0

func name() -> String:
	return NAMES[level]

func _in_hover_band() -> bool:
	return fdm.agl < 30.0 and Vector2(fdm.vel.x, fdm.vel.z).length() < 15.0 * 0.514444

## Called by main for each flight-model sub-step, after the pilot's inputs were copied to the fdm.
## cyc_free / ped_free: false when the lesson instructor's hands fly that axis.
func apply(dt: float, cyc_free: bool, ped_free: bool) -> void:
	active_level = level
	if level >= 2 and not _in_hover_band():
		active_level = 1
	if active_level >= 2 and cyc_free:
		if not _on:
			_begin()
		var st := Vector2(controls.cyclic_lat, controls.cyclic_lon)    # x = right, y = forward
		if active_level == 3:
			hh.att_cmd_override = Vector2(NAN, NAN)
			if st.length() < 0.04:
				_center_t += dt
				if _center_t < 1.2:
					hh.vel_cmd_override = Vector2.ZERO      # stop first...
				else:
					if not _captured:
						hh.target = fdm.pos                 # ...then hold this spot
						_captured = true
					hh.vel_cmd_override = Vector2(NAN, NAN)
			else:
				_center_t = 0.0
				_captured = false
				hh.vel_cmd_override = Vector2(st.y, st.x) * 3.0
		else:
			hh.vel_cmd_override = Vector2(NAN, NAN)
			hh.att_cmd_override = Vector2(-st.y * 12.0, st.x * 12.0)
		hh.update(dt, fdm.collective, fdm.cyclic_lon, fdm.cyclic_lat, fdm.pedal)
		fdm.cyclic_lon = hh.lon
		fdm.cyclic_lat = hh.lat
	elif _on:
		_end()
	if active_level >= 1:
		if cyc_free and active_level == 1:
			# rate damping plus a gentle pull back towards a level attitude (only in the hover band)
			var spring := 0.012 if _in_hover_band() else 0.0
			fdm.cyclic_lon = clampf(fdm.cyclic_lon + fdm.omega.y * 0.9 + fdm.pitch_deg() * spring, -1.0, 1.0)
			fdm.cyclic_lat = clampf(fdm.cyclic_lat - fdm.omega.x * 0.5 - (fdm.roll_deg() + 1.3) * spring, -1.0, 1.0)
		if ped_free:
			fdm.pedal = clampf(fdm.pedal - fdm.omega.z * (0.7 if active_level == 1 else 1.1), -1.0, 1.0)

## Entering levels 2/3: the controller starts from the current cyclic, the stick is centred
## (centre = "hold what you have").
func _begin() -> void:
	_on = true
	hh.sync(fdm.collective, fdm.cyclic_lon, fdm.cyclic_lat, fdm.pedal)
	controls.stick_mouse = Vector2.ZERO
	controls.key_offset = Vector2.ZERO
	controls._combine()
	_center_t = 0.0
	_captured = false

## Leaving levels 2/3: the stick takes the cyclic position the assist was using, so nothing jumps.
func _end() -> void:
	_on = false
	controls.stick_mouse = Vector2(hh.lat, hh.lon)
	controls.key_offset = Vector2.ZERO
	controls._combine()

func set_level(l: int) -> void:
	if l == level:
		return
	if _on and l < 2:
		_end()
	level = clampi(l, 0, 3)
