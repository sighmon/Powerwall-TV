import struct,sys,os,io,glob
from PIL import Image
import texture2ddecoder as T2D
def dec(path,out):
    d=open(path,'rb').read()
    assert d[:4]==b'GDST'
    w,cw,h,ch,flags,fmt=struct.unpack('<HHHHII',d[4:20])
    W,H=(cw or w),(ch or h)
    f=fmt&0xFFFFF; p=20
    if fmt&(1<<20) or fmt&(1<<21):
        n=struct.unpack('<I',d[p:p+4])[0]; p+=4
        sz=struct.unpack('<I',d[p:p+4])[0]; p+=4
        blob=d[p:p+sz]
        if blob[:4]==b'WEBP': blob=blob[4:]
        if blob[:4]==b'PNG ': blob=blob[4:]
        im=Image.open(io.BytesIO(blob)); im.load()
    else:
        raw=d[p:]
        if f==5: im=Image.frombytes('RGBA',(w,h),raw[:w*h*4])
        elif f==4: im=Image.frombytes('RGB',(w,h),raw[:w*h*3])
        elif f==0: im=Image.frombytes('L',(w,h),raw[:w*h])
        elif f==1: im=Image.frombytes('LA',(w,h),raw[:w*h*2])
        elif f in (29,35): im=Image.frombytes('RGBA',(w,h),T2D.decode_etc2(raw,w,h) if f==35 else T2D.decode_etc1(raw,w,h),'raw','BGRA')
        elif f==6:
            import numpy as np; a=np.frombuffer(raw[:w*h*2],'<u2').reshape(h,w); im=Image.fromarray(np.stack([(a>>12)&15,(a>>8)&15,(a>>4)&15,a&15],-1).astype('uint8')*17,'RGBA')
        elif f==36: im=Image.frombytes('RGBA',(w,h),T2D.decode_etc2a8(raw,w,h),'raw','BGRA')
        elif f==17: im=Image.frombytes('RGBA',(w,h),T2D.decode_bc1(raw,w,h),'raw','BGRA')
        elif f==19: im=Image.frombytes('RGBA',(w,h),T2D.decode_bc3(raw,w,h),'raw','BGRA')
        else: return 'fmt%d'%f
    im.save(out); return 'ok %dx%d fmt%d'%(w,h,f)
