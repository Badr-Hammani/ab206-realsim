"""Finds buildings and trees in the stitched 0.5 m Esri photo of Khouribga (tools/ai/mosaic.py) and
writes data/maps/khouribga/ai_features.json for the sim:
  buildings: [[height_m, [x0, z0, x1, z1, ...]], ...]   (footprint polygon, sim map metres)
  trees:     [[x, z, crown_radius_m], ...]
Method (no training data exists for Khouribga, so this is image analysis, not a trained network):
- roads from OpenStreetMap (map.json) are masked first; they also split the city into blocks
- vegetation = green-tinted, textured pixels; shadows = very dark pixels (sun is in the east, so
  shadows lie on the WEST side of each building)
- roof = the rest, if textured (bare ground is smooth); split into separate buildings at strong
  roof edges and at shadow lines
- height = length of the shadow west of the building x calibration (median house ~7 m); 3-30 m
- trees = vegetation blobs; centre and crown radius from the distance transform
Usage: extract.py <mosaic prefix (m18)> <out json>"""
import json, os, sys
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(__file__))
from geo import Geo

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
pref, out_path = sys.argv[1], sys.argv[2]
MIN_SHADOW_FRAC = float(os.environ.get("MIN_SHADOW_FRAC", "0.5"))   # share of west-edge rows with shadow
MIN_WIDTH_M = 4.0
im = cv2.imread(pref + ".jpg")
meta = np.load(pref + ".npz")
geo = Geo(int(meta["z"]), int(meta["x0"]), int(meta["y0"]))
valid = meta["valid"].astype(bool)
# work at 1 m (half resolution); pixel (u, v) here = (2u, 2v) in the mosaic
S = 2
small = cv2.resize(im, (im.shape[1] // S, im.shape[0] // S), interpolation=cv2.INTER_AREA)
valid = cv2.resize(valid.astype(np.uint8), (small.shape[1], small.shape[0]), interpolation=cv2.INTER_NEAREST).astype(bool)
valid = cv2.erode(valid.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
lab = cv2.cvtColor(small, cv2.COLOR_BGR2LAB).astype(np.float32)
L, A, Bb = lab[..., 0], lab[..., 1] - 128, lab[..., 2] - 128
m = cv2.blur(L, (4, 4)); sd = np.sqrt(np.maximum(cv2.blur(L * L, (4, 4)) - m * m, 0))
H, W = L.shape
print("work grid", W, H)

road = np.zeros((H, W), np.uint8)
mm = json.load(open(os.path.join(ROOT, "data/maps/khouribga/map.json")))
for r in mm["roads"]:
    p = geo.to_px([q[0] for q in r[2]], [q[1] for q in r[2]]) / S
    cv2.polylines(road, [np.round(p).astype(np.int32).reshape(-1, 1, 2)], False, 1, max(2, int(round(r[1] * 0.8))))
# airport surfaces and helipads are kept free too (runway shoulders 10 m)
ap = mm["airport"]
def _pl(pts, w, closed=False, fill=False):
    p = np.round(geo.to_px([q[0] for q in pts], [q[1] for q in pts]) / S).astype(np.int32).reshape(-1, 1, 2)
    if fill:
        cv2.fillPoly(road, [p], 1)
    else:
        cv2.polylines(road, [p], closed, 1, max(2, int(round(w))))
_pl(ap["runway"]["ends"], ap["runway"]["width"] + 20.0)
for t in ap["taxiways"]:
    _pl(t, ap["taxiway_width"] + 6.0)
for a in ap["aprons"]:
    _pl(a, 0, fill=True)
for nm, pd in mm["pads"].items():
    c = geo.to_px([pd[0]], [pd[1]])[0] / S
    cv2.circle(road, (int(c[0]), int(c[1])), int(pd[2] + 15), 1, -1)
road = road.astype(bool)
# built-up land (ESA WorldCover "built-up" houses and OSM footprints of map.json): a roof without a
# clear shadow is only accepted inside it, so bare soil and fields beside roads stay empty
urban = np.zeros((H, W), np.uint8)
for b in mm["buildings"]:
    if len(b) > 6 and int(b[6]) <= 1:
        u, v = geo.to_px(b[0], b[1]) / S
        if 0 <= u < W and 0 <= v < H:
            cv2.circle(urban, (int(u), int(v)), 18, 1, -1)
urban = urban.astype(bool)
near_road = cv2.dilate(road.astype(np.uint8), np.ones((61, 61), np.uint8)).astype(bool)   # 30 m

veg = (A < -9) & (sd > 2.5) & (L < 140)
veg = cv2.morphologyEx(veg.astype(np.uint8), cv2.MORPH_OPEN, np.ones((2, 2), np.uint8)).astype(bool)
shadow = (L < 72) & ~veg
smooth = (cv2.blur(sd, (5, 5)) < 3.0) & (Bb > 8)
bld = valid & ~road & ~veg & ~shadow & ~smooth & (L > 90) & near_road
bld = cv2.morphologyEx(bld.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
bld = cv2.morphologyEx(bld, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
# split at strong roof edges (parapets / height steps between houses)
edges = cv2.Canny(cv2.GaussianBlur(small, (3, 3), 0), 60, 140)
split = bld.copy()
split[edges > 0] = 0
n, lbl, stats, cent = cv2.connectedComponentsWithStats(split, connectivity=4)
print("components", n)

# shadow length west of each pixel row segment: for every shadow run, its length is the height
# cue of the building just EAST of it
shadow_u8 = shadow.astype(np.uint8)
run_len = np.zeros((H, W), np.float32)      # at the first pixel east of a shadow run: run length
for y in range(H):
    row = shadow_u8[y]
    if not row.any():
        continue
    d = np.diff(np.concatenate([[0], row, [0]]))
    starts = np.where(d == 1)[0]; ends = np.where(d == -1)[0]
    for s0, e0 in zip(starts, ends):
        if e0 < W and e0 - s0 <= 40:
            run_len[y, e0] = e0 - s0
            if e0 + 1 < W:
                run_len[y, e0 + 1] = max(run_len[y, e0 + 1], e0 - s0)

buildings = []
shadow_meds = []
lbl_d = lbl
for i in range(1, n):
    x, y, w, h, area = stats[i]
    if area < 25 or area > 20000:
        continue
    mask = (lbl_d[y:y + h, x:x + w] == i).astype(np.uint8)
    mask = cv2.dilate(mask, np.ones((2, 2), np.uint8))      # give back the edge pixel taken by the split
    cs, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cs:
        continue
    c = max(cs, key=cv2.contourArea)
    c = cv2.approxPolyDP(c, 1.0, True)
    if len(c) < 3 or cv2.contourArea(c) < 20:
        continue
    rl = run_len[y:y + h, x:x + w][mask > 0]
    rl = rl[rl > 0]
    med = float(np.median(rl)) if rl.size >= 3 else 0.0
    # a real building casts a shadow: most of its west edge must touch a shadow run (bare soil,
    # road shoulders and fields beside roads have none). M2.25b: without this check thousands of
    # false "buildings" lined every road and the airfield.
    rows = np.where(mask.any(1))[0]
    west = mask.argmax(1)
    sh_rows = 0
    for r in rows:
        x_w = x + int(west[r])
        sh_rows += 1 if shadow[y + r, max(x_w - 3, 0):x_w + 1].any() else 0
    sh_frac = sh_rows / max(len(rows), 1)
    in_urban = urban[y:y + h, x:x + w][mask > 0].mean() > 0.6
    if not in_urban and (sh_frac < MIN_SHADOW_FRAC or med <= 0):
        continue
    # thin strips (road shoulders, kerbs, walls of plots) are not houses
    (_, _), (rw, rh), _ = cv2.minAreaRect(c)
    if min(rw, rh) < MIN_WIDTH_M:
        continue
    # bent strips: mean width (2 x area / perimeter) under 4.5 m, or very long and narrow
    ar, pe = cv2.contourArea(c), cv2.arcLength(c, True)
    if 2.0 * ar / max(pe, 1e-6) < 2.25 or max(rw, rh) > 8.0 * min(rw, rh):
        continue
    if med > 0:
        shadow_meds.append(med)
    pts = (c.reshape(-1, 2).astype(np.float64) + [x, y]) * S
    xz = geo.to_map(pts[:, 0], pts[:, 1])
    col = small[y:y + h, x:x + w][mask > 0].mean(0)   # BGR mean of the roof
    buildings.append([med, xz, col])

k = 7.0 / float(np.median(shadow_meds)) if shadow_meds else 1.0
print("buildings", len(buildings), "with shadow", len(shadow_meds), "median shadow m", np.median(shadow_meds) if shadow_meds else 0, "k", k)
out_b = []
rng = np.random.default_rng(7)
for med, xz, col in buildings:
    hgt = med * k if med > 0 else float(rng.choice([4.0, 6.5, 6.5, 9.5]))
    hgt = float(np.clip(hgt + rng.uniform(-1.0, 1.0), 3.0, 30.0))
    poly = []
    # sim winding: keep as is; round to 0.1 m
    for p in xz:
        poly += [round(float(p[0]), 1), round(float(p[1]), 1)]
    out_b.append([round(hgt, 1), poly, "%02x%02x%02x" % (int(col[2]), int(col[1]), int(col[0]))])

# trees: vegetation blobs that are dark (crowns), centres from the distance transform peaks
crowns = veg & (L < 100) & (sd > 4.0) & valid & ~road
crowns = cv2.morphologyEx(crowns.astype(np.uint8), cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
dist = cv2.distanceTransform(crowns, cv2.DIST_L2, 3)
peaks = (dist >= 1.4) & (dist == cv2.dilate(dist, np.ones((5, 5), np.uint8)))
ys, xs = np.where(peaks)
trees = []
taken = np.zeros_like(crowns)
order = np.argsort(-dist[ys, xs])
for j in order:
    yy, xx = ys[j], xs[j]
    if taken[yy, xx]:
        continue
    r = float(dist[yy, xx]) + 0.7
    cv2.circle(taken, (int(xx), int(yy)), int(r), 1, -1)
    p = geo.to_map(np.array([xx * S + 1.0]), np.array([yy * S + 1.0]))[0]
    trees.append([round(float(p[0]), 1), round(float(p[1]), 1), round(min(r, 7.0), 1)])
print("trees", len(trees))
# coverage: 32 m cells of the 16 km core that were analysed (the sim drops its estimated houses
# and trees there). Row-major 512 x 512 bitmap from x,z = -8192, as a hex string of bytes.
cov = np.zeros((512, 512), np.uint8)
gz, gx = np.mgrid[0:512, 0:512]
cx = -8192 + (gx + 0.5) * 32.0; cz = -8192 + (gz + 0.5) * 32.0
pp = geo.to_px(cx.ravel(), cz.ravel()) / S
ix = np.round(pp[:, 0]).astype(int); iy = np.round(pp[:, 1]).astype(int)
ok = (ix >= 0) & (iy >= 0) & (ix < W) & (iy < H)
inside = np.zeros(ix.size, bool)
inside[ok] = valid[iy[ok], ix[ok]]
cov = inside.reshape(512, 512).astype(np.uint8)
print("coverage km2", cov.sum() * 32 * 32 / 1e6)
json.dump({"coverage": np.packbits(cov.ravel()).tobytes().hex(), "cov_cell": 32.0, "cov_origin": -8192.0, "cov_n": 512, "source": "Esri World Imagery (Maxar), 0.5 m, as cached by the sim; features found by tools/ai/extract.py",
           "buildings": out_b, "trees": trees}, open(out_path, "w"), separators=(",", ":"))

# preview images
vis = small.astype(np.float32)
for mk, cc in ((bld.astype(bool), (0, 0, 255)), (crowns.astype(bool), (0, 255, 0)), (road, (255, 160, 0))):
    vis[mk] = vis[mk] * 0.45 + np.array(cc) * 0.55
vis = vis.astype(np.uint8)
for hgt, poly, _c in out_b:
    p = geo.to_px(poly[0::2], poly[1::2]) / S
    cv2.polylines(vis, [np.round(p).astype(np.int32).reshape(-1, 1, 2)], True, (255, 255, 255), 1)
cv2.imwrite(out_path + ".preview.jpg", vis, [cv2.IMWRITE_JPEG_QUALITY, 88])
