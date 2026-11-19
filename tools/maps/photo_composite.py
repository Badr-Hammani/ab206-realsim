"""Cloud-free natural-colour photo for a real map from several clear Sentinel-2 L2A days.

Median of the surface reflectance bands B04/B03/B02 (10 m) over the chosen dates removes haze,
shadows of small clouds and one-day noise; a gentle sRGB curve gives natural colours instead of
the over-saturated "TCI" quick-look. Writes <out>/photo_<season>_jpg.bin (2048 px, 8 m per pixel).
Usage: python photo_composite.py <out_dir> <season> <item> [<item> ...]
       item = YYYY/M/S2X_29SPS_YYYYMMDD_0_L2A
With REGION=1 in the environment it instead writes region_<season>_jpg.bin: 98 x 98 km at 16 m per pixel
for the moving map, from the same dates on tiles 29SPS and 29SQS (full 10 m bands, averaged).
"""
import sys, io, os
import numpy as np
import rasterio
import rasterio.errors
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from pyproj import CRS
from PIL import Image, ImageFilter

OUT, SEASON, ITEMS = sys.argv[1], sys.argv[2], sys.argv[3:]
LON0, LAT0 = -6.9504834, 32.8594064
REGION = os.environ.get("REGION") == "1"
SIZE = 98304.0 if REGION else 16384.0
PX = 6144 if REGION else 2048
local = CRS.from_proj4(f"+proj=aeqd +lat_0={LAT0} +lon_0={LON0} +x_0=0 +y_0=0 +ellps=WGS84 +units=m")
tf = from_origin(-SIZE / 2, SIZE / 2, SIZE / PX, SIZE / PX)
B = "/vsicurl/https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/"
TILES = [("29SPS", "29/S/PS/"), ("29SQS", "29/S/QS/")] if REGION else [("29SPS", "29/S/PS/")]
os.environ.setdefault("GDAL_CACHEMAX", "256")
# one band at a time over all dates, so the 98 km region fits in memory (median per band)
refl = np.zeros((3, PX, PX), np.float32)
for k, band in enumerate(["B04", "B03", "B02"]):
    stack = []
    for it in ITEMS:
        layer = np.full((PX, PX), np.nan, np.float32)
        for code, path in TILES:
            src = None
            for variant in (it.replace("29SPS", code), it.replace("29SPS", code).replace("_0_L2A", "_1_L2A")):
                try:
                    src = rasterio.open(f"{B}{path}{variant}/{band}.tif")
                    break
                except rasterio.errors.RasterioIOError:
                    src = None
            if src is None:
                print("missing", code, it)
                continue
            with src:
                arr = src.read(1)
                part = np.full((PX, PX), np.nan, np.float32)
                reproject(arr, part, src_transform=src.transform, src_crs=src.crs, dst_transform=tf, dst_crs=local,
                          resampling=Resampling.cubic if not REGION else Resampling.average, src_nodata=0, dst_nodata=np.nan)
                del arr
            layer = np.where(np.isnan(layer), part, layer)
            del part
        # Earth Search COGs already have the baseline-04 BOA offset removed (earthsearch:boa_offset_applied)
        stack.append(layer / 10000.0)
        print("read", band, it.split("/")[-1], float(np.nanmean(stack[-1])), flush=True)
    refl[k] = np.nanmedian(np.stack(stack), axis=0)
    del stack
refl = np.nan_to_num(refl, nan=0.15)
# natural colour: linear exposure, slight atmospheric dehaze on blue, sRGB-like gamma, soft shoulder
exp = 2.2
refl[2] = np.maximum(refl[2] - 0.010, 0)
x = np.clip(refl * exp, 0, None)
x = x / (1 + 0.18 * x)               # soft highlight roll-off (bright soils and roofs keep detail)
srgb = np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)
lum = srgb.mean(axis=0, keepdims=True)
srgb = lum + (srgb - lum) * 1.05
srgb = 0.5 + (srgb - 0.5) * 1.15      # a little contrast: the sim's haze and tonemapper flatten it again
img = Image.fromarray((np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8).transpose(1, 2, 0))
img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
buf = io.BytesIO()
img.save(buf, "JPEG", quality=88)
open(os.path.join(OUT, f"{'region' if REGION else 'photo'}_{SEASON}_jpg.bin"), "wb").write(buf.getvalue())
img.resize((1024, 1024)).save(os.path.join(OUT, f"../../../../preview_{SEASON}.png") if False else f"/tmp/claude-0/preview_{'region_' if REGION else ''}{SEASON}.png")
print("wrote", SEASON, len(buf.getvalue()) // 1024, "KB")
