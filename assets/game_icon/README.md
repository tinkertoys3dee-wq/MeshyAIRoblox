# Forge UGC — experience icon

The game's icon (the square thumbnail shown in search, home, and the game
page — distinct from the 16:9 promotional thumbnails). Roblox requires a
square image, recommends a 512×512 template for full-resolution display, and
notes that icons scale down to sizes like 150×150 elsewhere on the site/app,
so it needs to stay legible small.

- `png/forge_ugc_icon_512.png` — **upload this one.** 512×512, opaque RGB (no
  alpha), matches Roblox's recommended template exactly.
- `png/forge_ugc_icon_1024.png` — same art at 2x, kept as a high-res source
  in case it's ever useful for store pages or marketing elsewhere.
- `svg/forge_ugc_icon.svg` — editable vector source.

## Upload

Creator Hub → your experience → Basic Info → Icon → upload
`forge_ugc_icon_512.png`. It goes through Roblox moderation before it's
visible on the platform.

## Design

A hammer strikes an anvil and the impact erupts into a forge-burst — warm
sparks fused with violet/cyan magic ribbons — out of which a large faceted
gem is rising, standing in for any AI-generated wearable. It's meant to read
at a glance as "things get forged here" while the magic-energy half of the
burst signals the AI-generation angle, and it's deliberately no flatter than
it needs to be: layered gradients, screen-blended glows, a beveled metal rim
on the anvil/hammer, and drop shadows for depth, tuned specifically so the
silhouette and color contrast still read at 150px and smaller (Roblox's own
guidance point for icon legibility), not just at full size.

No wordmark/text — Roblox displays the experience's name as a separate
label next to the icon in essentially every placement, so baking text into
the icon itself would be redundant and (at 150px) illegible anyway.

To tweak: hand-edit `svg/forge_ugc_icon.svg` (plain, readable SVG — see
`build.py` in the icon's generation script if regenerating from scratch) and
re-export to PNG at 512×512, keeping it fully opaque (no transparency —
Roblox composites icons on their own tile background, not on the page).
