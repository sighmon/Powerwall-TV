# Approximate SceneKit showroom renders in Cycles: "before" = add/3d CarShowroom settings,
# "after" = the Tesla-derived settings implemented on the showroom branch.
import bpy, math, sys, json
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index('--') + 1:]
MODE, MODEL, OUT = argv[0], argv[1], argv[2]
PAINT = argv[3] if len(argv) > 3 else 'PearlWhite'
W, H = (int(argv[4]), int(argv[5])) if len(argv) > 5 else (1280, 720)
SAMPLES = 128
ASSETS = '/workspace/powerwall-tv-3d/Powerwall-TV/TeslaAssets/'
import os
LAMPS = os.environ.get('LAMPS', 'after')          # before = VehicleLights split glow, after = VehicleLamps
USDZ = os.environ.get('USDZ', ASSETS + MODEL + '.usdz')
TEX = os.environ.get('LAMPTEX', ASSETS)
VIEW = os.environ.get('VIEW', 'front')             # front = front-left headlight, rear = rear-left taillight
SAMPLES = int(os.environ.get('SAMPLES', '96'))
HOUSING = {'Model3': ('Model3', .102, .7, 0), 'Model3Highland': ('Model3Highland', .137, 1, 1), 'ModelY': ('ModelY', .102, .7, .5),
           'ModelYJuniper': (None, .0196, 0, .45), 'ModelS': ('ModelS', .098, .75, .5), 'ModelX': ('ModelX', .098, 1, 1),
           'Cybertruck': ('Cybertruck', .349, 0, 1)}
LENS = {'Model3': (.0118, .51, .05), 'Model3Highland': (.0118, .39, .05), 'ModelY': (.0118, .39, .05), 'ModelYJuniper': (.0118, .39, .05),
        'ModelS': (.0118, .43, .1), 'ModelX': (.0118, .51, .1), 'Cybertruck': (0, .51, .01)}
BG = (22/255, 23/255, 24/255)

# Demo paints (TeslaPaint.demoDisplayHex + metallic/roughness) and Tesla highlight colours (Terrain.gd)
PAINTS = {'PearlWhite': (0xF3F0E8, .25, .2), 'UltraRed': (0xD01020, .7, .05), 'DeepBlue': (0x1A3F8F, .7, .04),
          'StealthGrey': (0x6A6E74, .88, .1), 'SolidBlack': (0x1A1A1A, 1.0, .04), 'Quicksilver': (0xD5D7DE, .85, .2)}
HIGHLIGHT = {'RedMulticoat': 0xf13d3d, 'SolidBlack': 0x6d6d6d, 'SilverMetallic': 0xc1c1c1, 'MidnightSilver': 0x999ea9,
             'DeepBlue': 0x1667ee, 'PearlWhite': 0xdadada, 'MidnightCherryRed': 0xeb4b69, 'Quicksilver': 0xd0d9f7,
             'UltraRed': 0xf03042, 'StealthGrey': 0x929ba7, 'GlacierBlue': 0x42599c, 'DiamondBlack': 0x6d6d6d,
             'SilkroadSilver': 0xc1c1c1, 'MarineBlue': 0x1f4b75}

def s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def hexrgb(h):
    return tuple(((h >> s) & 255) / 255 for s in (16, 8, 0))
def lin(rgb):
    return tuple(s2l(c) for c in rgb)

CFG = {
    'before': dict(offset=(-3.1, 0.53, -5.4), look=0.72, fov=28, fill=0.9, refl=0.22, falloff=(0.08, 0.32),
                   env=None, key=0.9, ambient=0.28, shadow=False, glow=False),
    'after': dict(offset=(-4.244, 2.958, -4.713), look=0.72, fov=30, fill=0.9, refl=0.1, falloff=None,
                  env=2.2, key=0.0, ambient=0.0, shadow=True, glow=True),
}[MODE]
if len(argv) > 6:
    CFG.update(json.loads(argv[6]))

AO = {'Model3': ('Model3', (-2.104, 2.104, -3.458, 3.122)), 'Model3Highland': ('Model3Highland', (-2.104, 2.104, -3.458, 3.122)),
      'ModelY': ('ModelY', (-2.104, 2.104, -3.458, 3.122)), 'ModelYJuniper': ('Model3Highland', (-2.104, 2.104, -3.458, 3.122)),
      'ModelS': ('ModelS', (-2.104, 2.104, -3.458, 3.122)), 'ModelX': ('ModelX', (-2.104, 2.104, -3.458, 3.122)),
      'Cybertruck': ('Cybertruck', (-2.043, 2.157, -3.912, 3.888)), 'Generic': ('Model3', (-2.104, 2.104, -3.458, 3.122))}

def g2b(v):  # SceneKit/Godot (Y up, nose -Z) -> Blender (Z up)
    return Vector((v[0], -v[2], v[1]))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = True
sc.cycles.max_bounces = 6; sc.cycles.transparent_max_bounces = 16
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.film_transparent = False

before = set(bpy.data.objects)
bpy.ops.wm.usd_import(filepath=USDZ)
car = [o for o in bpy.data.objects if o not in before]
meshes = [o for o in car if o.type == 'MESH']

def bsdf(mat):
    return next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) if mat and mat.use_nodes else None

hexv, metal, rough = PAINTS[PAINT]
for o in meshes:
    for slot in o.material_slots:
        m = slot.material; b = bsdf(m)
        if not b: continue
        n = m.name.split('.')[0]
        if n == 'Paint' and MODEL not in ('Generic',) and not (MODEL == 'Cybertruck'):
            b.inputs['Base Color'].default_value = (*lin(hexrgb(hexv)), 1)
            b.inputs['Metallic'].default_value = metal; b.inputs['Roughness'].default_value = rough
        if n == 'Glass':  # VehicleGlass.reveal
            b.inputs['Base Color'].default_value = (*lin((0.16, 0.20, 0.24)), 1)
            b.inputs['Metallic'].default_value = 0.9; b.inputs['Roughness'].default_value = 0.08
            b.inputs['Alpha'].default_value = 0.85
        if n == 'Lights':
            # VehicleLights.illuminate on add/3d: split by object-space Z (nose -Z, |z| > 1.15) into three lenses
            mats = {}
            for key, dif, glow in (('front', (.72, .76, .80), (.42, .40, .34)), ('rear', (.34, .02, .015), (.62, .04, .015)),
                                   ('side', (.62, .28, .04), (.7, .28, .03))):
                mm = m.copy(); bb = bsdf(mm)
                bb.inputs['Base Color'].default_value = (*lin(dif), 1); bb.inputs['Metallic'].default_value = .02
                bb.inputs['Roughness'].default_value = .2
                bb.inputs['Emission Color'].default_value = (*lin(glow), 1); bb.inputs['Emission Strength'].default_value = 1
                mats[key] = mm
            o.data.materials.clear()
            for key in ('front', 'rear', 'side'): o.data.materials.append(mats[key])
            Mw = o.matrix_world
            for poly in o.data.polygons:
                z = -(Mw @ poly.center).y
                poly.material_index = 0 if z < -1.15 else 1 if z > 1.15 else 2
            break
        if n == 'Lamps':
            tex, alb, met, rgh = HOUSING[MODEL]
            nt_ = m.node_tree
            if tex:
                bc = nt_.nodes.new('ShaderNodeTexImage'); bc.image = bpy.data.images.load(TEX + tex + '_Lamps_BC.png')
                mra = nt_.nodes.new('ShaderNodeTexImage'); mra.image = bpy.data.images.load(TEX + tex + '_Lamps_MRA.png')
                mra.image.colorspace_settings.name = 'Non-Color'
                uvm = nt_.nodes.new('ShaderNodeUVMap'); uvm.uv_map = o.data.uv_layers[0].name if o.data.uv_layers else ''
                nt_.links.new(uvm.outputs[0], bc.inputs[0]); nt_.links.new(uvm.outputs[0], mra.inputs[0])
                sp = nt_.nodes.new('ShaderNodeSeparateColor'); nt_.links.new(mra.outputs[0], sp.inputs[0])
                mul = nt_.nodes.new('ShaderNodeMix'); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'; mul.inputs['Factor'].default_value = 1
                nt_.links.new(bc.outputs[0], mul.inputs[6]); nt_.links.new(sp.outputs['Blue'], mul.inputs[7])  # AO
                mul2 = nt_.nodes.new('ShaderNodeMix'); mul2.data_type = 'RGBA'; mul2.blend_type = 'MULTIPLY'; mul2.inputs['Factor'].default_value = 1
                nt_.links.new(mul.outputs[2], mul2.inputs[6]); mul2.inputs[7].default_value = (alb, alb, alb, 1)
                nt_.links.new(mul2.outputs[2], b.inputs['Base Color'])
                mm_ = nt_.nodes.new('ShaderNodeMath'); mm_.operation = 'MULTIPLY'; mm_.inputs[1].default_value = met
                nt_.links.new(sp.outputs['Red'], mm_.inputs[0]); nt_.links.new(mm_.outputs[0], b.inputs['Metallic'])
                mr_ = nt_.nodes.new('ShaderNodeMath'); mr_.operation = 'MULTIPLY'; mr_.inputs[1].default_value = rgh
                nt_.links.new(sp.outputs['Green'], mr_.inputs[0]); nt_.links.new(mr_.outputs[0], b.inputs['Roughness'])
            else:
                b.inputs['Base Color'].default_value = (alb, alb, alb, 1); b.inputs['Metallic'].default_value = met
                b.inputs['Roughness'].default_value = rgh
            b.inputs['Emission Strength'].default_value = 0
        if n == 'LampGlass':
            alb, op, rgh = LENS[MODEL]
            for l_ in list(b.inputs['Alpha'].links): m.node_tree.links.remove(l_)
            b.inputs['Base Color'].default_value = (alb, alb, alb, 1); b.inputs['Metallic'].default_value = 0
            b.inputs['Roughness'].default_value = rgh; b.inputs['Alpha'].default_value = op

# ---- camera: port of CarShowroomOrbit fit + centre bias ----
pts = []
for o in meshes:
    for c in o.bound_box:
        p = o.matrix_world @ Vector(c); pts.append(np.array([p.x, p.z, -p.y]))  # back to Y-up
pts = np.array(pts)
R0 = np.array(CFG['offset'], float); LH = CFG['look']; FOV = CFG['fov']; FILL = CFG['fill']
UP = np.array([0, 1.0, 0])
def norm(v): return v / np.linalg.norm(v)
def eye_of(scale, bias, yaw=0, pitch=0):
    tgt = np.array([0, LH, 0]) + bias
    off = R0.copy()
    return tgt, tgt + off * scale
def dist_scale(aspect):
    tgt, e = eye_of(1, np.zeros(3)); off = e - tgt; L = np.linalg.norm(off); fw = -off / L
    rt = norm(np.cross(fw, UP)); up = norm(np.cross(rt, fw))
    ty = math.tan(math.radians(FOV) / 2); tx = ty * aspect; s = 0.2
    for p in pts:
        f = p - tgt; d = f @ fw
        s = max(s, (abs(f @ rt) / (tx * FILL) - d) / L, (abs(f @ up) / (ty * FILL) - d) / L)
    return min(max(s, 0.2), 6)
def centre_bias(scale):
    bias = np.zeros(3)
    for _ in range(3):
        tgt, e = eye_of(scale, bias); fw = norm(tgt - e); rt = norm(np.cross(fw, UP))
        xs = [((p - e) @ rt) / ((p - e) @ fw) for p in pts if (p - e) @ fw > 1e-3]
        bias = bias + rt * ((min(xs) + max(xs)) * 0.5 * np.linalg.norm(e - tgt))
    return bias
scale = dist_scale(W / H); bias = centre_bias(scale)
tgt, eye = eye_of(scale, bias)
# ---- close-up on a front-left headlight (or rear-left taillight) ----
lamp_pts = []
for o in meshes:
    nm = o.name.split('.')[0]
    if nm not in ('Lights', 'Lamps', 'LampGlass'): continue
    Mw = o.matrix_world
    for v in o.data.vertices:
        p = Mw @ v.co; q = np.array([p.x, p.z, -p.y])
        if q[0] < -0.2 and ((q[2] < -1.4) if VIEW == 'front' else (q[2] > 1.4)): lamp_pts.append(q)
lamp_pts = np.array(lamp_pts)
tgt = (lamp_pts.min(0) + lamp_pts.max(0)) / 2
span = np.linalg.norm(lamp_pts.max(0) - lamp_pts.min(0))
direction = norm(np.array([-0.75, 0.32, -1.0] if VIEW == 'front' else [-0.75, 0.32, 1.0]))
FOV = 30
eye = tgt + direction * (span * float(os.environ.get("ZOOM", "0.4")) / math.tan(math.radians(FOV) / 2))
cam = bpy.data.cameras.new('cam'); cam.sensor_fit = 'VERTICAL'; cam.angle_y = math.radians(FOV)
cam.clip_start = 0.05; cam.clip_end = 200
co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
co.location = g2b(eye)
co.rotation_euler = (g2b(tgt) - g2b(eye)).to_track_quat('-Z', 'Y').to_euler()

# ---- world ----
w = bpy.data.worlds.new('w'); w.use_nodes = True; sc.world = w
nt = w.node_tree; nt.nodes.clear()
outn = nt.nodes.new('ShaderNodeOutputWorld')
lp = nt.nodes.new('ShaderNodeLightPath')
bgcam = nt.nodes.new('ShaderNodeBackground'); bgcam.inputs[0].default_value = (*lin(BG), 1)
mix = nt.nodes.new('ShaderNodeMixShader')
light = nt.nodes.new('ShaderNodeBackground')
if CFG['env']:
    # Godot panorama lookup in Godot space: u = atan2(x, z)/2pi, v = acos(y)/pi; Blender dir D -> Godot (Dx, Dz, -Dy)
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Generated'], sep.inputs[0])
    neg = nt.nodes.new('ShaderNodeMath'); neg.operation = 'MULTIPLY'; neg.inputs[1].default_value = -1
    nt.links.new(sep.outputs['Y'], neg.inputs[0])
    at = nt.nodes.new('ShaderNodeMath'); at.operation = 'ARCTAN2'
    nt.links.new(sep.outputs['X'], at.inputs[0]); nt.links.new(neg.outputs[0], at.inputs[1])
    u = nt.nodes.new('ShaderNodeMath'); u.operation = 'DIVIDE'; u.inputs[1].default_value = 2 * math.pi
    nt.links.new(at.outputs[0], u.inputs[0])
    ac = nt.nodes.new('ShaderNodeMath'); ac.operation = 'ARCCOSINE'; nt.links.new(sep.outputs['Z'], ac.inputs[0])
    v = nt.nodes.new('ShaderNodeMath'); v.operation = 'MULTIPLY_ADD'; v.inputs[1].default_value = -1 / math.pi; v.inputs[2].default_value = 1
    nt.links.new(ac.outputs[0], v.inputs[0])
    comb = nt.nodes.new('ShaderNodeCombineXYZ'); nt.links.new(u.outputs[0], comb.inputs[0]); nt.links.new(v.outputs[0], comb.inputs[1])
    img = nt.nodes.new('ShaderNodeTexImage'); img.image = bpy.data.images.load('/workspace/powerwall-tv-3d/Powerwall-TV/TeslaAssets/ShowroomStudio.png')
    img.extension = 'REPEAT'; img.interpolation = 'Linear'
    nt.links.new(comb.outputs[0], img.inputs[0]); nt.links.new(img.outputs[0], light.inputs[0])
    light.inputs[1].default_value = CFG['env']
else:
    light.inputs[0].default_value = (1, 1, 1, 1); light.inputs[1].default_value = CFG['ambient']
nt.links.new(lp.outputs['Is Camera Ray'], mix.inputs[0])
nt.links.new(light.outputs[0], mix.inputs[1]); nt.links.new(bgcam.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], outn.inputs[0])

if CFG['key'] > 0:  # SceneKit directional 900 -> Cycles sun 0.9*pi
    l = bpy.data.lights.new('key', 'SUN'); l.energy = CFG['key'] * math.pi; l.angle = 0.01
    lo = bpy.data.objects.new('key', l); sc.collection.objects.link(lo)
    lo.rotation_euler = (g2b(np.array([0, 0.6, 0])) - g2b(eye)).to_track_quat('-Z', 'Y').to_euler()

def camera_only(o):
    o.visible_diffuse = False; o.visible_glossy = False; o.visible_shadow = False
    o.visible_transmission = False; o.visible_volume_scatter = False

def emission_mat(name, colour, alpha_socket_builder=None):
    m = bpy.data.materials.new(name); m.use_nodes = True; t = m.node_tree; t.nodes.clear()
    o = t.nodes.new('ShaderNodeOutputMaterial'); e = t.nodes.new('ShaderNodeEmission'); e.inputs[0].default_value = (*colour, 1)
    tr = t.nodes.new('ShaderNodeBsdfTransparent'); mx = t.nodes.new('ShaderNodeMixShader')
    t.links.new(tr.outputs[0], mx.inputs[1]); t.links.new(e.outputs[0], mx.inputs[2]); t.links.new(mx.outputs[0], o.inputs[0])
    return m, t, mx, e, tr

# ---- floor: unshaded background colour, partially see-through to a mirrored car = reflection ----
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0)); floor = bpy.context.object
m, t, mx, e, tr = emission_mat('floor', lin(BG))
# opacity = (1 - refl) * distance fade (Tesla: 1 - smoothstep(5, 15, d)); the see-through part shows the mirror car
geo = t.nodes.new('ShaderNodeNewGeometry'); sep = t.nodes.new('ShaderNodeSeparateXYZ'); t.links.new(geo.outputs['Position'], sep.inputs[0])
comb = t.nodes.new('ShaderNodeCombineXYZ'); t.links.new(sep.outputs['X'], comb.inputs[0]); t.links.new(sep.outputs['Y'], comb.inputs[1])
ln = t.nodes.new('ShaderNodeVectorMath'); ln.operation = 'LENGTH'; t.links.new(comb.outputs[0], ln.inputs[0])
mr = t.nodes.new('ShaderNodeMapRange'); mr.interpolation_type = 'SMOOTHSTEP'
mr.inputs['From Min'].default_value = 5; mr.inputs['From Max'].default_value = 15
mr.inputs['To Min'].default_value = 1 - CFG['refl']; mr.inputs['To Max'].default_value = 0
t.links.new(ln.outputs[1], mr.inputs['Value']); t.links.new(mr.outputs[0], mx.inputs[0])
floor.data.materials.append(m); camera_only(floor)

# mirrored car under the floor (camera rays only)
mirror_root = bpy.data.objects.new('mirror', None); sc.collection.objects.link(mirror_root)
for o in meshes:
    d = o.copy(); d.data = o.data; sc.collection.objects.link(d)
    d.parent = None; d.matrix_world = Matrix.Scale(-1, 4, Vector((0, 0, 1))) @ o.matrix_world
    camera_only(d)
    if CFG['falloff']:
        mats = []
        for slot in d.material_slots:
            mm = slot.material.copy(); tt = mm.node_tree
            out = next(n for n in tt.nodes if n.type == 'OUTPUT_MATERIAL'); src = out.inputs[0].links[0].from_socket
            g2 = tt.nodes.new('ShaderNodeNewGeometry'); s2 = tt.nodes.new('ShaderNodeSeparateXYZ'); tt.links.new(g2.outputs['Position'], s2.inputs[0])
            mr2 = tt.nodes.new('ShaderNodeMapRange'); mr2.inputs['From Min'].default_value = -CFG['falloff'][1]; mr2.inputs['From Max'].default_value = -CFG['falloff'][0]
            mr2.inputs['To Min'].default_value = 0; mr2.inputs['To Max'].default_value = 1
            tt.links.new(s2.outputs['Z'], mr2.inputs['Value'])
            tr2 = tt.nodes.new('ShaderNodeBsdfTransparent'); mx2 = tt.nodes.new('ShaderNodeMixShader')
            tt.links.new(mr2.outputs[0], mx2.inputs[0]); tt.links.new(tr2.outputs[0], mx2.inputs[1]); tt.links.new(src, mx2.inputs[2])
            tt.links.new(mx2.outputs[0], out.inputs[0]); slot.link = 'OBJECT'; slot.material = mm

# ---- Tesla ground AO quad ----
if CFG['shadow']:
    tex, (x0, x1, z0, z1) = AO[MODEL]
    bpy.ops.mesh.primitive_plane_add(size=1); q = bpy.context.object
    q.scale = (x1 - x0, z1 - z0, 1); q.location = g2b(np.array([(x0 + x1) / 2, 0.003, (z0 + z1) / 2]))
    m, t, mx, e, tr = emission_mat('ao', (0, 0, 0))
    it = t.nodes.new('ShaderNodeTexImage'); it.image = bpy.data.images.load(ASSETS + tex + '_GroundAO.png')
    it.extension = 'CLIP'
    # Blender plane UV v=1 at +Y(blender) = -Z(Godot) = nose; canonical image top = nose. Image node v=1 is the top row.
    t.links.new(it.outputs['Alpha'], mx.inputs[0])
    q.data.materials.append(m); camera_only(q)

# ---- Tesla paint-coloured glow plane (ReflectiveFloor.update_glow_plane) ----
if CFG['glow']:
    GHW, GHH, GD, GREF = 8.2, 4.3, 16.3, 15.8
    gc = np.array([0, 1.0, 0]); to_c = gc - eye; facing = -norm(to_c)
    up = UP - facing * (facing @ UP); up = norm(up)
    dist = max(np.linalg.norm(to_c), 0.01)
    ss = (dist + GD) / dist * GREF / (GREF + GD)
    origin = eye + norm(to_c) * (dist + GD)
    looking_down = -norm(tgt - eye)[1]
    def smooth(a, b, x):
        t_ = min(max((x - a) / (b - a), 0), 1); return t_ * t_ * (3 - 2 * t_)
    fade = 0.26 * (1 - smooth(0.6, 0.85, looking_down))
    X = np.cross(facing, up) * GHW * ss; Z = up * GHH * ss
    bpy.ops.mesh.primitive_plane_add(size=2); gp = bpy.context.object
    # Godot local X -> X, local Z (Godot) -> Blender local -Y, normal Y -> Blender local Z
    M = Matrix.Identity(4)
    cx, cz_, cn = g2b(X), g2b(-Z), g2b(facing)
    for i in range(3):
        M[i][0], M[i][1], M[i][2], M[i][3] = cx[i], cz_[i], cn[i], g2b(origin)[i]
    gp.matrix_world = M
    hl = 0xc1c1c1 if MODEL == 'Cybertruck' else HIGHLIGHT.get(PAINT, 0xc1c1c1)
    m, t, mx, e, tr = emission_mat('glow', lin(hexrgb(hl)))
    uvn = t.nodes.new('ShaderNodeTexCoord')
    sub = t.nodes.new('ShaderNodeVectorMath'); sub.operation = 'SUBTRACT'; sub.inputs[1].default_value = (0.5, 0.5, 0)
    t.links.new(uvn.outputs['UV'], sub.inputs[0])
    sc2 = t.nodes.new('ShaderNodeVectorMath'); sc2.operation = 'SCALE'; sc2.inputs['Scale'].default_value = 2
    t.links.new(sub.outputs[0], sc2.inputs[0])
    l2 = t.nodes.new('ShaderNodeVectorMath'); l2.operation = 'LENGTH'; t.links.new(sc2.outputs[0], l2.inputs[0])
    mr = t.nodes.new('ShaderNodeMapRange'); mr.interpolation_type = 'SMOOTHSTEP'
    mr.inputs['From Min'].default_value = 0.5; mr.inputs['From Max'].default_value = 1.0
    mr.inputs['To Min'].default_value = fade; mr.inputs['To Max'].default_value = 0
    t.links.new(l2.outputs[1], mr.inputs['Value']); t.links.new(mr.outputs[0], mx.inputs[0])
    gp.data.materials.append(m); camera_only(gp)

sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print('WROTE', OUT, 'scale', scale, 'eye', eye.round(3), 'target', tgt.round(3))
