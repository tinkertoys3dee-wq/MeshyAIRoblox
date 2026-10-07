# Forge UI polish verification

Verified in Roblox Studio on 2026-10-07. Normal mode is enabled, with the full illustrated design.

## Changes

- Keep uploaded artwork renderable while loading, with native surfaces as the fallback. This fixes the panels and icons that remained invisible.
- Put Graphics composer controls, instructions, the real avatar thumbnail, and activity strip above their decorative surfaces. Text-source mode now uses a wide, taller input.
- Preserve live avatars, item thumbnails, prices, owned items, progress, and original action handlers. Example creation art is explicitly labeled.
- Separate icon and caption space, readiness details and preview space, marketplace title and free-try-on badge, and Runway action/status rows.
- Add native holographic stages behind the existing item and Runway avatar viewports.
- Give Avatar Lab persistent page-owned navigation and a visible worn-item list.
- Improve Graphics Discover with complete Fit previews and separate captions/actions. Its compact layout scrolls the entire page so short windows cannot hide every result.
- Shorten compact chrome, keep the logo clear of Roblox's toolbar, darken the compact backdrop for readability, and remove unnecessary Settings card headroom.
- Replace earned achievement and shared Arcade glyphs with approved artwork. Genuine locked achievement states remain intact.
- Keep Arcade HUD, retry/back controls, and weekly standings readable after the outer modal is scaled. Preserve the standings list layout during refresh; keep standings clear of the game-over card.
- Hide stale preview ornaments when switching skins or returning to the original native layout.

## Studio review

Reviewed the Home, Create, My Items, Community Market, Avatar Lab, Avatar Graphics, Games, Arcade, Runway, and Settings screens through native UI navigation. Also reviewed Avatar Graphics avatar/text source modes, Graphics Discover and its detail view, onboarding choices, and the shared Arcade result/weekly panels.

Desktop Studio window: 1536 × 816, game viewport approximately 1270 × 575. Smaller Studio window: 1134 × 816, game viewport approximately 865 × 568. Compact Settings and Graphics Discover were checked at the existing 125% interface preference, including scrolling to captions and actions below the fold.

The review uses real Studio rendering and local playtest data. Paid purchases, generation checkout, publishing, creator tips, and external social actions were not executed. Their original native controls and handlers are retained.

## Automated verification

All 73 Luau source files compile. 1,080 assertions pass:

| Suite | Assertions |
| --- | ---: |
| UI/avatar | 238 |
| Home | 27 |
| Home effects | 49 |
| Modern screens | 344 |
| Redesigned core screens | 95 |
| Redesigned games | 64 |
| Redesigned tools | 163 |
| Actual Graphics composer renderer | 58 |
| Actual Graphics Discover renderer | 42 |

The extracted renderer suites exercise the real App methods with engine doubles; they complement Studio visual review. Suites run in isolated processes to avoid the Luau VM's fixed heap limit.

Argon builds `default.project.json` successfully into the ignored local `forge-redesign-v2.rbxlx`. Changes are synced through the connected local Argon server.
