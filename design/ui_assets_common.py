"""Shared helpers for the UI-decal pipeline: writing the generated Luau
module that Factory.luau reads asset ids from, and loading the manifest.
Used by both upload_ui_assets.py (automatic, Open Cloud) and
apply_asset_ids.py (manual, paste ids you uploaded yourself in Studio).
"""

import json
import pathlib
import hashlib
import re
import struct
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).parent
ASSETS = HERE / "assets"
MANIFEST = ASSETS / "manifest.json"
IDS_FILE = ASSETS / "asset_ids.json"
LUAU_OUT = HERE.parent / "src" / "Shared" / "UIAssets.luau"
SVG_NS = "http://www.w3.org/2000/svg"
VECTOR_TAGS = {
    "svg", "defs", "g", "symbol", "use", "path", "rect", "circle", "ellipse",
    "line", "polyline", "polygon", "linearGradient", "radialGradient", "stop",
    "clipPath", "mask", "pattern", "filter", "feBlend", "feColorMatrix",
    "feComponentTransfer", "feComposite", "feConvolveMatrix", "feDiffuseLighting",
    "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood", "feFuncA",
    "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feMerge", "feMergeNode",
    "feMorphology", "feOffset", "fePointLight", "feSpecularLighting", "feSpotLight",
    "feTile", "feTurbulence", "title", "desc", "metadata", "style", "text",
    "tspan", "textPath",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validate_vector_svg(source: bytes | str, label: str = "SVG") -> tuple[int, int]:
    """Accept self-contained vector art, never a bitmap wrapped in an SVG."""
    raw = source.encode("utf-8") if isinstance(source, str) else source
    if re.search(rb"<!\s*(?:DOCTYPE|ENTITY)\b", raw, re.IGNORECASE):
        raise ValueError(f"{label}: XML document types/entities are not allowed")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as error:
        raise ValueError(f"{label}: invalid SVG XML") from error
    if root.tag != f"{{{SVG_NS}}}svg":
        raise ValueError(f"{label}: expected an SVG root in the SVG namespace")
    references = set()
    ids = set()

    def check_resources(value: str) -> None:
        if re.search(r"@import\b", value, re.IGNORECASE):
            raise ValueError(f"{label}: imported resources are not allowed")
        for match in re.finditer(r"url\s*\(\s*([^)]*)\)", value, re.IGNORECASE):
            target = match.group(1).strip().strip("\"'")
            if not re.fullmatch(r"#[A-Za-z_][\w:.-]*", target):
                raise ValueError(f"{label}: external SVG resources are not allowed")
            references.add(target[1:])

    for node in root.iter():
        tag = node.tag.rsplit("}", 1)[-1]
        if node.tag != f"{{{SVG_NS}}}{tag}" or tag not in VECTOR_TAGS:
            raise ValueError(f"{label}: non-vector or active SVG element <{tag}> is not allowed")
        if node.get("id"):
            ids.add(node.get("id"))
        for attr, value in node.attrib.items():
            attr_name = attr.rsplit("}", 1)[-1]
            if attr_name.lower().startswith("on"):
                raise ValueError(f"{label}: SVG event handlers are not allowed")
            if attr_name == "href":
                if not re.fullmatch(r"#[A-Za-z_][\w:.-]*", value):
                    raise ValueError(f"{label}: external SVG references are not allowed")
                references.add(value[1:])
            check_resources(value)
        if tag == "style":
            check_resources(node.text or "")
    if references - ids:
        raise ValueError(f"{label}: unresolved SVG definitions: {sorted(references - ids)}")

    def dimension(name: str) -> int:
        value = root.get(name, "")
        if not re.fullmatch(r"(?:\d+(?:\.\d*)?|\.\d+)(?:px)?", value):
            raise ValueError(f"{label}: {name} must be an absolute positive pixel size")
        pixels = float(value.removesuffix("px"))
        if pixels <= 0 or not pixels.is_integer():
            raise ValueError(f"{label}: {name} must be a positive whole pixel size")
        return int(pixels)

    return dimension("width"), dimension("height")


def png_dimensions(data: bytes, label: str = "PNG") -> tuple[int, int]:
    if (len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n"
            or data[12:16] != b"IHDR" or struct.unpack(">I", data[8:12])[0] != 13):
        raise ValueError(f"{label}: expected a PNG with an IHDR header")
    width, height = struct.unpack(">II", data[16:24])
    if width <= 0 or height <= 0:
        raise ValueError(f"{label}: invalid PNG dimensions")
    return width, height


def svg_origin(svg_path: pathlib.Path, png_path: pathlib.Path) -> dict:
    """Stamp outputs only after the exporter actually renders their SVG."""
    source, png = svg_path.read_bytes(), png_path.read_bytes()
    width, height = validate_vector_svg(source, str(svg_path))
    if png_dimensions(png, str(png_path)) != (width, height):
        raise ValueError(f"{png_path}: PNG dimensions do not match its SVG source")
    return {"kind": "pure-svg", "source": svg_path.name,
            "sourceSha256": sha256(source), "pngSha256": sha256(png),
            "renderer": "chromium-svg", "width": width, "height": height}


def validate_manifest_asset(item: dict, directory: pathlib.Path | None = None) -> None:
    """Prevent upload of raster-only, embedded-raster, or modified outputs.

    The initial 40 exports predate origin stamps. Their vector sources and
    dimensions remain mandatory; newly stamped exports also bind both files
    by hash. Rendering-engine differences are not treated as pixel failures.
    """
    name, filename = item.get("name"), item.get("file")
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name):
        raise ValueError("UI manifest entry has an invalid name")
    if not isinstance(filename, str) or pathlib.Path(filename).suffix.lower() != ".png":
        raise ValueError(f"{name}: a PNG file is required")
    root = (directory or ASSETS).resolve()

    def asset_path(value: str) -> pathlib.Path:
        result = (root / value).resolve()
        if not result.is_relative_to(root):
            raise ValueError(f"{name}: asset path must remain inside its asset directory")
        if not result.is_file():
            raise ValueError(f"{name}: missing required source/output {value}")
        return result

    png_path = asset_path(filename)
    svg_filename = str(pathlib.Path(filename).with_suffix(".svg"))
    source_path = asset_path(svg_filename)
    source, png = source_path.read_bytes(), png_path.read_bytes()
    dimensions = validate_vector_svg(source, f"{name}.svg")
    if png_dimensions(png, filename) != dimensions:
        raise ValueError(f"{name}: PNG dimensions do not match its SVG source")
    origin = item.get("origin")
    if origin is not None:
        if not isinstance(origin, dict) or origin.get("kind") != "pure-svg" or origin.get("renderer") != "chromium-svg":
            raise ValueError(f"{name}: invalid SVG origin stamp")
        if origin.get("source") != source_path.name:
            raise ValueError(f"{name}: origin source does not match its SVG")
        if (origin.get("width"), origin.get("height")) != dimensions:
            raise ValueError(f"{name}: stale SVG origin dimensions")
        if origin.get("sourceSha256") != sha256(source) or origin.get("pngSha256") != sha256(png):
            raise ValueError(f"{name}: SVG/PNG files changed after rendering; export again")


def load_manifest() -> list:
    if not MANIFEST.exists():
        raise SystemExit(f"{MANIFEST} not found -- run export_ui_assets.py first.")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if not isinstance(manifest, list):
        raise ValueError("UI manifest must be an array")
    names = set()
    for item in manifest:
        if not isinstance(item, dict):
            raise ValueError("UI manifest entries must be objects")
        validate_manifest_asset(item)
        if item["name"] in names:
            raise ValueError(f"Duplicate UI asset name: {item['name']}")
        names.add(item["name"])
    return manifest


def load_ids() -> dict:
    if not IDS_FILE.exists():
        return {}
    return json.loads(IDS_FILE.read_text(encoding="utf-8"))


def save_ids(ids: dict) -> None:
    IDS_FILE.write_text(json.dumps(ids, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_luau_module(ids: dict) -> None:
    """(Re)generate src/Shared/UIAssets.luau from assets/manifest.json +
    whatever ids are currently known. Every entry defaults to 0 -- Factory's
    image helpers treat 0 as "not uploaded yet" and fall back to the
    existing code-drawn look, so this is always safe to commit and ship
    even mid-rollout."""
    manifest = load_manifest()
    lines = [
        "--!strict",
        "",
        "-- GENERATED FILE -- do not hand-edit.",
        "-- Regenerate with design/upload_ui_assets.py (automatic, Open Cloud) or",
        "-- design/apply_asset_ids.py (paste ids you uploaded yourself in Studio).",
        "--",
        "-- Every id defaults to 0, meaning \"not uploaded yet\": Factory.luau's",
        "-- image-backed helpers (ImageCard/ImageButton/ImagePill/Icon) check for",
        "-- that and fall back to the original code-drawn fill, so this file is",
        "-- always safe to ship as-is, before or mid-rollout of any single asset.",
        "local UIAssets = {",
    ]
    ready_count = 0
    for item in manifest:
        asset_id = int(ids.get(item["name"], 0) or 0)
        if asset_id:
            ready_count += 1
        lines.append(f"\t{item['name']} = {asset_id},")
    lines.append("}")
    lines.append("")
    lines.append(f"-- {ready_count}/{len(manifest)} assets have a real id right now.")
    lines.append("UIAssets.Ready = " + ("true" if ready_count == len(manifest) else "false"))
    lines.append("")
    lines.append("return UIAssets")
    lines.append("")
    LUAU_OUT.parent.mkdir(parents=True, exist_ok=True)
    LUAU_OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {LUAU_OUT.relative_to(HERE.parent)} ({ready_count}/{len(manifest)} ids set)")
