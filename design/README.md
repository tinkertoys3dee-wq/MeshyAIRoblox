# Forge UI decal pipeline

Turns the gold-filigree concept art into real Roblox decals, wired into the
live app with a safe fallback so nothing breaks before (or unless) you
upload anything.

## Why only these 12 pieces, not a screenshot per page

`Factory.Card`, `Factory.Button`, and `Factory.Pill` (in
`src/Client/UI/Factory.luau`) are each defined once and reused across every
one of the app's 8 screens. Retexturing those three shared primitives, plus
the topbar logo and the 6 sidebar nav icons, reskins chrome everywhere at
once — no per-page rewiring needed. Interactive pieces (the actual
TextButton/TextBox/ScrollingFrame instances) stay real Roblox controls;
these images only ever sit *behind* them.

## One-time setup

```
python3 export_ui_assets.py
```

Regenerates every PNG in `assets/` (plus `assets/manifest.json`) from the
same `<defs>` (gradients/filters/ornaments) as `forge-create-screen.svg`, so
the decals always match the approved concept art. Re-run this any time you
tweak a shape in `export_ui_assets.py`.

## Getting real asset ids — pick one

**Automatic** (needs a Roblox Open Cloud API key):

```
export ROBLOX_API_KEY="..."          # create.roblox.com/dashboard/credentials, Assets:Create
export ROBLOX_CREATOR_TYPE="User"    # or "Group"
export ROBLOX_CREATOR_ID="..."
python3 upload_ui_assets.py
```

Uploads everything in one command, polls Roblox's moderation queue per
asset, and bakes the results straight into `src/Shared/UIAssets.luau`. Safe
to re-run — already-uploaded assets are skipped unless you pass `--force`.

**Manual** (upload yourself via Studio's Asset Manager):

```
python3 apply_asset_ids.py      # first run just creates assets/asset_ids.json
# ...upload each PNG in assets/ however you like, fill in the ids it printed...
python3 apply_asset_ids.py      # bakes them into src/Shared/UIAssets.luau
```

## What ships even with zero ids

`src/Shared/UIAssets.luau` is checked in with every id at `0`. Factory's
image-backed helpers (`ImageCard`, `ImageButton`, `ImagePill`, `Icon`) treat
`0` as "not uploaded yet" and fall back to the exact original code-drawn
look — so the repo always builds and looks like it did before this pipeline
existed, and each asset can go live independently as it clears moderation.

## Extending the reskin further

Right now only the shared topbar logo + sidebar nav (in `App:_BuildChrome`)
call the image-backed variants. To reskin a specific page's own cards or
buttons too, swap that call site from `Factory.Card(...)` /
`Factory.Button(...)` to `Factory.ImageCard(...)` / `Factory.ImageButton(...)`
— same arguments, same return type, zero behavior change until its asset id
is set. `Factory.ImagePill` works the same way for `Factory.Pill`.

## Files

| File | What it does |
|---|---|
| `export_ui_assets.py` | Renders `assets/*.png` + `assets/manifest.json` from the shared `<defs>`. |
| `upload_ui_assets.py` | Uploads via Open Cloud, writes `src/Shared/UIAssets.luau`. |
| `apply_asset_ids.py` | Same output, from ids you paste into `assets/asset_ids.json` by hand. |
| `ui_assets_common.py` | Shared manifest/Luau-writing helpers used by both upload paths. |
| `assets/manifest.json` | Name, file, 9-slice center, and intended use of each asset. |
| `assets/asset_ids.json` | Your working copy of `{name: assetId}` — gets created/updated by the scripts above. |
