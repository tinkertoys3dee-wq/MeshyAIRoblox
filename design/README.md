# Forge UI decal pipeline

Turns the gold-filigree concept art into real Roblox decals, wired into the
live app with a safe fallback so nothing breaks before (or unless) you
upload anything.

## Two families of asset, 37 pieces total

**Shared chrome** (12 pieces): `Factory.Card`, `Factory.Button`, and
`Factory.Pill` (in `src/Client/UI/Factory.luau`) are each defined once and
reused across every one of the app's 8 screens. Retexturing those three
shared primitives, plus the topbar logo and the 6 sidebar nav icons, reskins
chrome everywhere at once — no per-page rewiring needed. Interactive pieces
(the actual TextButton/TextBox/ScrollingFrame instances) stay real Roblox
controls; these images only ever sit *behind* them.

**Individual illustrated items** (25 pieces): every hand-drawn glyph, hero
illustration and decorative ornament from the concept SVGs, exported
one-per-file exactly as drawn there — the 12 item icons (wings, crown,
katana, hat, butterfly, halo, horns, visor, backpack, avatar, picture,
wand), the Direct Forge hero crystal, the ember mascot tip sprite, the
price cartouche frame, the standalone corner ornament / flourish divider /
rivet stud / sparkle star, and the 6 gem studs. These are decorative art,
not shared chrome that Factory.luau reuses, so only the 5 that match real
Create-page content — the idea-chip prompts (Dragon Wings, Crystal Crown,
Neon Katana, Steampunk Hat, Fairy Wings) — are wired into App.luau so far.
The rest export and upload the same way, ready to drop into any page's
layout via `Factory.Icon` once there's a real spot for them; per-item card
art elsewhere in the app renders actual generated content and can't use a
fixed illustration.

See `assets/manifest.json` for the full list of names, files, and intended
use of every asset.

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

**Automatic, from Railway** (no Python available there, only Node): the same
one-command upload exists as a Node script at
`backend/scripts/ui-decals/upload.mjs` — same manifest and images, same API,
zero `npm install` needed. See that folder's README for how to run it from
Railway's Shell/Terminal tab and how to get the resulting ids back into this
repo.

## What ships even with zero ids

`src/Shared/UIAssets.luau` is checked in with every id at `0`. Factory's
image-backed helpers (`ImageCard`, `ImageButton`, `ImagePill`, `Icon`) treat
`0` as "not uploaded yet" and fall back to the exact original code-drawn
look — so the repo always builds and looks like it did before this pipeline
existed, and each asset can go live independently as it clears moderation.

## Extending the reskin further

Right now the shared topbar logo + sidebar nav (in `App:_BuildChrome`) and
the 5 Create-page idea chips (in `App:_RenderCreate`) call the image-backed
variants. To reskin a specific page's own cards or buttons too, swap that
call site from `Factory.Card(...)` / `Factory.Button(...)` to
`Factory.ImageCard(...)` / `Factory.ImageButton(...)` — same arguments, same
return type, zero behavior change until its asset id is set.
`Factory.ImagePill` works the same way for `Factory.Pill`.

To drop in one of the individual illustrated items (say, `CrystalHero` on
the Create page, or a `GemGold` stud next to a price), call
`Factory.Icon(parent, "CrystalHero", size, position)` the same way the nav
icons and idea chips do — it returns `nil` until that asset has a real id,
so gate any layout changes on that the same way `App.luau` already does.

## Files

| File | What it does |
|---|---|
| `export_ui_assets.py` | Renders `assets/*.png` + `assets/manifest.json` from the shared `<defs>`. |
| `upload_ui_assets.py` | Uploads via Open Cloud, writes `src/Shared/UIAssets.luau`. |
| `apply_asset_ids.py` | Same output, from ids you paste into `assets/asset_ids.json` by hand. |
| `ui_assets_common.py` | Shared manifest/Luau-writing helpers used by both upload paths. |
| `assets/manifest.json` | Name, file, 9-slice center, and intended use of each asset. |
| `assets/asset_ids.json` | Your working copy of `{name: assetId}` — gets created/updated by the scripts above. |
