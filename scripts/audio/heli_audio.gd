extends Node
## Procedurally synthesised sound (no audio files needed):
##  - turbine whine follows N1 (gas producer),
##  - main rotor blade passage (2 blades x Nr) with loudness from rotor thrust,
##  - transmission whine follows Nr,
##  - airflow noise follows airspeed,
##  - ROTOR LOW RPM horn, touchdown thump.
## Loops are generated once at start-up, then pitch/volume follow the simulation.

const RATE := 22050

var turbine: AudioStreamPlayer
var rotor: AudioStreamPlayer
var gearbox: AudioStreamPlayer
var air: AudioStreamPlayer
var horn: AudioStreamPlayer
var thump: AudioStreamPlayer
var master_volume := 0.8
var _rng := RandomNumberGenerator.new()

func _make_stream(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = samples.size()
	return st

func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	return p

func _ready() -> void:
	_rng.seed = 7
	# turbine: tonal compressor whine + combustion roar; 1.0 s loop with whole cycles
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.08
		s[i] = 0.22 * sin(TAU * 1180.0 * t) + 0.10 * sin(TAU * 2360.0 * t) + 0.05 * sin(TAU * 3540.0 * t) + 0.35 * lp
	turbine = _player(_make_stream(s, true))
	# rotor: 13 blade passes in the loop at 100% Nr (2 blades x 394 rpm = 13.13 Hz)
	var bpf := 2.0 * 394.0 / 60.0
	var n_r := int(round(13.0 / bpf * RATE))
	var r := PackedFloat32Array()
	r.resize(n_r)
	var period := float(n_r) / 13.0
	var lp2 := 0.0
	for i in n_r:
		var ph := fmod(float(i), period) / RATE
		lp2 += (_rng.randf_range(-1, 1) - lp2) * 0.15
		var env := exp(-ph * 38.0)
		r[i] = env * (0.75 * sin(TAU * 62.0 * ph) + 0.45 * lp2) + 0.05 * lp2
	rotor = _player(_make_stream(r, true))
	# transmission whine
	var g := PackedFloat32Array()
	g.resize(n)
	for i in n:
		var t := float(i) / RATE
		g[i] = 0.3 * sin(TAU * 1450.0 * t) + 0.12 * sin(TAU * 2900.0 * t) * sin(TAU * 7.0 * t)
	gearbox = _player(_make_stream(g, true))
	# air noise (low-passed)
	var a := PackedFloat32Array()
	a.resize(n)
	var l3 := 0.0
	var l4 := 0.0
	for i in n:
		l3 += (_rng.randf_range(-1, 1) - l3) * 0.05
		l4 += (l3 - l4) * 0.2
		a[i] = l4 * 2.5
	air = _player(_make_stream(a, true))
	# low rpm horn: steady tone (the real horn is continuous below the limit)
	var hn := int(RATE * 0.5)
	var h := PackedFloat32Array()
	h.resize(hn)
	for i in hn:
		var t := float(i) / RATE
		h[i] = 0.35 * signf(sin(TAU * 600.0 * t)) * 0.6 + 0.2 * sin(TAU * 1200.0 * t)
	horn = _player(_make_stream(h, true))
	# touchdown thump (one shot)
	var tn := int(RATE * 0.35)
	var th := PackedFloat32Array()
	th.resize(tn)
	var l5 := 0.0
	for i in tn:
		var t := float(i) / RATE
		l5 += (_rng.randf_range(-1, 1) - l5) * 0.1
		th[i] = exp(-t * 14.0) * (0.8 * sin(TAU * 48.0 * t) + 0.5 * l5)
	thump = _player(_make_stream(th, false))
	for p in [turbine, rotor, gearbox, air, horn]:
		p.play()

static func _db(lin: float) -> float:
	return linear_to_db(maxf(lin, 0.0001))

var horn_on := true                # set by main from the systems (bus powered, collective not full down)

func update(fdm, cockpit: bool, paused: bool) -> void:
	if paused:
		for p in [turbine, rotor, gearbox, air, horn]:
			p.volume_db = -80.0
		return
	var n1f: float = fdm.n1 / 100.0
	var nrf: float = fdm.nr / fdm.omega100
	turbine.pitch_scale = clampf(0.35 + 0.65 * n1f, 0.05, 2.0)
	turbine.volume_db = _db(master_volume * (0.35 if cockpit else 0.22) * clampf((n1f - 0.1) * 1.4, 0.0, 1.0))
	rotor.pitch_scale = clampf(nrf, 0.05, 2.0)
	var load := clampf(fdm.ct_sigma / 0.08, 0.3, 1.8)
	var slap := 1.0 + clampf(-fdm.vel.y / 6.0, 0.0, 1.0) * clampf(fdm.mu * 6.0, 0.0, 1.0) * 0.8   # blade slap in descents
	rotor.volume_db = _db(master_volume * (0.55 if cockpit else 0.9) * nrf * nrf * load * slap)
	gearbox.pitch_scale = clampf(nrf, 0.05, 2.0)
	gearbox.volume_db = _db(master_volume * (0.12 if cockpit else 0.05) * nrf)
	var spd: float = fdm.air_body.length()
	air.volume_db = _db(master_volume * clampf(spd / 60.0, 0.0, 1.0) * (0.25 if cockpit else 0.5))
	horn.volume_db = _db(master_volume * 0.3) if horn_on else -80.0

func play_touchdown(sink: float) -> void:
	if sink > 0.25:
		thump.volume_db = _db(master_volume * clampf(sink / 2.0, 0.2, 1.5))
		thump.play()
