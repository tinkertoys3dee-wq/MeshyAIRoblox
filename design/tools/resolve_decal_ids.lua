--[[
	Run this in Roblox Studio's Command Bar (Edit mode is fine, no need to
	press Play) any time after uploading new UI decals via
	design/upload_ui_assets.py or backend/scripts/ui-decals/upload.mjs.

	Why this is needed: Roblox's Open Cloud Assets API creates a "Decal"
	asset (AssetTypeId 13) and hands back that wrapper's own id. That id
	works fine as a 3D Decal.Texture, but NOT as an ImageLabel/ImageButton
	.Image -- GUI image properties need the raw underlying texture id, which
	is a *different* number nested inside the Decal wrapper. There's no
	public HTTP API to get that number; the only reliable way is to actually
	load the asset in the Roblox engine and read it back out, which is what
	this script does via InsertService:LoadAsset.

	It reads the wrapper ids straight out of whatever's currently synced to
	ReplicatedStorage.UIAssets (no need to hand-copy ids into this script),
	resolves every single one, and prints a ready-to-paste Luau table block.
	Hand that block back so UIAssets.luau can be regenerated with the real,
	GUI-usable ids.
]]

local InsertService = game:GetService("InsertService")
local UIAssets = require(game.ReplicatedStorage.UIAssets)

local results = {}
local failures = {}

for name, wrapperId in UIAssets do
	if type(wrapperId) == "number" and wrapperId ~= 0 then
		local ok, modelOrErr = pcall(function()
			return InsertService:LoadAsset(wrapperId)
		end)
		if ok then
			local model = modelOrErr
			local found = nil
			for _, inst in model:GetDescendants() do
				if inst:IsA("Decal") then
					found = inst.Texture
					break
				end
			end
			model:Destroy()
			if found then
				local rawId = found:gsub("rbxassetid://", "")
				table.insert(results, string.format("%s = %s,", name, rawId))
				print("ok", name, wrapperId, "->", rawId)
			else
				table.insert(failures, name)
				print("NO DECAL FOUND", name, wrapperId)
			end
		else
			table.insert(failures, name)
			print("FAILED", name, wrapperId, modelOrErr)
		end
	end
end

print("\n=== paste this block back (design/assets/asset_ids.json needs these) ===")
print(table.concat(results, "\n"))
print("=== end ===")

if #failures > 0 then
	print("\nCould not resolve:", table.concat(failures, ", "))
end
