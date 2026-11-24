import re, godot, numpy as np, os, json
src=open('/workspace/tesla-apk-latest/gdre/VehicleOptions.gd').read()
paths=sorted(set(re.findall(r'NodePath\("(res://Ego/[^"]+\.tscn)"\)',src.split('const MobileWheelTypeEnumMap')[0].split('const WheelTypeToPathMap')[1])))
paths=[p for p in paths if 'Cybercab' not in p]
if __name__=='__main__':
    tex=set(); bad=[]
    for p in paths:
        try: ms=godot.scene_meshes(p)
        except Exception as e: bad.append((p,repr(e))); continue
        tris=0; mats=[]
        for np_,surfs,W in ms:
            for s in surfs:
                tris+=len(s['F']); m=s['material']
                d=None
                if m is not None:
                    d=m.type+':'+m.path.split('/')[-1]
                    for k,v in m.props.items():
                        if isinstance(v,godot.Res) and v.type=='Texture': tex.add(v.props['stex']); d+=f' {k}'
                mats.append(d)
        print(f"{p.replace('res://Ego/','')}: {tris} tris; {mats}")
    print(len(paths),'paths;',len(tex),'textures', sum(os.path.getsize(godot.fs(t)) for t in tex)//1024,'KB stex')
    print('BAD',bad)

def extents(p):
    lo=np.full(3,9.);hi=np.full(3,-9.)
    for _,surfs,W in godot.scene_meshes(p):
        for s in surfs:
            P=(np.c_[s['P'],np.ones(len(s['P']))]@W.T)[:,:3]; lo=np.minimum(lo,P.min(0)); hi=np.maximum(hi,P.max(0))
    return lo,hi
