extends Node3D
## Cockpit, chase and free cameras. Hold the RIGHT mouse button to look around
## (the mouse controls the cyclic otherwise). Free camera: I/J/K/L move, U/O down/up.
## Z = instrument view: the pilot's head turns down to the panel and the view zooms
## so every gauge fills the screen (works at any window size); Z again (or C, or
## looking around) goes back to the outside view.

enum Mode { COCKPIT, CHASE, FREE }

var cam: Camera3D
var mode := Mode.COCKPIT
var look_yaw := 0.0
## Default head pitch in the cockpit. With the 72 deg vertical field of view this
## puts the whole instrument panel (bottom edge ~47 deg below the eye line) on screen
## with a margin above the status line, and still leaves ~30 % of the screen above
## the horizon for hover references. The vertical FOV is fixed, so this holds for
## any window size or aspect ratio.
const DEFAULT_PITCH := -16.0
const COCKPIT_FOV := 72.0
## Instrument panel face in the helicopter body frame (must match heli_model.gd).
const PANEL_CENTER := Vector3(0.0, 0.0, -1.965)
const PANEL_SIZE := Vector2(1.05, 0.44)
const PANEL_TILT_DEG := -18.0
var look_pitch := DEFAULT_PITCH
const FOCUS_FOV := 40.0
var panel_focus := false
var _focus_t := 0.0
var chase_yaw := 0.0
var chase_pitch := -12.0
var chase_dist := 16.0
var free_pos := Vector3.ZERO
var free_yaw := 0.0
var free_pitch := 0.0
var eye := Vector3(0.38, 0.66, -1.1)     # right seat (pilot in command seat of the 206)
var _smooth_basis := Basis.IDENTITY
var _smooth_pos := Vector3.ZERO

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.far = 12000.0
	add_child(cam)
	cam.make_current()

func mode_name() -> String:
	if mode == Mode.COCKPIT and panel_focus:
		return "Instruments (Z)"
	return ["Cockpit", "Chase", "Free"][mode]

func cycle() -> void:
	mode = (mode + 1) % 3
	if mode == Mode.FREE:
		free_pos = cam.global_position
		free_yaw = cam.global_rotation.y
		free_pitch = cam.global_rotation.x

func toggle_panel_focus() -> void:
	if mode != Mode.COCKPIT:
		mode = Mode.COCKPIT
		panel_focus = true
	else:
		panel_focus = not panel_focus

## Instrument view: the head leans in square to the panel face (like a pilot leaning
## forward to read a gauge) so the gauges are not skewed by the right-seat angle,
## at the distance where the whole panel fits the window with a small margin.
## Returns [yaw_deg, pitch_deg, vertical_fov_deg, eye_position_body].
func panel_focus_view(aspect: float) -> Array:
	var tilt := Basis.from_euler(Vector3(deg_to_rad(PANEL_TILT_DEG), 0.0, 0.0))
	var normal := tilt * Vector3(0, 0, 1)            # points up and aft, towards the pilot
	var t := tan(deg_to_rad(FOCUS_FOV * 0.5))
	var dist := maxf(PANEL_SIZE.y * 0.5 / t, PANEL_SIZE.x * 0.5 / (t * maxf(aspect, 0.5))) * 1.08
	return [0.0, PANEL_TILT_DEG, FOCUS_FOV, PANEL_CENTER + normal * dist]

func mouse_look(rel: Vector2) -> void:
	var k := 0.15
	match mode:
		Mode.COCKPIT:
			if panel_focus:
				# looking around leaves the instrument view from where the head is now
				var f := panel_focus_view(_aspect())
				var s := _ease(_focus_t)
				look_yaw = lerpf(look_yaw, f[0], s)
				look_pitch = lerpf(look_pitch, f[1], s)
				panel_focus = false   # the zoom eases back out from here
			look_yaw = clampf(look_yaw - rel.x * k, -150.0, 150.0)
			look_pitch = clampf(look_pitch - rel.y * k, -70.0, 60.0)
		Mode.CHASE:
			chase_yaw -= rel.x * k
			chase_pitch = clampf(chase_pitch - rel.y * k, -80.0, 30.0)
		Mode.FREE:
			free_yaw -= deg_to_rad(rel.x * k)
			free_pitch = clampf(free_pitch - deg_to_rad(rel.y * k), -1.5, 1.5)

func recenter() -> void:
	look_yaw = 0.0
	look_pitch = DEFAULT_PITCH
	panel_focus = false
	chase_yaw = 0.0
	chase_pitch = -12.0

func _aspect() -> float:
	var sz := cam.get_viewport().get_visible_rect().size if cam.is_inside_tree() else Vector2(16, 9)
	return sz.x / maxf(sz.y, 1.0)

static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func update_camera(heli_xform: Transform3D, dt: float) -> void:
	if mode != Mode.COCKPIT:
		panel_focus = false
		_focus_t = 0.0
	match mode:
		Mode.COCKPIT:
			cam.near = 0.05
			# instrument view blend (about 0.35 s each way, real time so it works when paused)
			var rdt := dt / maxf(Engine.time_scale, 0.01)
			_focus_t = move_toward(_focus_t, 1.0 if panel_focus else 0.0, rdt * 3.0)
			var yaw := look_yaw
			var pitch := look_pitch
			var fov := COCKPIT_FOV
			var head := eye
			if _focus_t > 0.0:
				var f := panel_focus_view(_aspect())
				var s := _ease(_focus_t)
				yaw = lerpf(look_yaw, f[0], s)
				pitch = lerpf(look_pitch, f[1], s)
				fov = lerpf(COCKPIT_FOV, f[2], s)
				head = eye.lerp(f[3], s)
			cam.fov = fov
			var b := heli_xform.basis * Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0), EULER_ORDER_YXZ)
			cam.global_transform = Transform3D(b, heli_xform * head)
		Mode.CHASE:
			cam.near = 0.2
			cam.fov = 65.0
			# follow heading only (not pitch/roll) so the horizon stays readable
			var fwd := -heli_xform.basis.z
			var hdg := atan2(-fwd.x, -fwd.z)
			var target_b := Basis.from_euler(Vector3(deg_to_rad(chase_pitch), hdg + deg_to_rad(chase_yaw), 0.0), EULER_ORDER_YXZ)
			_smooth_basis = _smooth_basis.slerp(target_b, clampf(dt * 3.0, 0.0, 1.0)).orthonormalized()
			var focus := heli_xform.origin + Vector3(0, 1.2, 0)
			cam.global_transform = Transform3D(_smooth_basis, focus + _smooth_basis.z * chase_dist)
		Mode.FREE:
			cam.near = 0.2
			var mv := Vector3.ZERO
			if Input.is_physical_key_pressed(KEY_I): mv.z -= 1
			if Input.is_physical_key_pressed(KEY_K): mv.z += 1
			if Input.is_physical_key_pressed(KEY_J): mv.x -= 1
			if Input.is_physical_key_pressed(KEY_L): mv.x += 1
			if Input.is_physical_key_pressed(KEY_U): mv.y -= 1
			if Input.is_physical_key_pressed(KEY_O): mv.y += 1
			var b := Basis.from_euler(Vector3(free_pitch, free_yaw, 0.0), EULER_ORDER_YXZ)
			var spd := 60.0 if Input.is_key_pressed(KEY_SHIFT) else 15.0
			free_pos += b * mv * spd * dt
			cam.global_transform = Transform3D(b, free_pos)
			# always look at the helicopter unless the user is steering the view
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and mv == Vector3.ZERO:
				cam.look_at(heli_xform.origin, Vector3.UP)
				free_yaw = cam.global_rotation.y
				free_pitch = cam.global_rotation.x
