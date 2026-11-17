extends SceneTree
## Manual integration harness: runs the phone server headless for N seconds and prints
## what it receives. Used with an external client (tests/phone_client.py) or a browser.
const PhoneServer = preload("res://scripts/input/phone_server.gd")
const Controls = preload("res://scripts/input/controls.gd")
var ps
var ctl
var t := 0.0
var next_print := 0.0
var dur := 20.0
func _init():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dur="):
			dur = float(a.substr(6))
	ps = PhoneServer.new()
	root.add_child(ps)
	ctl = Controls.new()
	root.add_child(ctl)
	ctl.phone = ps
	ps.calibrated.connect(func(_r): ctl.phone_release())
	if "--hover" in OS.get_cmdline_user_args():
		ctl.set_from_trim(0.15, -0.05, 0.5, 0.0, 1.0)   # sim already flying: phones must not wait for a match
	var ok = ps.start()
	print("START ", ok, " err='", ps.error_text, "' addrs=", ps.addresses, " url=", ps.url(true))
func _process(dt):
	t += dt
	ctl.update(dt)
	ps.role_status["cyclic"] = "%d,test" % (1 if ctl.phone_cyc_engaged else 0)
	ps.role_status["collective"] = "%d,test" % (1 if ctl.phone_coll_engaged else 0)
	if t >= next_print:
		next_print += 0.5
		var s = "T %.1f" % t
		for r in ps.roles:
			var tl = ps.tilt_deg(r)
			s += " | %s rate %.0f tilt %+.1f %+.1f" % [r, ps.roles[r]["rate"], tl.x, tl.y]
		s += " | ctl lon %+.2f lat %+.2f coll %.2f thr %.2f eng %s/%s" % [ctl.cyclic_lon, ctl.cyclic_lat, ctl.collective, ctl.throttle, ctl.phone_cyc_engaged, ctl.phone_coll_engaged]
		print(s)
	if t > dur:
		ps.stop()
		quit()
	return false
