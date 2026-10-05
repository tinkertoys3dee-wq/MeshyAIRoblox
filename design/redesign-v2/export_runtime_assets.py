"""Export the approved image-first SVGs as separate text-free runtime skins.

Live players/items/jobs remain runtime content. SVG ancestor transforms, styles,
clips and referenced definitions survive extraction. The local source rectangles
are converted to world canvas coordinates before cropping transparent PNGs.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = HERE / 'assets'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
spec = importlib.util.spec_from_file_location('existing_export', HERE.parent / 'export_screen_assets.py')
existing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(existing)

STATIC_REPLACEMENTS = {'ReplaceWithIdeaThumbnail', 'ReplaceWithCreationPreview', 'ReplaceWithGameIllustration', 'ReplaceWithCommunityItem'}
STYLE_ATTRS = {'transform', 'opacity', 'fill', 'stroke', 'stroke-width', 'color', 'style', 'filter', 'clip-path', 'mask', 'visibility'}
IDENTITY = (1., 0., 0., 1., 0., 0.)

def multiply(a, b):
    aa, ab, ac, ad, ae, af = a
    ba, bb, bc, bd, be, bf = b
    return (aa*ba+ac*bb, ab*ba+ad*bb, aa*bc+ac*bd, ab*bc+ad*bd, aa*be+ac*bf+ae, ab*be+ad*bf+af)

def transform_matrix(value):
    result = IDENTITY
    for name, raw in re.findall(r'([A-Za-z]+)\s*\(([^)]*)\)', value or ''):
        values = [float(part) for part in re.findall(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?', raw)]
        if name == 'translate':
            operation = (1, 0, 0, 1, values[0], values[1] if len(values)>1 else 0)
        elif name == 'scale':
            operation = (values[0], 0, 0, values[1] if len(values)>1 else values[0], 0, 0)
        elif name == 'matrix':
            assert len(values) == 6
            operation = tuple(values)
        elif name == 'rotate':
            angle = math.radians(values[0]); c, s = math.cos(angle), math.sin(angle)
            operation = (c, s, -s, c, 0, 0)
            if len(values) == 3:
                operation = multiply(multiply((1,0,0,1,values[1],values[2]), operation), (1,0,0,1,-values[1],-values[2]))
        else:
            raise AssertionError(f'Unsupported SVG transform: {name}')
        result = multiply(result, operation)
    return result

def world_rect(node, chain):
    explicit = node.get('data-source-bounds')
    if explicit:
        return [float(v) for v in explicit.split()]
    rect = [float(v) for v in node.get('data-bounds').split()]
    assert len(rect) == 4
    matrix = IDENTITY
    for ancestor in chain:
        matrix = multiply(matrix, transform_matrix(ancestor.get('transform')))
    a,b,c,d,e,f = matrix; x,y,w,h = rect
    corners = [(a*px+c*py+e,b*px+d*py+f) for px,py in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)]]
    xs,ys = zip(*corners)
    return [min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]

def excluded(role):
    return role.startswith('ReplaceWith') and role not in STATIC_REPLACEMENTS

def clean_asset(node):
    for parent in list(node.iter()):
        for child in list(parent):
            if (existing.local_name(child) in existing.TEXT_TAGS or excluded(child.get('data-role', ''))
                    or child.get('data-native') or child.get('data-asset')):
                parent.remove(child)
    for item in node.iter():
        for attr in list(item.attrib):
            if attr.startswith('data-') or attr in {'role', 'aria-labelledby', 'aria-label'}:
                del item.attrib[attr]

def key(slug, name):
    return 'V2_' + ''.join(part.title() for part in slug.split('-')) + '_' + name

def lua_number(value):
    return f'{value:.6f}'.rstrip('0').rstrip('.') or '0'

def main():
    (OUT / 'svg').mkdir(parents=True, exist_ok=True)
    (OUT / 'png').mkdir(exist_ok=True)
    manifests, metrics, excluded_names = [], {}, []
    for source in sorted((HERE / 'svg').glob('*.svg')):
        slug = source.stem
        root = ET.parse(source).getroot()
        source_defs = list(root.iter(f'{{{NS}}}defs'))
        assert source_defs
        defs = ET.Element(f'{{{NS}}}defs')
        for section in source_defs:
            for definition in section:
                defs.append(copy.deepcopy(definition))
        parents = {child: parent for parent in root.iter() for child in parent}
        metrics[slug] = {}
        for node in root.iter():
            name = node.get('data-asset')
            if not name:
                continue
            assert node.get('data-bounds'), f'Missing bounds for {slug}:{name}'
            chain = [node]
            while chain[0] in parents:
                chain.insert(0, parents[chain[0]])
            roles = [parent.get('data-role', '') for parent in chain]
            live = any(excluded(role) for role in roles)
            original = world_rect(node, chain)
            assert original[2] > 0 and original[3] > 0
            component = next((parent.get('data-component') for parent in reversed(chain) if parent.get('data-component')), None)
            pad = 0 if component == 'artwork' else 4
            rect = [original[0]-pad, original[1]-pad, original[2]+2*pad, original[3]+2*pad]
            asset_key = key(slug, name)
            metrics[slug][name] = {'assetKey': asset_key, 'rect': rect, 'sourceRect': original,
                'imported': not live, 'role': roles[-1] or next((role for role in reversed(roles) if role), None)}
            if live:
                excluded_names.append({'screen': slug, 'name': name, 'role': metrics[slug][name]['role']})
                continue
            x,y,w,h = rect
            scale = 2 if max(w,h) < 1000 else 1
            output = ET.Element(f'{{{NS}}}svg', {'width': str(math.ceil(w*scale)), 'height': str(math.ceil(h*scale)),
                'viewBox': ' '.join(lua_number(v) for v in rect)})
            output.append(copy.deepcopy(defs))
            part = copy.deepcopy(node)
            clean_asset(part)
            for ancestor in reversed(chain[:-1]):
                attrs = {attr: value for attr,value in ancestor.attrib.items() if attr in STYLE_ATTRS}
                if attrs:
                    wrapper = ET.Element(f'{{{NS}}}g', attrs); wrapper.append(part); part = wrapper
            output.append(part)
            # Definitions may include SVG metadata; no text becomes raster UI.
            for parent in list(output.iter()):
                for child in list(parent):
                    if existing.local_name(child) in existing.TEXT_TAGS:
                        parent.remove(child)
            existing.prune_defs(output)
            assert not any(existing.local_name(el) in {'text','tspan','textPath','image','feImage','script','foreignObject'} for el in output.iter())
            ET.ElementTree(output).write(OUT / 'svg' / f'{asset_key}.svg', encoding='utf-8', xml_declaration=True)
            asset = {'name': asset_key, 'sourceName': name, 'screen': slug,
                'file': f'png/{asset_key}.png', 'svg': f'svg/{asset_key}.svg',
                'rect': rect, 'sourceRect': original, 'scale': scale, 'width': math.ceil(w*scale), 'height': math.ceil(h*scale),
                'usage': 'EmptyCreationStateOnly' if name == 'CreateHeroV2' else 'StaticInterfaceArtwork'}
            if name.endswith('Backdrop') and original == [0, 0, 1672, 941]:
                # The approved Home city backdrop is identical vector artwork;
                # reuse its sharper 2x raw Image instead of publishing copies.
                asset['homeAsset'] = 'Backdrop'
            manifests.append(asset)
    assert len({item['name'] for item in manifests}) == len(manifests)
    (OUT / 'manifest.json').write_text(json.dumps(manifests, indent=2)+'\n', encoding='utf-8')
    (OUT / 'metrics.json').write_text(json.dumps(metrics, indent=2)+'\n', encoding='utf-8')
    (OUT / 'excluded-live-art.json').write_text(json.dumps(excluded_names, indent=2)+'\n', encoding='utf-8')
    if not (OUT / 'asset_ids.json').exists():
        (OUT / 'asset_ids.json').write_text('{}\n', encoding='utf-8')
    lines = ['--!strict', '', '-- GENERATED by design/redesign-v2/export_runtime_assets.py.',
        '-- rect is transparent image placement; sourceRect is the original group bounds.',
        '-- Coordinates use the approved 1672 x 941 SVG canvas.', 'local RedesignMetrics = {', '\tcanvasWidth = 1672,', '\tcanvasHeight = 941,', '\tscreens = {']
    for slug, entries in metrics.items():
        lines.append(f'\t\t["{slug}"] = {{')
        for name,item in entries.items():
            numbers = ', '.join(lua_number(v) for v in item['rect'])
            originals = ', '.join(lua_number(v) for v in item['sourceRect'])
            lines.append(f'\t\t\t["{name}"] = {{ assetKey = "{item["assetKey"]}", rect = {{ {numbers} }}, sourceRect = {{ {originals} }}, imported = {str(item["imported"]).lower()} }},')
        lines.append('\t\t},')
    lines += ['\t},', '}', '', 'return table.freeze(RedesignMetrics)', '']
    (ROOT / 'src/Shared/RedesignMetrics.luau').write_text('\n'.join(lines), encoding='utf-8')
    print(f'Exported {len(manifests)} separate runtime layers; excluded {len(excluded_names)} live thumbnails/previews. All nine screens have world-coordinate metrics.')

if __name__ == '__main__':
    main()
