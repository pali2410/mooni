"""Generate a source-grounded asset/configuration inventory for reconstruction."""
from pathlib import Path
from collections import Counter
import sys, re, json

base = Path(__file__).resolve().parent.parent
recovery = base / 'MoonSweepers-Android-Recovery'
root = base / 'MoonSweepers-Native-Rebuild'
sys.path.insert(0, str(recovery / 'Tools/python-deps'))
import yaml
assets = recovery / 'Recovered-Unity-Project-Normalized/ExportedProject/Assets'
configs = {}
for path in (assets / 'MonoBehaviour').glob('*.asset'):
    text = path.read_text(encoding='utf-8-sig')
    text = re.sub(r'^%.*\n', '', text, flags=re.M)
    text = re.sub(r'^--- !u!\d+ &-?\d+', '---', text, flags=re.M)
    try:
        value = yaml.load(text, Loader=yaml.CSafeLoader)
        configs[path.name] = value.get('MonoBehaviour', value)
    except Exception as e: configs[path.name] = {'parse_error': str(e)}
(root / 'analysis/serialized-configs.json').write_text(json.dumps(configs, indent=2))
guid_map = json.loads((root / 'game/assets/guid_map.json').read_text())
catalog = configs['MoonUpgrades.asset']
tools = []
for offer in catalog['tools']:
    asset_path = guid_map[offer['tool']['guid']]
    definition = configs[Path(asset_path).name]
    tools.append({**definition, 'purchaseDollars': offer['purchaseDollars'],
                  'prefabPath': guid_map.get(definition['prefab']['guid'], '')})
(root / 'game/assets/tool_definitions.json').write_text(json.dumps(tools, indent=2))
(root / 'game/assets/upgrade_catalog.json').write_text(json.dumps(catalog, indent=2))
inventory = []
for path in assets.rglob('*'):
    if path.is_file(): inventory.append({'path': str(path.relative_to(assets)).replace('\\', '/'), 'bytes': path.stat().st_size})
(root / 'analysis/original-asset-files.json').write_text(json.dumps(inventory, indent=2))
types = json.loads((recovery / 'Recovered-Code-Information/runtime-types.json').read_text())
classes = [{'name': c['name'], 'namespace': c['namespace'], 'fields': c['fields'], 'methods': c['methods']} for c in types['classes']]
(root / 'analysis/reference-gameplay-api.json').write_text(json.dumps(classes, indent=2))
summary = {'asset_files': len(inventory), 'asset_bytes': sum(i['bytes'] for i in inventory),
           'extension_counts': dict(Counter(Path(i['path']).suffix for i in inventory)),
           'serialized_config_files': len(configs), 'runtime_types': len(classes),
           'reference_methods': sum(len(c['methods']) for c in classes),
           'tool_names': [t['displayName'] for t in tools], 'tool_prefabs': [t['prefabPath'] for t in tools]}
(root / 'analysis/reference-summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
