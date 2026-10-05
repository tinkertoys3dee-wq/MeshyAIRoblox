# Arcade, Runway and Settings conversion notes

The full mockup PNGs were measured before reconstruction. These three SVGs use
native paths and gradients with editable text, separate named panel/button/icon
groups, artwork-only `data-asset` groups and explicit bounds. No raster images
are embedded. The exact approved Home brand and background are reused.

- Arcade includes all eleven actual game destinations and Leaderboards, with
  independent Play controls, weekly prizes and the daily challenge strip.
- Runway includes the four illustrated entrant rows, avatar stage, Reset camera,
  phase/timer, lock action, Avatar Lab, invite control, weekly standings and
  Refresh. Its reward copy matches `Config.Runway.WeeklyPlacementXP` and the
  server payout: first +600 XP, second +350 XP, third +200 XP. The generated
  reference was corrected before final conversion; the previous exclusive-item
  claim is absent.
- Settings includes Simple/Advanced, the accessibility toggles and scale slider,
  sound toggle, equipped-item removal and community controls. The four visible
  achievement labels match the real definitions: First Spark, Bring a Friend,
  Collector and Prolific.

Player portraits, avatar scenery, equipped thumbnails, balances, names, scores,
progress values and achievement states illustrate a possible populated state.
Their artwork/text carries replacement roles and must be populated with real
runtime content when integrated. Unshown list entries and alternate states
remain governed by `screen-specs.json`.

Illustrations were traced separately at color precision 8, layer difference 4,
speckle 1 and length threshold 2. Small Runway portraits use more precise polygon
outlines with layer difference 1, speckle 0 and length threshold 0.8. The helper's
evenodd clip holes exclude overlaid control lettering. Detailed bitmap shading
is approximated by vector contours; native typography and chrome differ slightly
from the raster reference.

Final SVG renders, amplified differences, comparison sheets and pixel metrics
are in `svg/qa/arcade`, `svg/qa/runway` and `svg/qa/settings`. All three passed
`validate_vectors.py --require-ui-groups`. They were also visually inspected and
label spacing, button fit, header icon spacing and weekly row contrast repaired.
The corrected Settings PNG is 1671 pixels wide; its SVG retains the shared
1672 × 941 design canvas, a one-pixel reference difference.

Rebuild these files with `vector_ars.py arcade runway settings`; regenerate
illustrations with `trace_ars_art.py arcade runway settings`.
