# UI sounds

Ten short, originally synthesized (no samples, no external audio, nothing
that needs a license) UI sound effects for `src/Shared/SoundIds.luau`,
matching the character/duration spec in `docs/SOUND_SETUP.md`. Generated with
a small numpy/scipy synthesis script (not checked into this repo) that builds
each sound from sine tones, pitch sweeps, and filtered noise — no vocals, no
third-party material.

`ogg/` holds the upload-ready files (OGG Vorbis, what Roblox's audio importer
accepts); `wav/` holds the same sounds as uncompressed 16-bit PCM if you want
to inspect, trim, or re-edit one in an audio editor before uploading.

| File (without extension) | `SoundIds.luau` key | Spec'd direction | Actual length |
|---|---|---|---|
| `ui_hover` | `Hover` | soft glass tick, 60–90 ms | 75 ms |
| `ui_press` | `Press` | compact glossy click, 90–130 ms | 110 ms |
| `ui_panel_open` | `PanelOpen` | airy upward synth bloom, 250–350 ms | 300 ms |
| `ui_panel_close` | `PanelClose` | quiet reverse bloom, 180–250 ms | 210 ms |
| `ui_success` | `Success` | restrained two-note digital chime, 400–600 ms | 500 ms |
| `ui_error` | `Error` | warm muted low pulse, 220–350 ms | 280 ms |
| `ui_queue` | `Queue` | subtle metallic drop, 200–300 ms | 240 ms |
| `ui_generation_ready` | `GenerationReady` | polished three-note reveal, 700–950 ms | 820 ms |
| `ui_like` | `Like` | tiny soft pop, 100–180 ms | 130 ms |
| `ui_purchase_prompt` | `PurchasePrompt` | low-volume rising confirmation tone, 300–450 ms | 380 ms |

## Uploading

Roblox doesn't expose an API for a script to upload its own audio assets, and
this repo's automation has no Open Cloud credential to do it with even if it
did — audio has to go through Creator Hub by hand, same as every badge/product
icon in `assets/icons/`:

1. Creator Hub → your experience or group → **Audio** (or **Creator Store** →
   **Upload**) → upload the matching file from `ogg/`.
2. Wait for Roblox's moderation to approve it (usually automatic and fast for
   a short synthesized tone, but can take longer).
3. Copy the numeric asset ID Roblox gives you into the matching key in
   `src/Shared/SoundIds.luau`, replacing that key's `0`.

A key left at `0` just means `SoundController` skips creating a `Sound`
instance for it — nothing errors, that cue is silent until filled in.

## Regenerating or editing

Each sound is parameterized (frequency, sweep range, envelope shape) rather
than hand-drawn, so the easiest way to change one's character is to re-run
the synthesis script with different numbers for that sound and re-export.
Short of that, the `wav/` files are plain 16-bit PCM and open in any editor
(Audacity, etc.); re-export as OGG Vorbis afterward for upload.
