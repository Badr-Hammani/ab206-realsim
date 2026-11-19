"""Moving-map data for the area around Khouribga (64 x 64 km): towns and villages, main roads, railways.
Sources: Overture Maps 2026-11-18.0 divisions (towns, populations) and transportation segments
(OpenStreetMap, ODbL). Output: data/maps/khouribga/region.json (map coordinates: x east, z south, metres).
Usage: python build_region.py <towns.json> <wide_roads.json> <out_dir>
(the two json files come from overture_query.py-style queries over lon -7.32..-6.58, lat 32.55..33.17)
"""
import json, sys, os, re
from pyproj import CRS, Transformer
from shapely import wkt as WKT
from shapely.geometry import box
from shapely.ops import transform

TOWNS, ROADS, OUT = sys.argv[1:4]
LON0, LAT0 = -6.9504834, 32.8594064
HALF = 32768.0
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
json.dump({"size_m": HALF * 2, "towns": towns, "roads": roads,
           "photos": {"spring": "region_spring_jpg.bin", "summer": "region_summer_jpg.bin"},
           "sources": "Towns: Overture Maps divisions; roads and railways: OpenStreetMap contributors (ODbL) via Overture Maps; photo: Sentinel-2 L2A, 32 m per pixel"},
          open(os.path.join(OUT, "region.json"), "w"), separators=(",", ":"), ensure_ascii=False)
print(len(towns), "towns,", len(roads), "road pieces,", os.path.getsize(os.path.join(OUT, "region.json")) // 1024, "KB")
