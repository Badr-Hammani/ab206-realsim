extends RefCounted
## Live flight coach ("auto teaching"). Watches the aircraft AND the student's own control
## inputs every frame and gives one short, specific correction at a time, in aircraft-relative
## words ("drifting left - ease right cyclic"). The first time a fault appears it explains WHY,
## in plain language; after that it only gives the short cue, so it does not nag.
## Lessons give it a target (spot, height, heading, tolerances, which controls the student has);
## in free flight it coaches low hover and touchdown from the motion alone.
## Cues are training advice for this simulator; your instructor's technique comes first.

var instructor
var enabled := true
## Context, set by lessons every frame (or left empty in free flight).
##  target: Vector3 or null    height: float or NAN    hdg: float or NAN
##  tol_pos, tol_h, tol_hdg     student: {"coll","ped","cyc"} -> bool      phase: String
var ctx := {}
var faults := {}               # fault key -> count (for the debrief)
var stable_time := 0.0
var quiet := false             # true: the lesson gives its own cues (the automatic hover cues stay silent)

var _gap := 0.0                # global quiet time between cues
var _hist: Array = []          # recent [t, lon, lat, coll, ped, p, q, r]
var _t := 0.0
var _seen_concepts := {}
var _td_time := -1.0
var _prev_ground := true

const CONCEPT := {
	"drift": "WHY IT DRIFTS: the helicopter moves wherever the rotor disc is tilted, and the disc follows the cyclic with a short lag. So: a small pressure, wait, and take it out again BEFORE you arrive. Keep your eyes outside, well ahead, not on the ground under the nose.",
	"height": "COLLECTIVE = HEIGHT: raising it adds blade pitch and thrust. The governor feeds in power to hold rotor RPM, so torque rises. Only a few percent of collective changes the hover height - think tiny, slow movements and wait for the result.",
	"heading": "PEDALS = HEADING: the tail rotor balances main-rotor torque. The 206 main rotor turns counter-clockwise seen from above, so the fuselage wants to yaw RIGHT: more power needs more LEFT pedal, less power needs right pedal.",
	"pio": "OVER-CONTROLLING (pilot-induced oscillation): each correction arrives after the helicopter has already started coming back, so you end up chasing it. Fix: hold the controls still for a moment, then use smaller and slower inputs - pressure, not movement.",
	"overshoot": "ANTICIPATE: a hovering helicopter keeps moving after you stop pushing the cyclic. Start taking the correction out about halfway back to the spot, so the drift stops exactly over it.",
	"couple": "COUPLING: you raised the collective and the nose swung right - that is the extra torque. Move the left pedal TOGETHER with the collective (and right pedal when you lower it). Good pilots do it without thinking.",
	"touchdown": "SETTING DOWN: lower the collective so slowly that you hardly notice the descent, and keep position and heading with cyclic and pedals. When the skids touch, keep lowering smoothly to fully down, cyclic centred.",
	"rollover": "SIDEWAYS MOVEMENT NEAR THE GROUND is dangerous: if a skid catches while you move sideways, the helicopter can pivot over it (dynamic rollover). Always touch down and lift off with zero movement over the ground.",
}

func reset() -> void:
	quiet = false
	faults = {}
	stable_time = 0.0
	_gap = 0.0
	_hist.clear()
	_td_time = -1.0

func _fault(k: String) -> void:
	faults[k] = int(faults.get(k, 0)) + 1

## Concept explanation once per session, then short cues. Returns true if something was shown.
func cue(key: String, text: String, concept := "", cooldown := 6.0) -> bool:
	if not enabled or instructor == null or _gap > 0.0:
		return false
	if concept != "" and not _seen_concepts.has(concept) and CONCEPT.has(concept):
		_seen_concepts[concept] = true
		if instructor.say("why_" + concept, CONCEPT[concept] + "\n\nNOW: " + text, 1e9, 12.0, text):
			_gap = 8.0
			_fault(key)
			return true
	if instructor.say("cue_" + key, text, cooldown, 4.5, text):
		_gap = 3.5
		_fault(key)
		return true
	return false

static func dir_words(v: Vector2) -> String:
	## v = (forward, right). Returns e.g. "forward and left".
	var w := []
	if absf(v.x) > 0.35 * v.length():
		w.append("forward" if v.x > 0.0 else "back")
	if absf(v.y) > 0.35 * v.length():
		w.append("right" if v.y > 0.0 else "left")
	return " and ".join(w)

static func opposite_words(v: Vector2) -> String:
	return dir_words(-v)

func _body_xy(f, v: Vector3) -> Vector2:
	var hd := deg_to_rad(f.heading_deg())
	var g := Vector2(v.x, v.z)
	return Vector2(g.dot(Vector2(sin(hd), -cos(hd))), g.dot(Vector2(cos(hd), sin(hd))))

func _student(axis: String) -> bool:
	var s: Dictionary = ctx.get("student", {"coll": true, "ped": true, "cyc": true})
	return bool(s.get(axis, true))

## Oscillation detector: number of sign reversals of an angular rate above a threshold.
func _reversals(idx: int, thresh: float, window: float) -> int:
	var n := 0
	var last := 0
	for h in _hist:
		if _t - float(h[0]) > window:
			continue
		var v: float = h[idx]
		var s := 0
		if v > thresh:
			s = 1
		elif v < -thresh:
			s = -1
		if s != 0 and last != 0 and s != last:
			n += 1
		if s != 0:
			last = s
	return n

func _stick_travel(window: float) -> float:
	var d := 0.0
	var prev = null
	for h in _hist:
		if _t - float(h[0]) > window:
			continue
		if prev != null:
			d += Vector2(h[1] - prev[1], h[2] - prev[2]).length()
		prev = h
	return d

## s_* = the student's own control positions (not the instructor's hands).
func update(dt: float, f, s_lon: float, s_lat: float, s_coll: float, s_ped: float) -> void:
	_t += dt
	_gap = maxf(_gap - dt, 0.0)
	_hist.append([_t, s_lon, s_lat, s_coll, s_ped, rad_to_deg(f.omega.x), rad_to_deg(f.omega.y), rad_to_deg(f.omega.z)])
	while _hist.size() > 0 and _t - float(_hist[0][0]) > 5.0:
		_hist.pop_front()
	if not enabled:
		return
	var phase: String = ctx.get("phase", "")
	var airborne: bool = not f.on_ground
	var gs_ms: float = Vector2(f.vel.x, f.vel.z).length()
	var low_hover: bool = airborne and f.agl < 12.0 and gs_ms < 6.0
	# touchdown bookkeeping
	if f.on_ground and not _prev_ground:
		_td_time = _t
	_prev_ground = f.on_ground
	if phase == "approach" or phase == "off" or quiet:
		return
	if not low_hover and not (f.on_ground and _td_time >= 0.0):
		stable_time = 0.0
		return
	var vb := _body_xy(f, f.vel)
	var tgt = ctx.get("target", null)
	var h_t: float = ctx.get("height", NAN)
	var hdg_t: float = ctx.get("hdg", NAN)
	var tol_pos: float = ctx.get("tol_pos", 1.2)
	var tol_h: float = ctx.get("tol_h", 0.5)
	var tol_hdg: float = ctx.get("tol_hdg", 10.0)
	var ok_all := true

	# ---- after touchdown: lower the collective, do not lift again
	if f.on_ground:
		if _td_time >= 0.0 and _t - _td_time > 3.0 and s_coll > 0.15 and _student("coll") and phase in ["land", ""]:
			cue("coll_down", "You are on the ground: lower the collective smoothly all the way down and keep the cyclic centred.", "touchdown", 8.0)
		return

	# ---- over-controlling (checked first: it is the root cause of most other faults)
	var rev := _reversals(5, 4.0, 4.0) + _reversals(6, 4.0, 4.0)
	if _student("cyc") and rev >= 4 and _stick_travel(3.0) > 0.35:
		ok_all = false
		stable_time = 0.0
		if cue("pio", "You are over-controlling the cyclic. Freeze it for a second, then use smaller, slower inputs.", "pio", 8.0):
			return

	# ---- touchdown phase cues
	if phase == "land" or (phase == "" and f.agl < 1.2 and f.vel.y < -0.2):
		if f.agl < 1.0 and f.vel.y < -0.6 and _student("coll"):
			cue("sink_fast", "Too fast for touchdown (%.1f m/s). Raise the collective slightly to slow the descent." % -f.vel.y, "touchdown", 4.0)
			return
		if f.agl < 0.8 and gs_ms > 0.5 and _student("cyc"):
			cue("td_drift", "Stop the movement %s before the skids touch - hold the spot." % dir_words(vb), "rollover", 4.0)
			return

	# ---- collective/pedal coupling (torque yaw)
	if _hist.size() > 20 and _student("ped") and _student("coll"):
		var old = _hist[maxi(_hist.size() - 40, 0)]
		var coll_rate: float = (s_coll - float(old[3])) / maxf(_t - float(old[0]), 0.05)
		var r: float = rad_to_deg(f.omega.z)
		if coll_rate > 0.06 and r < -6.0:
			cue("couple", "Collective up, nose swinging right: add left pedal with it.", "couple", 10.0)
		elif coll_rate < -0.06 and r > 6.0:
			cue("couple", "Collective down, nose swinging left: add right pedal with it.", "couple", 10.0)

	# ---- height
	if _student("coll"):
		if not is_nan(h_t):
			var he: float = f.agl - h_t
			if absf(he) > tol_h:
				ok_all = false
				if he > 0.0 and f.vel.y > -0.15:
					cue("high", "Too high (%.1f m, aim %.1f m). Lower the collective a little." % [f.agl, h_t], "height")
				elif he < 0.0 and f.vel.y < 0.15:
					cue("low", "Too low (%.1f m, aim %.1f m). Raise the collective a little." % [f.agl, h_t], "height")
		elif phase != "land" and absf(f.vel.y) > 0.7 and f.agl < 6.0:
			cue("climb" if f.vel.y > 0.0 else "sink", ("Climbing" if f.vel.y > 0.0 else "Sinking") + " - small collective correction to hold your height.", "height", 8.0)

	# ---- heading
	if _student("ped") and phase != "turn":
		var r: float = rad_to_deg(f.omega.z)    # aero yaw rate, + = nose right
		if not is_nan(hdg_t):
			var e := wrapf(f.heading_deg() - hdg_t, -180.0, 180.0)
			if absf(e) > tol_hdg:
				ok_all = false
				if e > 0.0 and r > -2.0:
					cue("hdg_r", "Nose is %.0f deg right of the heading. A little left pedal." % e, "heading")
				elif e < 0.0 and r < 2.0:
					cue("hdg_l", "Nose is %.0f deg left of the heading. A little right pedal." % -e, "heading")
		elif absf(r) > 8.0:
			cue("yaw", "Nose swinging %s - %s pedal to stop it." % ["right" if r > 0.0 else "left", "left" if r > 0.0 else "right"], "heading", 8.0)

	# ---- position / drift (cyclic)
	if _student("cyc"):
		var spd := vb.length()
		if tgt != null:
			var pe := _body_xy(f, tgt - f.pos)       # from the aircraft to the spot
			var dist := pe.length()
			var closing := vb.dot(pe.normalized()) if dist > 0.05 else 0.0
			if dist > tol_pos:
				ok_all = false
			if dist > 0.6 and closing > 0.5 and dist / closing < 1.6:
				cue("overshoot", "Coming back fast - start taking the correction out now so you stop over the spot.", "overshoot", 6.0)
			elif dist > tol_pos and closing < 0.15 and spd > 0.3:
				cue("drift", "Drifting %s, %.1f m off the spot. Gentle %s cyclic, then centre it." % [dir_words(vb), dist, opposite_words(vb)], "drift")
			elif dist > tol_pos and spd <= 0.3:
				cue("off_spot", "The spot is %.1f m %s of you. Small %s cyclic pressure to move back over it." % [dist, dir_words(pe), dir_words(pe)], "drift")
		elif spd > 0.8 and phase != "taxi":
			cue("drift", "Drifting %s. Gentle %s cyclic, then centre it." % [dir_words(vb), opposite_words(vb)], "drift", 7.0)

	# ---- praise when it is genuinely stable
	if ok_all and vb.length() < 0.4 and absf(f.vel.y) < 0.25 and absf(rad_to_deg(f.omega.z)) < 4.0:
		stable_time += dt
	else:
		stable_time = 0.0
	if stable_time > 10.0:
		stable_time = -20.0
		cue("good", "Good - that is a stable hover. Keep the inputs that small.", "", 45.0)
