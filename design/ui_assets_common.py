"""Shared helpers for the UI-decal pipeline: writing the generated Luau
module that Factory.luau reads asset ids from, and loading the manifest.
Used by both upload_ui_assets.py (automatic, Open Cloud) and
apply_asset_ids.py (manual, paste ids you uploaded yourself in Studio).
"""

import json
import pathlib

HERE = pathlib.Path(__file__).parent
ASSETS = HERE / "assets"
MANIFEST = ASSETS / "manifest.json"
IDS_FILE = ASSETS / "asset_ids.json"
LUAU_OUT = HERE.parent / "src" / "Shared" / "UIAssets.luau"


def load_manifest() -> list:
    if not MANIFEST.exists():
        raise SystemExit(f"{MANIFEST} not found -- run export_ui_assets.py first.")
    return json.loads(MANIFEST.read_text())


def load_ids() -> dict:
    if not IDS_FILE.exists():
        return {}
    return json.loads(IDS_FILE.read_text())


def save_ids(ids: dict) -> None:
    IDS_FILE.write_text(json.dumps(ids, indent=2, sort_keys=True) + "\n")


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
    LUAU_OUT.write_text("\n".join(lines))
    print(f"wrote {LUAU_OUT.relative_to(HERE.parent)} ({ready_count}/{len(manifest)} ids set)")
