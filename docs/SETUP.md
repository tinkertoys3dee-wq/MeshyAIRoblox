# Creator setup checklist

No secret should be pasted into chat or committed to this repository.

## Roblox Creator Hub

1. Set the experience's maximum player count to **15**.
2. Enable HTTP requests and Studio API access for the experience.
3. Add a Creator Hub secret named `FORGE_BACKEND_SECRET`; use the same cryptographically random value of at least 32 characters for Railway's `ROBLOX_SHARED_SECRET`.
4. Create developer products at the suggested prices and enter their IDs in `src/Shared/Config.luau`:
   - Direct Text → 3D: 159 R$
   - Reference Image: 29 R$
   - Image → 3D Conversion: 159 R$
   - Priority Queue Pass: 29 R$
5. Enter the Roblox group ID in `Config.Group.Id` to enable 10% faster queue polling and one extra queued job.
6. Create Avatar Creation Tokens for each accessory type you will permit. Enter those public token IDs in `Config.AvatarCreationTokens`.
7. Keep the group or token owner ID-verified with Roblox Premium so in-experience avatar creation remains available.
8. Enable API access for the Open Cloud key used by Railway:
   - Assets API read/write for the experience's group creator.
   - Restrict the key by IP if Railway provides a stable egress IP.
9. Complete the experience's Maturity & Compliance questionnaire, disclose paid item trading, and confirm that the experience enforces `IsPaidItemTradingAllowed` and `IsContentSharingAllowed` per player.

## Railway variables

Copy every field from `backend/.env.example` into the Railway service. Required production values are:

- `MESHY_API_KEY`
- `OPENAI_API_KEY`
- `ROBLOX_OPEN_CLOUD_API_KEY`
- `ROBLOX_CREATOR_ID` (the group ID)
- `ROBLOX_CREATOR_TYPE=group`
- `ROBLOX_SHARED_SECRET`
- `DATABASE_URL` (attach Railway PostgreSQL)

Create a Railway service from this repository with `backend/` as its root directory. Use `npm run build` as the build command, `npm run start` as the start command, and `/health` as the health-check path. A production boot deliberately fails if PostgreSQL, the Roblox shared secret, or any live provider credential is absent.

Finally, put the Railway HTTPS origin in `Config.Backend.BaseUrl`. Do not include a trailing slash.

## Studio smoke test

With the IDs still set to `0`, Studio uses mock purchases and placeholder model results. Verify onboarding, both creation paths, fitting-control state, visibility/listing controls, discovery, catalog try-on, sound preferences, and reconnect persistence before enabling live products. Placeholder asset IDs do not render a mesh; test the full viewport/equip/publish path with a privately owned test model or the live backend. Never put a provider key in a Luau file.
