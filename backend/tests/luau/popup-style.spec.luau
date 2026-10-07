local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end
local Factory = require("Factory")
local PopupStyle = require("PopupStyle")
local Motion = require("Motion")
local previousInset = services.GuiService.GetGuiInset
services.GuiService.GetGuiInset = function() return Vector2.new(0, 58), Vector2.zero end
local overlay = Factory.New("Frame", { ZIndex = 240 })
local safe = PopupStyle.SafeArea(overlay)
check(safe.Position.Y.Offset == 58, "Popup safe area clears the Roblox toolbar")
check(safe.Size.Y.Offset == -58, "Popup safe area reserves toolbar space from its available height")
check(safe.Parent == overlay and not safe.Active, "Safe area preserves the original overlay without a new input shield")
services.GuiService.GetGuiInset = previousInset
overlay:Destroy()
local panel = Factory.New("Frame", { Name = "DetailsPanel", ZIndex = 241, Size = UDim2.fromOffset(580, 520) })
local heading = Factory.Label(panel, "Forge Tokens", UDim2.fromOffset(450, 40), { Name = "Caption" })
PopupStyle.Panel(panel, "Forge Tokens")
check(heading.Position.X.Offset == 68, "Popup title reserves the vector icon lane")
check(heading.Size.X.Offset == -132, "Popup title reserves the close control lane")
check(heading.ZIndex > panel.ZIndex, "Popup title stays above its native surface")
check(panel:FindFirstChild("PopupIcon").Image == "rbxassetid://" .. tostring(require("HomeAssets").TokenIcon), "Wallet uses the original SVG-derived token icon")
check(panel:FindFirstChild("PopupHeaderRule") ~= nil, "Popup header has a quiet structural divider")
check(panel.BackgroundColor3.R == 1 and panel.BackgroundColor3.G == 1 and panel.BackgroundColor3.B == 1, "Normal panel base preserves the authored gradient colors")
PopupStyle.Panel(panel, "Forge Tokens")
local icons = 0
for _, child in panel:GetChildren() do if child.Name == "PopupIcon" then icons += 1 end end
check(icons == 1, "Reapplying panel styling does not duplicate artwork")
local action = Factory.New("TextButton", {
	Name = "DetailAction", Text = "Open Token Lounge", Size = UDim2.fromOffset(530, 72),
	ZIndex = 243, Active = true, Selectable = true, Parent = panel,
})
local activated = 0
action.Activated:Connect(function() activated += 1 end)
PopupStyle.Action(action, "Open Token Lounge", { kind = "primary", icon = "TokenIcon", detail = "Earn tokens while you hang out" })
local caption = action:FindFirstChild("Caption")
check(caption and caption:IsA("TextLabel"), "Action keeps a native editable Caption")
check(caption.Position.X.Offset == 66, "Action reserves a separate icon lane")
check(caption.Size.X.Offset == -114, "Action caption reserves the chevron lane")
check(caption.ZIndex > action:FindFirstChild("PopupInteractionWash").ZIndex, "Hover tint cannot obscure the caption")
check(action:FindFirstChild("ActionDetail").Position.Y.Offset >= caption.Position.Y.Offset + caption.Size.Y.Offset, "Action detail sits below the title without overlap")
check(action.Selectable and action.Active, "Styling preserves keyboard and pointer interaction")
action.Activated:Fire()
check(activated == 1, "The original action callback remains connected exactly once")
action.MouseEnter:Fire()
check(action:FindFirstChild("PopupInteractionWash").BackgroundTransparency == 0.94, "Hover feedback lights the surface without changing layout")
action.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Unknown })
check(action:FindFirstChild("PopupInteractionWash").BackgroundTransparency == 0.86, "Pointer press has a distinct inset feedback state")
action.InputEnded:Fire()
action.MouseLeave:Fire()
check(action:FindFirstChild("PopupInteractionWash").BackgroundTransparency == 1, "Leaving the action restores its authored surface")
PopupStyle.Action(action, "Buy Tokens", { kind = "gold", icon = "TokenIcon" })
check(action:FindFirstChild("Caption") == caption, "Restyling keeps references to the live caption intact")
check(action:FindFirstChild("ActionDetail") == nil, "Restyling clears the old description")
check(caption.Position.Y.Offset == 0 and caption.Size.Y.Scale == 1, "Description-free action centers its caption vertically")
icons = 0
for _, child in action:GetDescendants() do if child.Name == "PopupIcon" then icons += 1 end end
check(icons == 1, "Restyling does not accumulate icon layers")
PopupStyle.Action(action, "Avatar Lab  ›", { icon = "TutorialIcon" })
check(action.Text == "Avatar Lab  ›", "Action keeps the original semantic text for navigation lookup")
check(caption.Text == "Avatar Lab", "Rendered caption uses the reserved arrow lane instead of a duplicate chevron")
action.Active = false
action.MouseEnter:Fire()
check(action:FindFirstChild("PopupInteractionWash").BackgroundTransparency == 1, "Disabled actions do not advertise hover feedback")
action.Active = true
Motion.Configure(function() return true end)
action.MouseLeave:Fire()
action.MouseEnter:Fire()
check(action:FindFirstChild("PopupInteractionWash").BackgroundTransparency == 0.94, "Reduced motion preserves immediate useful interaction feedback")
fixtures.Theme.IsHighContrast = true
PopupStyle.Panel(panel, "Forge Tokens")
PopupStyle.Action(action, "Buy Tokens", { kind = "gold", icon = "TokenIcon" })
check(panel:FindFirstChildOfClass("UIGradient").Enabled == false, "High contrast replaces decorative panel gradients with a plain accessible surface")
check(action:FindFirstChildOfClass("UIGradient").Enabled == false, "High contrast uses a solid action surface")
check(action:FindFirstChild("PopupBorder").Transparency == 0, "High contrast preserves a visible action boundary")
check(action:FindFirstChild("PopupActionShadow").Visible == false, "High contrast suppresses unnecessary shadows")
local captionColor, accessibleColor = action:FindFirstChild("Caption").TextColor3, fixtures.Theme.Colors.Text
check(captionColor.R == accessibleColor.R and captionColor.G == accessibleColor.G and captionColor.B == accessibleColor.B, "High contrast uses its native readable caption color")
check(action.Selectable and action.Active, "Accessibility styling preserves live control semantics")
action:Destroy()
panel:Destroy()
Motion.Configure(function() return false end)
fixtures.Theme.IsHighContrast = false
return checks
