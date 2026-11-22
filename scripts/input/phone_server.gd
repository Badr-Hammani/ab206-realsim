extends Node
## Phone motion controller (F10).
##
## The simulator runs a tiny web server on the PC. A phone on the same Wi-Fi opens
## https://<pc-address>:8206 and streams its orientation (the browser's sensor-fused
## gyroscope + accelerometer attitude) over a WebSocket. Nothing has to be installed
## on the phone.
##
## Roles (one phone each, so two phones give both hands a control):
##   "cyclic"     tilt the phone forward/back = cyclic fore/aft, tilt left/right = lateral cyclic
##   "collective" hold the phone like the collective lever: raise its front edge = collective up.
##                Optional: rotate it about its long axis = throttle twist grip.
##   "pedals"     anti-torque pedals with your feet. Two ways (F10):
##                Turn: phone lies on a pedal bar that turns on a turntable (lazy susan, see
##                      hardware/diy_pedals); the bar's rotation = pedal. Uses the browser's
##                      gyro-based heading (alpha) relative to "neutral" - it can drift slowly
##                      (estimated a few degrees per 10 min, phone dependent): press N to re-centre.
##                Rock: phone lies on a rocker board; tilting it left/right = pedal. Gravity-based,
##                      no drift.
##
## Only the direction of gravity in the phone's own frame is used (pitch and roll of the phone),
## never the compass heading, so there is no yaw drift. Moving the phone up and down without
## tilting it cannot be measured reliably (accelerometer double integration drifts in seconds),
## so the collective is a lever ANGLE, which is also how the real lever moves (it pivots).
##
## Two listening ports:
##   8206 HTTPS + WSS with a self-signed certificate generated on first use (needed because
##        phone browsers only give motion sensors to secure pages). The phone shows a
##        certificate warning once; accept it.
##   8207 plain HTTP fallback for browsers that allow sensors without HTTPS.

const HTTPS_PORT := 8206
const HTTP_PORT := 8207
## If 8206/8207 are taken (most often a second AB206 window that is still open, or one that did not
## close properly), the server moves to the next free pair and says so; the QR code and address
## follow the ports really in use.
const PORT_PAIRS := [[8206, 8207], [8216, 8217], [8226, 8227], [8236, 8237]]
var https_port := HTTPS_PORT
var http_port := HTTP_PORT
const CERT_PATH := "user://phone_tls.crt"
const KEY_PATH := "user://phone_tls.key"
const PAGE_PATH := "res://phone/phone.html"
const CFG_PATH := "user://phone.cfg"
const WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const ROLE_TIMEOUT := 2.0           # s without data -> phone treated as disconnected (hotspot Wi-Fi can pause ~1 s)
const MAX_CONNS := 12

signal role_connected(role: String)
signal role_lost(role: String)
signal calibrated(role: String)

var running := false
var error_text := ""
var addresses: PackedStringArray = []

# ------------------------------------------------------------------ settings
var cyc_range_deg := 20.0        # phone tilt for full cyclic deflection
var cyc_deadzone_deg := 1.0
var cyc_expo := 0.25             # 0 = linear, 1 = very soft centre
var cyc_invert_lon := false
var cyc_invert_lat := false
var coll_range_deg := 35.0       # lever angle from full down to full up
var coll_deadband_deg := 2.0     # first degrees above "down" still read full down
var coll_invert := false
var twist_throttle := false      # collective phone also works the twist grip
var twist_range_deg := 35.0
var twist_invert := false
var ped_mode := 0                # 0 = turn (turntable, heading), 1 = rock (left/right tilt)
var ped_range_deg := 20.0        # bar rotation / rocker tilt for full pedal
var ped_deadzone_deg := 1.0
var ped_invert := false
var smoothing_ms := 0.0          # extra low-pass (ms); 0 = none, the phone already fuses its sensors

# ------------------------------------------------------------------- state
var roles := {}                   # role -> Dictionary (see _role_state)
var lost_at := {}                 # role -> time it was lost (for "reconnecting..." in the F10 panel)
var drops := {}                   # role -> number of times it dropped this session
var _srv_tls: TCPServer
var _srv_plain: TCPServer
var _tls_opts: TLSOptions
var _conns: Array = []
var _page := PackedByteArray()
var _status_timer := 0.0
var role_status := {}             # role -> "engaged(0/1),text" sent to that phone, set by controls/main

class Conn:
	var tcp: StreamPeerTCP
	var tls: StreamPeerTLS
	var secure := false
	var buf := PackedByteArray()
	var ws := false
	var role := ""
	var born := 0.0
	var dead := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()

# ------------------------------------------------------------------ start/stop
func start() -> bool:
	if running:
		return true
	if OS.has_feature("web"):
		error_text = "Not available in the browser version (a web page cannot open a server)."
		return false
	error_text = ""
	if FileAccess.file_exists(PAGE_PATH):
		_page = FileAccess.get_file_as_bytes(PAGE_PATH)
	else:
		_page = "<html><body>phone.html missing</body></html>".to_utf8_buffer()
	_tls_opts = _make_tls()
	var e1 := ERR_UNAVAILABLE
	var e2 := ERR_UNAVAILABLE
	var moved := false
	for pair in PORT_PAIRS:
		_srv_tls = TCPServer.new()
		_srv_plain = TCPServer.new()
		e1 = _srv_tls.listen(pair[0], "*") if _tls_opts != null else ERR_UNAVAILABLE
		e2 = _srv_plain.listen(pair[1], "*")
		if e2 == OK and (e1 == OK or _tls_opts == null):
			https_port = pair[0]
			http_port = pair[1]
			break
		# this pair is (partly) taken: free what we got and try the next pair
		_srv_tls.stop()
		_srv_plain.stop()
		e1 = ERR_UNAVAILABLE
		e2 = ERR_UNAVAILABLE
		moved = true
	if e1 != OK and e2 != OK:
		error_text = "Could not open the phone ports (8206-8237). Another AB206 window is probably still open: close it (taskbar, or Task Manager > Godot), then press Start phone server."
		return false
	if e1 != OK:
		error_text = "HTTPS port unavailable; only plain HTTP %d is running." % http_port
	elif moved:
		error_text = "Ports 8206/8207 are busy (another AB206 window still open?), so the phone server uses %d/%d. Use the new address / QR code below." % [https_port, http_port]
	var html := _page.get_string_from_utf8()
	if html.find("__HTTPS_PORT__") >= 0:
		_page = html.replace("__HTTPS_PORT__", str(https_port)).to_utf8_buffer()
	running = true
	addresses = local_addresses()
	return true

func stop() -> void:
	for c in _conns:
		_close(c)
	_conns.clear()
	if _srv_tls:
		_srv_tls.stop()
	if _srv_plain:
		_srv_plain.stop()
	running = false
	for r in roles.keys():
		role_lost.emit(r)
	roles.clear()
	lost_at.clear()

func _make_tls() -> TLSOptions:
	var crypto := Crypto.new()
	var key: CryptoKey
	var cert: X509Certificate
	if FileAccess.file_exists(CERT_PATH) and FileAccess.file_exists(KEY_PATH):
		key = CryptoKey.new()
		cert = X509Certificate.new()
		if key.load(KEY_PATH) != OK or cert.load(CERT_PATH) != OK:
			key = null
	if key == null:
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=AB206 REALSIM phone controller,O=AB206 REALSIM,C=XX", "20250101000000", "20450101000000")
		key.save(KEY_PATH)
		cert.save(CERT_PATH)
	if key == null or cert == null:
		return null
	return TLSOptions.server(key, cert)

## IPv4 addresses a phone could use, best first. The QR code uses the first one.
## Virtual adapters (Hyper-V "vEthernet", WSL, VirtualBox, VMware, Docker...) exist only inside the PC,
## so they go last; Wi-Fi comes first, then wired Ethernet. (Sorting the plain address text put
## Hyper-V's 172.20.0.1 before an iPhone hotspot's 172.20.10.5 - the phone could not load the page.)
static func local_addresses() -> PackedStringArray:
	var scored := []
	var seen := {}
	for itf in IP.get_local_interfaces():
		var nm := (str(itf.get("friendly", "")) + " " + str(itf.get("name", ""))).to_lower()
		for a in itf.get("addresses", []):
			a = str(a)
			if seen.has(a) or not _usable(a):
				continue
			seen[a] = true
			scored.append([_score(a, nm), a])
	# fallback when the interface list is empty (some platforms)
	for a in IP.get_local_addresses():
		a = str(a)
		if not seen.has(a) and _usable(a):
			seen[a] = true
			scored.append([_score(a, ""), a])
	scored.sort_custom(func(x, y) -> bool: return x[0] > y[0] if x[0] != y[0] else str(x[1]) < str(y[1]))
	var out: PackedStringArray = []
	for e in scored:
		out.append(e[1])
	return out

static func _usable(a: String) -> bool:
	return not a.contains(":") and not a.begins_with("127.") and not a.begins_with("169.254.") and a.count(".") == 3

const _VIRTUAL := ["vethernet", "hyper-v", "wsl", "virtualbox", "vbox", "vmware", "vmnet", "docker", "loopback", "npcap", "bluetooth", "zerotier", "tailscale", "hamachi", "tap-", "tun", "wintun", "nordlynx", "openvpn", "default switch"]

static func _score(a: String, nm: String) -> int:
	var sc := 0
	if a.begins_with("192.168.") or a.begins_with("10.") or _is_172_private(a):
		sc += 10
	if a.begins_with("172.20.10.") or a.begins_with("192.168.43.") or a.begins_with("192.168.137."):
		sc += 5          # iPhone / Android hotspot / Windows hotspot ranges
	if nm.contains("wi-fi") or nm.contains("wifi") or nm.contains("wlan") or nm.contains("wireless"):
		sc += 40
	elif nm.contains("ethernet") and not nm.contains("vethernet"):
		sc += 20
	for v in _VIRTUAL:
		if nm.contains(v):
			sc -= 100
			break
	return sc

static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var p := a.split(".")
	return p.size() > 1 and int(p[1]) >= 16 and int(p[1]) <= 31

var addr_pick := 0      # which of `addresses` the QR code shows (F10 "Use another address")

func url(secure := true) -> String:
	var ip := addresses[clampi(addr_pick, 0, addresses.size() - 1)] if addresses.size() > 0 else "<this-pc-ip>"
	return ("https://%s:%d" % [ip, https_port]) if secure else ("http://%s:%d" % [ip, http_port])

# ------------------------------------------------------------------- polling
func _process(dt: float) -> void:
	if not running:
		return
	poll()      # also polled from controls.update() every physics tick (lower latency)
	var now := _now()
	for r in roles.keys():
		if now - float(roles[r]["t"]) > ROLE_TIMEOUT:
			roles.erase(r)
			lost_at[r] = now
			drops[r] = int(drops.get(r, 0)) + 1
			role_lost.emit(r)
	_status_timer -= dt
	if _status_timer <= 0.0:
		_status_timer = 0.2
		for c in _conns:
			if c.ws and c.role != "":
				_ws_send(c, "s," + c.role + "," + str(role_status.get(c.role, "")))
				if c.role == "pedals":
					_ws_send(c, "m," + ("turn" if ped_mode == 0 else "rock"))

func poll() -> void:
	while _srv_tls and _srv_tls.is_listening() and _srv_tls.is_connection_available():
		var t := _srv_tls.take_connection()
		t.set_no_delay(true)
		var c := Conn.new()
		c.tcp = t
		c.secure = true
		c.tls = StreamPeerTLS.new()
		c.born = _now()
		if c.tls.accept_stream(t, _tls_opts) != OK:
			t.disconnect_from_host()
			continue
		_add_conn(c)
	while _srv_plain and _srv_plain.is_listening() and _srv_plain.is_connection_available():
		var c2 := Conn.new()
		c2.tcp = _srv_plain.take_connection()
		c2.tcp.set_no_delay(true)
		c2.born = _now()
		_add_conn(c2)
	for c in _conns:
		_service(c)
	var alive: Array = []
	for c in _conns:
		if not c.dead:
			alive.append(c)
	_conns = alive

func _add_conn(c: Conn) -> void:
	if _conns.size() >= MAX_CONNS:
		# drop the oldest non-WebSocket connection first
		for o in _conns:
			if not o.ws:
				_close(o)
				break
	_conns.append(c)

func _service(c: Conn) -> void:
	if c.dead:
		return
	var data := PackedByteArray()
	if c.secure:
		c.tls.poll()
		var st := c.tls.get_status()
		if st == StreamPeerTLS.STATUS_HANDSHAKING:
			if _now() - c.born > 10.0:
				_close(c)
			return
		if st != StreamPeerTLS.STATUS_CONNECTED:
			_close(c)
			return
		var n := c.tls.get_available_bytes()
		if n > 0:
			var r := c.tls.get_partial_data(n)
			if r[0] != OK:
				_close(c)
				return
			data = r[1]
	else:
		c.tcp.poll()
		if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_close(c)
			return
		var n2 := c.tcp.get_available_bytes()
		if n2 > 0:
			var r2 := c.tcp.get_partial_data(n2)
			if r2[0] != OK:
				_close(c)
				return
			data = r2[1]
	if data.size() > 0:
		c.buf.append_array(data)
		if c.buf.size() > 65536:
			_close(c)
			return
		if c.ws:
			_ws_parse(c)
		else:
			_http_parse(c)
	elif not c.ws and c.buf.is_empty() and _now() - c.born > 30.0:
		_close(c)     # idle keep-alive connection

func _close(c: Conn) -> void:
	if c.dead:
		return
	c.dead = true
	if c.secure and c.tls:
		c.tls.disconnect_from_stream()
	if c.tcp:
		c.tcp.disconnect_from_host()

func _send(c: Conn, bytes: PackedByteArray) -> void:
	if c.dead:
		return
	var err := c.tls.put_data(bytes) if c.secure else c.tcp.put_data(bytes)
	if err != OK:
		_close(c)

# ---------------------------------------------------------------------- HTTP
static func _find_header_end(b: PackedByteArray) -> int:
	for i in range(0, b.size() - 3):
		if b[i] == 13 and b[i + 1] == 10 and b[i + 2] == 13 and b[i + 3] == 10:
			return i
	return -1

func _http_parse(c: Conn) -> void:
	while not c.dead and not c.ws:
		var he := _find_header_end(c.buf)
		if he < 0:
			return
		var head := c.buf.slice(0, he).get_string_from_utf8()
		var lines := head.split("\r\n")
		var req := lines[0].split(" ")
		if req.size() < 2:
			_close(c)
			return
		var method := req[0]
		var path := req[1]
		var hdr := {}
		for i in range(1, lines.size()):
			var k := lines[i].find(":")
			if k > 0:
				hdr[lines[i].substr(0, k).strip_edges().to_lower()] = lines[i].substr(k + 1).strip_edges()
		var clen := int(hdr.get("content-length", "0"))
		if c.buf.size() < he + 4 + clen:
			return
		var body := c.buf.slice(he + 4, he + 4 + clen)
		c.buf = c.buf.slice(he + 4 + clen)
		if str(hdr.get("upgrade", "")).to_lower() == "websocket":
			_ws_accept(c, hdr)
			return
		if method == "GET" and (path == "/" or path.begins_with("/?") or path == "/index.html"):
			_respond(c, "200 OK", "text/html; charset=utf-8", _page)
		elif method == "POST" and path.begins_with("/m"):
			_post_active_t = _now()
			# fallback transport when WebSocket is refused: one or more lines per request
			var role := ""
			for line in body.get_string_from_utf8().split("\n", false):
				role = _handle_message(line, null)
			var reply := ("s," + role + "," + str(role_status.get(role, ""))) if role != "" else ""
			if role == "pedals":
				reply += "\nm," + ("turn" if ped_mode == 0 else "rock")
			for v in _pending_buzz:
				reply += "\n" + v
			_pending_buzz.clear()
			_respond(c, "200 OK", "text/plain", reply.to_utf8_buffer())
		else:
			_respond(c, "404 Not Found", "text/plain", "not found".to_utf8_buffer())

func _respond(c: Conn, code: String, ctype: String, body: PackedByteArray) -> void:
	var h := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: keep-alive\r\n\r\n" % [code, ctype, body.size()]
	var out := h.to_utf8_buffer()
	out.append_array(body)
	_send(c, out)

# ----------------------------------------------------------------- WebSocket
func _ws_accept(c: Conn, hdr: Dictionary) -> void:
	var key := str(hdr.get("sec-websocket-key", ""))
	if key == "":
		_close(c)
		return
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA1)
	hc.update((key + WS_GUID).to_utf8_buffer())
	var accept := Marshalls.raw_to_base64(hc.finish())
	var resp := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept
	_send(c, resp.to_utf8_buffer())
	c.ws = true
	if c.buf.size() > 0:
		_ws_parse(c)

func _ws_parse(c: Conn) -> void:
	while not c.dead and c.buf.size() >= 2:
		var b0 := c.buf[0]
		var b1 := c.buf[1]
		var opcode := b0 & 0x0F
		var masked := (b1 & 0x80) != 0
		var plen := b1 & 0x7F
		var off := 2
		if plen == 126:
			if c.buf.size() < 4:
				return
			plen = (c.buf[2] << 8) | c.buf[3]
			off = 4
		elif plen == 127:
			_close(c)       # 64-bit frames are never needed here
			return
		var mlen := 4 if masked else 0
		if c.buf.size() < off + mlen + plen:
			return
		var payload := c.buf.slice(off + mlen, off + mlen + plen)
		if masked:
			var mk := c.buf.slice(off, off + 4)
			for i in payload.size():
				payload[i] = payload[i] ^ mk[i % 4]
		c.buf = c.buf.slice(off + mlen + plen)
		match opcode:
			1, 2:
				for line in payload.get_string_from_utf8().split("\n", false):
					var r := _handle_message(line, c)
					if r != "":
						c.role = r
			8:
				_send(c, PackedByteArray([0x88, 0x00]))
				_close(c)
			9:
				var pong := PackedByteArray([0x8A, payload.size()])
				pong.append_array(payload)
				_send(c, pong)

func _ws_send(c: Conn, text: String) -> void:
	var p := text.to_utf8_buffer()
	var f := PackedByteArray([0x81])
	if p.size() < 126:
		f.append(p.size())
	else:
		f.append(126)
		f.append((p.size() >> 8) & 0xFF)
		f.append(p.size() & 0xFF)
	f.append_array(p)
	_send(c, f)

# ------------------------------------------------------------------ messages
## o,<role>,<beta>,<gamma>,<screen angle>   orientation sample (degrees, W3C DeviceOrientation)
## c,<role>                                 "set neutral here" from the phone
## h,<role>                                 hello / role selection
## Returns the role named in the message ("" if invalid).
func _handle_message(line: String, c) -> String:
	var f := line.strip_edges().split(",")
	if f.size() < 2:
		return ""
	var role := f[1]
	if role != "cyclic" and role != "collective" and role != "pedals":
		return ""
	match f[0]:
		"o":
			if f.size() < 5:
				return ""
			feed(role, float(f[2]), float(f[3]), float(f[4]), float(f[5]) if f.size() >= 6 and f[5] != "" else NAN)
		"c":
			if roles.has(role):
				calibrate(role)
		"h":
			pass
		"p":
			# latency probe: echo the phone's timestamp straight back
			if c != null and f.size() >= 3:
				_ws_send(c, "q," + f[2])
		_:
			return ""
	return role

func _role_state(role: String) -> Dictionary:
	if not roles.has(role):
		lost_at.erase(role)
		roles[role] = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "p0": 0.0, "r0": 0.0, "y0": 0.0, "has_yaw": false, "cal": false, "t": _now(),
			"n": 0, "rate": 0.0, "rate_t": _now(), "f_a": 0.0, "f_b": 0.0, "f_c": 1.0, "first": true}
		role_connected.emit(role)
	return roles[role]

## Converts one DeviceOrientation sample to the phone's pitch and roll relative to gravity,
## in the screen frame (so it works in portrait or landscape).
## W3C: device x right, y top of screen, z out of the screen; R = Rz(alpha) Rx(beta) Ry(gamma).
## Gravity direction in device axes = (sin g cos b, -sin b, -cos g cos b) (alpha drops out).
func feed(role: String, beta_deg: float, gamma_deg: float, screen_deg: float, alpha_deg := NAN) -> void:
	var s := _role_state(role)
	if not is_nan(alpha_deg):
		s["yaw"] = alpha_deg       # W3C alpha: + = counter-clockwise seen from above (phone flat, screen up)
		s["has_yaw"] = true
	var b := deg_to_rad(beta_deg)
	var g := deg_to_rad(gamma_deg)
	var d := Vector3(sin(g) * cos(b), -sin(b), -cos(g) * cos(b))
	var a := deg_to_rad(screen_deg)
	# screen right / up expressed in device axes
	var ds := Vector3(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a), d.z)
	s["pitch"] = rad_to_deg(atan2(ds.y, -ds.z))     # + = top edge tilted away / down
	s["roll"] = rad_to_deg(asin(clampf(ds.x, -1.0, 1.0)))   # + = right edge down
	var now_us := Time.get_ticks_usec()
	var now := now_us / 1000000.0
	var gap := (now_us - int(s.get("t_us", now_us))) / 1000.0
	s["t_us"] = now_us
	s["gap_max_run"] = maxf(float(s.get("gap_max_run", 0.0)), gap)
	s["t"] = now
	s["n"] = int(s["n"]) + 1
	if now - float(s["rate_t"]) >= 1.0:
		s["rate"] = float(s["n"]) / (now - float(s["rate_t"]))
		s["gap_max"] = s["gap_max_run"]     # longest pause between samples in the last second (Wi-Fi hiccups)
		s["gap_max_run"] = 0.0
		s["n"] = 0
		s["rate_t"] = now
	if not s["cal"]:
		calibrate(role)

## "Set neutral here": cyclic = centred, collective = lever fully down (throttle fully open), pedals = centred.
func calibrate(role: String) -> void:
	if not roles.has(role):
		return
	var s: Dictionary = roles[role]
	s["p0"] = s["pitch"]
	s["r0"] = s["roll"]
	s["y0"] = s["yaw"]
	s["cal"] = true
	s["first"] = true
	for c in _conns:
		if c.ws and c.role == role:
			_ws_send(c, "n")
	calibrated.emit(role)

func calibrate_all() -> void:
	for r in roles:
		calibrate(r)

func has_role(role: String) -> bool:
	return running and roles.has(role)

static func _wrap180(x: float) -> float:
	return fposmod(x + 180.0, 360.0) - 180.0

func _shape_centered(deg: float, range_deg: float, dz: float, expo: float) -> float:
	var m := absf(deg)
	if m <= dz:
		return 0.0
	var t := clampf((m - dz) / maxf(range_deg - dz, 1.0), 0.0, 1.0)
	t = (1.0 - expo) * t + expo * t * t * t
	return signf(deg) * t

## Raw (unsmoothed) tilt of a role relative to its neutral, degrees: Vector2(fwd, right).
func tilt_deg(role: String) -> Vector2:
	if not roles.has(role):
		return Vector2.ZERO
	var s: Dictionary = roles[role]
	return Vector2(_wrap180(float(s["pitch"]) - float(s["p0"])), _wrap180(float(s["roll"]) - float(s["r0"])))

## Pedal-phone rotation relative to neutral, degrees: + = right pedal (before invert).
func pedal_deg() -> float:
	if not roles.has("pedals"):
		return 0.0
	var s: Dictionary = roles["pedals"]
	if ped_mode == 0:
		# right pedal forward turns the bar counter-clockwise seen from above = alpha increases
		return _wrap180(float(s["yaw"]) - float(s["y0"]))
	return _wrap180(float(s["roll"]) - float(s["r0"]))      # right edge down = right pedal

## Normalised control outputs, low-pass filtered. Call once per physics tick.
## Returns {"lon","lat"} for cyclic, {"coll","thr"} for collective, {"ped"} for pedals.
func axes(role: String, dt: float) -> Dictionary:
	var s: Dictionary = roles[role]
	var t := tilt_deg(role)
	var a := 0.0
	var b := 0.0
	var c := 1.0
	if role == "pedals":
		a = _shape_centered(pedal_deg(), ped_range_deg, ped_deadzone_deg, 0.0) * (-1.0 if ped_invert else 1.0)
	elif role == "cyclic":
		a = _shape_centered(t.x, cyc_range_deg, cyc_deadzone_deg, cyc_expo) * (-1.0 if cyc_invert_lon else 1.0)
		b = _shape_centered(t.y, cyc_range_deg, cyc_deadzone_deg, cyc_expo) * (-1.0 if cyc_invert_lat else 1.0)
	else:
		var up := -t.x * (-1.0 if coll_invert else 1.0)     # front edge raised = up
		a = clampf((up - coll_deadband_deg) / maxf(coll_range_deg, 5.0), 0.0, 1.0)
		if twist_throttle:
			var tw := t.y * (-1.0 if twist_invert else 1.0)    # roll one way = close
			c = 1.0 - clampf((tw - 6.0) / maxf(twist_range_deg, 5.0), 0.0, 1.0)
	var k := 1.0 if s["first"] or smoothing_ms <= 0.0 else clampf(dt / (smoothing_ms / 1000.0), 0.0, 1.0)
	s["first"] = false
	s["f_a"] = lerpf(float(s["f_a"]), a, k)
	s["f_b"] = lerpf(float(s["f_b"]), b, k)
	s["f_c"] = lerpf(float(s["f_c"]), c, k)
	if role == "pedals":
		return {"ped": float(s["f_a"])}
	if role == "cyclic":
		return {"lon": float(s["f_a"]), "lat": float(s["f_b"])}
	return {"coll": float(s["f_a"]), "thr": float(s["f_c"])}

var _pending_buzz: Array = []
var _post_active_t := -100.0

## Vibrates the phones (Android; iPhones ignore it). Used for touchdown and the low-rotor warning.
func buzz(ms: int) -> void:
	for c in _conns:
		if c.ws and c.role != "":
			_ws_send(c, "v,%d" % ms)
	if _now() - _post_active_t < 2.0:
		_pending_buzz.append("v,%d" % ms)
		if _pending_buzz.size() > 4:
			_pending_buzz.pop_front()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# -------------------------------------------------------------------- config
const _KEYS := ["cyc_range_deg", "cyc_deadzone_deg", "cyc_expo", "cyc_invert_lon", "cyc_invert_lat",
	"coll_range_deg", "coll_deadband_deg", "coll_invert", "twist_throttle", "twist_range_deg", "twist_invert", "smoothing_ms",
	"ped_mode", "ped_range_deg", "ped_deadzone_deg", "ped_invert"]

var autostart := false

func save_config() -> void:
	var cf := ConfigFile.new()
	for k in _KEYS:
		cf.set_value("phone", k, get(k))
	cf.set_value("phone", "autostart", autostart)
	cf.set_value("phone", "cfg_version", 2)
	cf.save(CFG_PATH)

func load_config() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	for k in _KEYS:
		set(k, cf.get_value("phone", k, get(k)))
	autostart = cf.get_value("phone", "autostart", false)
	if int(cf.get_value("phone", "cfg_version", 1)) < 2:
		smoothing_ms = 0.0     # v1 default (35 ms) added noticeable lag

