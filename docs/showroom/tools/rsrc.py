"""Minimal reader for Godot 3.x binary resources (RSRC, format 3): ArrayMesh .mesh and
SpatialMaterial .material files from the Tesla app's asset pack. Read-only, no Godot needed."""
import struct, numpy as np

class R:
    def __init__(s, d): s.d=d; s.o=0
    def u32(s): v=struct.unpack_from('<I',s.d,s.o)[0]; s.o+=4; return v
    def i32(s): v=struct.unpack_from('<i',s.d,s.o)[0]; s.o+=4; return v
    def u64(s): v=struct.unpack_from('<Q',s.d,s.o)[0]; s.o+=8; return v
    def f32(s,n=1):
        v=struct.unpack_from('<%df'%n,s.d,s.o); s.o+=4*n; return v if n>1 else v[0]
    def ustr(s):
        n=s.u32(); b=s.d[s.o:s.o+n]; s.o+=n; return b.rstrip(b'\0').decode('utf-8','replace')

class ExtRef:
    def __init__(s,type_,path): s.type=type_; s.path=path
    def __repr__(s): return f"ExtRef({s.type},{s.path})"
class SubRef:
    def __init__(s,i): s.i=i
    def __repr__(s): return f"SubRef({s.i})"

def decompress(d):
    """Godot 3 FileAccessCompressed (RSCC): blocks of zstd/deflate data."""
    import zlib
    mode,bs,total=struct.unpack_from('<III',d,4); n=(total+bs-1)//bs
    sizes=struct.unpack_from('<%dI'%n,d,16); o=16+4*n; out=bytearray()
    for i,z in enumerate(sizes):
        blk=d[o:o+z]; o+=z; want=min(bs,total-i*bs)
        if mode==2:
            import zstandard; out+=zstandard.ZstdDecompressor().decompress(blk,max_output_size=want)
        elif mode in (1,3): out+=zlib.decompress(blk, -15 if mode==1 else 31)
        else: raise ValueError('compression mode %d'%mode)
    return bytes(out)

def load(path):
    d=open(path,'rb').read()
    shift=0
    if d[:4]==b'RSCC': d=b'RSRC'+decompress(d); shift=4
    r=R(d)
    assert d[:4]==b'RSRC', path
    r.o=4; be,r64,vmaj,vmin,vfmt=[r.u32() for _ in range(5)]
    assert be==0 and r64==0, 'only little-endian 32-bit reals'
    rtype=r.ustr(); r.u64(); [r.u32() for _ in range(14)]
    names=[r.ustr() for _ in range(r.u32())]
    ext=[ExtRef(r.ustr(),r.ustr()) for _ in range(r.u32())]
    internal=[(r.ustr(),r.u64()+shift) for _ in range(r.u32())]
    def var():
        t=r.u32()
        if t==1: return None
        if t==2: return bool(r.u32())
        if t==3: return r.i32()
        if t==4: return r.f32()
        if t==5: return r.ustr()
        if t==10: return r.f32(2)
        if t==11: return r.f32(4)
        if t==12: return r.f32(3)
        if t==13: return r.f32(4)
        if t==14: return r.f32(4)
        if t==15: return r.f32(6)
        if t==16: return r.f32(9)
        if t==17: return r.f32(12)
        if t==18: return r.f32(6)
        if t==20: return r.f32(4)
        if t==22:  # node path
            nn=r.u32()&0x7fff; ns=r.u32(); r.u32(); 
            return '/'.join(names[r.u32()] for _ in range(nn+ns))
        if t==23: r.u32(); return None
        if t==24:
            k=r.u32()
            if k==0: return None
            if k==1: return ExtRef(r.ustr(),r.ustr())
            if k==2: return SubRef(r.u32())
            if k==3: return ext[r.u32()]
            raise ValueError(k)
        if t==26:
            n=r.u32()&0x7fffffff; out={}
            for _ in range(n):
                k=var(); out[k]=var()
            return out
        if t==30:
            n=r.u32()&0x7fffffff; return [var() for _ in range(n)]
        if t==31:
            n=r.u32(); b=d[r.o:r.o+n]; r.o+=n; r.o+=(4-n%4)%4; return bytes(b)
        if t==32:
            n=r.u32(); a=np.frombuffer(d,np.int32,n,r.o); r.o+=4*n; return a
        if t==33:
            n=r.u32(); a=np.frombuffer(d,np.float32,n,r.o); r.o+=4*n; return a
        if t==34:
            n=r.u32(); return [r.ustr() for _ in range(n)]
        if t==35:
            n=r.u32(); a=np.frombuffer(d,np.float32,3*n,r.o).reshape(n,3); r.o+=12*n; return a
        if t==36:
            n=r.u32(); a=np.frombuffer(d,np.float32,4*n,r.o).reshape(n,4); r.o+=16*n; return a
        if t==37:
            n=r.u32(); a=np.frombuffer(d,np.float32,2*n,r.o).reshape(n,2); r.o+=8*n; return a
        if t==40: v=struct.unpack_from('<q',d,r.o)[0]; r.o+=8; return v
        if t==41: v=struct.unpack_from('<d',d,r.o)[0]; r.o+=8; return v
        raise ValueError(f'variant {t} at {r.o}')
    res=[]
    for p,off in internal:
        r.o=off; t=r.ustr(); props={}
        for _ in range(r.u32()):
            nm=names[r.u32()]; props[nm]=var()
        res.append((p,t,props))
    return rtype,ext,res

def _half(b): return np.frombuffer(b,np.float16).astype(np.float32)
def surfaces(path):
    """yield dict(P,N,UV,F,material) per surface of an ArrayMesh file."""
    _,ext,res=load(path)
    yield from surfaces_of(res[-1][2])

def surfaces_of(main):
    k=0
    while f'surfaces/{k}' in main:
        s=main[f'surfaces/{k}']; k+=1
        yield decode_surface(s)

def decode_surface(s):
    if True:
        fmt=s['format']; vc=s['vertex_count']; data=s['array_data']
        C=lambda bit: fmt&(1<<(9+bit))
        layout=[]
        if fmt&1: layout.append(('P', 8 if C(0) else 12))
        if fmt&2: layout.append(('N', 4 if C(1) else 12))
        if fmt&4: layout.append(('T', 4 if C(2) else 16))
        if fmt&8: layout.append(('C', 4 if C(3) else 16))
        if fmt&16: layout.append(('UV', 4 if C(4) else 8))
        if fmt&32: layout.append(('UV2', 4 if C(5) else 8))
        if fmt&64: layout.append(('B', 8 if fmt&(1<<19) else 4))
        if fmt&128: layout.append(('W', 8 if C(7) else 16))
        stride=sum(z for _,z in layout)
        assert stride*vc==len(data), (fmt,stride,vc,len(data),len(data)/vc)
        a=np.frombuffer(data,np.uint8).reshape(vc,stride); off=0; out={}
        for nm,z in layout:
            col=a[:,off:off+z].copy(); off+=z
            if nm=='P': out['P']=(_half(col.tobytes()).reshape(vc,4)[:,:3] if z==8 else col.view(np.float32).reshape(vc,3))
            elif nm=='N': out['N']=(col.view(np.int8).reshape(vc,4)[:,:3].astype(np.float32)/127 if z==4 else col.view(np.float32).reshape(vc,3))
            elif nm=='UV': out['UV']=(_half(col.tobytes()).reshape(vc,2) if z==4 else col.view(np.float32).reshape(vc,2))
            elif nm=='UV2': out['UV2']=(_half(col.tobytes()).reshape(vc,2) if z==4 else col.view(np.float32).reshape(vc,2))
        if fmt&256:
            ic=s['index_count']; ib=s['array_index_data']
            F=np.frombuffer(ib, np.uint16 if vc<65536 else np.uint32, ic).astype(np.int64)
        else:
            F=np.arange(vc)
        F=F.reshape(-1,3)[:,::-1]  # Godot front faces are clockwise
        out['F']=F; out['material']=s.get('material'); out['name']=s.get('name')
        out['P']=out['P'].astype(np.float64)
        if 'N' in out: out['N']=out['N'].astype(np.float64)
        return out
