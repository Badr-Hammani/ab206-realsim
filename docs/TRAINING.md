# Training levels, live coaching and the instructor (milestone 2.6)

Open them with **Esc > Training levels**. Each level is graded 0-100 from what the flight model
actually did (nothing completes on a timer alone), shows a debrief with the measured numbers and
the three things to work on, and keeps your best score (shown next to the level in the menu).

> Educational simulation, not an approved training device. Your instructor's technique and your
> school's standards come first. Tell me where they differ and the levels will be changed.

## How hover is taught here: part-task, on "dual controls"

Real instructors teach the hover one control at a time while they fly the others. The simulator
does the same with the **instructor's hands** (`scripts/core/hover_hold.gd`):

* During H1-H3 the instructor flies some controls and you fly one. The objective panel and the
  hover guide always say who has what ("YOU: collective / instructor: pedals, cyclic").
* Your controls are linked to the instructor's, like real dual controls: the mouse stick, the
  collective and the pedal trim move with the instructor's inputs, so a hand-over never jumps.
  (A joystick axis cannot be moved by the simulator: after a hand-over move it to match.
  A phone takes its axis back at once from the instructor's last position.)
* After a part-task level the instructor keeps the aircraft hovering ("I have control").
  Press **T** to take all controls.
* The instructor's hands are a teaching aid; the real 206B-3 has no autopilot or hover hold.

## H0 Instructor hover: "I have control" / "you have control" (milestone 2.9)

This is how the hover is really taught on the first flights:

1. **"I have control."** The instructor flies, brings the helicopter over the spot (1 m, heading 360) and
   steadies it (within 0.4 m, 0.15 m of height and 4 deg for 2.5 s). Look outside: that picture is what you keep.
2. **"You have control."** You get the controls exactly where the instructor had them (linked dual
   controls - nothing jumps). Hold the same references and height.
3. If it gets away from you - more than **3 m** from the spot, below 0.4 m or above 2.3 m, the nose more than
   30 deg off, more than 15 deg of pitch or roll, or faster than 2.5 m/s over the ground - **"I have control"**:
   the instructor takes it back, says why and how long you held it, returns to the spot and steadies it again.
4. Repeat until you hold it **30 s** without a take-over. The debrief counts attempts and take-overs.

Esc > H0 > choose what you fly: **All controls**, **Cyclic only**, **Collective only** or **Pedals only**
(the instructor keeps the rest). Your training assist (H) works as usual; with the instructor flying, the
assist does nothing. The take-over limits are simulator choices, not a school standard.

## The levels

| Level | You fly | What is checked |
|---|---|---|
| H1 Collective | collective | Hold 1 m, climb to 2 m, back to 1 m, then a soft touchdown |
| H2 Pedals | pedals | Hold 360, pivot left to 270, right back to 360; turn rate |
| H3 Cyclic | cyclic | Stay over the spot, sidestep 5 m right and back |
| H4 Full hover | all | 1 m, over the spot, heading 360, 40 s, light wind |
| H5 Hovering turns | all | 360 left and 360 right over the pivot point, stop on 360 |
| H6 Crosswind | all | As H4 with 12 kt from the right and gusts, 30 s |
| L1 Vertical take-off | all | From the pad: no drift, no aft movement, heading, smooth lift, no ballooning |
| L2 Vertical landing | all | Onto the spot: sink rate, position, ground speed, heading, collective fully down, no re-lift |
| L3 Hover-taxi | all | 22 m along the yellow line at walking pace, stop over the yellow spot, land on it |
| L4 Normal approach | all | From 500 ft / 60 kt: ~10 deg approach, progressive slow-down, no VRS, terminate in a hover |

E1-E3 (pad to Field LZ, vortex ring state, autorotation) are the M2 exercises, unchanged.

Each lesson sets its own wind (light headwind, or the H6 crosswind) so scores are comparable;
your own weather settings come back when the lesson stops.

## If the hover is too hard: learning aids (milestone 2.6)

A hovering helicopter is unstable: if nothing corrects it, a small drift grows, and every input
arrives a moment late. That is why everyone finds the cyclic hard at first. The simulator now has
"training wheels" that you take off one at a time. **None of them exist on the real 206.**

| Training assist (H) | What the cyclic does | What it teaches |
|---|---|---|
| **3 Hover hold** | Sets your speed over the ground (full stick about 6 kt). Centre it: the helicopter stops and holds the spot, even in gusts | Where you want to go, the picture outside, collective and pedals |
| **2 Attitude hold** | Sets the attitude (full stick 12 deg). Centre it: it levels itself and a drift slowly dies | "Attitude = drift": tilt a little, wait, level again |
| **1 Damping** | The real stick, but the wobbles are damped and it is pulled gently back to level in the hover | Finding the hover stick position yourself |
| **Off** | The real thing | |

* **You choose the assist (milestone 2.8, default).** Esc > top of the Training levels list: OFF / 1 / 2 / 3,
  or **H** at any time in flight. It stays where you set it, in every lesson and after it. The current level is
  shown in the bottom status bar. With a score of 80+ the debrief suggests trying one level less.
* **Optional: Automatic assist** (checkbox under the picker). The lessons then choose the assist and fade it
  out: H3, H4 and the hover-taxi start at 3, H5, H6, L1-L3 at 2, L4 at 1. Score **80 or more** and the next try
  uses one level less, until you fly it with none. After the lesson your own level comes back.
  Assisted scores are kept separately; "best" in the menu is your score with no assist.
  You can change the assist at any time with **H** or in the menu, or untick the automatic fading.
* Levels 2 and 3 only act in a low hover (below 30 m and 15 kt). Above that they act as damping, and
  the stick takes over from the assist without a jump.
* **Ghost stick (green rings)** on the control display, bottom right: where the instructor would put
  the controls you fly right now (cyclic ring, collective mark, pedal ring). Move your control
  onto the ring - "follow me through" the way instructors teach. In the tests, a robot that only
  copies the green rings, with no assist, flies H4 for a score of 85-94.
* **Training speed (Y): 100 / 75 / 50 %.** Slow motion gives you more time to see the movement
  and react. The physics are the same, just slower.
* **Arrow keys** now move the cyclic only 12% (hold Shift for the old 35%): one tap of 35% was far
  more than a hover needs. With the mouse, lower "Mouse cyclic sensitivity" in the menu (try 0.5).

Suggested path: H1 and H2 first (the instructor has the cyclic), then H3 with assist 3, then
H4 until the assist is gone, with training speed at 75% if needed, then back to 100%.

## Where the tolerances come from

**Verified (FAA, Private Pilot Rotorcraft-Helicopter ACS, FAA-S-ACS-15, November 2023):**

* Vertical take-off and landing (PH.IV.A): hover height +/- half of that height (below 10 ft),
  position within 4 ft (1.2 m) of the point with no aft movement, descend to within 4 ft of the
  touchdown point, heading +/-10 deg.
* Hover taxi (PH.IV.B): ground track within +/-4 ft, 360 deg pivot turns left and right within
  4 ft of the pivot point, stopping within 10 deg of the heading.
* Normal approach (PH.V.B): arrive at the termination point, on the surface or in a stabilised
  hover, +/-4 ft.

These are FAA private-pilot check-ride standards, used as the "A" grade reference. They are not
Bell figures, and your school (and EASA/national rules) may use different ones.

**Guidance (published, not a standard):** normal approach angle about 10 deg (steep approaches are
about 15 deg, FAA Helicopter Flying Handbook); closure at about a jogging pace at the end; hover
taxi no faster than a brisk walk.

**Simulator choices (estimates, tell me if your school differs):** training hover height 1 m
(about 3 ft); the 3 m "pass" box; touchdown ratings (below 0.3 m/s = full marks); turn-rate limits
(30 deg/s in H2, 45 deg/s in H5); the closure-speed guide in L4 (distance / 12 m per kt, minimum
5 kt); the VRS danger zone used for scoring (sink above 500 ft/min below 20 kt); all score weights.

## Live coaching (auto teaching)

`scripts/core/coach.gd` watches the aircraft and **your own control inputs** every frame and gives
one short correction at a time, in words relative to the aircraft ("Drifting back and left -
gentle forward-right cyclic, then centre it"). The first time a fault appears it explains *why*
(drift and disc tilt, collective and torque, pedals and torque reaction, over-controlling,
anticipation, coupling of collective and pedals, touchdown technique, dynamic rollover). After that
it gives only the short cue, with cool-downs so it does not nag. It detects:

* height high/low against the lesson target (or a climb/sink in a free-flight hover);
* heading off target or a yaw swing; collective raised without left pedal (torque yaw);
* drift away from the spot, coming back too fast (overshoot coming), sitting off the spot;
* over-controlling: pitch/roll rate reversals together with a busy cyclic (pilot-induced oscillation);
* landing: sinking too fast in the last metre, moving over the ground before touchdown,
  collective not lowered after touchdown;
* approach (L4): above/below the 10 deg angle, closing too fast/slow, vortex-ring danger zone,
  loss of translational lift;
* and it says so when the hover is genuinely stable for 10 s.

The coach works in free flight as well (low hover and touchdown). Switch it off in the menu.

**Voice:** short cues are spoken with the Windows text-to-speech voice (menu: Instructor voice).
Long explanations stay on screen.

## Outside references: sight gates (B) - milestone 2.7

To learn to hover by looking OUT (not at the circle), every hover and landing level puts two sight
gates in the world, built around the pilot's eye (right seat) at the correct hover over the spot:

| Gate | Where | What it tells you |
|---|---|---|
| ORANGE gate + white board with orange stripe | straight ahead, poles 14 m, board 50 m | **left/right**: board stripe between the poles. **Height**: the bar lies on the board's black line. Bar BELOW the line = too high, ABOVE = too low |
| BLUE gate + white board with blue stripe | 35 deg front-right, poles 9 m, board 35 m | **forward/back**: board between the poles (fix left/right first, the blue gate sees a little of both) |

Each gate's bar is **green** inside the ACS 4 ft box (and, for the orange bar, the height band),
**amber** up to the 3 m pass box, **red** beyond. "Board inside the gate" is about 1.3-1.4 m off the
spot. This is how hover is taught for real (a reference ahead, one to the side); the gates make the
picture exact. They hide during hover-taxi and the approach and when you are more than 25 m away.
**B** switches them off, **G** switches the HUD circle off - try H4 with the circle off.
Sight picture is exact only in the cockpit view (V). Simulator aid: estimated geometry, not a real installation.

## Hover guide (G)

Bottom left: a top-down view in the aircraft's frame (nose up). Green ring = 1.2 m (ACS 4 ft), amber
ring = 3 m pass box around the target spot; the blue arrow is your movement over the ground; the bar
on the right is skid height with the target band; the dot on the top arc is heading error.
It is a training aid only - real pilots hover by looking outside, so use it to learn what you are
seeing outside and switch it off (G) once H4 is easy - the outside gates (B) give the same information out of the window.

## Tests

`Run_Training_Tests.bat` (`tests/lesson_tests.gd`) loads the real simulator, flies every H and L
level with a robot student through the normal control path and checks that each one completes and
scores well, that hand-overs are bumpless, that **T** gives the controls back, that a deliberately
sloppy student scores much lower and gets drift and over-controlling cues, and that lesson weather
is restored. Your own scores are not touched (the test uses a separate progress file).
