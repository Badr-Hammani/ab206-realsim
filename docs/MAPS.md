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
| Terrain heights (649-877 m MSL) | Copernicus GLO-30 DEM, 30 m grid, cubic-resampled to a 16 m grid | **Real data.** It is a surface model (includes tree and roof tops in places). Flattened by the sim under the runway, taxiways and aprons. |
| Ground photo (Weather → Season) | Sentinel-2 L2A surface reflectance, median of 4 clear days per season: spring = 16, 26, 31 March and 22 April 2025; summer = 4, 14, 31 July and 13 August 2025. Natural colour, 10 m, shown at 8 m per pixel | **Real images.** 10 m is the sharpest free satellite imagery; markings and small objects are not visible in it. Ground grain, stones, tufts and plough lines near the helicopter are generated from the photo's colour. |
| Mosques (6, with minarets), fuel stations (13) | Overture Maps places (Foursquare / Meta / Microsoft data, CDLA Permissive 2.0) | **Real positions.** The building shapes are generic (prayer hall + square minaret, canopy + shop). |
| Schools, hospitals, university, industry, parks, football pitches, cemeteries | OpenStreetMap land use via Overture | **Real outlines.** Pitches get their lines drawn to their real size; schools/hospitals get generic blocks inside their real grounds; no estimated houses are placed inside these areas. |
| ~1,000 trees in real tree rows | OpenStreetMap via Overture | **Real positions.** |
| Roads and railway (1,088 km) | OpenStreetMap via Overture Maps | **Real positions.** Widths by road class and the surface look are estimated. |
| Runway 05/23 position, direction (047.6° true) and length | OpenStreetMap (via Overture Maps 2026-11-18) | **Real data.** OSM gives 2,402 m; OpenAIP lists 2,800 m x 45 m. The sim follows the OSM line (it matches the satellite photo). |
| Runway width 45 m, asphalt, elevation 2,552 ft | OpenAIP (learn-atc.com GMMK page) | **Published data.** The sim's ground at the runway is 769-777 m (2,522-2,549 ft). |
| Taxiways, aprons, apron helipad position | OpenStreetMap | **Real positions.** Taxiway width 15 m and the markings are estimated. |
| 127 buildings | OpenStreetMap footprints (mostly in the city), height 7 m unless tagged | Real footprint, **estimated height**. |
| ~40,000 houses | ESA WorldCover 2021 "built-up" cells, one 11-15 m block per 15 m cell, kept off the OSM streets and real land-use areas, 1-4 storeys (1-2 more where many shops and cafés are listed), windows drawn by a shader | **Estimated.** They show where the town is and how dense it is, not the real buildings. |
| ~2,900 trees | ESA WorldCover "tree cover" cells | **Estimated** positions and shapes. |
| Main helipad (start point, lessons) | Sim choice: open ground 100 m south-east of the apron helipad | **Not a real pad.** Moved so the hover sight gates are not inside the hangar 40 m north of the real apron helipad. |
| Apron helipad | OpenStreetMap helipad node | Real position, the H marking is generic. |
| Field LZ, Pinnacle LZ | Sim choice: flat open ground 1.5 km north of the main pad; the highest point of the map (875 m, 7 km east) | **Sim training sites**, not real landing sites. |

GMMK is a **military aerodrome**: this map is for practice in the sim only. Real procedures,
circuits, frequencies and restricted areas come from your school and the Moroccan AIP, never from here.

Elevation matters: on the Khouribga plateau (about 2,550 ft) the same hover needs more torque than in
the training valley (about 920 ft). Use the Weather menu temperature to try a hot summer day.

## Performance

The terrain is cut into 2 km tiles with three detail levels (16 m grid near you, 32 m beyond 2 km,
64 m beyond 5 km). Houses, trees and streets are only drawn within a distance set by the graphics
preset (F7): houses 2 / 3.5 / 7 km, trees 1.5 / 3 / 5 km, fine terrain 1.5 / 2 / 2.5 km on Low / Medium / High. If the frame rate stays under 38 FPS for 4 seconds, the game lowers the preset by itself (then the render scale on Low); choosing a preset yourself (F7 or menu) turns that off. The satellite photo
still shows the whole town and every road beyond that distance. If the frame rate drops over the city,
use Low.

## Real building footprints

Checked 2026-11-19: the Google and Microsoft machine-learned building datasets (VIDA combined set) have no
footprints at Khouribga, and OpenStreetMap has only about 130 mapped buildings there (used as-is). The rest
of the town is therefore estimated from ESA WorldCover. If buildings are added to OpenStreetMap later,
re-running tools/maps/overture_query.py and build_khouribga.py picks them up.

## Rebuilding the map data

`tools/maps/overture_query.py` fetches the OSM features, `tools/maps/build_khouribga.py` downloads
the DEM and land cover and writes `data/maps/khouribga/` (height.bin, map.json); `tools/maps/photo_composite.py`
makes the season photos (photo_spring_jpg.bin, photo_summer_jpg.bin).
Python 3 with numpy, scipy, rasterio, pyproj, shapely, pillow, s3fs, pyarrow. All sources are open
data from public AWS / ESA buckets (no account needed).

Attribution: contains modified Copernicus Sentinel data 2025 and Copernicus DEM (ESA);
ESA WorldCover 2021 (CC BY 4.0); © OpenStreetMap contributors (ODbL) via Overture Maps.
