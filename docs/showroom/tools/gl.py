import numpy as np
from pygltflib import GLTF2
def local(n):
    if n.matrix: return np.array(n.matrix).reshape(4,4).T
    t=np.array(n.translation or [0,0,0]); r=n.rotation or [0,0,0,1]; s=np.array(n.scale or [1,1,1])
    x,y,z,w=r; R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    m=np.eye(4); m[:3,:3]=R*s; m[:3,3]=t; return m
def worlds(g):
    W={}
    def rec(i,P):
        W[i]=P@local(g.nodes[i])
        for c in g.nodes[i].children or []: rec(c,W[i])
    for r in g.scenes[g.scene or 0].nodes: rec(r,np.eye(4))
    return W
def acc(g,i,blob):
    a=g.accessors[i]; bv=g.bufferViews[a.bufferView]
    nc={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a.type]
    dt={5126:np.float32,5125:np.uint32,5123:np.uint16,5121:np.uint8}[a.componentType]
    off=(bv.byteOffset or 0)+(a.byteOffset or 0); isz=np.dtype(dt).itemsize*nc; st=bv.byteStride or isz
    raw=np.frombuffer(blob,np.uint8,count=st*(a.count-1)+isz,offset=off)
    idx=(np.arange(a.count)[:,None]*st+np.arange(isz)[None,:])
    return raw[idx].copy().view(dt).reshape(a.count,nc)
def meshes(path):
    """yield (nodename, matname, P(world), N, UV or None, F)"""
    g=GLTF2().load(path); W=worlds(g); blob=g.binary_blob()
    for i,n in enumerate(g.nodes):
        if n.mesh is None or i not in W: continue
        for p in g.meshes[n.mesh].primitives:
            P=acc(g,p.attributes.POSITION,blob).astype(float)
            N=acc(g,p.attributes.NORMAL,blob).astype(float) if p.attributes.NORMAL is not None else np.zeros_like(P)
            UV=acc(g,p.attributes.TEXCOORD_0,blob).astype(float) if p.attributes.TEXCOORD_0 is not None else None
            F=acc(g,p.indices,blob).reshape(-1,3).astype(np.int64) if p.indices is not None else np.arange(len(P)).reshape(-1,3)
            m=W[i]; P=(np.c_[P,np.ones(len(P))]@m.T)[:,:3]
            N=N@np.linalg.inv(m[:3,:3]); N/=np.linalg.norm(N,axis=1,keepdims=True)+1e-12
            if np.linalg.det(m[:3,:3])<0: F=F[:,::-1]
            mat=g.materials[p.material].name if p.material is not None else None
            yield n.name,mat,P,N,UV,F
def node_world(path,name):
    g=GLTF2().load(path); W=worlds(g)
    return {g.nodes[i].name:W[i] for i in W if g.nodes[i].name and name in g.nodes[i].name}
