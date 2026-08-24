# Experience thumbnail

`png/forge_ugc_thumbnail_1920x1080.png` — the 16:9 thumbnail for the
experience page carousel. Roblox wants thumbnails at 16:9 and recommends
1920×1080 so they stay sharp everywhere they're shown; `.png` is among the
accepted formats. Editable source is `svg/forge_ugc_thumbnail.svg`.

Upload it in Creator Hub → your experience → Basic Info → Thumbnails.
Nothing in `src/` reads this file, and no ID from it goes back into code.

## The design tells a story, left to right

Three beats: a plain, grey, unadorned avatar goes in on the left; the forge
is the engine in the middle; the **same** avatar comes out on the right
transformed — bigger, gold-lit, crowned, winged, arms up.

That is the experience's actual promise in one glance: *you come in plain,
you leave with gear nobody else has.* A row of characters posed either side
of a prop is a logo card, not a story — it shows what is in the game without
saying what happens to you in it.

Every channel pushes the same direction instead of repeating one:

| | left | right |
|---|---|---|
| colour | cold violet | hot gold |
| scale | small | large |
| posture | arms down, flat mouth | arms raised, open grin |
| light | cool blue rim | warm forge rim |
| density | dead air | embers, sparks, wings |

Both characters stand on the **same ground line**, so the size difference
reads as "levelled up" rather than as perspective. Light streams out of the
forge toward the transformed side — without a direction, two characters are
just two characters rather than a before and an after.

## Relationship to the icon

The thumbnail shares the object art with `assets/game_icon` — same anvil,
hammer, gem, wordmark treatment, same forge-ember palette — so the two read
as one product.

The whole forge assembly is drawn in the icon's own coordinate space and then
placed with a single transform. That keeps every relationship tuned for the
icon (where the hammer face contacts, how high the gem sits above the burst,
where the shockwave sits on the anvil's top plane) exactly intact instead of
re-deriving them at a new size and drifting.

## Things worth not re-learning

- **A transformation needs posture, not just palette.** Recolouring the same
  pose reads as a palette swap. The arms and mouth carry at least half of it.
- **Raised arms want ~146° from vertical.** Around 132° reads as a shrug;
  past ~150° the arms disappear behind the head. They also have to be drawn
  in front of the torso, or only a stub clears the silhouette.
- **Worn wings need a near-horizontal fan.** Rooted level with the face they
  fan up over the skull and read as a leafy crown; steep, they hide behind
  the torso and read as fluff.
- **The hat's offset and scale are relative to the avatar's scale.** They were
  hardcoded for one avatar size and slid off the head at every other.
- **Backgrounds are keyed to user space.** An `objectBoundingBox` radial on a
  16:9 rect stretches into a wide ellipse, putting the falloff at a different
  distance sideways than vertically.

## Regenerating

Built by a Python script that composes SVG and rasterises through headless
Chromium (not checked into this repo, same as the icon). To tweak, hand-edit
the SVG and re-export at 1920×1080 with any SVG-to-PNG tool.
