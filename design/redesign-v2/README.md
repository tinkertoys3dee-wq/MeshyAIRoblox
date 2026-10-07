# Generated mockups → editable vectors

Nine redesigned frames are in `mockups/` (full image designs) and `svg/`
(editable vector reconstructions): Create, My Items, Market, Avatar Lab,
Avatar Graphics, Games, Arcade, Runway, and Settings. Open `index.html` to
compare each pair and inspect the files at full size. The approved Home
screen supplies the shared brand and backdrop.

Images were made with the built-in ImageGen tool, then reconstructed as real
SVG paths, gradients, panels, buttons, icons, and editable text. The SVGs do
not embed their reference PNGs. Detailed illustrated media have separate
vector groups; button artwork and text are separate in the game import.

The original generation prompts are in `prompts.json`; `generation-log.json`
records the targeted correction prompts and selected generated files.
`mockups/originals/` preserves the earlier images before control corrections.
Rendered SVGs and side-by-side checks are in `svg/qa/`.
Some fine raster shading is simplified into vector contours; compare the
image and SVG in the gallery. Settings' generated image is 1671 × 941; the
editable SVG uses the shared 1672 × 941 canvas (a one-pixel width difference).
`manifest.json` indexes the editable controls/assets and `validation-all.json`
records the final nine-screen vector checks.

Names, balances, scores, ownership prices, job progress, collection contents,
and avatar art show illustrative states. Their SVG groups are marked for
replacement with live game data. My Items' name editor illustrates its
editing state; original items can save their moderated title from the new
Simple screen too. Runway's weekly reward copy uses the game's actual
Creator XP rewards: 600, 350, and 200 for the top three.

The import is complete: 509 artwork names use 346 new moderation-approved
Roblox Images and three reused Home aliases. The nine screen layouts are
wired into `src/Client/UI/Redesign*Layouts.luau` and the Argon project.
Real avatars, items, posters, scores, prices, and job progress remain native
live content. Complete mobile, Advanced, and public-image discovery flows
remain available through their existing scrollable layouts. See
`assets/README.md` and `assets/verification.json` for the upload inventory.

`SVG-ORIGIN.md` records the audit of all static UI SVG-to-PNG origins, including
the older fallback assets. `node design/verify_svg_png_provenance.mjs` verifies
the current source/output pairs without credentials or uploads. Vector format
does not remove the appearance of an AI illustration traced into SVG paths.

The generated mockup is the visual reference for each new screen. Measure its
actual geometry and colors before reconstructing it; these helpers contain no
previous screen layout or design.

Rebuild chrome, panels, buttons, fields, dividers and typography with native SVG
shapes, gradients and `<text>`. Give panels/buttons/icons separate groups marked
`data-component="panel"`, `"button"` or `"icon"`. Keep an artwork-only group
marked `data-asset="UniqueName"` with `data-bounds="x y width height"`; place its
editable label outside that artwork group. This keeps later image extraction
and native game controls separate.

For detailed decorative artwork, measure a crop that excludes UI lettering and
trace it into an independent vector group:

```text
python design/redesign-v2/trace_artwork.py mockup.png HeroArt.svg --crop x,y,w,h --name HeroArt
```

Repeat `--exclude x,y,w,h` to remove any label/control rectangles that overlap
an artwork crop. Exclusion coordinates use the full reference image; the
masked areas become transparent in the trace and are rebuilt as native UI.

`vtracer 0.6.15` is installed only in the ignored `.deps` directory. The helper
uses its color/path tracer, retains source bounds, and produces actual SVG
paths rather than wrapping an image. A flat full-screen trace would flatten
the UI's semantics; trace artwork separately and reconstruct controls/text.

Validate and inspect each completed screen:

```text
python design/redesign-v2/validate_vectors.py --require-ui-groups converted.svg
node design/redesign-v2/render_conversion_review.mjs mockup.png converted.svg
```

The validator rejects raster embedding, external resources, executable content,
duplicate IDs, missing references and text inside exported artwork groups. The
review helper produces the SVG render beside its generated reference, an
amplified difference image and pixel metrics. Inspect geometry, gradients,
icons and text as well; metrics alone do not establish faithful conversion.
