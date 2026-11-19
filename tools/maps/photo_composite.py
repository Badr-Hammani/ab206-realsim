"""Cloud-free natural-colour photo for a real map from several clear Sentinel-2 L2A days.

Median of the surface reflectance bands B04/B03/B02 (10 m) over the chosen dates removes haze,
shadows of small clouds and one-day noise; a gentle sRGB curve gives natural colours instead of
the over-saturated "TCI" quick-look. Writes <out>/photo_<season>_jpg.bin (2048 px, 8 m per pixel).
Usage: python photo_composite.py <out_dir> <season> <item> [<item> ...]
       item = YYYY/M/S2X_29SPS_YYYYMMDD_0_L2A
"""
import sys, io, os
import numpy as np
import rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from pyproj import CRS
from PIL import Image, ImageFilter

OUT, SEASON, ITEMS = sys.argv[1], sys.argv[2], sys.argv[3:]
LON0, LAT0 = -6.9504834, 32.8594064
SIZE = 16384.0
PX = 2048
local = CRS.from_proj4(f"+proj=aeqd +lat_0={LAT0} +lon_0={LON0} +x_0=0 +y_0=0 +ellps=WGS84 +units=m")
tf = from_origin(-SIZE / 2, SIZE / 2, SIZE / PX, SIZE / PX)
B = "/vsicurl/https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/29/S/PS/"
stack = []
for it in ITEMS:
    name = it.split("/")[-1]
    rgb = np.zeros((3, PX, PX), np.float32)
    for k, band in enumerate(["B04", "B03", "B02"]):
        with rasterio.open(f"{B}{it}/{band}.tif") as src:
            reproject(rasterio.band(src, 1), rgb[k], dst_transform=tf, dst_crs=local, resampling=Resampling.cubic, src_nodata=0, dst_nodata=np.nan)
    # Earth Search COGs already have the baseline-04 BOA offset removed (earthsearch:boa_offset_applied)
    rgb = rgb / 10000.0
    stack.append(rgb)
    print("read", name, np.nanmean(rgb, axis=(1, 2)).round(3))
refl = np.nanmedian(np.stack(stack), axis=0)
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
open(os.path.join(OUT, f"photo_{SEASON}_jpg.bin"), "wb").write(buf.getvalue())
img.resize((1024, 1024)).save(os.path.join(OUT, f"../../../../preview_{SEASON}.png") if False else f"/tmp/claude-0/preview_{SEASON}.png")
print("wrote", SEASON, len(buf.getvalue()) // 1024, "KB")
