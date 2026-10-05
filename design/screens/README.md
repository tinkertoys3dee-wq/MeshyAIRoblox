# Forge UGC screen artwork

These editable SVG screens follow the supplied Home artwork. Text stays native
in the game. Collection items, avatars, catalog thumbnails and saved graphics
are live player data; the SVG examples are visual placeholders.

The artwork is already uploaded. Pull the latest Git changes and sync
`default.project.json` with Argon to bring the UI into the existing game.
`src/Shared/HomeAssets.luau` and `src/Shared/ScreenAssets.luau` contain the public
Image IDs. An upload key is only needed when adding or replacing artwork;
normal Argon synchronization does not need it. The existing map is preserved.

Run these from the project directory with the configured Python and Node runtimes:

```text
python design/export_screen_assets.py
node design/render_screen_assets.mjs
node design/upload_screen_assets.mjs --dry-run
node design/upload_screen_assets.mjs
```

The exporter extracts every group marked `data-asset` using its `data-bounds`,
retains referenced gradients/filters/clips/symbols, and removes all SVG text.
Groups marked `data-role="ReplaceWith…"` and `data-native` nodes are excluded.
The renderer creates transparent PNGs and deduplicates pixel-identical artwork.
Review `assets/contact-sheet.png`; `assets/manifest.json` records each original
name, unique upload name, source bounds and any slice center.

Shared panel skins are **240 × 240** pixels with a slice center of
**(30, 30, 210, 210)**. Shared button, search and section-header skins are
**240 × 64** pixels with a slice center of **(30, 30, 210, 34)**. These exact
dimensions have no outer padding; the game applies the matching nine-slice
settings. Screen-specific artwork renders at 2× source resolution.

Home chrome and navigation icons reuse the already uploaded Home Image IDs.
The upload key is read silently from the ignored `backend/.env.roblox-upload`;
dry-run does not read credentials. Upload requests only use the official Roblox
Assets API. Images must pass moderation before their numeric public IDs appear
in `src/Shared/ScreenAssets.luau`.

Uploads save progress in `assets/upload_state.json` and approved IDs in
`assets/asset_ids.json`. Re-run the uploader to resume pending operations without
uploading duplicates. `--only PanelBlue,ButtonBlue` selects names;
`--apply-ids` rebuilds the module from saved approved IDs without reading a key.
Use `--force` only to deliberately replace existing uploads.

If a legacy interrupted upload has names quarantined in `recovery_required.json`
and its Image IDs cannot be recovered, `--retry-uncertain` permits one audited
re-upload of each missing name. Earlier accepted copies may remain unused.
Known IDs and operations are reused. The retry is recorded durably before its
POST in `recovery_retry_audit.jsonl` and `upload_journal.jsonl`; the flag cannot
repeat a retry whose new POST is ambiguous. Do not combine it with `--force`.
