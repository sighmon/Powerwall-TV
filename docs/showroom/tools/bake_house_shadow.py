"""Bake Home_GroundShadow.png from the Shadow.png inside ResidentialClassic.usdz.

Tesla's CompactShadow.shader draws the house's Shadow card black with
ALPHA = pow(1 - texture.g, exponent) * strength. ResidentialClassic.tscn sets
strength 2 and exponent 1. SceneKit has no such shader on a plain material, so this
writes the result as a black RGBA image, the same form as the showroom's Ground_AO
contact shadows. 512 px is plenty for a blur this soft.

    python bake_house_shadow.py Powerwall-TV/TeslaAssets/ResidentialClassic.usdz Powerwall-TV/TeslaAssets/Home_GroundShadow.png
"""
import io, sys, zipfile
import numpy as np
from PIL import Image

STRENGTH, EXPONENT, SIZE = 2.0, 1.0, 512

usdz, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(usdz) as z:
    name = next(n for n in z.namelist() if n.endswith('Shadow.png') and 'Vehicle' not in n)
    src = Image.open(io.BytesIO(z.read(name))).convert('RGBA').resize((SIZE, SIZE), Image.LANCZOS)
px = np.asarray(src, dtype=np.float32) / 255
# The converter already stored Tesla's shade as black + alpha (alpha = 1 - G). Fall back to the
# green channel for an untouched Tesla texture (white = no shade).
shade = px[..., 3] if px[..., :3].max() < 0.01 else 1 - px[..., 1]
alpha = np.clip(np.power(shade, EXPONENT) * STRENGTH, 0, 1)
rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
rgba[..., 3] = np.round(alpha * 255).astype(np.uint8)
Image.fromarray(rgba, 'RGBA').save(out, optimize=True)
print(out, 'max alpha', rgba[..., 3].max(), 'share above 3%', round(float((rgba[..., 3] > 8).mean()), 3))
