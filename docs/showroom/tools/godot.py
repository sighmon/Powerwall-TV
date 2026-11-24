"""Read Tesla app Godot 3 scenes (text .tscn/.tres and binary .scn/.mesh/.material) into
flat mesh lists. Paths are res:// paths inside the recovered asset pack."""
import os, re, copy, numpy as np
import rsrc
from rsrc import ExtRef, SubRef
G=os.environ.get('TESLA_GODOT','/workspace/tesla-apk-latest/u/assets_pack/assets/godot/')

def fs(p): return G+p.replace('res://','')
def imported(p):
    """Source asset (obj/glb/fbx/png) -> its .import remap target."""
    f=fs(p)+'.import'
    if not os.path.exists(f): return p
    t=open(f).read()
    for m in re.findall(r'path(?:\.\w+)?="(res://[^"]+)"',t):
        if os.path.exists(fs(m)): return m
    raise FileNotFoundError(p)

# ---------- text resource parser ----------
TOK=re.compile(r'\s*(?:(?P<s>"(?:[^"\\]|\\.)*")|(?P<n>-?\d+\.?\d*(?:e[-+]?\d+)?)|(?P<id>[A-Za-z_][\w]*)|(?P<p>[\[\]{}(),:]))')
def parse_value(text):
    toks=[]; i=0
    while i<len(text):
        m=TOK.match(text,i)
        if not m:
            if text[i:].strip()=='' : break
            raise ValueError(text[i:i+40])
        i=m.end(); toks.append((m.lastgroup,m.group(m.lastgroup)))
    pos=[0]
    def nxt(): t=toks[pos[0]]; pos[0]+=1; return t
    def peek(): return toks[pos[0]] if pos[0]<len(toks) else (None,None)
    def val():
        k,v=nxt()
        if k=='s': return bytes(v[1:-1],'utf-8').decode('unicode_escape')
        if k=='n': return float(v) if re.search(r'[.e]',v) else int(v)
        if k=='p' and v=='[':
            out=[]
            while peek()[1]!=']':
                out.append(val())
                if peek()[1]==',': nxt()
            nxt(); return out
        if k=='p' and v=='{':
            out={}
            while peek()[1]!='}':
                kk=val(); nxt(); out[kk]=val()
                if peek()[1]==',': nxt()
            nxt(); return out
        if k=='id':
            if v in ('true','false'): return v=='true'
            if v=='null': return None
            if peek()[1]=='(':
                nxt(); args=[]
                while peek()[1]!=')':
                    args.append(val())
                    if peek()[1]==',': nxt()
                nxt()
                return ('call',v,args)
            return v
        raise ValueError((k,v))
    return val()

def parse_text(path):
    """-> dict(ext={id:(type,path)}, sub={id:(type,props)}, nodes=[(hdr,props)], resource=props, type)"""
    out=dict(ext={},sub={},nodes=[],resource={},type=None)
    cur=None
    lines=open(fs(path),encoding='utf-8').read().split('\n')
    buf=''
    for ln in lines:
        if buf:
            buf+='\n'+ln
            if buf.count('(')>buf.count(')') or buf.count('[')>buf.count(']') or buf.count('{')>buf.count('}') or buf.count('"')%2: continue
            k,v=buf.split('=',1); cur[k.strip()]=parse_value(v.strip()); buf=''; continue
        s=ln.strip()
        if not s or s.startswith(';'): continue
        if s.startswith('[') and s.endswith(']') and '=' not in s.split(' ',1)[0]:
            head=s[1:-1].split(' ',1); tag=head[0]; attrs={}
            if len(head)>1:
                for m in re.finditer(r'(\w+)=("(?:[^"\\]|\\.)*"|\w+\([^)]*\)|[^\s\]]+)',head[1]):
                    attrs[m.group(1)]=parse_value(m.group(2))
            props={}
            if tag in('gd_scene','gd_resource'): out['type']=attrs.get('type','PackedScene'); continue
            if tag=='ext_resource': out['ext'][attrs['id']]=(attrs['type'],attrs['path']); continue
            if tag=='sub_resource': out['sub'][attrs['id']]=(attrs['type'],props)
            elif tag=='node': out['nodes'].append((attrs,props))
            elif tag=='resource': out['resource']=props
            else: props={}
            cur=props; continue
        if '=' in s and cur is not None:
            k,v=s.split('=',1)
            vv=v.strip()
            if vv.count('(')>vv.count(')') or vv.count('[')>vv.count(']') or vv.count('{')>vv.count('}') or vv.count('"')%2:
                buf=s; continue
            cur[k.strip()]=parse_value(vv)
    return out

# ---------- resources ----------
class Res:
    def __init__(s,type_,props,path): s.type=type_; s.props=props; s.path=path
    def __repr__(s): return f"Res({s.type},{s.path})"
_cache={}
def load(path):
    """Load any res:// resource -> Res (materials, meshes, textures as path) or Scene tree."""
    if path in _cache: return _cache[path]
    p=imported(path)
    if p.endswith('.stex'): r=Res('Texture',{'stex':p,'source':path},path)
    elif p.endswith(('.tres','.tscn')): r=_load_text(p)
    else: r=_load_bin(p)
    _cache[path]=r; return r

def _resolve_text(v,t,subs):
    if isinstance(v,tuple) and v and v[0]=='call':
        _,fn,a=v
        if fn=='ExtResource': typ,pth=t['ext'][a[0]]; return load(pth)
        if fn=='SubResource': return subs[a[0]]
        if fn=='Color': return tuple(a)
        if fn=='Transform': return tuple(a)
        if fn in('Vector3','Vector2','Quat','Plane','Rect2','AABB','Basis'): return tuple(a)
        if fn=='PoolByteArray': return bytes(int(x) for x in a)
        if fn=='PoolIntArray': return np.array(a,np.int32)
        if fn=='PoolRealArray': return np.array(a,np.float32)
        if fn=='PoolVector3Array': return np.array(a,np.float32).reshape(-1,3)
        if fn=='PoolVector2Array': return np.array(a,np.float32).reshape(-1,2)
        if fn=='PoolColorArray': return np.array(a,np.float32).reshape(-1,4)
        if fn=='PoolStringArray': return list(a)
        return v
    if isinstance(v,list): return [_resolve_text(x,t,subs) for x in v]
    if isinstance(v,dict): return {k:_resolve_text(x,t,subs) for k,x in v.items()}
    return v

def _load_text(p):
    t=parse_text(p); subs={}
    for sid,(typ,props) in t['sub'].items():
        subs[sid]=Res(typ,None,p+'::'+str(sid))
    for sid,(typ,props) in t['sub'].items():
        subs[sid].props={k:_resolve_text(v,t,subs) for k,v in props.items()}
        if typ=='ArrayMesh' or typ=='CubeMesh': pass
    if t['type']!='PackedScene':
        return Res(t['type'],{k:_resolve_text(v,t,subs) for k,v in t['resource'].items()},p)
    root=None; byPath={}
    for attrs,props in t['nodes']:
        props={k:_resolve_text(v,t,subs) for k,v in props.items()}
        name=attrs['name']; parent=attrs.get('parent')
        if 'instance' in attrs:
            base=_resolve_text(attrs['instance'],t,subs)
            n=copy.deepcopy(base); n.name=name
            if 'type' in attrs: n.type=attrs['type']
        else:
            n=None
        if parent is None:
            if n is None: n=Node(name,attrs.get('type','Spatial'))
            n.props.update(props); root=n; continue
        par=root if parent=='.' else root.find(parent)
        if par is None: continue
        if n is None:
            existing=par.children.get(name)
            if existing is not None and 'type' not in attrs:
                existing.props.update(props); continue
            n=Node(name,attrs.get('type','Spatial'))
        n.props.update(props); par.children[name]=n
    return root

class Node:
    def __init__(s,name,type_): s.name=name; s.type=type_; s.props={}; s.children={}
    def find(s,path):
        n=s
        for part in path.split('/'):
            if part in('','.'): continue
            n=n.children.get(part)
            if n is None: return None
        return n
    def __deepcopy__(s,memo):
        n=Node(s.name,s.type); n.props=dict(s.props); n.children={k:copy.deepcopy(v,memo) for k,v in s.children.items()}; return n

def _load_bin(p):
    rtype,ext,res=rsrc.load(fs(p))
    local={}
    for rp,typ,props in res:
        idx=int(rp.split('://')[-1].split('::')[-1]) if '://' in rp and rp.startswith('local') else None
        r=Res(typ,props,rp)
        if idx is not None: local[idx]=r
        last=r
    def fix(v):
        if isinstance(v,ExtRef): return load(v.path)
        if isinstance(v,SubRef): return local.get(v.i)
        if isinstance(v,dict): return {k:fix(x) for k,x in v.items()}
        if isinstance(v,list): return [fix(x) for x in v]
        return v
    for r in list(local.values())+[last]:
        if r.type!='PackedScene': r.props={k:fix(v) for k,v in r.props.items()}
    if last.type=='PackedScene':
        return _bundled(last.props['_bundled'],fix,p)
    last.path=p
    if last.type=='ArrayMesh': last.mesh_file=fs(p)
    return last

def _bundled(b,fix,p):
    names=b['names']; variants=[fix(v) for v in b['variants']]; nd=list(b['nodes']); i=0
    nodes=[]; root=None
    for _ in range(b['node_count']):
        parent,owner,typ,name,inst=nd[i:i+5]; i+=5
        pc=nd[i]; i+=1; props={}
        for _ in range(pc):
            k,v=nd[i],nd[i+1]; i+=2; props[names[k]]=variants[v]
        gc=nd[i]; i+=1+gc
        nm=names[name&0x3fffffff] if (name&0x3fffffff)<len(names) else 'Node'
        if inst>=0 and inst!=0x7fffffff:
            base=variants[inst&0x7fffffff]; n=copy.deepcopy(base); n.name=nm
        else:
            n=Node(nm,names[typ] if 0<=typ<len(names) else 'Spatial')
        n.props.update(props)
        if parent<0 or parent==0x7fffffff:
            root=n
        else:
            if parent & (1<<30):
                par=root.find(b['node_paths'][parent&~(1<<30)])
            else: par=nodes[parent]
            par.children[nm]=n
        nodes.append(n)
    return root

# ---------- flattening ----------
def xf(t):
    if t is None: return np.eye(4)
    m=np.eye(4); m[:3,:3]=np.array(t[:9]).reshape(3,3); m[:3,3]=t[9:12]; return m

def walk(node,M=np.eye(4),path=''):
    """yield (path,node,world)"""
    if node.props.get('visible',True) is False: return
    W=M@xf(node.props.get('transform'))
    p=(path+'/'+node.name) if path else node.name
    yield p,node,W
    for c in node.children.values(): yield from walk(c,W,p)

def mesh_surfaces(mesh_res):
    """(surface dicts with resolved material) for an ArrayMesh Res."""
    out=[]
    for k,s in enumerate(rsrc.surfaces_of(mesh_res.props)):
        m=mesh_res.props.get(f'surfaces/{k}',{}).get('material')
        s['material']=m if isinstance(m,Res) else None
        out.append(s)
    return out

def scene_meshes(path):
    """Flatten a scene -> [(nodepath, surfaces(list), world 4x4)] with per-node material overrides applied."""
    root=load(path); out=[]
    for p,n,W in walk(root):
        mesh=n.props.get('mesh')
        if n.type!='MeshInstance' and mesh is None: continue
        if not isinstance(mesh,Res) or mesh.type!='ArrayMesh': continue
        surfs=mesh_surfaces(mesh)
        for k,s in enumerate(surfs):
            o=n.props.get(f'material/{k}')
            if isinstance(o,Res): s['material']=o
            mo=n.props.get('material_override')
            if isinstance(mo,Res): s['material']=mo
        out.append((p,surfs,W))
    return out
