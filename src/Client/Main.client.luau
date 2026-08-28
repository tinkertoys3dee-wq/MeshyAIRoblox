--!strict
--l
local Players = game:GetService("Players")

local App = require(script.Parent.UI.App)

-- Limit the normal Roblox gameplay camera, independently of the camera
-- objects used inside Forge's avatar preview ViewportFrames.
Players.LocalPlayer.CameraMaxZoomDistance = 20

App.new()
