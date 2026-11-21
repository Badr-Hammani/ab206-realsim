"""Puts one checked spot (tools/ai/spot/build.py + inf.py + trees.py, run in the spot's work folder)
into data/maps/khouribga/ai_features.json: buildings and trees inside the spot square are replaced,
and the square is marked as analysed (no estimated houses/trees drawn there).

usage: cd <work folder with area.png, pieces.json, inf_cells.json, trees.json>
       python3 <repo>/tools/ai/spot/merge.py <repo>/data/maps/khouribga/spots/<name>/spot.json
spot.json: {"name", "z", "tx0", "ty0", "off": [px, py] of area.png in the tile mosaic, "size": px}

Heights: the photo was taken with the sun nearly overhead, so shadows are too short to measure.
Planned-district houses get 6.5-9.5 m (ground floor + 1 or 2, Moroccan R+1/R+2), small pieces 3.5 m
(stair rooms, sheds), the old village 3.2 m (single storey), hand-drawn buildings their own height.
"""
import json, math, os, sys, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import tiles

spot = json.load(open(sys.argv[1]))
FEAT = os.path.join(HERE, "..", "..", "..", "data", "maps", "khouribga", "ai_features.json")
Z, TX0, TY0 = spot["z"], spot["tx0"], spot["ty0"]
OX, OY = spot["off"]
N = float(2 ** Z * 256)

def to_map(u, v):
    X = TX0 * 256 + OX + u
    Y = TY0 * 256 + OY + v
    lon = X / N * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * Y / N))))
    return tiles.to_map(lon, lat)

S = spot["size"]
x0, z0 = to_map(0, 0)
x1, z1 = to_map(S, S)
mpp = (x1 - x0) / S
inside = lambda x, z: x0 <= x <= x1 and z0 <= z <= z1

def h_of(key, lo, hi):
    r = int(hashlib.md5(key.encode()).hexdigest()[:6], 16) / float(0xFFFFFF)
    return round(lo + r * (hi - lo), 1)

bld = []
masks = []
for i, p in enumerate(json.load(open("pieces.json"))):
    poly = p["poly"]
    if p.get("manual"):
        h = p["h"]
    else:
        a = p["area_m2"]
        h = 3.5 if a < 25 else h_of("p%d" % i, 6.5, 9.5)
    col = "%02x%02x%02x" % tuple(int(c) for c in reversed(p["col"])) if sum(p["col"]) > 0 else "c8b8a0"
    bld.append((h, poly, col))
for i, p in enumerate(json.load(open("inf_cells.json"))):
    bld.append((h_of("i%d" % i, 2.9, 3.6), p["poly"], "b4aa98"))

def pip(x, y, poly):
    c = False
    n = len(poly)
    for k in range(n):
        ax, ay = poly[k]; bx, by = poly[(k + 1) % n]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            c = not c
    return c

out_b = []
for h, poly, col in bld:
    flat = []
    for u, v in poly:
        x, z = to_map(u, v)
        flat += [round(x, 1), round(z, 1)]
    out_b.append([h, flat, col])
out_t = []
for u, v, r in json.load(open("trees.json")):
    if any(pip(u, v, poly) for _, poly, _ in bld):
        continue                       # dark spot on a roof, not a tree
    x, z = to_map(u, v)
    out_t.append([round(x, 1), round(z, 1), round(min(max(r * mpp, 1.2), 7.0), 1)])

d = json.load(open(FEAT))
d["buildings"] = [b for b in d["buildings"] if not inside(b[1][0], b[1][1])] + out_b
d["trees"] = [t for t in d["trees"] if not inside(t[0], t[1])] + out_t
cov = bytearray(bytes.fromhex(d["coverage"]))
n, cell, org = d["cov_n"], d["cov_cell"], d["cov_origin"]
for j in range(n):
    for i in range(n):
        if inside(org + (i + 0.5) * cell, org + (j + 0.5) * cell):
            bit = j * n + i
            cov[bit >> 3] |= 1 << (7 - (bit & 7))
d["coverage"] = cov.hex()
sp = [s for s in d.get("spots", []) if s.get("name") != spot["name"]]
sp.append({"name": spot["name"], "rect": [round(x0, 1), round(z0, 1), round(x1, 1), round(z1, 1)],
           "buildings": len(out_b), "trees": len(out_t)})
d["spots"] = sp
json.dump(d, open(FEAT, "w"), separators=(",", ":"))
print("spot %s: %d buildings, %d trees, square x %.0f..%.0f z %.0f..%.0f (%.3f m/px)"
      % (spot["name"], len(out_b), len(out_t), x0, x1, z0, z1, mpp))
