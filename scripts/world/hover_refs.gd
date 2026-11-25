extends Node3D
## OUTSIDE hover references (training aid): sight gates placed in the world around the lesson's
## hover spot, so the student learns to hold the hover by looking OUT, the way it is really
## taught (pick a reference ahead and one to the side), instead of watching the HUD circle.
##
##  ORANGE gate, straight ahead (14 m) + far board (50 m):
##     far board between the two poles .... you are left/right on the spot
##     bar lying on the board's black line . you are at the right hover height
##  BLUE gate, 35 deg front-right (9 m) + far board (35 m):
##     far board between the two poles .... you are forward/back on the spot
##  Each gate's bar turns GREEN inside the ACS box (4 ft, and the height band for the orange bar),
##  AMBER up to the pass limit (3 m), RED beyond.
##
## The geometry is computed from the pilot's eye (right seat) at the correct hover, so the sight
## picture is exact only from the cockpit view. The gate widths are chosen so "board inside the
## gate" is about the ACS 4 ft box (about 1.3-1.4 m). Simulator aid, not a real-world installation.

const ACS_POS := 1.2192
const FRONT_NEAR := 14.0
const FRONT_FAR := 50.0
const FRONT_HALF := 1.0          # board inside the gate <=> |lateral| < 1.0/(1-14/50) = 1.39 m
const SIDE_ANGLE := 35.0         # deg right of the nose (stays in view from the cockpit)
const SIDE_NEAR := 9.0
const SIDE_FAR := 35.0
const SIDE_HALF := 0.55          # board inside <=> |perp| < 0.74 m  <=> |fore/aft| < ~1.3 m

var terrain
var eye_body := Vector3(0.38, 0.66, -1.1)
var cg_height := 1.15
var enabled := true

var _front: Node3D
var _side: Node3D
var _front_bar_mat: StandardMaterial3D
var _side_bar_mat: StandardMaterial3D
var _anchor = null               # Vector3 ground point of the spot
var _hdg := NAN                  # frame heading (deg)
var _height := 1.0
var status := {}                 # for tests: lat, fwd, dh, front, side ("green"/"amber"/"red")

const GREEN := Color(0.15, 0.95, 0.25)
const AMBER := Color(1.0, 0.75, 0.1)
const RED := Color(1.0, 0.2, 0.15)

func _ready() -> void:
	_front_bar_mat = _mat(GREEN, true)
	_side_bar_mat = _mat(GREEN, true)
	_front = _make_gate(FRONT_NEAR, FRONT_FAR, FRONT_HALF, Color(1.0, 0.45, 0.05), _front_bar_mat, Vector2(1.2, 0.8))
	_side = _make_gate(SIDE_NEAR, SIDE_FAR, SIDE_HALF, Color(0.15, 0.45, 1.0), _side_bar_mat, Vector2(0.9, 0.6))
	add_child(_front)
	add_child(_side)
	visible = false

func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.6
	return m

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi

## A gate: local frame x = across the line of sight, z = -along it (towards the far board),
## y = up from the spot's ground level. Bars are placed at y = 0 and moved to eye height later.
func _make_gate(near: float, far: float, half: float, col: Color, bar_mat: Material, board: Vector2) -> Node3D:
	var g := Node3D.new()
	var white := _mat(Color(0.95, 0.95, 0.95))
	var colm := _mat(col)
	var black := _mat(Color(0.05, 0.05, 0.05))
	# two striped poles, 5 m tall (stripes 0.5 m)
	for sx in [-1.0, 1.0]:
		var pole := Node3D.new()
		pole.name = "PoleL" if sx < 0 else "PoleR"
		pole.position = Vector3(sx * half, 0, -near)
		g.add_child(pole)
		for k in 10:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.5, 0.12)
			_mesh(pole, bm, colm if k % 2 == 0 else white, Vector3(0, 0.25 + k * 0.5, 0))
	# sight bar between the poles (moved to eye height)
	var bar := BoxMesh.new()
	bar.size = Vector3(half * 2.0, 0.1, 0.1)
	_mesh(g, bar, bar_mat, Vector3(0, 0, -near), "Bar")
	# far board on a post: white face, black horizontal line, coloured centre stripe
	var fb := Node3D.new()
	fb.name = "Board"
	fb.position = Vector3(0, 0, -far)
	g.add_child(fb)
	var face := BoxMesh.new()
	face.size = Vector3(board.x, board.y, 0.05)
	_mesh(fb, face, white, Vector3.ZERO)
	var line := BoxMesh.new()
	line.size = Vector3(board.x + 0.02, 0.12, 0.06)
	_mesh(fb, line, black, Vector3.ZERO)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.16, board.y + 0.02, 0.06)
	_mesh(fb, stripe, colm, Vector3.ZERO)
	var post := BoxMesh.new()
	post.size = Vector3(0.1, 1.0, 0.1)
	_mesh(fb, post, colm, Vector3.ZERO, "Post")
	return g

## guide: the lesson's hover guide (target, height, hdg, tol_h ...), may be empty.
## phase: coach phase. f: HeliFDM (for the live position check).
func update(guide: Dictionary, phase: String, f, dt: float) -> void:
	var want: bool = enabled and not guide.is_empty() and not (phase in ["taxi", "approach", "off"])
	if not want:
		visible = false
		_anchor = null
		_hdg = NAN
		status = {}
		return
	var tgt = guide.get("target")
	if tgt != null:
		_anchor = tgt
	elif _anchor == null:
		_anchor = Vector3(f.pos.x, terrain.height_at(f.pos.x, f.pos.z) if terrain else f.pos.y - f.agl - f.cg_height, f.pos.z)
	var h: float = guide.get("height", NAN)
	if not is_nan(h):
		_height = h
	var hd: float = guide.get("hdg", NAN)
	if is_nan(_hdg):
		_hdg = hd if not is_nan(hd) else f.heading_deg()
	elif not is_nan(hd):
		# a new heading (pivot-turn step) swings the gates round smoothly
		var d := wrapf(hd - _hdg, -180.0, 180.0)
		_hdg = wrapf(_hdg + clampf(d, -120.0 * dt, 120.0 * dt), 0.0, 360.0)
	# hide when far from the spot (e.g. still on the way)
	var a: Vector3 = _anchor
	var dist := Vector2(f.pos.x - a.x, f.pos.z - a.z).length()
	if dist > 25.0 or f.agl > 15.0:
		visible = false
		status = {}
		return
	visible = true
	_layout(a)
	_colour(guide, f)

func _frame(hd_deg: float) -> Array:
	var hd := deg_to_rad(hd_deg)
	return [Vector3(sin(hd), 0, -cos(hd)), Vector3(cos(hd), 0, sin(hd))]   # fwd, right

## Eye position (horizontal) when hovering exactly over the spot on the frame heading.
func _eye_ground(a: Vector3) -> Vector3:
	var fr := _frame(_hdg)
	return a + fr[0] * (-eye_body.z) + fr[1] * eye_body.x

func _place_gate(g: Node3D, origin: Vector3, dir_deg: float, near: float, far: float, eye_y: float) -> void:
	var hd := deg_to_rad(dir_deg)
	g.global_transform = Transform3D(Basis(Vector3.UP, -hd), origin)
	var ny: float = origin.y
	var fy: float = origin.y
	if terrain:
		var npos := origin + Vector3(sin(hd), 0, -cos(hd)) * near
		var fpos := origin + Vector3(sin(hd), 0, -cos(hd)) * far
		ny = terrain.height_at(npos.x, npos.z)
		fy = terrain.height_at(fpos.x, fpos.z)
	for pn in ["PoleL", "PoleR"]:
		var p: Node3D = g.get_node(pn)
		p.position.y = ny - origin.y
	g.get_node("Bar").position.y = eye_y
	var b: Node3D = g.get_node("Board")
	b.position.y = eye_y
	var post: MeshInstance3D = b.get_node("Post")
	var ph: float = maxf(eye_y - (fy - origin.y) - 0.2, 0.2)
	(post.mesh as BoxMesh).size.y = ph
	post.position.y = -0.2 - ph * 0.5

func _layout(a: Vector3) -> void:
	var e := _eye_ground(a)
	e.y = a.y
	var eye_y := _height + cg_height + eye_body.y
	_place_gate(_front, e, _hdg, FRONT_NEAR, FRONT_FAR, eye_y)
	_place_gate(_side, e, _hdg + SIDE_ANGLE, SIDE_NEAR, SIDE_FAR, eye_y)

func _grade(err: float, ok: float, limit: float) -> String:
	if err <= ok:
		return "green"
	return "amber" if err <= limit else "red"

func _colour(guide: Dictionary, f) -> void:
	var a: Vector3 = _anchor
	var fr := _frame(_hdg)
	var rel := Vector3(f.pos.x - a.x, 0, f.pos.z - a.z)
	var fwd: float = rel.dot(fr[0])
	var lat: float = rel.dot(fr[1])
	var dh: float = f.agl - _height
	var tol_h: float = guide.get("tol_h", 0.5)
	if is_nan(tol_h):
		tol_h = 0.5
	var pass_pos: float = guide.get("pass_pos", 3.0)
	var fg := _grade(absf(lat), ACS_POS, pass_pos)
	if absf(dh) > tol_h:
		fg = "amber" if fg == "green" or absf(dh) < tol_h * 2.0 else "red"
	var sg := _grade(absf(fwd), ACS_POS, pass_pos)
	_front_bar_mat.albedo_color = _col(fg)
	_front_bar_mat.emission = _col(fg)
	_side_bar_mat.albedo_color = _col(sg)
	_side_bar_mat.emission = _col(sg)
	status = {"lat": lat, "fwd": fwd, "dh": dh, "front": fg, "side": sg}

func _col(s: String) -> Color:
	return GREEN if s == "green" else (AMBER if s == "amber" else RED)

## Sight-picture check used by the tests: is the far board inside the near gate as seen from eye?
## Returns the board's offset in "gate half-widths" (|x| < 1 = inside).
func sight_offset(gate: String, eye: Vector3) -> float:
	var g: Node3D = _front if gate == "front" else _side
	var half := FRONT_HALF if gate == "front" else SIDE_HALF
	var near_c: Vector3 = g.get_node("Bar").global_position
	var far_c: Vector3 = g.get_node("Board").global_position
	var right: Vector3 = g.global_transform.basis.x
	var dn := near_c - eye
	var df := far_c - eye
	var hn := Vector2(dn.x, dn.z)
	var hf := Vector2(df.x, df.z)
	var rr := Vector2(right.x, right.z)
	# angle of the board relative to the gate centre, divided by the gate's half-angle
	var ang_far := atan2(hf.dot(rr), hf.length())
	var ang_near := atan2(hn.dot(rr), hn.length())
	var half_ang := atan2(half, hn.length())
	return (ang_far - ang_near) / half_ang

## Height check: angle of the board line relative to the bar (deg, + = board above bar).
func sight_height(gate: String, eye: Vector3) -> float:
	var g: Node3D = _front if gate == "front" else _side
	var near_c: Vector3 = g.get_node("Bar").global_position
	var far_c: Vector3 = g.get_node("Board").global_position
	var dn := near_c - eye
	var df := far_c - eye
	return rad_to_deg(atan2(df.y, Vector2(df.x, df.z).length()) - atan2(dn.y, Vector2(dn.x, dn.z).length()))
