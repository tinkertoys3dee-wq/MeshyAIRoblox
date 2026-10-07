--!strict

-- Lay out existing live controls inside the approved SVG composition. Moving
-- a control preserves its callbacks, prompt value, price and moderation flow.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Factory = require(script.Parent.Factory)
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local HomeAssets = require(ReplicatedStorage:WaitForChild("HomeAssets"))
local ScreenAssets = require(ReplicatedStorage:WaitForChild("ScreenAssets"))
local ModernPageLayouts = require(script.Parent.ModernPageLayouts)
local RedesignCoreLayouts = require(script.Parent.RedesignCoreLayouts)
local RedesignToolsLayouts = require(script.Parent.RedesignToolsLayouts)
local RedesignGamesLayouts = require(script.Parent.RedesignGamesLayouts)
local ModernLayouts = {}

local function sized(control: any, size: number)
	control.TextSize = size
	control:SetAttribute("ForgeSized", true)
	local caption = control:FindFirstChild("Label")
	if caption and caption:IsA("TextLabel") then caption:SetAttribute("ForgeSized", true) end
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, fontSize: number, color: Color3?)
	local result = Factory.Label(parent, text, size, {
		Position = position, TextSize = fontSize, Color = color or Theme.Colors.Text,
		Font = Theme.Fonts.Bold, Wrapped = true,
	})
	result:SetAttribute("ForgeSized", true)
	return result
end

local function create(app: any)
	if app.compact or app.state.profile.settings.simpleMode == false or app.customUGCGuideRequested then return end
	local page = app.content:FindFirstChild("CreateScroll")
	local prompt = app.content:FindFirstChild("CustomUGCPrompt", true)
	local generate = app.content:FindFirstChild("CreatePersonalUGCButton", true)
	local ideas = app.content:FindFirstChild("IdeaSuggestions", true)
	if not page or not prompt or not generate or not ideas then return end
	local oldCard = prompt.Parent
	local title = app.content:FindFirstChild("PageTitle")
	local subtitle = app.content:FindFirstChild("PageSubtitle")
	if title then title.Text = "Create UGC" end
	if subtitle then subtitle.Text = "Describe it. Wear it." end
	local counter, safety, advanced, help
	for _, child in app.content:GetDescendants() do
		if child:IsA("TextButton") then
			if child.Text == "MORE CREATION OPTIONS" then advanced = child end
			if child.Text == "HOW IT WORKS" then help = child end
		elseif child:IsA("TextLabel") and child.Parent == oldCard then
			if string.match(child.Text, "^%d+ / %d+$") then counter = child end
			if child.Name == "CreateSafetyNote" or string.find(child.Text, "One custom 3D accessory", 1, true)
				or string.find(child.Text, "Your retry credit will be used", 1, true) then safety = child end
		end
	end
	local panel = Factory.ImageCard(app.content, UDim2.fromOffset(976, 516), UDim2.fromOffset(32, 99), "ModernPromptPanel")
	label(panel, "Tell us your idea", UDim2.fromOffset(34, 26), UDim2.new(1, -68, 0, 39), 29)
	label(panel, "Describe an accessory. We will help you bring it to life.", UDim2.fromOffset(34, 72), UDim2.new(1, -68, 0, 28), 20, Theme.Colors.TextMuted)
	prompt.Parent = panel
	prompt.Position = UDim2.fromOffset(34, 112)
	prompt.Size = UDim2.new(1, -68, 0, 123)
	sized(prompt, 22)
	if counter then
		counter.Parent = panel
		counter.Position = UDim2.new(1, -49, 0, 211)
		counter.Size = UDim2.fromOffset(120, 20)
		sized(counter, 15)
	end
	label(panel, "Need an idea? Tap one", UDim2.fromOffset(34, 258), UDim2.new(1, -68, 0, 28), 21)
	ideas.Parent = panel
	ideas.Position = UDim2.fromOffset(34, 302)
	ideas.Size = UDim2.new(1, -68, 0, 62)
	for _, chip in ideas:GetChildren() do
		if chip:IsA("TextButton") then
			chip.Size = UDim2.fromOffset(175, 52)
			sized(chip, 15)
			for _, icon in chip:GetChildren() do
				if icon:IsA("ImageLabel") and icon.Name ~= "Decal" then
					icon.Position = UDim2.fromOffset(9, 16)
				end
			end
		end
	end
	generate.Parent = panel
	generate.Position = UDim2.fromOffset(34, 382)
	generate.Size = UDim2.new(1, -68, 0, 76)
	sized(generate, 27)
	if safety then
		safety.Parent = panel
		safety.Position = UDim2.fromOffset(34, 469)
		safety.Size = UDim2.new(1, -68, 0, 35)
		safety.TextXAlignment = Enum.TextXAlignment.Center
		sized(safety, 16)
	end
	if advanced then
		advanced.Parent = app.content
		advanced.Text = "Advanced options"
		advanced.Position = UDim2.new(1, -221, 0, 15)
		advanced.Size = UDim2.fromOffset(190, 44)
		sized(advanced, 18)
		local mode = Factory.ImagePill(app.content, "Simple", Theme.Colors.Cyan, 170)
		mode.Position = UDim2.new(1, -405, 0, 15)
		mode.Size = UDim2.fromOffset(170, 44)
		sized(mode, 18)
		ModernPageLayouts.Skin(mode, "CreateSimpleMode")
	end
	if help then
		help.Position = UDim2.new(1, -199, 0, 621)
		help.Size = UDim2.fromOffset(168, 24)
		sized(help, 17)
	end
	local activity = page:FindFirstChild("Activity", true)
	local hasActivity = activity and activity.Visible
	local preview = Factory.ImageCard(app.content, UDim2.fromOffset(527, if hasActivity then 350 else 516), UDim2.fromOffset(1030, 99), "ModernCreatePreview")
	label(preview, "Your next creation", UDim2.fromOffset(30, 25), UDim2.new(1, -60, 0, 34), 27)
	Factory.New("ImageLabel", {
		Name = "CreationIllustration", Image = "rbxassetid://" .. tostring(if (ScreenAssets.CreatePreviewArtwork or 0) > 0 then ScreenAssets.CreatePreviewArtwork else HomeAssets.CreateArt),
		Position = UDim2.fromOffset(27, 76), Size = UDim2.new(1, -54, 1, -145),
		BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Parent = preview,
	})
	label(preview, "One idea. Something only you could make.", UDim2.new(0, 30, 1, -60), UDim2.new(1, -60, 0, 42), 19, Theme.Colors.TextMuted)
	if hasActivity then
		activity.Parent = app.content
		activity.Position = UDim2.fromOffset(1030, 466)
		activity.Size = UDim2.fromOffset(527, 149)
	end
	ModernPageLayouts.Skin(panel, "CreatePromptPanel")
	ModernPageLayouts.Skin(preview, "CreatePreviewPanel")
	ModernPageLayouts.Skin(generate, "CreateGenerateButton")
	local ideaIndex = 0
	local ideaNames = { "Dragon Wings", "Crystal Crown", "Neon Katana", "Steampunk Hat", "Fairy Wings" }
	for _, chip in ideas:GetChildren() do
		if chip:IsA("TextButton") then
			ideaIndex += 1
			if ModernPageLayouts.Skin(chip, "CreateIdea" .. tostring(ideaIndex)) then
				chip.Text = ideaNames[ideaIndex] or chip.Text
				for _, icon in chip:GetChildren() do
					if icon:IsA("ImageLabel") and icon.Name ~= "Decal" and icon.Name ~= "ForgeScreenArt" then icon.Visible = false end
				end
			end
		end
	end
	-- Retain hidden original containers: callbacks can still reference them.
	page.Visible = false
end

function ModernLayouts.Apply(app: any)
	app.redesignLayoutActive = false
	if app.compact and app.state and app.state.profile then
		if RedesignToolsLayouts.Compact(app) then return end
	end
	if not app.compact and app.activePage ~= "Home" and app.state and app.state.profile then
		app.content.Position = UDim2.new()
		app.content.Size = UDim2.fromOffset(1672, 941)
		local handled = RedesignCoreLayouts.Apply(app) or RedesignToolsLayouts.Apply(app) or RedesignGamesLayouts.Apply(app)
		if handled then
			app.redesignLayoutActive = true
			for _, child in app.content:GetChildren() do
				if child:IsA("TextButton") and (child.Text == "HOME" or string.find(child.Text, "←  HOME", 1, true)) then child.Visible = false end
				if child.Name == "FlourishDivider" then child.Visible = false end
			end
			if app.activePage == "Play" then
				local title, subtitle = app.content:FindFirstChild("PageTitle"), app.content:FindFirstChild("PageSubtitle")
				if title then title.Visible = false end
				if subtitle then subtitle.Visible = false end
			end
			return
		end
		local hasPreview = app.activePage == "Avatar Lab" or app.activePage == "Discover"
		app.content.Position = UDim2.fromOffset(46, 238)
		app.content.Size = UDim2.fromOffset(if hasPreview then 1087 else 1586, 645)
	end
	if app.activePage == "Create" then create(app) end
	ModernPageLayouts.Apply(app)
	if not app.compact and app.avatarPreviewPanel and (app.activePage == "Avatar Lab" or app.activePage == "Discover") then
		ModernPageLayouts.Skin(app.avatarPreviewPanel, if app.activePage == "Discover" then "MarketAvatarPanel" else "AvatarLabPreviewPanel")
	end
end

return ModernLayouts
