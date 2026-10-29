"""Preserve all recovered assets; extract native-engine mesh data and scene references."""
from pathlib import Path
from collections import Counter, defaultdict
import sys, json, re, struct, hashlib, shutil
import numpy as np

workspace = Path(__file__).resolve().parent.parent
recovery = workspace / 'MoonSweepers-Android-Recovery'
sys.path.insert(0, str(recovery / 'Tools/python-deps'))
import UnityPy, yaml
from UnityPy.helpers.MeshHelper import MeshHandler
root = workspace / 'MoonSweepers-Native-Rebuild'
out = root / 'game/assets'; out.mkdir(parents=True, exist_ok=True)
exported = recovery / 'Recovered-Unity-Project-Normalized/ExportedProject/Assets'
data = recovery / 'Windows-Build-Reference/MoonSweepers_Data'
reports = root / 'analysis'; reports.mkdir(exist_ok=True)

def documents(path):
    text = path.read_text(encoding='utf-8-sig')
    result = {}
    for section in re.split(r'^--- !u!', text, flags=re.M)[1:]:
        header, body = section.split('\n', 1)
        kind, ident = re.match(r'(\d+) &(-?\d+)', header).groups()
        tree = yaml.load(body, Loader=yaml.CSafeLoader)
        result[ident] = {'kind': int(kind), 'data': next(iter(tree.values()))}
    return result

guid_map = {}
for meta in exported.rglob('*.meta'):
    match = re.search(r'^guid: ([a-f0-9]+)', meta.read_text(encoding='utf-8-sig'), re.M)
    if match: guid_map[match[1]] = str(meta.with_suffix('').relative_to(exported)).replace('\\', '/')
(reports / 'unity-guid-map.json').write_text(json.dumps(guid_map, indent=2))

prefabs = {}
for folder, suffix in [('GameObject', '*.prefab'), ('Resources', '*.prefab'), ('Scenes', '*.unity')]:
    for path in (exported / folder).rglob(suffix):
        prefabs[str(path.relative_to(exported)).replace('\\', '/')] = documents(path)
(out / 'prefabs.json').write_text(json.dumps(prefabs, separators=(',', ':')))
materials = {}
for path in (exported / 'Material').glob('*.mat'):
    tree = documents(path)
    materials[str(path.relative_to(exported)).replace('\\', '/')] = next(iter(tree.values()))['data']
(out / 'materials.json').write_text(json.dumps(materials, separators=(',', ':')))
(out / 'guid_map.json').write_text(json.dumps(guid_map, separators=(',', ':')))
for folder in ['Texture2D', 'AudioClip', 'Font']:
    shutil.copytree(exported / folder, out / folder, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('*.meta'))
for path in (exported / 'Resources').rglob('*'):
    if path.suffix.lower() in ('.png', '.ttf', '.ogg', '.wav'):
        target = out / 'Resources' / path.relative_to(exported / 'Resources')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
for path in exported.rglob('*.png'):
    target = out / path.relative_to(exported)
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)

mesh_dir = out / 'meshes'; mesh_dir.mkdir(exist_ok=True)
mesh_records = []
errors = []
counts = Counter()
animation_records = []
for filename in ['globalgamemanagers.assets', 'resources.assets', 'sharedassets0.assets', 'sharedassets1.assets', 'level0', 'level1']:
    print('Scanning', filename, flush=True)
    env = UnityPy.Environment(path=str(data))
    asset = env.load_file(str(data / filename))
    for obj in asset.objects.values():
        counts[obj.type.name] += 1
        if obj.type.name == 'AnimationClip':
            try:
                tree = obj.read_typetree()
                dest = reports / 'animation-data' / f'{filename}-{obj.path_id}.json'
                dest.parent.mkdir(exist_ok=True)
                dest.write_text(json.dumps(tree, default=lambda b: b.hex() if isinstance(b, bytes) else str(b)))
                animation_records.append({'name': tree.get('m_Name'), 'data': str(dest.relative_to(root))})
            except Exception as e: errors.append({'kind': 'AnimationClip', 'file': filename, 'id': obj.path_id, 'error': str(e)})
        if obj.type.name != 'Mesh': continue
        try:
            mesh = obj.parse_as_object()
            safe = re.sub(r'[^A-Za-z0-9_.-]', '_', mesh.m_Name)[:100]
            key = f'{filename}-{obj.path_id}-{safe}'
            target = mesh_dir / f'{key}.bin'
            handler = MeshHandler(mesh); handler.process()
            vertices = np.asarray(handler.m_Vertices, dtype='<f4')
            if not len(vertices): continue
            normals = np.asarray(handler.m_Normals, dtype='<f4') if handler.m_Normals else np.zeros_like(vertices)
            uv = np.asarray(handler.m_UV0, dtype='<f4')[:, :2] if handler.m_UV0 else np.zeros((len(vertices), 2), dtype='<f4')
            # Unity -> Godot reflection in Z. Preserve prefab positions with the same basis.
            vertices[:, 2] *= -1; normals[:, 2] *= -1
            triangles = [np.asarray(t, dtype='<u4').reshape(-1, 3) for t in handler.get_triangles()]
            if not target.exists():
                with target.open('wb') as f:
                    f.write(struct.pack('<4sII', b'MSW1', len(vertices), len(triangles)))
                    f.write(vertices.tobytes()); f.write(normals.tobytes()); f.write(uv.tobytes())
                    for indices in triangles:
                        # Godot clockwise winding plus reflected coordinates preserves Unity order.
                        f.write(struct.pack('<I', indices.size)); f.write(indices.tobytes())
            mesh_records.append({'name': mesh.m_Name, 'file': 'res://assets/meshes/' + target.name,
                                 'vertices': len(vertices), 'surface_indices': [int(t.size) for t in triangles],
                                 'source': filename, 'path_id': obj.path_id,
                                 'bounds_min': vertices.min(axis=0).tolist(), 'bounds_max': vertices.max(axis=0).tolist()})
        except Exception as e:
            errors.append({'kind': 'Mesh', 'file': filename, 'id': obj.path_id, 'error': str(e)})
    print('Meshes so far:', len(mesh_records), 'errors:', len(errors), flush=True)

by_name = defaultdict(list)
for record in mesh_records: by_name[record['name']].append(record)
mesh_map = {}; ambiguous = []
for path in (exported / 'Mesh').glob('*.asset'):
    # Read only the leading name/submesh metadata, not multi-megabyte compressed payload YAML.
    with path.open(encoding='utf-8-sig') as f: prefix = f.read(32768)
    name_match = re.search(r'^  m_Name: (.+)$', prefix, re.M)
    name = name_match[1].strip().strip('"') if name_match else path.stem
    candidates = by_name.get(name, [])
    index_counts = [int(n) for n in re.findall(r'^    indexCount: (\d+)$', prefix, re.M)]
    filtered = [m for m in candidates if m['surface_indices'] == index_counts]
    if filtered: candidates = filtered
    key = str(path.relative_to(exported)).replace('\\', '/')
    if candidates:
        mesh_map[key] = candidates[0]
        if len(candidates) > 1: ambiguous.append({'asset': key, 'candidate_count': len(candidates)})
    else: errors.append({'kind': 'MeshMapping', 'asset': key, 'name': name})
(out / 'mesh_map.json').write_text(json.dumps(mesh_map, separators=(',', ':')))
(reports / 'mesh-inventory.json').write_text(json.dumps(mesh_records, indent=2))
(reports / 'extraction-report.json').write_text(json.dumps({'source': str(data), 'object_counts': dict(counts),
    'extracted_meshes': len(mesh_records), 'mapped_mesh_assets': len(mesh_map), 'prefabs_and_scenes': len(prefabs),
    'animations': animation_records, 'mapping_ambiguities': ambiguous, 'errors': errors,
    'limitations': ['Animation curves preserved as data, not yet retargeted to Godot skeletons.',
                   'Material shader behavior requires reconstruction.', 'Duplicate mesh names may require stronger matching.']}, indent=2))
print('Extraction complete:', len(mesh_records), 'meshes,', len(errors), 'errors.', flush=True)
