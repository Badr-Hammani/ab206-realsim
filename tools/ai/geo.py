"""Mosaic pixel <-> sim map metres for a stitched zoom-z mosaic (tools/ai/mosaic.py)."""
import numpy as np, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import tiles

class Geo:
    def __init__(self, z, x0, y0):
        self.z, self.x0, self.y0 = z, x0, y0
        # affine fit map(x,z) -> pixel over a grid (error < 0.3 px over ~10 km, checked in fit_err)
        pts, pix = [], []
        for gx in np.linspace(-8000, 8000, 21):
            for gz in np.linspace(-8000, 8000, 21):
                lon, lat = tiles.to_lonlat(gx, gz)
                tx, ty = tiles.tile_xy(lon, lat, z)
                pts.append([gx, gz, 1.0]); pix.append([(tx - x0) * 256.0, (ty - y0) * 256.0])
        A = np.array(pts); P = np.array(pix)
        # quadratic terms for accuracy
        Q = np.column_stack([A[:, 0], A[:, 1], np.ones(len(A)), A[:, 0] ** 2, A[:, 0] * A[:, 1], A[:, 1] ** 2])
        self.c, *_ = np.linalg.lstsq(Q, P, rcond=None)
        self.fit_err = float(np.abs(Q @ self.c - P).max())
        Qi = np.column_stack([P[:, 0], P[:, 1], np.ones(len(P)), P[:, 0] ** 2, P[:, 0] * P[:, 1], P[:, 1] ** 2])
        self.ci, *_ = np.linalg.lstsq(Qi, A[:, :2], rcond=None)

    def to_px(self, x, z):
        x = np.asarray(x, float); z = np.asarray(z, float)
        Q = np.stack([x, z, np.ones_like(x), x * x, x * z, z * z], -1)
        return Q @ self.c

    def to_map(self, px, py):
        px = np.asarray(px, float); py = np.asarray(py, float)
        Q = np.stack([px, py, np.ones_like(px), px * px, px * py, py * py], -1)
        return Q @ self.ci
