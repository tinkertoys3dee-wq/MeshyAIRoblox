--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Factory = require(script.Parent.Factory)
local Motion = require(script.Parent.Motion)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))

local NotificationService = {}
NotificationService.__index = NotificationService

function NotificationService.new(host: Frame, sounds: any)
	return setmetatable({ host = host, sounds = sounds, entries = {}, serial = 0 }, NotificationService)
end

-- Three readable, individually dismissible notices; repeated server pushes
-- reuse the same notice and deadline. Height follows text, not a 70px guess.
function NotificationService:Show(tone: string, message: string)
	if not self.host.Parent then
		return
	end
	local key = tone .. ":" .. message
	local now = os.clock()
	local lifetime = if tone == "error" then 9 else 6
	for _, entry in self.entries do
		if entry.key == key then
			entry.expires = now + lifetime
			return
		end
	end
	local height = if Workspace.CurrentCamera then Workspace.CurrentCamera.ViewportSize.Y else 800
	local limit = if height < 500 then 1 elseif height < 750 then 2 else 3
	while #self.entries >= limit do
		local oldest = table.remove(self.entries, 1)
		oldest.frame:Destroy()
	end
	self.serial += 1
	local color = if tone == "error"
		then Theme.Colors.Danger
		elseif tone == "success" then Theme.Colors.Mint
		else Theme.Colors.Cyan
	local frame = Factory.New("Frame", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BorderSizePixel = 0,
		LayoutOrder = self.serial,
		ZIndex = 501,
		Parent = self.host,
	})
	Factory.Corner(frame, 12)
	Factory.Stroke(frame, color, 0.2)
	local content = Factory.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -62, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(14, 0),
		ZIndex = 502,
		Parent = frame,
	})
	Factory.Padding(content, 0, 12)
	Factory.List(content, Enum.FillDirection.Vertical, 5)
	local title = Factory.Label(
		content,
		if tone == "error" then "COULDN'T FINISH" elseif tone == "success" then "DONE" else "FORGE UPDATE",
		UDim2.new(1, 0, 0, 18),
		{ TextSize = 11, Font = Theme.Fonts.Bold, Color = color, ZIndex = 503 }
	)
	title.LayoutOrder = 1
	local body = Factory.Label(content, message, UDim2.new(1, 0, 0, 0), {
		TextSize = 13,
		Wrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		AlignY = Enum.TextYAlignment.Top,
		ZIndex = 503,
	})
	body.LayoutOrder = 2
	local close = Factory.Button(frame, "×", UDim2.fromOffset(36, 36), UDim2.new(1, -43, 0, 7))
	close.ZIndex = 504
	local entry = { key = key, frame = frame, expires = now + lifetime, closing = false }
	table.insert(self.entries, entry)
	local function dismiss()
		if entry.closing then
			return
		end
		entry.closing = true
		local index = table.find(self.entries, entry)
		if index then
			table.remove(self.entries, index)
		end
		Motion.Close(frame, nil)
	end
	close.Activated:Connect(dismiss)
	local scale = Factory.New("UIScale", { Scale = 0.97, Parent = frame })
	Motion.Tween(scale, 0.18, { Scale = 1 })
	if tone == "error" then
		self.sounds:Play("Error")
	elseif tone == "ready" then
		self.sounds:Play("GenerationReady")
	end
	task.spawn(function()
		while frame.Parent and not entry.closing do
			task.wait(0.5)
			if os.clock() >= entry.expires then
				dismiss()
			end
		end
	end)
end

return NotificationService
