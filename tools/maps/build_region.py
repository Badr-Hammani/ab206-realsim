"""Moving-map data for the area around Khouribga (98 x 98 km): towns and villages, main roads, railways.
Sources: Overture Maps 2026-11-18.0 divisions (towns, populations) and transportation segments
(OpenStreetMap, ODbL). Output: data/maps/khouribga/region.json (map coordinates: x east, z south, metres).
Usage: python build_region.py <towns.json> <wide_roads.json> <out_dir>
(the two json files come from overture_query.py-style queries over lon -7.49..-6.41, lat 32.41..33.31)
"""
import json, sys, os, re
from pyproj import CRS, Transformer
from shapely import wkt as WKT
from shapely.geometry import box
from shapely.ops import transform

TOWNS, ROADS, OUT = sys.argv[1:4]
LON0, LAT0 = -6.9504834, 32.8594064
HALF = 49152.0
local = CRS.from_proj4(f"+proj=aeqd +lat_0={LAT0} +lon_0={LON0} +x_0=0 +y_0=0 +ellps=WGS84 +units=m")
tr = Transformer.from_crs("EPSG:4326", local, always_xy=True)
clip = box(-HALF, -HALF, HALF, HALF)

def latin(name):
    # names come as "Latin Tifinagh Arabic": keep the Latin part when there is one
    if not name:
        return ""
    parts = re.split(r"\s+(?=[؀-ۿⴰ-⵿])", name, maxsplit=1)
    return parts[0].strip() if re.search(r"[A-Za-z]", parts[0]) else name

towns = []
for t in json.load(open(TOWNS)):
    if t["subtype"] not in ("locality",) or not t["name"]:
        continue
    e, n = tr.transform(t["x"], t["y"])
    if abs(e) > HALF or abs(n) > HALF:
        continue
    kind = {"city": 3, "town": 2}.get(t["class"], 1)
    towns.append([latin(t["name"]), round(e), round(-n), int(t["pop"] or 0), kind])
towns.sort(key=lambda t: -t[3])

CLS = {"motorway": 0, "trunk": 1, "primary": 1, "secondary": 2, "tertiary": 3, "standard_gauge": 4}
roads = []
for r in json.load(open(ROADS)):
    g = transform(lambda x, y, z=None: tr.transform(x, y), WKT.loads(r["wkt"])).intersection(clip)
    if g.is_empty:
        continue
    parts = list(g.geoms) if hasattr(g, "geoms") else [g]
    for p in parts:
        if p.geom_type != "LineString" or p.length < 20:
            continue
        p = p.simplify(12.0)
        roads.append([CLS[r["class"]], [[round(x), round(-y)] for x, y in p.coords]])
# cubic polynomials between lon/lat and map metres (millimetre accuracy over the area) so the game can
# place web map tiles and show GPS positions without a projection library
import numpy as np
lo, la = np.meshgrid(np.linspace(-0.6, 0.6, 61), np.linspace(-0.5, 0.5, 51))
lo = lo.ravel(); la = la.ravel()
ee, nn = tr.transform(lo + LON0, la + LAT0)
def basis(u, v):
    return np.stack([u ** i * v ** j for i in range(4) for j in range(4) if i + j <= 3], 1)
A = basis(lo, la); Bm = basis(ee / 1e4, nn / 1e4)
proj = {"fwd_e": np.linalg.lstsq(A, ee, rcond=None)[0].tolist(), "fwd_n": np.linalg.lstsq(A, nn, rcond=None)[0].tolist(),
        "inv_lon": np.linalg.lstsq(Bm, lo, rcond=None)[0].tolist(), "inv_lat": np.linalg.lstsq(Bm, la, rcond=None)[0].tolist(),
        "lon0": LON0, "lat0": LAT0, "note": "terms u^i v^j for i in 0..3, j in 0..3, i+j<=3; fwd u,v = dlon,dlat deg -> east,north m; inv u,v = east/1e4,north/1e4 -> dlon,dlat"}
json.dump({"size_m": HALF * 2, "proj": proj, "towns": towns, "roads": roads,
           "photos": {"spring": "region_spring_jpg.bin", "summer": "region_summer_jpg.bin"},
           "sources": "Towns: Overture Maps divisions; roads and railways: OpenStreetMap contributors (ODbL) via Overture Maps; photo: Sentinel-2 L2A, 32 m per pixel"},
          open(os.path.join(OUT, "region.json"), "w"), separators=(",", ":"), ensure_ascii=False)
print(len(towns), "towns,", len(roads), "road pieces,", os.path.getsize(os.path.join(OUT, "region.json")) // 1024, "KB")
