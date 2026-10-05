"""Audit the nine image-first SVG designs and record their native layer inventory.

This creates design metadata only. It does not flatten controls, extract runtime
assets, upload artwork, or read credentials. Re-run after editing any final SVG.
"""
from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image
from validate_vectors import validate

HERE = Path(__file__).resolve().parent
SCREENS = [
    ('create', 'Create UGC'),
    ('my-items', 'My Items'),
    ('market', 'Community Market'),
    ('avatar-lab', 'Avatar Lab'),
    ('avatar-graphics', 'Avatar Graphics'),
    ('games', 'Games'),
    ('arcade', 'Arcade'),
    ('runway', 'Forge Runway'),
    ('settings', 'Settings'),
]
CONTROL_COMPONENTS = {'button', 'input', 'field', 'toggle', 'slider', 'tab', 'dropdown'}
RASTER_TAGS = {'image', 'feImage'}


def numbers(value):
    if value is None:
        return None
    return [float(part) for part in value.split()]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ancestors(node, parents):
    result = [node]
    while node in parents:
        node = parents[node]
        result.append(node)
    return list(reversed(result))


def inherited(chain, attribute):
    return next((el.get(attribute) for el in reversed(chain) if el.get(attribute)), None)


def layer_inventory(root):
    parents = {child: parent for parent in root.iter() for child in parent}
    assets = []
    for el in root.iter():
        name = el.get('data-asset')
        if not name:
            continue
        chain = ancestors(el, parents)
        component = next((p for p in reversed(chain) if p.get('data-component')), None)
        assets.append({
            'name': name,
            'elementId': el.get('id'),
            'bounds': numbers(el.get('data-bounds')),
            'boundsAttribute': el.get('data-bounds'),
            'transform': el.get('transform'),
            'transformChain': [
                {'elementId': p.get('id'), 'transform': p.get('transform')}
                for p in chain if p.get('transform')
            ],
            'component': component.get('data-component') if component is not None else None,
            'componentId': component.get('id') if component is not None else None,
            'role': inherited(chain, 'data-role'),
            'roleAttribute': el.get('data-role'),
            'state': inherited(chain, 'data-state'),
            'sourceBounds': numbers(el.get('data-source-bounds')),
            'containsEditableText': any(p.tag.rsplit('}', 1)[-1] in {'text', 'tspan', 'textPath'} for p in el.iter()),
        })
    return assets


def write_json(name, data):
    target = HERE / name
    temporary = target.with_suffix(target.suffix + '.tmp')
    temporary.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    temporary.replace(target)


def main():
    gallery = HERE / 'index.html'
    gallery_source = gallery.read_text(encoding='utf-8')
    gallery_slugs = re.findall(r"\{\s*slug:\s*'([^']+)'", gallery_source)
    expected_slugs = [slug for slug, _ in SCREENS]
    assert gallery_slugs == expected_slugs, 'Gallery screen inventory differs from the nine final designs'
    manifest_screens, reports, gallery_assets = [], [], []
    for slug, title in SCREENS:
        mockup_rel = f'mockups/{slug}.png'
        svg_rel = f'svg/{slug}.svg'
        render_rel = f'svg/qa/{slug}/render.png'
        review_rel = f'svg/qa/{slug}/review.png'
        mockup, svg = HERE / mockup_rel, HERE / svg_rel
        assert mockup.is_file() and svg.is_file(), f'Missing gallery input for {slug}'
        svg_hash = digest(svg)
        report = validate(svg, require_ui_groups=True)
        root = ET.parse(svg).getroot()
        assert svg_hash == digest(svg), f'{slug} changed while inventory was reading it; rerun after editing finishes'
        with Image.open(mockup) as image:
            png_dimensions = [image.width, image.height]
        canvas = numbers(root.get('viewBox'))
        assert max(abs(a-b) for a,b in zip(png_dimensions, [1672, 941])) <= 1, f'{slug} PNG dimensions differ by more than one generated pixel: {png_dimensions}'
        assert canvas == [0, 0, 1672, 941], f'{slug} SVG canvas differs: {canvas}'
        components = Counter(el.get('data-component') for el in root.iter() if el.get('data-component'))
        assets = layer_inventory(root)
        native_controls = sum(components[kind] for kind in CONTROL_COMPONENTS)
        raster_count = sum(el.tag.rsplit('}', 1)[-1] in RASTER_TAGS for el in root.iter())
        manifest_screens.append({
            'slug': slug,
            'name': title,
            'mockupPath': mockup_rel,
            'svgPath': svg_rel,
            'renderPath': render_rel,
            'reviewPath': review_rel,
            'renderExists': (HERE / render_rel).is_file(),
            'reviewExists': (HERE / review_rel).is_file(),
            'canvasDimensions': [1672, 941],
            'mockupDimensions': png_dimensions,
            'mockupExactlyMatchesCanvas': png_dimensions == [1672, 941],
            'dimensionNote': None if png_dimensions == [1672, 941] else 'One-pixel image-generation framing variation is preserved as generated; review rendering fits the SVG to the actual reference dimensions.',
            'svgViewBox': canvas,
            'editableTextLabelCount': report['editableTextLabels'],
            'nativeButtonCount': components['button'],
            'semanticControlCount': native_controls,
            'componentCounts': dict(components),
            'namedAssetCount': len(assets),
            'rasterEmbeddingCount': raster_count,
            'sourceSha256': {'mockup': digest(mockup), 'svg': svg_hash},
            'assets': assets,
        })
        report['screen'] = slug
        report['relativeFile'] = svg_rel
        report['sourceSha256'] = svg_hash
        reports.append(report)
        gallery_assets += [{'path': mockup_rel, 'exists': True}, {'path': svg_rel, 'exists': True}]
    totals = {
        'screens': len(manifest_screens),
        'nativeButtons': sum(s['nativeButtonCount'] for s in manifest_screens),
        'semanticControls': sum(s['semanticControlCount'] for s in manifest_screens),
        'editableTextLabels': sum(s['editableTextLabelCount'] for s in manifest_screens),
        'namedAssets': sum(s['namedAssetCount'] for s in manifest_screens),
        'rasterEmbeddings': sum(s['rasterEmbeddingCount'] for s in manifest_screens),
        'galleryInputs': len(gallery_assets),
        'existingGalleryInputs': sum(a['exists'] for a in gallery_assets),
        'existingRenderPreviews': sum(s['renderExists'] for s in manifest_screens),
        'mockupsWithOnePixelCanvasVariation': sum(not s['mockupExactlyMatchesCanvas'] for s in manifest_screens),
    }
    manifest = {
        'schemaVersion': 1,
        'kind': 'design-layer-inventory',
        'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
        'method': 'Full generated images followed by native editable SVG reconstruction.',
        'notes': [
            'This is a design inventory, not a live Roblox asset registry.',
            'Sample avatars/items/counts/creators/prices are placeholders; ReplaceWith roles preserve runtime substitution intent.',
            'Bounds are retained as authored; transformChain is ordered from outer ancestors to the asset and preserves original SVG coordinates.',
            'Asset names are scoped to their screen SVG; shared chrome may repeat across screens.',
            'Control counts include native button/input/field/toggle/slider/tab/dropdown semantic groups; labels are native text nodes, including repeated brand shadow lettering.',
        ],
        'totals': totals,
        'gallery': {'path': 'index.html', 'slugs': gallery_slugs, 'assets': gallery_assets},
        'screens': manifest_screens,
    }
    assert totals['rasterEmbeddings'] == 0
    assert totals['galleryInputs'] == totals['existingGalleryInputs'] == 18
    write_json('manifest.json', manifest)
    write_json('validation-all.json', reports)
    print(json.dumps(totals, indent=2))


if __name__ == '__main__':
    main()
