# Experience thumbnail — "The Forge Chamber"

`png/forge_ugc_thumbnail_1920x1080.png` — the 16:9 thumbnail for the
experience page carousel. Roblox wants thumbnails at 16:9 and recommends
1920×1080; `.png` is among the accepted formats. Source is
`svg/forge_ugc_thumbnail.svg`.

Upload it in Creator Hub → your experience → Basic Info → Thumbnails.
Nothing in `src/` reads this file, and no ID from it goes back into code.

## What this is

A constructed one-point-perspective interior, not a flat staging layer:

- A **pillar corridor** receding to a vanishing point on the horizon.
- A **furnace arch** built into the far wall, white-hot, banked with coals.
- The player's avatar seen **from behind** — pure shadow, hot edges, one arm
  raised into the light. Shot from behind, the viewer occupies the character
  rather than looking at a mascot.
- **UGC items on a perspective ellipse**, cyan wireframe on the far half and
  finished solid on the near half. That is the generation loop made visible
  rather than described.
- **Hanging braziers** and an **anvil** standing in the light, so the room
  reads as a forge with its own light sources.
- A **near plane** of out-of-focus embers and a hard-cropped item, so the
  image has real depth rather than one flat plane.

Deliberately **no sunburst and no symmetrical character lineup**. Those are
the mobile-icon template, and they are what the earlier drafts of this file
kept defaulting to.

## The perspective is one function

`depth_scale(t)` returns the foreshortening factor for a depth `t`, and the
floor rungs, the pillar corridor and the orbiting item sizes all key off it.
Anything that computes its own falloff drifts out of agreement with the rest
of the scene within one edit.

## Things worth not re-learning

- **A uniform rim light on the hero does nothing.** The figure is silhouetted
  against the brightest part of the frame, so a screen-blended warm edge over
  a blown-out arch adds no contrast at all. What reads is slightly different
  dark values per body part plus hot edges placed by hand only where a
  surface actually faces the fire.
- **Pillars must be drawn after the light shafts.** Behind them, the warm
  volumetric wash turns the stone beige and destroys the silhouette.
- **A circle floats; an arch sits.** As a circle the furnace read as a sun
  over a desert road. Rounded top, flat bottom on the floor, masonry
  voussoirs — then it reads as a mouth built into a wall.
- **Do not wash the whole floor warm.** Full-width it blew out and looked
  like sand. A carpet of light spilling from the arch and widening toward the
  camera, with dark stone either side, puts the brightness where the fire
  actually throws it.
- **Nothing goes at the front of the orbit ellipse** (angle ≈ 90°) — that is
  where the hero stands, and items there sit on top of him.
- **The far pillar pair had to go.** At that depth the columns landed at
  x≈846 and x≈1074, directly behind the hero, and appeared to grow out of his
  shoulders.
- **A blur filter and a drop shadow cannot share an element.** The
  depth-of-field blur goes on an outer wrapper, the shadow on an inner group.

## Regenerating

Built by a Python script that composes SVG and rasterises through headless
Chromium (not checked into this repo, same as the icon). To tweak, hand-edit
the SVG and re-export at 1920×1080 with any SVG-to-PNG tool.
