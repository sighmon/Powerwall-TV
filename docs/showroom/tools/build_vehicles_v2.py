import sys,os,re,numpy as np
sys.path.insert(0,"conv"); from gl import *
from pxr import Usd,UsdGeom,UsdShade,Sdf,Gf,Vt,UsdUtils
import trimesh
from trimesh.visual import TextureVisuals
from trimesh.visual.material import PBRMaterial
R="vehicles_raw/"; OUT="tvos/vehicles/"; os.makedirs(OUT,exist_ok=True)
# CYBERTRUCK_TONNEAU=closed|open — closed (default) attaches the vault cover at rest pose;
# open omits it (bed exposed). No separate open-pose mesh exists in the APK; open is absence.
CYBERTRUCK_TONNEAU=os.environ.get("CYBERTRUCK_TONNEAU","closed").lower()
CARS={ # name: (car glb, wheel glb, default paint)
 "Model3":("Ego__3_High__Model3_High_tscn","Ego__Wheels_P3__Wheel_Standard_tscn",(0.62,0.64,0.66)),
 "Model3Highland":("Ego__v2023__Poppyseed__Poppyseed_tscn","Ego__v2023__Wheels__Glider_tscn",(0.08,0.2,0.45)),
 "ModelY":("Ego__Y_High__ModelY_High_tscn","Ego__Wheels__Wheel_Gemini_tscn",(0.93,0.93,0.92)),
 "ModelYJuniper":("Ego__Bayberry__Bayberry_tscn","Ego__Wheels_Bayberry__Helix2__Helix2_tscn",(0.35,0.36,0.38)),
 "ModelS":("Ego__S_Palladium__S_Palladium_tscn","Ego__Wheels_Palladium__Cardenio_tscn",(0.6,0.05,0.07)),
 "ModelX":("Ego__X_Palladium__X_Palladium_tscn","Ego__Wheels_Palladium__Cyberstream_tscn",(0.05,0.05,0.06)),
 "Cybertruck":("Ego__Cybertruck__Cybertruck_tscn","Ego__Cybertruck__Wheels__Wheel_Cybertruck_Standard_tscn",(0.72,0.73,0.74)),
 "Generic":("Energy__Vehicle__GenericVehicle__GenericVehicle_tscn",None,(0.85,0.85,0.86)),
}
DROP_NODE=re.compile(r"seat|doorcard|dashboard|console|interior|steering|screen|floor|frunk|plate|trunk_card|defrost|headliner|shadow|marker|carpet|pedal|cupholder|speaker|mirror_inside|footwell|cabin|occupant|lightbeam|projection|basecamp|tonneau_inner|bed_|cargo|ground",re.I)
# Note: "interior" must NOT drop Glass_Interior* — those are the exterior window shells on several cars.
DROP_MAT=re.compile(r"seat|leather|carpet|suede|fabric|(?<!glass_)interior|decor|screen|textile|frunk|ground|shadow|projection|illumination|plates|headlights_projection|beam",re.I)
BODY_PANEL=re.compile(r"trunk|hood|door|body|bumper|fender|quarter|tailgate|liftgate|boot|tonneau",re.I)
def drop_mat(mat):
    if not mat: return False
    if re.search(r"glass", mat, re.I): return False  # never drop glass materials
    return bool(DROP_MAT.search(mat))
def cat(node,mat,car):
    n=(node or ""); m=(mat or "").lower()
    # Cybertruck vault cover (TonneauCover plane + rib panels)
    if car=="Cybertruck" and re.search(r"tonneau", n, re.I) and not re.search(r"button|marker", n, re.I):
        # Reuse the same dark Trim as adjacent Black_Plastic_Exterior bed surround.
        return "Trim"
    # Lamp lens glass and the textured lamp housing (reflectors, red and amber lenses) stay
    # separate so the app can give them the Tesla app's Glass_Lights and Light materials.
    if "glass" in m and "light" in m: return "LampGlass"
    # Model Y Juniper's roof, rear glass, and rear door and quarter windows use glass_skybox
    # ShaderMaterials (Glass_Windows_Dark, Glass_Top_Fade). The glTF export writes no material
    # for them, so they came through as opaque Trim. No other car has unnamed exterior surfaces.
    if m=="" and car=="ModelYJuniper": return "Glass"
    if "glass" in m or "window" in m: return "Glass"
    # ExteriorFade was wrongly mapped to Glass; on body panels it is body paint (Model Y liftgate).
    if m in ("exteriorfade","exterior_fade"):
        return "Paint" if BODY_PANEL.search(n) else "Trim"
    if car=="Cybertruck" and ("stainless" in m or "paint" in m): return "Paint"
    if "paint" in m or m in ("exterior","exterior_perf","exterior_hydroxide","cover","vehiclebody") or (car=="Generic"): return "Paint"
    if "light" in m or "lamp" in m: return "Lamps"
    if "chrome" in m or "alumin" in m or "steel" in m or "metal" in m: return "Chrome"
    if "tire" in m or "rubber" in m or "pirelli" in m: return "Tires"
    return "Trim"
# Consistent original dark tint across all cars; retain restored glass geometry.
MATS={"Paint":dict(metallic=0.35,roughness=0.25),
 "Glass":dict(c=(0.03,0.04,0.05),metallic=0,roughness=0.05,opacity=0.85),
 # Lamps: flat fallback; the app dresses it with <Model>_Lamps_BC/_MRA.png on primvars:st.
 "Lamps":dict(c=(0.1,0.1,0.1),metallic=0.7,roughness=0.3),
 # LampGlass: Glass_Lights in every car (albedo 0.0118, alpha 0.39, roughness 0.05).
 "LampGlass":dict(c=(0.0118,0.0118,0.0118),metallic=0,roughness=0.05,opacity=0.39),
 # Pillar: Bayberry Pillar.tres albedo 0.0196, gloss black like the car's pillar trim.
 "Pillar":dict(c=(0.0196,0.0196,0.0196),metallic=0,roughness=0.25),
 "Chrome":dict(c=(0.6,0.6,0.62),metallic=0.9,roughness=0.3),
 "Tires":dict(c=(0.03,0.03,0.03),metallic=0,roughness=0.9),"Wheels":dict(c=(0.55,0.56,0.58),metallic=0.8,roughness=0.35),
 "Trim":dict(c=(0.04,0.04,0.045),metallic=0,roughness=0.5)}
def _ry_neg90(P,N,F):
    """Map standalone Tonneau.glb (X-long) into Cybertruck body space (Z-long): (x,y,z)->(z,y,-x)."""
    P2=np.column_stack([P[:,2], P[:,1], -P[:,0]])
    N2=np.column_stack([N[:,2], N[:,1], -N[:,0]])
    N2/=np.linalg.norm(N2,axis=1,keepdims=True)+1e-12
    return P2,N2,F
def add_cybertruck_tonneau(add):
    """Attach closed vault cover. Prefer the full-scene export (correct axes); else rotate standalone."""
    if CYBERTRUCK_TONNEAU=="open":
        print("Cybertruck tonneau: OPEN (omitted)")
        return
    full=R+"Ego__Cybertruck__Cybertruck_with_tonneau_tscn.glb"
    stand=R+"Ego__Cybertruck__Tonneau_tscn.glb"
    n_keep=0
    if os.path.exists(full):
        for n,m,P,N,UV,F in meshes(full):
            if not n or not re.search(r"^Tonneau(\d|$)|TonneauCover", n): continue
            if re.search(r"button|marker|inner", n, re.I): continue
            add(cat(n,m,"Cybertruck"),P,F,N); n_keep+=1
        print(f"Cybertruck tonneau: CLOSED from with_tonneau ({n_keep} meshes)")
    elif os.path.exists(stand):
        for n,m,P,N,UV,F in meshes(stand):
            if not n or not re.search(r"^Tonneau(\d|$)|TonneauCover", n): continue
            P2,N2,F2=_ry_neg90(P,N,F)
            add(cat(n,m,"Cybertruck"),P2,F2,N2); n_keep+=1
        print(f"Cybertruck tonneau: CLOSED from standalone+Ry-90 ({n_keep} meshes)")
    else:
        print("Cybertruck tonneau: NO COVER ASSET FOUND (bed will look open)")
def add_b_pillars(add,P,F,N,UV):
    """Model Y Juniper's B pillars live on the dropped Interior mesh: the outer cover on its
    Trim surface and the inner trim on its Pillar surface. Keep only the triangles between
    the front and rear door windows, above the belt line."""
    c=P[F].mean(1)
    keep=(np.abs(c[:,0])>0.6)&(c[:,1]>1.0)&(c[:,1]<1.55)&(c[:,2]>0.05)&(c[:,2]<0.5)
    if not keep.any(): return
    F=F[keep]; used=np.unique(F); remap=-np.ones(len(P),np.int64); remap[used]=np.arange(len(used))
    add("Pillar",P[used],remap[F],N[used],None if UV is None else UV[used])
def build(name,carf,wheelf,paint):
    groups={}
    def add(k,P,F,N,UV=None):
        if not np.isfinite(N).all() or (np.linalg.norm(N,axis=1)<0.5).any():
            N=trimesh.Trimesh(P,F,process=False).vertex_normals
        if UV is None or len(UV)!=len(P): UV=np.zeros((len(P),2))
        groups.setdefault(k,[]).append((P,F,N,UV))
    for n,m,P,N,UV,F in meshes(R+carf+".glb"):
        if name=="ModelYJuniper" and n=="Interior" and (m or "").lower() in ("trim","pillar"):
            add_b_pillars(add,P,F,N,UV); continue
        if DROP_NODE.search(n or "") or drop_mat(m): continue
        ext=P.max(0)-P.min(0)
        if ext[1]<0.02 and ext[0]>1.5: continue  # flat ground/shadow cards
        k=cat(n,m,name)
        # *_Global lamp meshes are other-market variants on a different texture atlas.
        if k=="Lamps" and re.search(r"_global",n or "",re.I): continue
        add(k,P,F,N,UV)
    if name=="Cybertruck":
        add_cybertruck_tonneau(add)
    if wheelf:
        W={k:v for k,v in node_world(R+carf+".glb","Wheel_").items() if k.endswith("_Spatial") and "Steering" not in k}
        wm=list(meshes(R+wheelf+".glb"))
        for k,T in W.items():
            for n,m,P,N,UV,F in wm:
                P2=(np.c_[P,np.ones(len(P))]@T.T)[:,:3]
                N2=N@np.linalg.inv(T[:3,:3]); N2/=np.linalg.norm(N2,axis=1,keepdims=True)+1e-12
                F2=F[:,::-1] if np.linalg.det(T[:3,:3])<0 else F
                add("Tires" if re.search("tire|pirelli",m or "",re.I) else "Wheels",P2,F2,N2)
    out={}; uvs={}
    for k,lst in groups.items():
        off=0; Ps=[];Fs=[];Ns=[];UVs=[]
        for P,F,N,UV in lst: Ps.append(P); Fs.append(F+off); Ns.append(N); UVs.append(UV); off+=len(P)
        out[k]=trimesh.Trimesh(np.concatenate(Ps),np.concatenate(Fs),vertex_normals=np.concatenate(Ns),process=False)
        uvs[k]=np.concatenate(UVs)
    for f in [OUT+name+".usda"]:
        if os.path.exists(f): os.remove(f)
    st=Usd.Stage.CreateNew(OUT+name+".usda"); UsdGeom.SetStageUpAxis(st,"Y"); UsdGeom.SetStageMetersPerUnit(st,1)
    root=UsdGeom.Xform.Define(st,"/"+name); st.SetDefaultPrim(root.GetPrim())
    UsdGeom.Scope.Define(st,f"/{name}/Materials")
    sc=trimesh.Scene(); tot=0
    for k,tm in out.items():
        spec=MATS[k]; c=paint if k=="Paint" else spec["c"]
        mp=f"/{name}/Materials/{k}"; mat=UsdShade.Material.Define(st,mp); sh=UsdShade.Shader.Define(st,mp+"/PBR"); sh.CreateIdAttr("UsdPreviewSurface")
        sh.CreateInput("diffuseColor",Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*c))
        sh.CreateInput("metallic",Sdf.ValueTypeNames.Float).Set(spec["metallic"]); sh.CreateInput("roughness",Sdf.ValueTypeNames.Float).Set(spec["roughness"])
        if "opacity" in spec:
            sh.CreateInput("opacity",Sdf.ValueTypeNames.Float).Set(spec["opacity"])
            # Help RealityKit / Quick Look treat it as translucent glass
            try: sh.CreateInput("opacityThreshold",Sdf.ValueTypeNames.Float).Set(0.0)
            except Exception: pass
        mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(),"surface")
        m=UsdGeom.Mesh.Define(st,f"/{name}/{k}")
        m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(np.asarray(tm.vertices,np.float32)))
        m.CreateFaceVertexCountsAttr(Vt.IntArray([3]*len(tm.faces))); m.CreateFaceVertexIndicesAttr(Vt.IntArray(tm.faces.reshape(-1).tolist()))
        m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(np.asarray(tm.vertex_normals,np.float32))); m.SetNormalsInterpolation("vertex")
        # The lamp lens is one layer of smoke (Glass_Lights culls back faces); double-sided doubles it.
        m.CreateSubdivisionSchemeAttr("none"); m.CreateDoubleSidedAttr(k!="LampGlass")
        if k=="Lamps":
            # glTF UV origin is top left; USD st origin is bottom left.
            uv=np.asarray(uvs[k],np.float32).copy(); uv[:,1]=1-uv[:,1]
            pv=UsdGeom.PrimvarsAPI(m.GetPrim()).CreatePrimvar("st",Sdf.ValueTypeNames.TexCoord2fArray,UsdGeom.Tokens.vertex)
            pv.Set(Vt.Vec2fArray.FromNumpy(uv))
        m.CreateExtentAttr([Gf.Vec3f(*tm.bounds[0]),Gf.Vec3f(*tm.bounds[1])])
        UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(mat)
        pb=PBRMaterial(name=k,baseColorFactor=list(c)+[spec.get("opacity",1)],metallicFactor=spec["metallic"],roughnessFactor=spec["roughness"],
                       alphaMode="BLEND" if "opacity" in spec else "OPAQUE",doubleSided=k!="LampGlass")
        g=trimesh.Trimesh(tm.vertices,tm.faces,vertex_normals=tm.vertex_normals,visual=TextureVisuals(material=pb),process=False)
        sc.add_geometry(g,node_name=k,geom_name=k); tot+=len(tm.faces)
    st.GetRootLayer().Save()
    # Binary USDC inside the USDZ (ASCII USDA balloons ~3-4x and does not compress in the zip)
    usdc=OUT+name+".usdc"
    if os.path.exists(usdc): os.remove(usdc)
    Usd.Stage.Open(OUT+name+".usda").Export(usdc)
    usdz=OUT+name+".usdz"
    if os.path.exists(usdz): os.remove(usdz)
    UsdUtils.CreateNewUsdzPackage(usdc, usdz)
    sc.export(OUT+name+".glb")
    b=np.array([t.bounds for t in out.values()]); lo=b[:,0].min(0); hi=b[:,1].max(0)
    print(name,tot,"tris",{k:len(v.faces) for k,v in out.items()},"size",(hi-lo).round(2))
    return out
if __name__=="__main__":
    only=sys.argv[1:] or list(CARS)
    for n in only:
        c,w,p=CARS[n]; build(n,c,w,p)
