"""Take the baked wheels out of each car usdz and add four empty wheel anchors.

The car files were built with one wheel style merged into their Wheels and Tires meshes. The app now
mounts the car's own wheels at runtime (VehicleWheels.swift), so this removes the Wheels mesh, removes
every Tires triangle inside a wheel (Cybertruck's Tires mesh also holds body rubber, which stays), and
adds Xforms WheelAnchor_LF/RF/LR/RR with the Tesla app's Wheel_*_Spatial transforms in the car's
frame (nose -Z, +X right, metres). Anchor +Z points out of the car on both sides (a 180 degree turn
on the left, never a negative scale). Idempotent: an already stripped file is only re-anchored.

Usage: python strip_wheels.py TeslaAssets_dir [car ...]
"""
import os, sys, shutil, tempfile, zipfile, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pxr import Usd, UsdGeom, Gf, Vt, UsdUtils
import anchors as A

CARS = ['Model3', 'Model3Highland', 'ModelY', 'ModelYJuniper', 'ModelS', 'ModelX', 'Cybertruck']

def car_anchors(car):
    a, _ = A.anchors(car)
    if 'LR' not in a:  # Bayberry's LR comes from its glTF base scene: the LF turn at the RR axle
        m = a['LF'].copy(); m[2, 3] = a['RR'][2, 3]; a['LR'] = m
    return a

def in_wheel(points, M, radius, inner=-0.13, outer=0.26):
    """Points inside the tyre cylinder of the anchor M (wheel frame: +Z outward)."""
    inv = np.linalg.inv(M)
    local = (np.c_[points, np.ones(len(points))] @ inv.T)[:, :3]
    scale = np.linalg.norm(M[:3, 1])
    r = np.hypot(local[:, 0], local[:, 1]) * scale
    return (r < radius) & (local[:, 2] > inner) & (local[:, 2] < outer)

def strip(assets, car):
    usdz = os.path.join(assets, car + '.usdz')
    work = tempfile.mkdtemp(prefix='strip_' + car)
    try:
        with zipfile.ZipFile(usdz) as z: z.extractall(work)
        layer = next(n for n in os.listdir(work) if n.endswith(('.usdc', '.usda')))
        st = Usd.Stage.Open(os.path.join(work, layer))
        root = st.GetDefaultPrim(); rp = root.GetPath()
        anchors = car_anchors(car)
        removed = {}; mesh_holder = []
        w = st.GetPrimAtPath(rp.AppendChild('Wheels'))
        if w: removed['Wheels'] = len(UsdGeom.Mesh(w).GetFaceVertexCountsAttr().Get()); st.RemovePrim(w.GetPath())
        t = st.GetPrimAtPath(rp.AppendChild('Tires'))
        if t:
            mesh = UsdGeom.Mesh(t)
            P = np.array(mesh.GetPointsAttr().Get(), np.float64)
            F = np.array(mesh.GetFaceVertexIndicesAttr().Get(), np.int64).reshape(-1, 3)
            c = P[F].mean(1)
            radius = 0.47 if car == 'Cybertruck' else 0.41
            hit = np.zeros(len(F), bool)
            for M in anchors.values(): hit |= in_wheel(c, M, radius)
            removed['Tires'] = int(hit.sum())
            keep = F[~hit]
            if len(keep) == 0:
                st.RemovePrim(t.GetPath())
            else:
                used = np.unique(keep); remap = -np.ones(len(P), np.int64); remap[used] = np.arange(len(used))
                N = mesh.GetNormalsAttr().Get()
                mesh.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy(P[used].astype(np.float32)))
                if N is not None and len(N) == len(P):
                    mesh.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(np.array(N, np.float32)[used]))
                mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray([3] * len(keep)))
                mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray(remap[keep].reshape(-1).astype(np.int32).tolist()))
                for pv in UsdGeom.PrimvarsAPI(t).GetPrimvars():
                    v = pv.Get()
                    if v is not None and len(v) == len(P) and pv.GetInterpolation() in ('vertex', 'varying'):
                        pv.Set(type(v)(np.array(v)[used].tolist()))
                mesh.GetExtentAttr().Set([Gf.Vec3f(*P[used].min(0)), Gf.Vec3f(*P[used].max(0))])
        for k, M in sorted(anchors.items()):
            x = UsdGeom.Xform.Define(st, rp.AppendChild('WheelAnchor_' + k))
            x.ClearXformOpOrder()
            x.AddTransformOp().Set(Gf.Matrix4d(*M.T.reshape(-1).tolist()))
        # Export, not Save: saving a crate file in place appends and keeps the removed data.
        fresh = os.path.splitext(layer)[0] + '.usdc'
        st.GetRootLayer().Export(os.path.join(work, '_fresh.usdc'))
        left = st.GetPrimAtPath(rp.AppendChild('Tires'))
        removed['Tires kept'] = len(UsdGeom.Mesh(left).GetFaceVertexCountsAttr().Get()) if left else 0
        del st, mesh_holder[:]
        os.remove(os.path.join(work, layer)); os.replace(os.path.join(work, '_fresh.usdc'), os.path.join(work, fresh))
        os.remove(usdz)
        cwd = os.getcwd(); os.chdir(work)
        try: assert UsdUtils.CreateNewUsdzPackage(fresh, usdz)
        finally: os.chdir(cwd)
        print(car, 'removed', removed, 'anchors', {k: np.round(M[:3, 3], 3).tolist() for k, M in sorted(anchors.items())}, os.path.getsize(usdz))
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == '__main__':
    assets = os.path.abspath(sys.argv[1])
    for car in sys.argv[2:] or CARS: strip(assets, car)
