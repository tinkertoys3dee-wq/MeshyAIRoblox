# SVG origin audit

All 799 authored static UI registry names have genuine SVG sources, including the older fallback assets. No reference PNG is embedded inside any of these SVGs.

| Registry | Names | Evidence |
| --- | ---: | --- |
| HomeAssets | 30 | Fresh SVG renders exactly match the PNG pixels |
| ScreenAssets | 220 | 199 SVG renders match; 21 aliases resolve to verified Home exports |
| RedesignAssets | 509 | 506 SVG renders match; 3 aliases resolve to the verified Home backdrop |
| UIAssets | 40 | Original Chromium exporter renders the paired pure SVG; source/output dimensions and hashes are recorded |

The 759 names using the Sharp renderer or Home aliases have independent exact pixel verification. The 40 older UIAssets use Chromium's SVG renderer; Sharp pixel equality is not claimed for a different rasterizer. Their source files contain native SVG geometry, and the documented exporter renders that SVG before cropping the transparent PNG.

Live avatar, catalog, item, and player-created image thumbnails are game content and are outside this authored UI artwork audit.

## What this does and does not establish

The format requirement is satisfied: SVG geometry comes before the runtime PNG. The detailed art in 44 redesign asset names was traced from AI-generated mockups into SVG paths. That conversion retains the original illustrated appearance. A cleaner, manually drawn vector style would require redrawing those illustrations, not simply changing their file format. The list is in `audits/svg-provenance.json`.

## Keeping the requirement enforced

Home and screen renderers reject embedded bitmap or external SVG content. Home, screen, and redesign upload tools verify that PNG pixels match a fresh render of the paired SVG before uploading. The legacy Chromium exporter stamps source/output hashes; its loader rejects missing sources, raster embedding, mismatched dimensions, and stale stamped outputs. All 40 existing exports now have these stamps.

The historical 37-PNG upload bundle also verifies its original SVG sources and byte-identical exported PNGs before reading credentials. Four stale copies of buttons/pills were refreshed from the current SVG exports. Existing Roblox Image IDs and runtime artwork were unchanged.

Run the read-only audit from the repository root:

```text
node design/verify_svg_png_provenance.mjs
```

`audits/static-ui-provenance.json` contains the per-name source, output, hashes, dimensions, aliases, and verification results. This check does not read API credentials or upload anything.
