This folder contains the runtime import of the nine image-first SVG screens.

Import verification passed: 509/509 runtime names are approved, using 346 new
raw Images and three aliases to the existing Home backdrop. No requests remain
pending or quarantined. The approved PNG pixels, dimensions, world-coordinate
metrics and quoted Luau registry keys match the final manifest.

The exporter separates named artwork groups, removes all SVG text, removes live
item/catalog/avatar/gallery/player thumbnails, and keeps ancestor transforms,
clips, opacity, styles and referenced vector definitions. Nested named artwork
is exported independently, so panel PNGs do not bake in their buttons.

The five Create idea illustrations and the twelve Arcade game illustrations are
static UI art. `CreateHeroV2` is available only for the empty creation state;
actual generation previews replace it. Games destination scenes are decorative.
The city backdrop reuses the existing approved Home Image rather than uploading
another copy. `excluded-live-art.json` lists every excluded runtime placeholder.

`manifest.json` records source rectangles, transparent export rectangles,
dimensions and pixel hashes. `metrics.json` and the generated
`src/Shared/RedesignMetrics.luau` use the 1672×941 design coordinate system. The
`rect` field matches image placement, including four source pixels of edge
padding on surfaces/icons; `sourceRect` is the original named group bounds.

Asset keys use `V2_<PascalScreenSlug>_<originalArtworkName>`. Identical rendered
PNG pixels share one upload; `uploadName` names that canonical Image. Public
Image IDs are stored in `asset_ids.json` and the generated
`src/Shared/RedesignAssets.luau`. The registry only emits moderation-approved raw
Images whose saved pixel hash matches the current rendered component.

From the repository root, run these commands with the configured Python/Node:

```text
python design/redesign-v2/export_runtime_assets.py
node design/render_screen_assets.mjs --dir design/redesign-v2/assets
node design/upload_screen_assets.mjs --dir design/redesign-v2/assets --output src/Shared/RedesignAssets.luau --table RedesignAssets --dry-run
node design/upload_screen_assets.mjs --dir design/redesign-v2/assets --output src/Shared/RedesignAssets.luau --table RedesignAssets
```

The uploader reads the already configured ignored credential file only for a
real upload. Its ignored append-only journal durably records each accepted
operation before snapshot updates. Re-running resumes saved operations and
moderation checks without another upload. Never use `--force` for normal import
or retry work.
