import re, numpy as np, godot
CARS={'Model3':'res://Ego/3_High/Model3_High.tscn','Model3Highland':'res://Ego/v2023/Poppyseed/Poppyseed.tscn','ModelY':'res://Ego/Y_High/ModelY_High.tscn','ModelYJuniper':'res://Ego/Bayberry/Bayberry.tscn','ModelS':'res://Ego/S_Palladium/S_Palladium.tscn','ModelX':'res://Ego/X_Palladium/X_Palladium.tscn','Cybertruck':'res://Ego/Cybertruck/Cybertruck.tscn'}
def light_nodes(p):
    """Node headers and transforms only (no resource loading)."""
    txt=open(godot.fs(p),encoding='utf-8').read()
    nodes=[]
    for m in re.finditer(r'^\[node ([^\n]*?)\]\s*\n((?:(?!\[)[^\n]*\n)*)',txt,re.M):
        h=m.group(1); body=m.group(2)
        name=re.search(r'name="([^"]+)"',h).group(1)
        par=re.search(r'parent="([^"]*)"',h); par=par.group(1) if par else None
        inst='instance=' in h
        t=re.search(r'^transform = Transform\(([^)]*)\)',body,re.M)
        T=[float(x) for x in t.group(1).split(',')] if t else None
        nodes.append((name,par,inst,T))
    return nodes
def anchors(car):
    nodes=light_nodes(CARS[car]); W={}; root=None; info=[]
    for name,par,inst,T in nodes:
        M=godot.xf(T)
        if par is None: root=name; W['.']=M; info.append(('root',name,inst,T)); continue
        key=name if par=='.' else par+'/'+name
        P=W.get(par if par!='.' else '.', None)
        if P is None: P=W.get('.',np.eye(4)); info.append(('missing parent',par))
        W[key]=P@M
        if par!='.' and inst: info.append(('instanced',key))
    out={}
    for k,M in W.items():
        m=re.search(r'Wheel_([LR][FR])_(Spatial|Marker)$',k)
        if m: out[m.group(1)]=M
    return out,info
if __name__=='__main__':
    for c in CARS:
        a,info=anchors(c)
        print(c,[i for i in info if i[0]!='instanced'][:3])
        for k in sorted(a): print('  ',k,np.round(a[k][:3,3],3), 'det',round(np.linalg.det(a[k][:3,:3]),3))
