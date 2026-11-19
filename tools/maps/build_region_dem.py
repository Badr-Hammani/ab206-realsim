"""Wide-area 3D terrain for the Khouribga map: the whole 98 x 98 km moving-map region at 32 m.
Source: Copernicus GLO-30 DEM (ESA, 30 m, surface model), tiles N32/N33 x W008/W007 from the
copernicus-dem-30m open bucket. Includes the open-cast phosphate mine pits east of Khouribga, the
plateau edge to the north and the hills around Oued Zem.
Output: data/maps/khouribga/region_height_png.bin = 16-bit heights (units of 0.25 m) packed in an
8-bit grey+alpha PNG, and a "dem" entry in region.json.
Pixel (i, j): i = east index, j = south index; x = -HALF + i * CELL, z = -HALF + j * CELL.
L channel = height high byte, A channel = low byte.
Usage: python build_region_dem.py <dir with N32_W008.tif N32_W007.tif N33_W008.tif N33_W007.tif> <map dir>
"""
import json, os, sys, io
import numpy as np, rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from pyproj import CRS
from PIL import Image

D, OUT = sys.argv[1:3]
HALF = 49152.0
CELL = 32.0
SCALE = 0.25
N = int(2 * HALF / CELL) + 1
LON0, LAT0 = -6.9504834, 32.8594064
local = CRS.from_proj4(f"+proj=aeqd +lat_0={LAT0} +lon_0={LON0} +x_0=0 +y_0=0 +ellps=WGS84 +units=m")
tf = from_origin(-HALF - CELL / 2, HALF + CELL / 2, CELL, CELL)
dem = np.full((N, N), np.nan, np.float32)
for t in ["N32_W008", "N32_W007", "N33_W008", "N33_W007"]:
    with rasterio.open(os.path.join(D, t + ".tif")) as s:
        tmp = np.full((N, N), np.nan, np.float32)
        reproject(rasterio.band(s, 1), tmp, dst_transform=tf, dst_crs=local, resampling=Resampling.cubic, dst_nodata=np.nan)
        dem = np.where(np.isnan(dem), tmp, dem)
assert not np.isnan(dem).any(), "DEM gap"
u = np.round(dem / SCALE).astype(np.uint16)       # row 0 = north edge = z -HALF
la = np.stack([(u >> 8).astype(np.uint8), (u & 255).astype(np.uint8)], -1)
b = io.BytesIO()
Image.fromarray(la, "LA").save(b, "PNG", optimize=True)
open(os.path.join(OUT, "region_height_png.bin"), "wb").write(b.getvalue())
rp = os.path.join(OUT, "region.json")
r = json.load(open(rp))
r["dem"] = {"file": "region_height_png.bin", "n": N, "cell": CELL, "scale": SCALE,
            "source": "Copernicus GLO-30 DEM (ESA, 30 m surface model), resampled to 32 m"}
json.dump(r, open(rp, "w"), separators=(",", ":"))
print("N %d, %.1f-%.1f m, %.1f MB" % (N, dem.min(), dem.max(), len(b.getvalue()) / 1e6))
