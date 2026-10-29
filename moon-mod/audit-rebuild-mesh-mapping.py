"""Resolve duplicate mesh names against compressed payloads; classify source-empty mesh."""
from pathlib import Path
import sys, json, re, hashlib

base = Path(__file__).resolve().parent.parent
recovery = base / 'MoonSweepers-Android-Recovery'
root = base / 'MoonSweepers-Native-Rebuild'
sys.path.insert(0, str(recovery / 'Tools/python-deps'))
import UnityPy, yaml
report_path = root / 'analysis/extraction-report.json'
report = json.loads(report_path.read_text())
records = json.loads((root / 'analysis/mesh-inventory.json').read_text())
mapping_path = root / 'game/assets/mesh_map.json'
mapping = json.loads(mapping_path.read_text())
assets = recovery / 'Recovered-Unity-Project-Normalized/ExportedProject/Assets'
data = recovery / 'Windows-Build-Reference/MoonSweepers_Data'
environments = {}
def read_mesh(record):
    filename = record['source']
    if filename not in environments:
        env = UnityPy.Environment(path=str(data))
        environments[filename] = env.load_file(str(data / filename))
    return environments[filename].objects[record['path_id']].parse_as_object()

resolved = []; changed = 0
for item in report['mapping_ambiguities']:
    path = item['asset']
    text = (assets / path).read_text(encoding='utf-8-sig')
    text = re.sub(r'^%.*\n', '', text, flags=re.M)
    text = re.sub(r'^--- !u!\d+ &-?\d+', '---', text, flags=re.M)
    tree = yaml.load(text, Loader=yaml.CSafeLoader)['Mesh']
    compressed = bool(tree['m_MeshCompression'])
    vertex_data = bytes.fromhex((tree['m_CompressedMesh']['m_Vertices']['m_Data'] if compressed else tree['m_VertexData']['_typelessdata']) or '')
    index_data = bytes.fromhex((tree['m_CompressedMesh']['m_Triangles']['m_Data'] if compressed else tree['m_IndexBuffer']) or '')
    candidates = []
    for record in records:
        if record['name'] != tree['m_Name']: continue
        mesh = read_mesh(record)
        source_vertices = mesh.m_CompressedMesh.m_Vertices.m_Data if compressed else mesh.m_VertexData.m_DataSize
        source_indices = mesh.m_CompressedMesh.m_Triangles.m_Data if compressed else mesh.m_IndexBuffer
        if bytes(source_vertices) == vertex_data and bytes(source_indices) == index_data:
            candidates.append(record)
    assert candidates, path
    # Multiple matches are accepted only when the actual converted buffers match too.
    hashes = {hashlib.sha256((root / 'game' / c['file'].replace('res://', '')).read_bytes()).hexdigest() for c in candidates}
    assert len(hashes) == 1, ('Converted duplicate contents differ', path)
    selected = candidates[0]
    if mapping[path]['file'] != selected['file']: changed += 1
    mapping[path] = selected
    resolved.append({'asset': path, 'matching_source_objects': len(candidates), 'converted_geometry_sha256': next(iter(hashes)),
                     'basis': 'Exact compressed vertex/index payload match plus equal converted-buffer hashes for duplicate matches.'})

empty = read_mesh({'source': 'sharedassets0.assets', 'path_id': 163})
assert empty.m_Name == 'solar_tracker - Solar _ Brushed hardware'
assert all(m.indexCount == 0 and m.vertexCount == 0 for m in empty.m_SubMeshes)
report['empty_source_meshes'] = [{'source': 'sharedassets0.assets', 'path_id': 163, 'name': empty.m_Name,
                                  'basis': 'Source has zero indices and zero vertices; no renderable geometry exists to extract.'}]
report['resolved_duplicate_matches'] = resolved
report['mapping_ambiguities'] = []
report['errors'] = [e for e in report['errors'] if not
    (e.get('kind') == 'Mesh' and e.get('file') == 'sharedassets0.assets' and e.get('id') == 163) and not
    (e.get('kind') == 'MeshMapping' and e.get('name') == empty.m_Name)]
report['empty_mesh_asset_paths'] = ['Mesh/solar_tracker - Solar _ Brushed hardware.asset']
report['limitations'] = ['Animation curves preserved as data, not yet retargeted to Godot skeletons.',
                         'Material shader behavior requires reconstruction.', 'Runtime mesh buffers currently contain static geometry, not skin/bind-pose data.']
mapping_path.write_text(json.dumps(mapping, separators=(',', ':')))
report_path.write_text(json.dumps(report, indent=2))
print('Duplicate-name mappings resolved:', len(resolved), 'changed runtime references:', changed, 'remaining conversion errors:', len(report['errors']))
