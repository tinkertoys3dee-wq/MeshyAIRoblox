# Create, My Items, and Market conversion

The final corrected generated PNGs in `mockups/` are the measured references for
`svg/create.svg`, `svg/my-items.svg`, and `svg/market.svg`.

The approved Home's branding, blurred city backdrop, outer shell and shared
header icons are reused. Each new screen body is reconstructed from its new
image. Panels, fields, buttons, dividers and icon controls use native SVG shapes,
gradients, shadows and glow. All UI lettering remains separate editable `<text>`.
Decorative crowns, accessories, avatars and display scenes are real traced paths,
with individual named `data-asset` groups and measured bounds. Traced illustrations
approximate the generated image's fine shading; they are not embedded PNGs.

`build_create_market.py` regenerates these three conversions. Artwork uses color
precision 8, layer difference 4, speckle filter 1 and curve length threshold 2.
UI lettering/control rectangles are excluded from hero tracing. Explicit SVG
clip holes remove masked rectangles, including any black paths produced by the
tracer for transparent pixels. UI controls are rebuilt outside those artwork
groups. Bold heading measurement uses Arial Black; body/button text uses Arial.

Corrections now match the image edits: My Items and Close in all three headers,
Create's lower Close removed, My Items active shortcut without an active Create
tab, Create new in the collection's upper right, and no invented verification
badges in the community cards.

Sample creators, counts, balances, statistics and accessory images are placeholders.
Dynamic artwork groups carry `ReplaceWith…` roles. The item name field and Save
name are marked `data-state="Advanced item editing"`, so these visible design
controls describe that existing edit state rather than an additional game feature.
The creation price is sample presentation and retains the Roblox confirmation note.

All three SVGs passed `validate_vectors.py --require-ui-groups`: no raster
embedding, external resources, duplicate IDs or unresolved SVG references. Final
renders and side-by-side comparisons are in `svg/qa/{create,my-items,market}/`.
Visual QA checked field and button geometry, complete pedestals, header controls,
separate labels, native glow, and the artwork exclusion edges.
