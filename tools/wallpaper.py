"""ruxchipher Tokyo Night wallpaper: flowing contour lines + the Arch logo kept in its original spot."""
import sys
import numpy as np
from PIL import Image, ImageFilter

W, H = 3840, 2160                      # 2x the 1920x1080 screen
SRC = sys.argv[1]                      # original geology.png (5120x2880) for the logo
OUT = sys.argv[2]
rng = np.random.default_rng(23)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32) / 255


BG0, BG1 = hexc('#1a1b26'), hexc('#101119')
CYAN, BLUE, PURPLE, FG = hexc('#7dcfff'), hexc('#7aa2f7'), hexc('#bb9af7'), hexc('#c0caf5')

y, x = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = x / W, y / H


def smoothstep(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def noise(cells_x, cells_y):
    """Smooth value noise in [-1, 1]: a small random grid upsampled bicubically in float (no banding)."""
    small = rng.uniform(-1, 1, (cells_y, cells_x)).astype(np.float32)
    return np.asarray(Image.fromarray(small, 'F').resize((W, H), Image.BICUBIC), dtype=np.float32)


# ---------------------------------------------------------------- base
img = BG0 * (1 - (0.6 * u + 0.4 * v))[..., None] + BG1 * (0.6 * u + 0.4 * v)[..., None]


def glow(cx, cy, r, color, strength):
    d = np.sqrt(((x - cx) / r) ** 2 + ((y - cy) / r) ** 2)
    return (np.exp(-d * d) * strength)[..., None] * color


img += glow(0.20 * W, 0.30 * H, 0.35 * W, CYAN, 0.06)
img += glow(0.92 * W, 0.95 * H, 0.45 * W, PURPLE, 0.09)
img += glow(0.75 * W, 0.05 * H, 0.35 * W, BLUE, 0.05)

# ---------------------------------------------------------------- flowing contours
field = v * 46 + noise(7, 5) * 7.0 + noise(16, 10) * 1.6 + np.sin(u * 9.0 + v * 3.0) * 0.8
gy, gx = np.gradient(field)
grad = np.sqrt(gx * gx + gy * gy) + 1e-6
frac = field - np.floor(field)
dist = np.minimum(frac, 1 - frac) / grad          # distance to nearest isoline, in px
line = np.clip(1.4 - dist, 0, 1)                   # ~1.4px antialiased line

major = (np.floor(field + 0.5).astype(np.int32) % 6 == 0)
weight = np.where(major, 0.7, 0.24)

# empty on the left (like the original), dense from the middle to the right
reveal = smoothstep(0.28, 0.62, u + noise(5, 4) * 0.06)
fade_tb = smoothstep(0.0, 0.08, v) * smoothstep(1.0, 0.92, v)
alpha = line * weight * reveal * fade_tb

t = np.clip((u - 0.3) / 0.7 + noise(6, 4) * 0.25, 0, 1)
col = np.where((t < 0.5)[..., None],
               CYAN * (1 - t * 2)[..., None] + BLUE * (t * 2)[..., None],
               BLUE * (2 - t * 2)[..., None] + PURPLE * (t * 2 - 1)[..., None])
img = img * (1 - alpha[..., None]) + col * alpha[..., None]

# faint grid, strongest around the middle
grid = ((x % 96 < 2) | (y % 96 < 2)).astype(np.float32)
img += (grid * 0.018 * smoothstep(0.1, 0.5, u) * fade_tb)[..., None] * BLUE

# ---------------------------------------------------------------- Arch logo (same place as before)
src = Image.open(SRC).convert('L')
sx = src.width / W                                 # 5120 -> 3840
box = (440, 720, 1440, 1050)                       # logo area in the 5120x2880 original
crop = src.crop(box).resize((round((box[2] - box[0]) / sx), round((box[3] - box[1]) / sx)), Image.LANCZOS)
ox, oy = round(box[0] / sx), round(box[1] / sx)
mask = np.zeros((H, W), np.float32)
m = np.asarray(crop, dtype=np.float32) / 255
mask[oy:oy + m.shape[0], ox:ox + m.shape[1]] = m

halo = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(28)),
                  dtype=np.float32) / 255
img += (halo * 0.55)[..., None] * CYAN * 0.6

lt = np.clip((x - ox) / m.shape[1], 0, 1)
logo_col = CYAN * (1 - lt)[..., None] + PURPLE * lt[..., None]
logo_col = logo_col * 0.75 + FG * 0.25
img = img * (1 - mask[..., None]) + logo_col * mask[..., None]

# ---------------------------------------------------------------- finish
vig = 1 - 0.35 * smoothstep(0.55, 1.15, np.sqrt((u - 0.5) ** 2 * 1.2 + (v - 0.5) ** 2 * 1.6) * 1.6)
img *= vig[..., None]
img += rng.normal(0, 0.006, img.shape).astype(np.float32)   # grain, stops gradient banding

Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGB').save(OUT, optimize=True)
print('saved', OUT)
