# Sound setup

`assets/sounds/` already has all ten sounds below, synthesized to this spec and ready to upload (see `assets/sounds/README.md`) — there's nothing left to source or record. Upload each short, original, non-vocal file under the experience's creator/group, grant the experience permission to use it, and replace the zeros in `src/Shared/SoundIds.luau` with their numeric asset IDs.

| Key | File (`assets/sounds/ogg/`) | Sound direction | Used for |
|---|---|---|---|
| `Hover` | `ui_hover.ogg` | soft glass tick, 60–90 ms | pointer entering an actionable card/button |
| `Press` | `ui_press.ogg` | compact glossy click, 90–130 ms | normal button confirmation |
| `PanelOpen` | `ui_panel_open.ogg` | airy upward synth bloom, 250–350 ms | opening a main panel |
| `PanelClose` | `ui_panel_close.ogg` | quiet reverse bloom, 180–250 ms | closing a panel |
| `Success` | `ui_success.ogg` | restrained two-note digital chime, 400–600 ms | saved fit, completed purchase, completed job |
| `Error` | `ui_error.ogg` | warm muted low pulse, 220–350 ms | validation or network error |
| `Queue` | `ui_queue.ogg` | subtle metallic drop, 200–300 ms | job accepted into queue |
| `GenerationReady` | `ui_generation_ready.ogg` | polished three-note reveal, 700–950 ms | image or model ready |
| `Like` | `ui_like.ogg` | tiny soft pop, 100–180 ms | like/favorite toggle |
| `PurchasePrompt` | `ui_purchase_prompt.ogg` | low-volume rising confirmation tone, 300–450 ms | immediately before a Roblox purchase modal |

Keep all sounds under roughly -10 dB relative to Roblox's default UI level. The client pools the configured `Sound` instances under `SoundService/ForgeUISounds`; the navigation sound toggle applies immediately and persists in the player's profile.
