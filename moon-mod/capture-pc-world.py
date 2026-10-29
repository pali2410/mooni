"""Read the running original world; keep layout and generated mesh evidence separate."""
from pathlib import Path
import sys, json, threading, struct
import numpy as np
from PIL import Image

base=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(base/'moon-mod/python-deps'))
import frida
root=base/'MoonSweepers-Native-Rebuild'; output=root/'analysis/pc-world-capture'; output.mkdir(exist_ok=True)
mesh_records=json.loads((root/'analysis/mesh-inventory.json').read_text())
known=list({m['name']+'|'+str(m['vertices']) for m in mesh_records})
textures=[p.stem for p in (root/'game/assets').rglob('*.png')]
source=(base/'moon-mod/game-api.js').read_text()+'\n'+(base/'moon-mod/capture-pc-world.js').read_text().replace('__KNOWN_MESHES__',json.dumps(known)).replace('__KNOWN_TEXTURES__',json.dumps(textures))
device=frida.get_local_device(); process=next(p for p in device.enumerate_processes() if p.name.lower()=='moonsweepers.exe')
session=device.attach(process.pid); finished=threading.Event()
result={'source':'Original running PC game, getter-only main-thread capture','instances':[],'runtime_meshes':{},'materials':{},'textures':{},'doors':[],'colliders':[]}
def message(msg,data):
    if msg['type']!='send': print(msg,flush=True);finished.set();return
    item=msg['payload'];stage=item.get('stage')
    if stage=='instance':result['instances'].append(item['instance'])
    elif stage=='door':result['doors'].append(item['door'])
    elif stage=='collider':result['colliders'].append(item['collider'])
    elif stage=='material':result['materials'][item['material']['id']]=item['material']
    elif stage=='runtime_texture':
        target=output/(item['id']+'.png')
        Image.frombytes('RGBA',(item['width'],item['height']),data).transpose(Image.Transpose.FLIP_TOP_BOTTOM).save(target)
        result['textures'][item['id']]={**item,'file':str(target.relative_to(root))}
    elif stage=='runtime_mesh':
        n=item['vertices']; offsets=[n*12,item['normals']*12,item['uv']*8,item['indices']*4]
        pos=0; parts=[]
        for size in offsets:parts.append(data[pos:pos+size]);pos+=size
        vertices=np.frombuffer(parts[0],dtype='<f4').copy().reshape(n,3);vertices[:,2]*=-1
        normals=np.frombuffer(parts[1],dtype='<f4').copy().reshape(-1,3) if item['normals']==n else np.tile([0,1,0],(n,1)).astype('<f4')
        normals[:,2]*=-1
        uv=parts[2] if item['uv']==n else bytes(n*8)
        target=output/(item['id']+'.bin')
        with target.open('wb') as f:
            f.write(struct.pack('<4sII',b'MSW1',n,len(item['submesh_indices'])));f.write(vertices.tobytes());f.write(normals.tobytes());f.write(uv)
            index_offset=0
            for count in item['submesh_indices']:
                f.write(struct.pack('<I',count));f.write(parts[3][index_offset:index_offset+count*4]);index_offset+=count*4
        result['runtime_meshes'][item['id']]={**item,'file':str(target.relative_to(root))}
    elif stage=='capture_started':
        result['anchor']=item['anchor'];result['total_filters']=item['total_filters'];print(json.dumps(item),flush=True)
    elif stage in ('world_complete','world_error'):
        result['completion']=item;print(json.dumps(item),flush=True);finished.set()
    else:print(json.dumps(item),flush=True)
handle=session.create_script(source);handle.on('message',message);handle.load()
finished.wait(75);session.detach()
complete=result.get('completion',{}).get('stage')=='world_complete'
(output/('scene.json' if complete else 'scene.partial.json')).write_text(json.dumps(result,indent=2))
print('Captured',len(result['instances']),'visible instances and',len(result['runtime_meshes']),'generated meshes.',flush=True)
if not complete:raise SystemExit('World capture incomplete; see the saved report.')
