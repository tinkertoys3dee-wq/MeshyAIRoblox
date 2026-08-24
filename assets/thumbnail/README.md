# Experience thumbnail

`png/forge_ugc_thumbnail_1920x1080.png` — the 16:9 thumbnail for the
experience page carousel. Roblox wants thumbnails at 16:9 and recommends
1920×1080 so they stay sharp everywhere they're shown; `.png` is among the
accepted formats. Editable source is `svg/forge_ugc_thumbnail.svg`.

Upload it in Creator Hub → your experience → Basic Info → Thumbnails.
Nothing in `src/` reads this file, and no ID from it goes back into code.

## Relationship to the icon

The thumbnail is not a wide crop of `assets/game_icon`. It shares the object
art — same anvil, hammer, gem, avatars, wordmark treatment, same forge-ember
palette — so the two read as one product, but the composition is built for
16:9 from scratch.

The whole forge assembly is drawn in the icon's own coordinate space and then
placed with a single transform. That keeps every relationship tuned for the
icon (where the hammer face contacts, how high the gem sits above the burst,
where the shockwave sits on the anvil's top plane) exactly intact instead of
re-deriving them at a new size and drifting.

## What 16:9 changes

- **Two avatars instead of one.** A square icon has room for one character;
  a thumbnail can stage a scene. One wears the forged top hat, the other the
  forged wings, which says "gear, plural" better than any single prop.
- **The far avatar is mirrored, not re-lit.** The avatar's warm rim light is
  baked onto its right edge for a forge to the right. On the other side of
  the scene the forge is to its *left*, so the whole character is flipped —
  which fixes the lighting and stops the pair looking cloned. Different shirt
  colours finish that job.
- **Wordmark set side by side** rather than stacked. A 16:9 frame has width
  to spare and very little height left once the scene is staged.
- **Backgrounds keyed to user space.** An `objectBoundingBox` radial on a
  16:9 rect stretches into a wide ellipse, putting the falloff at a different
  distance sideways than vertically; the thumbnail's gradients use
  `userSpaceOnUse` with an explicit centre and radius so the falloff stays
  circular and the corners land on the dark stops.

## Two things worth not re-learning

- **Worn wings need a near-horizontal fan.** Rooted level with the face they
  fan up over the skull and read as a leafy crown; rooted at back height but
  still steep, they hide behind the torso and read as fluff. They only read
  as wings when the fan sweeps out past the body silhouette.
- **The hat's offset and scale are relative to the avatar's scale.** They were
  hardcoded for exactly one avatar size, which silently slid the hat off the
  head at every other size — the thumbnail draws avatars larger than the icon
  does and surfaced it immediately.

## Regenerating

Built by a Python script that composes SVG and rasterises through headless
Chromium (not checked into this repo, same as the icon). To tweak, hand-edit
the SVG and re-export at 1920×1080 with any SVG-to-PNG tool.
