--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundIds = require(ReplicatedStorage:WaitForChild("SoundIds"))

local SoundController = {}
SoundController.__index = SoundController

function SoundController.new()
	local folder = Instance.new("Folder")
	folder.Name = "ForgeUISounds"
	folder.Parent = SoundService
	local self = setmetatable({
		folder = folder,
		sounds = {} :: { [string]: Sound },
		enabled = true,
	}, SoundController)
	for name, assetId in SoundIds do
		if assetId > 0 then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = "rbxassetid://" .. tostring(assetId)
			sound.Volume = if name == "Hover" then 0.22 else 0.42
			sound.Parent = folder
			self.sounds[name] = sound
		end
	end
	return self
end

function SoundController:Play(name: string)
	if not self.enabled then
		return
	end
	local sound = self.sounds[name]
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

function SoundController:Bind(button: GuiButton)
	if button:GetAttribute("ForgeSoundBound") then
		return
	end
	button:SetAttribute("ForgeSoundBound", true)
	button.MouseEnter:Connect(function()
		if button.Active then
			self:Play("Hover")
		end
	end)
	button.Activated:Connect(function()
		if button.Active then
			self:Play("Press")
		end
	end)
end

function SoundController:SetEnabled(enabled: boolean)
	self.enabled = enabled
end

return SoundController
