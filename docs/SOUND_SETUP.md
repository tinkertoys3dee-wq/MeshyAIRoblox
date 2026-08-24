# Sound setup

`assets/sounds/wav/` already has all ten sounds below, synthesized to this spec and verified against it (see `assets/sounds/README.md`) — there's nothing left to source or record. They're 44.1 kHz mono 24-bit WAV, which Roblox accepts for upload directly. Upload each under the experience's creator/group, grant the experience permission to use it, and replace the zeros in `src/Shared/SoundIds.luau` with their numeric asset IDs.

| Key | File (`assets/sounds/wav/`) | Sound direction | Used for |
|---|---|---|---|
| `Hover` | `ui_hover.wav` | soft glass tick, 60–90 ms | pointer entering an actionable card/button |
| `Press` | `ui_press.wav` | compact glossy click, 90–130 ms | normal button confirmation |
| `PanelOpen` | `ui_panel_open.wav` | airy upward synth bloom, 250–350 ms | opening a main panel |
| `PanelClose` | `ui_panel_close.wav` | quiet reverse bloom, 180–250 ms | closing a panel |
| `Success` | `ui_success.wav` | restrained two-note digital chime, 400–600 ms | saved fit, completed purchase, completed job |
| `Error` | `ui_error.wav` | warm muted low pulse, 220–350 ms | validation or network error |
| `Queue` | `ui_queue.wav` | subtle metallic drop, 200–300 ms | job accepted into queue |
| `GenerationReady` | `ui_generation_ready.wav` | polished three-note reveal, 700–950 ms | image or model ready |
| `Like` | `ui_like.wav` | tiny soft pop, 100–180 ms | like/favorite toggle |
| `PurchasePrompt` | `ui_purchase_prompt.wav` | low-volume rising confirmation tone, 300–450 ms | immediately before a Roblox purchase modal |

The shipped set is already levelled for this: files sit within ~5 dB of each other by weighted RMS with peaks between 0.20 and 0.58, leaving headroom for `Sound.Volume` scaling on top (see `assets/sounds/README.md` for why the per-cue level difference lives in the mixer rather than in the files). The client pools the configured `Sound` instances under `SoundService/ForgeUISounds`; the navigation sound toggle applies immediately and persists in the player's profile.
