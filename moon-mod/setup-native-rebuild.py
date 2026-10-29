"""Download a pinned official Godot editor and only its Android templates."""
from pathlib import Path
import json, urllib.request, zipfile, io, struct, zlib, hashlib, time

root = Path(__file__).resolve().parent.parent / 'MoonSweepers-Native-Rebuild'
tools = root / 'tools'; tools.mkdir(parents=True, exist_ok=True)
version = '4.7.2-stable'
release = json.load(urllib.request.urlopen(f'https://api.github.com/repos/godotengine/godot/releases/tags/{version}'))
assets = {a['name']: a for a in release['assets']}
records = []
editor_name = f'Godot_v{version}_win64.exe.zip'
editor_zip = tools / editor_name
if not editor_zip.exists():
    print('Downloading official Godot editor', flush=True)
    urllib.request.urlretrieve(assets[editor_name]['browser_download_url'], editor_zip)
with zipfile.ZipFile(editor_zip) as archive:
    archive.extractall(tools / 'godot')
records.append({'file': editor_name, 'sha256': hashlib.sha256(editor_zip.read_bytes()).hexdigest(), 'url': assets[editor_name]['browser_download_url']})

# HTTP ranges avoid downloading desktop/web templates that are not used.
asset = assets[f'Godot_v{version}_export_templates.tpz']
url = asset['browser_download_url']
size = asset['size']
def fetch(start, end):
    parts = []
    for chunk_start in range(start, end + 1, 4 * 1024 * 1024):
        chunk_end = min(end, chunk_start + 4 * 1024 * 1024 - 1)
        for attempt in range(4):
            try:
                req = urllib.request.Request(url + f'?range={chunk_start}-{chunk_end}', headers={'Range': f'bytes={chunk_start}-{chunk_end}'})
                with urllib.request.urlopen(req, timeout=60) as response:
                    if response.status != 206:
                        raise RuntimeError('Release host does not honor ranges')
                    part = response.read()
                    assert len(part) == chunk_end - chunk_start + 1
                    parts.append(part)
                    break
            except Exception:
                if attempt == 3: raise
                time.sleep(1)
    return b''.join(parts)
tail_start = max(0, size - 131072)
tail = fetch(tail_start, size - 1)
eocd = tail.rfind(b'PK\x05\x06')
assert eocd >= 0
_, _, _, _, total, cd_size, cd_offset, _ = struct.unpack_from('<4s4H2IH', tail, eocd)
central = fetch(cd_offset, cd_offset + cd_size - 1)
pos = 0
for _ in range(total):
    vals = struct.unpack_from('<4s6H3I5H2I', central, pos)
    assert vals[0] == b'PK\x01\x02'
    method, crc, compressed, uncompressed = vals[4], vals[7], vals[8], vals[9]
    name_len, extra_len, comment_len, offset = vals[10], vals[11], vals[12], vals[16]
    name = central[pos + 46:pos + 46 + name_len].decode()
    pos += 46 + name_len + extra_len + comment_len
    if name.split('/')[-1] != 'android_debug.apk':
        continue
    target = tools / 'templates' / name.split('/')[-1]
    target.parent.mkdir(exist_ok=True)
    if not target.exists() or target.stat().st_size != uncompressed:
        print(f'Downloading {name}: {compressed:,} compressed bytes', flush=True)
        head = fetch(offset, offset + 29)
        local = struct.unpack('<4s5H3I2H', head)
        data_start = offset + 30 + local[-2] + local[-1]
        data = fetch(data_start, data_start + compressed - 1)
        result = zlib.decompress(data, -15) if method == 8 else data
        assert len(result) == uncompressed and zlib.crc32(result) == crc
        target.write_bytes(result)
    records.append({'file': str(target.relative_to(root)), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'source_zip': url, 'zip_entry': name})
(tools / 'download-manifest.json').write_text(json.dumps({'version': version, 'records': records}, indent=2))
print('Editor and Android templates ready.', flush=True)
