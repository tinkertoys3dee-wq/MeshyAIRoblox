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
gem is rising. The `FORGE` / `UGC` wordmark carries the name, since a
storefront icon has to sell what the experience is before anyone reads the
label next to it.

Three elements do the work of pulling players in:

- **A blocky avatar wearing the forged top hat.** Players respond to seeing
  an avatar far more than to props alone, and putting the hat *on* a
  character rather than floating it next to one says "this is gear for
  you," not "here is an object."
- **A gold crown** floating opposite the avatar, so the item variety reads
  as a wardrobe rather than a single trinket.

The look is deliberately loud: a saturated magenta→violet radial with
sunburst rays behind the hero, screen-blended glows, and a chunky
gold-gradient wordmark with stacked keylines. All of it is tuned so the
silhouette, color contrast, and title still read at 150×150 and smaller —
Roblox's own guidance point for icon legibility — not just at full size.

### A note on the wordmark

The title is live `<text>` in the SVG set in **DejaVu Sans Bold**, faked up
to a heavier weight with stacked `paint-order="stroke"` keylines (a wide
dark outline, a warm inner outline, then the gradient fill). If you
re-render the SVG on a machine without DejaVu installed, the wordmark will
fall back to another face and the spacing will shift — the shipped PNGs
already have it baked in, so this only matters if you regenerate.

To tweak: hand-edit `svg/forge_ugc_icon.svg` (plain, readable SVG) and
re-export to PNG at 512×512, keeping it fully opaque (no transparency —
Roblox composites icons on their own tile background, not on the page).
