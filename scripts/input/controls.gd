extends Node
## Pilot inputs: keyboard + mouse, and any joystick / HOTAS axis.
## Outputs normalised controls for the flight model:
##   cyclic_lon (+1 forward), cyclic_lat (+1 right), collective (0 down..1 up),
##   pedal (+1 right), throttle (0 idle..1 full open).
## Keyboard pedals/arrow cyclic spring back to their trim position when released;
## the mouse cyclic and collective stay where you leave them (like friction-held controls).

const CFG_PATH := "user://controls.cfg"
const FUNCS := ["cyclic_lat", "cyclic_lon", "collective", "pedal", "throttle"]
# [id, label, is_hold]
const BTN_ACTIONS := [
	["trim_set", "Force trim set (stick + pedal)", false],
	["trim_reset", "Force trim reset (clear trim)", false],
	["cam_panel_focus", "Instrument zoom (Z)", false],
	["cam_recenter", "Recenter view (C)", false],
	["cam_cycle", "Cycle camera (V)", false],
	["toggle_assist", "Cycle flight assist (H)", false],
	["toggle_auto_pedal", "Auto-pedals / heading hold", false],
	["throttle_open", "Throttle open (hold)", true],
	["throttle_close", "Throttle close (hold)", true],
	["pedal_trim_left", "Pedal trim left (hold)", true],
	["pedal_trim_right", "Pedal trim right (hold)", true],
	["collective_up", "Collective up (hold)", true],
	["collective_down", "Collective down (hold)", true],
	["pause", "Pause / resume (P)", false],
	["reset_pad", "Reset on pad (F2)", false],
	["reset_hover", "Reset in hover (F3)", false],
	["reset_cruise", "Reset in cruise (F4)", false],
	["reset_auto", "Reset autorotation (F5)", false],
	["toggle_map", "Moving map (K)", false],
	["toggle_panel_2d", "2D instruments (Tab)", false],
	["toggle_guide", "Hover guide (G)", false],
	["toggle_gates", "Hover gates (B)", false],
	["take_control", "Take / hand control (T)", false],
	["sim_speed", "Cycle sim speed (Y)", false],
	["toggle_hud", "Toggle telemetry (F6)", false],
	["screenshot", "Screenshot (F12)", false],
	# M2.30 cockpit systems (engine start / checklists)
	["starter", "Starter (hold, I)", true],
	["gov_incr", "Governor RPM INCR (hold, ])", true],
	["gov_decr", "Governor RPM DECR (hold, [)", true],
	["caution_test", "Caution lights test (hold)", true],
	["checklist_ok", "Checklist item checked (Enter)", false],
	["fuel_valve", "Fuel valve ON / OFF (red handle)", false],
	["systems_panel", "Switches + checklists panel (J)", false],
	["overhead_panel", "Overhead breakers (O)", false],
	["cold_dark", "Cold and dark reset (Shift+F2)", false],
]

var cyclic_lon := 0.0
var cyclic_lat := 0.0
var collective := 0.0
var pedal := 0.0
var throttle := 1.0
var open_block := false            # M2.30: the press that rolls the grip out of CLOSED stops at idle (release, press again to open)
var throttle_rate := 0.6           # R/F twist-grip speed per second (main.gd slows it on the ground, M2.30)

var mouse_cyclic := true
signal mouse_cyclic_toggled(on: bool)
signal joy_action_pressed(action: String)
var touch_owns_mouse := false       # touch controls switched the mouse cyclic off (not saved)
const CFG_VERSION := 2              # 2 (M2.23): mouse cyclic switched back on once (a touch had saved it off)
var mouse_sensitivity := 1.0
var invert_mouse_y := false
var mouse_look_held := false

var stick_mouse := Vector2.ZERO     # x = lat, y = lon from the mouse
var key_offset := Vector2.ZERO      # arrow keys deflection (springs back)
var pedal_trim := 0.0
var pedal_key := 0.0

# joystick bindings: func -> {device, axis, invert, min, max, deadzone, expo, dev_name}
var bindings := {}
var joy_raw := {}                   # func -> last raw value (diagnostics)
var _joy_filt := {}                 # func -> low-pass filtered value for smooth hydraulic feel
var joy_smooth_ms := 45.0           # ms low-pass smoothing on joystick axes (0 = raw)
var joy_cyc_trim := Vector2.ZERO    # force trim offset for spring-centered cyclic sticks
var _trim_wait_t := 0.0             # grace timer after Force Trim Set while stick returns to center
var _trim_resetting := false        # smoothly ramps cyclic + pedal trim back to zero
# joystick button bindings: action -> {device, button, dev_name}
var btn_bindings := {}
var pov_hat_look := true            # 8-way POV hat pans the camera
var pov_look_speed := 1.0
var btn_capture_paused := false     # true while F8 setup panel is open

# phone motion controller (scripts/input/phone_server.gd). When a phone (re)takes an axis
# (connect, reset, recalibration, lesson start, instructor hand-back) it acts AT ONCE, with an
# offset so the control does not jump: the control keeps its current position and follows every
# phone movement from there. The offset melts away as the phone moves (catch-up), so after a few
# normal corrections the phone angle maps to the absolute control position again.
# (Until 2026-11-17 the phone was ignored until it was moved to match the control exactly, which
# felt like the phone input "not reaching the PC" for the first seconds.)
const PHONE_CATCHUP := 0.5          # offset removed per unit of phone movement
var phone = null
var phone_cyc_engaged := false
var phone_coll_engaged := false
var phone_thr_engaged := false
var phone_cyc := Vector2.ZERO       # x = lat, y = lon
var phone_coll := 0.0
var phone_thr := 1.0
var phone_cyc_off := Vector2.ZERO   # control minus phone at take-over, melts with movement
var phone_coll_off := 0.0
var phone_ped_engaged := false
var phone_ped := 0.0
var phone_ped_off := 0.0
var _phone_ped_prev := 0.0
var _phone_ped_src := ""
var _coll_axes := {}
var _all_axes := {}
var _phone_cyc_src := ""
var _phone_coll_src := ""
var _phone_cyc_prev := Vector2.ZERO
var _phone_coll_prev := 0.0

func _ready() -> void:
	_setup_actions()
	load_config()
	_auto_preset_if_empty()

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _setup_actions() -> void:
	_key("collective_up", [KEY_W, KEY_PAGEUP])
	_key("collective_down", [KEY_S, KEY_PAGEDOWN])
	_key("pedal_left", [KEY_A])
	_key("pedal_right", [KEY_D])
	_key("pedal_trim_left", [KEY_Q])
	_key("pedal_trim_right", [KEY_E])
	_key("cyclic_fwd", [KEY_UP])
	_key("cyclic_back", [KEY_DOWN])
	_key("cyclic_left", [KEY_LEFT])
	_key("cyclic_right", [KEY_RIGHT])
	_key("cyclic_center", [KEY_X])
	_key("throttle_open", [KEY_R])
	_key("throttle_close", [KEY_F])
	_key("toggle_mouse_cyclic", [KEY_M])

func set_from_trim(lon: float, lat: float, coll: float, ped: float, thr: float) -> void:
	stick_mouse = Vector2(lat, lon)
	key_offset = Vector2.ZERO
	collective = coll
	pedal_trim = ped
	pedal_key = 0.0
	throttle = thr
	joy_cyc_trim = Vector2(lat, lon)
	_trim_wait_t = 0.0
	_trim_resetting = false
	_joy_filt.clear()
	phone_release()
	_combine()

## Helicopter Force Trim Set: locks the current cyclic & pedal deflection as the new neutral
## so a spring-centered joystick can relax to center with zero jump.
func set_force_trim() -> void:
	joy_cyc_trim = Vector2(cyclic_lat, cyclic_lon)
	pedal_trim = pedal
	_trim_wait_t = 0.65
	_trim_resetting = false

## Smoothly clears cyclic and pedal trim back to zero (no abrupt kick).
func reset_force_trim() -> void:
	_trim_wait_t = 0.0
	_trim_resetting = true

## Linked dual controls: while the instructor flies an axis, your control moves with it.
func follow(hold: Dictionary, coll: float, lon: float, lat: float, ped: float) -> void:
	if hold["coll"]:
		collective = coll
		phone_coll_engaged = false
	if hold["cyc"]:
		stick_mouse = Vector2(lat - key_offset.x, lon - key_offset.y)
		cyclic_lat = lat
		cyclic_lon = lon
		phone_cyc_engaged = false
	if hold["ped"]:
		pedal_trim = clampf(ped - pedal_key, -1.0, 1.0)
		pedal = ped
		phone_ped_engaged = false

## Phones re-take their axes from the current control position (after resets/recalibration/hand-overs).
func phone_release() -> void:
	phone_cyc_engaged = false
	phone_coll_engaged = false
	phone_thr_engaged = false
	phone_ped_engaged = false

func _update_phone(dt: float) -> void:
	if phone == null:
		return
	if phone.running:
		phone.poll()     # read the newest phone samples right before this physics tick uses them
	_all_axes = phone.axes("all", dt) if phone.has_role("all") else {}
	var cyc_src := "cyclic" if phone.has_role("cyclic") else ("all" if not _all_axes.is_empty() else "")
	if cyc_src != _phone_cyc_src:
		phone_cyc_engaged = false        # a phone joined/left: take over again from the current stick, no jump
	_phone_cyc_src = cyc_src
	if cyc_src != "":
		var ax: Dictionary = phone.axes("cyclic", dt) if cyc_src == "cyclic" else _all_axes
		phone_cyc = Vector2(ax["lat"], ax["lon"])
		if not phone_cyc_engaged:
			phone_cyc_engaged = true
			phone_cyc_off = Vector2(cyclic_lat - key_offset.x, cyclic_lon - key_offset.y) - phone_cyc
		else:
			var d := phone_cyc - _phone_cyc_prev
			phone_cyc_off.x = move_toward(phone_cyc_off.x, 0.0, absf(d.x) * PHONE_CATCHUP)
			phone_cyc_off.y = move_toward(phone_cyc_off.y, 0.0, absf(d.y) * PHONE_CATCHUP)
		_phone_cyc_prev = phone_cyc
	elif phone_cyc_engaged:
		stick_mouse = _phone_cyc_out()   # phone lost: the stick stays where it was
		phone_cyc_engaged = false
	var coll_src := "collective" if phone.has_role("collective") else ("all" if not _all_axes.is_empty() else "")
	if coll_src != _phone_coll_src:
		phone_coll_engaged = false
	_phone_coll_src = coll_src
	if coll_src != "":
		var ac: Dictionary = phone.axes("collective", dt) if coll_src == "collective" else _all_axes
		_coll_axes = ac
		phone_coll = ac["coll"]
		phone_thr = ac["thr"]
		if not phone_coll_engaged:
			phone_coll_engaged = true
			phone_coll_off = collective - phone_coll
		else:
			phone_coll_off = move_toward(phone_coll_off, 0.0, absf(phone_coll - _phone_coll_prev) * PHONE_CATCHUP)
		_phone_coll_prev = phone_coll
		if phone.twist_throttle and phone.coll_pedals != 2 and coll_src == "collective":
			if not phone_thr_engaged and absf(phone_thr - throttle) < 0.08:
				phone_thr_engaged = true
		else:
			phone_thr_engaged = false
	else:
		phone_coll_engaged = false
		phone_thr_engaged = false
	var ped_src := ""
	if phone.has_role("pedals"):
		ped_src = "pedals"
	elif phone.running and phone.coll_has_pedals():
		ped_src = "collective"
	elif not _all_axes.is_empty() and bool(phone.roles["all"].get("has_yaw", false)):
		ped_src = "all"
	if ped_src != "":
		var pv := 0.0
		if ped_src == "pedals":
			pv = float(phone.axes("pedals", dt)["ped"])
		elif ped_src == "all":
			pv = float(_all_axes.get("ped", 0.0))
		else:
			pv = float(_coll_axes.get("ped", 0.0))
		if ped_src != _phone_ped_src:
			phone_ped_engaged = false       # source changed (pedal phone joined/left): take over again without a jump
		_phone_ped_src = ped_src
		phone_ped = pv
		if not phone_ped_engaged:
			phone_ped_engaged = true
			phone_ped_off = pedal - phone_ped      # no jump at take-over; the difference melts as the feet move
		else:
			phone_ped_off = move_toward(phone_ped_off, 0.0, absf(phone_ped - _phone_ped_prev) * PHONE_CATCHUP)
		_phone_ped_prev = phone_ped
	elif phone_ped_engaged:
		pedal_trim = clampf(phone_ped + phone_ped_off, -1.0, 1.0)   # phone lost: pedals stay where they were
		pedal_key = 0.0
		phone_ped_engaged = false

func phone_engaged(role: String) -> bool:
	match role:
		"cyclic": return phone_cyc_engaged
		"collective": return phone_coll_engaged
		"all": return phone_cyc_engaged or phone_coll_engaged
		"pedals": return phone_ped_engaged
	return false

func _phone_cyc_out() -> Vector2:
	var v := phone_cyc + phone_cyc_off
	return Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_cyclic and not mouse_look_held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative * 0.0022 * mouse_sensitivity
		stick_mouse.x = clampf(stick_mouse.x + rel.x, -1.0, 1.0)
		var dy := -rel.y if not invert_mouse_y else rel.y
		stick_mouse.y = clampf(stick_mouse.y + dy, -1.0, 1.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and not _joy_bound("collective"):
			collective = clampf(collective + 0.015, 0.0, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _joy_bound("collective") and not phone_coll_engaged:
			collective = clampf(collective - 0.015, 0.0, 1.0)
	elif event is InputEventJoypadButton and event.pressed and not btn_capture_paused:
		for act in BTN_ACTIONS:
			if act[2]:
				continue     # hold actions are polled in update()
			var id: String = act[0]
			if btn_bindings.has(id):
				var b: Dictionary = btn_bindings[id]
				var dev := _resolve_device(b)
				if dev == event.device and int(b["button"]) == event.button_index:
					joy_action_pressed.emit(id)
	if event.is_action_pressed("toggle_mouse_cyclic"):
		mouse_cyclic = not mouse_cyclic
		touch_owns_mouse = false
		mouse_cyclic_toggled.emit(mouse_cyclic)
	if event.is_action_pressed("cyclic_center"):
		stick_mouse = Vector2.ZERO

func _resolve_device(b: Dictionary) -> int:
	var pads := Input.get_connected_joypads()
	var dev := int(b.get("device", -1))
	var wanted := str(b.get("dev_name", ""))
	if pads.has(dev) and (wanted == "" or Input.get_joy_name(dev) == wanted):
		return dev
	if wanted != "":
		for d in pads:
			if Input.get_joy_name(d) == wanted:
				return d
	if pads.has(dev):
		return dev
	return -1

func _joy_bound(fn: String) -> bool:
	return bindings.has(fn) and _resolve_device(bindings[fn]) >= 0

func joy_button_held(action: String) -> bool:
	if btn_capture_paused or not btn_bindings.has(action):
		return false
	var b: Dictionary = btn_bindings[action]
	var dev := _resolve_device(b)
	return dev >= 0 and Input.is_joy_button_pressed(dev, int(b["button"]))

func _button_is_bound(dev: int, btn: int) -> bool:
	for id in btn_bindings:
		var b: Dictionary = btn_bindings[id]
		if _resolve_device(b) == dev and int(b["button"]) == btn:
			return true
	return false

## 8-way POV hat look vector (x = right +, y = down +), matching mouse_look() conventions.
func pov_look_vector() -> Vector2:
	if not pov_hat_look or btn_capture_paused:
		return Vector2.ZERO
	var v := Vector2.ZERO
	for d in Input.get_connected_joypads():
		if not _button_is_bound(d, JOY_BUTTON_DPAD_LEFT) and Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT):
			v.x -= 1.0
		if not _button_is_bound(d, JOY_BUTTON_DPAD_RIGHT) and Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT):
			v.x += 1.0
		if not _button_is_bound(d, JOY_BUTTON_DPAD_UP) and Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP):
			v.y -= 1.0
		if not _button_is_bound(d, JOY_BUTTON_DPAD_DOWN) and Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN):
			v.y += 1.0
	return v.normalized() if v.length() > 1.0 else v

static func button_name(btn: int) -> String:
	match btn:
		JOY_BUTTON_DPAD_UP: return "Hat Up / B12"
		JOY_BUTTON_DPAD_DOWN: return "Hat Down / B13"
		JOY_BUTTON_DPAD_LEFT: return "Hat Left / B14"
		JOY_BUTTON_DPAD_RIGHT: return "Hat Right / B15"
		_: return "Button %d" % (btn + 1)

func find_tflight_stick_x() -> int:
	for d in Input.get_connected_joypads():
		var nm := Input.get_joy_name(d).to_lower()
		if nm.contains("t.flight stick x") or nm.contains("t-flight stick x"):
			return d
	return -1

func _auto_preset_if_empty() -> void:
	var d := find_tflight_stick_x()
	if d < 0:
		return
	if bindings.is_empty() and btn_bindings.is_empty():
		apply_tflight_stick_x_preset(d)
	elif btn_bindings.is_empty():
		_apply_tflight_buttons(d)
	elif not btn_bindings.has("starter") and not _button_is_bound(d, 11):
		# M2.30: existing T.Flight setups get the starter on the free button 12 (index 11)
		btn_bindings["starter"] = {"device": d, "button": 11, "dev_name": Input.get_joy_name(d)}
		save_config()

func _apply_tflight_buttons(dev: int) -> void:
	var nm := Input.get_joy_name(dev)
	btn_bindings = {
		"trim_set":         {"device": dev, "button": 0,  "dev_name": nm},
		"cam_recenter":     {"device": dev, "button": 1,  "dev_name": nm},
		"cam_panel_focus":  {"device": dev, "button": 2,  "dev_name": nm},
		"trim_reset":       {"device": dev, "button": 3,  "dev_name": nm},
		"throttle_open":    {"device": dev, "button": 4,  "dev_name": nm},
		"throttle_close":   {"device": dev, "button": 5,  "dev_name": nm},
		"cam_cycle":        {"device": dev, "button": 6,  "dev_name": nm},
		"toggle_assist":    {"device": dev, "button": 7,  "dev_name": nm},
		"toggle_map":       {"device": dev, "button": 8,  "dev_name": nm},
		"reset_hover":      {"device": dev, "button": 9,  "dev_name": nm},
		"reset_pad":        {"device": dev, "button": 10, "dev_name": nm},
		"starter":          {"device": dev, "button": 11, "dev_name": nm},
	}

## Applies a complete default mapping for the Thrustmaster T.Flight Stick X:
##   Axes: 0/1 = X/Y cyclic (smooth expo), 2 = twist handle (pedals, smooth expo),
##         3 = base slider (collective, inverted)
##   POV Hat: 8-way camera look around
##   Buttons 1..11: force trim set, recenter view, instrument zoom, force trim reset,
##                  throttle +/-, cycle camera, flight assist, moving map, reset hover, reset pad.
func apply_tflight_stick_x_preset(dev: int = -1) -> bool:
	if dev < 0:
		dev = find_tflight_stick_x()
	if dev < 0:
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			return false
		dev = pads[0]
	var nm := Input.get_joy_name(dev)
	bindings = {
		"cyclic_lat": {"device": dev, "axis": 0, "invert": false, "min": -1.0, "max": 1.0, "deadzone": 0.06, "expo": 0.35, "dev_name": nm},
		"cyclic_lon": {"device": dev, "axis": 1, "invert": false, "min": -1.0, "max": 1.0, "deadzone": 0.06, "expo": 0.35, "dev_name": nm},
		"pedal":      {"device": dev, "axis": 2, "invert": false, "min": -1.0, "max": 1.0, "deadzone": 0.08, "expo": 0.40, "dev_name": nm},
		"collective": {"device": dev, "axis": 3, "invert": true,  "min": -1.0, "max": 1.0, "deadzone": 0.02, "expo": 0.0,  "dev_name": nm},
	}
	_apply_tflight_buttons(dev)
	joy_smooth_ms = 50.0
	pov_hat_look = true
	_joy_filt.clear()
	return true

func _twist_crosstalk_dz(fn: String) -> float:
	if (fn != "cyclic_lat" and fn != "cyclic_lon") or not _joy_bound("pedal"):
		return 0.0
	if _resolve_device(bindings[fn]) != _resolve_device(bindings["pedal"]):
		return 0.0
	# Twisting a single-handle joystick mechanically nudges X/Y slightly: widen cyclic
	# center deadzone gently while twisting so fixing yaw does not pitch/roll the helicopter.
	var p := absf(float(_joy_filt.get("pedal", 0.0)))
	return clampf((p - 0.10) * 0.09, 0.0, 0.06)

func joy_value(fn: String) -> float:
	var b: Dictionary = bindings[fn]
	var dev := _resolve_device(b)
	var raw := Input.get_joy_axis(dev, int(b["axis"])) if dev >= 0 else 0.0
	joy_raw[fn] = raw
	var lo: float = b.get("min", -1.0)
	var hi: float = b.get("max", 1.0)
	var t := clampf((raw - lo) / maxf(hi - lo, 0.05), 0.0, 1.0)
	if b.get("invert", false):
		t = 1.0 - t
	var dz: float = float(b.get("deadzone", 0.03)) + _twist_crosstalk_dz(fn)
	if fn == "collective" or fn == "throttle":
		return t
	var c := t * 2.0 - 1.0
	if absf(c) < dz:
		return 0.0
	var lin := (absf(c) - dz) / maxf(1.0 - dz, 0.05)
	var expo := clampf(float(b.get("expo", 0.0)), 0.0, 0.9)
	var shaped := (1.0 - expo) * lin + expo * lin * lin * lin
	return signf(c) * shaped

func update(dt: float) -> void:
	_update_phone(dt)
	# collective (rate-based, holds position)
	if not _joy_bound("collective") and not phone_coll_engaged:
		var rate := 0.35 if Input.is_key_pressed(KEY_SHIFT) else 0.18
		if Input.is_action_pressed("collective_up") or joy_button_held("collective_up"):
			collective += rate * dt
		if Input.is_action_pressed("collective_down") or joy_button_held("collective_down"):
			collective -= rate * dt
		collective = clampf(collective, 0.0, 1.0)
	# throttle twist grip
	if not _joy_bound("throttle") and not phone_thr_engaged:
		var opening: bool = Input.is_action_pressed("throttle_open") or joy_button_held("throttle_open")
		if not opening:
			open_block = false
		if opening and not open_block:
			throttle += throttle_rate * dt
		if Input.is_action_pressed("throttle_close") or joy_button_held("throttle_close"):
			throttle -= throttle_rate * dt
		throttle = clampf(throttle, 0.0, 1.0)
	# pedals: key deflection springs back to the pedal trim (Q/E or joy buttons move the trim)
	var target := 0.0
	if Input.is_action_pressed("pedal_left"):
		target -= 1.0
	if Input.is_action_pressed("pedal_right"):
		target += 1.0
	pedal_key = move_toward(pedal_key, target * 0.6, (2.5 if target != 0.0 else 4.0) * dt)
	if Input.is_action_pressed("pedal_trim_left") or joy_button_held("pedal_trim_left"):
		pedal_trim -= 0.25 * dt
	if Input.is_action_pressed("pedal_trim_right") or joy_button_held("pedal_trim_right"):
		pedal_trim += 0.25 * dt
	pedal_trim = clampf(pedal_trim, -1.0, 1.0)
	# arrow-key cyclic deflection
	var kt := Vector2.ZERO
	if Input.is_action_pressed("cyclic_left"):
		kt.x -= 1.0
	if Input.is_action_pressed("cyclic_right"):
		kt.x += 1.0
	if Input.is_action_pressed("cyclic_fwd"):
		kt.y += 1.0
	if Input.is_action_pressed("cyclic_back"):
		kt.y -= 1.0
	key_offset = key_offset.move_toward(kt * (0.35 if Input.is_key_pressed(KEY_SHIFT) else 0.12), (1.5 if kt != Vector2.ZERO else 3.0) * dt)
	# smooth force-trim reset
	if _trim_resetting and dt > 0.0:
		var step := 2.2 * dt
		joy_cyc_trim.x = move_toward(joy_cyc_trim.x, 0.0, step)
		joy_cyc_trim.y = move_toward(joy_cyc_trim.y, 0.0, step)
		pedal_trim = move_toward(pedal_trim, 0.0, step)
		if joy_cyc_trim == Vector2.ZERO and pedal_trim == 0.0:
			_trim_resetting = false
	# update low-pass filtered joystick axes (hydraulic feel, removes pot jitter)
	var stick_centered := true
	for fn in FUNCS:
		if _joy_bound(fn):
			var raw_v := joy_value(fn)
			if (fn == "cyclic_lat" or fn == "cyclic_lon" or fn == "pedal") and absf(raw_v) > 0.08:
				stick_centered = false
			if dt <= 0.0 or joy_smooth_ms <= 0.0 or not _joy_filt.has(fn):
				_joy_filt[fn] = raw_v
			else:
				var mult := 1.4 if fn == "collective" else (1.3 if fn == "pedal" else 1.0)
				var tau := (joy_smooth_ms * mult) / 1000.0
				var alpha := 1.0 - exp(-dt / maxf(tau, 0.001))
				_joy_filt[fn] = lerpf(float(_joy_filt[fn]), raw_v, alpha)
	if _trim_wait_t > 0.0:
		_trim_wait_t = maxf(_trim_wait_t - dt, 0.0)
		if stick_centered:
			_trim_wait_t = 0.0
	_combine()

func _combine() -> void:
	cyclic_lat = clampf(stick_mouse.x + key_offset.x, -1.0, 1.0)
	cyclic_lon = clampf(stick_mouse.y + key_offset.y, -1.0, 1.0)
	pedal = clampf(pedal_trim + pedal_key, -1.0, 1.0)
	for fn in FUNCS:
		if _joy_bound(fn):
			var v: float = float(_joy_filt[fn]) if _joy_filt.has(fn) else joy_value(fn)
			match fn:
				"cyclic_lat":
					cyclic_lat = clampf(joy_cyc_trim.x + (0.0 if _trim_wait_t > 0.0 else v), -1.0, 1.0)
				"cyclic_lon":
					cyclic_lon = clampf(joy_cyc_trim.y + (0.0 if _trim_wait_t > 0.0 else -v), -1.0, 1.0)
				"collective":
					collective = v
				"pedal":
					pedal = clampf(pedal_trim + (0.0 if _trim_wait_t > 0.0 else v), -1.0, 1.0)
				"throttle":
					# M2.30: small detents at both ends so a throttle lever / twist axis reaches the
					# idle stop and full open exactly (checklist items test idle and full)
					throttle = 0.0 if v < 0.04 else (1.0 if v > 0.96 else v)
	if phone_cyc_engaged:
		stick_mouse = _phone_cyc_out()
		cyclic_lat = clampf(stick_mouse.x + key_offset.x, -1.0, 1.0)
		cyclic_lon = clampf(stick_mouse.y + key_offset.y, -1.0, 1.0)
	if phone_coll_engaged:
		collective = clampf(phone_coll + phone_coll_off, 0.0, 1.0)
	if phone_thr_engaged:
		throttle = phone_thr
	if phone_ped_engaged:
		pedal = clampf(phone_ped + phone_ped_off, -1.0, 1.0)

func save_config() -> void:
	var cf := ConfigFile.new()
	cf.set_value("mouse", "sensitivity", mouse_sensitivity)
	cf.set_value("mouse", "invert_y", invert_mouse_y)
	cf.set_value("mouse", "cyclic", mouse_cyclic or touch_owns_mouse)
	cf.set_value("mouse", "cfg_version", CFG_VERSION)
	cf.set_value("joy_opts", "pov_hat_look", pov_hat_look)
	cf.set_value("joy_opts", "pov_look_speed", pov_look_speed)
	cf.set_value("joy_opts", "smooth_ms", joy_smooth_ms)
	for fn in bindings:
		cf.set_value("joy", fn, bindings[fn])
	for act in btn_bindings:
		cf.set_value("joy_btn", act, btn_bindings[act])
	cf.save(CFG_PATH)

func load_config() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	mouse_sensitivity = cf.get_value("mouse", "sensitivity", 1.0)
	invert_mouse_y = cf.get_value("mouse", "invert_y", false)
	mouse_cyclic = cf.get_value("mouse", "cyclic", true)
	if int(cf.get_value("mouse", "cfg_version", 1)) < CFG_VERSION:
		mouse_cyclic = true     # older builds saved it OFF after a touch on a touch-screen PC
	pov_hat_look = cf.get_value("joy_opts", "pov_hat_look", true)
	pov_look_speed = cf.get_value("joy_opts", "pov_look_speed", 1.0)
	joy_smooth_ms = cf.get_value("joy_opts", "smooth_ms", 45.0)
	if cf.has_section("joy"):
		for fn in cf.get_section_keys("joy"):
			bindings[fn] = cf.get_value("joy", fn)
	if cf.has_section("joy_btn"):
		for act in cf.get_section_keys("joy_btn"):
			btn_bindings[act] = cf.get_value("joy_btn", act)
