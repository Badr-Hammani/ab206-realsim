# Known issues and limitations (milestone 2.6)

1. **Not measured on the target laptop yet.** Frame rate on the Ryzen 5 PRO 4650U is unknown until you run it. Use F6 (telemetry shows FPS, 1% low, frame time) and F7 to switch presets, and note the result in TEST_LOG.md.
2. **Placeholder art.** Helicopter and cockpit are built from simple shapes. Instruments are a simplified 206B-3 layout, not a replica of your panel.
3. **Missing instruments:** TOT, fuel quantity, engine oil, transmission, ammeter, clock and caution panel lights other than ROTOR LOW RPM. They are left out because their systems are not simulated yet (no fake gauges).
4. **Vortex ring state** is modelled with an empirical inflow curve (see FLIGHT_MODEL.md); the envelope edges and buffet amplitude are estimates.
5. **Collisions:** terrain and building roofs only. Trees and building walls are not solid.
6. **Joystick axes** are read through Godot's joystick layer (SDL3 in Godot 4.6). Only axes 0-7 per device are listed.
7. **Graphics scaling:** the Mobile renderer uses bilinear upscaling (FSR 1 needs the heavier Forward+ renderer).
8. **Engine always running** at start; cold start/shutdown procedures come in milestone 3.
9. Many aerodynamic and mass values are estimates (see DATA_SOURCES.md). Handling is tuned to plausible trends, not to Bell flight-test data.
10. **Phone controller** was tested with a desktop test client and an emulated phone browser (Chromium, Pixel 7 profile), not yet with your real phone. Phone browsers need the https:// address (self-signed certificate warning once). iPhones do not vibrate from web pages. Windows Firewall must allow Godot on private networks.
11. **Phone tilt has no force feel** and no centring spring; it is a different feel from a real cyclic/collective. Moving the phone up/down without tilting cannot be measured (accelerometer drift), so the collective is a lever angle.
12. **Lesson tolerances**: the "A" grade uses FAA private-pilot ACS figures (FAA-S-ACS-15); pass boxes, sink-rate ratings, turn-rate limits and score weights are simulator choices, not school or Bell standards. Your school may differ (see docs/TRAINING.md).
13. **Instructor's hands** (part-task levels H1-H3) are a teaching aid, not a real 206 system. They cannot move a joystick or phone axis: after a hand-over, move that axis to match.
14. **Voice** uses the Windows text-to-speech voice installed on the PC; if none is installed the cues are text only. Not tested on your PC yet.
15. **Training levels were flown by a robot student in tests**, not by a human yet: the difficulty and the coaching wording need your feedback.
16. **Training assists** (H) are learning aids that do not exist on the 206B-3. Levels 2-3 work only in a low hover. With a joystick cyclic, switching assist 2/3 on or off moves the meaning of the stick (centre = hold vs centre = neutral cyclic), so expect a small correction.
17. The step from assist 2 to assist 1 is the biggest one: at 1 you must find the hover stick position yourself. Use the green ghost ring and training speed 75 % for that step.
18. **Outside sight gates** (B) are a training aid placed in the world; the sight picture is exact only from the cockpit view with the view centred (C). The blue gate reacts mostly to forward/back but also a little to left/right, so line up the orange gate first. Gate geometry is a simulator choice.
19. **G and T keys** were listed in the help since M2.5 but did nothing until M2.7 (fixed: G = circle on/off, T = take all controls).
20. **Assist choice** (M2.8): by default the assist stays where you set it; the old automatic fading is now an option in the menu. If you saved settings with M2.6/M2.7, the automatic mode is switched off once by this update.
21. **H0 instructor loop** (M2.9): the instructor's take-over limits (3 m, height 0.4-2.3 m, 30 deg, 15 deg attitude, 2.5 m/s) and the 30 s goal are simulator choices. With a joystick or phone, after "I have control" your stick stays where you left it: match the aircraft again before the next "you have control" (the keyboard/mouse controls follow the instructor automatically).
22. **Khouribga map** (M2.14): houses and trees are placed from land-cover data, not real buildings; most building heights are guesses; the runway length follows OpenStreetMap (2,402 m) while OpenAIP says 2,800 m. Building walls are not solid (only roofs), like the rest of the sim. The main training pad there is a sim placement, not a real pad. See docs/MAPS.md.
