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

**Then run the required follow-up step below** — the ids this writes aren't
usable in the actual UI yet.

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
repo. **This also needs the follow-up step below.**

## Required follow-up: resolving to the real, GUI-usable id

Whichever path you used above, the id you get back from Roblox's Open Cloud
Assets API is a Decal *wrapper* id (Roblox `AssetTypeId` 13) — it works fine
as a 3D `Decal.Texture`, but **not** as an `ImageLabel`/`ImageButton.Image`,
which is what every one of these decals actually needs. GUI images need the
raw texture id nested inside that wrapper, and there's no public HTTP API to
get it (a known, long-standing Roblox platform gap — see
[this DevForum thread](https://devforum.roblox.com/t/provide-a-stable-open-cloud-api-to-get-an-image-id-from-a-decal-id/3594046)
asking Roblox to add one). The only reliable way is to have the Roblox
engine itself load the asset and read the real id back out.

Also note: newly-uploaded images can pass Roblox's 3D-decal moderation
review well before they clear the *separate* review pass specifically for
GUI-displayed images — so a freshly-uploaded id can render fine as a 3D
decal while still failing to load in an `ImageLabel` for a while after.

Once ids show as cleared (Roblox's dashboard, or a `ContentProvider:PreloadAsync`
check returning `Success` rather than `Failure` — note that call is known to
be unreliable specifically when run from Studio's Command Bar, so prefer
checking from an actual running client/LocalScript if you want to rely on
it), resolve them:

1. Open this place in Studio, make sure it's synced to the latest
   `UIAssets.luau`.
2. Paste `design/tools/resolve_decal_ids.lua` into the Command Bar (Edit
   mode is fine) and run it. It reads the wrapper ids straight out of the
   currently-synced `UIAssets` module, resolves each one via
   `InsertService:LoadAsset`, and prints a ready-to-paste block of the real
   ids.
3. Paste that block's values into `assets/asset_ids.json`, then run
   `python3 apply_asset_ids.py` to bake the real ids into
   `src/Shared/UIAssets.luau`.

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
| `upload_ui_assets.py` | Uploads via Open Cloud, writes `src/Shared/UIAssets.luau` (with wrapper ids — see the follow-up step above). |
| `apply_asset_ids.py` | Same output, from ids you paste into `assets/asset_ids.json` by hand. |
| `ui_assets_common.py` | Shared manifest/Luau-writing helpers used by both upload paths. |
| `tools/resolve_decal_ids.lua` | Run in Studio's Command Bar to resolve wrapper ids to the real, GUI-usable ids. |
| `assets/manifest.json` | Name, file, 9-slice center, and intended use of each asset. |
| `assets/asset_ids.json` | Your working copy of `{name: assetId}` — gets created/updated by the scripts above. |
