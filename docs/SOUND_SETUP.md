# Sound setup

Upload short, original, non-vocal UI sounds under the experience's creator/group, grant the experience permission to use them, and replace the zeros in `src/Shared/SoundIds.luau` with their numeric asset IDs.

| Key | Sound direction | Used for |
|---|---|---|
| `Hover` | soft glass tick, 60–90 ms | pointer entering an actionable card/button |
| `Press` | compact glossy click, 90–130 ms | normal button confirmation |
| `PanelOpen` | airy upward synth bloom, 250–350 ms | opening a main panel |
| `PanelClose` | quiet reverse bloom, 180–250 ms | closing a panel |
| `Success` | restrained two-note digital chime, 400–600 ms | saved fit, completed purchase, completed job |
| `Error` | warm muted low pulse, 220–350 ms | validation or network error |
| `Queue` | subtle metallic drop, 200–300 ms | job accepted into queue |
| `GenerationReady` | polished three-note reveal, 700–950 ms | image or model ready |
| `Like` | tiny soft pop, 100–180 ms | like/favorite toggle |
| `PurchasePrompt` | low-volume rising confirmation tone, 300–450 ms | immediately before a Roblox purchase modal |

Keep all sounds under roughly -10 dB relative to Roblox's default UI level. The client pools the configured `Sound` instances under `SoundService/ForgeUISounds`; the navigation sound toggle applies immediately and persists in the player's profile.
