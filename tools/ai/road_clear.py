"""Hard rule: no photo-detected building may stand on a road.

Removes or trims every building in data/maps/khouribga/ai_features.json that overlaps
  - a road of map.json (the strips the game draws: half width + MARGIN m), and
  - for checked spots, the asphalt seen in the photo (spots/<name>/road_mask.png, white = road).
A building that loses more than DROP of its area is removed; otherwise the road part is cut off
and the rest kept (a straight cut along the road edge, the box stays tidy).

usage: python3 tools/ai/road_clear.py            (rewrites ai_features.json in place)
"""
import json, math, os, sys
import numpy as np
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import tiles
ROOT = os.path.join(HERE, "..", "..", "data", "maps", "khouribga")
MARGIN = 1.0      # m of kerb/sidewalk kept clear beyond the drawn road edge
DROP = 0.35       # building removed if more than this share of it is on a road

feat = json.load(open(os.path.join(ROOT, "ai_features.json")))
meta = json.load(open(os.path.join(ROOT, "map.json")))

road_geoms = []
for kind, w, pts in meta.get("roads", []):
    if len(pts) >= 2:
        road_geoms.append(LineString(pts).buffer(float(w) * 0.5 + MARGIN, cap_style=2))

# asphalt seen in the photo of checked spots
for name in sorted(os.listdir(os.path.join(ROOT, "spots"))):
    sd = os.path.join(ROOT, "spots", name)
    mpath = os.path.join(sd, "road_mask.png")
    if not os.path.exists(mpath):
        continue
    import cv2
    spot = json.load(open(os.path.join(sd, "spot.json")))
    N = float(2 ** spot["z"] * 256)
    def to_map(u, v):
        X = spot["tx0"] * 256 + spot["off"][0] + u
        Y = spot["ty0"] * 256 + spot["off"][1] + v
        lon = X / N * 360.0 - 180.0
        lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * Y / N))))
        return tiles.to_map(lon, lat)
    m = (cv2.imread(mpath, 0) > 127).astype(np.uint8)
    m = cv2.dilate(m, np.ones((3, 3), np.uint8))           # ~0.5 m kerb
    cs, hier = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    n = 0
    for i, c in enumerate(cs):
        if hier[0][i][3] != -1 or len(c) < 3:
            continue
        shell = [to_map(float(p[0][0]), float(p[0][1])) for p in c]
        holes = [[to_map(float(p[0][0]), float(p[0][1])) for p in cs[j]]
                 for j in range(len(cs)) if hier[0][j][3] == i and len(cs[j]) >= 3]
        g = Polygon(shell, holes).buffer(0)
        if not g.is_empty:
            road_geoms.append(g); n += 1
    print("spot %s: %d asphalt areas from the photo" % (name, n))

tree = STRtree(road_geoms)
out, dropped, trimmed = [], 0, 0
for b in feat["buildings"]:
    h, flat, col = b[0], b[1], b[2] if len(b) > 2 else None
    poly = Polygon(list(zip(flat[0::2], flat[1::2]))).buffer(0)
    if poly.geom_type != "Polygon":
        poly = max(getattr(poly, "geoms", [poly]), key=lambda g: g.area)
    if poly.is_empty:
        continue
    hits = [road_geoms[i] for i in tree.query(poly) if road_geoms[i].intersects(poly)]
    if hits:
        rest = poly.difference(unary_union(hits))
        if rest.is_empty or rest.area < (1 - DROP) * poly.area or rest.area < 12:
            dropped += 1
            continue
        if rest.geom_type != "Polygon":
            rest = max(rest.geoms, key=lambda g: g.area)
            if rest.area < (1 - DROP) * poly.area:
                dropped += 1
                continue
        poly = rest.simplify(0.3)
        if poly.geom_type != "Polygon" or poly.is_empty:
            dropped += 1
            continue
        trimmed += 1
    xy = list(poly.exterior.coords)[:-1]
    nb = [h, [round(v, 1) for p in xy for v in p]]
    if col is not None:
        nb.append(col)
    out.append(nb)
print("buildings %d -> %d (%d removed, %d trimmed off a road)" % (len(feat["buildings"]), len(out), dropped, trimmed))
feat["buildings"] = out
json.dump(feat, open(os.path.join(ROOT, "ai_features.json"), "w"), separators=(",", ":"))
