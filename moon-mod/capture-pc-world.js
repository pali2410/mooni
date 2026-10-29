// Getter-only scene capture on the original game's main thread.
const knownMeshes = new Set(__KNOWN_MESHES__);
const knownTextures = new Set(__KNOWN_TEXTURES__);
function engineClass(name) {
  for(let i=0;i<count.readU64().toNumber();i++) {
    const im=imgOf(assemblies.add(i*8).readPointer());
    if(imgName(im).readCString().startsWith('UnityEngine.')){
      const found=api('class_from_name','pointer',['pointer','pointer','pointer'])(im,Memory.allocUtf8String('UnityEngine'),Memory.allocUtf8String(name));
      if(!found.isNull())return found;
    }
  }
  throw Error('Unity class unavailable: '+name);
}
function exact(c,name,types) {
  const it=Memory.alloc(8);it.writePointer(NULL);let m;
  while(!(m=api('class_get_methods','pointer',['pointer','pointer'])(c,it)).isNull()) {
    if(api('method_get_name','pointer',['pointer'])(m).readCString()!==name)continue;
    if(api('method_get_param_count','uint',['pointer'])(m)!==types.length)continue;
    const params=types.map((_,i)=>api('type_get_name','pointer',['pointer'])(api('method_get_param','pointer',['pointer','uint'])(m,i)).readCString());
    if(params.every((t,i)=>t===types[i]))return m;
  }
  throw Error('Method unavailable: '+name+'('+types+')');
}
const objectClass=engineClass('Object'), componentClass=engineClass('Component'), transformClass=engineClass('Transform');
const meshClass=engineClass('Mesh'), filterClass=engineClass('MeshFilter'), rendererClass=engineClass('Renderer');
const gameObjectClass=engineClass('GameObject'), colliderClass=engineClass('Collider');
const find=exact(objectClass,'FindObjectsByType',['System.Type','UnityEngine.FindObjectsInactive','UnityEngine.FindObjectsSortMode']);
const reflection=c=>api('type_get_object','pointer',['pointer'])(api('class_get_type','pointer',['pointer'])(c));
const zeroEnum=Memory.alloc(4);zeroEnum.writeS32(0);
const objects=c=>arr(invoke(find,NULL,[reflection(c),zeroEnum,zeroEnum]));
const getTransform=method(componentClass,'get_transform',0), getName=method(objectClass,'get_name',0);
const getPosition=method(transformClass,'get_position',0), getUp=method(transformClass,'get_up',0), getForward=method(transformClass,'get_forward',0);
const getMatrix=method(transformClass,'get_localToWorldMatrix',0), getParent=method(transformClass,'get_parent',0);
const getComponent=exact(componentClass,'GetComponent',['System.Type']);
const getGameObject=method(componentClass,'get_gameObject',0), getActive=method(gameObjectClass,'get_activeInHierarchy',0);
const getMesh=method(filterClass,'get_sharedMesh',0), getMaterials=method(rendererClass,'get_sharedMaterials',0);
const getEnabled=method(rendererClass,'get_enabled',0), getBounds=method(rendererClass,'get_bounds',0);
const getVertices=method(meshClass,'get_vertices',0), getNormals=method(meshClass,'get_normals',0), getUV=method(meshClass,'get_uv',0);
const getTriangles=method(meshClass,'get_triangles',0), getCount=method(meshClass,'get_vertexCount',0), getReadable=method(meshClass,'get_isReadable',0);
const getSubmeshCount=method(meshClass,'get_subMeshCount',0), getSubmeshTriangles=exact(meshClass,'GetTriangles',['System.Int32']);
const materialClass=engineClass('Material'), textureClass=engineClass('Texture'), texture2DClass=engineClass('Texture2D');
const hasProperty=exact(materialClass,'HasProperty',['System.String']), getTexture=exact(materialClass,'GetTexture',['System.String']);
const getColor=exact(materialClass,'GetColor',['System.String']), getFloat=exact(materialClass,'GetFloat',['System.String']);
const getShader=method(materialClass,'get_shader',0), textureWidth=method(textureClass,'get_width',0), textureHeight=method(textureClass,'get_height',0);
// Pixel readback APIs are stripped from this player; retain texture references.
const textureReadable=method(texture2DClass,'get_isReadable',0), pixels32=null;
const managedString=api('string_new','pointer',['pointer']);
const textArg=text=>managedString(Memory.allocUtf8String(text));
const rendererType=reflection(rendererClass);
const vector=(m,o,n=3)=>{const p=unbox(invoke(m,o));return Array.from({length:n},(_,i)=>p.add(i*4).readFloat());};
const name=o=>str(invoke(getName,o));
function path(transform) {
  const parts=[];let current=transform;
  for(let i=0;i<16&&!current.isNull();i++){parts.push(name(current));current=invoke(getParent,current);}
  return parts.reverse().join('/');
}
function buffer(m,o,components,args=[]){const a=invoke(m,o,args);const length=a.add(24).readU64().toNumber();return {length,bytes:new Uint8Array(a.add(32).readByteArray(length*components*4))};}
let phase=0, filters=[], index=0, anchor=null, exported=new Set(), failures=[], captured=0, skipped=0, processed=0;
let colliders=[],colliderIndex=0;
const materialRecords=new Map(), textureRecords=new Set();
function materialRecord(material) {
  if(material.isNull())return null;
  const id=material.toString();if(materialRecords.has(id))return materialRecords.get(id);
  const record={id,name:name(material),shader:name(invoke(getShader,material)),colors:{},floats:{},textures:{}};
  for(const key of ['_BaseColor','_Color','_EmissionColor','_EyeColor']){
    const arg=textArg(key);if(unbox(invoke(hasProperty,material,[arg])).readU8()){
      const value=unbox(invoke(getColor,material,[arg]));record.colors[key]=Array.from({length:4},(_,i)=>value.add(i*4).readFloat());
    }
  }
  for(const key of ['_Metallic','_Smoothness','_BumpScale','_EyeStyle','_Glow']){
    const arg=textArg(key);if(unbox(invoke(hasProperty,material,[arg])).readU8())record.floats[key]=unbox(invoke(getFloat,material,[arg])).readFloat();
  }
  for(const key of ['_BaseMap','_MainTex','_BumpMap','_EyeSheet']){
    const arg=textArg(key);if(!unbox(invoke(hasProperty,material,[arg])).readU8())continue;
    const texture=invoke(getTexture,material,[arg]);if(texture.isNull())continue;
    const textureId=texture.toString();const tex={id:textureId,name:name(texture)};record.textures[key]=tex;
    const klass=api('object_get_class','pointer',['pointer'])(texture);
    const klassName=api('class_get_name','pointer',['pointer'])(klass).readCString();
    if(pixels32&&klassName==='Texture2D'&&!knownTextures.has(tex.name)&&!textureRecords.has(textureId)&&unbox(invoke(textureReadable,texture)).readU8()){
      const width=unbox(invoke(textureWidth,texture)).readS32(),height=unbox(invoke(textureHeight,texture)).readS32();
      if(width*height<=2048*2048){
        const pixels=invoke(pixels32,texture,[zeroEnum]),length=pixels.add(24).readU64().toNumber();
        if(length===width*height){send({stage:'runtime_texture',id:textureId,name:tex.name,width,height},pixels.add(32).readByteArray(length*4));textureRecords.add(textureId);}
      }
    }
  }
  materialRecords.set(id,record);send({stage:'material',material:record});return record;
}
function near(bounds) {
  let d=0;
  for(let k=0;k<3;k++){const q=Math.max(0,Math.abs(bounds[k]-anchor.position[k])-bounds[k+3]);d+=q*q;}
  return d<180*180;
}
function collect(filter) {
  const owner=invoke(getGameObject,filter);
  if(!unbox(invoke(getActive,owner)).readU8()){skipped++;return;}
  const renderer=invoke(getComponent,filter,[rendererType]);
  if(renderer.isNull()||!unbox(invoke(getEnabled,renderer)).readU8()){skipped++;return;}
  const bounds=vector(getBounds,renderer,6);if(!near(bounds)){skipped++;return;}
  const mesh=invoke(getMesh,filter);if(mesh.isNull()){skipped++;return;}
  const transform=invoke(getTransform,filter), meshName=name(mesh), vertexCount=unbox(invoke(getCount,mesh)).readS32();
  if(vertexCount<=0||vertexCount>500000){skipped++;return;}
  const id=mesh.toString(), readable=!!unbox(invoke(getReadable,mesh)).readU8();
  const info={id, name:name(owner), path:path(transform),mesh_name:meshName,vertex_count:vertexCount,
    matrix:vector(getMatrix,transform,16),bounds,materials:arr(invoke(getMaterials,renderer)).map(m=>m.isNull()?null:name(m)),
    readable,known_source:knownMeshes.has(meshName+'|'+vertexCount)};
  info.material_ids=arr(invoke(getMaterials,renderer)).map(m=>{const r=materialRecord(m);return r?r.id:null;});
  send({stage:'instance',instance:info});captured++;
  if(!info.known_source&&readable&&!exported.has(id)) exportMesh(mesh,id,meshName);
}
function exportMesh(mesh,id,meshName){
    const vertices=buffer(getVertices,mesh,3),normals=buffer(getNormals,mesh,3),uv=buffer(getUV,mesh,2);
    const submeshes=[];
    const submeshCount=unbox(invoke(getSubmeshCount,mesh)).readS32();
    for(let i=0;i<submeshCount;i++){const arg=Memory.alloc(4);arg.writeS32(i);submeshes.push(buffer(getSubmeshTriangles,mesh,1,[arg]));}
    const chunks=[vertices.bytes,normals.bytes,uv.bytes,...submeshes.map(s=>s.bytes)];
    const joined=new Uint8Array(chunks.reduce((s,c)=>s+c.length,0));let offset=0;
    for(const chunk of chunks){joined.set(chunk,offset);offset+=chunk.length;}
    send({stage:'runtime_mesh',id,name:meshName,vertices:vertices.length,normals:normals.length,uv:uv.length,indices:submeshes.reduce((s,m)=>s+m.length,0),submesh_indices:submeshes.map(s=>s.length)},joined.buffer);
    exported.add(id);
}
function collectCollider(collider){
  if(!unbox(invoke(method(colliderClass,'get_enabled',0),collider)).readU8())return;
  if(unbox(invoke(method(colliderClass,'get_isTrigger',0),collider)).readU8())return;
  const t=invoke(getTransform,collider), p=path(t);
  if(!p.includes('/TheCollector')&&!/\/Terrain [^/]+$/.test(p))return;
  const bounds=vector(method(colliderClass,'get_bounds',0),collider,6);if(!near(bounds))return;
  const klass=api('object_get_class','pointer',['pointer'])(collider);
  const type=api('class_get_name','pointer',['pointer'])(klass).readCString();
  const record={path:p,type,matrix:vector(getMatrix,t,16),bounds};
  if(type==='BoxCollider'){record.center=vector(method(klass,'get_center',0),collider);record.size=vector(method(klass,'get_size',0),collider);}
  else if(type==='SphereCollider'||type==='CapsuleCollider'){
    record.center=vector(method(klass,'get_center',0),collider);record.radius=unbox(invoke(method(klass,'get_radius',0),collider)).readFloat();
    if(type==='CapsuleCollider'){record.height=unbox(invoke(method(klass,'get_height',0),collider)).readFloat();record.direction=unbox(invoke(method(klass,'get_direction',0),collider)).readS32();}
  }else if(type==='MeshCollider'){
    const mesh=invoke(method(klass,'get_sharedMesh',0),collider);if(mesh.isNull())return;
    record.mesh_id=mesh.toString();record.mesh_name=name(mesh);record.vertex_count=unbox(invoke(getCount,mesh)).readS32();
    if(!knownMeshes.has(record.mesh_name+'|'+record.vertex_count)&&!exported.has(record.mesh_id)&&unbox(invoke(getReadable,mesh)).readU8())exportMesh(mesh,record.mesh_id,record.mesh_name);
  }else return;
  send({stage:'collider',collider:record});
}
let busy=false,last=0;
Interceptor.attach(method(cls('MoonWorld'),'Update',0).readPointer(),{
  onEnter(){
    if(phase===2||busy)return;busy=true;
    try{
      if(phase===0){
        const intakes=objects(cls('MoonDepositIntake'));
        if(!intakes.length)return;
        const transform=invoke(getTransform,intakes[0]);
        anchor={position:vector(getPosition,transform),up:vector(getUp,transform),forward:vector(getForward,transform),name:name(intakes[0])};
        filters=objects(filterClass);colliders=objects(colliderClass);phase=1;send({stage:'capture_started',anchor,total_filters:filters.length});
        for(const door of objects(cls('MoonCollectorDoor'))){
          const frame=door.add(56).readPointer(); if(frame.isNull())continue;
          const leaves=arr(door.add(32).readPointer()), closed=door.add(40).readPointer(),open=door.add(48).readPointer();
          const readPoint=(a,i)=>Array.from({length:3},(_,k)=>a.add(32+i*12+k*4).readFloat());
          const trigger=invoke(getComponent,door,[reflection(colliderClass)]);
          send({stage:'door',door:{frame:vector(getMatrix,frame,16),seconds:door.add(64).readFloat(),
            amount:door.add(72).readFloat(),bounds:trigger.isNull()?null:vector(method(colliderClass,'get_bounds',0),trigger,6),
            leaves:leaves.map((leaf,i)=>{const t=invoke(getTransform,leaf);return {path:path(t),current:vector(getPosition,t),closed:readPoint(closed,i),open:readPoint(open,i)};})}});
        }
      }
      for(let budget=0;budget<12&&index<filters.length;budget++,index++) {
        try{collect(filters[index]);}catch(error){failures.push({index,error:String(error)});}
        processed++;
      }
      if(index>=filters.length){
        for(let budget=0;budget<30&&colliderIndex<colliders.length;budget++,colliderIndex++){
          try{collectCollider(colliders[colliderIndex]);}catch(error){failures.push({colliderIndex,error:String(error)});}
        }
        if(colliderIndex>=colliders.length){phase=2;send({stage:'world_complete',captured,skipped,processed,exported_meshes:exported.size,failures});}
      }
    }catch(error){phase=2;send({stage:'world_error',error:String(error),stack:error.stack});}
    finally{busy=false;}
  }
});
send({stage:'world_capture_ready',waiting_for:'running PC gameplay; read-only getters'});
