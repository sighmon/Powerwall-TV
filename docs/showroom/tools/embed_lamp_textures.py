"""Wire each car's lamp housing atlas into its usdz, the way ResidentialClassic.usdz wires its textures.

SceneKit's USD import brings in a mesh's `primvars:st` reliably only when a material samples it
through UsdPrimvarReader_float2 -> UsdUVTexture. The converter wrote the Lamps UVs but a flat
UsdPreviewSurface, so the housing could arrive without texture coordinates and the app's atlas had
nothing to map onto. This adds the reader and the BC texture (packaged inside the usdz as
0/<Car>_Lamps_BC.png). It also writes metallic 0 and roughness 0.35, so the housing still reads
under plain lights before the app dresses it. Idempotent: rerunning replaces the same prims.

Usage: python embed_lamp_textures.py [TeslaAssets dir] [car ...]
"""
import os, shutil, sys, tempfile, zipfile
from pxr import Sdf, Usd, UsdShade, UsdUtils

ASSETS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '../../../Powerwall-TV/TeslaAssets')
CARS = sys.argv[2:] or ['Model3', 'Model3Highland', 'ModelY', 'ModelS', 'ModelX', 'Cybertruck']

def embed(car):
    usdz = os.path.join(ASSETS, f'{car}.usdz')
    bc = os.path.join(ASSETS, f'{car}_Lamps_BC.png')
    work = tempfile.mkdtemp(prefix=f'lamps_{car}_')
    try:
        with zipfile.ZipFile(usdz) as z:
            z.extractall(work)
        layer = next(n for n in os.listdir(work) if n.endswith(('.usdc', '.usda')))
        os.makedirs(os.path.join(work, '0'), exist_ok=True)
        shutil.copy(bc, os.path.join(work, '0', f'{car}_Lamps_BC.png'))
        stage = Usd.Stage.Open(os.path.join(work, layer))
        base = f'/{car}/Materials/Lamps'
        material = UsdShade.Material.Get(stage, base)
        assert material, f'{car}: no {base}'
        pbr = UsdShade.Shader.Get(stage, base + '/PBR')
        reader = UsdShade.Shader.Define(stage, base + '/st')
        reader.CreateIdAttr('UsdPrimvarReader_float2')
        reader.CreateInput('varname', Sdf.ValueTypeNames.Token).Set('st')
        tex = UsdShade.Shader.Define(stage, base + '/BaseColorTex')
        tex.CreateIdAttr('UsdUVTexture')
        tex.CreateInput('file', Sdf.ValueTypeNames.Asset).Set(f'0/{car}_Lamps_BC.png')
        tex.CreateInput('sourceColorSpace', Sdf.ValueTypeNames.Token).Set('sRGB')
        tex.CreateInput('wrapS', Sdf.ValueTypeNames.Token).Set('repeat')
        tex.CreateInput('wrapT', Sdf.ValueTypeNames.Token).Set('repeat')
        tex.CreateInput('st', Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), 'result')
        rgb = tex.CreateOutput('rgb', Sdf.ValueTypeNames.Float3)
        pbr.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).ConnectToSource(rgb)
        pbr.CreateInput('metallic', Sdf.ValueTypeNames.Float).Set(0.0)
        pbr.CreateInput('roughness', Sdf.ValueTypeNames.Float).Set(0.35)
        stage.GetRootLayer().Save()
        os.remove(usdz)
        cwd = os.getcwd(); os.chdir(work)
        try:
            assert UsdUtils.CreateNewUsdzPackage(layer, usdz), f'{car}: packaging failed'
        finally:
            os.chdir(cwd)
        names = zipfile.ZipFile(usdz).namelist()
        print(car, os.path.getsize(usdz), names)
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == '__main__':
    ASSETS = os.path.abspath(ASSETS)
    for car in CARS:
        embed(car)
