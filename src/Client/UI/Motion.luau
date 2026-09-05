--!strict

local TweenService = game:GetService("TweenService")

local Motion = {}
local reduced = function(): boolean
	return false
end

function Motion.Configure(isReduced: () -> boolean)
	reduced = isReduced
end

function Motion.Tween(target: Instance, seconds: number, properties: { [string]: any }): Tween?
	if reduced() then
		for key, value in properties do
			(target :: any)[key] = value
		end
		return nil
	end
	local tween =
		TweenService:Create(target, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	tween:Play()
	return tween
end

function Motion.FitScale(size: Vector2, viewport: Vector2, preferred: number): number
	return math.max(
		0.1,
		math.min(
			preferred,
			math.max(1, viewport.X - 24) / math.max(1, size.X),
			math.max(1, viewport.Y - 24) / math.max(1, size.Y)
		)
	)
end

-- Modals are siblings of the studio, not children of its UIScale. Keep
-- their close controls on-screen, including after a phone rotates.
function Motion.FitPanel(panel: GuiObject, preferred: (() -> number)?): UIScale
	local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = panel
	if panel:GetAttribute("ForgeFitBound") then
		return scale :: UIScale
	end
	panel:SetAttribute("ForgeFitBound", true)
	local parent = panel.Parent :: GuiObject
	local function fit()
		local viewport = parent.AbsoluteSize
		local width = panel.Size.X.Scale * viewport.X + panel.Size.X.Offset
		local height = panel.Size.Y.Scale * viewport.Y + panel.Size.Y.Offset
		local constraint = panel:FindFirstChildOfClass("UISizeConstraint")
		if constraint then
			width = math.clamp(width, constraint.MinSize.X, constraint.MaxSize.X)
			height = math.clamp(height, constraint.MinSize.Y, constraint.MaxSize.Y)
		end
		(scale :: UIScale).Scale =
			Motion.FitScale(Vector2.new(width, height), viewport, if preferred then preferred() else 1)
	end
	fit()
	local resized = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local sized = panel:GetPropertyChangedSignal("Size"):Connect(fit)
	panel.Destroying:Connect(function()
		resized:Disconnect()
		sized:Disconnect()
	end)
	return scale :: UIScale
end

-- No position/size tween: layout-owned buttons must never spill into their
-- neighbours. The dedicated outline works on transparent/decal buttons too.
function Motion.Bind(button: GuiButton)
	if button:GetAttribute("ForgeMotionBound") then
		return
	end
	button:SetAttribute("ForgeMotionBound", true)
	button.AutoButtonColor = false
	local outline: UIStroke? = nil
	local hovering, selected, pressing = false, false, false
	local activeTween: Tween? = nil
	local function update()
		if not outline then
			-- Create after normal styling, so existing code looking for the
			-- button's first UIStroke continues to find its authored border.
			outline = Instance.new("UIStroke")
			outline.Name = "InteractionOutline"
			outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			outline.Color = Color3.fromRGB(186, 239, 255)
			outline.Transparency = 1
			outline.Parent = button
		end
		if activeTween then
			activeTween:Cancel()
		end
		local opacity = if not button.Active then 1 elseif pressing then 0 elseif hovering or selected then 0.35 else 1
		activeTween =
			Motion.Tween(outline :: UIStroke, 0.12, { Transparency = opacity, Thickness = if pressing then 3 else 2 })
	end
	button.MouseEnter:Connect(function()
		hovering = true
		update()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		update()
	end)
	button.SelectionGained:Connect(function()
		selected = true
		update()
	end)
	button.SelectionLost:Connect(function()
		selected = false
		pressing = false
		update()
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.Return
		then
			pressing = true
			update()
		end
	end)
	button.InputEnded:Connect(function()
		pressing = false
		update()
	end)
	button.Activated:Connect(function()
		if not button.Active then
			return
		end
		pressing = true
		update()
		task.delay(0.12, function()
			if button.Parent then
				pressing = false
				update()
			end
		end)
	end)
	button:GetPropertyChangedSignal("Active"):Connect(update)
end

function Motion.Close(overlay: GuiObject, panel: GuiObject?, finished: (() -> ())?)
	if overlay:GetAttribute("ForgeClosing") then
		return
	end
	overlay:SetAttribute("ForgeClosing", true)
	for _, child in overlay:GetDescendants() do
		if child:IsA("GuiButton") then
			child.Active = false
		end
		if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
			Motion.Tween(child, 0.16, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
			Motion.Tween(child, 0.16, { ImageTransparency = 1, BackgroundTransparency = 1 })
		elseif child:IsA("Frame") then
			Motion.Tween(child, 0.16, { BackgroundTransparency = 1 })
		elseif child:IsA("UIStroke") then
			Motion.Tween(child, 0.16, { Transparency = 1 })
		end
	end
	if panel and panel ~= overlay then
		Motion.Tween(panel, 0.16, { Position = panel.Position + UDim2.fromOffset(0, 12) })
	end
	Motion.Tween(overlay, 0.16, { BackgroundTransparency = 1 })
	local function finish()
		overlay:Destroy()
		if finished then
			finished()
		end
	end
	if reduced() then
		finish()
	else
		task.delay(0.16, finish)
	end
end

return Motion
