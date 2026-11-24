"""Blender check of mounted wheels: car usdz (wheels stripped, WheelAnchor_* empties) plus a wheel usdz
on each anchor, lifted so the tyre touches y = 0 the way VehicleWheels.swift mounts it.
Usage: blender-python render_wheels.py -- CAR_USDZ WHEEL_USDZ OUT.png VIEW(side|q34|close) MODE(showroom|home) [paint hex]
"""
import bpy, math, sys, numpy as np
from mathutils import Matrix, Vector
argv = sys.argv[sys.argv.index('--') + 1:]
CAR, WHEEL, OUT, VIEW, MODE = argv[:5]
PAINT = int(argv[5], 16) if len(argv) > 5 else 0xF3F0E8
W, H = 960, 540
def s2l(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def lin(h): return tuple(s2l(((h >> s) & 255) / 255) for s in (16, 8, 0))
def g2b(v): return Vector((v[0], -v[2], v[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 48; sc.cycles.use_denoising = True
sc.view_settings.view_transform = 'Standard'
sc.render.resolution_x, sc.render.resolution_y = W, H

def bsdf(m): return next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) if m and m.use_nodes else None
before = set(bpy.data.objects)
bpy.ops.wm.usd_import(filepath=CAR)
car = [o for o in bpy.data.objects if o not in before]
for o in car:
    if o.type != 'MESH': continue
    for s in o.material_slots:
        b = bsdf(s.material); n = s.material.name.split('.')[0] if s.material else ''
        if b and n == 'Paint' and 'Cybertruck' not in CAR:
            b.inputs['Base Color'].default_value = (*lin(PAINT), 1); b.inputs['Metallic'].default_value = 0.3; b.inputs['Roughness'].default_value = 0.2
        if b and n == 'Glass':
            b.inputs['Base Color'].default_value = (*lin(0x29333D), 1); b.inputs['Metallic'].default_value = 0.9; b.inputs['Roughness'].default_value = 0.08
anchors = {o.name.split('.')[0][-2:]: o for o in car if o.name.startswith('WheelAnchor_')}
assert len(anchors) == 4, [o.name for o in car]

before = set(bpy.data.objects)
bpy.ops.wm.usd_import(filepath=WHEEL)
wheel = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
wroot = [o for o in bpy.data.objects if o not in before and o.parent is None][0]
if MODE == 'home':  # VehicleWheels.dressForHome: metalness 0
    for o in wheel:
        for s in o.material_slots:
            b = bsdf(s.material)
            if b: b.inputs['Metallic'].default_value = 0.0
# wheel radius in its own frame (Y up there; Blender import turns Y-up into Z-up)
bpy.context.view_layer.update()
r = 0
for o in wheel:
    for c in o.bound_box:
        p = wroot.matrix_world.inverted() @ (o.matrix_world @ Vector(c)); r = max(r, abs(p.z), abs(p.x))  # radius in the wheel plane
CONTACT = 0.005
for k, a in anchors.items():
    M = a.matrix_world.copy()
    sy = (M.to_3x3() @ Vector((0, 0, 1))).length  # wheel-frame Y is Blender Z
    lift = (r * sy - CONTACT) - M.translation.z
    for o in wheel:
        d = o.copy(); d.data = o.data; sc.collection.objects.link(d)
        rel = wroot.matrix_world.inverted() @ o.matrix_world
        T = Matrix.Translation((0, 0, lift)) @ M @ rel
        d.parent = None; d.matrix_world = T
for o in wheel: o.hide_render = True

pts = []
for o in bpy.data.objects:
    if o.type == 'MESH' and not o.hide_render:
        for c in o.bound_box: pts.append(np.array(o.matrix_world @ Vector(c)))
pts = np.array(pts); lo, hi = pts.min(0), pts.max(0); ctr = (lo + hi) / 2
if VIEW == 'side':
    eye = Vector((ctr[0] - 9.0, ctr[1], 0.75)); tgt = Vector((ctr[0], ctr[1], 0.6)); fov = 32
elif VIEW == 'close':
    f = anchors['LF'].matrix_world.translation
    eye = Vector((f.x - 2.2, f.y - 0.9, 0.55)); tgt = Vector((f.x, f.y, 0.33)); fov = 32
else:
    off = g2b((-4.244, 2.958, -4.713)) * 1.15
    tgt = Vector((ctr[0], ctr[1], 0.72)); eye = tgt + off; fov = 30
cam = bpy.data.cameras.new('cam'); cam.sensor_fit = 'VERTICAL'; cam.angle_y = math.radians(fov)
co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
co.location = eye; co.rotation_euler = (tgt - eye).to_track_quat('-Z', 'Y').to_euler()

w = bpy.data.worlds.new('w'); w.use_nodes = True; sc.world = w; nt = w.node_tree; nt.nodes.clear()
outn = nt.nodes.new('ShaderNodeOutputWorld'); bg = nt.nodes.new('ShaderNodeBackground')
if MODE == 'showroom':
    tc = nt.nodes.new('ShaderNodeTexEnvironment')
    tc.image = bpy.data.images.load('/workspace/powerwall-tv-3d/Powerwall-TV/TeslaAssets/ShowroomStudio.png')
    nt.links.new(tc.outputs[0], bg.inputs[0]); bg.inputs[1].default_value = 2.2
else:
    bg.inputs[0].default_value = (1, 1, 1, 1); bg.inputs[1].default_value = 0.25
    for name, rot, e in (('key', (math.radians(35), 0, math.radians(30)), 2.4), ('rim', (math.radians(65), 0, math.radians(200)), 1.2)):
        l = bpy.data.lights.new(name, 'SUN'); l.energy = e; lo_ = bpy.data.objects.new(name, l); sc.collection.objects.link(lo_); lo_.rotation_euler = rot
nt.links.new(bg.outputs[0], outn.inputs[0])
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0)); floor = bpy.context.object
fm = bpy.data.materials.new('floor'); fm.use_nodes = True; b = bsdf(fm)
b.inputs['Base Color'].default_value = (0.06, 0.06, 0.065, 1); b.inputs['Roughness'].default_value = 0.6
floor.data.materials.append(fm)
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print('WROTE', OUT, 'r', round(r, 3))
