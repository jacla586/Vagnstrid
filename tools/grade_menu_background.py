"""HDR-like grade of the main menu picture: lifts shadows locally (the big-scale
brightness is compressed, fine detail kept or boosted), then vibrance and a gentle
S-curve, so the dusk colours stand out of the dark.
    geodata/.venv/bin/python tools/grade_menu_background.py [strength]
Reads assets/ui/raw/menu_background.jpg (the render, from render_menu_background.gd),
writes assets/ui/menu_background.jpg."""
import sys
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

SRC = "assets/ui/raw/menu_background.jpg"
DST = "assets/ui/menu_background.jpg"
strength = float(sys.argv[1]) if len(sys.argv) > 1 else 0.6

BASE_SIGMA_PX = 60.0       # what counts as "big-scale" brightness
BASE_COMPRESS = 0.6       # base layer in log space is scaled by this (1 = unchanged)
DETAIL_BOOST = 1.5        # local contrast
TARGET_MID = 0.30          # where the base's average lands
VIBRANCE = 0.35            # extra saturation, most for dull colours
CURVE = 0.18               # S-curve strength

img = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32) / 255.0
lin = img ** 2.2
lum = 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]
log_l = np.log2(np.maximum(lum, 1e-4))
base = gaussian_filter(log_l, BASE_SIGMA_PX)
detail = log_l - base
mean_base = base.mean()
compress = 1.0 - (1.0 - BASE_COMPRESS) * strength
boost = 1.0 + (DETAIL_BOOST - 1.0) * strength
new_log = (base - mean_base) * compress + detail * boost
new_log += np.log2(TARGET_MID ** 2.2) * strength + mean_base * (1.0 - strength)
new_lum = np.exp2(new_log)
ratio = new_lum / np.maximum(lum, 1e-4)
out = lin * ratio[..., None]
# Soft shoulder so highlights (sky, flashes) don't clip.
out = out / (1.0 + out * 0.35) * 1.35
out = np.clip(out, 0.0, 1.0) ** (1.0 / 2.2)
# Vibrance: push saturation, more where it is low.
grey = out.mean(axis=2, keepdims=True)
sat = (out.max(axis=2, keepdims=True) - out.min(axis=2, keepdims=True))
out = grey + (out - grey) * (1.0 + VIBRANCE * strength * (1.0 - sat))
# Gentle S-curve round the middle.
out = np.clip(out, 0.0, 1.0)
out = out + CURVE * strength * out * (1.0 - out) * (2.0 * out - 1.0) * 2.0
Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).save(DST, quality=92)
print("wrote", DST)
