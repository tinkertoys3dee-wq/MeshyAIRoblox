# Forge UI decal uploader (Railway / Node)

`upload.mjs` is the Node twin of `design/upload_ui_assets.py` — same source
images (copied into `assets/` alongside this script), same manifest, same
Roblox Open Cloud API — for running from this Railway service's terminal,
where Python isn't installed but Node already is (this repo requires >=22,
which ships `fetch`/`FormData`/`Blob` for free — no `npm install` needed).

## Run it from Railway's Shell/Terminal tab for this service

```
export ROBLOX_API_KEY="..."          # create.roblox.com/dashboard/credentials, Assets:Create
export ROBLOX_CREATOR_TYPE="User"    # or "Group"
export ROBLOX_CREATOR_ID="..."
cd backend/scripts/ui-decals
node upload.mjs
```

Tip: if you set those 3 as Railway **service Variables** first (dashboard →
Variables), they're already in the environment when you open the terminal —
you never have to type the key itself into the shell.

It uploads all 37 decals one at a time, printing `ok  <Name> -> <id>` as
each clears Roblox's moderation queue. Safe to re-run — anything already
uploaded is skipped unless you pass `--force`.

## Required follow-up step — the ids it prints aren't usable yet

Roblox's Open Cloud Assets API hands back a Decal *wrapper* id, which
renders fine as a 3D `Decal.Texture` but **not** as an
`ImageLabel`/`ImageButton.Image` — which is what every one of these decals
actually needs. There's no HTTP API to get the real, GUI-usable id; it has
to be resolved by the Roblox engine itself. See `design/README.md`'s
"Required follow-up" section for the full explanation and
`design/tools/resolve_decal_ids.lua`, which you run once in Studio's
Command Bar to resolve every id at once. Newly-uploaded images can also
clear 3D-decal moderation well before the separate GUI-image moderation
pass catches up, so don't be surprised if ids need a while after upload
before that resolve script finds them ready.

## Getting the ids back out

Railway's container filesystem doesn't survive a redeploy, so don't rely on
the `ids.json` this writes still being there later. At the end the script
prints the full `{name: id}` map as one block:

```
=== Final ids (copy this block) ===
{
  "PanelFrame": 123456789,
  ...
}
=== end ===
```

Copy that block and send it back — paste it into chat, or hand over the
`ids.json` file's contents if you grabbed it before the shell closed. Either
way, it gets merged into `design/assets/asset_ids.json` and baked into
`src/Shared/UIAssets.luau` from there — same end state as the Python path.

## Why this exists as a separate copy

`design/` isn't part of what Railway builds/deploys for this Node service,
so the PNGs and manifest live here too (`assets/`, `manifest.json`) — a
straight copy of `design/assets/`. If you add or change a decal, re-run
`python3 export_ui_assets.py` in `design/` and copy the changed files here
too (or ask for that to be done for you).
