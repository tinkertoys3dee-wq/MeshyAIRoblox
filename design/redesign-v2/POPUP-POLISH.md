# Secondary popup polish

The Forge Tokens screenshot used the shared Home popup family. This pass updates Tokens, More tools, Daily Missions, Daily Rewards, UGC Item Codes, and Roblox Plus.

- Native navy panels, restrained borders, a header icon/divider, and larger action rows replace the uniform blue boxes.
- Wallet balances are separate live cards. Lounge, checkout, and Priority Pass actions use distinct colors, icons, captions, and details.
- Missions show real completion progress. Rewards use a seven-day card layout with the actual current reward day highlighted.
- More tools has distinct destination icons and descriptions, with a desktop grid and a compact scrolling list.
- Item Codes keeps its native input/category selector, with free try-on as the primary action and quieter navigation below.
- Plus uses larger copy, separated benefits, stacked actions, and a visible close control.
- Panels reserve Roblox toolbar space. Body text can grow on narrow displays; all actions remain reachable through scrolling.
- Hover/press feedback respects reduced motion and native high contrast. Native action handlers, balances, rewards, prices, and purchase logic are preserved.

The style uses native Roblox geometry and existing SVG-derived Home icons. No new AI bitmap or asset upload was needed.

## Verification

74 source files compile and 1,126 assertions pass, including 34 popup-style checks and 39 Home integration checks. The local Argon project build succeeds.

Studio review covered wallet balance values (1,103 spendable and 321 bonus), action colors/contrast, desktop and smaller-window fit, and the Missions and Rewards views. Toolbar overlap and a shadow that darkened action surfaces were corrected during review. User mouse activity prevented the remaining automated popup navigation; those variants retain source/behavior coverage and are synced for review in Studio.

Financial controls were inspected without activating purchases. The offline integration fixture verifies their original handlers without contacting Roblox.
