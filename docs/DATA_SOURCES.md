# Aircraft data register - Bell 206B-3 (AB206 REALSIM)

Generated from `data/bell206b3.json` (the file the simulator actually loads). Edit the JSON, not this page.

Confidence levels:
- **verified**: from a primary certification document (EASA type-certificate data sheet).
- **derived**: calculated from verified values with a stated assumption.
- **secondary**: published by a non-authoritative source; check against your RFM.
- **estimated**: engineering estimate chosen for plausible behaviour. NOT real aircraft data.
- **tuning**: simulator-only parameter.

## Verified (11)

| Parameter | Value | Unit | Source / note |
|---|---|---|---|
| main_rotor_diameter_m | 10.16 | m | EASA TCDS EASA.IM.R.512 Issue 4 (Bell 206A/206B) |
| tail_rotor_diameter_m | 1.65 | m | EASA TCDS EASA.IM.R.512 Issue 4 (Bell 206A/206B) |
| rotor_rpm_100pct | 394.0 | rpm | EASA TCDS EASA.IM.R.512 Issue 4: 100% Nr = 394 rpm (to 3,000 lb); 395 rpm quoted for later sections |
| nr_power_off_min_pct | 90.0 | % | EASA TCDS EASA.IM.R.512 Issue 4: power-off 90-107% (355-422 rpm) |
| nr_power_off_max_pct | 107.0 | % | EASA TCDS EASA.IM.R.512 Issue 4 |
| nr_power_on_min_pct | 95.0 | % | EASA TCDS EASA.IM.R.512 Issue 4: power-on 95-100% to 3,000 lb (97-100% from 3,000 to 3,200 lb) |
| nr_power_on_max_pct | 100.0 | % | EASA TCDS EASA.IM.R.512 Issue 4 |
| takeoff_power_shp | 317.0 | shp | EASA TCDS EASA.IM.R.512 Issue 4: 317 shp take-off (5 min) transmission limit |
| max_continuous_power_shp | 270.0 | shp | EASA TCDS EASA.IM.R.512 Issue 4: 270 shp maximum continuous |
| max_gross_weight_kg | 1451.0 | kg | EASA TCDS EASA.IM.R.512 Issue 4 and CAA NZ AB206B report: 3,200 lb |
| blade_count | 2 |  | Two-bladed teetering (semi-rigid) main rotor, all 206 variants |

## Derived (1)

| Parameter | Value | Unit | Source / note |
|---|---|---|---|
| torque_100pct_definition | 317.0 | shp at 100% N2 | Assumption: 100% torque = 317 shp at 100% rpm, so 270 shp max continuous = 85% torque. Matches the commonly published 206B-3 torque marking (85% continuous / 100% 5-min) but check your gauge markings |

## Secondary (8)

| Parameter | Value | Unit | Source / note |
|---|---|---|---|
| engine_rated_power_shp | 420.0 | shp | 250-C20J/C20B take-off rating 420 shp (flugzeuginfo.net and engine literature). The airframe torque limit above governs |
| n1_max_pct | 105.0 | % | 250-C20J N1 limit 105% (secondary); check your RFM |
| low_rpm_warning_pct | 90.0 | % | 206B-3 ROTOR LOW RPM light/horn commonly quoted at 90% Nr; check your RFM |
| vne_kias | 130.0 | kt | 206B-3 Vne 130 KIAS sea level (secondary; varies with altitude/weight in the RFM) |
| tail_rotor_rpm_100pct | 2550.0 | rpm | Commonly quoted 206B tail rotor speed; gives tip speed ~220 m/s |
| empty_weight_kg | 775.0 | kg | Typical 206B-3 empty weight ~1,700 lb; individual aircraft vary |
| blade_chord_m | 0.33 | m | Bell 206 main blade chord ~13 in (secondary) |
| skid_half_track_m | 0.95 | m | Skid track ~1.9 m |

## Estimated (38)

| Parameter | Value | Unit | Source / note |
|---|---|---|---|
| n1_idle_pct | 62.0 | % | Typical 250-C20 ground idle range ~59-65% N1; check your RFM |
| blade_lift_slope_per_rad | 5.7 | 1/rad | Typical value for NACA 0012-class blade sections |
| blade_cd0 | 0.0085 |  | Typical blade profile drag; tuned with induced factor for plausible hover power |
| induced_power_factor | 1.15 |  | Typical kappa for a two-bladed rotor |
| lock_number | 5.0 |  | Typical for a light helicopter; sets flapping lag 16/(gamma*Omega) |
| rotor_polar_inertia_kgm2 | 800.0 | kg m2 | Blade mass data not public; estimated from ~40 kg blades plus tip weights. Sets autorotation rpm decay rate |
| collective_pitch_min_deg | 0.5 | deg at 75% R | Chosen so full-down collective autorotation holds Nr inside 90-107% |
| collective_pitch_max_deg | 14.0 | deg at 75% R | Gives hover at ~8 deg at max weight with margin |
| cyclic_long_range_deg | 14.0 | deg | Rotor disc tilt per full cyclic deflection fore/aft |
| cyclic_rig_aft_deg | 3.0 | deg | Swashplate rigging: centred cyclic tilts the disc aft relative to the forward-tilted mast, so hover needs near-centre cyclic |
| cyclic_rig_left_deg | 1.2 | deg | Lateral swashplate rigging offset so hover needs only slight left cyclic against tail-rotor drift |
| cyclic_lat_range_deg | 7.0 | deg | Rotor disc tilt per full lateral cyclic |
| mast_forward_tilt_deg | 5.0 | deg | Forward shaft tilt, typical for the type |
| hub_height_above_cg_m | 1.65 | m | Overall height to hub ~2.9 m minus estimated CG height |
| mast_bumping_flap_deg | 10.0 | deg | Teetering hub flap stop angle used for the mast-bumping warning |
| tail_rotor_arm_m | 6.0 | m | CG to tail rotor hub, from published overall dimensions |
| tail_rotor_height_m | 0.9 | m | Tail rotor hub height above CG |
| tail_rotor_chord_m | 0.12 | m | Tail rotor blade chord |
| tail_pitch_full_left_deg | 18.0 | deg | Full left pedal tail rotor pitch |
| tail_pitch_full_right_deg | -11.0 | deg | Full right pedal tail rotor pitch |
| inertia_xx_kgm2 | 1300.0 | kg m2 | Roll inertia at ~1,200 kg, scaled with weight |
| inertia_yy_kgm2 | 3600.0 | kg m2 | Pitch inertia |
| inertia_zz_kgm2 | 3000.0 | kg m2 | Yaw inertia |
| fuselage_drag_area_m2 | 0.85 | m2 | Equivalent flat-plate area (forward) |
| fuselage_side_area_m2 | 6.0 | m2 | Side drag area |
| fuselage_vertical_area_m2 | 4.0 | m2 | Vertical drag area incl. rotor-wash download |
| hstab_area_m2 | 0.9 | m2 | Horizontal stabilizer |
| hstab_arm_m | 4.6 | m | CG to horizontal stabilizer |
| hstab_incidence_deg | -2.0 | deg | Inverted-camber stab producing down-force in cruise |
| vfin_area_m2 | 0.9 | m2 | Vertical fin |
| vfin_arm_m | 5.8 | m | CG to vertical fin |
| vfin_incidence_deg | 1.0 | deg | Cambered fin unloads the tail rotor in cruise |
| drivetrain_loss_kw | 6.0 | kW | Transmission and accessory losses at 100% rpm |
| power_turbine_inertia_kgm2 | 20.0 | kg m2 (rotor-equivalent) | Engine free turbine + drive shafts referred to rotor speed |
| n1_accel_pct_per_s | 10.0 | %/s | Gas producer acceleration limit |
| cg_height_above_skids_m | 1.15 | m | CG height above skid bottoms |
| skid_front_m | 1.25 | m | Skid contact point forward of CG |
| skid_rear_m | 1.15 | m | Skid contact point aft of CG |

## Tuning (3)

| Parameter | Value | Unit | Source / note |
|---|---|---|---|
| default_gross_weight_kg | 1200.0 | kg | Simulator default: two occupants, part fuel |
| governor_kp | 220.0 | %N1 per unit Nr error | Simulation governor gain |
| governor_ki | 120.0 |  | Simulation governor integral gain |

Variant: Bell 206B-3 JetRanger III with Allison/Rolls-Royce 250-C20J. User reports their 'code G' aircraft differs only slightly; differences not yet known.

## Training standards (milestone 2.5)

| Item | Value | Source | Status |
|---|---|---|---|
| Hover height tolerance | +/- half of hover height (below 10 ft) | FAA-S-ACS-15 (Nov 2023) PH.IV.A.S5 / PH.IV.B.S7 | Verified (FAA private pilot standard, not Bell) |
| Position over point | within 4 ft (1.2 m), no aft movement | FAA-S-ACS-15 PH.IV.A.S6/S7 | Verified (FAA) |
| Heading | +/-10 deg | FAA-S-ACS-15 PH.IV.A.S8 | Verified (FAA) |
| Hovering turns | within 4 ft of pivot, stop within 10 deg | FAA-S-ACS-15 PH.IV.B.S10/S11 | Verified (FAA) |
| Hover-taxi track | +/-4 ft | FAA-S-ACS-15 PH.IV.B.S6 | Verified (FAA) |
| Approach termination | +/-4 ft, on the surface or stabilised hover | FAA-S-ACS-15 PH.V.B.S9 | Verified (FAA) |
| Normal approach angle | about 10 deg (steep about 15 deg) | FAA Helicopter Flying Handbook; copters.com | Guidance |
| Training hover height | 1 m (about 3 ft) | Simulator choice | Estimate |
| Touchdown / turn-rate / closure guides, score weights | see docs/TRAINING.md | Simulator choice | Estimate |
