# AB206 REALSIM flight model (milestone 2)

Plain-language summary first, details after. Everything here is a **model**: it reproduces the
physics that make a helicopter behave the way it does, using real Bell 206B-3 numbers where they
are published and labelled estimates where they are not (see `DATA_SOURCES.md`).

## Why our own model and not JSBSim (yet)

The feasibility report chose JSBSim (inside Godot through a C++ GDExtension) with our own
AB206 rotor module, and named a fallback: *"if JSBSim's rotor proves too limiting during the first
technical spike, a fully custom rotor model can replace it without touching the game."*
For this first playable build we went straight to that fallback, for three reasons:

1. JSBSim's FGRotor has no ground-effect, vortex-ring or dynamic-inflow model of the kind we need, so
   the report already planned to write those ourselves. With the rotor, engine, governor and skids all
   project-owned, JSBSim would only have provided the rigid-body integrator.
2. A native C++ plug-in has to be compiled for Windows and tested on Windows. That could not be done
   from the development machine, and an untested native DLL is the most likely thing to stop the sim
   from starting on your laptop.
3. The model below runs in about 25 microseconds per step (240 steps per second), far inside the
   1 ms budget, so performance is not a reason to go native.

The flight model sits behind one object (`scripts/fdm/heli_fdm.gd`) with a small interface
(controls in, state out). Swapping in JSBSim later stays possible.

## What is modelled

| Phenomenon | How | What you should see |
|---|---|---|
| Rotor thrust | Blade-element thrust with uniform momentum inflow, solved every step (Heffley & Mnich, NASA CR-177476) | Collective changes thrust; thrust falls with rotor rpm squared |
| Induced flow and power | Momentum theory, induced power factor 1.15, profile power with advance-ratio term | Torque needed in the hover, power bucket around 40-60 kt |
| Translational lift (ETL) | Falls out of the inflow solution: forward speed lowers induced velocity | Less torque from ~15 kt; at fixed controls the aircraft climbs |
| Flapback and transverse flow | Steady flapping terms vs advance ratio | Nose-up and slight right roll when accelerating through ETL |
| Ground effect | Hayden power ratio applied to induced velocity, fading with airspeed | ~15-20% less torque at 1 m skid height than at 20 m |
| Teetering rotor | No hub moment; control moment only from thrust-vector tilt x hub height | Control authority drops at low thrust (low-G); mast-bumping warning at large flapping |
| Flapping dynamics | First-order tip-path-plane lag (tau = 16 / (Lock no. x Omega)); disc tends to stay in space | Natural pitch/roll damping and the slight lag in cyclic response |
| Blade stall | Thrust coefficient over solidity saturates at 0.135, extra profile drag | Pulling collective at low rpm stops giving lift |
| Tail rotor | Same thrust/inflow model, geared to the main rotor | Pedal authority, weathervaning, loss of authority if Nr decays |
| Torque reaction | Engine drive torque reacts on the fuselage | Raise collective = nose yaws right unless you add left pedal; throttle chop = nose yaws left |
| Engine 250-C20J | Gas producer N1 with acceleration limit, free power turbine N2 with a torque-speed line | N1 lags collective inputs by about a second |
| Governor | N2 governor (PI + collective anticipator) active with throttle fully open | Nr held at 100% in normal flight |
| Freewheel (sprag) clutch | Engine and rotor separate when the rotor would drive the engine | Needle split in autorotation: N2 ~70%, Nr 90-107% |
| Rotor rpm | Torque balance on the rotor inertia (800 kg m2, estimated) | Nr decays in about 2 s if you chop the throttle and keep the collective up |
| Fuselage, stabilizer, fin | Drag areas, rotor-wash download, stabilizer in rotor wash at low speed | Pitch stability in cruise, tail pitch-up effects in transition |
| Skids | Spring-damper per skid point, stick/slide friction, tail-stinger contact | Settles on the pad without bouncing or creeping; hard landings rated |
| Vortex ring state | Inside the VRS envelope (descent 0.25-2 x hover induced velocity vh, in-plane speed below ~1 vh) the momentum inflow is replaced by the empirical induced-velocity curve of Young (1978) as given in Leishman, *Principles of Helicopter Aerodynamics*; plus thrust (+/-10%) and roll/pitch fluctuations (amplitude estimated) | Sink rate builds much faster in a vertical descent, the aircraft shakes, more collective costs power without arresting the sink quickly; forward or sideways speed clears it |
| Atmosphere | ISA with temperature offset, log wind profile near the ground, Dryden-like turbulence | Density altitude changes power required |

## Not yet modelled (planned for M2)

- Vortex ring state limits: the empirical curve gives the extra induced flow, power and the much
  weaker heave damping, but not the strongly unstable "more collective = faster sink" region some
  flight tests show; the envelope edges and fluctuation amplitudes are estimates (test [8]).
- Dynamic inflow, rotor cross-coupling of pitch and roll rates, retreating blade stall, mast bumping damage.
- Turbine outlet temperature (TOT), fuel burn, start-up and shutdown sequence, hydraulics.
- Building and tree side collisions (roofs are landable, walls and trees are not solid).

## Validation (automated, `tests/run_tests.gd`)

Checks are qualitative trends with plausible ranges, because Bell flight-test data is not public.
Current results (1,200 kg unless stated, sea level ISA, no wind):

- Hover torque: 89.5% OGE and 73.5% at 1 m skid height at 1,451 kg; 60% / 51% at 1,000 kg.
- Power bucket: 72.6% hover, 41% at 40-60 kt, 64% at 100 kt, 88% at 120 kt.
- Steady autorotation: about 1,600 ft/min at 56 kt, Nr 99-101%, needles split (N2 70%).
- Throttle chop with collective held: Nr below 90% in 1.9 s.
- Landing at 0.26 m/s: no bounce, 2 cm slide, no yaw creep when parked.
- Vortex ring state: collective -0.12 below hover for 5 s gives 13.2 m/s sink with the VRS model vs 7.0 m/s without; none at 30 kt.

Compare these with your own flights and your instructor's numbers; tell us where it feels wrong.
