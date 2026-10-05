"""Verify that a reconstructed mockup is editable, self-contained SVG.

This reads new conversion files only. It never traces an old design, uploads
artwork, reads credentials, or changes game files.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

NS = "http://www.w3.org/2000/svg"
LINK = "http://www.w3.org/1999/xlink"
FORBIDDEN = {"image", "feImage", "script", "foreignObject"}


def validate(path: Path, *, require_ui_groups=False) -> dict:
    source = path.read_text(encoding="utf-8")
    assert "<!DOCTYPE" not in source.upper(), "External document definitions are not allowed"
    root = ET.fromstring(source)
    assert root.tag == f"{{{NS}}}svg", "Expected SVG namespace/root"
    nodes = list(root.iter())
    ids = [node.get("id") for node in nodes if node.get("id")]
    assert len(ids) == len(set(ids)), "Duplicate IDs"
    refs = set()
    for node in nodes:
        tag = node.tag.rsplit("}", 1)[-1]
        assert tag not in FORBIDDEN, f"Raster embedding or executable content: {tag}"
        for attr, value in node.attrib.items():
            assert not attr.lower().startswith("on"), "Event handler attributes are not allowed"
            for raw in re.findall(r"url\(([^)]+)\)", value):
                ref = raw.strip(" \t\r\n\"'")
                assert ref.startswith("#"), f"External resource: {ref}"
                refs.add(ref[1:])
            if attr in {"href", f"{{{LINK}}}href"}:
                assert value.startswith("#"), f"External reference: {value}"
                refs.add(value[1:])
        if tag == "style" and node.text:
            assert "@import" not in node.text.lower(), "External CSS imports are not allowed"
            for raw in re.findall(r"url\(([^)]+)\)", node.text):
                ref = raw.strip(" \t\r\n\"'")
                assert ref.startswith("#"), f"External CSS resource: {ref}"
                refs.add(ref[1:])
    assert refs <= set(ids), f"Missing definitions: {sorted(refs - set(ids))}"
    viewbox = [float(value) for value in root.get("viewBox", "").split()]
    assert len(viewbox) == 4 and viewbox[2] > 0 and viewbox[3] > 0, "Invalid viewBox"
    assets = [node for node in nodes if node.get("data-asset")]
    for node in assets:
        bounds = [float(value) for value in node.get("data-bounds", "").split()]
        assert len(bounds) == 4 and bounds[2] > 0 and bounds[3] > 0, f"Missing bounds for {node.get('data-asset')}"
        assert not any(child.tag.rsplit("}", 1)[-1] in {"text", "tspan", "textPath"}
                       for child in node.iter()), f"Artwork group contains text: {node.get('data-asset')}"
    text_nodes = [node for node in nodes if node.tag == f"{{{NS}}}text"]
    components = {}
    for node in nodes:
        kind = node.get("data-component")
        if kind:
            components[kind] = components.get(kind, 0) + 1
    if require_ui_groups:
        assert text_nodes, "A UI conversion must retain editable text labels"
        assert components.get("button"), "Buttons need separate semantic groups"
        assert components.get("panel"), "Panels need separate semantic groups"
        assert components.get("icon"), "Icons need separate semantic groups"
    return {"file": str(path.resolve()), "viewBox": viewbox, "elements": len(nodes),
            "editableTextLabels": len(text_nodes), "artworkGroups": len(assets),
            "components": components,
            "rasterEmbedding": False, "externalResources": False,
            "labels": ["".join(node.itertext()) for node in text_nodes]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-ui-groups", action="store_true")
    parser.add_argument("svg", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([validate(path, require_ui_groups=args.require_ui_groups) for path in args.svg], indent=2))


if __name__ == "__main__":
    main()
