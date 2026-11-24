"""Export every Tesla app wheel scene (VehicleOptions.gd WheelTypeToPathMap and the caps overrides)
to a small usdz in the wheel's own frame: centred on the axle, +X forward, +Y up, +Z outward
(the right-hand side). Each material becomes one mesh: WheelTire*, WheelRim*.

Textures: the albedo map times Tesla's albedo colour and its baked occlusion, sRGB-encoded so a
reader that decodes sRGB gets Tesla's texel values back as linear colour (as flat colours are), 256 px for rims and
128 px for tyres (JPEG). A flat map becomes a plain colour. Materials over 3000 triangles are
quadric-decimated, with normals rebuilt (split at 35°) and texture coordinates carried over.
Rim colours are multiplied by 3.5, like the showroom's paint display boost: Tesla's albedos are
tuned for its studio reflections and read near black without them.
Metallic and roughness are Tesla's factors times the mean of their texture channel.
Normal, AO and MRA maps are dropped to keep the files small.

Usage: python export_wheels.py OUT_DIR [scene ...]
"""
import os, re, sys, io, shutil, tempfile, hashlib, numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot, inventory
sys.path.insert(0, os.environ.get('SHOWROOM_TOOLS', '/workspace/powerwall-tv-3d/docs/showroom/tools'))
from stex import dec
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils

TEX_PX = 256
TIRE = re.compile(r'tire|pirelli|conti|rubber', re.I)

def asset_name(path):
    stem = path.rsplit('/', 1)[-1][:-5]
    return stem if stem.startswith('Wheel_') else 'Wheel_' + stem

_img = {}
def image(tex):
    """Decoded texture as RGBA numpy float (0..1)."""
    p = tex.props['stex']
    if p not in _img:
        tmp = tempfile.mktemp(suffix='.png')
        r = dec(godot.fs(p), tmp)
        assert r.startswith('ok'), (p, r)
        _img[p] = np.asarray(Image.open(tmp).convert('RGBA'), np.float32) / 255
        os.remove(tmp)
    return _img[p]

def channel_mean(tex, ch):
    if not isinstance(tex, godot.Res) or tex.type != 'Texture': return 1.0
    return float(image(tex)[..., min(int(ch), 3)].mean())

RIM_BOOST = float(os.environ.get('WHEEL_RIM_BOOST', 3.5))

def material_spec(m, boost=1.0):
    """Tesla SpatialMaterial -> (colour rgb, texture image or None, metallic, roughness)."""
    pr = m.props if m is not None else {}
    c = np.array(pr.get('albedo_color', (1, 1, 1, 1))[:3], np.float32)
    if pr.get('flags_unshaded') and c.max() < 0.01:
        return c, None, 0.0, 1.0
    def tex_ok(t): return isinstance(t, godot.Res) and t.type == 'Texture'
    def fit(a):
        im = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8), 'RGB')
        return im.resize((TEX_PX, TEX_PX), Image.LANCZOS) if im.size != (TEX_PX, TEX_PX) else im
    tex = pr.get('albedo_texture'); ao = pr.get('ao_texture')
    if pr.get('ao_on_uv2') or not pr.get('ao_enabled', tex_ok(ao)): ao = None
    a = None
    if tex_ok(tex):
        a = np.asarray(fit(image(tex)[..., :3] * c), np.float32) / 255  # Tesla multiplies the map by albedo_color
    if tex_ok(ao):
        # Baked occlusion carries most of the spoke detail; with no studio light in the home view
        # it is folded into the colour.
        occ = np.asarray(fit(np.repeat(image(ao)[..., [min(int(pr.get('ao_texture_channel', 0)), 3)]], 3, -1)), np.float32) / 255
        a = (a if a is not None else np.broadcast_to(c, occ.shape)) * occ
    c = c * boost
    if a is not None: a = np.clip(a * boost, 0, 1)
    img = None
    if a is not None:
        if a.reshape(-1, 3).std(0).max() < 0.012:
            c = a.reshape(-1, 3).mean(0)  # a flat map is just a colour
        else:
            # Tesla's GLES2 renderer uses these texels as they are. SceneKit decodes a JPEG as sRGB, which
            # left silver wheels near black, so the texels are written sRGB-encoded: SceneKit then reads
            # back Tesla's values as linear colour, the same treatment the flat colours get.
            img = fit(np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(np.clip(a, 0, 1), 1 / 2.4) - 0.055))
    metal = float(pr.get('metallic', 0.0)) * channel_mean(pr.get('metallic_texture'), pr.get('metallic_texture_channel', 0))
    rough = float(pr.get('roughness', 1.0)) * channel_mean(pr.get('roughness_texture'), pr.get('roughness_texture_channel', 0))
    return c, img, metal, rough

def collect(path):
    groups = {}
    for node, surfs, W in godot.scene_meshes(path):
        R = W[:3, :3]; flip = np.linalg.det(R) < 0
        Ninv = np.linalg.inv(R).T
        for s in surfs:
            m = s['material']
            key = m.path if m is not None else 'none'
            P = (np.c_[s['P'], np.ones(len(s['P']))] @ W.T)[:, :3]
            N = s.get('N', np.zeros_like(P)) @ Ninv.T
            N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
            UV = s.get('UV'); UV = np.zeros((len(P), 2)) if UV is None else UV.astype(np.float64)
            F = s['F'][:, ::-1] if flip else s['F']
            g = groups.setdefault(key, dict(material=m, parts=[], node=node))
            g['parts'].append((P, N, UV, F))
    return groups

MAX_TRIS = int(os.environ.get('WHEEL_MAX_TRIS', 3000))  # per material
CREASE = np.cos(np.radians(35))

def weld(P, N, UV, F):
    cols = [np.round(P, 5), np.round(N, 3)] + ([np.round(UV, 4)] if UV is not None else [])
    key = np.concatenate(cols, 1)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    F = inv[F]; F = F[(F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])]
    return P[first], N[first], (UV[first] if UV is not None else None), F

def crease_normals(V, F):
    """Smooth normals that split at edges sharper than 35 degrees; returns per-corner arrays."""
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    area = np.linalg.norm(fn, axis=1, keepdims=True); fnu = fn / (area + 1e-20)
    order = np.argsort(F.reshape(-1), kind='stable'); vtx = F.reshape(-1)[order]
    starts = np.searchsorted(vtx, np.arange(len(V))); ends = np.searchsorted(vtx, np.arange(len(V)), 'right')
    faces_of = order // 3
    out = np.zeros((len(F) * 3, 3))
    for corner in range(len(F) * 3):
        f = corner // 3; v = F[f, corner % 3]
        nb = faces_of[starts[v]:ends[v]]
        keep = nb[(fnu[nb] @ fnu[f]) > CREASE]
        n = fn[keep].sum(0); out[corner] = n / (np.linalg.norm(n) + 1e-20)
    return out

def nearest(src, dst, chunk=2048):
    idx = np.empty(len(dst), np.int64)
    for i in range(0, len(dst), chunk):
        d = ((dst[i:i + chunk, None, :] - src[None, :, :]) ** 2).sum(-1); idx[i:i + chunk] = d.argmin(1)
    return idx

def compact(P, N, UV, F):
    """Weld duplicate vertices; quadric-decimate a material over MAX_TRIS triangles."""
    P, N, UV, F = weld(P, N, UV, F)
    if len(F) <= MAX_TRIS: return P, N, UV, F
    import fast_simplification
    # Decimate on positions only (welded), then rebuild normals and texture coordinates.
    _, firstp, invp = np.unique(np.round(P, 5), axis=0, return_index=True, return_inverse=True)
    Vp = P[firstp]; Fp = invp.reshape(-1)[F]
    V2, F2 = fast_simplification.simplify(Vp.astype(np.float32), Fp.astype(np.int32), target_reduction=1 - MAX_TRIS / len(F))
    V2 = V2.astype(np.float64); F2 = F2.astype(np.int64)
    corners = V2[F2.reshape(-1)]
    cn = crease_normals(V2, F2)
    cuv = UV[nearest(P, corners)] if UV is not None else None
    Fc = np.arange(len(corners)).reshape(-1, 3)
    return weld(corners, cn, cuv, Fc)

def role(key, m, P):
    name = (m.props.get('resource_name', '') if m is not None else '') + ' ' + key
    if TIRE.search(name): return 'WheelTire'
    return 'WheelRim'

def export(path, out_dir):
    name = asset_name(path)
    groups = collect(path)
    work = tempfile.mkdtemp(prefix='wheel_')
    try:
        layer = os.path.join(work, name + '.usdc')
        st = Usd.Stage.CreateNew(layer)
        UsdGeom.SetStageUpAxis(st, 'Y'); UsdGeom.SetStageMetersPerUnit(st, 1)
        root = UsdGeom.Xform.Define(st, '/' + name); st.SetDefaultPrim(root.GetPrim())
        UsdGeom.Scope.Define(st, f'/{name}/Materials')
        used = {}; tris = 0; summary = []
        os.makedirs(os.path.join(work, '0'), exist_ok=True)
        for key, g in groups.items():
            P = np.concatenate([p[0] for p in g['parts']]); N = np.concatenate([p[1] for p in g['parts']])
            UV = np.concatenate([p[2] for p in g['parts']]); off = 0; Fs = []
            for p in g['parts']: Fs.append(p[3] + off); off += len(p[0])
            F = np.concatenate(Fs)
            r = role(key, g['material'], P)
            c_, img_, _, _ = material_spec(g['material'], RIM_BOOST if r == 'WheelRim' else 1.0)
            P, N, UV, F = compact(P, N, UV if img_ is not None else None, F)
            used[r] = used.get(r, 0) + 1
            mname = r if used[r] == 1 else f'{r}{used[r]}'
            c, img, metal, rough = material_spec(g['material'], RIM_BOOST if r == 'WheelRim' else 1.0)
            mp = f'/{name}/Materials/{mname}'
            mat = UsdShade.Material.Define(st, mp)
            sh = UsdShade.Shader.Define(st, mp + '/PBR'); sh.CreateIdAttr('UsdPreviewSurface')
            sh.CreateInput('metallic', Sdf.ValueTypeNames.Float).Set(round(metal, 3))
            sh.CreateInput('roughness', Sdf.ValueTypeNames.Float).Set(round(rough, 3))
            if img is not None:
                if r == 'WheelTire': img = img.resize((TEX_PX // 2, TEX_PX // 2), Image.LANCZOS)
                buf = io.BytesIO(); img.save(buf, 'JPEG', quality=80, optimize=True)
                tname = f'0/{name}_{mname}.jpg'
                open(os.path.join(work, tname), 'wb').write(buf.getvalue())
                reader = UsdShade.Shader.Define(st, mp + '/st'); reader.CreateIdAttr('UsdPrimvarReader_float2')
                reader.CreateInput('varname', Sdf.ValueTypeNames.Token).Set('st')
                tex = UsdShade.Shader.Define(st, mp + '/BaseColorTex'); tex.CreateIdAttr('UsdUVTexture')
                tex.CreateInput('file', Sdf.ValueTypeNames.Asset).Set(tname)
                tex.CreateInput('sourceColorSpace', Sdf.ValueTypeNames.Token).Set('sRGB')
                tex.CreateInput('wrapS', Sdf.ValueTypeNames.Token).Set('repeat')
                tex.CreateInput('wrapT', Sdf.ValueTypeNames.Token).Set('repeat')
                tex.CreateInput('st', Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), 'result')
                sh.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).ConnectToSource(tex.CreateOutput('rgb', Sdf.ValueTypeNames.Float3))
                e = np.asarray(img, np.float32).reshape(-1, 3) / 255
                mean = np.where(e <= 0.04045, e / 12.92, ((e + 0.055) / 1.055) ** 2.4).mean(0)
            else:
                sh.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*map(float, c)))
                mean = c
            mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), 'surface')
            m = UsdGeom.Mesh.Define(st, f'/{name}/{mname}')
            m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(P.astype(np.float32)))
            m.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(F)))
            m.CreateFaceVertexIndicesAttr(Vt.IntArray(F.reshape(-1).astype(np.int32).tolist()))
            m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(N.astype(np.float32))); m.SetNormalsInterpolation('vertex')
            m.CreateSubdivisionSchemeAttr('none'); m.CreateDoubleSidedAttr(True)
            if UV is not None:
                uv = UV.astype(np.float32).copy(); uv[:, 1] = 1 - uv[:, 1]  # Godot UV origin is top left
                pv = UsdGeom.PrimvarsAPI(m.GetPrim()).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
                pv.Set(Vt.Vec2fArray.FromNumpy(uv))
            m.CreateExtentAttr([Gf.Vec3f(*P.min(0)), Gf.Vec3f(*P.max(0))])
            UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(mat)
            tris += len(F)
            summary.append((mname, len(F), 'tex' if img is not None else 'flat', tuple(np.round(mean, 2)), round(metal, 2), round(rough, 2)))
        st.GetRootLayer().Save()
        usdz = os.path.join(out_dir, name + '.usdz')
        if os.path.exists(usdz): os.remove(usdz)
        cwd = os.getcwd(); os.chdir(work)
        try:
            assert UsdUtils.CreateNewUsdzPackage(os.path.basename(layer), usdz)
        finally:
            os.chdir(cwd)
        return name, tris, os.path.getsize(usdz), summary
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == '__main__':
    out = os.path.abspath(sys.argv[1]); os.makedirs(out, exist_ok=True)
    only = sys.argv[2:]
    total = 0
    for p in inventory.paths:
        if only and not any(o in p for o in only): continue
        name, tris, size, summary = export(p, out)
        total += size
        print(f'{name}: {tris} tris {size//1024} KB', summary)
    print('total', total // 1024, 'KB')
