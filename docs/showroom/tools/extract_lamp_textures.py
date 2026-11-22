import sys,re,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__))); from stex import dec
G='/workspace/tesla-apk-latest/u/assets_pack/assets/godot/'
T={'Model3':('3_High/Textures/Lights_BC.png','3_High/Textures/Lights_MRA.png'),
 'ModelY':('Y_High/Textures/Lights_BC_Y_High.png','Y_High/Textures/Lights_MRA_Y_High.png'),
 'ModelS':('S_Palladium/Textures/Lights_BC.png','S_Palladium/Textures/Lights_MRA.png'),
 'ModelX':('X_Palladium/Textures/Lights_BC.png','X_Palladium/Textures/Lights_MRA.png'),
 'Model3Highland':('v2023/Poppyseed/Textures/Lights_BC.png','v2023/Poppyseed/Textures/Lights_MRA.png'),
 'Cybertruck':('Cybertruck/Textures/Lights_BC.png','Cybertruck/Textures/Lights_RA.png')}
for car,(bc,mra) in T.items():
    for kind,p in (('BC',bc),('MRA',mra)):
        imp=open(G+'Ego/'+p+'.import').read()
        paths=re.findall(r'path(?:\.\w+)?="res://(.*?\.stex)"',imp)
        src=next(G+x for x in paths if os.path.exists(G+x))
        out=f'{car}_Lamps_{kind}.png'
        print(car,kind,src.split('/')[-1],dec(src,out))
