# Flight-model test log

Run 2026-11-06 in the development container (Godot 4.6.3, Linux, headless). **Re-run on your PC with Run_Flight_Model_Tests.bat and add the result below.** Frame-rate tests must be done on the ThinkPad itself (see README, Performance).

```

AB206 REALSIM flight-model tests  2026-11-06T17:31:50

[1] Hover power vs weight and ground effect (sea level, ISA, no wind)
    1000 kg, skid  1.0 m: torque  51.0%  collective 0.39  N1  82.1%  pitch  -0.0  roll  -1.3  pedal -0.19  GE 0.791  (residual 0.00000)
    1000 kg, skid 20.0 m: torque  60.0%  collective 0.44  N1  84.5%  pitch   0.0  roll  -1.5  pedal -0.24  GE 1.000  (residual 0.00000)
    1451 kg, skid  1.0 m: torque  73.5%  collective 0.53  N1  87.8%  pitch   0.0  roll  -1.3  pedal -0.32  GE 0.791  (residual 0.00009)
    1451 kg, skid 20.0 m: torque  89.5%  collective 0.60  N1  91.5%  pitch  -0.0  roll  -1.6  pedal -0.40  GE 1.000  (residual 0.00000)
  PASS  trim converges  (residuals 0.00000 / 0.00000)
  PASS  heavy needs more torque than light (OGE)  (89.5% vs 60.0%)
  PASS  heavy needs more collective than light  (0.60 vs 0.44)
  PASS  ground effect: 1 m needs less torque than 20 m (max weight)  (73.5% vs 89.5%)
  PASS  ground effect: 1 m needs less torque than 20 m (light)  (51.0% vs 60.0%)
  PASS  max-weight OGE hover torque plausible (70-100%)  (89.5%)
  PASS  hover attitude plausible (nose up 0-8 deg, left roll for tail rotor drift)  (pitch -0.0 roll -1.6)
  PASS  hover needs left pedal  (pedal -0.40)

[2] Level-flight power required (1200 kg, 300 m AGL) - translational lift
      0 kt: torque  72.6%  collective 0.52  cyclic lon -0.14  pitch   0.0  N1  88.1  (res 0.00000)
     10 kt: torque  65.0%  collective 0.48  cyclic lon -0.10  pitch   0.2  N1  86.2  (res 0.00004)
     20 kt: torque  53.5%  collective 0.43  cyclic lon -0.00  pitch   1.0  N1  83.2  (res 0.00000)
     30 kt: torque  45.4%  collective 0.39  cyclic lon  0.10  pitch   1.7  N1  81.0  (res 0.00002)
     40 kt: torque  41.2%  collective 0.36  cyclic lon  0.12  pitch   1.3  N1  79.8  (res 0.00000)
     60 kt: torque  41.1%  collective 0.36  cyclic lon  0.13  pitch  -0.6  N1  79.7  (res 0.00000)
     80 kt: torque  49.0%  collective 0.39  cyclic lon  0.24  pitch  -1.6  N1  82.0  (res 0.00000)
    100 kt: torque  64.4%  collective 0.45  cyclic lon  0.44  pitch  -2.0  N1  86.1  (res 0.00010)
    120 kt: torque  88.1%  collective 0.55  cyclic lon  0.69  pitch  -2.3  N1  91.8  (res 0.00002)
  PASS  power bucket: 40-80 kt needs much less torque than hover  (min 41.1% vs hover 72.6%)
  PASS  translational lift: 20 kt needs less torque than hover  (53.5% vs 72.6%)
  PASS  cruise 100 kt within max continuous (85%)  (64.4%)
  PASS  power rises again at high speed  (88.1%)
  PASS  accelerating from hover gives a nose-up pitching moment  (M_pitch 538 N m at 15 kt with hover controls)
  PASS  and a rolling moment to the right (transverse flow)  (M_roll 49 N m)

[3] Closed-loop hover hold 60 s at 5 m (numerical stability)
  PASS  values stay finite  ()
  PASS  hover held (drift < 3 m)  (drift 0.00 m)
  PASS  governor holds Nr within 1.5%  (max deviation 0.00%)
  PASS  FDM step cost small  (27 us per 1/240 s step)

[4] Torque reaction: collective up without pedal yaws nose right
  PASS  nose yaws right when collective raised with fixed pedals  (yaw rate 28.2 deg/s, turned 25.7 deg)
  PASS  left pedal stops / reverses the yaw  (yaw rate now -53.0 deg/s)

[5] Autorotation (1200 kg, 80 kt, 800 m AGL)
  PASS  Nr decays below 90% within 3 s if collective is not lowered  (reached 90% at 1.90 s (Nr now 79%))
    steady auto: Nr 99.1-100.6%, descent 8.0 m/s (1576 ft/min), IAS 56 kt, collective 0.11
  PASS  steady autorotation holds Nr inside power-off limits 90-107%  (99.1-100.6%)
  PASS  steady descent rate plausible (1,200-2,600 ft/min)  (8.0 m/s)
  PASS  engine and rotor needles split in autorotation (freewheel)  (N2 70%, Nr 100%)
  PASS  descent rate is steady (spread < 2.5 m/s)  (7.0..8.8 m/s)
  PASS  power recovery: Nr back to 100% with engine engaged  (Nr 100.2%, N2 100.2%, torque 55%)

[6] Landing and ground contact
  PASS  gentle touchdown detected  (sink 0.26 m/s)
  PASS  rating says normal  (SMOOTH)
  PASS  settles without bouncing (stays on skids)  (max skid height after settling 0.000 m)
  PASS  does not slide (< 0.3 m)  (0.02 m)
  PASS  at rest with collective down  (speed 0.000 m/s)
  PASS  parked with collective down: no yaw creep from tail rotor thrust  (heading change -0.00 deg in 10 s)
  PASS  drop from 3 m with collective down is rated HARD or worse  (sink 6.83 m/s -> DAMAGE)
  PASS  no numerical blow-up after hard landing  (CG height 1.12 m)

[7] Long run: 10 minutes hover in light turbulence
  PASS  10 min in wind and turbulence stays finite and airborne  (skid height 9.9 m, Nr 99.9%)

RESULT: 35 passed, 0 failed
```

## Runs on the target PC (ThinkPad T14s, Ryzen 5 PRO 4650U)

| Date | Tests | Preset | Avg FPS cockpit | 1% low | Notes |
|---|---|---|---|---|---|
| | | | | | |

## 2026-11-09 Cockpit frame fix
- Windshield centre post and forward door posts were rotated the wrong way (leaning forward at the top), so they passed through the cabin close to the pilot's eyes and looked like thick bars. Rebuilt: centre post from glareshield up and aft to the roof header, door posts out at the cabin sides, dark matte paint.
- Tab 2D panel in cockpit view now hides the 3D panel face, so only one panel shows.
- Checked with --autoshot screenshots (pad_cockpit, hover_cockpit with Tab on). Web pack re-exported and republished.


## 2026-11-09 milestone 2 (phone controller, VRS, lessons)

Flight-model suite in the development container (Godot 4.6.3 Linux headless):

```
AB206 REALSIM flight-model tests  2026-11-09T09:57:29
[1] Hover power vs weight and ground effect (sea level, ISA, no wind)
    1000 kg, skid  1.0 m: torque  51.0%  collective 0.39  N1  82.1%  pitch  -0.0  roll  -1.3  pedal -0.19  GE 0.791  (residual 0.00000)
    1000 kg, skid 20.0 m: torque  60.0%  collective 0.44  N1  84.5%  pitch   0.0  roll  -1.5  pedal -0.24  GE 1.000  (residual 0.00000)
    1451 kg, skid  1.0 m: torque  73.5%  collective 0.53  N1  87.8%  pitch   0.0  roll  -1.3  pedal -0.32  GE 0.791  (residual 0.00009)
    1451 kg, skid 20.0 m: torque  89.5%  collective 0.60  N1  91.5%  pitch  -0.0  roll  -1.6  pedal -0.40  GE 1.000  (residual 0.00000)
  PASS  trim converges  (residuals 0.00000 / 0.00000)
  PASS  heavy needs more torque than light (OGE)  (89.5% vs 60.0%)
  PASS  heavy needs more collective than light  (0.60 vs 0.44)
  PASS  ground effect: 1 m needs less torque than 20 m (max weight)  (73.5% vs 89.5%)
  PASS  ground effect: 1 m needs less torque than 20 m (light)  (51.0% vs 60.0%)
  PASS  max-weight OGE hover torque plausible (70-100%)  (89.5%)
  PASS  hover attitude plausible (nose up 0-8 deg, left roll for tail rotor drift)  (pitch -0.0 roll -1.6)
  PASS  hover needs left pedal  (pedal -0.40)
[2] Level-flight power required (1200 kg, 300 m AGL) - translational lift
      0 kt: torque  72.6%  collective 0.52  cyclic lon -0.14  pitch   0.0  N1  88.1  (res 0.00000)
     10 kt: torque  65.0%  collective 0.48  cyclic lon -0.10  pitch   0.2  N1  86.2  (res 0.00004)
     20 kt: torque  53.5%  collective 0.43  cyclic lon -0.00  pitch   1.0  N1  83.2  (res 0.00000)
     30 kt: torque  45.4%  collective 0.39  cyclic lon  0.10  pitch   1.7  N1  81.0  (res 0.00002)
     40 kt: torque  41.2%  collective 0.36  cyclic lon  0.12  pitch   1.3  N1  79.8  (res 0.00000)
     60 kt: torque  41.1%  collective 0.36  cyclic lon  0.13  pitch  -0.6  N1  79.7  (res 0.00000)
     80 kt: torque  49.0%  collective 0.39  cyclic lon  0.24  pitch  -1.6  N1  82.0  (res 0.00000)
    100 kt: torque  64.4%  collective 0.45  cyclic lon  0.44  pitch  -2.0  N1  86.1  (res 0.00010)
    120 kt: torque  88.1%  collective 0.55  cyclic lon  0.69  pitch  -2.3  N1  91.8  (res 0.00002)
  PASS  power bucket: 40-80 kt needs much less torque than hover  (min 41.1% vs hover 72.6%)
  PASS  translational lift: 20 kt needs less torque than hover  (53.5% vs 72.6%)
  PASS  cruise 100 kt within max continuous (85%)  (64.4%)
  PASS  power rises again at high speed  (88.1%)
  PASS  accelerating from hover gives a nose-up pitching moment  (M_pitch 538 N m at 15 kt with hover controls)
  PASS  and a rolling moment to the right (transverse flow)  (M_roll 49 N m)
[3] Closed-loop hover hold 60 s at 5 m (numerical stability)
  PASS  values stay finite  ()
  PASS  hover held (drift < 3 m)  (drift 0.00 m)
  PASS  governor holds Nr within 1.5%  (max deviation 0.00%)
  PASS  FDM step cost small  (24 us per 1/240 s step)
[4] Torque reaction: collective up without pedal yaws nose right
  PASS  nose yaws right when collective raised with fixed pedals  (yaw rate 28.2 deg/s, turned 25.7 deg)
  PASS  left pedal stops / reverses the yaw  (yaw rate now -53.0 deg/s)
[5] Autorotation (1200 kg, 80 kt, 800 m AGL)
  PASS  Nr decays below 90% within 3 s if collective is not lowered  (reached 90% at 1.90 s (Nr now 79%))
    steady auto: Nr 99.1-100.6%, descent 8.0 m/s (1576 ft/min), IAS 56 kt, collective 0.11
  PASS  steady autorotation holds Nr inside power-off limits 90-107%  (99.1-100.6%)
  PASS  steady descent rate plausible (1,200-2,600 ft/min)  (8.0 m/s)
  PASS  engine and rotor needles split in autorotation (freewheel)  (N2 70%, Nr 100%)
  PASS  descent rate is steady (spread < 2.5 m/s)  (7.0..8.8 m/s)
  PASS  power recovery: Nr back to 100% with engine engaged  (Nr 100.2%, N2 100.2%, torque 55%)
[6] Landing and ground contact
  PASS  gentle touchdown detected  (sink 0.26 m/s)
  PASS  rating says normal  (SMOOTH)
  PASS  settles without bouncing (stays on skids)  (max skid height after settling 0.000 m)
  PASS  does not slide (< 0.3 m)  (0.02 m)
  PASS  at rest with collective down  (speed 0.000 m/s)
  PASS  parked with collective down: no yaw creep from tail rotor thrust  (heading change -0.00 deg in 10 s)
  PASS  drop from 3 m with collective down is rated HARD or worse  (sink 7.78 m/s -> DAMAGE)
  PASS  no numerical blow-up after hard landing  (CG height 1.12 m)
[7] Long run: 10 minutes hover in light turbulence
  PASS  10 min in wind and turbulence stays finite and airborne  (skid height 9.9 m, Nr 99.9%)
[8] Vortex ring state (1200 kg, 500 m AGL, no wind)
  PASS  VRS detected in a 6 m/s vertical descent  (intensity 1.00)
  PASS  no VRS in the same descent at 20 m/s (39 kt) forward  (intensity 0.00)
    collective -0.12 for 5 s then back to hover collective:
      without VRS model: sink 7.0 m/s after 5 s, arrested after 4.7 s
      with VRS model:    sink 13.2 m/s after 5 s, worst 13.3 m/s, arrested after 5.1 s
      at 30 kt:          sink 5.7 m/s, VRS max 0.00
  PASS  in VRS the sink rate builds much faster (low heave damping)  (13.2 vs 7.0 m/s)
  PASS  in VRS the aircraft loses more height before the descent is arrested  (worst sink 13.3 vs 7.0 m/s)
  PASS  forward speed keeps the rotor out of VRS  (max 0.00)
  PASS  values stay finite in VRS  ()
RESULT: 41 passed, 0 failed

```

Phone controller: HTTPS + WebSocket on 8206 with a generated self-signed certificate and HTTP POST on 8207 tested with a Python client (cyclic over WSS, collective over HTTP, 60 Hz), and the phone page tested in Chromium with a Pixel 7 profile and synthetic orientation events: isSecureContext true after accepting the certificate, WebSocket link, collective 20 deg raise -> 0.51 (expected (20-2)/35 = 0.51), soft take-over, hold-on-disconnect after 1 s. QR code decoded with OpenCV. Not yet tried on a real phone.

## 2026-11-11 milestone 2.5 (training levels, live coach, instructor's hands)

Development container, Godot 4.6.3 Linux headless.

- Flight-model suite (`Run_Flight_Model_Tests.bat`): **41 passed, 0 failed** (flight model unchanged).
- Training-level suite (`Run_Training_Tests.bat`, new): **54 passed, 0 failed**, about 5.5 min.
  Robot student (good flying) scores:

| Level | Score | Level | Score |
|---|---|---|---|
| H1 Collective | 99 | L1 Vertical take-off | 92 |
| H2 Pedals | 97 | L2 Vertical landing | 100 |
| H3 Cyclic | 85 | L3 Hover-taxi + land | 90 |
| H4 Full hover | 100 | L4 Normal approach | 85 |
| H5 Hovering turns | 91 | Sloppy student, H4 | 22 (coach: over-controlling, drift, overshoot) |
| H6 Gusty crosswind | 100 | | |

  Hand-overs between instructor and student: largest control jump 0.000. Lesson weather restored afterwards.
- Finding: lifting off with the cyclic centred makes the aircraft drift about 2 m in the first 5 s
  (the simulated hover cyclic is about 13% aft and 5% left of centre). Pre-positioning the cyclic
  brought it to 1.0 m - so L1 now tells you to ease the cyclic slightly aft and left as the skids get light.
- Screenshots checked under Xvfb/llvmpipe (hover guide, lesson panel, Training levels menu).
- **Not yet tested by a human, with the Windows TTS voice, or for FPS on the ThinkPad.**

## 2026-11-12 milestone 2.6 (learning aids for the hover)

Development container, Godot 4.6.3 Linux headless. Flight-model suite **41/41**, training suite **68/68**.

New checks with a simulated **beginner** (reacts 0.5 s late, steers only by position and drift, no feel
for attitude - roughly the "the helicopter does what it wants" experience):

| Beginner on H4 full hover | Result |
|---|---|
| no assist | not completed in 120 s (cannot stay 40 s in the box) |
| assist 3 hover hold | 100 |
| assist 2 attitude hold | 83 |
| assist 1 damping | not completed in 150 s - the beginner model has no attitude feel; a person learns it at assist 2 |

Assist 3, hands off for 40 s in 10 kt gusty wind: max drift 0.65 m. Half stick = 1.4 m/s; centred, it stops
within 8 s. Assist 2: a 2 m/s drift dies to 0.46 m/s in 12 s with the stick centred (no assist: still 2.3 m/s).
Switching assists off in a hover: no cyclic jump. A robot that only copies the green ghost markers (no assist)
scores 85-94 on H4. Assist step-down after 80+, separate assisted scores, assist level given back after a lesson.

## 2026-11-13 milestone 2.7 (outside hover references)

Development container, Godot 4.6.3 Linux headless. Flight-model suite **41/41**, training suite **84/84**
(16 new checks in [L6]). Gates checked from the pilot's eye position in the sim:

| Aircraft position vs spot | Front gate (board offset, 1 = pole) | Side gate | Bars |
|---|---|---|---|
| on the spot, 1 m | 0.01 | 0.01, bar on board line 0.02 deg | green / green |
| 1 m right | 0.71 (inside) | - | green |
| 2 m left | 1.43 (outside) | - | amber |
| 2 m forward | - | 1.59 (outside) | green / amber |
| 0.7 m high | board line 2.1 deg above the bar | - | amber |
| 5 m off | - | - | red |

Gates hide outside lessons, more than 25 m from the spot, during hover-taxi/approach, and with B.
Screenshots (cockpit, chase, 2 m left + 0.6 m high) checked by eye. Not yet flown by a human.

## 2026-11-13 milestone 2.8 (you choose the assist level)

New [L7] checks: a lesson keeps your assist (2 stays 2 where the lesson would pick 3; OFF stays OFF);
H in flight changes it and it stays after the lesson; the optional automatic mode still picks the
lesson's level and gives yours back. Menu screenshot checked by eye. Training suite **90/90**, flight model **41/41**.

## 2026-11-13 milestone 2.9 (H0 instructor hover: "I have control / you have control")

Training suite **101/101**, flight model **41/41**. New [L8] checks: H0 starts with the instructor on all
controls; a good robot student gets the hand-over after the instructor steadies it and finishes with no
take-over (score 100; also cyclic/collective/pedals-only variants); a beginner model (late, no attitude feel,
no assist) is taken over and handed back again 5 times in 150 s, every hand-over within 0.35 m of the spot,
largest control jump at a hand-over/take-over 0.003; cyclic-only keeps the instructor on collective and pedals;
the same beginner with assist 3 finishes on the first attempt (93). Not yet flown by a human.

## 2026-11-13 milestone 2.10 (menu redesign)

Pause menu rebuilt (scripts/ui/menu.gd): frosted-glass panel over a blurred view of the sim, tabs
Fly / Lessons / Weather / Settings, grouped cards, segmented controls, iOS-style switches and sliders.
Same settings and actions as before. Screenshots of all four tabs checked by eye (1600x900). Training suite 101/101, flight model 41/41.
