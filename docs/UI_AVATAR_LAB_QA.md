# UI and Avatar Lab update

## What changed

- Shared pointer, touch, keyboard and gamepad button feedback, with reduced-motion support. Feedback does not enlarge controls into neighbouring cards.
- Animated studio and modal transitions. Duplicate close/reopen actions cannot strand or unexpectedly hide the studio. Modals refit after viewport changes.
- Label truncation, live font/alignment/padding updates for decal labels, header/close-button gutters, scrollable desktop navigation, and a labelled mobile bottom bar.
- A global notification service with dismiss controls, deduplication, text-driven height, and a smaller stack on short screens. Forge requests acknowledge immediately; errors and results remain distinct from payment confirmation.
- A versioned, scrollable starting guide with Create, Style and Arcade routes. The paid custom-generation process is explained before a purchase; catalog try-on is explicitly separate from ownership.
- Avatar Lab: 16 accessory/clothing categories, price/creator/sort filters, paginated results, session bookmarks, a mobile-accessible live look preview, worn-item removal, bounded server-side undo/redo, and Roblox's native avatar-save prompt.
- Mixed outfits save catalog appearance together with owned Forge UGC IDs. Existing Forge-only outfits remain compatible. A Style Spark theme can seed a catalog search and an editable matching custom-UGC idea; it does not submit or purchase anything.
- Catalog permission now appears before search/filter controls. The first successful phone try-on opens My look once; later edits preserve the player's chosen tab. Style Sparks are expandable to keep initial results closer to the top.
- Completed generations use non-blocking notices during Arcade, styling or another modal, rather than covering active play. Repeated Arcade opens cannot stack duplicate windows.

No price, entitlement, generation backend, publishing-bound calculation, or world/map changes are included. This is separate from the earlier paid-generation/bounds PR.

## Automated checks

Run from the repository root:

```sh
npm ci --prefix backend
npm run check --prefix backend
npm run check:luau --prefix backend
npm test --prefix backend
npm run build --prefix backend
npx --yes @johnnymorganz/stylua-bin@2.5.2 --check src backend/tests/luau
git diff --check
```

`check:luau` compiles every source file in the Luau VM, then executes the actual shared UI, avatar snapshot, catalog service, catalog search and studio-transition code with deterministic engine doubles. It checks stale responses, pagination retry/deduplication, bounded notifications/history, reduced motion, responsive modal scale math, duplicate close/reopen, server asset-type validation, classic/layered clothing, undo/redo failures, catalog-only outfit saving and legacy outfit compatibility.

These are **not** Roblox engine rendering or Luau type-analysis tests. No Studio runtime or live device rendering was available during implementation. Do not treat the automated pass as proof that every screen is visually flawless or that native catalog/purchase APIs work in a published session.

## Required Studio / private-server release gate

Use a private test place before publishing to players. Sync the complete `src/Shared`, `src/Server` and `src/Client` trees together; the existing Rojo project already includes the added modules.

| Surface | Test | Expected result |
| --- | --- | --- |
| Phone portrait | 320×568 and 390×844; open each page | Six readable bottom-nav captions; headers do not touch close/help buttons; cards have a usable single-column layout |
| Phone landscape | 844×390; rotate with guide, Arcade and Runway open | Close controls remain reachable; guide scrolls; no content extends outside its intended clipping region |
| Desktop/tablet | 768×1024, 1280×720, 1920×1080; both UI modes | Desktop preview never collides with editor; nav extras scroll; long item names truncate within cards |
| Accessibility | UI scale 80–140%, high contrast, reduced motion, keyboard and controller | No hidden navigation; selection/press feedback works; reduced motion applies final states immediately |
| Notifications | Repeat an action; trigger several failures; close the studio | Duplicate notices coalesce; short screens show fewer; notices stay readable, dismissible and independent of the studio |
| Onboarding | New profile and existing tutorial-version-1 profile; every route and Skip | Guide appears once per version; choices remain usable after an error; no automatic purchase/generation request |
| Catalog consent | Accept, cancel, retry; reconnect | Explicit Roblox permission prompt; cancellation explains next step; no search without approved access |
| Catalog search | Rapid query/category changes; repeated Load more; disconnect/reconnect | Latest query wins; no duplicate cards; previous results remain on page-load failure; loading state clears |
| Try-on | Hat, hair, classic shirt/pants/T-shirt, face, layered jacket/top/pants | Correct type is applied; already-worn try-on is a no-op; worn list and 3D preview reflect the character |
| Outfit editing | Undo/redo/reset; respawn; apply outfit after undo | History is bounded and character-scoped; whole-outfit replacement clears old catalog history |
| Forge mixing | Wear/remove custom item over catalog clothing; save, rejoin, restore | Snapshot restores catalog appearance and owned custom items; unavailable pieces are skipped without granting ownership |
| Native purchase/save | Cancel first; only make a paid test purchase if separately authorized | No success toast on canceled avatar save; Roblox confirms final item price/ownership; trying an item is not a purchase |
| Runway | Change look while voting/look is frozen | Server rejects the edit without changing the look; UI explains the lock |
| Existing editor | Text/image/avatar generation, My Studio fitting, Discover, Avatar Art, Settings | Existing workflows still open; Forge gives immediate feedback; no new automatic retries or charges |

Also verify long/localized text, slow thumbnail loading, touch scrolling around the avatar viewport, and repeatedly opening/closing every modal. Record screenshots and any engine Output errors before approving release. If the whole UI needs rollback, revert this PR as a unit; legacy outfit readers ignore the optional `avatarLook` field.

## Platform references

- [Avatar editor integration and consent](https://create.roblox.com/docs/players/avatar-editor)
- [AvatarEditorService search/save APIs](https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService)
- [CatalogPages pagination](https://create.roblox.com/docs/reference/engine/classes/CatalogPages)
- [HumanoidDescription appearance fields](https://create.roblox.com/docs/reference/engine/classes/HumanoidDescription)
- [AvatarAssetType categories](https://create.roblox.com/docs/reference/engine/enums/AvatarAssetType)

## Scope of the product improvement

This is an integrated styling workflow, not a claim of feature parity with Catalog Avatar Creator. Bookmarks are explicitly **for the current visit**; saved mixed outfits are persistent. Body sliders, catalog bundles, emotes and cross-player outfit sharing are not introduced here. No demographic-specific claim is made because an age-distribution image was not available in the current context. Retention and spending effects need a fresh post-release cohort; they cannot be inferred from a code/test pass.
