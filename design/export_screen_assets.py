"""Export modern screen artwork as text-free, self-contained SVG components.

Run render_screen_assets.mjs next. Shared skins use the fixed 240-pixel
nine-slice contract used by the game; screen-specific art is exported at 2x.
This script never reads upload credentials or changes game scripts.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
SCREENS = HERE / "screens"
OUT = SCREENS / "assets"
NS = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"
ET.register_namespace("", NS)
ET.register_namespace("xlink", XLINK)
TEXT_TAGS = {"text", "tspan", "textPath", "title", "desc"}
HOME_ALIASES = [
    "Backdrop", "Dashboard", "LogoMark", "NavBar", "NavActive", "NavHome",
    "NavCreate", "NavMarket", "NavGames", "ResourcePill", "TokenIcon",
    "TicketIcon", "PlusButton", "SettingsButton", "Arrow", "QuickLink",
    "TutorialIcon", "MissionsIcon", "RewardsIcon", "CodesIcon", "PremiumIcon",
]


def local_name(node: ET.Element) -> str:
    return node.tag.rsplit("}", 1)[-1]


def element(parent, tag, **attrs):
    return ET.SubElement(parent, f"{{{NS}}}{tag}",
                         {k.replace("_", "-"): str(v) for k, v in attrs.items()})


def rect(parent, x, y, w, h, fill, radius, stroke, **attrs):
    return element(parent, "rect", x=x, y=y, width=w, height=h, rx=radius,
                   fill=fill, stroke=stroke, stroke_width=2, **attrs)


def strip_live_content(svg: ET.Element) -> None:
    """Remove letters and placeholder thumbnails, rather than hiding them."""
    for parent in list(svg.iter()):
        for child in list(parent):
            role = child.get("data-role", "")
            if (local_name(child) in TEXT_TAGS or role.startswith("ReplaceWith")
                    or child.get("data-native")):
                parent.remove(child)
    # IDs remain because gradients, clips, symbols and filters depend on them.
    for node in svg.iter():
        for attr in list(node.attrib):
            if attr.startswith("data-") or attr in {"role", "aria-labelledby"}:
                del node.attrib[attr]
    assert not any(local_name(node) in TEXT_TAGS for node in svg.iter())
    assert not any(local_name(node) in {"image", "feImage", "script", "foreignObject"} for node in svg.iter())
    for node in svg.iter():
        for attr, value in node.attrib.items():
            if attr in {"href", f"{{{XLINK}}}href"}:
                assert value.startswith("#"), "External SVG resources are not allowed"
            for url in re.findall(r"url\(([^)]+)\)", value):
                assert url.startswith("#"), "External SVG resources are not allowed"


def prune_defs(svg: ET.Element) -> None:
    """Retain only transitively referenced definitions, including nested defs."""
    defs = svg.find(f"{{{NS}}}defs")
    assert defs is not None
    direct = list(defs)
    owners = {}
    for definition in direct:
        for node in definition.iter():
            if node.get("id"):
                owners[node.get("id")] = definition

    def references(nodes):
        refs = set()
        for tree in nodes:
            for node in tree.iter():
                for attr, value in node.attrib.items():
                    refs.update(re.findall(r"url\(#([^)]+)\)", value))
                    if attr in {"href", f"{{{XLINK}}}href"} and value.startswith("#"):
                        refs.add(value[1:])
        return refs

    pending = references([node for node in svg if node is not defs])
    keep = set()
    while pending:
        ref = pending.pop()
        owner = owners.get(ref)
        if owner is not None and owner not in keep:
            keep.add(owner)
            pending.update(references([owner]))
    for definition in direct:
        if definition not in keep:
            defs.remove(definition)
    ids = [node.get("id") for node in svg.iter() if node.get("id")]
    assert len(ids) == len(set(ids)), "Duplicate IDs in an extracted component"
    unresolved = references([svg]) - set(ids)
    assert not unresolved, f"Unresolved SVG definitions: {sorted(unresolved)}"


def save_asset(name, bounds, parts, defs, specs, *, scale=2, screen="shared", slice_center=None):
    assert re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name), f"Invalid asset name: {name}"
    x, y, w, h = bounds
    assert w > 0 and h > 0
    svg = ET.Element(f"{{{NS}}}svg", {
        "width": str(round(w * scale)), "height": str(round(h * scale)),
        "viewBox": " ".join(map(str, bounds)),
    })
    svg.append(copy.deepcopy(defs))
    for part in parts:
        svg.append(copy.deepcopy(part))
    # These rows predate explicit placeholder roles. Their accessory icon is
    # the selected player's live item thumbnail, rather than permanent UI art.
    if name.startswith("ItemsCollectionRow"):
        for parent in list(svg.iter()):
            if parent is svg.find(f"{{{NS}}}defs"):
                continue
            for child in list(parent):
                if local_name(child) == "use" and parent.get("data-asset") == name:
                    parent.remove(child)
    strip_live_content(svg)
    prune_defs(svg)
    ET.indent(svg, space="  ")
    ET.ElementTree(svg).write(OUT / "svg" / f"{name}.svg", encoding="utf-8", xml_declaration=True)
    spec = {"name": name, "file": f"png/{name}.png", "svg": f"svg/{name}.svg",
            "rect": list(bounds), "scale": scale, "screen": screen,
            "width": round(w * scale), "height": round(h * scale)}
    if slice_center:
        spec["sliceCenter"] = list(slice_center)
    specs.append(spec)


def shared_assets(defs, specs):
    accents = {"Blue": "#00caff", "Purple": "#bf67ff", "Gold": "#ffd04e"}
    for theme, accent in accents.items():
        art = ET.Element(f"{{{NS}}}g")
        rect(art, 1, 1, 238, 238, f"url(#screen-{theme.lower()})", 26, accent)
        rect(art, 3, 3, 234, 234, "none", 24, "#ffffff", stroke_opacity=".08")
        rect(art, 9, 6, 222, 66, "url(#screen-sheen)", 20, "none")
        save_asset("Panel" + theme, (0, 0, 240, 240), [art], defs, specs,
                   scale=1, slice_center=(30, 30, 210, 210))
    for theme in ["Blue", "Purple", "Gold", "Quiet", "Danger"]:
        art = ET.Element(f"{{{NS}}}g")
        quiet = theme in {"Quiet", "Danger"}
        fill = {"Quiet": "#14223b", "Danger": "#312337"}.get(theme, f"url(#{theme.lower()}-button)")
        accent = {"Quiet": "#345278", "Danger": "#ae5d73"}.get(theme, accents.get(theme))
        rect(art, 1, 1, 238, 62, fill, 20, accent)
        if not quiet:
            rect(art, 8, 5, 224, 23.5, "url(#screen-sheen)", 12, "none")
            element(art, "path", d="M18 3H222", stroke="#ffffff", stroke_opacity=".45")
        save_asset("Button" + theme, (0, 0, 240, 64), [art], defs, specs,
                   scale=1, slice_center=(30, 30, 210, 34))
    art = ET.Element(f"{{{NS}}}g")
    rect(art, 1, 1, 238, 62, "#0d1b32", 17, "#00caff")
    rect(art, 7, 7, 226, 50, "none", 12, "#82eaff", stroke_opacity=".08")
    save_asset("SearchField", (0, 0, 240, 64), [art], defs, specs,
               scale=1, slice_center=(30, 30, 210, 34))
    art = ET.Element(f"{{{NS}}}g")
    rect(art, 1, 1, 238, 62, "url(#screen-blue)", 17, "#2d6282")
    rect(art, 7, 5, 226, 23, "url(#screen-sheen)", 12, "none")
    save_asset("SectionHeader", (0, 0, 240, 64), [art], defs, specs,
               scale=1, slice_center=(30, 30, 210, 34))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="Comma-separated screen stems; shared assets are always included")
    args = parser.parse_args()
    selected = set(args.only.split(",")) if args.only else None
    files = sorted(path for path in SCREENS.glob("*.svg") if selected is None or path.stem in selected)
    assert files, "No modern screen SVGs found"
    if selected:
        assert selected <= {path.stem for path in files}, "Unknown --only screen"
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    (OUT / "png").mkdir(exist_ok=True)
    specs = []
    first_defs = ET.parse(files[0]).getroot().find(f"{{{NS}}}defs")
    assert first_defs is not None
    shared_assets(first_defs, specs)
    for source in files:
        root = ET.parse(source).getroot()
        defs = root.find(f"{{{NS}}}defs")
        assert defs is not None
        for node in root.iter():
            name, bounds = node.get("data-asset"), node.get("data-bounds")
            if not name or node.get("data-role", "").startswith("ReplaceWith"):
                continue
            assert bounds, f"{source.name}: {name} needs data-bounds"
            parts = tuple(float(value) for value in bounds.split())
            assert len(parts) == 4, f"Invalid bounds: {name}"
            save_asset(name, parts, [node], defs, specs, screen=source.stem)
    names = [item["name"] for item in specs]
    assert len(names) == len(set(names)), "Asset names must be unique across screens"
    for name in HOME_ALIASES:
        assert name not in names
        specs.append({"name": name, "homeAsset": name, "screen": "home"})
    (OUT / "manifest.json").write_text(json.dumps(specs, indent=2) + "\n", encoding="utf-8")
    if not (OUT / "asset_ids.json").exists():
        (OUT / "asset_ids.json").write_text("{}\n", encoding="utf-8")
    print(f"Extracted {len(names)} text-free components from {len(files)} screens; reused {len(HOME_ALIASES)} Home assets.")


if __name__ == "__main__":
    main()
