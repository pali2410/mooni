const mod=Process.getModuleByName('GameAssembly.dll');
const api=(n,r,a)=>new NativeFunction(mod.getExportByName('il2cpp_'+n),r,a);
const domain=api('domain_get','pointer',[])();api('thread_attach','pointer',['pointer'])(domain);
const count=Memory.alloc(8),assemblies=api('domain_get_assemblies','pointer',['pointer','pointer'])(domain,count);
const imgOf=api('assembly_get_image','pointer',['pointer']);
const imgName=api('image_get_name','pointer',['pointer']);
let image;
for(let i=0;i<count.readU64().toNumber();i++){const p=imgOf(assemblies.add(i*8).readPointer());if(imgName(p).readCString().startsWith('Assembly-CSharp')){image=p;break;}}
const cls=n=>api('class_from_name','pointer',['pointer','pointer','pointer'])(image,Memory.allocUtf8String('MoonCleaners'),Memory.allocUtf8String(n));
const method=(c,n,argc)=>api('class_get_method_from_name','pointer',['pointer','pointer','int'])(c,Memory.allocUtf8String(n),argc);
const invoke=(m,obj,args=[])=>{const arr=Memory.alloc(Math.max(8,args.length*8));args.forEach((v,i)=>arr.add(i*8).writePointer(v));const exc=Memory.alloc(8);exc.writePointer(NULL);const r=api('runtime_invoke','pointer',['pointer','pointer','pointer','pointer'])(m,obj,arr,exc);if(!exc.readPointer().isNull())throw Error('Managed exception '+exc.readPointer());return r;};
const unbox=api('object_unbox','pointer',['pointer']);
const str=p=>p.isNull()?null:p.add(20).readUtf16String(p.add(16).readS32());
const arr=p=>p.isNull()?[]:Array.from({length:p.add(24).readU64().toNumber()},(_,i)=>p.add(32+i*8).readPointer());
const field=(c,n)=>api('class_get_field_from_name','pointer',['pointer','pointer'])(c,Memory.allocUtf8String(n));
const staticRef=(c,n)=>{const p=Memory.alloc(8);api('field_static_get_value','void',['pointer','pointer'])(field(c,n),p);return p.readPointer();};
const describe=p=>{
 const c=api('object_get_class','pointer',['pointer'])(p),it=Memory.alloc(8);it.writePointer(NULL);let f;const o={};
 while(!(f=api('class_get_fields','pointer',['pointer','pointer'])(c,it)).isNull()){
  const n=api('field_get_name','pointer',['pointer'])(f).readCString(),off=api('field_get_offset','int',['pointer'])(f),t=api('type_get_name','pointer',['pointer'])(api('field_get_type','pointer',['pointer'])(f)).readCString();
  try{o[n]={offset:off,type:t,value:t==='System.String'?str(p.add(off).readPointer()):t==='System.Int32'?p.add(off).readS32():t==='System.Single'?p.add(off).readFloat():p.add(off).readPointer().toString()};}catch(e){o[n]={type:t,error:String(e)};}
 }
 return o;
};
