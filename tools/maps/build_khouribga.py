"""Builds the Khouribga (GMMK) map data for AB206 REALSIM from open data.

Sources (all free/open):
  - Elevation: Copernicus GLO-30 DEM (30 m), ESA / AWS open data  (copernicus-dem-30m)
  - Satellite photo: Sentinel-2 L2A true colour, 1 June 2025, tile 29SPS (sentinel-cogs, Element84/AWS)
  - Land cover: ESA WorldCover 2021 v200 10 m (esa-worldcover)
  - Airport layout, buildings, names: OpenStreetMap via Overture Maps 2026-11-18.0 (ODbL)
Output: data/maps/khouribga/{height.bin, map.json}; the photos come from photo_composite.py

Usage: python build_khouribga.py <dl_dir> <infra.json> <buildings.json> <out_dir> <roads.json> <landuse.json> <land.json> <places.json>
(dl_dir holds the two Copernicus tiles; the json files come from overture_query.py: infra, buildings, roads (transportation
segments), landuse (base/land_use), land (base/land: tree rows) and places (overture_query.py places mode))
"""
import json, math, sys, io, os
import numpy as np
import rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from pyproj import CRS, Transformer
from shapely import wkt as WKT
from shapely.geometry import Point, LineString, Polygon, box
from shapely.ops import unary_union
from shapely import transform as shp_transform2
from shapely.prepared import prep
from PIL import Image

DL, INFRA, BLD, OUT, ROADS, LANDUSE, LANDF, PLACES = sys.argv[1:9]
os.makedirs(OUT, exist_ok=True)

# World origin = the OSM helipad on the airport's main apron ("Main helipad" in the sim).
LON0, LAT0 = -6.9504834, 32.8594064
SIZE = 16384.0
N = 1025          # 16 m grid (DEM is 30 m: cubic resampling gives smooth hills instead of facets)
CELL = SIZE / (N - 1)
HALF = SIZE / 2
HSCALE = 0.05     # height.bin: uint16 * 0.05 m

local = CRS.from_proj4(f"+proj=aeqd +lat_0={LAT0} +lon_0={LON0} +x_0=0 +y_0=0 +ellps=WGS84 +units=m")
to_local = Transformer.from_crs("EPSG:4326", local, always_xy=True)
to_ll = Transformer.from_crs(local, "EPSG:4326", always_xy=True)

def ll2xz(lon, lat):
    e, n = to_local.transform(lon, lat)
    return e, -n          # Godot: x = east, -z = north

def geom_local(g):
    return shp_transform2(g, lambda a: np.column_stack(to_local.transform(a[:, 0], a[:, 1])))   # (east, north)

# ---------------------------------------------------------------- elevation
# Destination grid in (east, north) with row 0 = north edge. We need row j = z index (z from -HALF = north).
dst_tf = from_origin(-HALF - CELL / 2, HALF + CELL / 2, CELL, CELL)
dem = np.full((N, N), np.nan, dtype=np.float32)
for t in ["dem_w008.tif", "dem_w007.tif"]:
    with rasterio.open(os.path.join(DL, t)) as src:
        tmp = np.full((N, N), np.nan, dtype=np.float32)
        reproject(rasterio.band(src, 1), tmp, dst_transform=dst_tf, dst_crs=local, resampling=Resampling.cubic, dst_nodata=np.nan)
        dem = np.where(np.isnan(dem), tmp, dem)
assert not np.isnan(dem).any(), "DEM gap"
# row r of dem is north = HALF - r*CELL  ->  z = -north = -HALF + r*CELL : row index == j directly.
heights = dem.astype(np.float64)
print("DEM range %.1f - %.1f m" % (heights.min(), heights.max()))

# ---------------------------------------------------------------- OSM / Overture features
infra = json.load(open(INFRA))
feat = {"runway": [], "taxiway": [], "apron": [], "helipad": []}
for f in infra:
    if f["subtype"] == "airport" and f["class"] in feat:
        feat[f["class"]].append(geom_local(WKT.loads(f["wkt"])))
rw_line = feat["runway"][0]
c = list(rw_line.coords)
sw, ne = np.array(c[0]), np.array(c[-1])
rw_len = float(np.linalg.norm(ne - sw))
rw_hdg = (math.degrees(math.atan2(ne[0] - sw[0], ne[1] - sw[1])) + 360) % 360
print("runway length %.0f m, true heading %.1f" % (rw_len, rw_hdg))
RW_W = 45.0     # OpenAIP: 2,800 m x 45 m asphalt
TW_W = 15.0     # estimated taxiway width
paved = unary_union([LineString([sw, ne]).buffer(RW_W / 2, cap_style=2)] +
                    [t.buffer(TW_W / 2) for t in feat["taxiway"]] + feat["apron"])
flat_zone = paved.buffer(40.0)
pz = prep(flat_zone)

# flatten: inside the zone, heights follow a smooth surface (runway: straight slope between its ends)
from scipy.ndimage import gaussian_filter, distance_transform_edt
import shapely
smooth = gaussian_filter(heights, 160.0 / CELL)
gx = -HALF + np.arange(N) * CELL
GX, GN = np.meshgrid(gx, -gx)          # east, north for [j, i]
mask = shapely.contains_xy(flat_zone, GX, GN)
def grid_h(arr, e, n):
    fi = (e + HALF) / CELL; fj = (-n + HALF) / CELL
    i, j = int(fi), int(fj); a, b = fi - i, fj - j
    return (arr[j, i] * (1 - a) * (1 - b) + arr[j, i + 1] * a * (1 - b) + arr[j + 1, i] * (1 - a) * b + arr[j + 1, i + 1] * a * b)
h_sw, h_ne = grid_h(smooth, *sw), grid_h(smooth, *ne)
print("runway ends %.1f / %.1f m (%.2f%% slope)" % (h_sw, h_ne, (h_ne - h_sw) / rw_len * 100))
target = smooth.copy()
u = (ne - sw) / rw_len
PX_, PY_ = GX - sw[0], GN - sw[1]
S_ = np.clip(PX_ * u[0] + PY_ * u[1], 0, rw_len)
D_ = np.abs(PX_ * u[1] - PY_ * u[0])
lin = h_sw + (h_ne - h_sw) * S_ / rw_len
w_ = np.clip((D_ - 60) / 60, 0, 1)
sel = mask & (D_ < 120)
target[sel] = (lin * (1 - w_) + smooth * w_)[sel]
dist = distance_transform_edt(~mask) * CELL
blend = np.clip(dist / 96.0, 0, 1)
blend = blend * blend * (3 - 2 * blend)
heights = target * (1 - blend) + heights * blend

# ---------------------------------------------------------------- land cover (ESA WorldCover)
WC = "/vsicurl/https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N30W009_Map.tif"
LC_N = 1640    # 10 m
lc = np.zeros((LC_N, LC_N), np.uint8)
lc_tf = from_origin(-HALF, HALF, SIZE / LC_N, SIZE / LC_N)
with rasterio.open(WC) as src:
    reproject(rasterio.band(src, 1), lc, dst_transform=lc_tf, dst_crs=local, resampling=Resampling.nearest)
vals, cnt = np.unique(lc, return_counts=True)
print("land cover classes", dict(zip(vals.tolist(), (cnt / cnt.sum()).round(3).tolist())))

# ---------------------------------------------------------------- roads and railways (OSM via Overture)
ROAD_W = {"motorway": 14, "trunk": 12, "primary": 10, "secondary": 8, "tertiary": 7, "residential": 6, "unclassified": 5.5,
          "living_street": 5, "service": 4.5, "track": 3.5, "unknown": 5, "pedestrian": 4, "standard_gauge": 4}
ROAD_KIND = {"track": 1, "standard_gauge": 2}     # 0 asphalt, 1 dirt track, 2 railway
roads = []
road_geoms = []
for r in json.load(open(ROADS)):
    w = ROAD_W.get(r["class"])
    if w is None:
        continue
    g = geom_local(WKT.loads(r["wkt"]))
    if g.geom_type != "LineString" or g.length < 3:
        continue
    if paved.buffer(5).contains(g):
        continue            # airport taxiways come from the airport layer
    roads.append([ROAD_KIND.get(r["class"], 0), w, [[round(x, 1), round(-y, 1)] for x, y in g.coords]])
    road_geoms.append(g.buffer(w / 2 + 1.5))
road_zone = prep(unary_union(road_geoms))
print("roads:", len(roads), "km %.0f" % (sum(LineString([(p[0], p[1]) for p in r[2]]).length for r in roads) / 1000))

# ---------------------------------------------------------------- real land use (OSM via Overture)
# Parks, sports pitches, cemeteries, schools, hospitals, industry: drawn as ground areas, and no estimated
# houses inside them. Area kinds: 0 park / grass, 1 sports pitch, 2 cemetery, 3 school or hospital yard.
AREA_KIND = {"park": 0, "grass": 0, "garden": 0, "recreation_ground": 0, "playground": 0, "pitch": 1, "stadium": 1,
             "cemetery": 2, "school": 3, "university": 3, "college": 3, "hospital": 3}
NO_HOUSE = set(AREA_KIND) | {"industrial", "quarry", "orchard", "farmland"}
from shapely import constrained_delaunay_triangles
areas = []
lu_polys = []         # (class, name, polygon in east/north)
no_house = []
for r in json.load(open(LANDUSE)):
    g = geom_local(WKT.loads(r["wkt"]))
    if g.geom_type == "MultiPolygon":
        parts = list(g.geoms)
    elif g.geom_type == "Polygon":
        parts = [g]
    else:
        continue
    for pg in parts:
        if not pg.is_valid:
            pg = pg.buffer(0)
        c = r["class"]
        lu_polys.append((c, r["name"], pg))
        if c in NO_HOUSE:
            no_house.append(pg.buffer(3))
        if c not in AREA_KIND or pg.area > 400000:
            continue
        k = AREA_KIND[c]
        tri = []
        if k == 1:
            # pitch: its oriented rectangle, so the lines can be drawn in the rectangle's frame
            rr = pg.minimum_rotated_rectangle
            cc = np.array(rr.exterior.coords)[:4]
            e1 = cc[1] - cc[0]; e2 = cc[2] - cc[1]
            if np.linalg.norm(e1) < np.linalg.norm(e2):
                e1, e2 = e2, e1
            ctr = cc.mean(axis=0)
            L = float(np.linalg.norm(e1)); W = float(np.linalg.norm(e2))
            u = e1 / L; v = e2 / W
            nl = max(1, int(L / 10)); nw = max(1, int(W / 10))
            for a in range(nl):
                for b in range(nw):
                    q = [ctr + u * (L * (a / nl - 0.5)) + v * (W * (b / nw - 0.5)), ctr + u * (L * ((a + 1) / nl - 0.5)) + v * (W * (b / nw - 0.5)),
                         ctr + u * (L * ((a + 1) / nl - 0.5)) + v * (W * ((b + 1) / nw - 0.5)), ctr + u * (L * (a / nl - 0.5)) + v * (W * ((b + 1) / nw - 0.5))]
                    for t in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                        tri += [round(float(t[i][j]) * (1 if j == 0 else -1), 1) for i in range(3) for j in range(2)]
            areas.append([k, tri, [round(float(ctr[0]), 1), round(float(-ctr[1]), 1), round(float(u[0]), 4), round(float(-u[1]), 4), round(L, 1), round(W, 1)]])
            continue
        # other areas: clipped to a 10 m grid so they follow the ground, then triangulated
        x0, y0, x1, y1 = pg.bounds
        for gx in np.arange(math.floor(x0 / 10) * 10, x1, 10):
            for gy in np.arange(math.floor(y0 / 10) * 10, y1, 10):
                piece = pg.intersection(box(gx, gy, gx + 10, gy + 10))
                if piece.is_empty or piece.area < 0.5:
                    continue
                for t in constrained_delaunay_triangles(piece).geoms:
                    cs = list(t.exterior.coords)[:3]
                    # Godot front faces are clockwise seen from above (x east, z south)
                    (ax, ay), (bx, by), (cx_, cy_) = cs
                    if (bx - ax) * (cy_ - ay) - (by - ay) * (cx_ - ax) < 0:
                        cs = [cs[0], cs[2], cs[1]]
                    tri += [round(v, 1) for x, y in cs for v in (x, -y)]
        if tri:
            areas.append([k, tri])
no_house_zone = prep(unary_union(no_house)) if no_house else None
print("land-use areas:", len(areas), "no-house polygons:", len(no_house))

# ---------------------------------------------------------------- real places (Overture places)
places = json.load(open(PLACES))
def place_xy(o):
    e, n = to_local.transform(o["x"], o["y"])
    return e, n
mosques, fuel, poi = [], [], []
for o in places:
    e, n = place_xy(o)
    if abs(e) > HALF - 300 or abs(n) > HALF - 300:
        continue
    if o["cat"] in ("muslim_place_of_worship",) and o["conf"] >= 0.4:
        if all(math.hypot(e - a, n - b) > 60 for a, b, _ in mosques):
            mosques.append((e, n, o["name"]))
    elif o["cat"] == "gas_station" and o["conf"] >= 0.6:
        if all(math.hypot(e - a, n - b) > 60 for a, b, _ in fuel):
            fuel.append((e, n, o["name"]))
    if o["cat"] and o["conf"] >= 0.5:
        poi.append((e, n))
print("mosques:", len(mosques), "fuel stations:", len(fuel), "shops/services:", len(poi))
from scipy.spatial import cKDTree
poi_tree = cKDTree(np.array(poi)) if poi else None
special_zone = prep(unary_union([Point(e, n).buffer(30) for e, n, _ in mosques + fuel])) if mosques or fuel else None

# ---------------------------------------------------------------- buildings
rng = np.random.default_rng(206)
# [x, z, w(along yaw), d, yaw_deg, h, src(, base)]  src 0 = OSM footprint, 1 = estimated, 2 mosque hall,
# 3 minaret, 4 school / hospital / kiosk, 5 industrial shed, 6 fuel station canopy (base = height above ground)
blds = []
bld = json.load(open(BLD))
osm_polys = []
for b in bld:
    g = geom_local(WKT.loads(b["wkt"]))
    if g.geom_type != "Polygon" or g.area < 12:
        continue
    osm_polys.append(g)
    r = g.minimum_rotated_rectangle
    cc = list(r.exterior.coords)
    e1 = np.array(cc[1]) - np.array(cc[0]); e2 = np.array(cc[2]) - np.array(cc[1])
    yaw = math.degrees(math.atan2(e1[0], e1[1]))
    h = b["height"] or (b["floors"] * 3.2 if b["floors"] else (14.0 if b["class"] in ("mosque",) else 7.0))
    blds.append([g.centroid.x, -g.centroid.y, float(np.linalg.norm(e1)), float(np.linalg.norm(e2)), yaw, float(h), 0])
osm_union = prep(unary_union(osm_polys).buffer(4)) if osm_polys else None
keep_out = prep(unary_union([LineString([sw, ne]).buffer(RW_W / 2 + 60, cap_style=2), paved.buffer(18.0), Point(0, 0).buffer(60), Point(70, -70).buffer(130)]))
# estimated houses: one block per 22 m cell where WorldCover says "built-up" (class 50)
STEP = 15.0       # Moroccan towns are dense: terraced 1-4 storey houses
cells = int(SIZE / STEP)
lc_res = SIZE / LC_N
for cj in range(cells):
    for ci in range(cells):
        e = -HALF + (ci + 0.5) * STEP
        n = HALF - (cj + 0.5) * STEP
        if abs(e) > HALF - 200 or abs(n) > HALF - 200:
            continue
        i0 = int((e + HALF - STEP / 2) / lc_res); j0 = int((HALF - n - STEP / 2) / lc_res)
        k = max(1, int(STEP / lc_res))
        patch = lc[j0:j0 + k, i0:i0 + k]
        frac = (patch == 50).mean() if patch.size else 0
        if frac < 0.5 or rng.random() > 0.9:
            continue
        p = Point(e, n)
        if keep_out.contains(p) or road_zone.contains(p) or (osm_union and osm_union.contains(p)):
            continue
        if (no_house_zone and no_house_zone.contains(p)) or (special_zone and special_zone.contains(p)):
            continue
        w = rng.uniform(11, 15); d = rng.uniform(11, 15)
        storeys = rng.choice([1, 2, 2, 3, 3, 4], p=[0.18, 0.3, 0.2, 0.17, 0.1, 0.05])
        # busier streets (many shops, cafes, banks nearby) have taller buildings
        if poi_tree is not None:
            busy = len(poi_tree.query_ball_point((e, n), 250))
            if busy >= 12 and rng.random() < 0.7:
                storeys += 1 + int(busy >= 30 and rng.random() < 0.5)
        blds.append([e + rng.uniform(-1, 1), -n + rng.uniform(-1, 1), w, d, 0.0, float(storeys * 3.1), 1])
# real landmarks from Overture places / OSM land use
def add_block(e, n, w, d, yaw, h, src, base=0.0):
    b = [e, -n, float(w), float(d), float(yaw), float(h), src]
    if base:
        b.append(float(base))
    blds.append(b)
for e, n, _ in mosques:
    yaw = float(rng.uniform(0, 90))
    a = math.radians(yaw)
    ux, uy = math.sin(a), math.cos(a)       # along w
    vx, vy = math.cos(a), -math.sin(a)      # along d
    add_block(e, n, 24, 22, yaw, 8.5, 2)
    mx, my = e + ux * 13 + vx * 12, n + uy * 13 + vy * 12          # minaret at one corner
    add_block(mx, my, 5, 5, yaw, 24, 3)
    add_block(mx, my, 3.6, 3.6, yaw, 4.5, 3, base=24)
for e, n, _ in fuel:
    yaw = float(rng.uniform(0, 90))
    add_block(e, n, 24, 13, yaw, 0.9, 6, base=4.8)
    a = math.radians(yaw)
    add_block(e + math.cos(a) * 14, n - math.sin(a) * 14, 10, 7, yaw, 3.8, 4)
for c, name, pg in lu_polys:
    if c not in ("school", "college", "university", "hospital", "industrial"):
        continue
    rr = pg.minimum_rotated_rectangle
    cc = np.array(rr.exterior.coords)[:4]
    e1 = cc[1] - cc[0]; e2 = cc[2] - cc[1]
    if np.linalg.norm(e1) < np.linalg.norm(e2):
        e1, e2 = e2, e1
    L = float(np.linalg.norm(e1)); W = float(np.linalg.norm(e2))
    if L < 20 or W < 15:
        continue
    u = e1 / L; v = e2 / W
    ctr = np.array(pg.representative_point().coords[0]) if not pg.contains(Point(cc.mean(axis=0))) else cc.mean(axis=0)
    yaw = math.degrees(math.atan2(u[0], u[1]))
    if c == "industrial":
        # sheds in rows, 50 x 28 m
        for a in np.arange(-L / 2 + 30, L / 2 - 25, 62):
            for b in np.arange(-W / 2 + 20, W / 2 - 15, 40):
                q = ctr + u * a + v * b
                if pg.contains(Point(q)):
                    add_block(q[0], q[1], 50, 28, yaw, float(rng.uniform(7, 11)), 5)
        continue
    storeys = 3 if c == "hospital" else 2
    blen = min(L * 0.65, 90.0); bdep = 16.0 if c == "hospital" else 11.0
    rows = [-W * 0.25, W * 0.25] if W > 55 else [-W * 0.5 + bdep * 0.5 + 6]
    for b in rows:
        q = ctr + v * b
        if pg.contains(Point(q)):
            add_block(q[0], q[1], blen, bdep, yaw, storeys * 3.4, 4)
print("landmark buildings:", sum(1 for b in blds if b[6] >= 2))
est = [b for b in blds if b[6] == 1]
rng.shuffle(est)   # random order: the low graphics presets draw only the first part
blds = [b for b in blds if b[6] != 1] + est
print("buildings: %d OSM + %d estimated" % (sum(1 for b in blds if b[6] == 0), sum(1 for b in blds if b[6] == 1)))

# ---------------------------------------------------------------- trees (WorldCover class 10 = tree cover)
trees = []
TSTEP = 14.0
tc = int(SIZE / TSTEP)
for cj in range(tc):
    for ci in range(tc):
        e = -HALF + (ci + 0.5) * TSTEP
        n = HALF - (cj + 0.5) * TSTEP
        li = int((e + HALF) / lc_res); lj = int((HALF - n) / lc_res)
        if lc[min(lj, LC_N - 1), min(li, LC_N - 1)] != 10 or rng.random() > 0.55:
            continue
        p = Point(e, n)
        if keep_out.contains(p) or road_zone.contains(p):
            continue
        trees.append([round(e + rng.uniform(-5, 5), 1), round(-n + rng.uniform(-5, 5), 1), round(float(rng.uniform(0.7, 1.4)), 2)])
# real single trees and tree rows (OSM via Overture base/land)
nreal = 0
for r in json.load(open(LANDF)):
    if r["subtype"] != "tree":
        continue
    g = geom_local(WKT.loads(r["wkt"]))
    pts = []
    if g.geom_type == "Point":
        pts = [(g.x, g.y)]
    elif g.geom_type == "LineString":
        pts = [g.interpolate(t).coords[0] for t in np.arange(0, g.length + 0.1, 7.0)]
    for e, n in pts:
        if abs(e) < HALF - 50 and abs(n) < HALF - 50:
            trees.append([round(e, 1), round(-n, 1), round(float(rng.uniform(0.8, 1.2)), 2)])
            nreal += 1
print("trees:", len(trees), "of which real OSM trees/rows:", nreal)

# ---------------------------------------------------------------- landing sites for the lessons
def h_at(x, z):
    return float(grid_h(heights, x, -z))
# Field LZ: a flat open spot about 1.5 km north of the main helipad (lesson E1 "fly 1.5 km north")
best = None
MAIN = (70.0, 70.0)
bxz = np.array([[b[0], b[1]] for b in blds])
for dz in range(int(MAIN[1]) - 1700, int(MAIN[1]) - 1300, 20):
    for dx in range(int(MAIN[0]) - 300, int(MAIN[0]) + 301, 20):
        if np.min(np.hypot(bxz[:, 0] - dx, bxz[:, 1] - dz)) < 80:
            continue
        li = int((dx + HALF) / lc_res); lj = int((dz + HALF) / lc_res)
        patch = lc[lj - 5:lj + 6, li - 5:li + 6]
        if (patch == 50).any() or (patch == 10).any():
            continue
        hs = [h_at(dx + a, dz + b) for a in (-40, 0, 40) for b in (-40, 0, 40)]
        rough = max(hs) - min(hs) + abs(dx - MAIN[0]) * 0.004 + abs(dz - MAIN[1] + 1500) * 0.004
        if best is None or rough < best[0]:
            best = (rough, dx, dz)
field = [best[1], best[2]]
# Pinnacle LZ: highest point of the map away from the edges
inner = heights[40:-40, 40:-40]
jj, ii = np.unravel_index(np.argmax(inner), inner.shape)
pin = [-HALF + (ii + 40) * CELL, -HALF + (jj + 40) * CELL]
print("field LZ", field, "pinnacle", pin, "%.0f m" % heights[jj + 40, ii + 40])

# ---------------------------------------------------------------- write
q = np.clip(np.round(heights / HSCALE), 0, 65535).astype("<u2")
open(os.path.join(OUT, "height.bin"), "wb").write(q.tobytes())

def line_xz(g):
    return [[round(x, 2), round(-y, 2)] for x, y in g.coords]
landmarks = []
for b in bld:
    if b["name"]:
        g = geom_local(WKT.loads(b["wkt"]))
        landmarks.append({"name": b["name"], "x": round(g.centroid.x, 1), "z": round(-g.centroid.y, 1)})
cx, cz = ll2xz(-6.9063, 32.8811)
landmarks.append({"name": "Khouribga city centre", "x": round(cx, 1), "z": round(cz, 1)})
meta = {
    "name": "Khouribga - GMMK",
    "origin_lat": LAT0, "origin_lon": LON0, "size_m": SIZE, "n": N, "height_scale": HSCALE,
    "sources": {
        "elevation": "Copernicus GLO-30 DEM (ESA, 30 m) - surface model, flattened by the sim on paved areas",
        "photo": "Sentinel-2 L2A surface reflectance, median of 4 clear days per season (spring: Mar-Apr 2025, summer: Jul-Aug 2025), natural colour, 10 m",
        "roads": "OpenStreetMap contributors (ODbL) via Overture Maps 2026-11-18.0",
        "land_cover": "ESA WorldCover 2021 v200 (10 m): built-up -> estimated houses, tree cover -> trees",
        "land_use": "OpenStreetMap contributors (ODbL) via Overture Maps: parks, pitches, cemeteries, schools, hospitals, industry, tree rows",
        "places": "Overture Maps places (CDLA Permissive 2.0): mosques, fuel stations, shop density for building heights",
        "airport": "OpenStreetMap contributors (ODbL) via Overture Maps 2026-11-18.0; runway size from OpenAIP",
    },
    "airport": {
        "icao": "GMMK", "name": "Khouribga (military aerodrome)", "elevation_ft_published": 2552,
        "runway": {"ends": [[round(sw[0], 2), round(-sw[1], 2)], [round(ne[0], 2), round(-ne[1], 2)]], "width": RW_W,
                   "length_osm": round(rw_len, 1), "true_heading": round(rw_hdg, 1), "designators": ["05", "23"]},
        "taxiways": [line_xz(t) for t in feat["taxiway"]], "taxiway_width": TW_W,
        "aprons": [[[round(x, 2), round(-y, 2)] for x, y in a.exterior.coords] for a in feat["apron"]],
        "helipads": [[round(h.x, 2), round(-h.y, 2)] for h in feat["helipad"]],
    },
    # "Main helipad" (where the sim starts and the lessons run) is a sim-placed training pad on open ground
    # 100 m SE of the real apron helipad, so the hover sight gates to the north are not inside the hangar
    # that stands 40 m north of the real pad. "Apron helipad" is the real one (OSM position).
    "pads": {"Main helipad": [MAIN[0], MAIN[1], 26.0], "Apron helipad": [0.0, 0.0, 15.0], "Field LZ": [field[0], field[1], 20.0], "Pinnacle LZ": [pin[0], pin[1], 9.0]},
    "landmarks": landmarks + [{"name": nm or "Mosque", "x": round(e, 1), "z": round(-n, 1)} for e, n, nm in mosques],
    "areas": areas,
    "roads": roads,
    "photos": {"spring": "photo_spring_jpg.bin", "summer": "photo_summer_jpg.bin"},
    "buildings": [[round(v, 2) if isinstance(v, float) else v for v in b] for b in blds],
    "trees": trees,
}
json.dump(meta, open(os.path.join(OUT, "map.json"), "w"), separators=(",", ":"))
print("wrote", OUT, os.path.getsize(os.path.join(OUT, "map.json")) // 1024, "KB json")
