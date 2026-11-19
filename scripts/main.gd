extends Node3D
## AB206 REALSIM - milestone 1 main loop.
## Builds the world, the helicopter and the UI, runs the flight model at 240 Hz
## (2 sub-steps per 120 Hz physics tick) and routes inputs, cameras, sound and displays.

const DataLoader = preload("res://scripts/core/data_loader.gd")
const HeliFDM = preload("res://scripts/fdm/heli_fdm.gd")
const Trim = preload("res://scripts/fdm/trim.gd")
const World = preload("res://scripts/world/world.gd")
const HoverRefs = preload("res://scripts/world/hover_refs.gd")
const HeliModel = preload("res://scripts/aircraft/heli_model.gd")
const Controls = preload("res://scripts/input/controls.gd")
const CameraRig = preload("res://scripts/core/camera_rig.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PanelScript = preload("res://scripts/ui/instrument_panel.gd")
const Menu = preload("res://scripts/ui/menu.gd")
const JoyPanel = preload("res://scripts/ui/joy_panel.gd")
const HeliAudio = preload("res://scripts/audio/heli_audio.gd")
const Instructor = preload("res://scripts/core/instructor.gd")
const Landing = preload("res://scripts/core/landing_rating.gd")
const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const PhoneServer = preload("res://scripts/input/phone_server.gd")
const PhonePanel = preload("res://scripts/ui/phone_panel.gd")
const Lessons = preload("res://scripts/core/lessons.gd")
const Coach = preload("res://scripts/core/coach.gd")
const HoverHold = preload("res://scripts/core/hover_hold.gd")
const TrainingAssist = preload("res://scripts/core/training_assist.gd")

const SETTINGS_PATH := "user://settings.cfg"
const SUBSTEPS := 2

var data := {}
var fdm
var world
var heli: Node3D
var controls
var cam_rig
var hud
var panel_vp: SubViewport
var panel3d
var menu
var joy
var touch
var phone
var phone_panel
var lessons
var audio
var instructor
var coach
var show_guide := true
var refs                         # outside hover references (sight gates in the world)
var _refs_told := false
var assist                       # TrainingAssist (levels 0-3)
var sim_speed := 1.0              # training speed (Engine.time_scale)
var ghost := {}                   # instructor's suggested control positions (HUD ghost)
var preset := 1
var visibility_m := 12000.0
var vsi_lagged := 0.0
var show_panel_2d := false
var paused := false
var _frame_ms: Array[float] = []
var _fdm_usec_frame := 0
# Auto quality: if the frame rate stays low for a few seconds, step the graphics preset down.
const AUTO_Q_FPS := 38.0
var _auto_q_off := false
var _auto_q_wait := 8.0
var _auto_q_ms := 0.0
var _auto_q_n := 0
var _touch_pending := false
var _touch_sink := 0.0

func _ready() -> void:
	data = DataLoader.load_aircraft()
	fdm = HeliFDM.new(data)
	world = World.new()
	world.name = "World"
	add_child(world)
	world.season = _startup_season()
	world.build(_startup_map())
	fdm.ground = world.terrain
	refs = HoverRefs.new()
	refs.name = "HoverRefs"
	refs.terrain = world.terrain
	refs.cg_height = fdm.cg_height
	world.add_child(refs)

	# instrument panel rendered to a texture for the 3D cockpit
	panel_vp = SubViewport.new()
	panel_vp.size = Vector2i(1000, 420)
	panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	panel_vp.transparent_bg = false
	add_child(panel_vp)
	panel3d = Control.new()
	panel3d.set_script(PanelScript)
	panel_vp.add_child(panel3d)
	_apply_limits(panel3d)

	heli = Node3D.new()
	heli.set_script(HeliModel)
	heli.name = "Helicopter"
	add_child(heli)
	heli.build(fdm, panel_vp.get_texture())

	controls = Controls.new()
	controls.name = "Controls"
	add_child(controls)
	cam_rig = CameraRig.new()
	add_child(cam_rig)
	hud = Hud.new()
	add_child(hud)
	hud.build(PanelScript)
	_apply_limits(hud.panel2d)
	audio = HeliAudio.new()
	add_child(audio)
	instructor = Instructor.new()
	coach = Coach.new()
	coach.instructor = instructor
	lessons = Lessons.new()
	lessons.main = self
	lessons.coach = coach
	lessons.hands = HoverHold.new(fdm)
	assist = TrainingAssist.new(fdm, controls)
	lessons.assist = assist
	menu = Menu.new()
	menu.main = self
	add_child(menu)
	menu.action.connect(_on_menu_action)
	joy = JoyPanel.new()
	joy.controls = controls
	joy.ui_theme = menu._theme
	add_child(joy)
	joy.closed.connect(func() -> void: _set_paused(menu.visible))
	touch = TouchControls.new()
	touch.main = self
	touch.controls = controls
	add_child(touch)
	phone = PhoneServer.new()
	phone.name = "PhoneServer"
	add_child(phone)
	controls.phone = phone
	phone.role_connected.connect(func(r: String) -> void:
		instructor.force("PHONE %s connected. It controls the %s from %s current position right away." % [r.to_upper(), r, "their" if r == "pedals" else "its"]))
	phone.role_lost.connect(func(r: String) -> void:
		instructor.force("PHONE %s lost. The control stays where it was; keyboard/mouse have it again." % r.to_upper()))
	phone.calibrated.connect(func(_r: String) -> void: controls.phone_release())
	phone_panel = PhonePanel.new()
	phone_panel.phone = phone
	phone_panel.controls = controls
	phone_panel.ui_theme = menu._theme
	add_child(phone_panel)
	phone_panel.closed.connect(func() -> void: _set_paused(menu.visible))
	if phone.autostart:
		phone.start()

	if OS.has_feature("web"):
		preset = 0   # web build: start on Low (phones / integrated GPUs); saved choice overrides
	_load_settings()
	apply_preset(preset)
	set_visibility(visibility_m)
	reset_on_pad()
	if DisplayServer.is_touchscreen_available() and (OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")):
		touch.enable()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_auto_dir = a.substr(11)
	if not touch.active:
		instructor.force("Welcome to the Bell 206B-3. Engine running, rotor at 100%, collective down on the main pad. Press F1 for controls. Raise the collective (W or mouse wheel) slowly and hold left pedal (A) as the torque builds.")

func _apply_limits(p) -> void:
	p.limits = {
		"nr_on_min": fdm._v("nr_power_on_min_pct"), "nr_on_max": fdm._v("nr_power_on_max_pct"),
		"nr_off_min": fdm._v("nr_power_off_min_pct"), "nr_off_max": fdm._v("nr_power_off_max_pct"),
		"tq_mcp": fdm._v("max_continuous_power_shp") / fdm._v("torque_100pct_definition") * 100.0,
		"tq_max": 100.0, "n1_max": fdm._v("n1_max_pct"), "vne": fdm._v("vne_kias"),
	}

# ------------------------------------------------------------------ resets
func _place(pos: Vector3, heading: float, speed_kt: float) -> void:
	fdm.pos = pos
	fdm.reset_dynamic_state()
	var hd := deg_to_rad(heading)
	var v := Vector3(sin(hd), 0.0, -cos(hd)) * speed_kt * HeliFDM.KT
	Trim.trim(fdm, heading, v)
	fdm.omega = Vector3.ZERO
	controls.set_from_trim(fdm.cyclic_lon, fdm.cyclic_lat, fdm.collective, fdm.pedal, 1.0)
	vsi_lagged = fdm.vs_fpm()

func reset_on_pad() -> void:
	var p: Vector3 = world.terrain.pads["Main helipad"]["pos"]
	fdm.reset_dynamic_state()
	fdm.pos = p + Vector3(0, fdm.cg_height - fdm.mass * 9.80665 / 4.0 / (fdm.mass * 9.80665 / 4.0 / 0.035), 0)
	fdm._was_on_ground = true
	fdm.vel = Vector3.ZERO
	fdm.set_attitude(0.0, 0.0, 0.0)
	fdm.collective = 0.0
	fdm.cyclic_lon = 0.0
	fdm.cyclic_lat = 0.0
	fdm.pedal = 0.0
	fdm.throttle = 1.0
	# engine at flat-pitch ground load, governor settled
	var out := {}
	fdm.compute_aero(out)
	var dens: float = (fdm.atmo.pressure_pa(fdm.pos.y) / 101325.0) / sqrt(fdm.atmo.temperature_k(fdm.pos.y) / 288.15)
	fdm.n1 = fdm.n1_for_power(float(out["q_load"]) * fdm.omega100 + 150.0 * fdm.omega100, dens)
	fdm.gov_int = fdm.n1 - fdm.n1_for_power(30000.0, dens)
	controls.set_from_trim(0.0, 0.0, 0.0, 0.0, 1.0)
	vsi_lagged = 0.0

func reset_hover() -> void:
	var p: Vector3 = world.terrain.pads["Main helipad"]["pos"]
	_place(p + Vector3(0, 5.0 + fdm.cg_height, 0), 0.0, 0.0)
	instructor.force("HOVER at 5 m skid height, trimmed. Small, smooth corrections: cyclic for position, collective for height, pedals for heading.")

func reset_cruise() -> void:
	var p: Vector3 = world.terrain.pads["Main helipad"]["pos"]
	_place(p + Vector3(0, 300.0 + fdm.cg_height, 1500.0), 0.0, 80.0)
	if world.map_id == "khouribga":
		instructor.force("CRUISE 80 kt at about 1,000 ft above the Khouribga plateau, heading north. The helipad on the main apron is straight ahead, 1.5 km; runway 05/23 is on your right and the city to the north-east.")
	else:
		instructor.force("CRUISE 80 kt at about 1,000 ft above the valley floor, heading north up the valley. The main pad is straight ahead, 1.5 km.")

func reset_autorotation() -> void:
	var p: Vector3 = world.terrain.pads["Main helipad"]["pos"]
	_place(p + Vector3(0, 760.0 + fdm.cg_height, 1800.0), 0.0, 80.0)
	controls.throttle = 0.0
	instructor.force("AUTOROTATION PRACTICE: the throttle has been rolled to idle (simulated engine failure). LOWER THE COLLECTIVE NOW (S), keep 55-65 kt, keep rotor RPM in the green (90-107%). Roll the throttle back on (R) for a power recovery.")

func set_assist(l: int, quiet := false) -> void:
	assist.set_level(l)
	if not quiet:
		var txt: String = ["Training assist OFF - this is the real 206: nothing holds it for you.",
			"Training assist 1 - DAMPING: the wobbles are damped, you still fly it. (Not on the real 206.)",
			"Training assist 2 - ATTITUDE HOLD: the cyclic sets the attitude; centre it and the helicopter levels itself and the drift slowly dies. (Not on the real 206.)",
			"Training assist 3 - HOVER HOLD: the cyclic sets your speed over the ground; centre it and the helicopter stops and holds the spot. (Not on the real 206.)"][assist.level]
		instructor.force(txt, ["Assist off.", "Assist one, damping.", "Assist two, attitude hold.", "Assist three, hover hold."][assist.level])

func set_sim_speed(v: float) -> void:
	sim_speed = clampf(v, 0.25, 1.0)
	Engine.time_scale = sim_speed
	instructor.force("Training speed %d%%%s" % [int(round(sim_speed * 100.0)), " - slow motion to learn the feel; the physics are the same, just slower." if sim_speed < 0.99 else " (real time)."])

func set_weight(kg: float) -> void:
	fdm.set_mass(kg)

## Map chosen at start-up: command line --map=<id> wins, else the saved setting.
var map_override := ""            # tests set this before adding the scene
static var _cmdline_map_used := false   # --map= only applies to the first start, not after a map switch

func _startup_map() -> String:
	if map_override != "":
		return map_override
	if not _cmdline_map_used:
		_cmdline_map_used = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--map="):
				return a.substr(6)
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return str(cf.get_value("world", "map", "valle"))
	return "valle"

## Photo season of real maps: saved choice, else by today's date (Dec-May green, Jun-Nov dry).
func _startup_season() -> String:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK and cf.has_section_key("world", "season"):
		return str(cf.get_value("world", "season"))
	var m: int = Time.get_date_dict_from_system()["month"]
	return "spring" if (m >= 12 or m <= 5) else "summer"

func set_season(s: String) -> void:
	world.set_season(s)
	_save_settings()

## Switch map: saves the choice and rebuilds the whole scene (about 2-4 s on the real map).
func set_map(id: String) -> void:
	if id == world.map_id:
		return
	world.map_id = id
	_save_settings()
	controls.save_config()
	phone.save_config()
	phone.stop()
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func set_visibility(m: float) -> void:
	visibility_m = m
	world.set_visibility(m)

# ---------------------------------------------------------- graphics presets
func apply_preset(i: int) -> void:
	preset = clampi(i, 0, 2)
	var vp := get_viewport()
	match preset:
		0:
			vp.scaling_3d_scale = 0.5
			vp.msaa_3d = Viewport.MSAA_DISABLED
			world.sun.shadow_enabled = false
			world.set_tree_count(1500)
			world.terrain.set_detail(0)
			cam_rig.cam.far = 7000.0
		1:
			vp.scaling_3d_scale = 0.67
			vp.msaa_3d = Viewport.MSAA_DISABLED
			world.sun.shadow_enabled = true
			world.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			world.sun.directional_shadow_max_distance = 150.0
			world.set_tree_count(4500)
			world.terrain.set_detail(1)
			cam_rig.cam.far = 10000.0
		2:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			world.sun.shadow_enabled = true
			world.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			world.sun.directional_shadow_max_distance = 500.0
			world.set_tree_count(9000)
			world.terrain.set_detail(1)
			cam_rig.cam.far = 12000.0
	world.set_draw_preset(preset)
	_save_settings()

## Lowers the preset (then the render scale on Low) when the average FPS stays under
## AUTO_Q_FPS for 4 s of flying. Pressing F7 yourself turns this off for the session.
func _auto_quality(delta: float) -> void:
	if _auto_q_off or paused or _auto_dir != "" or DisplayServer.get_name() == "headless":
		return
	if not get_window().has_focus():
		return
	if _auto_q_wait > 0.0:
		_auto_q_wait -= delta
		return
	_auto_q_ms += delta * 1000.0
	_auto_q_n += 1
	if _auto_q_ms < 4000.0:
		return
	var fps := 1000.0 * _auto_q_n / _auto_q_ms
	_auto_q_ms = 0.0
	_auto_q_n = 0
	if fps >= AUTO_Q_FPS:
		return
	_auto_q_wait = 3.0
	if preset > 0:
		apply_preset(preset - 1)
		instructor.force("Frame rate was low (%.0f FPS): graphics lowered to %s. F7 changes it." % [fps, preset_name()])
	elif get_viewport().scaling_3d_scale > 0.41:
		get_viewport().scaling_3d_scale = 0.4
		instructor.force("Frame rate still low (%.0f FPS): render scale lowered." % fps)
	else:
		_auto_q_off = true

func preset_name() -> String:
	return ["Low", "Medium", "High"][preset]

# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		controls.mouse_look_held = event.pressed
	if event is InputEventMouseMotion and controls.mouse_look_held:
		cam_rig.mouse_look(event.relative)
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu.visible and not joy.visible and not phone_panel.visible and not touch.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if phone_panel.visible:
				phone_panel.close()
				_set_paused(menu.visible)
			elif joy.visible:
				joy.close()
				_set_paused(menu.visible)
			elif menu.visible:
				menu.close()
				_set_paused(false)
			else:
				menu.open()
				_set_paused(true)
		KEY_P:
			if not menu.visible:
				_set_paused(not paused)
		KEY_F1:
			hud.help.visible = not hud.help.visible
		KEY_F2:
			lessons.stop()
			reset_on_pad()
		KEY_F3:
			lessons.stop()
			reset_hover()
		KEY_F4:
			lessons.stop()
			reset_cruise()
		KEY_F5:
			lessons.stop()
			reset_autorotation()
		KEY_F6:
			hud.show_telemetry = not hud.show_telemetry
		KEY_F7:
			_auto_q_off = true
			apply_preset((preset + 1) % 3)
			instructor.force("Graphics preset: " + preset_name())
		KEY_F8:
			if joy.visible:
				joy.close()
				_set_paused(menu.visible)
			else:
				joy.open()
				_set_paused(true)
		KEY_F10:
			if phone_panel.visible:
				phone_panel.close()
				_set_paused(menu.visible)
			else:
				phone_panel.open()
				_set_paused(true)
		KEY_N:
			if phone.running and not phone.roles.is_empty():
				phone.calibrate_all()
				instructor.force("Phone neutral set: cyclic phone = centre, collective phone = lever fully down, pedal phone = pedals centred. The phones keep control; the controls do not jump.")
		KEY_F9:
			instructor.enabled = not instructor.enabled
			if not instructor.enabled:
				instructor.message = ""
		KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		KEY_V:
			cam_rig.cycle()
		KEY_C:
			cam_rig.recenter()
		KEY_H:
			set_assist((assist.level + 1) % 4)
		KEY_G:
			show_guide = not show_guide
			instructor.force("Hover guide circle " + ("ON" if show_guide else "OFF - fly with the outside gates"))
		KEY_B:
			refs.enabled = not refs.enabled
			instructor.force("Outside hover references (gates) " + ("ON" if refs.enabled else "OFF"))
		KEY_T:
			lessons.take_control()
		KEY_Y:
			set_sim_speed(0.75 if sim_speed > 0.9 else (0.5 if sim_speed > 0.6 else 1.0))
		KEY_TAB:
			show_panel_2d = not show_panel_2d
		KEY_F12:
			take_screenshot("")

## F12: saves a PNG to the user data folder (shown on screen). Also used by --autoshot test mode.
func take_screenshot(path: String) -> String:
	var img := get_viewport().get_texture().get_image()
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		path = "user://screenshots/ab206_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(path)
	instructor.force("Screenshot saved: " + ProjectSettings.globalize_path(path))
	return path

var _auto_frames := 0
var _auto_dir := ""

func _autoshot_step() -> void:
	_auto_frames += 1
	var plan := {60: "pad_cockpit", 61: "", 120: "pad_chase", 121: "", 180: "hover_chase", 181: "", 240: "hover_cockpit", 241: "", 300: "cruise_chase", 360: "auto_cockpit", 400: "menu", 440: "joy", 480: "help", 520: "phone", 580: "lesson", 640: "lesson_menu", 644: "menu_settings", 648: "menu_weather", 720: "refs_cockpit", 760: "refs_chase", 820: "refs_cockpit_2m_left_high", 960: "mentor_handover", 970: "quit"}
	match _auto_frames:
		1:
			hud.show_telemetry = true
		59:
			cam_rig.mode = cam_rig.Mode.COCKPIT
		119:
			cam_rig.mode = cam_rig.Mode.CHASE
		150:
			reset_hover()
		179:
			cam_rig.mode = cam_rig.Mode.CHASE
		239:
			cam_rig.mode = cam_rig.Mode.COCKPIT
		270:
			reset_cruise()
			cam_rig.mode = cam_rig.Mode.CHASE
		330:
			reset_autorotation()
			cam_rig.mode = cam_rig.Mode.COCKPIT
		390:
			menu.open()
			menu.show_tab(0)
			_set_paused(true)
		430:
			menu.close()
			joy.open()
		470:
			joy.close()
			_set_paused(false)
			hud.help.visible = true
		490:
			hud.help.visible = false
			phone.start()
			phone_panel.open()
			_set_paused(true)
		530:
			phone_panel.close()
			_set_paused(false)
			lessons.start("h_cyc")
		600:
			menu.open()
			menu.show_tab(1)
			_set_paused(true)
		641:
			menu.show_tab(3)
		645:
			menu.show_tab(2)
		650:
			menu.close()
			_set_paused(false)
			lessons.start("h_full")
			set_assist(3, true)
			cam_rig.mode = cam_rig.Mode.COCKPIT
			show_guide = false
		730:
			cam_rig.mode = cam_rig.Mode.CHASE
		830:
			set_assist(0, true)
			lessons.mentor_axes = "all"
			lessons.start("h_mentor")
			show_guide = true
		770:
			var pad: Vector3 = world.terrain.pads["Main helipad"]["pos"]
			_place(pad + Vector3(-2.0, 1.6 + fdm.cg_height, 0.0), 0.0, 0.0)
			cam_rig.mode = cam_rig.Mode.COCKPIT
	if plan.has(_auto_frames) and plan[_auto_frames] != "":
		if plan[_auto_frames] == "quit":
			get_tree().quit()
		else:
			take_screenshot(_auto_dir + "/" + plan[_auto_frames] + ".png")

func _set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (menu.visible or joy.visible or phone_panel.visible or touch.active) else Input.MOUSE_MODE_CAPTURED

func _on_menu_action(a: String) -> void:
	match a:
		"resume":
			menu.close()
			_set_paused(false)
		"reset_pad":
			reset_on_pad()
		"reset_hover":
			reset_hover()
		"reset_cruise":
			reset_cruise()
		"reset_auto":
			reset_autorotation()
		"joy":
			joy.open()
		"phone":
			phone_panel.open()
		"quit":
			_save_settings()
			controls.save_config()
			get_tree().quit()
	if a == "tab_lessons":
		menu.show_tab(1)
		return
	if a.begins_with("mentor:"):
		lessons.mentor_axes = a.substr(7)
		a = "lesson:h_mentor"
	if a.begins_with("lesson:"):
		lessons.start(a.substr(7))
		menu.close()
		_set_paused(false)
	if a == "lesson_stop":
		lessons.stop()
		menu.close()
		_set_paused(false)
	if a.begins_with("reset"):
		lessons.stop()
		menu.close()
		_set_paused(false)

# ------------------------------------------------------------- simulation
func _physics_process(delta: float) -> void:
	if paused:
		return
	controls.update(delta)
	var dt: float = delta / SUBSTEPS
	_fdm_usec_frame = 0
	var hh = lessons.hands
	var hands_on: bool = hh.any()
	for i in SUBSTEPS:
		fdm.cyclic_lon = controls.cyclic_lon
		fdm.cyclic_lat = controls.cyclic_lat
		fdm.collective = controls.collective
		fdm.pedal = controls.pedal
		fdm.throttle = controls.throttle
		if hands_on:
			# instructor's hands on the dual controls fly the held axes
			hh.update(dt, fdm.collective, fdm.cyclic_lon, fdm.cyclic_lat, fdm.pedal)
			if hh.hold["coll"]:
				fdm.collective = hh.coll
			if hh.hold["cyc"]:
				fdm.cyclic_lon = hh.lon
				fdm.cyclic_lat = hh.lat
			if hh.hold["ped"]:
				fdm.pedal = hh.ped
		# training assists (not on the real 206) act only on the controls you fly yourself
		assist.apply(dt, not (hands_on and hh.hold["cyc"]), not (hands_on and hh.hold["ped"]))
		fdm.step(dt)
		_fdm_usec_frame += fdm.last_step_usec
		if fdm.touchdown_event:
			_touch_pending = true
			_touch_sink = fdm.touchdown_sink
	if hands_on:
		# dual controls are linked: your controls follow the instructor's, so handing over is bumpless
		controls.follow(hh.hold, hh.coll, hh.lon, hh.lat, hh.ped)
	ghost = lessons.suggest(delta)
	coach.update(delta, fdm, controls.cyclic_lon, controls.cyclic_lat, controls.collective, controls.pedal)
	instructor.update(fdm, delta)

func _process(delta: float) -> void:
	if _auto_dir != "":
		_autoshot_step()
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 600:
		_frame_ms.pop_front()
	_auto_quality(delta)
	var xf := Transform3D(fdm.basis, fdm.pos)
	heli.global_transform = xf
	heli.update_visual(fdm, 0.0 if paused else delta)
	heli.set_cockpit_view(cam_rig.mode == cam_rig.Mode.COCKPIT, show_panel_2d)
	cam_rig.update_camera(xf, delta)
	world.update_windsocks(fdm.atmo.mean_wind(5.0))
	audio.update(fdm, cam_rig.mode == cam_rig.Mode.COCKPIT, paused)
	if not paused:
		lessons.update(delta, _touch_pending, _touch_sink)
	if _touch_pending:
		_touch_pending = false
		audio.play_touchdown(_touch_sink)
		if phone.running and _touch_sink > 0.3:
			phone.buzz(int(clampf(_touch_sink * 120.0, 40.0, 400.0)))
		var rating: String = Landing.rate(_touch_sink)
		var col := Color(0.6, 1.0, 0.6)
		if rating == "FIRM":
			col = Color(1.0, 0.9, 0.4)
		elif rating == "HARD" or rating == "DAMAGE":
			col = Color(1.0, 0.35, 0.3)
		if _touch_sink > 0.15:
			hud.show_landing("TOUCHDOWN: %s  (%.2f m/s, %.0f ft/min)" % [rating, _touch_sink, _touch_sink / 0.3048 * 60.0], col)
		if rating == "HARD" or rating == "DAMAGE":
			instructor.force("HARD LANDING (%.1f m/s). On a real 206 this needs an inspection. Arrive with less than about 1 m/s (200 ft/min) and zero ground speed." % _touch_sink)
	if fdm.tail_strike:
		hud.show_landing("TAIL STRIKE", Color(1.0, 0.35, 0.3))
	# instrument values (VSI has a ~1.5 s lag like a real pressure VSI)
	vsi_lagged = lerpf(vsi_lagged, fdm.vs_fpm(), clampf(delta / 1.5, 0.0, 1.0))
	var vals := {
		"tq": maxf(fdm.torque_pct, 0.0), "nr": fdm.nr_pct(), "n2": fdm.n2_pct(), "n1": fdm.n1,
		"ias": fdm.ias_kt(), "pitch": fdm.pitch_deg(), "roll": fdm.roll_deg(),
		"alt_ft": fdm.pos.y / 0.3048, "vsi": vsi_lagged, "hdg": fdm.heading_deg(),
		"low_rpm": fdm.nr_pct() < fdm._v("low_rpm_warning_pct"),
	}
	if phone.running:
		_phone_feedback(delta, vals)
	panel3d.v = vals
	hud.panel2d.v = vals
	hud.panel_holder.visible = show_panel_2d or cam_rig.mode != cam_rig.Mode.COCKPIT
	hud.set_controls(fdm.cyclic_lon, fdm.cyclic_lat, fdm.collective, fdm.pedal, fdm.throttle, controls.pedal_trim)
	hud.set_ghost(ghost, controls.cyclic_lon, controls.cyclic_lat, assist.active_level >= 2)
	hud.set_lesson(lessons.objective if lessons.active() else "")
	var gd: Dictionary = lessons.guide if lessons.active() else {}
	refs.eye_body = cam_rig.eye
	refs.update(gd, "hover" if lessons.id == "h_mentor" else str(coach.ctx.get("phase", "")), fdm, delta)
	if refs.visible and not _refs_told and instructor.enabled:
		_refs_told = instructor.say("refs_intro", "LOOK OUTSIDE, not at the circle. ORANGE gate ahead: keep the far board's stripe between the poles (left/right) and lay the bar on the board's black line (bar below the line = too high). BLUE gate front-right: keep its board between its poles (forward/back). A bar turns GREEN when you are inside 4 ft. G hides the circle, B the gates.", 600.0, 14.0, "Look outside. Keep the boards inside the gates.")
	hud.set_guide(_guide_data() if show_guide else {})
	hud.update_hud(delta, _telemetry_text(), _status_text(), instructor.message, instructor.message_time > 0.0)

var _buzz_t := 0.0

## Data for the hover guide (training aid). In lessons it shows the lesson's target; in free
## flight it appears in a low hover and shows drift, height and yaw only.
func _guide_data() -> Dictionary:
	var g: Dictionary = {}
	if lessons.active():
		if lessons.guide.is_empty():
			return {}
		g = lessons.guide.duplicate()
	elif not fdm.on_ground and fdm.agl < 10.0 and fdm.groundspeed_kt() < 15.0:
		g = {"target": null, "height": NAN, "hdg": NAN, "owner": ""}
	else:
		return {}
	var hb = lessons.hands
	g["vel"] = hb.body_xy(fdm.vel)
	g["agl"] = fdm.agl
	g["vs"] = fdm.vel.y
	g["hdg_now"] = fdm.heading_deg()
	g["yaw_rate"] = rad_to_deg(fdm.omega.z)
	if g.get("target") != null:
		g["rel"] = hb.body_xy(g["target"] - fdm.pos)
	return g

## Status text and vibration cues for the phones (vibration = cue for the real ROTOR RPM horn).
func _phone_feedback(delta: float, vals: Dictionary) -> void:
	var txt := "NR %.0f%%  TQ %.0f%%  %s" % [vals["nr"], vals["tq"], "ROTOR LOW RPM" if vals["low_rpm"] else ""]
	phone.role_status["cyclic"] = "%d,%s" % [1 if controls.phone_cyc_engaged else 0, txt]
	phone.role_status["collective"] = "%d,%s" % [1 if controls.phone_coll_engaged else 0, txt]
	phone.role_status["pedals"] = "%d,%s" % [1 if controls.phone_ped_engaged else 0, txt]
	_buzz_t -= delta
	if vals["low_rpm"] and not paused and _buzz_t <= 0.0:
		phone.buzz(250)
		_buzz_t = 0.8

func _telemetry_text() -> String:
	var avg := 0.0
	for f in _frame_ms:
		avg += f
	avg /= maxf(_frame_ms.size(), 1)
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var p99: float = sorted[int(sorted.size() * 0.99)] if sorted.size() > 10 else avg
	var w: Vector3 = fdm.wind
	var wspd := Vector2(w.x, w.z).length() / HeliFDM.KT
	var t := ""
	t += "IAS %5.1f kt   GS %5.1f kt   VS %+6.0f ft/min\n" % [fdm.ias_kt(), fdm.groundspeed_kt(), fdm.vs_fpm()]
	t += "ALT %6.0f ft MSL   skid height %6.1f m AGL   DA %5.0f ft\n" % [fdm.pos.y / 0.3048, fdm.agl, fdm.atmo.density_altitude_ft(fdm.pos.y)]
	t += "NR %5.1f%%   N2 %5.1f%%   TQ %5.1f%%   N1 %5.1f%%   %s\n" % [fdm.nr_pct(), fdm.n2_pct(), fdm.torque_pct, fdm.n1, "ENGAGED" if fdm.engaged else "FREEWHEEL (needles split)"]
	t += "thrust %5.0f N (%.2f g)   Ct/s %.3f%s   mu %.3f%s\n" % [fdm.thrust, fdm.thrust / (fdm.mass * 9.80665), fdm.ct_sigma, "  STALL" if fdm.stalled else "", fdm.mu, ("   VORTEX RING STATE %.0f%%" % (fdm.vrs * 100.0)) if fdm.vrs > 0.05 else ""]
	t += "induced vel %5.2f m/s   ground effect %4.1f%% less induced flow   hub %4.1f m AGL\n" % [fdm.vi, (1.0 - fdm.ge_factor) * 100.0, fdm.hub_agl]
	t += "tail rotor thrust %5.0f N   disc tilt aft %+5.1f  right %+5.1f deg%s\n" % [fdm.tr_thrust, rad_to_deg(fdm.a1), rad_to_deg(fdm.b1), "   MAST BUMP RISK" if fdm.mast_bump else ""]
	t += "pitch %+5.1f  roll %+5.1f  hdg %03.0f   rates p %+5.1f q %+5.1f r %+5.1f deg/s\n" % [fdm.pitch_deg(), fdm.roll_deg(), fdm.heading_deg(), rad_to_deg(fdm.omega.x), rad_to_deg(fdm.omega.y), rad_to_deg(fdm.omega.z)]
	t += "controls: coll %3.0f%%  cyc lon %+4.0f%%  lat %+4.0f%%  pedal %+4.0f%%  throttle %3.0f%%\n" % [fdm.collective * 100.0, fdm.cyclic_lon * 100.0, fdm.cyclic_lat * 100.0, fdm.pedal * 100.0, fdm.throttle * 100.0]
	t += "mass %4.0f kg   wind %3.0f kt from %03.0f   %s\n" % [fdm.mass, wspd, fdm.atmo.wind_from_deg, "ON GROUND (%d contacts)" % fdm.contact_count if fdm.on_ground else "airborne"]
	t += "FPS %3.0f   frame %4.1f ms   1%% low %3.0f fps   FDM %3d us/frame   preset %s" % [1000.0 / maxf(avg, 0.1), avg, 1000.0 / maxf(p99, 0.1), _fdm_usec_frame, preset_name()]
	return t

func _status_text() -> String:
	var s := "%s view   |   %s   |   mouse cyclic %s   |   assist %s   |   F1 help   Esc menu" % [cam_rig.mode_name(), preset_name(), "ON" if controls.mouse_cyclic else "OFF", assist.SHORT[assist.level] + ("" if assist.active_level == assist.level else " (acting as 1)")]
	if sim_speed < 0.99:
		s += "   |   TRAINING SPEED %d%% (Y)" % int(round(sim_speed * 100.0))
	if phone.running:
		var ps := []
		for r in ["cyclic", "collective", "pedals"]:
			if phone.roles.has(r):
				var eng: bool = controls.phone_engaged(r)
				ps.append(r + (" IN CONTROL" if eng else " (waiting)"))
		s += "   |   phone: " + (", ".join(ps) if ps.size() > 0 else "server on, no phone (F10)")
	if paused:
		s = "PAUSED   |   " + s
	return s

# --------------------------------------------------------------- settings
func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", preset)
	cf.set_value("world", "visibility", visibility_m)
	cf.set_value("world", "map", world.map_id if world else "valle")
	if world:
		cf.set_value("world", "season", world.season)
	if fdm:
		cf.set_value("aircraft", "mass", fdm.mass)
		cf.set_value("weather", "wind_from", fdm.atmo.wind_from_deg)
		cf.set_value("weather", "wind_kt", fdm.atmo.wind_speed_kt)
		cf.set_value("weather", "gust", fdm.atmo.gust_intensity)
		cf.set_value("weather", "oat", fdm.atmo.temp_offset_c)
	cf.set_value("sim", "assist_level", assist.level if assist else 0)
	if lessons:
		cf.set_value("training", "assist_auto_fade", lessons.auto_assist)
	if instructor:
		cf.set_value("training", "voice", instructor.voice)
		cf.set_value("training", "coach", coach.enabled)
		cf.set_value("training", "guide", show_guide)
		cf.set_value("training", "outside_refs", refs.enabled)
	cf.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	preset = cf.get_value("graphics", "preset", 1)
	visibility_m = cf.get_value("world", "visibility", 12000.0)
	fdm.set_mass(cf.get_value("aircraft", "mass", fdm.mass))
	fdm.atmo.wind_from_deg = cf.get_value("weather", "wind_from", 270.0)
	fdm.atmo.wind_speed_kt = cf.get_value("weather", "wind_kt", 5.0)
	fdm.atmo.gust_intensity = cf.get_value("weather", "gust", 0.2)
	fdm.atmo.temp_offset_c = cf.get_value("weather", "oat", 0.0)
	assist.set_level(int(cf.get_value("sim", "assist_level", 0)))
	lessons.auto_assist = cf.get_value("training", "assist_auto_fade", false)   # M2.8: you choose by default
	instructor.voice = cf.get_value("training", "voice", true)
	coach.enabled = cf.get_value("training", "coach", true)
	show_guide = cf.get_value("training", "guide", true)
	refs.enabled = cf.get_value("training", "outside_refs", true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()
		if controls:
			controls.save_config()
		if phone:
			phone.save_config()
			phone.stop()
