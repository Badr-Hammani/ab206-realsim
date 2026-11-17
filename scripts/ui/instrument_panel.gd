extends Control
## Bell 206B-3 style instrument cluster (simplified layout), drawn in code.
## Every needle is driven by the simulation each frame (see main.gd -> panel.v).
## Markings come from the aircraft data file (verified/derived values where available).

const PANEL_SIZE := Vector2(1000, 420)
const R := 86.0

var v := {
	"tq": 0.0, "nr": 100.0, "n2": 100.0, "n1": 62.0, "ias": 0.0, "pitch": 0.0, "roll": 0.0,
	"alt_ft": 0.0, "vsi": 0.0, "hdg": 0.0, "low_rpm": false, "horn_test": false,
}
var limits := {
	"nr_on_min": 95.0, "nr_on_max": 100.0, "nr_off_min": 90.0, "nr_off_max": 107.0,
	"tq_mcp": 85.0, "tq_max": 100.0, "n1_max": 105.0, "vne": 130.0,
}
var font: Font
var blink := 0.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

func _process(dt: float) -> void:
	blink = fmod(blink + dt, 1.0)
	queue_redraw()

# value -> angle helpers (angle 0 = right, clockwise positive because y is down)
func _ang(val: float, vmin: float, vmax: float, a0: float, a1: float) -> float:
	return deg_to_rad(lerpf(a0, a1, clampf((val - vmin) / (vmax - vmin), 0.0, 1.0)))

func _face(c: Vector2, title: String) -> void:
	draw_circle(c, R + 6, Color(0.18, 0.18, 0.19))
	draw_circle(c, R, Color(0.05, 0.05, 0.06))
	draw_string(font, c + Vector2(-R, R * 0.48), title, HORIZONTAL_ALIGNMENT_CENTER, R * 2, 13, Color(0.85, 0.85, 0.85))

func _arc(c: Vector2, r: float, vmin: float, vmax: float, s: float, e: float, a0: float, a1: float, col: Color, w := 6.0) -> void:
	draw_arc(c, r, _ang(s, vmin, vmax, a0, a1), _ang(e, vmin, vmax, a0, a1), 24, col, w, true)

func _ticks(c: Vector2, vmin: float, vmax: float, step: float, label_step: float, a0: float, a1: float, fmt := "%d", scale := 1.0) -> void:
	var val := vmin
	while val <= vmax + 0.001:
		var a := _ang(val, vmin, vmax, a0, a1)
		var dir := Vector2(cos(a), sin(a))
		var major := is_equal_approx(fmod(val - vmin, label_step), 0.0) or fmod(val - vmin, label_step) < 0.001
		draw_line(c + dir * (R - (14.0 if major else 7.0)), c + dir * (R - 2.0), Color.WHITE, 2.0 if major else 1.0, true)
		if major:
			draw_string(font, c + dir * (R - 27.0) + Vector2(-16, 5), fmt % (val * scale), HORIZONTAL_ALIGNMENT_CENTER, 32, 12, Color.WHITE)
		val += step

func _needle(c: Vector2, a: float, length: float, col: Color, w := 4.0) -> void:
	var dir := Vector2(cos(a), sin(a))
	draw_line(c - dir * 10.0, c + dir * length, col, w, true)
	draw_circle(c, 6.0, Color(0.25, 0.25, 0.25))

func _readout(c: Vector2, text: String, y := 26.0) -> void:
	var box := Rect2(c + Vector2(-30, y - 13), Vector2(60, 18))
	draw_rect(box, Color(0.0, 0.0, 0.0))
	draw_rect(box, Color(0.4, 0.4, 0.4), false, 1.0)
	draw_string(font, box.position + Vector2(0, 14), text, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(0.6, 1.0, 0.6))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color(0.10, 0.10, 0.11))
	var row1 := 108.0
	var row2 := 312.0
	_torque(Vector2(110, row1))
	_tach(Vector2(325, row1))
	_asi(Vector2(540, row1))
	_attitude(Vector2(755, row1))
	_n1(Vector2(110, row2))
	_alt(Vector2(325, row2))
	_vsi(Vector2(540, row2))
	_hdg(Vector2(755, row2))
	_warnings(Vector2(880, 30))

func _torque(c: Vector2) -> void:
	_face(c, "TORQUE %")
	var a0 := 135.0
	var a1 := 405.0
	_arc(c, R - 4, 0, 120, 0, limits["tq_mcp"], a0, a1, Color(0.1, 0.75, 0.2))
	_arc(c, R - 4, 0, 120, limits["tq_mcp"], limits["tq_max"], a0, a1, Color(0.95, 0.85, 0.1))
	_arc(c, R - 4, 0, 120, limits["tq_max"], limits["tq_max"] + 1.2, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 120, 5, 20, a0, a1)
	_needle(c, _ang(v["tq"], 0, 120, a0, a1), R - 10, Color.WHITE)
	_readout(c, "%3.0f" % v["tq"], 44)

func _tach(c: Vector2) -> void:
	_face(c, "N2  ROTOR  %")
	var a0 := 135.0
	var a1 := 405.0
	# power-off rotor limits (outer), power-on limits (inner)
	_arc(c, R - 2, 0, 120, limits["nr_off_min"], limits["nr_off_max"], a0, a1, Color(0.1, 0.75, 0.2), 4)
	_arc(c, R - 2, 0, 120, limits["nr_off_max"], limits["nr_off_max"] + 0.8, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_arc(c, R - 10, 0, 120, limits["nr_on_min"], limits["nr_on_max"], a0, a1, Color(0.1, 0.75, 0.2), 6)
	_arc(c, R - 10, 0, 120, limits["nr_on_max"], limits["nr_on_max"] + 0.8, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 120, 5, 20, a0, a1)
	_needle(c, _ang(v["n2"], 0, 120, a0, a1), R - 34, Color(0.95, 0.95, 0.95), 5)
	_needle(c, _ang(v["nr"], 0, 120, a0, a1), R - 8, Color(1.0, 0.75, 0.2), 3)
	draw_string(font, c + Vector2(-R, 30), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.75, 0.2))
	draw_string(font, c + Vector2(R - 18, 30), "N2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _asi(c: Vector2) -> void:
	_face(c, "AIRSPEED KNOTS")
	var a0 := -90.0
	var a1 := 240.0
	_arc(c, R - 4, 0, 150, 0, limits["vne"], a0, a1, Color(0.1, 0.75, 0.2))
	_arc(c, R - 4, 0, 150, limits["vne"], limits["vne"] + 1.5, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 150, 10, 20, a0, a1)
	_needle(c, _ang(v["ias"], 0, 150, a0, a1), R - 10, Color.WHITE)

func _attitude(c: Vector2) -> void:
	draw_circle(c, R + 6, Color(0.18, 0.18, 0.19))
	var ppd := R / 28.0
	var roll := deg_to_rad(v["roll"])
	var circle := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		circle.append(c + Vector2(cos(a), sin(a)) * R)
	draw_colored_polygon(circle, Color(0.25, 0.55, 0.9))
	var hy: float = v["pitch"] * ppd
	var ground := PackedVector2Array([Vector2(-3 * R, hy), Vector2(3 * R, hy), Vector2(3 * R, 4 * R), Vector2(-3 * R, 4 * R)])
	var rot := Transform2D(-roll, c)
	var gw := rot * ground
	for poly in Geometry2D.intersect_polygons(circle, gw):
		draw_colored_polygon(poly, Color(0.55, 0.35, 0.15))
	for k in range(-6, 7):
		if k == 0:
			continue
		var y: float = hy - k * 5.0 * ppd
		var w := 22.0 if k % 2 == 0 else 11.0
		var p0 := rot * Vector2(-w, y)
		var p1 := rot * Vector2(w, y)
		if p0.distance_to(c) < R * 0.85 and p1.distance_to(c) < R * 0.85:
			draw_line(p0, p1, Color.WHITE, 1.5, true)
	var h0 := rot * Vector2(-R, hy)
	var h1 := rot * Vector2(R, hy)
	var hits := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([h0, h1]), circle)
	for seg in hits:
		draw_polyline(seg, Color.WHITE, 2.0, true)
	# bank scale
	for b in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(-90.0 + b)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (R - 10), c + d * R, Color.WHITE, 2.0)
	var pa := deg_to_rad(-90.0) - roll
	var pd := Vector2(cos(pa), sin(pa))
	var tip := c + pd * (R - 12)
	var side := Vector2(-pd.y, pd.x) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, tip - pd * 12 + side, tip - pd * 12 - side]), Color(1.0, 0.6, 0.1))
	# fixed aircraft symbol
	var org := Color(1.0, 0.6, 0.1)
	draw_line(c + Vector2(-45, 0), c + Vector2(-15, 0), org, 4)
	draw_line(c + Vector2(15, 0), c + Vector2(45, 0), org, 4)
	draw_circle(c, 4, org)
	draw_string(font, c + Vector2(-R, R + 20), "ATTITUDE", HORIZONTAL_ALIGNMENT_CENTER, R * 2, 12, Color(0.85, 0.85, 0.85))

func _n1(c: Vector2) -> void:
	_face(c, "GAS PROD N1 %")
	var a0 := 135.0
	var a1 := 405.0
	_arc(c, R - 4, 0, 110, 60, limits["n1_max"], a0, a1, Color(0.1, 0.75, 0.2))
	_arc(c, R - 4, 0, 110, limits["n1_max"], limits["n1_max"] + 1.0, a0, a1, Color(0.95, 0.1, 0.1), 10)
	_ticks(c, 0, 110, 5, 10, a0, a1)
	_needle(c, _ang(v["n1"], 0, 110, a0, a1), R - 10, Color.WHITE)
	_readout(c, "%5.1f" % v["n1"], 44)

func _alt(c: Vector2) -> void:
	_face(c, "ALT FEET")
	var alt: float = v["alt_ft"]
	for i in 10:
		var a := deg_to_rad(-90.0 + i * 36.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (R - 14), c + d * (R - 2), Color.WHITE, 2.0)
		draw_string(font, c + d * (R - 27) + Vector2(-8, 5), str(i), HORIZONTAL_ALIGNMENT_CENTER, 16, 14, Color.WHITE)
		for j in range(1, 5):
			var a2 := deg_to_rad(-90.0 + i * 36.0 + j * 7.2)
			var d2 := Vector2(cos(a2), sin(a2))
			draw_line(c + d2 * (R - 7), c + d2 * (R - 2), Color.WHITE, 1.0)
	_readout(c, "%05d" % int(round(alt / 10.0) * 10.0), -32)
	var a_th := deg_to_rad(-90.0 + fmod(alt, 10000.0) / 10000.0 * 360.0)
	var a_hu := deg_to_rad(-90.0 + fmod(alt, 1000.0) / 1000.0 * 360.0)
	_needle(c, a_th, R * 0.5, Color.WHITE, 6)
	_needle(c, a_hu, R - 12, Color.WHITE, 3)
	draw_string(font, c + Vector2(-R, 40), "1013 hPa", HORIZONTAL_ALIGNMENT_CENTER, R * 2, 11, Color(0.7, 0.7, 0.7))

func _vsi(c: Vector2) -> void:
	_face(c, "VERT SPEED")
	# 0 at 9 o'clock; up = clockwise to 2000 at 3 o'clock (top half)
	var a0 := 180.0
	var a1 := 360.0
	var val: float = clampf(v["vsi"], -2000.0, 2000.0)
	for t in [-2000, -1500, -1000, -500, 0, 500, 1000, 1500, 2000]:
		var a := deg_to_rad(180.0 + t / 2000.0 * 160.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (R - 14), c + d * (R - 2), Color.WHITE, 2.0)
		draw_string(font, c + d * (R - 28) + Vector2(-12, 5), str(absi(t) / 100), HORIZONTAL_ALIGNMENT_CENTER, 24, 12, Color.WHITE)
	draw_string(font, c + Vector2(-20, -24), "UP", HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(0.8, 0.8, 0.8))
	draw_string(font, c + Vector2(-20, 34), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color(0.8, 0.8, 0.8))
	draw_string(font, c + Vector2(10, 4), "100 FPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
	_needle(c, deg_to_rad(180.0 + val / 2000.0 * 160.0), R - 10, Color.WHITE)

func _hdg(c: Vector2) -> void:
	_face(c, "")
	var hdg: float = v["hdg"]
	for i in 72:
		var deg := i * 5.0
		var a := deg_to_rad(deg - hdg - 90.0)
		var d := Vector2(cos(a), sin(a))
		var major := i % 6 == 0
		draw_line(c + d * (R - (14.0 if major else 7.0)), c + d * (R - 2.0), Color.WHITE, 2.0 if major else 1.0)
		if major:
			var lbl := str(int(deg / 10.0))
			match int(deg):
				0: lbl = "N"
				90: lbl = "E"
				180: lbl = "S"
				270: lbl = "W"
			draw_string(font, c + d * (R - 28) + Vector2(-12, 5), lbl, HORIZONTAL_ALIGNMENT_CENTER, 24, 13, Color.WHITE)
	# lubber line and aircraft
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -R + 2), c + Vector2(-7, -R - 8), c + Vector2(7, -R - 8)]), Color(1.0, 0.6, 0.1))
	draw_line(c + Vector2(0, -26), c + Vector2(0, 26), Color(1.0, 0.6, 0.1), 3)
	draw_line(c + Vector2(-20, -6), c + Vector2(20, -6), Color(1.0, 0.6, 0.1), 3)
	draw_line(c + Vector2(-8, 20), c + Vector2(8, 20), Color(1.0, 0.6, 0.1), 3)
	_readout(c, "%03d" % (int(round(hdg)) % 360), 46)

func _warnings(p: Vector2) -> void:
	var lit: bool = v["low_rpm"] and blink < 0.6
	var box := Rect2(p, Vector2(105, 46))
	draw_rect(box, Color(0.8, 0.1, 0.05) if lit else Color(0.22, 0.06, 0.05))
	draw_rect(box, Color(0.4, 0.4, 0.4), false, 1.5)
	var tc := Color(1, 1, 1) if lit else Color(0.45, 0.3, 0.3)
	draw_string(font, p + Vector2(0, 19), "ROTOR", HORIZONTAL_ALIGNMENT_CENTER, 105, 14, tc)
	draw_string(font, p + Vector2(0, 37), "LOW RPM", HORIZONTAL_ALIGNMENT_CENTER, 105, 14, tc)
	draw_string(font, p + Vector2(0, 70), "Bell 206B-3", HORIZONTAL_ALIGNMENT_CENTER, 105, 12, Color(0.6, 0.6, 0.6))
	draw_string(font, p + Vector2(0, 86), "SIMULATION", HORIZONTAL_ALIGNMENT_CENTER, 105, 10, Color(0.5, 0.5, 0.5))
