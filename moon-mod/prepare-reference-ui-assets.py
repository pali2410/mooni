"""Prepare source-grounded menu, physics settings and character skin data."""
from pathlib import Path
import sys, json, dataclasses
import numpy as np

root = Path(__file__).resolve().parent.parent
recovery = root / 'MoonSweepers-Android-Recovery'
project = root / 'MoonSweepers-Native-Rebuild'
sys.path.insert(0, str(recovery / 'Tools/python-deps'))
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler
from UnityPy.helpers.PackedBitVector import unpack_ints
assets = project / 'game/assets'
prefab_path = assets / 'prefabs.json'
prefabs = json.loads(prefab_path.read_text())
def exact_references(value):
    if isinstance(value, dict):
        return {k: str(v) if k == 'fileID' and isinstance(v, int) else exact_references(v) for k, v in value.items()}
    if isinstance(value, list): return [exact_references(v) for v in value]
    return value
# Godot's JSON parser stores numbers as doubles. Unity prefab file IDs exceed
# 2**53; storing them as strings prevents rounded references and flattened trees.
prefab_path.write_text(json.dumps(exact_references(prefabs), separators=(',', ':')))
configs = json.loads((project / 'analysis/serialized-configs.json').read_text())
(assets / 'world_settings.json').write_text(json.dumps(configs['MoonSettings.asset'], indent=2))
mesh_map = json.loads((assets / 'mesh_map.json').read_text())
key = 'Mesh/Astronaut _ Suit mesh.asset'
record = mesh_map[key]
source = recovery / 'Windows-Build-Reference/MoonSweepers_Data'
env = UnityPy.Environment(path=str(source))
asset = env.load_file(str(source / record['source']))
mesh = asset.objects[record['path_id']].parse_as_object()
handler = MeshHandler(mesh); handler.process()
weights = np.zeros((record['vertices'], 4), dtype=np.float32)
indices = np.zeros((record['vertices'], 4), dtype=np.int32)
# UnityPy 1.25.4's fourth compressed weight uses `1 - sum` where sum is
# still a 0..31 integer. Decode independently, retaining quantization units.
packed_weights = iter(unpack_ints(mesh.m_CompressedMesh.m_Weights))
packed_indices = iter(unpack_ints(mesh.m_CompressedMesh.m_BoneIndices))
for vertex in range(record['vertices']):
    total = 0
    for slot in range(3):
        weight = next(packed_weights)
        total += weight
        assert total <= 31
        weights[vertex, slot] = weight / 31.0
        indices[vertex, slot] = next(packed_indices)
        if total == 31: break
        if slot == 2:
            weights[vertex, 3] = (31 - total) / 31.0
            indices[vertex, 3] = next(packed_indices)
assert next(packed_weights, None) is None and next(packed_indices, None) is None
assert weights.shape == indices.shape == (record['vertices'], 4)
totals = weights.sum(axis=1)
print('Raw weight sum range:', float(totals.min()), float(totals.max()), 'zero vertices:', int((totals == 0).sum()))
assert np.isfinite(weights).all() and (weights >= 0).all()
zero = totals == 0
weights[zero, 0] = 1.0
totals[zero] = 1.0
weights /= totals[:, None]
binds = [[float(getattr(m, f'e{r}{c}')) for r in range(4) for c in range(4)] for m in mesh.m_BindPose]
(assets / 'character_skin.json').write_text(json.dumps({key: {'weights': weights.reshape(-1).tolist(),
    'bones': indices.reshape(-1).tolist(), 'binds': binds}}, separators=(',', ':')))
print('Original skin:', record['vertices'], 'vertices;', len(binds), 'bind matrices; weights normalized.')
