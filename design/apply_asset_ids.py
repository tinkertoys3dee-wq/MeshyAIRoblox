#!/usr/bin/env python3
"""Manual path, if you'd rather upload the PNGs yourself (e.g. via Studio's
Asset Manager -> right-click -> Upload) instead of running
upload_ui_assets.py with an Open Cloud API key.

1. python3 export_ui_assets.py          # writes assets/*.png
2. Upload each PNG in assets/ to Roblox however you like, and note the
   resulting decal/image asset id for each.
3. Edit assets/asset_ids.json -- create it if it doesn't exist -- as a flat
   {"AssetName": 123456789, ...} object. Asset names match manifest.json's
   "name" field (PanelFrame, ButtonPrimary, ButtonDefault, ButtonDanger,
   PillFrame, Logo, NavCreate, NavStudio, NavDiscover, NavAvatarLab,
   NavAvatarArt, NavSettings). You don't need every one filled in at once --
   missing entries just stay 0 (code-drawn fallback) until you add them.
4. python3 apply_asset_ids.py            # writes src/Shared/UIAssets.luau

Re-run step 4 any time you add more ids to assets/asset_ids.json.
"""

from ui_assets_common import load_manifest, load_ids, write_luau_module, IDS_FILE


def main():
    manifest = load_manifest()
    ids = load_ids()
    if not IDS_FILE.exists():
        example = {item["name"]: 0 for item in manifest}
        import json
        IDS_FILE.write_text(json.dumps(example, indent=2, sort_keys=True) + "\n")
        print(f"Created {IDS_FILE} with every id set to 0 -- fill in the ones you've")
        print("uploaded, then run this script again.")
        return

    write_luau_module(ids)
    known = {item["name"] for item in manifest}
    unknown = set(ids) - known
    if unknown:
        print(f"Note: {IDS_FILE.name} has names not in the manifest (typo?): {', '.join(sorted(unknown))}")


if __name__ == "__main__":
    main()
