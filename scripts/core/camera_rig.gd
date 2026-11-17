extends Node3D
## Cockpit, chase and free cameras. Hold the RIGHT mouse button to look around
## (the mouse controls the cyclic otherwise). Free camera: I/J/K/L move, U/O down/up.

enum Mode { COCKPIT, CHASE, FREE }

var cam: Camera3D
var mode := Mode.COCKPIT
var look_yaw := 0.0
var look_pitch := -8.0
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
	return ["Cockpit", "Chase", "Free"][mode]

func cycle() -> void:
	mode = (mode + 1) % 3
	if mode == Mode.FREE:
		free_pos = cam.global_position
		free_yaw = cam.global_rotation.y
		free_pitch = cam.global_rotation.x

func mouse_look(rel: Vector2) -> void:
	var k := 0.15
	match mode:
		Mode.COCKPIT:
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
	look_pitch = -8.0
	chase_yaw = 0.0
	chase_pitch = -12.0

func update_camera(heli_xform: Transform3D, dt: float) -> void:
	match mode:
		Mode.COCKPIT:
			cam.near = 0.05
			cam.fov = 72.0
			var b := heli_xform.basis * Basis.from_euler(Vector3(deg_to_rad(look_pitch), deg_to_rad(look_yaw), 0.0), EULER_ORDER_YXZ)
			cam.global_transform = Transform3D(b, heli_xform * eye)
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
