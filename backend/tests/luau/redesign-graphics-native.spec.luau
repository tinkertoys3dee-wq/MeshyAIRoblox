-- Actual App:_RenderAvatarGraphics hierarchy, isolated in its own VM.
local checks = 0
local function check(value, message) checks += 1; assert(value, message) end
local function equal(actual, expected, message) check(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)) end
local function find(parent, name) local value = parent:FindFirstChild(name, true); assert(value, "Missing native node: " .. name); return value end
local function separated(first, second, gap, message)
    local ax, ay, bx, by = first.Position.X.Offset, first.Position.Y.Offset, second.Position.X.Offset, second.Position.Y.Offset
    check(ax + first.Size.X.Offset + gap <= bx or bx + second.Size.X.Offset + gap <= ax
        or ay + first.Size.Y.Offset + gap <= by or by + second.Size.Y.Offset + gap <= ay, message)
end
local function visibleAncestors(target, message)
    local current = target
    while current do if current:IsA("GuiObject") then check(current.Visible ~= false, message .. ": " .. current.Name) end; current = current.Parent end
end
fixtures.RedesignAssets = setmetatable({}, { __index = function() return 100 end })
fixtures.RedesignMetrics = { screens = {} }
cache.RedesignAssets, cache.RedesignMetrics = nil, nil
services.ContentProvider = services.ContentProvider or { PreloadAsync = function() end }
local originalNew = Instance.new
Instance.new = function(class) local value = originalNew(class); value.ZIndex = 1; value.IsLoaded = false; return value end
methods.CaptureFocus = function(self) self.focusCaptured = true end
local Factory = require("Factory")
local Tools = require("RedesignToolsLayouts")
local function text(parent, name, value)
    return Factory.Label(parent, value, UDim2.fromOffset(500, 40), { Name = name })
end
local function app(page)
    local instance = { content = Factory.New("Frame", { Name = "Content", Size = UDim2.fromOffset(1672, 941) }),
        activePage = page, compact = false, pageConnections = {}, scrollPositions = {},
        state = { profile = { settings = { simpleMode = true }, graphicOrder = {}, equippedItemIds = {} } },
        _BindButton = function() end,
        _Toast = function(self, kind, message) self.lastToast = message end,
        _RenderActivePage = function(self) self.renderCount = (self.renderCount or 0) + 1 end,
    }
    text(instance.content, "PageTitle", page); text(instance.content, "PageSubtitle", "Description")
    return instance
end
-- Execute the real App renderer supplied by check-luau.mjs. Keep these
-- regressions against its actual columns, source/view rows and callbacks.
local NativeGraphics = require("NativeGraphicsRenderer")
local nativeApp = app("Avatar Graphics")
nativeApp.graphicsTab, nativeApp.graphicMode, nativeApp.selectedAvatarView = "CREATE", "AVATAR", "BUST"
nativeApp.selectedImageQuality, nativeApp.selectedStylePreset, nativeApp.paymentMethod = "LOW", "AUTO", "ROBUX"
nativeApp.avatarGraphicPrompt, nativeApp.textImagePrompt = "Actual optional scene", "Actual required image prompt"
nativeApp.state.prices = { ImagePreviewLow = 37 }
nativeApp.state.profile.generationOrder, nativeApp.state.profile.generations = {}, {}
nativeApp._PageHeader = function(self, title, subtitle)
    find(self.content, "PageTitle").Text, find(self.content, "PageSubtitle").Text = title, subtitle
end
nativeApp._TextBox = function(self, parent, placeholder, size, position, multiline)
    return Factory.New("TextBox", { Name = "ActualGraphicPrompt", Parent = parent,
        PlaceholderText = placeholder, Size = size, Position = position, TextSize = 15,
        Text = "", TextEditable = true, BackgroundTransparency = 0,
    })
end
nativeApp._GlowField, nativeApp._TrackScroll = function() end, function() end
NativeGraphics._RenderAvatarGraphics(nativeApp)
local nativePage = find(nativeApp.content, "AvatarGraphicsScroll")
local nativeComposer = find(nativeApp.content, "GraphicComposer")
local nativeSourceRow, nativeInstructions, nativeCheckout, nativeAdvanced, nativeThumbnail = nil, {}, nil, nil, nil
for _, child in nativeComposer:GetChildren() do
    if child:IsA("Frame") then
        local buttons = {}
        for _, button in child:GetChildren() do if button:IsA("TextButton") then table.insert(buttons, button) end end
        if #buttons == 2 then nativeSourceRow = child end
    elseif child:IsA("TextLabel") then table.insert(nativeInstructions, child)
    elseif child:IsA("TextButton") and string.find(child.Text, "Advanced Mode", 1, true) then nativeAdvanced = child
    elseif child:IsA("TextButton") and string.find(child.Text, "Create", 1, true) then nativeCheckout = child
    elseif child:IsA("ImageLabel") and string.find(child.Image, "rbxthumb://", 1, true) then nativeThumbnail = child end
end
local nativeViews, nativePrompt = find(nativeComposer, "GraphicsChoiceOptions"), find(nativeComposer, "ActualGraphicPrompt")
equal(Tools.Apply(nativeApp), true, "Actual renderer hierarchy receives imported layout")
equal(nativeComposer.Parent, nativeApp.content, "Actual composer escapes the hidden scroll and both nested stacks")
check(not nativePage.Visible, "Emptied original scroll is hidden")
local nativeForm = find(nativeComposer, "V2DecorationGraphicsFormArt")
for _, control in { nativeSourceRow, nativeViews, nativePrompt, nativeCheckout, nativeAdvanced } do
    visibleAncestors(control, "Actual renderer controls have no hidden ancestors")
    check(control.ZIndex > nativeForm.ZIndex, "Actual renderer control clears opaque form artwork")
end
for _, label in nativeInstructions do
    if label:GetAttribute("ForgeV2Suppressed") then continue end
    visibleAncestors(label, "Actual renderer instruction is visible")
    check(label.ZIndex > nativeForm.ZIndex, "Actual renderer instruction clears opaque form artwork")
end
check(nativeThumbnail.ZIndex > find(nativeComposer, "V2DecorationGraphicsSourceThumbnailArt").ZIndex,
    "Actual player thumbnail clears its decorative blue well")
equal(nativeCheckout.Text, "Create · R$ 37", "Actual checkout price stays live")
local nativeIdle = find(nativeApp.content, "GraphicsIdleActivity")
check(nativeIdle.ZIndex > nativeComposer.ZIndex, "Actual idle strip clears composer background")
check(find(nativeApp.content, "V2DecorationGraphicsTitleSparkle1").ZIndex > nativeComposer.ZIndex,
    "Title decoration clears the composer surface")
local sources = {}
for _, child in nativeSourceRow:GetChildren() do if child:IsA("TextButton") then table.insert(sources, child) end end
sources[2].Activated:Fire()
equal(nativeApp.graphicMode, "TEXT", "Actual Source callback still selects Text")
-- Restore the original constructor state and render its real TEXT branch.
for _, child in nativeApp.content:GetChildren() do child:Destroy() end
text(nativeApp.content, "PageTitle", "Avatar Graphics")
text(nativeApp.content, "PageSubtitle", "Original description")
NativeGraphics._RenderAvatarGraphics(nativeApp)
local textComposer = find(nativeApp.content, "GraphicComposer")
local textSource, textCounter = nil, nil
for _, child in textComposer:GetChildren() do
    if child:IsA("Frame") then
        local n = 0
        for _, button in child:GetChildren() do if button:IsA("TextButton") then n += 1 end end
        if n == 2 then textSource = child end
    elseif child:IsA("TextLabel") and string.match(child.Text, "^%d+ / %d+") then textCounter = child end
end
local textPrompt = find(textComposer, "ActualGraphicPrompt")
Tools.Apply(nativeApp)
check(textPrompt.Size.X.Offset > 800 and textPrompt.Size.Y.Offset >= 160,
    "Actual Text branch uses the full composer width and a generous required prompt")
check(textPrompt.Position.Y.Offset < 250, "Text branch closes unused avatar/view gaps")
separated(textPrompt, textCounter, 4, "Actual Text counter remains outside its input")
local textButtons = {}
for _, child in textSource:GetChildren() do if child:IsA("TextButton") then table.insert(textButtons, child) end end
check(textButtons[2]:GetAttribute("ForgeSelected") and not textButtons[1]:GetAttribute("ForgeSelected"),
    "Actual Text source is visually selected and Avatar is inactive")
equal(find(textButtons[2], "V2SelectionMark").Transparency, .02, "Active Text source has visible emphasis border")
equal(textPrompt.Text, "Actual required image prompt", "Text branch retains actual player prompt")

return checks
