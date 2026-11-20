"""Helpers: region.json projection (lon/lat <-> sim map metres) and Esri tile cache names.
The sim saves HD tiles as user://hd_cache/<z>/<md5 of the tile URL>.img (tile_fetch.gd)."""
import hashlib, json, math, os

URL = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%d/%d/%d"
HERE = os.path.dirname(os.path.abspath(__file__))
REGION = os.path.join(HERE, "..", "..", "data", "maps", "khouribga", "region.json")

P = json.load(open(REGION))["proj"]
LON0, LAT0 = P["lon0"], P["lat0"]

def _poly(c, u, v):
    s, k = 0.0, 0
    for i in range(4):
        for j in range(4 - i):
            s += c[k] * u ** i * v ** j
            k += 1
    return s

def to_map(lon, lat):
    """lon/lat -> (x east, z south) sim metres"""
    u, v = lon - LON0, lat - LAT0
    return _poly(P["fwd_e"], u, v), -_poly(P["fwd_n"], u, v)

def to_lonlat(x, z):
    u, v = x / 1e4, -z / 1e4
    return LON0 + _poly(P["inv_lon"], u, v), LAT0 + _poly(P["inv_lat"], u, v)

def tile_lon(x, z):
    return x / float(1 << z) * 360.0 - 180.0

def tile_lat(y, z):
    return math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / float(1 << z)))))

def tile_xy(lon, lat, z):
    n = float(1 << z)
    lr = math.radians(lat)
    return (lon + 180.0) / 360.0 * n, (1.0 - math.log(math.tan(lr) + 1.0 / math.cos(lr)) / math.pi) * 0.5 * n

def cache_name(z, x, y):
    return hashlib.md5((URL % (z, y, x)).encode()).hexdigest() + ".img"

def index(z, half=8300.0):
    """{cache file name: (x, y)} for every tile of zoom z over the 16 km core"""
    lo0, la0 = to_lonlat(-half, -half)
    lo1, la1 = to_lonlat(half, half)
    tx0, ty0 = tile_xy(lo0, la0, z)
    tx1, ty1 = tile_xy(lo1, la1, z)
    out = {}
    for ty in range(int(min(ty0, ty1)), int(max(ty0, ty1)) + 1):
        for tx in range(int(min(tx0, tx1)), int(max(tx0, tx1)) + 1):
            out[cache_name(z, tx, ty)] = (tx, ty)
    return out
