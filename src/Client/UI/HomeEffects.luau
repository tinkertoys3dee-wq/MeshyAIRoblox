--!strict

-- Pop and entrance effects for absolute-positioned SVG controls. Controls in
-- native list/grid layouts retain Motion.Bind's layout-safe outline feedback.
local Motion = require(script.Parent.Motion)
local HomeEffects = {}

local function activationInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonA
		or input.KeyCode == Enum.KeyCode.Return
		or input.KeyCode == Enum.KeyCode.Space
end

function HomeEffects.Button(button: GuiButton, accent: Color3)
	if button:GetAttribute("ForgePopBound") then return end
	button:SetAttribute("ForgePopBound", true)
	Motion.Bind(button)
	-- Center the pivot without changing the resting bounds or authored size.
	local anchor, size, position = button.AnchorPoint, button.Size, button.Position
	local dx, dy = 0.5 - anchor.X, 0.5 - anchor.Y
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position + UDim2.new(size.X.Scale * dx, size.X.Offset * dx, size.Y.Scale * dy, size.Y.Offset * dy)
	local scale = Instance.new("UIScale")
	scale.Name = "PopScale"
	scale.Scale = 1
	scale.Parent = button
	local hovering, selected, pressing, alive = false, false, false, true
	local revision = 0
	local tween: Tween? = nil
	local function update(rebound: boolean?)
		revision += 1
		local current = revision
		if tween then tween:Cancel(); tween = nil end
		if not alive then return end
		local outline = button:FindFirstChild("InteractionOutline") :: UIStroke?
		if outline then outline.Color = accent end
		if not button.Active or Motion.IsReduced() then
			scale.Scale = 1
			return
		end
		local rest = if hovering or selected then 1.035 else 1
		local goal = if pressing then 0.95 elseif rebound then rest + 0.035 else rest
		tween = Motion.Tween(scale, if pressing then 0.07 else 0.13, { Scale = goal },
			if pressing then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
		if rebound then
			task.delay(0.13, function()
				if alive and revision == current then update(false) end
			end)
		end
	end
	button.MouseEnter:Connect(function() hovering = true; update(false) end)
	button.MouseLeave:Connect(function() hovering = false; pressing = false; update(false) end)
	button.SelectionGained:Connect(function() selected = true; update(false) end)
	button.SelectionLost:Connect(function() selected = false; pressing = false; update(false) end)
	button.InputBegan:Connect(function(input)
		if button.Active and activationInput(input) then pressing = true; update(false) end
	end)
	button.InputEnded:Connect(function(input)
		if activationInput(input) and pressing then pressing = false; update(true) end
	end)
	button.Activated:Connect(function()
		if button.Active then pressing = false; update(true) end
	end)
	button:GetPropertyChangedSignal("Active"):Connect(function() pressing = false; update(false) end)
	button.Destroying:Connect(function()
		alive = false
		revision += 1
		if tween then tween:Cancel() end
	end)
end

function HomeEffects.Rise(target: GuiObject, delaySeconds: number, distance: number?)
	if Motion.IsReduced() then return end
	local rest = target.Position
	local alive, started = true, false
	local tween: Tween? = nil
	target.Position = rest + UDim2.fromOffset(0, distance or 18)
	local function finish()
		if not alive or started then return end
		started = true
		tween = Motion.Tween(target, 0.36, { Position = rest }, Enum.EasingStyle.Quint)
	end
	-- A hovered/selected control immediately reaches its resting spot, so the
	-- delayed entrance cannot later pull it away from the player's pointer.
	local hovered = target.MouseEnter:Connect(finish)
	local selected = target.SelectionGained:Connect(finish)
	target.Destroying:Connect(function()
		alive = false
		hovered:Disconnect()
		selected:Disconnect()
		if tween then tween:Cancel() end
	end)
	task.delay(delaySeconds, finish)
end

function HomeEffects.Card(card: Frame, action: GuiButton, accent: Color3, entranceDelay: number?)
	local rest = card.Position
	local hovering, selected, alive = false, false, true
	local revision = 0
	local liftTween: Tween? = nil
	local glowTween: Tween? = nil
	local glow = Instance.new("UIStroke")
	glow.Name = "CardGlow"
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Color = accent
	glow.Thickness = 2.5
	glow.Transparency = 1
	glow.Parent = card
	local function update()
		revision += 1
		if liftTween then liftTween:Cancel() end
		if glowTween then glowTween:Cancel() end
		if not alive then return end
		local emphasized = hovering or selected
		local lift = if emphasized and not Motion.IsReduced() then -6 else 0
		liftTween = Motion.Tween(card, 0.2, { Position = rest + UDim2.fromOffset(0, lift) })
		glowTween = Motion.Tween(glow, 0.16, { Transparency = if emphasized then 0.12 else 1 })
	end
	card.MouseEnter:Connect(function() hovering = true; update() end)
	card.MouseLeave:Connect(function() hovering = false; update() end)
	local gained = action.SelectionGained:Connect(function() selected = true; update() end)
	local lost = action.SelectionLost:Connect(function() selected = false; update() end)
	card.Destroying:Connect(function()
		alive = false
		revision += 1
		gained:Disconnect()
		lost:Disconnect()
		if liftTween then liftTween:Cancel() end
		if glowTween then glowTween:Cancel() end
	end)
	if entranceDelay and not Motion.IsReduced() then
		card.Position = rest + UDim2.fromOffset(0, 22)
		task.delay(entranceDelay, function()
			if alive and revision == 0 then
				liftTween = Motion.Tween(card, 0.4, { Position = rest }, Enum.EasingStyle.Quint)
			end
		end)
	end
end

return HomeEffects
