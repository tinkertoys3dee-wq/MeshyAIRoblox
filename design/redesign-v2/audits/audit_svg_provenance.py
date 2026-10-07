"""Read-only SVG provenance inventory. Never accesses credentials or uploads."""
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent.parent
ROOT = HERE.parent.parent

def tag(el):
    return el.tag.rsplit('}', 1)[-1]

def main():
    manifest = json.loads((HERE / 'assets/manifest.json').read_text(encoding='utf-8'))
    registry = (ROOT / 'src/Shared/RedesignAssets.luau').read_text(encoding='utf-8')
    ids = dict((name, int(value)) for name, value in re.findall(r'\["([^"]+)"\]\s*=\s*(\d+)', registry))
    traces = {path.stem: path for path in (HERE / 'artwork').glob('*.svg')}
    inspected = []
    forbidden = []
    for directory in ['svg', 'artwork', 'assets/svg']:
        for path in sorted((HERE / directory).glob('*.svg')):
            root = ET.parse(path).getroot()
            problems = []
            for el in root.iter():
                if tag(el) in {'image', 'feImage', 'script', 'foreignObject'}:
                    problems.append(tag(el))
                for attr, value in el.attrib.items():
                    if attr.rsplit('}', 1)[-1] == 'href' and not value.startswith('#'):
                        problems.append('external-href')
                    if 'data:image' in value.lower():
                        problems.append('embedded-raster-data')
            record = {'path': path.relative_to(HERE).as_posix(), 'elements': sum(1 for _ in root.iter()),
                      'paths': sum(tag(el) == 'path' for el in root.iter()), 'problems': problems}
            inspected.append(record)
            if problems:
                forbidden.append(record)
    traced_runtime = []
    missing = []
    for asset in manifest:
        path = HERE / 'assets' / asset['svg']
        if not path.is_file() or asset['name'] not in ids:
            missing.append(asset['name'])
        if asset['sourceName'] in traces:
            art = ET.parse(traces[asset['sourceName']]).getroot()
            group = next(el for el in art.iter() if el.get('data-asset') == asset['sourceName'])
            traced_runtime.append({'name': asset['name'], 'sourceName': asset['sourceName'], 'screen': asset['screen'],
                                  'assetId': ids.get(asset['name']), 'svg': asset['svg'], 'png': asset['file'],
                                  'sourceBounds': group.get('data-source-bounds')})
    excluded = json.loads((HERE / 'assets/excluded-live-art.json').read_text(encoding='utf-8'))
    report = {
        'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
        'scope': 'Nine redesign-v2 design SVGs, artwork SVGs, exported runtime SVGs, manifest, and runtime registry.',
        'runtimeNames': len(manifest), 'registryNames': len(ids),
        'uniqueRuntimeIds': len(set(ids.values())),
        'svgFilesInspected': len(inspected), 'svgCountsByDirectory': dict(Counter('/'.join(x['path'].split('/')[:-1]) for x in inspected)),
        'rasterEmbeddingsOrExternalReferences': forbidden, 'missingSVGOrRegistryNames': missing,
        'homeAliases': [a['name'] for a in manifest if a.get('homeAsset')],
        'rasterRenderingPipeline': 'design/render_screen_assets.mjs uses sharp(svg).ensureAlpha().raw() then encodes those pixels as PNG. export_runtime_assets.py extracts SVG groups; it does not crop reference PNGs.',
        'aiOriginatedVectorTraces': len(traced_runtime),
        'aiOriginatedVectorTracesByScreen': dict(Counter(a['screen'] for a in traced_runtime)),
        'nativeOrReusedVectorRuntimeNames': len(manifest) - len(traced_runtime),
        'excludedLiveArtNames': len(excluded),
        'tracedRuntimeArtwork': traced_runtime,
        'interpretation': 'The runtime PNGs originate in genuine standalone vector SVGs, but traced decorative SVGs retain the look of their AI-generated reference artwork. Vectorizing an AI bitmap does not redesign it.',
        'recommendedVisualFix': 'Redraw the active traced decorations with a consistent native vector illustration system, then regenerate only changed PNGs and update their approved Roblox image IDs. Preserve live thumbnails, avatars, and user-generated content.',
    }
    output = HERE / 'audits/svg-provenance.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ['tracedRuntimeArtwork']}, indent=2))
    if forbidden or missing:
        raise SystemExit(1)

if __name__ == '__main__':
    main()
