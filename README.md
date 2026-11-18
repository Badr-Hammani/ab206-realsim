# AB206 REALSIM - Bell 206B-3 helicopter simulator (Milestone 2.12: training)

A personal learning simulator for the Bell 206B-3 JetRanger III (Allison/Rolls-Royce 250-C20J),
built with Godot 4.6 and a project-owned helicopter flight model.

> Educational simulation only. Not an approved training device. Always follow your instructor
> and the approved Rotorcraft Flight Manual (RFM). Values marked *estimated* are not Bell data.

## Play in your browser

**https://badr-hammani.github.io/ab206-realsim/**

No install needed. Click inside the window once so it receives the keyboard and mouse.
The browser version runs on the *Low* graphics preset; the Windows version below looks and runs better.
On a phone or tablet, on-screen touch controls appear when you touch the screen.
The phone tilt controller (F10) and joystick setup only work in the Windows version.

## Run it on Windows (full version)

1. Double-click **`Run_AB206.bat`**.
   The first time, it downloads the free Godot 4.6.3 engine (~70 MB) into the `engine` folder.
   If the download is blocked, get *Godot 4.6.3 - Windows 64-bit (standard, not .NET)* from
   https://godotengine.org/download/archive/ and unzip both `.exe` files into `engine\`.
2. You start on the main helipad, engine running, rotor at 100%, collective fully down.
3. Press **F1** at any time for the control list.

## Controls (keyboard + mouse)

| Control | Keys | Notes |
|---|---|---|
| Cyclic | **Mouse** (arrow keys nudge) | Mouse stick stays where you leave it. **X** centres it. **M** turns mouse cyclic off |
| Collective | **W / S** or **mouse wheel** | Holds its position like a friction-held lever. Shift = faster |
| Pedals | **A / D** | Spring back to the pedal trim. **Q / E** move the pedal trim |
| Throttle (twist grip) | **R / F** | Full open = governor holds 100% N2. Rolling to idle = engine-failure practice |
| Look around | hold **Right mouse** | **C** recentres the view |
| Camera | **V** | Cockpit, chase, free (I J K L U O to move) |
| Pause / menu | **P** / **Esc** | Glass menu with 4 tabs: **Fly** (resets, assist, training speed, weight), **Lessons** (all levels with best scores), **Weather**, **Settings** (training displays, instructor, controls, joystick, phone, graphics, sound, quit) |
| Resets | **F2** pad, **F3** hover 5 m, **F4** cruise 80 kt, **F5** autorotation practice | All resets are trimmed by the flight model |
| Phone controller | **F10**, **N** | Up to three phones: cyclic, collective and pedals (feet). N = set phone neutral |
| Training levels | **Esc > Training levels** | H1-H6 hover (part-task, then full), L1-L4 take-off and landing, E1-E3 other. Scores, debrief, best score. See `docs/TRAINING.md` |
| Take control | **T** | After a part-task level, take all controls back from the instructor |
| Hover guide circle | **G** | Training-aid display: drift, spot, height band, heading (on/off) |
| Outside sight gates | **B** | Orange gate ahead (left/right + height), blue gate front-right (forward/back); bars go green inside 4 ft. See docs/TRAINING.md |
| Take all controls | **T** | In a lesson: the instructor gives you every control |
| Telemetry | **F6** | Every number comes from the simulation, plus FPS / 1% low / FDM cost |
| Graphics preset | **F7** | Low / Medium / High |
| Joystick setup | **F8** | Assign axes by moving them, invert, dead zone, range calibration |
| Instructor | **F9** | Plain-language explanations + live coaching from your own inputs; short cues are spoken (menu) |
| 2D panel | **Tab** | Instrument panel overlay in cockpit view |
| Training assist | **H** | Off / 1 damping / 2 attitude hold / 3 hover hold - learning aids; you choose the level (Esc menu picker or H) and it stays. Optional automatic fading. The real 206 has no stability augmentation |
| Training speed | **Y** | 100 / 75 / 50 % (slow motion while learning) |
| Screenshot | **F12** | Saved in the user data folder |

## Your first hover (simulation exercise)

1. On the pad, raise the collective slowly with **W** (or the wheel). Watch the **torque** gauge rise.
2. As torque builds, the nose wants to yaw **right** (rotor torque reaction). Hold **left pedal** (A),
   or set it with **Q** so you do not have to hold the key.
3. When the skids get light (around 50-60% torque at 1,200 kg), keep raising gently to lift into a
   1 m hover. A 206 hovers slightly left-skid-low; that is normal.
4. Keep corrections tiny. The mouse cyclic is sensitive; lower the sensitivity in the menu if needed.
5. Climb to 10-15 m and watch the torque increase: you are leaving **ground effect**.
6. Push the cyclic forward a little and accelerate: around 15-25 kt you feel **translational lift**
   (the aircraft wants to climb and pitch nose-up). Then fly a circuit and land back on the pad.

**Autorotation practice: F5.** The throttle is rolled to idle at about 2,500 ft above the valley.
Lower the collective immediately, hold 55-65 kt, keep rotor rpm 90-107% with the collective, and
either roll the throttle back on (**R**) for a power recovery or continue to a landing.

## Phone as cyclic / collective / pedals (new in M2, pedals in M2.12)

Your phone becomes a motion controller over your home Wi-Fi. Nothing to install on the phone.

1. In the simulator press **F10**, then **START phone server**. The first time, Windows asks whether
   Godot may use the network: allow **private networks**.
2. On the phone (same Wi-Fi as the PC) scan the QR code, or type the `https://...:8206` address shown.
   The phone warns about the certificate: tap *Advanced > Proceed* (Android) or *Show details > visit
   this website* (iPhone). It is the simulator's own certificate, created on your PC.
3. Choose **Cyclic**, **Collective** or **Pedals**, hold the phone in its neutral position and tap **Start**
   (iPhone asks for motion access: allow).
   - **Cyclic** (right hand): tilt the top edge away = forward cyclic, tilt left/right = lateral cyclic.
     About 20 degrees of tilt = full deflection. The stick stays where you hold it.
   - **Collective** (left hand): screen up, top edge forward like the end of the lever; Start with the lever
     fully *down*; raise the top edge to pull collective (about 35 degrees = full up). The real lever pivots,
     so an angle is the natural movement. Optional twist grip throttle in F10.
4. The phone takes over at once from the control's current position (its screen says **IN CONTROL**),
   so connecting, a reset or an instructor hand-over never jerks the controls; any difference
   between phone angle and control melts away as you move the phone. **N** re-centres (cyclic centre / collective down / pedals centred).
   If a phone drops out, the control stays where it was and the phone reconnects by itself (M2.12).
5. Use two phones for both hands, or one phone for the collective and the mouse for the cyclic.
   A third phone can work the pedals with your feet (otherwise A/D, Q/E trim):
   - **Turn** mode: phone flat, screen up, on a pedal bar that turns on a turntable (see the DIY pedals
     guide). Right foot forward = right pedal. Uses the phone's gyro heading, which can drift slowly
     (estimate, depends on the phone): press **N** with your feet level if the centre moves.
   - **Rock** mode: phone flat on a board that tilts left/right; right side down = right pedal. No drift.
   Choose the mode, range, dead zone and invert in F10. Android phones vibrate on the low-rotor-RPM warning and on firm landings.

If the https address does not give motion data, try the `http://...:8207` address shown in F10.
Ranges, dead zone, expo, smoothing and inversion are in F10 and are saved.

## What is in this milestone

- Flight model (240 Hz): rotor thrust and inflow, flapping, flapback, ground effect, translational lift,
  blade stall, teetering-rotor control power, tail rotor, torque reaction, free-turbine engine with
  governor and freewheel, rotor rpm dynamics, autorotation, skid contact. See `docs/FLIGHT_MODEL.md`.
- Instruments driven by the simulation: torque, dual tach (Nr and N2), airspeed, attitude, altimeter,
  vertical speed (with realistic lag), heading, gas producer N1, ROTOR LOW RPM light and horn.
- 4 x 4 km fictional alpine valley: main helipad with hangar, field LZ, pinnacle LZ on the ridge,
  windsocks that show the real simulated wind, trees, village, church tower landmark.
- Cockpit, chase and free cameras. Moving cyclic, collective, twist grip and pedals in the cockpit.
- Synthesised sound: turbine (N1), rotor blade passage (Nr and thrust, blade slap in descents),
  transmission, wind, low-rpm horn, touchdown.
- Touchdown rating (smooth / normal / firm / hard / damage) and tail-strike detection.
- Headless flight-model tests: **`Run_Flight_Model_Tests.bat`** (41 checks, all passing at release).
- M2: phone motion controller (F10), vortex ring state in the flight model, graded lessons (Esc > Lessons).
- M2.5: training levels for stationary hover and landing taught part-task with the instructor's hands
  on dual controls, live coaching from your own inputs, spoken cues, hover guide, scores and debriefs,
  hover-taxi line and spot on the main pad. Tests: **`Run_Training_Tests.bat`**. See `docs/TRAINING.md`.
- M2.6: learning aids for the hover: training assists 3 hover hold / 2 attitude hold / 1 damping that the
  lessons fade out as you score 80+, green "ghost stick" showing where the instructor would put the
  controls, training speed (Y), gentler arrow-key cyclic.

## Aircraft data

Every number the simulator uses is in `data/bell206b3.json` with its source and confidence level;
`docs/DATA_SOURCES.md` lists them. Verified values come from EASA TCDS EASA.IM.R.512 Issue 4
(rotor diameters, 394 rpm = 100% Nr, Nr limits 95-100% power on and 90-107% power off,
317 shp take-off / 270 shp continuous, 1,451 kg maximum weight). Most aerodynamic and mass values
are estimates. To match your "code G" aircraft, edit the JSON (for example rpm, limits, weights)
and restart.

## Performance on the ThinkPad T14s

Target from the report: 60 fps average, 1% low above 45 fps, Medium preset, cockpit view.
The renderer is Godot's Mobile renderer (lighter than Forward+). Presets:

| Preset | Internal resolution | Shadows | Trees | View distance |
|---|---|---|---|---|
| Low | 50% | off | 1,500 | 7 km |
| Medium | 67% (about 720p on a 1080p screen) | 2 splits, 150 m | 4,500 | 10 km |
| High | 100% + MSAA 2x | 4 splits, 500 m | 9,000 | 12 km |

Please run on mains power, press F6, fly for a few minutes in cockpit view and note the FPS and
1% low in `docs/TEST_LOG.md`. This has **not been measured on your laptop yet**.

## Project layout

```
data/bell206b3.json        aircraft data with sources
scripts/fdm/               flight model, atmosphere, trim solver
scripts/world/             terrain, helipads, trees, buildings
scripts/aircraft/          3D model and cockpit
scripts/input/             keyboard, mouse, joystick
scripts/ui/                instruments, HUD, menu, joystick setup
scripts/audio/             synthesised sound
tests/run_tests.gd         flight-model test suite
tests/lesson_tests.gd      training-level tests (robot student flies every level)
scripts/core/              lessons, live coach, instructor's hands, instructor messages
docs/                      flight model, data register, test log, known issues
```

## Next milestones

M2 (done: phone controller, vortex ring state, first lessons; still to do: dynamic inflow, cross-coupling,
comparison with your instructor's numbers) -> M3 cockpit and systems (TOT, fuel, start-up/shutdown, caution panel) -> M4 lessons and
missions -> M5 world, weather, replay -> M6 dedicated hardware.
