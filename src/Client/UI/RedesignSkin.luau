--!strict

-- Image artwork sits behind the existing native controls and captions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Factory = require(script.Parent.Factory)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Assets = require(ReplicatedStorage:WaitForChild("RedesignAssets"))
local Metrics = require(ReplicatedStorage:WaitForChild("RedesignMetrics"))
local Skin = {}
local PREFIX = { create = "Create", ["my-items"] = "MyItems", market = "Market",
	["avatar-lab"] = "AvatarLab", ["avatar-graphics"] = "AvatarGraphics", games = "Games",
	arcade = "Arcade", runway = "Runway", settings = "Settings" }
local DECORATION = { Decal = true, Gloss = true, Shade = true, DropShadow = true,
	ForgeScreenArt = true, RedesignArt = true, PopScale = true, InteractionOutline = true }

function Skin.Place(target: GuiObject, x: number, y: number, w: number, h: number)
	target.AnchorPoint = Vector2.zero
	target.Position = UDim2.fromOffset(x, y)
	target.Size = UDim2.fromOffset(w, h)
end

function Skin.Sized(target: any, size: number)
	target.TextSize = size
	target:SetAttribute("ForgeSized", true)
	local label = target:FindFirstChild("Label")
	if label then label:SetAttribute("ForgeSized", true) end
end

function Skin.Label(parent: Instance, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3?): TextLabel
	local label = Factory.Label(parent, text, UDim2.fromOffset(w, h), {
		Position = UDim2.fromOffset(x, y), TextSize = size, Color = color or Theme.Colors.Text,
		Font = Theme.Fonts.Bold, Wrapped = true,
	})
	label:SetAttribute("ForgeSized", true)
	return label
end

function Skin.Named(root: Instance, name: string): any
	return root:FindFirstChild(name, true)
end

function Skin.Direct(root: Instance, className: string): { any }
	local result = {}
	for _, child in root:GetChildren() do
		if child:IsA(className) and not DECORATION[child.Name] then table.insert(result, child) end
	end
	return result
end

function Skin.Metric(slug: string, name: string): any
	local screen = Metrics.screens[slug]
	if not screen then return nil end
	return screen[name] or screen[name .. "Surface"] or screen[name .. "Art"] or screen[name .. "Artwork"]
end

function Skin.AssetId(slug: string, name: string): number
	local prefix = PREFIX[slug]
	local metric = Skin.Metric(slug, name)
	local id = if metric then Assets[metric.assetKey] elseif prefix then Assets["V2_" .. prefix .. "_" .. name] else 0
	return if type(id) == "number" and id > 0 then id else 0
end

function Skin.Reset(target: GuiObject)
	local art = target:FindFirstChild("RedesignArt")
	if art then art:Destroy() end
	for _, child in target:GetChildren() do
		if child:IsA("GuiObject") and child:GetAttribute("ForgeV2Decoration") then child.Visible = false end
	end
	local decal = target:FindFirstChild("Decal")
	if decal then decal.Visible = not Theme.IsHighContrast end
	local loaded = decal and decal.IsLoaded and not Theme.IsHighContrast
	local alpha = target:GetAttribute("V2AuthoredAlpha")
	if alpha ~= nil then target.BackgroundTransparency = if loaded then 1 else alpha end
	local border = target:FindFirstChildOfClass("UIStroke")
	if border then border.Transparency = if loaded then 1 else (target:GetAttribute("V2AuthoredStroke") or 0) end
	for _, name in { "Gloss", "Shade" } do
		local overlay = target:FindFirstChild(name)
		if overlay then overlay.Visible = not loaded and not Theme.IsHighContrast end
	end
end

function Skin.Skin(target: GuiObject, slug: string, name: string): boolean
	if target:IsA("TextBox") or target:IsA("ViewportFrame") or target:IsA("ImageLabel") then return false end
	if Theme.IsHighContrast then
		local previous = target:FindFirstChild("RedesignArt")
		if previous then previous:Destroy() end
		local old = target:FindFirstChild("ForgeScreenArt")
		if old then old:Destroy() end
		local decal = target:FindFirstChild("Decal")
		if decal then decal.Visible = false end
		local authoredAlpha = target:GetAttribute("V2AuthoredAlpha")
		if authoredAlpha ~= nil then target.BackgroundTransparency = authoredAlpha end
		local border = target:FindFirstChildOfClass("UIStroke")
		if border then border.Transparency = target:GetAttribute("V2AuthoredStroke") or 0 end
		return false
	end
	local id = Skin.AssetId(slug, name)
	if id <= 0 then return false end
	local key = slug .. "/" .. name
	local previous = target:FindFirstChild("RedesignArt")
	if previous then
		if previous:GetAttribute("ForgeAssetKey") == key then return true end
		for _, child in target:GetChildren() do
			if child:IsA("GuiObject") and child:GetAttribute("ForgeV2Decoration") then child.Visible = false end
		end
		previous:Destroy()
	end
	local oldScreen = target:FindFirstChild("ForgeScreenArt")
	if oldScreen then oldScreen:Destroy() end
	local caption = Factory.LiftLabel(target)
	if caption and target:GetAttribute("ForgeSized") then caption:SetAttribute("ForgeSized", true) end
	local metric = Skin.Metric(slug, name)
	local source = if metric then metric.sourceRect else nil
	local rect = if metric then metric.rect else nil
	local dx, dy, sx, sy = 0, 0, 1, 1
	if source and rect then
		local x, y, w, h = source.x or source[1], source.y or source[2], source.w or source[3], source.h or source[4]
		local rx, ry, rw, rh = rect.x or rect[1], rect.y or rect[2], rect.w or rect[3], rect.h or rect[4]
		if w > 0 and h > 0 then dx, dy, sx, sy = (rx-x)/w, (ry-y)/h, rw/w, rh/h end
	end
	local art = Factory.New("ImageLabel", {
		Name = "RedesignArt", Image = "rbxassetid://" .. tostring(id), Active = false,
		Position = UDim2.fromScale(dx, dy), Size = UDim2.fromScale(sx, sy),
		BackgroundTransparency = 1, BorderSizePixel = 0, ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Stretch, ZIndex = target.ZIndex, Parent = target,
	})
	art:SetAttribute("ForgeAssetKey", key)
	local function raise(child: Instance)
		if child ~= art and child:IsA("GuiObject") and not DECORATION[child.Name] then
			(child :: GuiObject).ZIndex = math.max((child :: GuiObject).ZIndex, target.ZIndex + 1)
		end
	end
	for _, child in target:GetChildren() do raise(child) end
	local added = target.ChildAdded:Connect(raise)
	local oldDecal = target:FindFirstChild("Decal")
	local stroke = target:FindFirstChildOfClass("UIStroke")
	if target:GetAttribute("V2AuthoredAlpha") == nil then target:SetAttribute("V2AuthoredAlpha", target.BackgroundTransparency) end
	if stroke and target:GetAttribute("V2AuthoredStroke") == nil then target:SetAttribute("V2AuthoredStroke", stroke.Transparency) end
	local authoredAlpha = target:GetAttribute("V2AuthoredAlpha")
	local authoredStroke = target:GetAttribute("V2AuthoredStroke") or 0
	local function refresh()
		local loaded = art.IsLoaded and not Theme.IsHighContrast
		-- An unloaded image has no pixels to cover the fallback. Keeping it
		-- renderable prevents the engine from unloading an invisible texture
		-- while IsLoaded is the condition that would reveal it.
		art.ImageTransparency = if Theme.IsHighContrast then 1 else 0
		if oldDecal then oldDecal.Visible = not loaded end
		target.BackgroundTransparency = if loaded or (oldDecal and oldDecal.IsLoaded) then 1 else authoredAlpha
		if stroke then stroke.Transparency = if loaded then 1 else authoredStroke end
		for _, overlayName in { "Gloss", "Shade" } do
			local overlay = target:FindFirstChild(overlayName)
			if overlay then overlay.Visible = not loaded end
		end
	end
	local loadedConnection = art:GetPropertyChangedSignal("IsLoaded"):Connect(refresh)
	local decalConnection = if oldDecal then oldDecal:GetPropertyChangedSignal("IsLoaded"):Connect(refresh) else nil
	art.Destroying:Connect(function()
		added:Disconnect()
		loadedConnection:Disconnect()
		if decalConnection then decalConnection:Disconnect() end
	end)
	refresh()
	-- Request the texture while the native fallback remains visible.
	if type(ContentProvider.PreloadAsync) == "function" then
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync({ art }) end)
			if art.Parent then refresh() end
		end)
	end
	return true
end

function Skin.Decoration(parent: Instance, slug: string, name: string, x: number, y: number, w: number, h: number): Frame?
	local existing = parent:FindFirstChild("V2Decoration" .. name)
	if Skin.AssetId(slug, name) <= 0 or Theme.IsHighContrast then
		if existing and existing:IsA("GuiObject") then existing.Visible = false end
		return nil
	end
	if existing and existing:IsA("Frame") then
		existing.Visible = true
		Skin.Place(existing, x, y, w, h)
		Skin.Skin(existing, slug, name)
		return existing
	end
	local holder = Factory.New("Frame", {
		Name = "V2Decoration" .. name, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		ZIndex = if parent:IsA("GuiObject") then (parent :: GuiObject).ZIndex + 1 else 1, Parent = parent,
	})
	holder:SetAttribute("ForgeV2Decoration", true)
	Skin.Skin(holder, slug, name)
	return holder
end

return Skin
