"""Package the original static base and generated ground without copying saved machines."""
from pathlib import Path
import collections, json, shutil, struct
import numpy as np

root = Path(__file__).resolve().parent.parent / 'MoonSweepers-Native-Rebuild'
capture = json.loads((root/'analysis/pc-world-capture/scene.json').read_text())
assert capture['completion']['stage'] == 'world_complete' and not capture['completion']['failures']
out = root/'game/assets/pc_world'; out.mkdir(exist_ok=True)
inventory = json.loads((root/'analysis/mesh-inventory.json').read_text())
by_name = collections.defaultdict(list)
for record in inventory: by_name[(record['name'],record['vertices'])].append(record)
materials = json.loads((root/'game/assets/materials.json').read_text())
material_names = collections.defaultdict(list)
for path, record in materials.items(): material_names[record.get('m_Name','')].append(path)
texture_names = {p.stem:'res://'+p.relative_to(root/'game').as_posix() for p in (root/'game/assets').rglob('*.png')}
anchor = np.array(capture['anchor']['position']); flip = np.diag([1.,1.,-1.,1.])
offset = np.array([0.,0.,-10.]) - anchor*np.array([1,1,-1])
mesh_map = {}; instances=[]; unresolved=[]; runtime_materials={}; terrain=[]
for instance in capture['instances']:
    path = instance['path']; is_ground = '/Terrain ' in path and len(path.split('/')) == 2
    if '/TheCollector/' not in path and not is_ground: continue
    # Animated/personal display contents require their original simulation, not frozen pictures.
    if any(part in path for part in ['/Live game Moon display','/Readout screen/']): continue
    candidates = by_name[(instance['mesh_name'],instance['vertex_count'])]
    if len(candidates) == 1:
        record = candidates[0]; key=record['file']; mesh_map[key]=record
    elif instance['id'] in capture['runtime_meshes']:
        record = capture['runtime_meshes'][instance['id']]
        filename=instance['id']+'.bin'; shutil.copy2(root/record['file'],out/filename)
        key='res://assets/pc_world/'+filename; mesh_map[key]={'file':key,'vertices':record['vertices']}
    else:
        unresolved.append({'path':path,'mesh':instance['mesh_name'],'candidates':len(candidates)});continue
    matrix = np.array(instance['matrix']).reshape((4,4),order='F')
    matrix = flip@matrix@flip; matrix[:3,3]+=offset
    material_ids=[]
    for mid in instance['material_ids']:
        if mid is None: material_ids.append('');continue
        mat=capture['materials'][mid]; material_ids.append(mid)
        runtime_materials[mid]={**mat,'source_paths':material_names.get(mat['name'],[])}
        for texture in runtime_materials[mid]['textures'].values(): texture['file']=texture_names.get(texture['name'],'')
    entry={'path':path,'mesh':key,'matrix':matrix.flatten(order='F').tolist(),'materials':material_ids,'ground':is_ground}
    instances.append(entry)
    if is_ground: terrain.append(entry)

def read_mesh(key):
    p=root/'game'/mesh_map[key]['file'].removeprefix('res://')
    data=p.read_bytes();magic,n,s=struct.unpack_from('<4sII',data);assert magic==b'MSW1'
    verts=np.frombuffer(data,dtype='<f4',count=n*3,offset=12).reshape(n,3).astype(float)
    offset=12+n*32;tri=[]
    for _ in range(s):
        count=struct.unpack_from('<I',data,offset)[0];offset+=4
        tri.append(np.frombuffer(data,dtype='<i4',count=count,offset=offset).reshape(-1,3));offset+=count*4
    return verts,np.concatenate(tri)

colliders=[]
for source in capture.get('colliders',[]):
    record=dict(source);m=flip@np.array(source['matrix']).reshape((4,4),order='F')@flip;m[:3,3]+=offset
    record['matrix']=m.flatten(order='F').tolist();record['ground']='/Terrain ' in source['path']
    if 'center' in record:record['center']=(np.array(record['center'])*[1,1,-1]).tolist()
    if source['type']=='MeshCollider':
        candidates=by_name[(source['mesh_name'],source['vertex_count'])]
        if len(candidates)==1:
            mesh=candidates[0];key=mesh['file'];mesh_map[key]=mesh
        elif source['mesh_id'] in capture['runtime_meshes']:
            mesh=capture['runtime_meshes'][source['mesh_id']];filename=source['mesh_id']+'.bin'
            shutil.copy2(root/mesh['file'],out/filename);key='res://assets/pc_world/'+filename;mesh_map[key]={'file':key,'vertices':mesh['vertices']}
        else:raise ValueError('Original collision geometry unavailable: '+source['path'])
        record['mesh']=key
    colliders.append(record)
assert len(colliders)>0,'Original physical colliders are required'

# Sample actual bare terrain under the playable cleaning patch, including its slopes.
origin=np.array([-22.8,-22.8]); step=.2; n=129
heights=np.full((n,n),-np.inf)
for entry in terrain:
    verts,triangles=read_mesh(entry['mesh']);m=np.array(entry['matrix']).reshape((4,4),order='F')
    verts=verts@m[:3,:3].T+m[:3,3]
    for indices in triangles:
        tri=verts[indices]; planar=tri[:,[0,2]]
        low=np.maximum(0,np.ceil((planar.min(axis=0)-origin)/step).astype(int))
        high=np.minimum(n-1,np.floor((planar.max(axis=0)-origin)/step).astype(int))
        if np.any(low>high):continue
        a,b,c=planar;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den)<1e-10:continue
        zz,xx=np.mgrid[low[1]:high[1]+1,low[0]:high[0]+1];px=origin[0]+xx*step;pz=origin[1]+zz*step
        u=((b[1]-c[1])*(px-c[0])+(c[0]-b[0])*(pz-c[1]))/den
        v=((c[1]-a[1])*(px-c[0])+(a[0]-c[0])*(pz-c[1]))/den;w=1-u-v
        mask=(u>=-1e-6)&(v>=-1e-6)&(w>=-1e-6)
        h=u*tri[0,1]+v*tri[1,1]+w*tri[2,1]
        heights[zz[mask],xx[mask]]=np.maximum(heights[zz[mask],xx[mask]],h[mask])
assert np.isfinite(heights).all(), 'Cleaning patch must be entirely backed by original terrain'
doors=[]
for door in capture.get('doors',[]):
    if not any('/TheCollector/' in leaf['path'] for leaf in door['leaves']):continue
    frame=np.array(door['frame']).reshape((4,4),order='F')
    def point(p): return (np.array(p)*[1,1,-1]+offset).tolist()
    def local_point(p): return point((frame@np.array([*p,1]))[:3])
    leaves=[{'key':leaf['path'].split('/')[-1],'current':point(leaf['current']), 'closed':local_point(leaf['closed']),'open':local_point(leaf['open'])} for leaf in door['leaves']]
    doors.append({'seconds':door['seconds'],'center':point(door['bounds'][:3]),'extents':door['bounds'][3:],'leaves':leaves})
manifest={'version':1,'source':'Getter-only original PC scene capture; static environment and measured sliding-door parameters','anchor':capture['anchor'],
    'instances':instances,'meshes':mesh_map,'materials':runtime_materials,'unresolved':unresolved,
    'terrain_grid':{'origin':origin.tolist(),'step':step,'n':n,'heights':heights.flatten().tolist()},
    'spawn':[-8.,float(heights[64,74])+1.,-10.], 'spawn_yaw':-np.pi/2,
    'intake':[0,0,-10], 'shop':[9.04,0,-25.18], 'doors':doors,'colliders':colliders}
(out/'world.json').write_text(json.dumps(manifest,separators=(',',':')))
report={'instances':len(instances),'terrain_chunks':len(terrain),'original_colliders':len(colliders),'sliding_doors':len(doors),
    'unresolved':unresolved,'terrain_height_range':[float(heights.min()),float(heights.max())],
    'excluded':'Player, saved robots/factories/belts/canisters, separate saved dust sheets, dynamic personal displays',
    'limitations':'Static scene geometry and converted materials only; original Unity shaders and all gameplay systems are not reconstructed.'}
(root/'analysis/captured-world-import.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
