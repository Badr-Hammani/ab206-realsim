"""Stitch cached HD tiles of one zoom into one image. Usage: mosaic.py <cache dir> <z> <out.npz>"""
import os, sys
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(__file__))
import tiles

def build(cache, z):
    idx = tiles.index(z)
    have = {idx[f]: f for f in os.listdir(os.path.join(cache, str(z))) if f in idx}
    xs = [k[0] for k in have]; ys = [k[1] for k in have]
    x0, y0 = min(xs), min(ys)
    W, H = (max(xs) - x0 + 1) * 256, (max(ys) - y0 + 1) * 256
    img = np.zeros((H, W, 3), np.uint8)
    valid = np.zeros((H, W), np.uint8)
    for (tx, ty), f in have.items():
        t = cv2.imread(os.path.join(cache, str(z), f), cv2.IMREAD_COLOR)
        if t is None or t.shape[:2] != (256, 256):
            continue
        img[(ty - y0) * 256:(ty - y0 + 1) * 256, (tx - x0) * 256:(tx - x0 + 1) * 256] = t
        valid[(ty - y0) * 256:(ty - y0 + 1) * 256, (tx - x0) * 256:(tx - x0 + 1) * 256] = 1
    return img, valid, x0, y0

if __name__ == "__main__":
    img, valid, x0, y0 = build(sys.argv[1], int(sys.argv[2]))
    cv2.imwrite(sys.argv[3] + ".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 92])
    np.savez(sys.argv[3] + ".npz", valid=valid, x0=x0, y0=y0, z=int(sys.argv[2]))
    small = cv2.resize(img, (img.shape[1] // 10, img.shape[0] // 10), interpolation=cv2.INTER_AREA)
    cv2.imwrite(sys.argv[3] + "_small.jpg", small)
    print(img.shape, x0, y0)
