# SVG Home screen

`forge-ugc.svg` is the supplied source. `HomeScreen.luau` replaces Home's
header, navigation, three main cards and five shortcuts. Other editor pages
keep their existing navigation. Desktop follows the source coordinates;
phones use native scrolling cards and touch sized actions.

Home controls pop on hover/focus, compress while pressed and rebound on
release. Main cards lift with colored glows; cards and shortcuts enter in
a staggered sequence when visiting Home. Profile refreshes do not replay
the entrance. Reduce Motion keeps controls stationary with static focus
and glow feedback. Effects support mouse, touch, keyboard and gamepad.

All 30 uploadable assets exclude SVG text, including the logo's lettering.
Headings, captions, balances and buttons remain live Roblox controls.
Inherited opacity, gradients, clips, transparency and shadows are preserved.

Run from the repository root using Python 3 and Node 22+:

```
python design/export_home_assets.py
node design/render_home_assets.mjs
node design/upload_home_assets.mjs --dry-run
node design/upload_home_assets.mjs
```

The uploader reads `backend/.env.roblox-upload`, which is ignored by Git:

```
ROBLOX_API_KEY=
ROBLOX_CREATOR_TYPE=Group
ROBLOX_CREATOR_ID=15575113
```

Give the Open Cloud key Assets read/write access for the correct creator.
It is sent only to Roblox's Assets API, never included in Roblox scripts,
generated assets, logs or the preview. Raw **Image** uploads eliminate the
old Decal wrapper resolution step. Only approved assets are applied.

Upload state persists after every accepted operation. Re-running resumes
processing and skips unchanged approved assets; changed PNGs are uploaded
as new Images. `--only CreateButton,MarketButton` selects named assets.
`--force` explicitly creates new uploads, including for unchanged files.

`asset_ids.json` and `src/Shared/HomeAssets.luau` contain the public image IDs.
The existing 40 shared UI assets are maintained separately. Sync the project
to Studio with Argon and publish the place to make it live for players.

Missions show the server's real daily quests. Daily rewards already credited
on join are displayed rather than claimed twice. UGC Codes opens catalog
item ID try-on and My Items; no promotional code-redemption service exists
in this game. Premium opens the existing Roblox Plus information flow.
