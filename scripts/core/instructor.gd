extends RefCounted
## Optional instructor mode: explains, in plain language, what the simulation is
## doing right now. Messages are triggered by the flight-model state, never by timers.
## Educational simulation only - always follow your instructor and the approved RFM.

var enabled := true
var voice := true                # spoken cues through the operating system's text-to-speech
var message := ""
var message_time := 0.0
var last_key := ""
var _cool := {}
var _prev := {}
var lang := "en"                 # voice language for spoken cues ("fr" in the French school briefings)
var _voices := {}

func say(key: String, text: String, cooldown := 25.0, duration := 9.0, speech := "") -> bool:
	if not enabled:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if _cool.has(key) and now - float(_cool[key]) < cooldown:
		return false
	_cool[key] = now
	message = text
	message_time = duration
	last_key = key
	if speech != "":
		speak(speech)
	return true

func force(text: String, speech := "") -> void:
	message = text
	message_time = 9.0
	last_key = ""
	if speech != "":
		speak(speech)

## Short spoken cue (Windows: SAPI voices via Godot's DisplayServer TTS). Silent when the
## OS has no voice or the voice is switched off in the menu.
func speak(text: String) -> void:
	if not voice or not enabled or DisplayServer.get_name() == "headless":
		return
	if not _voices.has(lang):
		var v := DisplayServer.tts_get_voices_for_language(lang)
		if v.size() == 0:
			v = DisplayServer.tts_get_voices_for_language("en")
		_voices[lang] = v[0] if v.size() > 0 else ""
	var vid: String = _voices[lang]
	if vid == "":
		return
	DisplayServer.tts_speak(text, vid, 70, 1.0, 1.1, 0, true)

func update(fdm, dt: float) -> void:
	message_time = maxf(message_time - dt, 0.0)
	if not enabled:
		return
	var agl: float = fdm.agl
	var gs: float = fdm.groundspeed_kt()
	var ias: float = fdm.ias_kt()
	var nr: float = fdm.nr_pct()
	var airborne: bool = not fdm.on_ground
	var in_ge: bool = airborne and fdm.ge_factor < 0.95 and agl < 8.0
	if in_ge and not _prev.get("in_ge", false) and gs < 10.0:
		say("ge", "GROUND EFFECT: close to the ground the rotor's downwash is blocked, induced flow drops and the rotor needs less power. Watch the torque: it rises as you climb out of ground effect (about one rotor diameter, ~10 m).")
	if airborne and _prev.has("ias") and float(_prev["ias"]) < 15.0 and ias >= 15.0 and agl < 60.0:
		say("etl", "TRANSLATIONAL LIFT: from about 15-25 kt the rotor flies into undisturbed air, induced flow falls and it gives more lift for the same power. Expect a climb or less torque, a nose-up pitch (flapback) and a slight right roll (transverse flow). Keep the nose down with forward cyclic.")
	if nr < 95.0 and fdm.throttle > 0.95 and airborne:
		say("lownr_pwr", "ROTOR RPM LOW with the engine at full throttle: you are asking for more power than available or the collective is too high. Lower the collective smoothly to recover rotor RPM.", 15.0)
	if fdm.throttle < 0.5 and airborne and agl > 20.0 and fdm.collective > 0.25 and nr < 97.0:
		say("auto_entry", "ENGINE AT IDLE: the rotor is slowing down. Lower the collective now to let the air drive the rotor (autorotation), then keep about 55-65 kt with cyclic and control rotor RPM (90-107%) with the collective.", 10.0)
	if fdm.throttle < 0.5 and airborne and not fdm.engaged and nr > 90.0 and agl > 50.0:
		say("auto_ok", "STEADY AUTOROTATION: the needles are split - the engine (N2) is at idle while the airflow drives the rotor (NR) through the freewheel unit. Raising collective slows the rotor, lowering it speeds it up.", 40.0)
	if nr > 107.0:
		say("over", "ROTOR OVERSPEED: rotor RPM is above the 107% power-off limit. Raise the collective a little to load the rotor.", 10.0)
	if fdm.torque_pct > 100.0:
		say("tq", "OVER-TORQUE: torque above the 100% (5-minute) limit. Reduce collective. Above 85% is the take-off range, limited to 5 minutes.", 15.0)
	if fdm.mast_bump:
		say("mast", "DANGER - LARGE ROTOR FLAPPING: the teetering rotor is near its flapping stop (mast bumping risk). Avoid abrupt cyclic, especially at low rotor thrust (low-G). Smoothly reduce cyclic deflection.", 10.0)
	if airborne and agl > 3.0 and fdm.vrs > 0.4:
		say("vrs", "VORTEX RING STATE: you are sinking into your own rotor downwash at low airspeed. The rotor recirculates its wake, so extra collective mostly costs power and the sink keeps building. RECOVER: forward (or lateral) cyclic to fly out of the downwash, then collective once you have airspeed.", 20.0)
	elif airborne and agl > 3.0 and ias < 15.0 and fdm.vel.y < -3.0 and fdm.torque_pct > 30.0:
		say("vrs_warn", "HIGH DESCENT RATE AT LOW AIRSPEED with power applied: this is how vortex ring state starts. Gain some forward airspeed or reduce the descent rate.", 25.0)
	_prev["in_ge"] = in_ge
	_prev["ias"] = ias
