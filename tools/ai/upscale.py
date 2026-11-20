"""AI-sharpen the cached 0.5 m (zoom 18) aerial photo to 0.25 m look (Real-ESRGAN general x4v3 model,
run x4 then averaged down to x2). Same layout and same objects: the network only sharpens edges and
texture, it cannot add things the photo does not show.
Usage: upscale.py <hd_cache dir> <weights realesr-general-x4v3.pth> <out dir> [max tiles]
Writes <out>/<x>_<y>.webp, 512 x 512, one per zoom-18 tile; the sim loads them from
user://hd_cache/sr18/ in place of the 256 px tile (scripts/world/hd_ground.gd)."""
import os, sys, time
import numpy as np, cv2, torch, torch.nn as nn, torch.nn.functional as F
sys.path.insert(0, os.path.dirname(__file__))
import mosaic

class SRVGG(nn.Module):
    def __init__(s, nf=64, nc=32, up=4):
        super().__init__()
        s.up = up
        b = [nn.Conv2d(3, nf, 3, 1, 1), nn.PReLU(nf)]
        for _ in range(nc):
            b += [nn.Conv2d(nf, nf, 3, 1, 1), nn.PReLU(nf)]
        b += [nn.Conv2d(nf, 3 * up * up, 3, 1, 1)]
        s.body = nn.ModuleList(b)
        s.ps = nn.PixelShuffle(up)
    def forward(s, x):
        o = x
        for l in s.body:
            o = l(o)
        return s.ps(o) + F.interpolate(x, scale_factor=s.up, mode="nearest")

PAD = 16      # source pixels of neighbour tiles fed in, so tile edges match

def main():
    cache, wpath, out = sys.argv[1], sys.argv[2], sys.argv[3]
    lim = int(sys.argv[4]) if len(sys.argv) > 4 else 10 ** 9
    os.makedirs(out, exist_ok=True)
    m = SRVGG()
    sd = torch.load(wpath, map_location="cpu")
    m.load_state_dict(sd.get("params", sd.get("params_ema", sd)))
    m.eval()
    torch.set_num_threads(os.cpu_count())
    img, valid, x0, y0 = mosaic.build(cache, 18)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    big = cv2.copyMakeBorder(rgb, PAD, PAD, PAD, PAD, cv2.BORDER_REFLECT)
    H, W = valid.shape
    todo = [(tx, ty) for ty in range(H // 256) for tx in range(W // 256) if valid[ty * 256 + 128, tx * 256 + 128]]
    t0 = time.time(); n = 0
    for tx, ty in todo[:lim]:
        f = os.path.join(out, "%d_%d.webp" % (x0 + tx, y0 + ty))
        if os.path.exists(f):
            continue
        a = big[ty * 256:ty * 256 + 256 + 2 * PAD, tx * 256:tx * 256 + 256 + 2 * PAD]
        x = torch.from_numpy(a.astype(np.float32) / 255).permute(2, 0, 1)[None]
        with torch.no_grad():
            o = m(x).clamp(0, 1)[0].permute(1, 2, 0).numpy()
        o = o[PAD * 4:PAD * 4 + 1024, PAD * 4:PAD * 4 + 1024]
        o = cv2.resize(o, (512, 512), interpolation=cv2.INTER_AREA)
        o = cv2.cvtColor((o * 255).round().astype(np.uint8), cv2.COLOR_RGB2BGR)
        cv2.imwrite(f, o, [cv2.IMWRITE_WEBP_QUALITY, 82])
        n += 1
        if n % 100 == 0:
            print("%d / %d tiles, %.1f s each" % (n, len(todo), (time.time() - t0) / n), flush=True)
    print("done", n, "tiles")

if __name__ == "__main__":
    main()
