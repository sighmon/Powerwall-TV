# Bake Tesla's PanoramaSky rotation (env/mobile.tres New_Studio.png, rotation_degrees (0,-11,83) from
# MobileEnvTest/Snapshots PARKED) into a 2:1 equirect so SceneKit (no 3D env rotation) can use it.
# Godot 3 Basis(euler) = Ry * Rx * Rz. Sky is rotated by R: world dir d samples sky at R^T d.
# Panorama lookup (Godot 3): u = atan2(x, z) / 2pi (wrapped), v = acos(y) / pi.
import numpy as np, sys
from PIL import Image
src = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.float32) / 255
out_path = sys.argv[2]
W, H = int(sys.argv[3]) if len(sys.argv) > 3 else 1024, None
H = W // 2
rx, ry, rz = np.radians([0.0, -11.0, 83.0])
def Rx(a): c, s = np.cos(a), np.sin(a); return np.array([[1,0,0],[0,c,-s],[0,s,c]])
def Ry(a): c, s = np.cos(a), np.sin(a); return np.array([[c,0,s],[0,1,0],[-s,0,c]])
def Rz(a): c, s = np.cos(a), np.sin(a); return np.array([[c,-s,0],[s,c,0],[0,0,1]])
R = Ry(ry) @ Rx(rx) @ Rz(rz)
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
U, V = np.meshgrid(u, v)
phi = U * 2 * np.pi; theta = V * np.pi
d = np.stack([np.sin(theta) * np.sin(phi), np.cos(theta), np.sin(theta) * np.cos(phi)], -1)
s = d @ R  # row vectors: (R^T d)^T = d^T R
su = (np.arctan2(s[..., 0], s[..., 2]) / (2 * np.pi)) % 1.0
sv = np.arccos(np.clip(s[..., 1], -1, 1)) / np.pi
sh, sw = src.shape[:2]
x = su * sw - 0.5; y = sv * sh - 0.5
x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int); fx = (x - x0)[..., None]; fy = (y - y0)[..., None]
def px(yy, xx): return src[np.clip(yy, 0, sh - 1), xx % sw]
img = (px(y0, x0) * (1 - fx) * (1 - fy) + px(y0, x0 + 1) * fx * (1 - fy) + px(y0 + 1, x0) * (1 - fx) * fy + px(y0 + 1, x0 + 1) * fx * fy)
Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out_path)
print(out_path, img.mean())
