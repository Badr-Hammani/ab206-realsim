# Checklists, cold-and-dark start and engine systems (M2.30)

**Esc > Fly > Cold and dark** (or **Shift+F2**) puts the 206 on the pad with everything off. **J** opens
the cockpit panel: switches on the left, the flight-manual checklist on the right. The sim keeps running.

| Key | What |
|---|---|
| J | cockpit switches + checklists (mouse free while open) |
| I (hold) | starter |
| R / F | throttle open / close. Hold **F at the idle stop** for half a second = IDLE REL → CLOSED. **R** from CLOSED = to the idle stop (fuel on: light-off) |
| [ / ] | governor RPM beep (97-100%) |
| Enter | current checklist item checked (or skip an automatic one) |

**AUTO** items tick themselves only when the cockpit really is in that state (switch, N1, TOT, rotor,
the light-off, the starter release, 60 s at idle...). Items you can only see or do outside the sim
(seat belts, altimeter, rotors clear, tie-downs) you confirm with Enter.

Lists: preflight, prestart, starting, hydraulics + run-up, before take-off, shutdown (Bell
BHT-206B3-FM-1), 20 emergency lists (AB206 manual E-AB206-250-1 Section 3 + Bell fire on start),
limitations, and the website quick cards.

Lessons (Esc > Lessons > Engine start and shutdown): **S1** engine start + run-up from cold and dark,
**S2** engine shutdown. Scored on light-off N1, TOT at light-off, peak TOT / hot start, rotor turning by
25% N1, starter release at 58%, 1 minute at idle, run-up torque, skipped items, starter limits.

What is real and what is estimated: see DATA_SOURCES.md ("Engine start, systems and checklists").
Overhead console (O): the circuit breakers the manual names (FUEL BOOST AFT/FWD, CAUTION LT, FUEL VALVE,
IGN ENG, HYD BOOST, PA SYST) plus GEN FIELD from the AB206 manual and typical 206 breakers. Pulling one
does what it would in the aircraft (no light-off without IGN ENG, no caution lights without CAUTION LT,
hydraulics stay ON with HYD BOOST out, FUEL PUMP light with a boost breaker out...). Hover a breaker
to see its effect. The console arrangement is a simulation layout (the manual has no drawing of it).
Checklist items that now tick themselves from the breakers: prestart "Circuit breakers - In",
"FUEL BOOST AFT and FWD - in", fire during start "IGN ENG - Out", hydraulic failure "HYD BOOST - Out",
electrical "GEN FIELD - check IN".

Not simulated yet: radios (switch only), pitot heat, ELT, external power, battery temperature.
Oil temperatures and the ammeter are simple estimates.
