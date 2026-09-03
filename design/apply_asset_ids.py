#!/usr/bin/env python3
"""Manual path, if you'd rather upload the PNGs yourself (e.g. via Studio's
Asset Manager -> right-click -> Upload) instead of running
upload_ui_assets.py with an Open Cloud API key. This is also the second
half of the *automatic* path: upload_ui_assets.py / upload.mjs hand back a
Decal wrapper id that isn't directly usable in an ImageLabel/ImageButton --
you resolve those to the real ids via tools/resolve_decal_ids.lua in Studio,
then feed the result through this script. See design/README.md's "Required
follow-up" section for why.

1. python3 export_ui_assets.py          # writes assets/*.png
2. Upload each PNG in assets/ to Roblox however you like, and note the
   resulting decal/image asset id for each. If you uploaded via Open Cloud,
   resolve each id to its real, GUI-usable form with
   tools/resolve_decal_ids.lua first (a raw Open Cloud id will look correct
   everywhere except actually rendering in the app).
3. Edit assets/asset_ids.json -- create it if it doesn't exist -- as a flat
   {"AssetName": 123456789, ...} object. Asset names match manifest.json's
   "name" field -- see that file for the full list (shared chrome like
   PanelFrame/ButtonPrimary/NavCreate, plus every individual item glyph,
   CrystalHero, EmberMascot, PriceCartouche, and the standalone ornament/gem
   pieces). You don't need every one filled in at once -- missing entries
   just stay 0 (code-drawn fallback, or simply "not used yet" for the
   decorative-only pieces) until you add them.
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
