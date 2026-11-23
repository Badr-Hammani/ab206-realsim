extends Node
## Pilot inputs: keyboard + mouse, and any joystick / HOTAS axis.
## Outputs normalised controls for the flight model:
##   cyclic_lon (+1 forward), cyclic_lat (+1 right), collective (0 down..1 up),
##   pedal (+1 right), throttle (0 idle..1 full open).
## Keyboard pedals/arrow cyclic spring back to their trim position when released;
## the mouse cyclic and collective stay where you leave them (like friction-held controls).

const CFG_PATH := "user://controls.cfg"
const FUNCS := ["cyclic_lat", "cyclic_lon", "collective", "pedal", "throttle"]

var cyclic_lon := 0.0
var cyclic_lat := 0.0
var collective := 0.0
var pedal := 0.0
var throttle := 1.0

var mouse_cyclic := true
signal mouse_cyclic_toggled(on: bool)
var touch_owns_mouse := false       # touch controls switched the mouse cyclic off (not saved)
const CFG_VERSION := 2              # 2 (M2.23): mouse cyclic switched back on once (a touch had saved it off)
var mouse_sensitivity := 1.0
var invert_mouse_y := false
var mouse_look_held := false

var stick_mouse := Vector2.ZERO     # x = lat, y = lon from the mouse
var key_offset := Vector2.ZERO      # arrow keys deflection (springs back)
var pedal_trim := 0.0
var pedal_key := 0.0

# joystick bindings: func -> {device, axis, invert, min, max, deadzone}
var bindings := {}
var joy_raw := {}                   # func -> last raw value (diagnostics)

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
	phone_release()
	_combine()

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
	if event.is_action_pressed("toggle_mouse_cyclic"):
		mouse_cyclic = not mouse_cyclic
		touch_owns_mouse = false
		mouse_cyclic_toggled.emit(mouse_cyclic)
	if event.is_action_pressed("cyclic_center"):
		stick_mouse = Vector2.ZERO

func _joy_bound(fn: String) -> bool:
	return bindings.has(fn) and Input.get_connected_joypads().has(int(bindings[fn]["device"]))

func joy_value(fn: String) -> float:
	var b: Dictionary = bindings[fn]
	var raw := Input.get_joy_axis(int(b["device"]), int(b["axis"]))
	joy_raw[fn] = raw
	var lo: float = b.get("min", -1.0)
	var hi: float = b.get("max", 1.0)
	var t := clampf((raw - lo) / maxf(hi - lo, 0.05), 0.0, 1.0)
	if b.get("invert", false):
		t = 1.0 - t
	var dz: float = b.get("deadzone", 0.03)
	if fn == "collective" or fn == "throttle":
		return t
	var c := t * 2.0 - 1.0
	if absf(c) < dz:
		return 0.0
	return signf(c) * (absf(c) - dz) / (1.0 - dz)

func update(dt: float) -> void:
	_update_phone(dt)
	# collective (rate-based, holds position)
	if not _joy_bound("collective") and not phone_coll_engaged:
		var rate := 0.35 if Input.is_key_pressed(KEY_SHIFT) else 0.18
		if Input.is_action_pressed("collective_up"):
			collective += rate * dt
		if Input.is_action_pressed("collective_down"):
			collective -= rate * dt
		collective = clampf(collective, 0.0, 1.0)
	# throttle twist grip
	if not _joy_bound("throttle") and not phone_thr_engaged:
		if Input.is_action_pressed("throttle_open"):
			throttle += 0.6 * dt
		if Input.is_action_pressed("throttle_close"):
			throttle -= 0.6 * dt
		throttle = clampf(throttle, 0.0, 1.0)
	# pedals: key deflection springs back to the pedal trim (Q/E move the trim)
	var target := 0.0
	if Input.is_action_pressed("pedal_left"):
		target -= 1.0
	if Input.is_action_pressed("pedal_right"):
		target += 1.0
	pedal_key = move_toward(pedal_key, target * 0.6, (2.5 if target != 0.0 else 4.0) * dt)
	if Input.is_action_pressed("pedal_trim_left"):
		pedal_trim -= 0.25 * dt
	if Input.is_action_pressed("pedal_trim_right"):
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
	_combine()

func _combine() -> void:
	cyclic_lat = clampf(stick_mouse.x + key_offset.x, -1.0, 1.0)
	cyclic_lon = clampf(stick_mouse.y + key_offset.y, -1.0, 1.0)
	pedal = clampf(pedal_trim + pedal_key, -1.0, 1.0)
	for fn in FUNCS:
		if _joy_bound(fn):
			var v := joy_value(fn)
			match fn:
				"cyclic_lat": cyclic_lat = v
				"cyclic_lon": cyclic_lon = -v    # stick forward gives negative axis on most devices
				"collective": collective = v
				"pedal": pedal = v
				"throttle": throttle = v
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
	for fn in bindings:
		cf.set_value("joy", fn, bindings[fn])
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
	if cf.has_section("joy"):
		for fn in cf.get_section_keys("joy"):
			bindings[fn] = cf.get_value("joy", fn)
