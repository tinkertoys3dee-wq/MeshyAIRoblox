"""Trace a measured artwork/icon crop from a newly generated mockup.

UI panels, buttons and typography should be reconstructed as native SVG. This
helper traces only a caller-selected artwork crop into editable vector paths;
it never embeds PNGs, reads old layouts, uploads or changes game files.
"""
from __future__ import annotations

import argparse
from io import BytesIO
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / ".deps"))
import vtracer

NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--crop", required=True, help="Measured x,y,width,height of artwork, excluding UI lettering")
    parser.add_argument("--name", required=True, help="Unique artwork group/asset ID")
    parser.add_argument("--exclude", action="append", default=[], help="Optional x,y,w,h in full-reference pixels to make transparent before tracing; repeat for label/control regions")
    parser.add_argument("--colors", type=int, default=7, choices=range(1, 9))
    parser.add_argument("--layer-difference", type=int, default=8)
    parser.add_argument("--speckle", type=int, default=2)
    parser.add_argument("--mode", default="spline", choices=["spline", "polygon", "none"])
    parser.add_argument("--length-threshold", type=float, default=2.0, help="Lower values retain fine illustrated detail")
    args = parser.parse_args()
    assert re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", args.name), "Use a unique SVG-compatible asset name"
    bounds = tuple(int(value) for value in args.crop.split(","))
    assert len(bounds) == 4, "Expected x,y,width,height"
    x, y, w, h = bounds
    image = Image.open(args.reference).convert("RGBA")
    assert x >= 0 and y >= 0 and w > 0 and h > 0 and x + w <= image.width and y + h <= image.height, "Crop is outside reference"
    crop = image.crop((x, y, x + w, y + h))
    masks = []
    for value in args.exclude:
        mask = tuple(int(part) for part in value.split(","))
        assert len(mask) == 4 and mask[2] > 0 and mask[3] > 0, "Expected exclusion x,y,width,height"
        mx, my, mw, mh = mask
        left, top, right, bottom = max(0, mx-x), max(0, my-y), min(w, mx+mw-x), min(h, my+mh-y)
        if right > left and bottom > top:
            ImageDraw.Draw(crop).rectangle((left, top, right-1, bottom-1), fill=(0, 0, 0, 0))
            masks.append(mask)
    buffer = BytesIO()
    crop.save(buffer, format="PNG")
    traced = vtracer.convert_raw_image_to_svg(buffer.getvalue(), img_format="png",
        colormode="color", hierarchical="stacked", mode=args.mode,
        filter_speckle=args.speckle, color_precision=args.colors,
        layer_difference=args.layer_difference, corner_threshold=60,
        length_threshold=args.length_threshold, max_iterations=10, splice_threshold=45, path_precision=4)
    root = ET.fromstring(traced)
    root.set("viewBox", f"0 0 {w} {h}")
    root.set("width", str(w))
    root.set("height", str(h))
    # Prefix any traced IDs before an artwork SVG is inserted into a screen.
    renamed = {node.get("id"): f"{args.name}_{node.get('id')}" for node in root.iter() if node.get("id")}
    for node in root.iter():
        for attr, value in list(node.attrib.items()):
            if attr == "id": value = renamed[value]
            for previous, current in renamed.items():
                value = value.replace(f"url(#{previous})", f"url(#{current})")
                if attr.endswith("href") and value == f"#{previous}": value = f"#{current}"
            node.set(attr, value)
    art = ET.Element(f"{{{NS}}}g", {"id": args.name, "data-component": "artwork",
        "data-asset": args.name, "data-bounds": f"0 0 {w} {h}", "data-source-bounds": " ".join(map(str, bounds))})
    for child in list(root):
        if child.tag.rsplit("}", 1)[-1] != "defs":
            root.remove(child)
            art.append(child)
    # VTracer can paint transparent excluded regions black. A real even-odd
    # clip removes their vector geometry, keeping the UI overlays separate.
    if masks:
        defs = ET.SubElement(root, f"{{{NS}}}defs")
        clip_id = f"{args.name}_excluded_regions"
        clip = ET.SubElement(defs, f"{{{NS}}}clipPath", {"id": clip_id, "clipPathUnits": "userSpaceOnUse"})
        contour = f"M0 0H{w}V{h}H0Z"
        for mx, my, mw, mh in masks:
            left, top, right, bottom = max(0, mx-x), max(0, my-y), min(w, mx+mw-x), min(h, my+mh-y)
            contour += f" M{left} {top}H{right}V{bottom}H{left}Z"
        ET.SubElement(clip, f"{{{NS}}}path", {"d": contour, "fill-rule": "evenodd", "clip-rule": "evenodd"})
        art.set("clip-path", f"url(#{clip_id})")
        art.set("data-excluded-source-bounds", json.dumps(masks, separators=(",", ":")))
    root.append(art)
    assert not any(node.tag.rsplit("}", 1)[-1] in {"image", "feImage", "text", "tspan", "textPath", "script", "foreignObject"} for node in root.iter())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(args.output, encoding="utf-8", xml_declaration=True)
    print(json.dumps({"output": str(args.output.resolve()), "reference": str(args.reference.resolve()),
        "sourceBounds": bounds, "excludedReferenceRects": masks,
        "paths": sum(node.tag == f"{{{NS}}}path" for node in root.iter()),
        "rasterEmbedding": False}, indent=2))


if __name__ == "__main__":
    main()
