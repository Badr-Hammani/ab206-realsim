# Maps

Pick the map in the pause menu: **Esc → Fly → Map**. The sim reloads on the new map
(a few seconds) and remembers the choice.

| Map | What it is |
|---|---|
| Training valley | The original fictional 4 x 4 km Alpine-style valley (procedural). |
| Khouribga GMMK | 16 x 16 km of real terrain around Khouribga military aerodrome (GMMK), Morocco. |

## Khouribga GMMK - what is real and what is estimated

| Item | Source | Status |
|---|---|---|
| Terrain heights (649-875 m MSL) | Copernicus GLO-30 DEM, 30 m grid, resampled to 32 m | **Real data.** It is a surface model (includes tree and roof tops in places). Flattened by the sim under the runway, taxiways and aprons. |
| Ground photo | Sentinel-2 L2A true colour, 1 June 2025 (0 % cloud), 10 m, shown at 8 m per pixel | **Real image.** Too coarse to show markings or small objects; fine detail near the ground is generated. |
| Runway 05/23 position, direction (047.6° true) and length | OpenStreetMap (via Overture Maps 2026-11-18) | **Real data.** OSM gives 2,402 m; OpenAIP lists 2,800 m x 45 m. The sim follows the OSM line (it matches the satellite photo). |
| Runway width 45 m, asphalt, elevation 2,552 ft | OpenAIP (learn-atc.com GMMK page) | **Published data.** The sim's ground at the runway is 769-777 m (2,522-2,549 ft). |
| Taxiways, aprons, apron helipad position | OpenStreetMap | **Real positions.** Taxiway width 15 m and the markings are estimated. |
| 127 buildings | OpenStreetMap footprints (mostly in the city), height 7 m unless tagged | Real footprint, **estimated height**. |
| ~22,400 houses | ESA WorldCover 2021 "built-up" cells, one block per 22 m cell, 1-4 storeys | **Estimated.** They show where the town is, not the real buildings. |
| ~3,000 trees | ESA WorldCover "tree cover" cells | **Estimated** positions and shapes. |
| Main helipad (start point, lessons) | Sim choice: open ground 100 m south-east of the apron helipad | **Not a real pad.** Moved so the hover sight gates are not inside the hangar 40 m north of the real apron helipad. |
| Apron helipad | OpenStreetMap helipad node | Real position, the H marking is generic. |
| Field LZ, Pinnacle LZ | Sim choice: flat open ground 1.5 km north of the main pad; the highest point of the map (875 m, 7 km east) | **Sim training sites**, not real landing sites. |

GMMK is a **military aerodrome**: this map is for practice in the sim only. Real procedures,
circuits, frequencies and restricted areas come from your school and the Moroccan AIP, never from here.

Elevation matters: on the Khouribga plateau (about 2,550 ft) the same hover needs more torque than in
the training valley (about 920 ft). Use the Weather menu temperature to try a hot summer day.

## Rebuilding the map data

`tools/maps/overture_query.py` fetches the OSM features, `tools/maps/build_khouribga.py` downloads
the DEM, photo and land cover and writes `data/maps/khouribga/` (height.bin, ortho_jpg.bin, map.json).
Python 3 with numpy, scipy, rasterio, pyproj, shapely, pillow, s3fs, pyarrow. All sources are open
data from public AWS / ESA buckets (no account needed).

Attribution: contains modified Copernicus Sentinel data 2025 and Copernicus DEM (ESA);
ESA WorldCover 2021 (CC BY 4.0); © OpenStreetMap contributors (ODbL) via Overture Maps.
