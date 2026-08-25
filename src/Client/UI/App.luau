--!strict

local AdService = game:GetService("AdService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Achievements = require(ReplicatedStorage:WaitForChild("Achievements"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local GamesHub = require(script.Parent.GamesHub)
local SoundController = require(script.Parent.SoundController)
local ViewportController = require(script.Parent.ViewportController)

local Colors = Theme.Colors
local player = Players.LocalPlayer
local REMOTE_WAIT_SECONDS = 15

-- Warm-to-cool spread for the ambient ember background (see
-- App:_SetAmbientMotion) so it reads as forge sparks rather than a single
-- flat color drifting upward.
local EMBER_COLORS = { Colors.Gold, Colors.Rose, Colors.Cyan }
local EMBER_COUNT = 10

local App = {}
App.__index = App

local function waitForRemoteFolder(): Folder?
	local instance = ReplicatedStorage:WaitForChild(Network.FolderName, REMOTE_WAIT_SECONDS)
	if instance and instance:IsA("Folder") then
		return instance
	end
	return nil
end

local function waitForRequestRemote(folder: Folder): RemoteFunction?
	local instance = folder:WaitForChild(Network.RequestName, REMOTE_WAIT_SECONDS)
	if instance and instance:IsA("RemoteFunction") then
		return instance
	end
	return nil
end

local function waitForPushRemote(folder: Folder): RemoteEvent?
	local instance = folder:WaitForChild(Network.PushName, REMOTE_WAIT_SECONDS)
	if instance and instance:IsA("RemoteEvent") then
		return instance
	end
	return nil
end

local ERROR_MESSAGES = {
	SERVER_ERROR = "The Roblox server hit an unexpected error. Check Server Output for the logged cause, then retry.",
	SERVER_STARTING = "The Forge server is still starting. Wait a moment and try again.",
	PROFILE_UNAVAILABLE = "Your creator profile is still loading. Try again in a moment.",
	PROFILE_MUTATION_FAILED = "Roblox could not update your saved profile safely.",
	INVALID_TRANSFORM = "That fit is outside the supported position, rotation, or scale range.",
	PROMPT_REQUIRED = "Describe the accessory you want to make.",
	PROMPT_TOO_SHORT = "Add a little more detail to your prompt.",
	PROMPT_TOO_LONG = "Keep your prompt under 500 characters.",
	PROMPT_BLOCKED = "That idea could not pass Roblox text filtering. Try a different description.",
	CONTENT_REJECTED = "That idea did not pass the generator safety check. Nothing was purchased.",
	MODERATION_UNAVAILABLE = "The safety check is temporarily unavailable. Nothing was purchased; try again shortly.",
	FILTER_UNAVAILABLE = "Roblox filtering is temporarily unavailable. Nothing was sent to the generator.",
	QUEUE_FULL = "Your creation queue is full. Finish a current job or join the group for one extra slot.",
	PRODUCT_ID_NOT_CONFIGURED = "This purchase is not configured yet. Add the developer product ID in Config.luau.",
	BACKEND_NOT_CONFIGURED = "The generation backend is not connected yet.",
	CONTENT_SHARING_DISABLED = "Roblox policy settings do not allow shared content for this account.",
	COMMERCE_NOT_ALLOWED = "Purchases are unavailable for this account.",
	PLUS_REQUIRED = "Roblox Plus is required to buy another creator's model.",
	LISTING_UNAVAILABLE = "This creator is not currently selling that model.",
	ITEM_NOT_FOUND = "That model is no longer available. Refresh the page and try again.",
	ITEM_NOT_SHAREABLE = "Only original creations can be shared publicly.",
	ITEM_NOT_LISTABLE = "Only an original creation can be listed for sale.",
	ITEM_NOT_PUBLISHABLE = "This model cannot be published as a wearable.",
	MARKETPLACE_UNAVAILABLE = "The creator marketplace could not update. Your saved item is unchanged; try again.",
	PRICE_OUT_OF_RANGE = "Choose a sale price from R$ 10 to R$ 500.",
	CREATION_TOKEN_NOT_CONFIGURED = "Add the Avatar Creation Token for this accessory type in Config.luau.",
	MODEL_UNAVAILABLE = "The model asset is not available yet.",
	ASSET_STILL_PROCESSING = "Roblox is still processing this new model. Wait a few seconds and try again.",
	ASSET_LOAD_FAILED = "Roblox could not load this model. Check that the uploaded asset belongs to this experience's creator.",
	MESH_NOT_FOUND = "The uploaded model does not contain a usable MeshPart.",
	ACCESSORY_PREPARATION_FAILED = "Roblox could not turn this model into an accessory. The server log now includes the exact failure.",
	EDITABLE_ASSET_FAILED = "Roblox could not prepare this mesh for wearable publishing. Check EditableMesh permissions and memory limits.",
	EQUIP_FAILED = "Roblox could not attach this model to your avatar. Try another fit region or rejoin.",
	CHARACTER_UNAVAILABLE = "Your avatar is still loading. Try again in a moment.",
	PLAYER_GUI_UNAVAILABLE = "Your private preview cache is unavailable. Rejoin and try again.",
	AVATAR_CREATION_UNAVAILABLE = "Roblox could not open the wearable publishing prompt. Check the creation token and asset permissions.",
	AVATAR_CREATION_REJECTED = "Wearable publishing was cancelled or Roblox rejected the asset.",
	AVATAR_CREATION_BAD_RESPONSE = "Roblox completed the prompt but did not return a valid wearable asset ID.",
	SAVE_FAILED = "Roblox could not safely save this transaction. Nothing new was prompted; try again.",
	GRANT_FAILED = "The purchase benefit could not be prepared. Try again in a moment.",
	PURCHASE_ALREADY_PENDING = "Finish or close the current Roblox purchase prompt before starting another.",
	PURCHASE_PROMPT_FAILED = "Roblox could not open the purchase prompt.",
	GAME_PASS_ID_NOT_CONFIGURED = "Add the Custom Image Upload game pass ID in Config.luau.",
	GAME_PASS_LOOKUP_FAILED = "Roblox could not verify that game pass right now. Try again shortly.",
	GAME_PASS_PROMPT_FAILED = "Roblox could not open the game pass purchase prompt.",
	CUSTOM_IMAGE_PASS_REQUIRED = "Unlock Custom Image Upload before submitting a reference.",
	INVALID_IMAGE_ASSET_ID = "Enter the numeric ID of your Roblox Image or Decal.",
	IMAGE_ASSET_UNAVAILABLE = "Roblox could not find that image asset, or it is still under moderation.",
	IMAGE_ASSET_TYPE_REQUIRED = "That ID is not a Roblox Image or Decal asset.",
	IMAGE_NOT_OWNED = "Use an Image or Decal uploaded by your account or the configured creator group.",
	ROBLOX_IMAGE_NOT_READY = "That Roblox image is still processing or unavailable. Try again after moderation finishes.",
	ROBLOX_IMAGE_UNAVAILABLE = "Roblox could not provide that reference image right now.",
	REFERENCE_IMAGE_TOO_SMALL = "That reference image is too small. Upload an image at least 128×128.",
	REFERENCE_IMAGE_INVALID = "That Roblox asset is not a valid still image.",
	INVALID_STYLE_PRESET = "Choose one of the available visual styles.",
	INVALID_DETAIL_LEVEL = "Choose one of the available detail levels.",
	INVALID_ASSET_TYPE = "Choose a supported accessory category.",
	CATALOG_ITEM_UNAVAILABLE = "That catalog item is unavailable or does not match this accessory category.",
	TRY_ON_FAILED = "Roblox could not apply that item to your avatar. Try another item.",
	AVATAR_UNAVAILABLE = "Roblox could not restore your avatar right now.",
	TRANSFER_PROMPT_FAILED = "Roblox could not open the Plus transfer prompt.",
	TRANSFER_ALREADY_PENDING = "Finish the current creator transfer before starting another.",
	SUBSCRIPTION_NOT_ALLOWED = "Roblox Plus subscriptions are unavailable for this account.",
	SUBSCRIPTION_PROMPT_FAILED = "Roblox could not open the Plus subscription prompt.",
	RATE_LIMITED = "Slow down for a moment, then try again.",
	UGC_VALIDATION_FAILED = "Roblox validation did not accept this fit. Adjust it and try again.",
	ITEM_NOT_EQUIPPED = "That item is not currently equipped.",
	INVALID_IMAGE_QUALITY = "Choose one of the available reference image quality tiers.",
	FIT_PRESET_LIMIT_REACHED = "You have saved the maximum number of fit presets. Delete one to save another.",
	FIT_PRESET_NOT_FOUND = "That saved fit preset no longer exists.",
	INSUFFICIENT_TOKENS = "You don't have enough Forge Tokens for that yet. Watch a rewarded ad to earn more.",
	INSUFFICIENT_AD_TOKENS = "Generations need ad-earned tokens specifically — free tokens (achievements, streaks) only cover the Priority Pass. Watch a rewarded ad to earn more.",
	TOKENS_NOT_ACCEPTED = "Forge Tokens can't pay for that.",
	AD_UNAVAILABLE = "No rewarded ad is available right now. Try again in a few minutes.",
	AD_NOT_COMPLETED = "The ad was closed before it finished, so no tokens were earned.",
}

local CATALOG_TYPES = {
	Hat = Enum.AvatarAssetType.Hat,
	HairAccessory = Enum.AvatarAssetType.HairAccessory,
	FaceAccessory = Enum.AvatarAssetType.FaceAccessory,
	NeckAccessory = Enum.AvatarAssetType.NeckAccessory,
	ShoulderAccessory = Enum.AvatarAssetType.ShoulderAccessory,
	FrontAccessory = Enum.AvatarAssetType.FrontAccessory,
	BackAccessory = Enum.AvatarAssetType.BackAccessory,
	WaistAccessory = Enum.AvatarAssetType.WaistAccessory,
}

local ACCESSORY_LABELS = {
	Hat = "Hat",
	HairAccessory = "Hair",
	FaceAccessory = "Face",
	NeckAccessory = "Neck",
	ShoulderAccessory = "Shoulder",
	FrontAccessory = "Front",
	BackAccessory = "Back",
	WaistAccessory = "Waist",
}

local CATALOG_SORT_TYPES = {
	Relevance = Enum.CatalogSortType.Relevance,
	Bestselling = Enum.CatalogSortType.Bestselling,
	MostFavorited = Enum.CatalogSortType.MostFavorited,
	PriceLowToHigh = Enum.CatalogSortType.PriceLowToHigh,
	PriceHighToLow = Enum.CatalogSortType.PriceHighToLow,
	RecentlyCreated = Enum.CatalogSortType.RecentlyCreated,
}

local CATALOG_SORT_ORDER = {
	"Relevance",
	"Bestselling",
	"MostFavorited",
	"PriceLowToHigh",
	"PriceHighToLow",
	"RecentlyCreated",
}

local CATALOG_SORT_LABELS = {
	Relevance = "Relevance",
	Bestselling = "Bestselling",
	MostFavorited = "Most favorited",
	PriceLowToHigh = "Price ↑",
	PriceHighToLow = "Price ↓",
	RecentlyCreated = "Newest",
}

local function thumbnail(assetId: any, size: number?): string
	local id = tonumber(assetId) or 0
	if id <= 0 then
		return ""
	end
	local pixels = size or 420
	return string.format("rbxthumb://type=Asset&id=%d&w=%d&h=%d", id, pixels, pixels)
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, nested in value :: any do
		(result :: any)[deepCopy(key)] = deepCopy(nested)
	end
	return result :: T
end

local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	while true do
		local replaced, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return text
end

-- Products with a real per-use provider cost, priced steeply enough in
-- tokens that even the worst measured ad still leaves Forge ahead — see
-- CommerceService.tokenPriceFor, the source of truth this mirrors.
local GENERATION_TOKEN_PRODUCTS = {
	DirectGeneration = true,
	ImagePreviewLow = true,
	ImagePreviewMedium = true,
	ImagePreviewHigh = true,
	ImageConversion = true,
}

-- Display-only mirror of CommerceService:BeginIntentWithTokens's math; the
-- server always recomputes and enforces this, this is purely so the button
-- can show the right token price before the click round-trips.
local function tokenPrice(robuxPrice: number, productKey: string?): number
	if productKey and GENERATION_TOKEN_PRODUCTS[productKey] then
		return math.ceil(robuxPrice * Config.Ads.TokenPurchaseMarkup / Config.Ads.WorstCaseAdRevenuePerAd)
	end
	return math.ceil(robuxPrice * Config.Ads.TokenPurchaseMarkup)
end

-- Display-only mirror of AdRewardService's daily-reset math, used only to
-- seed the "watched today" stat from the bootstrapped profile; the server
-- response after each watch is the value actually trusted afterward. This is
-- a running count, not a countdown -- there is no daily cap (every completed
-- ad is real, positive revenue, see Config.Ads.WorstCaseAdRevenuePerAd).
local function watchesTodayFromProfile(profile: { [string]: any }): number
	local watch = profile.adWatch or { day = 0, count = 0 }
	local today = math.floor(os.time() / 86400)
	return if watch.day == today then watch.count else 0
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		child:Destroy()
	end
end

function App.new()
	local self = setmetatable({
		sounds = SoundController.new(),
		state = nil :: { [string]: any }?,
		activePage = "Create",
		selectedMethod = "TEXT_TO_3D",
		selectedAccessoryType = "Hat",
		selectedStylePreset = "AUTO",
		selectedDetailLevel = "BALANCED",
		selectedImageQuality = "LOW",
		customImageAssetId = "",
		draftPrompt = "",
		selectedItemId = nil :: string?,
		fitDrafts = {} :: { [string]: { [string]: any } },
		pageConnections = {} :: { RBXScriptConnection },
		marketplaceItems = nil :: { any }?,
		marketplaceQuery = "",
		marketplaceSearchBy = "NAME",
		marketplaceSortBy = "TRENDING",
		catalogResults = nil :: { any }?,
		catalogSearching = false,
		catalogAccess = nil :: boolean?,
		catalogAccessPrompting = false,
		catalogError = nil :: string?,
		catalogType = "Hat",
		catalogQuery = "",
		catalogSortType = "Relevance",
		catalogCreatorName = "",
		catalogMinPrice = "",
		catalogMaxPrice = "",
		catalogFiltersExpanded = false,
		usePriority = false,
		paymentMethod = "ROBUX",
		adAvailable = nil :: boolean?,
		adAvailabilityChecking = false,
		adWatchesToday = nil :: number?,
		pageVersion = 0,
		toastVersion = 0,
		queuedSoundIds = {} :: { [string]: boolean },
		navButtons = {} :: { [string]: TextButton },
		activeViewport = nil :: any,
		ambientMotionEnabled = false,
		ambientBlobs = {} :: { { instance: Frame, restPosition: UDim2 } },
		ambientEmbers = {} :: { Frame },
		-- Set by GamesHub while the Arcade modal is open (nil otherwise) so
		-- the Settings page's UIScale chips can keep it live-scaled too --
		-- see the "Make Arcade modal inherit UIScale" fix in GamesHub.luau.
		arcadeUiScale = nil :: UIScale?,
	}, App)
	self:_BuildChrome()
	AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(result)
		self.catalogAccessPrompting = false
		self.catalogAccess = result == Enum.AvatarPromptResult.Success
		if self.catalogAccess then
			self.catalogError = nil
			self.catalogResults = nil
			self:_SearchCatalog(self.catalogQuery)
		else
			self.catalogError = "Catalog access was not approved. You can enable it whenever you are ready."
			if self.activePage == "Avatar Lab" then
				self:_RenderActivePage()
			end
		end
	end)
	-- Fires once the local player closes Roblox's native invite dialog.
	-- recipientIds only tells us invites were sent, never accepted (Roblox
	-- exposes no accepted-invite signal), so the small token reward is for
	-- taking the action, reported once to the server here.
	SocialService.GameInvitePromptClosed:Connect(function(promptedPlayer: Player, recipientIds: { any })
		if promptedPlayer ~= player or #recipientIds == 0 then
			return
		end
		task.spawn(function()
			self:_Invoke(Network.Actions.ReportInviteSent, { recipientCount = #recipientIds })
		end)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player?)
		if triggeringPlayer and triggeringPlayer ~= player then
			return
		end
		local page = prompt:GetAttribute("ForgePage")
		if type(page) == "string" then
			self:_SetStudioOpen(true)
			if self.state then
				self:_OpenPage(page)
			else
				self.activePage = page
			end
		end
	end)
	player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(function()
		if self.state then
			self:_RefreshBootstrap()
		end
	end)
	-- Keyboard/gamepad accessibility: Tab, or a gamepad's Y button, hands
	-- focus to the nav rail so the whole studio becomes reachable without a
	-- mouse. Roblox's default GuiObject/SelectionOrder traversal takes over
	-- from there once something is selected.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.shell.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonY then
			if not GuiService.SelectedObject or not GuiService.SelectedObject:IsDescendantOf(self.shell) then
				local target = self.navButtons[self.activePage] or self.navButtons["Create"]
				if target then
					GuiService.SelectedObject = target
				end
			end
		end
	end)
	self:_Bootstrap()
	return self
end

function App:_BuildChrome()
	local gui = Factory.New("ScreenGui", {
		Name = "ForgeUGC",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	self.gui = gui

	local backdrop = Factory.New("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})

	local shell = Factory.New("Frame", {
		Name = "Shell",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.88),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = backdrop,
	})
	Factory.Corner(shell, 22)
	Factory.Stroke(shell, Color3.fromRGB(101, 113, 170), 0.35, 1.2)
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(1440, 860),
		MinSize = Vector2.new(330, 450),
		Parent = shell,
	})
	self.shell = shell
	-- Accessibility: a single UIScale scales the entire studio (text, controls,
	-- and touch targets together) from the Settings page, without every
	-- literal TextSize/UDim needing its own scale-aware rewrite.
	self.uiScaleInstance = Factory.New("UIScale", {
		Scale = if self.state then tonumber(self.state.profile.settings.uiScale) or 1 else 1,
		Parent = shell,
	})

	-- Both base-view launchers (Studio and Arcade) share this shape: a
	-- shadow for lift, a gradient-filled pill with a gloss highlight, an
	-- icon badge, and a title/subtitle pair -- the same detailed language
	-- the Arcade's own tiles and buttons use, so the entry points into the
	-- Studio don't look noticeably plainer than what's inside it.
	local function buildLauncher(
		icon: string,
		title: string,
		subtitle: string,
		bottomOffset: number,
		accentColor: Color3,
		lightColor: Color3,
		darkColor: Color3,
		foreground: Color3
	): TextButton
		local shadow = Factory.New("Frame", {
			Name = "Shadow",
			Size = UDim2.fromOffset(240, 60),
			Position = UDim2.new(0, 18, 1, bottomOffset + 5),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 29,
			Parent = gui,
		})
		Factory.Corner(shadow, 18)
		local button = Factory.New("TextButton", {
			Size = UDim2.fromOffset(240, 60),
			Position = UDim2.new(0, 18, 1, bottomOffset),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Visible = false,
			ZIndex = 30,
			Parent = gui,
		})
		Factory.Corner(button, 18)
		Factory.Stroke(button, Colors.Ink, 0.4, 1.5)
		Factory.Gradient(button, { lightColor, darkColor }, 130)
		local gloss = Factory.New("Frame", {
			Name = "Gloss",
			Size = UDim2.new(1, -2, 0, 20),
			Position = UDim2.fromOffset(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = button,
		})
		Factory.Corner(gloss, 17)
		local badge = Factory.New("Frame", {
			Name = "IconBadge",
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = button,
		})
		Factory.Corner(badge, 13)
		Factory.Label(badge, icon, UDim2.fromScale(1, 1), {
			TextSize = 20,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 32,
		})
		Factory.Label(button, title, UDim2.new(1, -64, 0, 22), {
			Position = UDim2.fromOffset(58, 8),
			Font = Theme.Fonts.Black,
			TextSize = 15,
			Color = foreground,
			AlignX = Enum.TextXAlignment.Left,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 31,
		})
		Factory.Label(button, subtitle, UDim2.new(1, -64, 0, 16), {
			Position = UDim2.fromOffset(58, 30),
			Font = Theme.Fonts.Medium,
			TextSize = 10,
			Color = foreground,
			Transparency = 0.25,
			AlignX = Enum.TextXAlignment.Left,
			Truncate = Enum.TextTruncate.AtEnd,
			ZIndex = 31,
		})
		-- The shadow is a sibling, not a child (a child would render on top
		-- of the button, not behind it), so it has no automatic link to the
		-- button's own Visible toggling elsewhere (_SetStudioOpen) -- this
		-- keeps the two in sync without that code needing to know the
		-- shadow exists.
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			shadow.Visible = button.Visible
		end)
		return button
	end

	local launcher = buildLauncher(
		"✦",
		"Open Forge Studio",
		"Create & customize",
		-78,
		Colors.Violet,
		Color3.fromRGB(150, 120, 255),
		Color3.fromRGB(96, 64, 220),
		Colors.Text
	)
	launcher.Name = "StudioLauncher"
	self:_BindButton(launcher)
	launcher.Activated:Connect(function()
		self:_SetStudioOpen(true)
	end)
	self.launcher = launcher

	-- A separate entry point from the Forge Studio launcher above, not a
	-- variant of it: this opens the Arcade (see GamesHub), which has nothing
	-- to do with creation/fitting/marketplace. Same visibility rule as the
	-- Forge launcher (only shown on the closed/idle base view) since it's a
	-- peer of it, not something nested inside the studio.
	local arcadeLauncher = buildLauncher(
		"🎮",
		"Arcade",
		"3 mini-games · weekly prizes",
		-146,
		Colors.Mint,
		Color3.fromRGB(160, 255, 215),
		Color3.fromRGB(46, 196, 143),
		Colors.Ink
	)
	arcadeLauncher.Name = "ArcadeLauncher"
	self:_BindButton(arcadeLauncher)
	arcadeLauncher.Activated:Connect(function()
		GamesHub.Show(self)
	end)
	self.arcadeLauncher = arcadeLauncher

	local topbar = Factory.New("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, 78),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = shell,
	})
	Factory.New("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	local logoMark = Factory.New("Frame", {
		Size = UDim2.fromOffset(43, 43),
		Position = UDim2.fromOffset(20, 17),
		BackgroundColor3 = Colors.Violet,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	Factory.Corner(logoMark, 13)
	Factory.Gradient(logoMark, { Colors.Rose, Colors.Violet, Colors.Cyan }, 35)
	Factory.Label(logoMark, "F", UDim2.fromScale(1, 1), {
		Font = Theme.Fonts.Black,
		TextSize = 24,
		AlignX = Enum.TextXAlignment.Center,
	})
	Factory.Label(topbar, Config.Brand.Name, UDim2.fromOffset(170, 29), {
		Position = UDim2.fromOffset(76, 14),
		Font = Theme.Fonts.Black,
		TextSize = 19,
	})
	Factory.Label(topbar, Config.Brand.Tagline, UDim2.fromOffset(250, 22), {
		Position = UDim2.fromOffset(76, 41),
		Color = Colors.TextMuted,
		TextSize = 12,
	})
	local statusArea = Factory.New("Frame", {
		Name = "StatusArea",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -68, 0.5, 0),
		Size = UDim2.fromOffset(430, 48),
		BackgroundTransparency = 1,
		Parent = topbar,
	})
	Factory.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = statusArea,
	})
	self.statusArea = statusArea
	local closeStudio = Factory.Button(topbar, "×", UDim2.fromOffset(40, 40), UDim2.new(1, -54, 0.5, -20), nil)
	closeStudio.Name = "CloseStudio"
	closeStudio.TextSize = 21
	closeStudio.ZIndex = 4
	self:_BindButton(closeStudio)
	closeStudio.Activated:Connect(function()
		self:_SetStudioOpen(false)
	end)

	local nav = Factory.New("Frame", {
		Name = "Navigation",
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(0.145, 0, 1, -78),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = shell,
	})
	self.nav = nav
	Factory.New("Frame", {
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(1, -1, 0, 0),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = nav,
	})
	local navStack = Factory.New("Frame", {
		Position = UDim2.fromOffset(12, 18),
		Size = UDim2.new(1, -24, 0, 330),
		BackgroundTransparency = 1,
		Parent = nav,
	})
	Factory.List(navStack, Enum.FillDirection.Vertical, 9)
	self.navStack = navStack
	-- A single persistent bar that slides to whichever nav button is active,
	-- rather than every button just flatly recoloring on its own -- sits
	-- flush against `nav`'s own left edge (not inside navStack) so it isn't
	-- competing with any one button's own background for room.
	local navIndicator = Factory.New("Frame", {
		Name = "ActiveIndicator",
		Size = UDim2.fromOffset(4, 48),
		Position = UDim2.fromOffset(0, 18),
		BackgroundColor3 = Colors.Cyan,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = nav,
	})
	Factory.Corner(navIndicator, 2)
	self.navIndicator = navIndicator

	for index, page in { "Create", "My Studio", "Discover", "Avatar Lab", "Settings" } do
		local symbols = { "✦", "◈", "◎", "◇", "⚙" }
		local button = Factory.Button(navStack, symbols[index] .. "   " .. page, UDim2.new(1, 0, 0, 48), nil, nil)
		button.Name = page
		button.LayoutOrder = index
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Selectable = true
		Factory.Padding(button, 15, 0)
		self.sounds:Bind(button)
		button.Activated:Connect(function()
			self:_OpenPage(page)
		end)
		self.navButtons[page] = button
	end
	local tip = Factory.Card(nav, UDim2.new(1, -24, 0, 142), UDim2.new(0, 12, 1, -160), "GroupTip")
	Factory.Label(tip, "GROUP BOOST", UDim2.new(1, -24, 0, 22), {
		Position = UDim2.fromOffset(12, 12),
		Color = Colors.Mint,
		Font = Theme.Fonts.Bold,
		TextSize = 11,
	})
	Factory.Label(tip, "Join the creator group for priority scheduling and +1 queue slot.", UDim2.new(1, -24, 0, 62), {
		Position = UDim2.fromOffset(12, 38),
		Color = Colors.TextMuted,
		TextSize = 12,
		Wrapped = true,
		AlignY = Enum.TextYAlignment.Top,
	})
	Factory.Label(tip, "10% queue boost", UDim2.new(1, -24, 0, 25), {
		Position = UDim2.fromOffset(12, 106),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
	})

	local content = Factory.New("Frame", {
		Name = "Content",
		Position = UDim2.new(0.145, 0, 0, 78),
		Size = UDim2.new(0.855, 0, 1, -78),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = shell,
	})
	self.content = content

	-- A persistent home for ambient background decoration -- a sibling of
	-- Content rather than a child of it, so `clear(self.content)` inside
	-- _RenderActivePage (called on every page swap, and every ~4s of
	-- generation progress while "Create" is open) never touches it. Built
	-- once here; App:_SetAmbientMotion (called once bootstrap knows the
	-- reduce-motion setting, and again whenever that setting changes) is
	-- what actually starts or stops the motion.
	local backgroundLayer = Factory.New("Frame", {
		Name = "AmbientBackground",
		Position = content.Position,
		Size = content.Size,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 0,
		Parent = shell,
	})
	self.backgroundLayer = backgroundLayer
	self.ambientBlobs = {}
	self.ambientEmbers = {}
	for _, spec in
		{
			{ diameter = 560, position = UDim2.new(1, -160, 0, -220), color = Colors.Cyan, transparency = 0.93 },
			{ diameter = 460, position = UDim2.new(0, -220, 1, -160), color = Colors.Violet, transparency = 0.94 },
		}
	do
		local blob = Factory.Blob(backgroundLayer, spec.diameter, spec.position, spec.color, spec.transparency)
		table.insert(self.ambientBlobs, { instance = blob, restPosition = spec.position })
	end

	self.toastHost = Factory.New("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 92),
		Size = UDim2.fromOffset(360, 320),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = shell,
	})
	Factory.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.toastHost,
	})

	self.loading = Factory.New("Frame", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 100,
		Parent = shell,
	})
	local loadingMark = Factory.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = Colors.Violet,
		BorderSizePixel = 0,
		ZIndex = 101,
		Parent = self.loading,
	})
	Factory.Corner(loadingMark, 20)
	Factory.Gradient(loadingMark, { Colors.Rose, Colors.Violet, Colors.Cyan }, 35)
	Factory.Label(loadingMark, "F", UDim2.fromScale(1, 1), {
		Font = Theme.Fonts.Black,
		TextSize = 38,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 102,
	})
	Factory.Label(self.loading, "Opening your creator studio…", UDim2.fromOffset(330, 34), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.53),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		ZIndex = 101,
	})

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_ApplyResponsiveLayout()
		end)
	end
	self:_ApplyResponsiveLayout()
	self:_HighlightNavigation()
end

-- One ember: fades in, drifts upward with a little horizontal wander while
-- fading back out, then reappears at a new random spot along the bottom.
-- Self-scheduling rather than driven by a shared Heartbeat loop, so adding
-- more later is just spawning more of these.
function App:_LoopEmber(ember: Frame)
	local function cycle()
		if not self.ambientMotionEnabled or ember.Parent == nil then
			return
		end
		local startX = math.random(0, 1000) / 1000
		local driftX = math.clamp(startX + math.random(-80, 80) / 1000, 0, 1)
		ember.Position = UDim2.new(startX, 0, 1, math.random(0, 60))
		ember.BackgroundTransparency = 1
		local riseSeconds = math.random(75, 145) / 10
		local fadeIn = TweenService:Create(
			ember,
			TweenInfo.new(riseSeconds * 0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.45 }
		)
		local rise = TweenService:Create(
			ember,
			TweenInfo.new(riseSeconds, Enum.EasingStyle.Linear),
			{ Position = UDim2.new(driftX, 0, -0.05, 0) }
		)
		local fadeOut = TweenService:Create(
			ember,
			TweenInfo.new(riseSeconds * 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		fadeIn:Play()
		rise:Play()
		task.delay(riseSeconds * 0.65, function()
			if self.ambientMotionEnabled and ember.Parent then
				fadeOut:Play()
			end
		end)
		task.delay(riseSeconds + math.random(0, 20) / 10, cycle)
	end
	cycle()
end

-- Starts or stops all ambient background motion (the two depth blobs
-- breathing, and the ember drift) in one place, so both the initial
-- reduce-motion check at bootstrap and a live toggle from Settings go
-- through the same path. Embers are actually destroyed when disabled rather
-- than merely paused -- reduce-motion should mean no motion, not motion
-- that is invisibly still running.
function App:_SetAmbientMotion(enabled: boolean)
	self.ambientMotionEnabled = enabled
	for _, ember in self.ambientEmbers do
		ember:Destroy()
	end
	table.clear(self.ambientEmbers)
	for _, entry in self.ambientBlobs do
		if enabled then
			local drift = math.random(14, 26)
			local period = math.random(70, 110) / 10
			TweenService:Create(
				entry.instance,
				TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = entry.restPosition + UDim2.fromOffset(drift, math.floor(drift * 0.6)) }
			):Play()
		else
			TweenService:Create(entry.instance, TweenInfo.new(0.3), { Position = entry.restPosition }):Play()
		end
	end
	if not enabled or not self.backgroundLayer then
		return
	end
	for _ = 1, EMBER_COUNT do
		local diameter = math.random(3, 6)
		local ember = Factory.New("Frame", {
			Name = "Ember",
			Size = UDim2.fromOffset(diameter, diameter),
			BackgroundColor3 = EMBER_COLORS[math.random(1, #EMBER_COLORS)],
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = self.backgroundLayer,
		})
		Factory.Corner(ember, diameter / 2)
		table.insert(self.ambientEmbers, ember)
		task.delay(math.random(0, 60) / 10, function()
			self:_LoopEmber(ember)
		end)
	end
end

function App:_SetStudioOpen(open: boolean)
	local changed = self.shell.Visible ~= open
	self.shell.Visible = open
	self.launcher.Visible = not open
	self.arcadeLauncher.Visible = not open
	if changed and open then
		self.sounds:Play("PanelOpen")
	elseif changed then
		self.sounds:Play("PanelClose")
	end
end

function App:_ApplyResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1200
	local height = if camera then camera.ViewportSize.Y else 800
	local compact = width < 760
	local gridColumns = if compact then 1 elseif width < 1050 then 2 elseif width < 1420 then 3 else 4
	local layoutChanged = self.compact ~= nil
		and (self.compact ~= compact or (self.gridColumns ~= nil and self.gridColumns ~= gridColumns))
	self.compact = compact
	self.gridColumns = gridColumns
	local navScale = if compact then 0.16 else 0.145
	self.nav.Size = UDim2.new(navScale, 0, 1, -78)
	self.content.Position = UDim2.new(navScale, 0, 0, 78)
	self.content.Size = UDim2.new(1 - navScale, 0, 1, -78)
	-- AmbientBackground has to track Content's rect exactly: it's a sibling
	-- (see _BuildChrome for why), not a child, so it doesn't get this for
	-- free the way a normal child would.
	if self.backgroundLayer then
		self.backgroundLayer.Position = self.content.Position
		self.backgroundLayer.Size = self.content.Size
	end
	self.navStack.Position = UDim2.fromOffset(if compact then 8 else 12, 18)
	self.navStack.Size = UDim2.new(1, if compact then -16 else -24, 0, 330)
	for page, button in self.navButtons do
		local symbol = if page == "Create"
			then "✦"
			elseif page == "My Studio" then "◈"
			elseif page == "Discover" then "◎"
			elseif page == "Avatar Lab" then "◇"
			else "⚙"
		button.Text = if compact then symbol else symbol .. "   " .. page
		button.TextXAlignment = if compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	end
	self:_UpdateSoundButton()
	local tip = self.nav:FindFirstChild("GroupTip")
	if tip then
		tip.Visible = not compact and height >= 620
	end
	self.statusArea.Visible = width >= 1120
	if layoutChanged and self.state then
		task.defer(function()
			self:_RenderActivePage()
		end)
	end
end

function App:_UpdateSoundButton()
	if not self.soundButton or not self.soundButton.Parent then
		return
	end
	local enabled = not self.state or self.state.profile.settings.soundsEnabled ~= false
	self.soundButton.Text = if enabled then "♪   UI sound on" else "×   UI sound off"
	self.soundButton.BackgroundColor3 = if enabled then Colors.PanelSoft else Color3.fromRGB(47, 31, 48)
end

-- Builds the sound toggle used on the Settings page. Extracted from the old
-- persistent nav-rail button so it can be recreated each time that page
-- renders, like every other page-scoped control.
function App:_BuildSoundButton(parent: Instance, size: UDim2, position: UDim2): TextButton
	local button = Factory.Button(parent, "", size, position, nil)
	button.Name = "SoundToggle"
	button.TextXAlignment = Enum.TextXAlignment.Left
	Factory.Padding(button, 15, 0)
	self:_BindButton(button)
	self.soundButton = button
	self:_UpdateSoundButton()
	button.Activated:Connect(function()
		if not self.state then
			return
		end
		local enabled = self.state.profile.settings.soundsEnabled == false
		self.sounds:SetEnabled(enabled)
		self.state.profile.settings.soundsEnabled = enabled
		self:_UpdateSoundButton()
		task.spawn(function()
			local success, data = self:_Invoke(Network.Actions.UpdateSettings, { soundsEnabled = enabled })
			if success then
				self.state.profile.settings = data.settings
				self.sounds:SetEnabled(data.settings.soundsEnabled)
			else
				self.state.profile.settings.soundsEnabled = not enabled
				self.sounds:SetEnabled(not enabled)
			end
			self:_UpdateSoundButton()
		end)
	end)
	return button
end

-- Respects the reduce-motion accessibility setting by applying the target
-- properties instantly instead of tweening them.
function App:_Animate(instance: Instance, info: TweenInfo, properties: { [string]: any }): Tween?
	if self.state and self.state.profile.settings.reduceMotion == true then
		for property, value in properties do
			(instance :: any)[property] = value
		end
		return nil
	end
	local tween = TweenService:Create(instance, info, properties)
	tween:Play()
	return tween
end

-- Shared overlay-fade + modal-scale-pop entrance for the app's full-screen
-- confirm/upsell dialogs (Plus, leaderboard, onboarding) -- goes through
-- _Animate so it's a no-op under reduceMotion (final values applied
-- instantly) rather than each call site handling that itself.
function App:_AnimateModalIn(overlay: Frame, modal: Frame)
	local targetTransparency = overlay.BackgroundTransparency
	overlay.BackgroundTransparency = 1
	self:_Animate(
		overlay,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = targetTransparency }
	)
	local scale = Factory.New("UIScale", { Scale = 0.92, Parent = modal })
	self:_Animate(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

-- Shared by the Settings page's own Invite card and any other contextual
-- invite touchpoint (e.g. the Daily Quests clear-all banner) -- same native
-- prompt + eligibility check everywhere a "grow the studio" moment happens.
function App:_PromptFriendInvite()
	local player = Players.LocalPlayer
	local checkSuccess, allowed = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not checkSuccess or allowed ~= true then
		self:_Toast("error", "Invites aren't available for your account or platform right now.")
		return
	end
	local promptSuccess, promptProblem = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if not promptSuccess then
		warn(string.format("[App] Game invite prompt failed: %s", tostring(promptProblem)))
		self:_Toast("error", "Roblox could not open the invite prompt.")
	end
end

-- Shared by the Create page's own Priority Pass button and the contextual
-- upsell chip on a queued generation row -- both buy a pass the same way,
-- for use on whatever gets submitted next (see the upsell chip's own
-- comment for why it can't speed up a job already queued).
function App:_BuyPriorityPass()
	task.spawn(function()
		local success, result = self:_Invoke(Network.Actions.BuyPriorityPass, { paymentMethod = self.paymentMethod })
		if success and result.tokensSpent then
			self.state.profile.tokens = result.tokens
			self.state.profile.bonusTokens = result.bonusTokens
			self.sounds:Play("Success")
			self:_Toast("success", string.format("%d tokens spent on a priority pass.", result.tokensSpent))
			self:_RenderActivePage()
		elseif success and not result.mocked then
			self.sounds:Play("PurchasePrompt")
			self:_Toast("success", "Confirm the priority pass purchase in Roblox.")
		end
	end)
end

function App:_BindButton(button: GuiButton)
	self.sounds:Bind(button)
	button.Selectable = true
	local original = button.BackgroundTransparency
	button.MouseEnter:Connect(function()
		self:_Animate(button, TweenInfo.new(0.14), { BackgroundTransparency = math.min(0.18, original + 0.06) })
	end)
	button.MouseLeave:Connect(function()
		self:_Animate(button, TweenInfo.new(0.14), { BackgroundTransparency = original })
	end)
	button.SelectionGained:Connect(function()
		self:_Animate(button, TweenInfo.new(0.1), { BackgroundTransparency = math.min(0.18, original + 0.06) })
	end)
	button.SelectionLost:Connect(function()
		self:_Animate(button, TweenInfo.new(0.1), { BackgroundTransparency = original })
	end)
end

function App:_Invoke(action: string, payload: any?): (boolean, any)
	local folder = waitForRemoteFolder()
	local remote = if folder then waitForRequestRemote(folder) else nil
	if not remote then
		warn(string.format("[App] Forge network transport was unavailable for %s", action))
		self:_Toast("error", "The Forge server is still starting. Rejoin and try again.")
		return false, "NETWORK_UNAVAILABLE"
	end
	local success, response = pcall(function()
		return remote:InvokeServer(action, payload or {})
	end)
	if not success or type(response) ~= "table" then
		self:_Toast("error", "The studio server did not respond. Try again.")
		return false, "NETWORK_ERROR"
	end
	if response.ok ~= true then
		local code = tostring(response.error or "SERVER_ERROR")
		self:_Toast("error", ERROR_MESSAGES[code] or "That action could not be completed.")
		return false, code
	end
	if response.data == nil then
		warn(string.format("[App] Remote %s succeeded without response data; using an empty result", action))
		return true, {}
	end
	return true, response.data
end

function App:_Track(payload: { [string]: any })
	task.spawn(function()
		local folder = waitForRemoteFolder()
		local remote = if folder then waitForRequestRemote(folder) else nil
		if not remote then
			return
		end
		pcall(function()
			remote:InvokeServer(Network.Actions.Track, payload)
		end)
	end)
end

-- AdService:GetAdAvailabilityNowAsync may only be called from a client
-- script (confirmed against Roblox's own class reference), and Roblox's own
-- performance guidance is to call it right before you might show the ad
-- rather than continuously, so this runs once per Create-page visit rather
-- than on a timer.
function App:_RefreshAdAvailability()
	if self.adAvailabilityChecking then
		return
	end
	self.adAvailabilityChecking = true
	task.spawn(function()
		local success, result = pcall(function()
			return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		end)
		self.adAvailabilityChecking = false
		if success and type(result) == "table" then
			self.adAvailable = result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
		else
			self.adAvailable = false
		end
		if self.activePage == "Create" then
			self:_RenderActivePage()
		end
	end)
end

function App:_RefreshLocalizedPrices()
	local state = self.state
	if not state then
		return
	end
	task.spawn(function()
		for productKey, product in Config.Products do
			if product.Id > 0 then
				local success, info = pcall(function()
					return MarketplaceService:GetProductInfoAsync(product.Id, Enum.InfoType.Product)
				end)
				if success and type(info) == "table" and type(info.PriceInRobux) == "number" then
					state.prices[productKey] = info.PriceInRobux
				end
			end
		end
		for passKey, pass in Config.Passes do
			if pass.Id > 0 then
				local success, info = pcall(function()
					return MarketplaceService:GetProductInfoAsync(pass.Id, Enum.InfoType.GamePass)
				end)
				if success and type(info) == "table" and type(info.PriceInRobux) == "number" then
					state.prices[passKey] = info.PriceInRobux
				end
			end
		end
		if self.state == state then
			self:_RenderActivePage()
		end
	end)
end

function App:_Bootstrap()
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.Bootstrap, {})
		if not success then
			Factory.Label(self.loading, "Could not open your profile. Rejoin to retry.", UDim2.fromOffset(420, 60), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.64),
				Color = Colors.Danger,
				AlignX = Enum.TextXAlignment.Center,
				Wrapped = true,
				ZIndex = 102,
			})
			return
		end
		self.state = data
		self.adWatchesToday = watchesTodayFromProfile(data.profile)
		self.sounds:SetEnabled(data.profile.settings.soundsEnabled ~= false)
		if data.profile.settings.highContrast == true then
			Theme.SetHighContrast(true)
			self.gui:Destroy()
			self:_BuildChrome()
		end
		self.uiScaleInstance.Scale = tonumber(data.profile.settings.uiScale) or 1
		self:_UpdateSoundButton()
		self:_SetAmbientMotion(data.profile.settings.reduceMotion ~= true)
		self.loading:Destroy()
		self:_RenderStatus()
		self:_OpenPage("Create")
		self:_ConnectPush()
		self:_RefreshLocalizedPrices()
		if not data.profile.onboarding.completed then
			self:_ShowOnboarding()
		elseif
			data.dailyBrief
			and (
				data.dailyBrief.rewardGranted
				or (data.dailyBrief.tokensGranted or 0) > 0
				or (data.dailyBrief.winBackTokensGranted or 0) > 0
				or data.dailyBrief.milestoneReward ~= nil
			)
		then
			self.sounds:Play("Success")
			local parts = {}
			if (data.dailyBrief.winBackTokensGranted or 0) > 0 then
				table.insert(
					parts,
					string.format(
						"Welcome back after %d days! +%d bonus Forge Tokens",
						data.dailyBrief.daysAway or 0,
						data.dailyBrief.winBackTokensGranted
					)
				)
			end
			if (data.dailyBrief.tokensGranted or 0) > 0 then
				table.insert(parts, string.format("+%d Forge Tokens for returning", data.dailyBrief.tokensGranted))
			end
			if data.dailyBrief.rewardGranted then
				table.insert(
					parts,
					string.format("%d-day streak reward: one free Priority Pass", data.dailyBrief.streak)
				)
			end
			if data.dailyBrief.milestoneReward then
				local milestone = data.dailyBrief.milestoneReward
				table.insert(
					parts,
					string.format(
						"🏆 %d-day milestone: +%d tokens, +%d Priority Pass%s",
						milestone.day,
						milestone.tokens,
						milestone.priorityPasses,
						if milestone.priorityPasses == 1 then "" else "es"
					)
				)
			end
			self:_Toast("success", table.concat(parts, " · "))
		elseif data.dailyBrief and data.dailyBrief.streak > 0 then
			self:_Toast(
				"success",
				string.format(
					"Studio streak: %d days · Today's brief is %s",
					data.dailyBrief.streak,
					data.dailyBrief.theme
				)
			)
		end
	end)
end

function App:_RefreshBootstrap()
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.Bootstrap, {})
		if success then
			self.state = data
			self.adWatchesToday = watchesTodayFromProfile(data.profile)
			self:_RenderStatus()
			self:_RenderActivePage()
			self:_RefreshLocalizedPrices()
		end
	end)
end

-- Swaps the shared color palette and rebuilds the studio chrome so already
-- rendered elements (which hold their color as a plain value, not a live
-- binding) pick up the change too. Used by the Settings page toggle and,
-- once, right after bootstrap if the player saved this preference before.
function App:_SetHighContrast(enabled: boolean)
	if Theme.IsHighContrast == enabled then
		return
	end
	local wasOpen = self.shell.Visible
	local motionWasEnabled = self.ambientMotionEnabled
	Theme.SetHighContrast(enabled)
	self.gui:Destroy()
	self:_BuildChrome()
	self.loading:Destroy()
	self.shell.Visible = wasOpen
	self.launcher.Visible = not wasOpen
	self:_UpdateSoundButton()
	-- _BuildChrome creates fresh blob/ember instances but doesn't itself
	-- know whether ambient motion should be running -- carry the previous
	-- state over rather than defaulting back to off.
	self:_SetAmbientMotion(motionWasEnabled)
	self:_RenderStatus()
	self:_RenderActivePage()
end

function App:_ConnectPush()
	local folder = waitForRemoteFolder()
	local push = if folder then waitForPushRemote(folder) else nil
	if not push then
		warn("[App] Forge push transport was unavailable")
		self:_Toast("error", "Live Forge updates are unavailable. Rejoin to reconnect.")
		return
	end
	push.OnClientEvent:Connect(function(eventName: string, payload: any)
		if eventName == Network.PushEvents.Toast then
			self:_Toast(payload.tone or "success", payload.message or "Updated")
		elseif eventName == Network.PushEvents.Profile then
			for key, value in payload do
				self.state.profile[key] = value
			end
			self:_RenderStatus()
			self:_RenderActivePage()
		elseif eventName == Network.PushEvents.Generation then
			if payload.stage == "QUEUED" and not self.queuedSoundIds[payload.generationId] then
				self.queuedSoundIds[payload.generationId] = true
				self.sounds:Play("Queue")
			end
			local profile = self.state and self.state.profile
			local generation = profile and profile.generations[payload.generationId]
			if generation then
				for key, value in payload do
					if key ~= "generationId" then
						generation[key] = value
					end
				end
				if self.activePage == "Create" then
					self:_RenderActivePage()
				end
			else
				task.delay(0.25, function()
					self:_RefreshBootstrap()
				end)
			end
		elseif eventName == Network.PushEvents.Item or eventName == Network.PushEvents.Transfer then
			task.delay(0.2, function()
				self:_RefreshBootstrap()
			end)
		elseif eventName == Network.PushEvents.Entitlements then
			for key, value in payload do
				self.state.benefits[key] = value
			end
			self:_RenderStatus()
			self:_RenderActivePage()
		elseif eventName == Network.PushEvents.Quests then
			self.state.questState = { questsDone = payload.questsDone }
			self.questJustCompleted = payload.justCompleted
			if not self.state.profile.settings.reduceMotion then
				self.sounds:Play("Success")
			end
			self:_RenderActivePage()
		end
	end)
end

function App:_RenderStatus()
	clear(self.statusArea)
	Factory.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 9),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = self.statusArea,
	})
	if not self.state then
		return
	end
	local benefits = self.state.benefits
	local daily = self.state.dailyBrief
	if daily then
		Factory.Pill(self.statusArea, string.format("🔥 %d DAY STREAK", daily.streak), Colors.Rose, 112).LayoutOrder =
			1
	end
	Factory.Pill(
		self.statusArea,
		string.format("%d QUEUE SLOT%s", benefits.queueSlots, if benefits.queueSlots == 1 then "" else "S"),
		Colors.Cyan,
		118
	).LayoutOrder =
		2
	Factory.Pill(
		self.statusArea,
		if benefits.plusSubscriber then "PLUS ACTIVE" else "PLUS: SELL ONLY",
		if benefits.plusSubscriber then Colors.Mint else Colors.Gold,
		124
	).LayoutOrder =
		3
end

function App:_OpenPage(page: string)
	self.activePage = page
	self.sounds:Play("PanelOpen")
	self:_HighlightNavigation()
	self:_RenderActivePage()
	self:_Track({ event = "AppOpenedTab", fields = { page = page } })
end

function App:_HighlightNavigation()
	for page, button in self.navButtons do
		local active = page == self.activePage
		self:_Animate(
			button,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad),
			{ BackgroundColor3 = if active then Colors.Violet else Colors.PanelSoft }
		)
		self:_Animate(
			button,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad),
			{ TextColor3 = if active then Colors.Text else Colors.TextMuted }
		)
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			self:_Animate(stroke, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
				Color = if active then Colors.Cyan else Colors.Line,
				Transparency = if active then 0.3 else 0.55,
			})
		end
		if active and self.navIndicator then
			-- Computed from the known navStack layout (18px offset, 48px
			-- buttons, 9px gaps) rather than read off AbsolutePosition,
			-- which isn't guaranteed to already reflect a UIListLayout pass
			-- on the very frame a button was created.
			local targetY = 18 + (button.LayoutOrder - 1) * 57
			self:_Animate(
				self.navIndicator,
				TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(0, targetY) }
			)
		end
	end
end

function App:_RenderActivePage()
	self.pageVersion += 1
	for _, connection in self.pageConnections do
		connection:Disconnect()
	end
	table.clear(self.pageConnections)
	if self.activeViewport then
		self.activeViewport:Destroy()
		self.activeViewport = nil
	end
	clear(self.content)
	if not self.state then
		return
	end
	if self.activePage == "Create" then
		self:_RenderCreate()
	elseif self.activePage == "My Studio" then
		self:_RenderStudio()
	elseif self.activePage == "Discover" then
		self:_RenderDiscover()
	elseif self.activePage == "Avatar Lab" then
		self:_RenderAvatarLab()
	else
		self:_RenderSettings()
	end
end

function App:_PageHeader(title: string, subtitle: string)
	Factory.Label(self.content, title, UDim2.new(0.95, 0, 0, 42), {
		Position = UDim2.new(0.025, 0, 0, 18),
		Font = Theme.Fonts.Black,
		TextSize = 28,
	})
	Factory.Label(self.content, subtitle, UDim2.new(0.95, 0, 0, 32), {
		Position = UDim2.new(0.025, 0, 0, 57),
		Color = Colors.TextMuted,
		TextSize = 13,
		Wrapped = true,
		AlignY = Enum.TextYAlignment.Top,
	})
end

function App:_TextBox(parent: Instance, placeholder: string, size: UDim2, position: UDim2, multiline: boolean?): TextBox
	local box = Factory.New("TextBox", {
		Size = size,
		Position = position,
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(113, 124, 160),
		Text = "",
		TextColor3 = Colors.Text,
		Font = Theme.Fonts.Regular,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextWrapped = multiline == true,
		MultiLine = multiline == true,
		Parent = parent,
	})
	Factory.Corner(box, Theme.SmallCorner)
	Factory.Stroke(box, Colors.Line, 0.42)
	Factory.Padding(box, 14, if multiline then 12 else 0)
	return box
end

function App:_RenderCreate()
	self:_PageHeader(
		"Create something impossible",
		"Three paths, precise art direction, one Roblox-ready accessory. Every input is moderated."
	)
	local page = Factory.New("ScrollingFrame", {
		Name = "CreateScroll",
		Position = UDim2.new(0.02, 0, 0, 96),
		Size = UDim2.new(0.96, 0, 1, -112),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Violet,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = self.content,
	})
	Factory.ScalePadding(page, 0.006, 0.006)
	local stack = Factory.New("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = page,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 14)

	if self.adAvailable == nil and not self.adAvailabilityChecking then
		self:_RefreshAdAvailability()
	end
	-- Two pools shown as one combined balance (see ProfileService.
	-- defaultProfile): ad-earned/purchased tokens can fund a generation or
	-- the Priority Pass, free tokens (achievements, streaks, invites) only
	-- ever fund the Pass. CommerceService enforces which pool an actual
	-- purchase draws from; this display total is just tokens + bonusTokens.
	local adTokens = self.state.profile.tokens or 0
	local bonusTokens = self.state.profile.bonusTokens or 0
	local totalTokens = adTokens + bonusTokens
	-- No daily cap: every completed ad is real, positive revenue for Forge
	-- (see Config.Ads.WorstCaseAdRevenuePerAd), so this is purely a "you've
	-- watched N today" stat, never a limiter on the button below.
	local watchesToday = self.adWatchesToday or 0
	local tokensDescriptionText = "Earn tokens by watching ads. Ad tokens fund generations or the Pass; "
		.. "free tokens (achievements, streaks) fund the Pass only."
	-- Right-hand controls: on compact layouts this column collapses to full
	-- width BELOW the balance/description, so its start (payLabelY) has to
	-- clear however tall that description wraps to, not a number guessed
	-- once and left to drift the next time the copy changes — that mismatch
	-- is exactly how the description text overlapping "PAY WITH" would
	-- happen. On wide layouts the column sits beside the description
	-- instead, so its position is independent of the description's height.
	local rightX = if self.compact then 0 else 0.46
	local rightWidth = if self.compact then 1 else 0.54
	local inset = if self.compact then 16 else 0
	local gap = 8
	local tokensDescriptionY = 70
	-- Scaled from the previous copy's proven-good 32/50 at a proportional
	-- length increase (97 -> ~130 chars) rather than re-guessed from
	-- scratch — there is no layout pass to measure the actual wrapped height
	-- against here, so anchoring to a dimension that already shipped
	-- correctly beats a fresh pixel estimate for text this codebase can't
	-- measure at render time.
	local tokensDescriptionHeight = if self.compact then 46 else 68
	local payLabelY = if self.compact then tokensDescriptionY + tokensDescriptionHeight + 12 else 12
	local toggleY = payLabelY + 20
	local watchAdY = toggleY + 38
	local buyTokensY = watchAdY + 42
	local tokensCardHeight = if self.compact then buyTokensY + 30 + 16 else 156
	local tokensCard = Factory.Card(stack, UDim2.new(1, 0, 0, tokensCardHeight), nil, "TokensCard")
	tokensCard.LayoutOrder = 0
	Factory.Label(tokensCard, "FORGE TOKENS", UDim2.new(0.42, -16, 0, 18), {
		Position = UDim2.fromOffset(16, 12),
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		Color = Colors.Gold,
	})
	Factory.Label(tokensCard, formatNumber(totalTokens), UDim2.new(0.42, -16, 0, 36), {
		Position = UDim2.fromOffset(16, 30),
		Font = Theme.Fonts.Black,
		TextSize = 28,
	})
	Factory.Label(tokensCard, tokensDescriptionText, UDim2.new(0.42, -16, 0, tokensDescriptionHeight), {
		Position = UDim2.fromOffset(16, tokensDescriptionY),
		Color = Colors.TextMuted,
		TextSize = 11,
		Wrapped = true,
		AlignY = Enum.TextYAlignment.Top,
	})
	-- Applies to every purchase button below (generation, conversion, and
	-- the Priority Pass) — CommerceService silently draws from whichever
	-- pool a given purchase is actually allowed to use, per the comment
	-- above the balance.
	Factory.Label(tokensCard, "PAY WITH", UDim2.new(rightWidth, -2 * inset, 0, 16), {
		Position = UDim2.new(rightX, inset, 0, payLabelY),
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Color = Colors.TextMuted,
	})
	local toggleWidth = UDim2.new(rightWidth / 2, -(inset + gap / 2), 0, 30)
	local payRobux = Factory.Button(
		tokensCard,
		"Robux",
		toggleWidth,
		UDim2.new(rightX, inset, 0, toggleY),
		if self.paymentMethod == "ROBUX" then "primary" else nil
	)
	local payTokens = Factory.Button(
		tokensCard,
		"Tokens",
		toggleWidth,
		UDim2.new(rightX + rightWidth / 2, gap / 2, 0, toggleY),
		if self.paymentMethod == "TOKENS" then "mint" else nil
	)
	self:_BindButton(payRobux)
	self:_BindButton(payTokens)
	payRobux.Activated:Connect(function()
		self.paymentMethod = "ROBUX"
		self:_RenderActivePage()
	end)
	payTokens.Activated:Connect(function()
		self.paymentMethod = "TOKENS"
		self:_RenderActivePage()
	end)
	local watchAdActive = self.adAvailable == true
	local watchAd = Factory.Button(
		tokensCard,
		if self.adAvailabilityChecking
			then "Checking for an ad…"
			elseif self.adAvailable == false then "No ad available right now"
			else string.format(
				"Watch ad · +%d token%s%s",
				Config.Ads.TokenGrantPerPurchase,
				if Config.Ads.TokenGrantPerPurchase == 1 then "" else "s",
				if watchesToday > 0 then string.format(" (%d today)", watchesToday) else ""
			),
		UDim2.new(rightWidth, -2 * inset, 0, 34),
		UDim2.new(rightX, inset, 0, watchAdY),
		if watchAdActive then "mint" else nil
	)
	watchAd.Active = watchAdActive
	self:_BindButton(watchAd)
	watchAd.Activated:Connect(function()
		watchAd.Active = false
		watchAd.Text = "Loading ad…"
		task.spawn(function()
			local success, result = self:_Invoke(Network.Actions.RequestRewardedAd, {})
			if success then
				self.adWatchesToday = result.watchesToday
				self:_Toast("ready", "Thanks for watching! Your tokens are on the way.")
			end
			self:_RenderActivePage()
		end)
	end)
	local buyTokens = Factory.Button(
		tokensCard,
		string.format(
			"Buy %d token%s · R$ %d",
			Config.Ads.TokenGrantPerPurchase,
			if Config.Ads.TokenGrantPerPurchase == 1 then "" else "s",
			self.state.prices.AdRewardTokens
		),
		UDim2.new(rightWidth, -2 * inset, 0, 30),
		UDim2.new(rightX, inset, 0, buyTokensY),
		nil
	)
	self:_BindButton(buyTokens)
	buyTokens.Activated:Connect(function()
		buyTokens.Active = false
		task.spawn(function()
			local success, result = self:_Invoke(Network.Actions.BuyTokens, {})
			if success then
				if result.mocked then
					self:_RefreshBootstrap()
					self:_Toast("success", "Studio mock purchase confirmed. Tokens added.")
				else
					self.sounds:Play("PurchasePrompt")
					self:_Toast("success", "Confirm the token pack purchase in Roblox.")
				end
			end
			if buyTokens.Parent then
				buyTokens.Active = true
			end
		end)
	end)

	local customUploadOwned = self.state.benefits.customImageUpload == true
	local methodRow = Factory.New("Frame", {
		Size = UDim2.new(1, 0, 0, if self.compact then 456 else 156),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = stack,
	})
	for index, method in
		{
			{
				id = "TEXT_TO_3D",
				title = "Direct Forge",
				kicker = "FASTEST VALUE",
				body = "Text → Smart Topology 3D. Lower cost and ideal for bold, simple silhouettes.",
				price = self.state.prices.DirectGeneration,
				color = Colors.Cyan,
			},
			{
				id = "IMAGE_PREVIEW",
				title = "Art-Directed",
				kicker = "MORE CONTROL",
				body = "Text → reference image → 3D. Choose a reference quality tier, then approve the look before spending on the model.",
				priceText = string.format("FROM R$ %d", self.state.prices.ImagePreviewLow),
				color = Colors.Rose,
			},
			{
				id = "IMAGE_UPLOAD",
				title = "Upload Reference",
				kicker = "POWER USER",
				body = "Use your own Roblox-moderated Image or Decal, then approve it before 3D conversion.",
				priceText = if customUploadOwned
					then "OWNED"
					else string.format("R$ %d ONCE", self.state.prices.CustomImageUpload),
				color = Colors.Gold,
			},
		}
	do
		local card = if self.compact
			then Factory.Card(methodRow, UDim2.new(1, 0, 0, 144), UDim2.fromOffset(0, (index - 1) * 156))
			else Factory.Card(
				methodRow,
				UDim2.new(1 / 3, -8, 1, 0),
				UDim2.new((index - 1) / 3, (index - 1) * 4, 0, 0)
			)
		local selected = self.selectedMethod == method.id
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if selected then method.color else Colors.Line
			stroke.Transparency = if selected then 0.12 else 0.55
			stroke.Thickness = if selected then 2 else 1
		end
		Factory.Pill(card, method.kicker, method.color, 104).Position = UDim2.fromOffset(16, 14)
		Factory.Label(card, method.title, UDim2.new(1, -150, 0, 31), {
			Position = UDim2.fromOffset(16, 46),
			Font = Theme.Fonts.Black,
			TextSize = if self.compact then 20 else 18,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		Factory.Label(card, method.body, UDim2.new(1, -32, 0, 52), {
			Position = UDim2.fromOffset(16, 80),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		})
		local priceText = method.priceText or string.format("R$ %d", method.price)
		Factory.Label(card, priceText, UDim2.fromOffset(106, 35), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -15, 0, 48),
			AlignX = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.Black,
			TextSize = 18,
			Color = method.color,
		})
		local choose = Factory.New("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			Parent = card,
		})
		self:_BindButton(choose)
		choose.Activated:Connect(function()
			self.selectedMethod = method.id
			self:_RenderActivePage()
		end)
	end

	local isUpload = self.selectedMethod == "IMAGE_UPLOAD"
	if isUpload and not customUploadOwned then
		local unlock = Factory.Card(stack, UDim2.new(1, 0, 0, if self.compact then 246 else 196), nil, "UploadUnlock")
		unlock.LayoutOrder = 2
		Factory.Pill(unlock, "PERMANENT CREATOR TOOL", Colors.Gold, 164).Position = UDim2.fromOffset(16, 15)
		Factory.Label(unlock, "Bring your own art direction", UDim2.new(1, -32, 0, 34), {
			Position = UDim2.fromOffset(16, 48),
			Font = Theme.Fonts.Black,
			TextSize = 22,
		})
		Factory.Label(
			unlock,
			string.format(
				"Upload an Image or Decal to Roblox Creator Hub, wait for Roblox moderation, then paste its asset ID here. Forge verifies its type and ownership without spending OpenAI vision credits. The R$ %d conversion is still charged only after you approve the image.",
				self.state.prices.ImageConversion
			),
			if self.compact then UDim2.new(1, -32, 0, 92) else UDim2.new(1, -290, 0, 84),
			{
				Position = UDim2.fromOffset(16, 86),
				Color = Colors.TextMuted,
				TextSize = 12,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
		local unlockButton = Factory.Button(
			unlock,
			string.format("Unlock forever · R$ %d", self.state.prices.CustomImageUpload),
			if self.compact then UDim2.new(1, -32, 0, 44) else UDim2.fromOffset(244, 44),
			if self.compact then UDim2.new(0, 16, 1, -58) else UDim2.new(1, -260, 0.5, -22),
			"mint"
		)
		self:_BindButton(unlockButton)
		unlockButton.Activated:Connect(function()
			unlockButton.Active = false
			unlockButton.Text = "Checking ownership…"
			task.spawn(function()
				local success, result = self:_Invoke(Network.Actions.PromptCustomImagePass, {})
				if success then
					if result.mocked or result.alreadyOwned then
						self:_RefreshBootstrap()
						self:_Toast("success", "Custom image upload is unlocked.")
					else
						self.sounds:Play("PurchasePrompt")
						self:_Toast("success", "Confirm the permanent upload pass in Roblox.")
					end
				else
					unlockButton.Active = true
					unlockButton.Text = string.format("Unlock forever · R$ %d", self.state.prices.CustomImageUpload)
				end
			end)
		end)
	else
		local cursorY = 14
		local promptCard = Factory.Card(stack, UDim2.new(1, 0, 0, 560), nil, "PromptCard")
		promptCard.LayoutOrder = 2
		Factory.Label(promptCard, "1  DESCRIBE YOUR ACCESSORY", UDim2.new(1, -32, 0, 24), {
			Position = UDim2.fromOffset(16, cursorY),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Cyan,
		})
		cursorY += 32
		local prompt = self:_TextBox(
			promptCard,
			"Example: A glossy crescent-moon crown made of translucent violet crystal, chunky silhouette, no floating pieces",
			UDim2.new(1, -32, 0, 80),
			UDim2.fromOffset(16, cursorY),
			true
		)
		prompt.Text = self.draftPrompt
		local count = Factory.Label(
			promptCard,
			string.format("%d / %d", #self.draftPrompt, Config.Generation.PromptMaxLength),
			UDim2.fromOffset(120, 20),
			{
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -18, 0, cursorY + 82),
				AlignX = Enum.TextXAlignment.Right,
				Color = Colors.TextMuted,
				TextSize = 11,
			}
		)
		prompt:GetPropertyChangedSignal("Text"):Connect(function()
			self.draftPrompt = string.sub(prompt.Text, 1, Config.Generation.PromptMaxLength)
			count.Text = string.format("%d / %d", #prompt.Text, Config.Generation.PromptMaxLength)
		end)
		cursorY += 108

		local step = 2
		local imageAssetBox = nil :: TextBox?
		if isUpload then
			Factory.Label(promptCard, "2  ADD YOUR ROBLOX IMAGE / DECAL", UDim2.new(1, -32, 0, 22), {
				Position = UDim2.fromOffset(16, cursorY),
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				Color = Colors.Gold,
			})
			cursorY += 27
			imageAssetBox = self:_TextBox(
				promptCard,
				"Paste the numeric asset ID, for example 1234567890",
				UDim2.new(1, -32, 0, 40),
				UDim2.fromOffset(16, cursorY),
				false
			)
			imageAssetBox.Text = self.customImageAssetId
			imageAssetBox:GetPropertyChangedSignal("Text"):Connect(function()
				local digits = string.sub(string.gsub(imageAssetBox.Text, "%D", ""), 1, 16)
				if digits ~= imageAssetBox.Text then
					imageAssetBox.Text = digits
				end
				self.customImageAssetId = digits
			end)
			cursorY += 45
			Factory.Label(
				promptCard,
				"Upload in Creator Hub first and wait for approval · Player- or creator-group-owned assets only · Roblox-approved images are not billed for another vision check",
				UDim2.new(1, -32, 0, 30),
				{
					Position = UDim2.fromOffset(16, cursorY),
					Color = Colors.TextMuted,
					TextSize = 11,
					Wrapped = true,
				}
			)
			cursorY += 38
			step = 3
		end

		local function choiceRow(
			options: { any },
			selectedValue: string,
			positionY: number,
			color: Color3,
			onChoose: (string) -> ()
		)
			local row = Factory.New("ScrollingFrame", {
				Position = UDim2.fromOffset(16, positionY),
				Size = UDim2.new(1, -32, 0, 38),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				CanvasSize = UDim2.new(),
				ScrollingDirection = Enum.ScrollingDirection.X,
				Parent = promptCard,
			})
			Factory.List(row, Enum.FillDirection.Horizontal, 8)
			for _, option in options do
				local selected = selectedValue == option.Id
				local chip = Factory.Button(
					row,
					option.Label,
					UDim2.fromOffset(98, 34),
					nil,
					if selected then "primary" else nil
				)
				if selected then
					chip.BackgroundColor3 = color
				end
				self:_BindButton(chip)
				chip.Activated:Connect(function()
					onChoose(option.Id)
				end)
			end
		end

		Factory.Label(promptCard, string.format("%d  CHOOSE A VISUAL STYLE", step), UDim2.new(1, -32, 0, 22), {
			Position = UDim2.fromOffset(16, cursorY),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Violet,
		})
		cursorY += 27
		choiceRow(Config.Generation.StylePresets, self.selectedStylePreset, cursorY, Colors.Violet, function(value)
			self.selectedStylePreset = value
			self:_RenderActivePage()
		end)
		cursorY += 46
		step += 1

		Factory.Label(promptCard, string.format("%d  CHOOSE DETAIL DENSITY", step), UDim2.new(1, -32, 0, 22), {
			Position = UDim2.fromOffset(16, cursorY),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Rose,
		})
		cursorY += 27
		choiceRow(Config.Generation.DetailLevels, self.selectedDetailLevel, cursorY, Colors.Rose, function(value)
			self.selectedDetailLevel = value
			self:_RenderActivePage()
		end)
		cursorY += 46
		step += 1

		if self.selectedMethod == "IMAGE_PREVIEW" then
			Factory.Label(promptCard, string.format("%d  CHOOSE REFERENCE QUALITY", step), UDim2.new(1, -32, 0, 22), {
				Position = UDim2.fromOffset(16, cursorY),
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				Color = Colors.Gold,
			})
			cursorY += 27
			local qualityRow = Factory.New("ScrollingFrame", {
				Position = UDim2.fromOffset(16, cursorY),
				Size = UDim2.new(1, -32, 0, 38),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				CanvasSize = UDim2.new(),
				ScrollingDirection = Enum.ScrollingDirection.X,
				Parent = promptCard,
			})
			Factory.List(qualityRow, Enum.FillDirection.Horizontal, 8)
			for _, tier in Config.Generation.ImageQualityTiers do
				local tierSelected = self.selectedImageQuality == tier.Id
				local chip = Factory.Button(
					qualityRow,
					string.format("%s · R$ %d", tier.Label, self.state.prices[tier.ProductKey] or 0),
					UDim2.fromOffset(146, 34),
					nil,
					if tierSelected then "primary" else nil
				)
				if tierSelected then
					chip.BackgroundColor3 = Colors.Gold
				end
				self:_BindButton(chip)
				chip.Activated:Connect(function()
					self.selectedImageQuality = tier.Id
					self:_RenderActivePage()
				end)
			end
			cursorY += 46
			step += 1
			Factory.Label(
				promptCard,
				"Higher tiers use a more detailed OpenAI render for a closer, cleaner reference before you approve the 3D build.",
				UDim2.new(1, -32, 0, 18),
				{ Position = UDim2.fromOffset(16, cursorY), Color = Colors.TextMuted, TextSize = 10 }
			)
			cursorY += 24
		end

		Factory.Label(promptCard, string.format("%d  CHOOSE A FIT REGION", step), UDim2.new(1, -32, 0, 22), {
			Position = UDim2.fromOffset(16, cursorY),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Cyan,
		})
		cursorY += 27
		local chipRow = Factory.New("ScrollingFrame", {
			Position = UDim2.fromOffset(16, cursorY),
			Size = UDim2.new(1, -32, 0, 38),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.X,
			Parent = promptCard,
		})
		Factory.List(chipRow, Enum.FillDirection.Horizontal, 8)
		for typeName, label in ACCESSORY_LABELS do
			local selected = self.selectedAccessoryType == typeName
			local chip =
				Factory.Button(chipRow, label, UDim2.fromOffset(88, 34), nil, if selected then "primary" else nil)
			self:_BindButton(chip)
			chip.Activated:Connect(function()
				self.selectedAccessoryType = typeName
				self:_RenderActivePage()
			end)
		end
		cursorY += 50

		local safetyY = cursorY
		local buttonY = if self.compact then safetyY + 39 else safetyY
		promptCard.Size = UDim2.new(1, 0, 0, buttonY + 58)
		Factory.Label(
			promptCard,
			if isUpload
				then "Roblox asset moderation + ownership verification · no duplicate OpenAI image check"
				else "Roblox TextService + provider moderation · 3,600 triangle target · 2K texture",
			if self.compact then UDim2.new(1, -32, 0, 34) else UDim2.new(1, -462, 0, 42),
			{
				Position = UDim2.fromOffset(16, safetyY),
				Color = Colors.TextMuted,
				TextSize = 11,
				Wrapped = true,
			}
		)

		local selectedQualityTier = nil :: { Id: string, Label: string, ProductKey: string, OpenAIQuality: string }?
		for _, tier in Config.Generation.ImageQualityTiers do
			if tier.Id == self.selectedImageQuality then
				selectedQualityTier = tier
				break
			end
		end
		local generationProductKey = if self.selectedMethod == "TEXT_TO_3D"
			then "DirectGeneration"
			elseif selectedQualityTier then selectedQualityTier.ProductKey
			else "ImagePreviewLow"
		local price = self.state.prices[generationProductKey]
		-- Tokens spent here draw only from the ad-earned balance (see
		-- CommerceService:BeginIntentWithTokens) — free/bonus tokens can
		-- never fund this, no matter how large that balance looks.
		local payWithTokens = self.paymentMethod == "TOKENS" and self.selectedMethod ~= "IMAGE_UPLOAD"
		local priceText = if payWithTokens
			then string.format("%d ad tokens", tokenPrice(price, generationProductKey))
			else string.format("R$ %d", price)
		local actionText = if self.selectedMethod == "TEXT_TO_3D"
			then string.format("Forge 3D · %s", priceText)
			elseif self.selectedMethod == "IMAGE_PREVIEW" then string.format("Create reference · %s", priceText)
			else "Moderate my reference · Included"
		local generate = Factory.Button(
			promptCard,
			actionText,
			if self.compact then UDim2.new(0.5, -20, 0, 42) else UDim2.new(0, 250, 0, 42),
			if self.compact then UDim2.new(0.5, 5, 0, buttonY) else UDim2.new(1, -266, 0, buttonY),
			"primary"
		)
		local availablePasses = self.state.profile.retryCredits.PriorityPass or 0
		local priority = Factory.Button(
			promptCard,
			if availablePasses > 0
				then string.format(
					"Priority %s · %d pass%s",
					if self.usePriority then "✓" else "",
					availablePasses,
					if availablePasses == 1 then "" else "es"
				)
				elseif self.paymentMethod == "TOKENS" then string.format(
					"Priority pass · %d tokens",
					tokenPrice(self.state.prices.PriorityPass)
				)
				else string.format("Priority pass · R$ %d", self.state.prices.PriorityPass),
			if self.compact then UDim2.new(0.5, -20, 0, 42) else UDim2.fromOffset(184, 42),
			if self.compact then UDim2.new(0, 15, 0, buttonY) else UDim2.new(1, -460, 0, buttonY),
			if self.usePriority then "mint" else nil
		)
		self:_BindButton(generate)
		self:_BindButton(priority)
		priority.Activated:Connect(function()
			if availablePasses > 0 then
				self.usePriority = not self.usePriority
				self:_RenderActivePage()
			else
				self:_BuyPriorityPass()
			end
		end)
		generate.Activated:Connect(function()
			self.draftPrompt = prompt.Text
			generate.Active = false
			generate.Text = if isUpload then "Moderating image…" else "Checking prompt…"
			task.spawn(function()
				local request = {
					kind = self.selectedMethod,
					prompt = prompt.Text,
					accessoryType = self.selectedAccessoryType,
					stylePreset = self.selectedStylePreset,
					detailLevel = self.selectedDetailLevel,
					usePriority = self.usePriority,
					paymentMethod = self.paymentMethod,
				}
				if self.selectedMethod == "IMAGE_PREVIEW" then
					request.imageQuality = self.selectedImageQuality
				end
				if imageAssetBox then
					request.sourceImageAssetId = tonumber(imageAssetBox.Text)
				end
				local success, result = if isUpload
					then self:_Invoke(Network.Actions.CreateUploadedImage, request)
					else self:_Invoke(Network.Actions.CreateGeneration, request)
				generate.Active = true
				generate.Text = actionText
				if success then
					if isUpload then
						self:_Toast("success", "Your Roblox image is entering visual moderation at no extra charge.")
					elseif result.usedRetryCredit then
						self:_Toast("success", "Retry credit applied. Your generation is entering the queue.")
					elseif result.mocked then
						self:_Toast("success", "Studio mock purchase confirmed. Your generation is entering the queue.")
					elseif result.tokensSpent then
						self.state.profile.tokens = result.tokens
						self.state.profile.bonusTokens = result.bonusTokens
						self.sounds:Play("Success")
						self:_Toast(
							"success",
							string.format("%d tokens spent. Your generation is entering the queue.", result.tokensSpent)
						)
					else
						self.sounds:Play("PurchasePrompt")
						self:_Toast(
							"success",
							"Purchase prompt opened. Generation begins only after Roblox confirms it."
						)
					end
				end
			end)
		end)
	end

	local readyImage = nil
	for _, generationId in self.state.profile.generationOrder do
		local generation = self.state.profile.generations[generationId]
		if generation and generation.stage == "IMAGE_READY" then
			readyImage = generation
			break
		end
	end
	if readyImage then
		local reference =
			Factory.Card(stack, UDim2.new(1, 0, 0, if self.compact then 382 else 210), nil, "ReferenceReview")
		reference.LayoutOrder = 3
		local image = Factory.New("ImageLabel", {
			Size = if self.compact then UDim2.fromOffset(132, 132) else UDim2.fromOffset(172, 172),
			Position = if self.compact then UDim2.new(0.5, -66, 0, 16) else UDim2.fromOffset(18, 19),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			Image = thumbnail(readyImage.previewAssetId, 420),
			ScaleType = Enum.ScaleType.Crop,
			Parent = reference,
		})
		Factory.Corner(image, 13)
		Factory.Label(
			reference,
			"REFERENCE READY",
			if self.compact then UDim2.new(1, -36, 0, 24) else UDim2.new(1, -224, 0, 24),
			{
				Position = if self.compact then UDim2.fromOffset(18, 158) else UDim2.fromOffset(210, 21),
				AlignX = if self.compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
				Color = Colors.Mint,
				Font = Theme.Fonts.Bold,
				TextSize = 11,
			}
		)
		Factory.Label(
			reference,
			"Approve this direction?",
			if self.compact then UDim2.new(1, -36, 0, 34) else UDim2.new(1, -224, 0, 34),
			{
				Position = if self.compact then UDim2.fromOffset(18, 182) else UDim2.fromOffset(210, 48),
				AlignX = if self.compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
				Font = Theme.Fonts.Black,
				TextSize = 21,
			}
		)
		Factory.Label(
			reference,
			string.format(
				"%s style · %s detail%s\nApproving starts the textured 3D conversion. %s",
				string.gsub(readyImage.stylePreset or "AUTO", "_", " "),
				string.gsub(readyImage.detailLevel or "BALANCED", "_", " "),
				if readyImage.imageQuality
					then string.format(" · %s quality", string.lower(readyImage.imageQuality))
					else "",
				if readyImage.method == "IMAGE_UPLOAD"
					then "You can submit another owned image at no extra charge."
					else "A reroll creates a new paid reference."
			),
			if self.compact then UDim2.new(1, -36, 0, 66) else UDim2.new(1, -232, 0, 54),
			{
				Position = if self.compact then UDim2.fromOffset(18, 220) else UDim2.fromOffset(210, 84),
				AlignX = if self.compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
				Color = Colors.TextMuted,
				TextSize = 12,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
		-- See the matching comment above the generate button — same
		-- ad-earned-only rule applies here.
		local conversionPriceText = if self.paymentMethod == "TOKENS"
			then string.format("%d ad tokens", tokenPrice(self.state.prices.ImageConversion, "ImageConversion"))
			else string.format("R$ %d", self.state.prices.ImageConversion)
		local approve = Factory.Button(
			reference,
			if self.compact
				then string.format("Build · %s", conversionPriceText)
				else string.format("Approve & build · %s", conversionPriceText),
			if self.compact then UDim2.new(0.5, -22, 0, 42) else UDim2.fromOffset(210, 42),
			if self.compact then UDim2.new(0, 14, 1, -58) else UDim2.fromOffset(210, 150),
			"mint"
		)
		self:_BindButton(approve)
		approve.Activated:Connect(function()
			task.spawn(function()
				local success, result = self:_Invoke(Network.Actions.ConvertImage, {
					generationId = readyImage.id,
					usePriority = self.usePriority,
					paymentMethod = self.paymentMethod,
				})
				if success then
					if result.usedRetryCredit then
						self:_Toast("success", "Conversion credit applied. Your model is entering the queue.")
					elseif result.mocked then
						self:_Toast("success", "Studio mock conversion confirmed.")
					elseif result.tokensSpent then
						self.state.profile.tokens = result.tokens
						self.state.profile.bonusTokens = result.bonusTokens
						self.sounds:Play("Success")
						self:_Toast(
							"success",
							string.format("%d tokens spent. Your model is entering the queue.", result.tokensSpent)
						)
					else
						self.sounds:Play("PurchasePrompt")
						self:_Toast("success", "Confirm the conversion in Roblox to begin building your model.")
					end
				end
			end)
		end)
		local reroll = Factory.Button(
			reference,
			if readyImage.method == "IMAGE_UPLOAD"
				then (if self.compact then "Replace" else "Use another image")
				else (if self.compact then "Reroll" else "Reroll · new reference"),
			if self.compact then UDim2.new(0.5, -22, 0, 42) else UDim2.fromOffset(178, 42),
			if self.compact then UDim2.new(0.5, 8, 1, -58) else UDim2.fromOffset(430, 150),
			nil
		)
		self:_BindButton(reroll)
		reroll.Activated:Connect(function()
			self.selectedMethod = if readyImage.method == "IMAGE_UPLOAD" then "IMAGE_UPLOAD" else "IMAGE_PREVIEW"
			self:_RenderActivePage()
			self:_Toast(
				"success",
				if readyImage.method == "IMAGE_UPLOAD"
					then "Paste another owned Roblox image ID when you are ready."
					else "Edit the prompt if you like, then create another paid reference."
			)
		end)
	end

	local availablePasses = self.state.profile.retryCredits.PriorityPass or 0
	local hasQueuedRow = false
	local rowCount = 0
	for _, generationId in self.state.profile.generationOrder do
		if rowCount >= 3 then
			break
		end
		local generation = self.state.profile.generations[generationId]
		if generation then
			rowCount += 1
			if generation.stage == "QUEUED" then
				hasQueuedRow = true
			end
		end
	end
	local showUpsell = hasQueuedRow and availablePasses <= 0
	local activityHeight = (if rowCount == 0 then 140 else 45 + rowCount * 50 + 14) + (if showUpsell then 46 else 0)
	local activity = Factory.Card(stack, UDim2.new(1, 0, 0, activityHeight), nil, "Activity")
	activity.LayoutOrder = 4
	Factory.Label(activity, "LIVE CREATION ACTIVITY", UDim2.new(1, -32, 0, 24), {
		Position = UDim2.fromOffset(16, 13),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.Violet,
	})
	local y = 45
	local shown = 0
	for _, generationId in self.state.profile.generationOrder do
		if shown >= 3 then
			break
		end
		local generation = self.state.profile.generations[generationId]
		if generation then
			local row = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, y),
				Size = UDim2.new(1, -32, 0, 44),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.22,
				BorderSizePixel = 0,
				Parent = activity,
			})
			Factory.Corner(row, 10)
			Factory.Stroke(row, Colors.Line, 0.75, 1)

			local isModel = generation.method == "TEXT_TO_3D" or generation.method == "IMAGE_TO_3D"
			local stageColor = if generation.stage == "FAILED"
				then Colors.Danger
				elseif generation.stage == "SUCCEEDED" or generation.stage == "IMAGE_READY" then Colors.Mint
				else Colors.Cyan

			-- Icon badge replaces the old flat MODEL/IMAGE tag -- same
			-- gradient-circle-plus-glyph treatment used for badges
			-- everywhere else this pass (toasts, leaderboard ranks, the
			-- daily-brief flame).
			local badge = Factory.New("Frame", {
				Size = UDim2.fromOffset(30, 30),
				Position = UDim2.fromOffset(7, 7),
				BackgroundColor3 = if isModel then Colors.Violet else Colors.Cyan,
				BorderSizePixel = 0,
				Parent = row,
			})
			Factory.Corner(badge, 15)
			Factory.Gradient(
				badge,
				if isModel
					then { Colors.Violet, Color3.fromRGB(91, 94, 255) }
					else { Colors.Cyan, Color3.fromRGB(70, 170, 220) },
				135
			)
			Factory.Label(badge, if isModel then "🧊" else "🖼", UDim2.fromScale(1, 1), {
				TextSize = 14,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
			})

			Factory.Label(row, string.sub(generation.filteredPrompt or "Creation", 1, 40), UDim2.new(1, -108, 0, 16), {
				Position = UDim2.fromOffset(46, 4),
				Font = Theme.Fonts.Medium,
				TextSize = 12,
				Truncate = Enum.TextTruncate.AtEnd,
			})
			Factory.Label(row, string.format("%d%%", math.floor(generation.progress or 0)), UDim2.fromOffset(46, 16), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 4),
				AlignX = Enum.TextXAlignment.Right,
				Font = Theme.Fonts.Black,
				Color = stageColor,
				TextSize = 12,
			})
			Factory.Label(row, generation.stageText or generation.stage, UDim2.new(1, -58, 0, 14), {
				Position = UDim2.fromOffset(46, 22),
				Color = Colors.TextMuted,
				TextSize = 10,
				Truncate = Enum.TextTruncate.AtEnd,
			})

			-- A slim progress bar reads at a glance far better than the bare
			-- percent text alone did.
			local track = Factory.New("Frame", {
				Position = UDim2.fromOffset(46, 39),
				Size = UDim2.new(1, -58, 0, 3),
				BackgroundColor3 = Colors.PanelSoft,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				Parent = row,
			})
			Factory.Corner(track, 2)
			local fill = Factory.New("Frame", {
				Size = UDim2.new(math.clamp((generation.progress or 0) / 100, 0, 1), 0, 1, 0),
				BackgroundColor3 = stageColor,
				BorderSizePixel = 0,
				Parent = track,
			})
			Factory.Corner(fill, 2)

			y += 50
			shown += 1
		end
	end
	if showUpsell then
		-- Contextual Priority Pass pitch, shown only while a generation is
		-- actually sitting in the queue and the player has no pass banked --
		-- the real moment of friction, not a generic pitch buried in
		-- Settings. Framed around the NEXT submission (a pass here can't
		-- retroactively speed up a job already queued -- queue time is
		-- fixed at submission, see GenerationService._Prepare), which is
		-- both the honest framing and the one that matches what buying a
		-- pass from this exact button actually does.
		local upsell = Factory.New("Frame", {
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -32, 0, 38),
			BackgroundColor3 = Colors.Gold,
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			Parent = activity,
		})
		Factory.Corner(upsell, 10)
		Factory.Stroke(upsell, Colors.Gold, 0.5, 1)
		Factory.Label(
			upsell,
			"⚡ Tired of the wait? Stock a Priority Pass for your next one.",
			UDim2.new(1, -140, 1, 0),
			{
				Position = UDim2.fromOffset(12, 0),
				Color = Colors.Gold,
				Font = Theme.Fonts.Medium,
				TextSize = 11,
				Wrapped = true,
			}
		)
		local upsellButton = Factory.New("TextButton", {
			Size = UDim2.fromOffset(112, 26),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			BackgroundColor3 = Colors.Gold,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "Get a pass",
			TextColor3 = Colors.Ink,
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			Parent = upsell,
		})
		Factory.Corner(upsellButton, 13)
		self:_BindButton(upsellButton)
		upsellButton.Activated:Connect(function()
			self:_BuyPriorityPass()
		end)
	end
	if shown == 0 then
		Factory.Label(
			activity,
			"Your next generation will appear here with live pipeline progress.",
			UDim2.new(1, -32, 0, 70),
			{
				Position = UDim2.fromOffset(16, 62),
				Color = Colors.TextMuted,
				TextSize = 13,
				Wrapped = true,
				AlignX = Enum.TextXAlignment.Center,
			}
		)
	end

	local brief = self.state.dailyBrief
	if brief then
		local hasMilestoneBanner = brief.milestoneReward ~= nil
		local cardHeight = 156 + (if hasMilestoneBanner then 36 else 0)
		local daily = Factory.Card(stack, UDim2.new(1, 0, 0, cardHeight), nil, "DailyBrief")
		daily.LayoutOrder = 5

		-- Flame badge: the same streak iconography as the status-bar pill,
		-- now with its own gradient + stroke instead of a flat text pill.
		local flame = Factory.New("Frame", {
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Colors.Rose,
			BorderSizePixel = 0,
			Parent = daily,
		})
		Factory.Corner(flame, 22)
		Factory.Gradient(flame, { Colors.Rose, Colors.Gold }, 135)
		Factory.Stroke(flame, Colors.Ink, 0.3, 1.5)
		Factory.Label(flame, "🔥", UDim2.fromScale(1, 1), {
			TextSize = 20,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
		})

		Factory.Label(daily, string.format("%d-day streak", brief.streak), UDim2.new(1, -76, 0, 24), {
			Position = UDim2.fromOffset(72, 14),
			Font = Theme.Fonts.Black,
			TextSize = 18,
		})
		Factory.Label(daily, brief.theme, UDim2.new(1, -76, 0, 18), {
			Position = UDim2.fromOffset(72, 38),
			Color = Colors.TextMuted,
			TextSize = 12,
			Truncate = Enum.TextTruncate.AtEnd,
		})

		local briefY = 68
		if hasMilestoneBanner then
			local milestone = brief.milestoneReward
			local banner = Factory.New("Frame", {
				Position = UDim2.fromOffset(15, briefY),
				Size = UDim2.new(1, -30, 0, 28),
				BackgroundColor3 = Colors.Gold,
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				Parent = daily,
			})
			Factory.Corner(banner, 8)
			Factory.Stroke(banner, Colors.Gold, 0.4, 1)
			Factory.Label(
				banner,
				string.format(
					"🏆 %d-day milestone! +%d Forge Tokens · +%d Priority Pass%s",
					milestone.day,
					milestone.tokens,
					milestone.priorityPasses,
					if milestone.priorityPasses == 1 then "" else "es"
				),
				UDim2.new(1, -20, 1, 0),
				{
					Position = UDim2.fromOffset(10, 0),
					Font = Theme.Fonts.Bold,
					Color = Colors.Gold,
					TextSize = 12,
					AlignX = Enum.TextXAlignment.Center,
				}
			)
			briefY += 36
		end

		-- A real journey bar toward the next streak milestone (7/14/30, then
		-- every 30 days after), not just the existing "next check-in" line --
		-- that's the reward worth building visible anticipation for.
		local lastMilestoneDay = if brief.nextMilestoneDay <= 7
			then 0
			elseif brief.nextMilestoneDay <= 30 then brief.nextMilestoneDay - 7
			else brief.nextMilestoneDay - Config.Retention.StreakMilestoneRepeatDay
		local span = math.max(1, brief.nextMilestoneDay - lastMilestoneDay)
		local progress = math.clamp((brief.streak - lastMilestoneDay) / span, 0, 1)

		local track = Factory.New("Frame", {
			Position = UDim2.fromOffset(15, briefY),
			Size = UDim2.new(1, -76, 0, 10),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Parent = daily,
		})
		Factory.Corner(track, 5)
		local fill = Factory.New("Frame", {
			Size = UDim2.new(progress, 0, 1, 0),
			BackgroundColor3 = Colors.Gold,
			BorderSizePixel = 0,
			Parent = track,
		})
		Factory.Corner(fill, 5)
		Factory.Gradient(fill, { Colors.Rose, Colors.Gold }, 0)
		local flag = Factory.New("Frame", {
			Size = UDim2.fromOffset(38, 20),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 8, 0.5, 0),
			BackgroundColor3 = Colors.PanelSoft,
			BorderSizePixel = 0,
			Parent = track,
		})
		Factory.Corner(flag, 6)
		Factory.Stroke(flag, Colors.Gold, 0.5, 1)
		Factory.Label(flag, string.format("D%d", brief.nextMilestoneDay), UDim2.fromScale(1, 1), {
			Font = Theme.Fonts.Bold,
			TextSize = 10,
			Color = Colors.Gold,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
		})
		briefY += 20

		Factory.Label(
			daily,
			string.format(
				"Priority pass in %d check-in%s · milestone reward at day %d",
				brief.nextRewardIn,
				if brief.nextRewardIn == 1 then "" else "s",
				brief.nextMilestoneDay
			),
			UDim2.new(1, -30, 0, 18),
			{
				Position = UDim2.fromOffset(15, briefY),
				Color = Colors.TextMuted,
				TextSize = 11,
			}
		)
		briefY += 24

		Factory.Label(
			daily,
			"Use the theme as inspiration—or forge anything you can imagine.",
			UDim2.new(1, -30, 0, 20),
			{
				Position = UDim2.fromOffset(15, briefY),
				Color = Colors.TextMuted,
				TextSize = 12,
			}
		)
	end

	local questState = self.state.questState
	if questState then
		local quests = Config.Retention.Quests
		local questsDone = questState.questsDone or {}
		local doneCount = 0
		for _, quest in quests do
			if questsDone[quest.key] then
				doneCount += 1
			end
		end
		local allDone = doneCount >= #quests
		local cardHeight = #quests * 46 + (if allDone then 104 else 46)
		local questCard = Factory.Card(stack, UDim2.new(1, 0, 0, cardHeight), nil, "DailyQuests")
		questCard.LayoutOrder = 6
		Factory.Label(questCard, "DAILY QUESTS", UDim2.new(1, -100, 0, 20), {
			Position = UDim2.fromOffset(16, 13),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Mint,
		})
		Factory.Label(questCard, string.format("%d / %d", doneCount, #quests), UDim2.fromOffset(70, 20), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 13),
			AlignX = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.Black,
			Color = if allDone then Colors.Gold else Colors.TextMuted,
			TextSize = 12,
		})

		local qy = 40
		for _, quest in quests do
			local done = questsDone[quest.key] == true
			local row = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, qy),
				Size = UDim2.new(1, -32, 0, 38),
				BackgroundColor3 = if done then Colors.Mint else Colors.Ink,
				BackgroundTransparency = if done then 0.85 else 0.25,
				BorderSizePixel = 0,
				Parent = questCard,
			})
			Factory.Corner(row, 10)
			if done then
				Factory.Stroke(row, Colors.Mint, 0.5, 1)
			end

			local badge = Factory.New("Frame", {
				Size = UDim2.fromOffset(28, 28),
				Position = UDim2.fromOffset(5, 5),
				BackgroundColor3 = if done then Colors.Mint else Colors.PanelSoft,
				BorderSizePixel = 0,
				Parent = row,
			})
			Factory.Corner(badge, 14)
			Factory.Label(badge, if done then "✓" else quest.icon, UDim2.fromScale(1, 1), {
				TextSize = if done then 14 else 13,
				Color = if done then Colors.Ink else Colors.Text,
				Font = Theme.Fonts.Black,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
			})

			Factory.Label(row, quest.label, UDim2.new(1, -110, 1, 0), {
				Position = UDim2.fromOffset(42, 0),
				Font = if done then Theme.Fonts.Medium else Theme.Fonts.Regular,
				Color = if done then Colors.Text else Colors.TextMuted,
				TextSize = 12,
				Truncate = Enum.TextTruncate.AtEnd,
			})
			Factory.Label(row, string.format("+%d", quest.tokens), UDim2.fromOffset(50, 38), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				AlignX = Enum.TextXAlignment.Right,
				AlignY = Enum.TextYAlignment.Center,
				Font = Theme.Fonts.Bold,
				Color = if done then Colors.Mint else Colors.TextMuted,
				TextSize = 12,
			})

			if
				self.questJustCompleted == quest.key
				and not (self.state.profile.settings and self.state.profile.settings.reduceMotion)
			then
				local pop = Factory.New("UIScale", { Scale = 0.9, Parent = row })
				TweenService
					:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
					:Play()
			end

			qy += 46
		end

		if allDone then
			local banner = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, qy),
				Size = UDim2.new(1, -32, 0, 50),
				BackgroundColor3 = Colors.Gold,
				BackgroundTransparency = 0.82,
				BorderSizePixel = 0,
				Parent = questCard,
			})
			Factory.Corner(banner, 8)
			Factory.Stroke(banner, Colors.Gold, 0.4, 1)
			Factory.Label(
				banner,
				string.format("🏆 All quests cleared! +%d bonus tokens", Config.Retention.QuestClearBonusTokens),
				UDim2.new(1, -20, 0, 16),
				{
					Position = UDim2.fromOffset(10, 6),
					Font = Theme.Fonts.Bold,
					Color = Colors.Gold,
					TextSize = 12,
					AlignX = Enum.TextXAlignment.Center,
				}
			)
			-- A quest-clear day is a genuine high point -- the natural,
			-- non-pushy moment to surface the same invite prompt Settings
			-- already offers, since a player enjoying the studio enough to
			-- clear every quest is the one most likely to say yes.
			local inviteRow = Factory.New("TextButton", {
				Size = UDim2.fromOffset(150, 22),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 24),
				BackgroundColor3 = Colors.Gold,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "👥 Invite a friend",
				TextColor3 = Colors.Ink,
				Font = Theme.Fonts.Bold,
				TextSize = 11,
				Parent = banner,
			})
			Factory.Corner(inviteRow, 11)
			self:_BindButton(inviteRow)
			inviteRow.Activated:Connect(function()
				self:_PromptFriendInvite()
			end)
		end
	end
	self.questJustCompleted = nil
end

function App:_RenderStudio()
	self:_PageHeader("My Studio", "Fit, equip, share, list, or publish every original and personal copy you own.")
	local profile = self.state.profile
	if #profile.itemOrder == 0 then
		local empty = Factory.Card(self.content, UDim2.new(0.95, 0, 0, 260), UDim2.new(0.025, 0, 0, 112))
		Factory.Label(empty, "◇", UDim2.new(1, 0, 0, 70), {
			Position = UDim2.fromOffset(0, 34),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 50,
			Color = Colors.Violet,
		})
		Factory.Label(empty, "Your collection starts with an idea.", UDim2.new(1, -40, 0, 34), {
			Position = UDim2.fromOffset(20, 112),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 20,
		})
		local create = Factory.Button(
			empty,
			"Create your first accessory",
			UDim2.fromOffset(220, 44),
			UDim2.new(0.5, -110, 0, 170),
			"primary"
		)
		self:_BindButton(create)
		create.Activated:Connect(function()
			self:_OpenPage("Create")
		end)
		return
	end
	if not self.selectedItemId or not profile.items[self.selectedItemId] then
		self.selectedItemId = profile.itemOrder[1]
	end
	local selected = profile.items[self.selectedItemId]

	local collection = if self.compact
		then Factory.Card(self.content, UDim2.new(0.95, 0, 0, 164), UDim2.new(0.025, 0, 0, 100), "Collection")
		else Factory.Card(self.content, UDim2.new(0.39, 0, 1, -118), UDim2.new(0.02, 0, 0, 100), "Collection")
	Factory.Label(collection, string.format("COLLECTION · %d", #profile.itemOrder), UDim2.new(1, -28, 0, 30), {
		Position = UDim2.fromOffset(14, 12),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.Cyan,
	})
	local itemScroll = Factory.New("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 48),
		Size = UDim2.new(1, -24, 1, -60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Violet,
		Parent = collection,
	})
	Factory.ScalePadding(itemScroll, 0.008, 0.008)
	local itemStack = Factory.New("Frame", {
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = itemScroll,
	})
	Factory.List(itemStack, Enum.FillDirection.Vertical, 8)
	for index, itemId in profile.itemOrder do
		local item = profile.items[itemId]
		if item then
			local row = Factory.New("TextButton", {
				Size = UDim2.new(1, 0, 0, 82),
				BackgroundColor3 = if itemId == self.selectedItemId then Color3.fromRGB(66, 58, 112) else Colors.Ink,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				Parent = itemStack,
			})
			Factory.Corner(row, 11)
			Factory.Stroke(
				row,
				if itemId == self.selectedItemId then Colors.Violet else Colors.Line,
				if itemId == self.selectedItemId then 0.2 else 0.62
			)
			local image = Factory.New("ImageLabel", {
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.fromOffset(9, 9),
				BackgroundColor3 = Colors.Panel,
				BorderSizePixel = 0,
				Image = thumbnail(item.thumbnailAssetId, 150),
				ScaleType = Enum.ScaleType.Crop,
				Parent = row,
			})
			Factory.Corner(image, 9)
			if table.find(profile.equippedItemIds or {}, itemId) then
				local badge = Factory.New("TextLabel", {
					Size = UDim2.fromOffset(20, 20),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromOffset(83, 3),
					BackgroundColor3 = Colors.Mint,
					BorderSizePixel = 0,
					Text = "✓",
					TextColor3 = Colors.Ink,
					Font = Theme.Fonts.Black,
					TextSize = 13,
					Parent = row,
				})
				Factory.Corner(badge, 99)
				Factory.Stroke(badge, Color3.fromRGB(14, 19, 38), 0, 2)
			end
			Factory.Label(row, item.name, UDim2.new(1, -168, 0, 27), {
				Position = UDim2.fromOffset(86, 12),
				Font = Theme.Fonts.Bold,
				TextSize = 13,
				Truncate = Enum.TextTruncate.AtEnd,
			})
			Factory.Label(
				row,
				if item.license == "PERSONAL_COPY" then "PERSONAL COPY · NO RESALE" else string.upper(item.visibility),
				UDim2.new(1, -168, 0, 24),
				{
					Position = UDim2.fromOffset(86, 40),
					Color = if item.license == "PERSONAL_COPY" then Colors.Gold else Colors.TextMuted,
					Font = Theme.Fonts.Bold,
					TextSize = 10,
					Truncate = Enum.TextTruncate.AtEnd,
				}
			)
			Factory.Label(row, "›", UDim2.fromOffset(26, 82), {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				AlignX = Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = 24,
				Color = Colors.TextMuted,
			})
			self:_BindButton(row)
			row.Activated:Connect(function()
				self.selectedItemId = itemId
				self:_RenderActivePage()
			end)
		end
	end

	local inspector = if self.compact
		then Factory.Card(self.content, UDim2.new(0.95, 0, 1, -284), UDim2.new(0.025, 0, 0, 274), "Inspector")
		else Factory.Card(self.content, UDim2.new(0.56, 0, 1, -118), UDim2.new(0.42, 0, 0, 100), "Inspector")
	local inspectScroll = Factory.New("ScrollingFrame", {
		Size = UDim2.new(1, -12, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Cyan,
		Parent = inspector,
	})
	Factory.ScalePadding(inspectScroll, 0.006, 0.006)
	local body = Factory.New("Frame", {
		Size = UDim2.new(1, -8, 0, 1240),
		BackgroundTransparency = 1,
		Parent = inspectScroll,
	})
	Factory.Label(body, selected.name, UDim2.new(1, -32, 0, 32), {
		Position = UDim2.fromOffset(16, 10),
		Font = Theme.Fonts.Black,
		TextSize = 20,
		Truncate = Enum.TextTruncate.AtEnd,
	})
	Factory.Pill(
		body,
		if selected.license == "PERSONAL_COPY" then "PERSONAL COPY" else "ORIGINAL",
		if selected.license == "PERSONAL_COPY" then Colors.Gold else Colors.Mint,
		106
	).Position =
		UDim2.fromOffset(16, 47)
	Factory.Pill(
		body,
		string.format(
			"%s · %s",
			string.gsub(selected.stylePreset or "AUTO", "_", " "),
			string.gsub(selected.detailLevel or "BALANCED", "_", " ")
		),
		Colors.Violet,
		164
	).Position =
		UDim2.fromOffset(132, 47)
	local viewport = Factory.New("ViewportFrame", {
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.new(1, -32, 0, 292),
		BackgroundColor3 = Color3.fromRGB(62, 72, 108),
		BorderSizePixel = 0,
		Parent = body,
	})
	Factory.Corner(viewport, 14)
	Factory.Stroke(viewport, Colors.Violet, 0.45)
	local controller = ViewportController.new(viewport)
	self.activeViewport = controller
	local orbitHint = Factory.Pill(viewport, "DRAG ORBIT · RIGHT/SHIFT DRAG PAN", Colors.Cyan, 234)
	orbitHint.Position = UDim2.fromOffset(12, 12)
	orbitHint.ZIndex = 5
	local zoomHint = Factory.Pill(viewport, "WHEEL ZOOM", Colors.Violet, 92)
	zoomHint.Position = UDim2.fromOffset(12, 43)
	zoomHint.ZIndex = 5
	local resetCamera = Factory.Button(viewport, "↺", UDim2.fromOffset(38, 34), UDim2.new(1, -50, 0, 10), nil)
	resetCamera.Name = "ResetCamera"
	resetCamera.TextSize = 18
	resetCamera.ZIndex = 5
	self:_BindButton(resetCamera)
	resetCamera.Activated:Connect(function()
		controller:ResetCamera()
	end)

	if not self.fitDrafts[selected.id] then
		self.fitDrafts[selected.id] = deepCopy(selected.fit)
	end
	local fit = self.fitDrafts[selected.id]
	task.spawn(function()
		local version = self.pageVersion
		local success, data = self:_Invoke(Network.Actions.RequestPrivateModel, { itemId = selected.id })
		if success and version == self.pageVersion and viewport.Parent then
			local cache = player.PlayerGui:WaitForChild("ForgeAssetCache", 8)
			local model = cache and cache:WaitForChild(data.cacheName, 8)
			if model and model:IsA("Model") then
				controller:SetAccessory(model, fit)
			end
		end
	end)

	local controls = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, 392),
		Size = UDim2.new(1, -32, 0, 414),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = body,
	})
	Factory.Corner(controls, 13)
	Factory.Stroke(controls, Colors.Line, 0.5)
	Factory.Label(controls, "FIT CONTROLS", UDim2.new(0.5, -14, 0, 24), {
		Position = UDim2.fromOffset(14, 10),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.Cyan,
	})
	Factory.Label(controls, "Drag a dial or tap − / +", UDim2.new(0.5, -24, 0, 24), {
		Position = UDim2.new(0.5, 8, 0, 10),
		AlignX = Enum.TextXAlignment.Right,
		Color = Colors.TextMuted,
		TextSize = 10,
	})

	local function sliderRow(field: string, axis: string, y: number, minimum: number, maximum: number, step: number)
		Factory.Label(controls, string.upper(axis), UDim2.new(0.06, 0, 0, 28), {
			Position = UDim2.new(0.015, 0, 0, y),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			Color = if axis == "x" then Colors.Rose elseif axis == "y" then Colors.Mint else Colors.Cyan,
		})
		local minus = Factory.Button(controls, "−", UDim2.new(0.075, -4, 0, 28), UDim2.new(0.08, 0, 0, y), nil)
		Factory.New("UISizeConstraint", { MinSize = Vector2.new(26, 28), Parent = minus })
		local track = Factory.New("TextButton", {
			Position = UDim2.new(0.17, 0, 0, y + 4),
			Size = UDim2.new(0.55, 0, 0, 20),
			BackgroundColor3 = Colors.PanelSoft,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = controls,
		})
		Factory.Corner(track, 99)
		local fill = Factory.New("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Colors.Violet,
			BorderSizePixel = 0,
			Parent = track,
		})
		Factory.Corner(fill, 99)
		Factory.Gradient(fill, { Colors.Violet, Colors.Cyan }, 0)
		local knob = Factory.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = Color3.fromRGB(248, 250, 255),
			BorderSizePixel = 0,
			Parent = track,
		})
		Factory.Corner(knob, 99)
		Factory.Stroke(knob, Colors.Cyan, 0.15)
		local plus = Factory.Button(controls, "+", UDim2.new(0.075, -4, 0, 28), UDim2.new(0.735, 0, 0, y), nil)
		Factory.New("UISizeConstraint", { MinSize = Vector2.new(26, 28), Parent = plus })
		local valueLabel = Factory.Label(controls, "", UDim2.new(0.17, -10, 0, 28), {
			Position = UDim2.new(0.82, 0, 0, y),
			AlignX = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			Color = Colors.Text,
		})

		local function refresh()
			local value = fit[field][axis]
			local alpha = math.clamp((value - minimum) / (maximum - minimum), 0, 1)
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.fromScale(alpha, 0.5)
			if field == "rotation" then
				valueLabel.Text = string.format("%d°", math.floor(value + 0.5))
			elseif field == "scale" then
				valueLabel.Text = string.format("%.2f×", value)
			else
				valueLabel.Text = string.format("%.2f", value)
			end
		end
		local function setValue(rawValue: number)
			local steps = math.floor(((rawValue - minimum) / step) + 0.5)
			local value = math.clamp(minimum + steps * step, minimum, maximum)
			if math.abs(value) < step * 0.25 then
				value = 0
			end
			fit[field][axis] = value
			refresh()
			controller:ApplyFit(fit)
		end
		local function setFromPointer(pointerX: number)
			if track.AbsoluteSize.X <= 0 then
				return
			end
			local alpha = math.clamp((pointerX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			setValue(minimum + (maximum - minimum) * alpha)
		end

		local dragging = false
		local dragTouch = nil :: InputObject?
		track.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				dragTouch = if input.UserInputType == Enum.UserInputType.Touch then input else nil
				setFromPointer(input.Position.X)
			end
		end)
		table.insert(
			self.pageConnections,
			UserInputService.InputChanged:Connect(function(input: InputObject)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragTouch) then
					setFromPointer(input.Position.X)
				end
			end)
		)
		table.insert(
			self.pageConnections,
			UserInputService.InputEnded:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragTouch then
					dragging = false
					dragTouch = nil
				end
			end)
		)
		minus.Activated:Connect(function()
			setValue(fit[field][axis] - step)
		end)
		plus.Activated:Connect(function()
			setValue(fit[field][axis] + step)
		end)
		self:_BindButton(minus)
		self:_BindButton(plus)
		refresh()
	end

	local dialY = 64
	for _, group in
		{
			{
				title = "POSITION",
				field = "position",
				minimum = Config.Fitting.Position.Minimum,
				maximum = Config.Fitting.Position.Maximum,
				step = Config.Fitting.Position.Step,
			},
			{
				title = "ROTATION",
				field = "rotation",
				minimum = Config.Fitting.Rotation.Minimum,
				maximum = Config.Fitting.Rotation.Maximum,
				step = Config.Fitting.Rotation.Step,
			},
			{
				title = "SCALE",
				field = "scale",
				minimum = Config.Fitting.Scale.Minimum,
				maximum = Config.Fitting.Scale.Maximum,
				step = Config.Fitting.Scale.Step,
			},
		}
	do
		Factory.Label(controls, group.title, UDim2.new(1, -28, 0, 20), {
			Position = UDim2.fromOffset(14, dialY - 22),
			Font = Theme.Fonts.Bold,
			TextSize = 10,
			Color = Colors.TextMuted,
		})
		for _, axis in { "x", "y", "z" } do
			sliderRow(group.field, axis, dialY, group.minimum, group.maximum, group.step)
			dialY += 30
		end
		dialY += 23
	end

	-- Fit presets: save the current position/rotation/scale under a name so it
	-- can be reapplied later, without touching whatever fit is currently being
	-- drafted for a different item.
	local presetsY = 822
	local presetsHeight = 140
	local presets = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, presetsY),
		Size = UDim2.new(1, -32, 0, presetsHeight),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = body,
	})
	Factory.Corner(presets, 13)
	Factory.Stroke(presets, Colors.Line, 0.5)
	Factory.Label(presets, "FIT PRESETS", UDim2.new(1, -28, 0, 18), {
		Position = UDim2.fromOffset(14, 10),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.Cyan,
	})
	Factory.Label(
		presets,
		"Save this fit to reuse later while you customize a different item.",
		UDim2.new(1, -28, 0, 14),
		{
			Position = UDim2.fromOffset(14, 30),
			Color = Colors.TextMuted,
			TextSize = 10,
			Truncate = Enum.TextTruncate.AtEnd,
		}
	)
	local presetNameBox =
		self:_TextBox(presets, "Name this fit", UDim2.new(1, -122, 0, 32), UDim2.fromOffset(14, 52), false)
	local savePresetButton =
		Factory.Button(presets, "Save preset", UDim2.fromOffset(96, 32), UDim2.new(1, -110, 0, 52), "mint")
	self:_BindButton(savePresetButton)
	savePresetButton.Activated:Connect(function()
		savePresetButton.Active = false
		task.spawn(function()
			local success, data = self:_Invoke(Network.Actions.SaveFitPreset, {
				name = presetNameBox.Text,
				accessoryType = fit.accessoryType,
				fit = fit,
			})
			if success then
				self.state.profile.fitPresets[data.preset.id] = data.preset
				table.insert(self.state.profile.fitPresetOrder, data.preset.id)
				self.sounds:Play("Success")
				self:_Toast("success", "Fit preset saved.")
				self:_RenderActivePage()
				return
			end
			if savePresetButton.Parent then
				savePresetButton.Active = true
			end
		end)
	end)
	local presetList = Factory.New("ScrollingFrame", {
		Position = UDim2.fromOffset(14, 92),
		Size = UDim2.new(1, -28, 0, presetsHeight - 100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Cyan,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = presets,
	})
	Factory.List(presetList, Enum.FillDirection.Horizontal, 8)
	local presetOrder = profile.fitPresetOrder or {}
	if #presetOrder == 0 then
		Factory.Label(presetList, "No saved presets yet.", UDim2.fromOffset(220, 30), {
			AlignY = Enum.TextYAlignment.Center,
			Color = Colors.TextMuted,
			TextSize = 11,
		})
	else
		for _, presetId in presetOrder do
			local preset = profile.fitPresets[presetId]
			if preset then
				local nameWidth = math.clamp(#preset.name * 7 + 40, 90, 150)
				local chip = Factory.New("Frame", {
					Size = UDim2.fromOffset(nameWidth + 34, 30),
					BackgroundTransparency = 1,
					Parent = presetList,
				})
				local apply = Factory.Button(
					chip,
					preset.name,
					UDim2.fromOffset(nameWidth, 30),
					UDim2.fromOffset(0, 0),
					if preset.accessoryType == fit.accessoryType then "primary" else nil
				)
				apply.TextTruncate = Enum.TextTruncate.AtEnd
				self:_BindButton(apply)
				apply.Activated:Connect(function()
					fit.position = deepCopy(preset.fit.position)
					fit.rotation = deepCopy(preset.fit.rotation)
					fit.scale = deepCopy(preset.fit.scale)
					self:_Track({ event = "FitPresetApplied", fields = {} })
					self:_RenderActivePage()
				end)
				local remove =
					Factory.Button(chip, "×", UDim2.fromOffset(26, 30), UDim2.fromOffset(nameWidth + 8, 0), "danger")
				self:_BindButton(remove)
				remove.Activated:Connect(function()
					task.spawn(function()
						local success = self:_Invoke(Network.Actions.DeleteFitPreset, { presetId = presetId })
						if success then
							self.state.profile.fitPresets[presetId] = nil
							local index = table.find(self.state.profile.fitPresetOrder, presetId)
							if index then
								table.remove(self.state.profile.fitPresetOrder, index)
							end
							self:_RenderActivePage()
						end
					end)
				end)
			end
		end
	end

	local actionsY = presetsY + presetsHeight + 16
	local isEquipped = table.find(profile.equippedItemIds or {}, selected.id) ~= nil
	local save =
		Factory.Button(body, "Save fit", UDim2.new(0.25, -22, 0, 42), UDim2.fromOffset(16, actionsY), "primary")
	local equip = Factory.Button(
		body,
		if isEquipped then "Unequip" else "Equip in game",
		UDim2.new(0.25, -12, 0, 42),
		UDim2.new(0.25, 6, 0, actionsY),
		if isEquipped then "danger" else "mint"
	)
	local publish = Factory.Button(
		body,
		if selected.publishedAssetId then "Published ✓" else "Publish wearable",
		UDim2.new(0.25, -12, 0, 42),
		UDim2.new(0.5, 6, 0, actionsY),
		nil
	)
	local resetFit =
		Factory.Button(body, "↺ Reset fit", UDim2.new(0.25, -22, 0, 42), UDim2.new(0.75, 6, 0, actionsY), nil)
	for _, button in { save, equip, publish, resetFit } do
		self:_BindButton(button)
	end
	publish.Active = not selected.publishedAssetId
	local function saveCurrentFit(): (boolean, any)
		local success, data = self:_Invoke(Network.Actions.SaveFit, { itemId = selected.id, fit = fit })
		if success then
			self.state.profile.items[selected.id] = data.item
			self.sounds:Play("Success")
		end
		return success, data
	end
	save.Activated:Connect(function()
		save.Active = false
		save.Text = "Saving…"
		task.spawn(function()
			saveCurrentFit()
			if save.Parent then
				save.Active = true
				save.Text = "Save fit"
			end
		end)
	end)
	equip.Activated:Connect(function()
		equip.Active = false
		if isEquipped then
			equip.Text = "Removing…"
			task.spawn(function()
				local success = self:_Invoke(Network.Actions.UnequipItem, { itemId = selected.id })
				if success then
					local index = table.find(self.state.profile.equippedItemIds, selected.id)
					if index then
						table.remove(self.state.profile.equippedItemIds, index)
					end
					self:_Toast("success", "Unequipped.")
					self:_RenderActivePage()
					return
				end
				if equip.Parent then
					equip.Active = true
					equip.Text = "Unequip"
				end
			end)
		else
			equip.Text = "Applying fit…"
			task.spawn(function()
				local saved = saveCurrentFit()
				if saved then
					local success = self:_Invoke(Network.Actions.EquipItem, { itemId = selected.id })
					if success then
						if not table.find(self.state.profile.equippedItemIds, selected.id) then
							table.insert(self.state.profile.equippedItemIds, selected.id)
						end
						self:_Toast("success", "Equipped on your in-game avatar.")
						self:_RenderActivePage()
						return
					end
				end
				if equip.Parent then
					equip.Active = true
					equip.Text = "Equip in game"
				end
			end)
		end
	end)
	publish.Activated:Connect(function()
		publish.Active = false
		publish.Text = "Preparing wearable…"
		task.spawn(function()
			local saved = saveCurrentFit()
			if saved then
				local success, data = self:_Invoke(Network.Actions.PublishItem, { itemId = selected.id })
				if success then
					self.state.profile.items[selected.id].publishedAssetId = data.assetId
					self:_Toast("success", "Your wearable was published to Roblox.")
					self:_RenderActivePage()
					return
				end
			end
			if publish.Parent then
				publish.Active = true
				publish.Text = "Publish wearable"
			end
		end)
	end)
	resetFit.Activated:Connect(function()
		resetFit.Active = false
		resetFit.Text = "Resetting…"
		task.spawn(function()
			local success, data = self:_Invoke(Network.Actions.ResetFitToSuggested, { itemId = selected.id })
			if success then
				self.state.profile.items[selected.id] = data.item
				self.fitDrafts[selected.id] = deepCopy(data.item.fit)
				if self.activeViewport then
					self.activeViewport:ApplyFit(self.fitDrafts[selected.id])
				end
				self.sounds:Play("Success")
				self:_RenderActivePage()
				return
			end
			if resetFit.Parent then
				resetFit.Active = true
				resetFit.Text = "↺ Reset fit"
			end
		end)
	end)
	local noteY = actionsY + 50
	Factory.Label(
		body,
		"Publishing opens Roblox's creation prompt and can have a separate token price.",
		UDim2.new(1, -32, 0, 16),
		{
			Position = UDim2.fromOffset(16, noteY),
			Color = Colors.TextMuted,
			TextSize = 10,
			Truncate = Enum.TextTruncate.AtEnd,
		}
	)

	local socialY = noteY + 26
	local social = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, socialY),
		Size = UDim2.new(1, -32, 0, 154),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = body,
	})
	Factory.Corner(social, 12)
	Factory.Stroke(social, Colors.Line, 0.55)
	if selected.license == "PERSONAL_COPY" then
		Factory.Label(social, "PERSONAL LICENSE", UDim2.new(1, -28, 0, 25), {
			Position = UDim2.fromOffset(14, 14),
			Font = Theme.Fonts.Bold,
			Color = Colors.Gold,
			TextSize = 11,
		})
		Factory.Label(
			social,
			"You can fit, equip, and publish this copy as a wearable. It can never be listed or resold in Forge.",
			UDim2.new(1, -28, 0, 72),
			{
				Position = UDim2.fromOffset(14, 45),
				Color = Colors.TextMuted,
				TextSize = 12,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
	else
		Factory.Label(social, "SHARING & SALES", UDim2.new(1, -28, 0, 25), {
			Position = UDim2.fromOffset(14, 10),
			Font = Theme.Fonts.Bold,
			Color = Colors.Rose,
			TextSize = 11,
		})
		local visibility = Factory.Button(
			social,
			if selected.visibility == "PUBLIC" then "Private" else "Share",
			if self.compact then UDim2.new(0.31, -8, 0, 38) else UDim2.fromOffset(132, 38),
			UDim2.fromOffset(14, 42),
			nil
		)
		self:_BindButton(visibility)
		visibility.Activated:Connect(function()
			task.spawn(function()
				local success, data = self:_Invoke(Network.Actions.SetVisibility, {
					itemId = selected.id,
					isPublic = selected.visibility ~= "PUBLIC",
				})
				if success then
					self.state.profile.items[selected.id] = data.item
					self:_RenderActivePage()
				end
			end)
		end)
		local priceBox = self:_TextBox(
			social,
			"R$ 10–500",
			if self.compact then UDim2.new(0.31, -8, 0, 38) else UDim2.fromOffset(118, 38),
			if self.compact then UDim2.new(0.31, 12, 0, 42) else UDim2.fromOffset(156, 42),
			false
		)
		priceBox.Text = tostring(selected.listingPriceRobux or 50)
		priceBox.TextXAlignment = Enum.TextXAlignment.Center
		local list = Factory.Button(
			social,
			if selected.isListed then "End listing" else "List for sale",
			if self.compact then UDim2.new(0.38, -24, 0, 38) else UDim2.fromOffset(126, 38),
			if self.compact then UDim2.new(0.62, 10, 0, 42) else UDim2.fromOffset(284, 42),
			"primary"
		)
		self:_BindButton(list)
		list.Activated:Connect(function()
			task.spawn(function()
				local success, data = self:_Invoke(Network.Actions.SetListing, {
					itemId = selected.id,
					isListed = not selected.isListed,
					priceRobux = tonumber(priceBox.Text),
				})
				if success then
					self.state.profile.items[selected.id] = data.item
					self:_RenderActivePage()
				end
			end)
		end)
		local transferNote = Factory.Label(
			social,
			string.format(
				"Seller receives 90%% (about R$ %d). Buyers need Plus; public try-ons remain free even when not for sale.",
				math.floor((tonumber(priceBox.Text) or 50) * Config.Marketplace.SellerShare)
			),
			UDim2.new(1, -28, 0, 50),
			{
				Position = UDim2.fromOffset(14, 91),
				Color = Colors.TextMuted,
				TextSize = 11,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
		priceBox.FocusLost:Connect(function()
			local entered = math.clamp(math.floor(tonumber(priceBox.Text) or 50), 10, 500)
			priceBox.Text = tostring(entered)
			transferNote.Text = string.format(
				"Seller receives 90%% (about R$ %d). Buyers need Plus; public try-ons remain free even when not for sale.",
				math.floor(entered * Config.Marketplace.SellerShare)
			)
		end)
	end
end

function App:_RefreshMarketplace(query: string?)
	self.marketplaceQuery = query or self.marketplaceQuery or ""
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.GetMarketplace, {
			query = self.marketplaceQuery,
			searchBy = self.marketplaceSearchBy,
			sortBy = self.marketplaceSortBy,
		})
		if success then
			self.marketplaceItems = data.items
			if self.activePage == "Discover" then
				self:_RenderActivePage()
			end
		end
	end)
end

function App:_RenderDiscover()
	self:_PageHeader(
		"Discover",
		"Try on every public design for free. Like, favorite, and support creators through verified Plus transfers."
	)
	if not self.state.policy.contentSharingAllowed then
		local blocked = Factory.Card(self.content, UDim2.new(0.95, 0, 0, 230), UDim2.new(0.025, 0, 0, 112))
		Factory.Label(blocked, "Shared creations are unavailable", UDim2.new(1, -40, 0, 38), {
			Position = UDim2.fromOffset(20, 38),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 22,
		})
		Factory.Label(
			blocked,
			"Forge respects Roblox PolicyService. Your private studio remains available, but community sharing is hidden for this account.",
			UDim2.new(1, -70, 0, 70),
			{
				Position = UDim2.fromOffset(35, 88),
				AlignX = Enum.TextXAlignment.Center,
				Color = Colors.TextMuted,
				TextSize = 13,
				Wrapped = true,
			}
		)
		return
	end
	local tools = Factory.New("Frame", {
		Position = UDim2.new(0.025, 0, 0, 96),
		Size = UDim2.new(0.95, 0, 0, if self.compact then 98 else 48),
		BackgroundTransparency = 1,
		Parent = self.content,
	})
	local search = self:_TextBox(
		tools,
		if self.marketplaceSearchBy == "CREATOR" then "Search by creator username" else "Search public designs",
		if self.compact then UDim2.new(1, 0, 0, 42) else UDim2.new(1, -232, 0, 42),
		UDim2.new(),
		false
	)
	search.Text = self.marketplaceQuery
	local refresh = Factory.Button(
		tools,
		"Search",
		if self.compact then UDim2.new(0.5, -5, 0, 40) else UDim2.fromOffset(96, 42),
		if self.compact then UDim2.fromOffset(0, 50) else UDim2.new(1, -216, 0, 0),
		"primary"
	)
	local plus = Factory.Button(
		tools,
		if self.state.benefits.plusSubscriber then "Plus active ✓" else "Get Roblox Plus",
		if self.compact then UDim2.new(0.5, -5, 0, 40) else UDim2.fromOffset(110, 42),
		if self.compact then UDim2.new(0.5, 5, 0, 50) else UDim2.new(1, -110, 0, 0),
		if self.state.benefits.plusSubscriber then "mint" else nil
	)
	self:_BindButton(refresh)
	self:_BindButton(plus)
	refresh.Activated:Connect(function()
		self:_RefreshMarketplace(search.Text)
	end)
	search.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:_RefreshMarketplace(search.Text)
		end
	end)
	plus.Activated:Connect(function()
		if not self.state.benefits.plusSubscriber then
			task.spawn(function()
				self:_Invoke(Network.Actions.PromptPlus, {})
			end)
		end
	end)

	local filters = Factory.New("ScrollingFrame", {
		Position = UDim2.new(0.025, 0, 0, if self.compact then 200 else 150),
		Size = UDim2.new(0.95, 0, 0, 34),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = self.content,
	})
	Factory.List(filters, Enum.FillDirection.Horizontal, 7)
	for _, mode in { { Id = "NAME", Label = "By name" }, { Id = "CREATOR", Label = "By creator" } } do
		local selected = self.marketplaceSearchBy == mode.Id
		local chip =
			Factory.Button(filters, mode.Label, UDim2.fromOffset(96, 30), nil, if selected then "primary" else nil)
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.marketplaceSearchBy = mode.Id
			self:_RefreshMarketplace(search.Text)
			self:_RenderActivePage()
		end)
	end
	Factory.New("Frame", {
		Size = UDim2.fromOffset(1, 22),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Parent = filters,
	})
	for _, sort in
		{
			{ Id = "TRENDING", Label = "Trending" },
			{ Id = "NEWEST", Label = "Newest" },
			{ Id = "PRICE_LOW", Label = "Price ↑" },
			{ Id = "MOST_LIKED", Label = "Most liked" },
		}
	do
		local selected = self.marketplaceSortBy == sort.Id
		local chip =
			Factory.Button(filters, sort.Label, UDim2.fromOffset(94, 30), nil, if selected then "primary" else nil)
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.marketplaceSortBy = sort.Id
			self:_RefreshMarketplace(search.Text)
			self:_RenderActivePage()
		end)
	end
	local leaderboardChip = Factory.Button(filters, "🏆 Top Creators", UDim2.fromOffset(130, 30), nil, "mint")
	self:_BindButton(leaderboardChip)
	leaderboardChip.Activated:Connect(function()
		self:_ShowLeaderboard()
	end)

	if self.marketplaceItems == nil then
		Factory.Label(self.content, "Loading trending creations…", UDim2.new(1, -52, 0, 60), {
			Position = UDim2.fromOffset(26, if self.compact then 280 else 230),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			Font = Theme.Fonts.Bold,
		})
		self:_RefreshMarketplace(self.marketplaceQuery)
		return
	end
	local grid = Factory.New("ScrollingFrame", {
		Position = UDim2.new(0.02, 0, 0, if self.compact then 258 else 208),
		Size = UDim2.new(0.96, 0, 1, if self.compact then -274 else -224),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Violet,
		Parent = self.content,
	})
	Factory.ScalePadding(grid, 0.004, 0.004)
	Factory.New("UIGridLayout", {
		CellSize = UDim2.new(1 / self.gridColumns, -12 * (self.gridColumns - 1) / self.gridColumns, 0, 336),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, item in self.marketplaceItems do
		local card = Factory.Card(grid, UDim2.fromScale(1, 1), nil, "CommunityItem")
		card.LayoutOrder = index
		local image = Factory.New("ImageLabel", {
			Size = UDim2.new(1, -20, 0, 176),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			Image = thumbnail(item.thumbnailAssetId, 420),
			ScaleType = Enum.ScaleType.Crop,
			Parent = card,
		})
		Factory.Corner(image, 11)
		if item.isListed then
			Factory.Pill(card, string.format("R$ %d", item.listingPriceRobux), Colors.Mint, 68).Position =
				UDim2.fromOffset(156, 18)
		end
		Factory.Label(card, item.name, UDim2.new(1, -20, 0, 27), {
			Position = UDim2.fromOffset(10, 194),
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		Factory.Label(
			card,
			string.format(
				"by @%s · %s / %s",
				tostring(item.ownerName),
				string.gsub(item.stylePreset or "AUTO", "_", " "),
				string.gsub(item.detailLevel or "BALANCED", "_", " ")
			),
			UDim2.new(1, -20, 0, 22),
			{
				Position = UDim2.fromOffset(10, 221),
				Color = Colors.TextMuted,
				TextSize = 11,
				Truncate = Enum.TextTruncate.AtEnd,
			}
		)
		local try = Factory.Button(card, "Try on", UDim2.new(0.48, -5, 0, 38), UDim2.fromOffset(10, 250), "primary")
		local buy = Factory.Button(
			card,
			if item.isListed then "Buy copy" else "Not for sale",
			UDim2.new(0.52, -15, 0, 38),
			UDim2.new(0.48, 10, 0, 250),
			if item.isListed then "mint" else nil
		)
		self:_BindButton(try)
		self:_BindButton(buy)
		buy.Active = item.isListed == true
		try.Activated:Connect(function()
			try.Active = false
			try.Text = "Applying…"
			task.spawn(function()
				local success = self:_Invoke(Network.Actions.TryOnCommunityItem, { itemId = item.id })
				if success then
					self:_Toast("success", "Trying this creator's model on your avatar.")
				end
				if try.Parent then
					try.Active = true
					try.Text = "Try on"
				end
			end)
		end)
		buy.Activated:Connect(function()
			buy.Active = false
			buy.Text = "Checking listing…"
			task.spawn(function()
				local success, errorCode = self:_Invoke(Network.Actions.BeginMarketplacePurchase, { itemId = item.id })
				if success then
					self:_Toast("success", "Confirm the verified creator transfer in Roblox.")
				elseif errorCode == "PLUS_REQUIRED" then
					self:_ShowPlus()
				elseif errorCode == "LISTING_UNAVAILABLE" then
					self.marketplaceItems = nil
					self:_RefreshMarketplace(search.Text)
				end
				if buy.Parent then
					buy.Active = item.isListed == true
					buy.Text = if item.isListed then "Buy copy" else "Not for sale"
				end
			end)
		end)
		local like = Factory.Button(
			card,
			string.format("%s %s", if item.viewerLiked then "♥" else "♡", formatNumber(item.likes)),
			UDim2.new(0.5, -15, 0, 30),
			UDim2.fromOffset(10, 296),
			nil
		)
		local favorite = Factory.Button(
			card,
			string.format("%s %s", if item.viewerFavorited then "★" else "☆", formatNumber(item.favorites)),
			UDim2.new(0.5, -15, 0, 30),
			UDim2.new(0.5, 5, 0, 296),
			nil
		)
		self:_BindButton(like)
		self:_BindButton(favorite)
		like.Activated:Connect(function()
			task.spawn(function()
				local success = self:_Invoke(Network.Actions.ToggleLike, { itemId = item.id })
				if success then
					self.sounds:Play("Like")
					self:_RefreshMarketplace(search.Text)
				end
			end)
		end)
		favorite.Activated:Connect(function()
			task.spawn(function()
				local success = self:_Invoke(Network.Actions.ToggleFavorite, { itemId = item.id })
				if success then
					self:_RefreshMarketplace(search.Text)
				end
			end)
		end)
	end
	if #self.marketplaceItems == 0 then
		Factory.Label(
			grid,
			"No public designs match yet. Be the first creator to share one.",
			if self.compact then UDim2.new(1, -8, 0, 100) else UDim2.fromOffset(520, 100),
			{
				AlignX = Enum.TextXAlignment.Center,
				Color = Colors.TextMuted,
				Wrapped = true,
				TextSize = 14,
			}
		)
	end
end

function App:_RequestCatalogAccess()
	if self.catalogAccessPrompting then
		return
	end
	self.catalogAccessPrompting = true
	self.catalogError = nil
	task.spawn(function()
		local success, problem = pcall(function()
			AvatarEditorService:PromptAllowInventoryReadAccess()
		end)
		if not success then
			self.catalogAccessPrompting = false
			self.catalogAccess = false
			self.catalogError =
				"Roblox could not request catalog access. Rejoin a published server and try the consent prompt again."
			warn(string.format("[App] Inventory access prompt failed: %s", tostring(problem)))
			self:_Toast("error", self.catalogError)
			if self.activePage == "Avatar Lab" then
				self:_RenderActivePage()
			end
		end
	end)
end

-- Reads every live catalog filter control (query, sort has already been set
-- directly on self by its chip; creator name and price range still live in
-- their TextBoxes until this runs) and re-searches. Used by the Search
-- button, Enter on any filter field, and the type/sort chips so a filter you
-- just typed but never blurred is never silently dropped.
function App:_ApplyCatalogFilters()
	if self.catalogSearchBox and self.catalogSearchBox.Parent then
		self.catalogQuery = self.catalogSearchBox.Text
	end
	if self.catalogCreatorBox and self.catalogCreatorBox.Parent then
		self.catalogCreatorName = self.catalogCreatorBox.Text
	end
	if self.catalogMinBox and self.catalogMinBox.Parent then
		self.catalogMinPrice = self.catalogMinBox.Text
	end
	if self.catalogMaxBox and self.catalogMaxBox.Parent then
		self.catalogMaxPrice = self.catalogMaxBox.Text
	end
	self.catalogResults = nil
	self:_SearchCatalog(self.catalogQuery)
end

function App:_SearchCatalog(query: string)
	if self.catalogSearching then
		return
	end
	self.catalogQuery = query
	if self.catalogAccess ~= true then
		self:_RequestCatalogAccess()
		return
	end
	self.catalogSearching = true
	self.catalogError = nil
	task.spawn(function()
		local parameters = CatalogSearchParams.new()
		parameters.SearchKeyword = string.sub(query, 1, 60)
		parameters.AssetTypes = { CATALOG_TYPES[self.catalogType] }
		parameters.IncludeOffSale = false
		parameters.Limit = 30
		parameters.SortType = CATALOG_SORT_TYPES[self.catalogSortType] or Enum.CatalogSortType.Relevance
		local creatorName = string.match(self.catalogCreatorName or "", "^%s*(.-)%s*$")
		if creatorName ~= "" then
			parameters.CreatorName = string.sub(creatorName, 1, 50)
		end
		local minPrice = tonumber(self.catalogMinPrice)
		if minPrice then
			parameters.MinPrice = math.clamp(math.floor(minPrice), 0, 2147483647)
		end
		local maxPrice = tonumber(self.catalogMaxPrice)
		if maxPrice then
			parameters.MaxPrice = math.clamp(math.floor(maxPrice), 0, 2147483647)
		end
		local success, resultsOrProblem = pcall(function()
			local pages = AvatarEditorService:SearchCatalogAsync(parameters)
			return pages:GetCurrentPage()
		end)
		if success then
			self.catalogResults = resultsOrProblem
			self:_Track({
				event = "CatalogSearch",
				fields = {
					assetType = self.catalogType,
					resultCount = #self.catalogResults,
					sortType = self.catalogSortType,
					hasCreatorFilter = creatorName ~= "",
					hasPriceFilter = minPrice ~= nil or maxPrice ~= nil,
				},
			})
		else
			self.catalogResults = {}
			self.catalogError =
				"Roblox catalog search failed. Confirm inventory access was approved, then retry in a published server."
			warn(string.format("[App] Catalog search failed: %s", tostring(resultsOrProblem)))
			self:_Toast("error", self.catalogError)
		end
		self.catalogSearching = false
		if self.activePage == "Avatar Lab" then
			self:_RenderActivePage()
		end
	end)
end

function App:_RenderAvatarLab()
	self:_PageHeader(
		"Avatar Lab",
		"Mix Roblox Marketplace accessories with your Forge creations and stay longer in the look."
	)
	-- The creator-name/price-range row is the single biggest thing in this
	-- card, and most searches never touch it — collapsed by default, it only
	-- renders (and only counts toward controlsHeight) once a player asks for
	-- it, so the catalog grid below gets that space back instead of always
	-- reserving it for filters most sessions never open.
	local filtersExpanded = self.catalogFiltersExpanded == true
	local filtersActive = self.catalogCreatorName ~= "" or self.catalogMinPrice ~= "" or self.catalogMaxPrice ~= ""
	local controlsHeight = if filtersExpanded
		then (if self.compact then 276 else 200)
		else (if self.compact then 194 else 151)
	local controls =
		Factory.Card(self.content, UDim2.new(0.95, 0, 0, controlsHeight), UDim2.new(0.025, 0, 0, 94), "CatalogControls")
	local search = self:_TextBox(
		controls,
		"Search the Roblox avatar marketplace",
		if self.compact then UDim2.new(1, -28, 0, 40) else UDim2.new(1, -346, 0, 42),
		UDim2.fromOffset(14, 13),
		false
	)
	search.Text = self.catalogQuery
	local searchButton = Factory.Button(
		controls,
		"Search",
		if self.compact then UDim2.new(0.32, -8, 0, 36) else UDim2.fromOffset(92, 42),
		if self.compact then UDim2.fromOffset(14, 59) else UDim2.new(1, -322, 0, 13),
		"primary"
	)
	local saveAvatar = Factory.Button(
		controls,
		if self.compact then "Save" else "Save avatar",
		if self.compact then UDim2.new(0.34, -8, 0, 36) else UDim2.fromOffset(100, 42),
		if self.compact then UDim2.new(0.32, 7, 0, 59) else UDim2.new(1, -220, 0, 13),
		"mint"
	)
	local reset = Factory.Button(
		controls,
		if self.compact then "Reset" else "Reset look",
		if self.compact then UDim2.new(0.34, -20, 0, 36) else UDim2.fromOffset(96, 42),
		if self.compact then UDim2.new(0.66, 7, 0, 59) else UDim2.new(1, -110, 0, 13),
		nil
	)
	for _, button in { searchButton, saveAvatar, reset } do
		self:_BindButton(button)
	end
	saveAvatar.Activated:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local success, problem = pcall(function()
				AvatarEditorService:PromptSaveAvatar(humanoid:GetAppliedDescription(), Enum.HumanoidRigType.R15)
			end)
			if not success then
				warn(string.format("[App] Save avatar prompt failed: %s", tostring(problem)))
				self:_Toast("error", "Roblox could not open the save-avatar prompt.")
			end
		else
			self:_Toast("error", ERROR_MESSAGES.CHARACTER_UNAVAILABLE)
		end
	end)
	reset.Activated:Connect(function()
		task.spawn(function()
			self:_Invoke(Network.Actions.ResetAvatar, {})
		end)
	end)
	local accessoryChipsY = if self.compact then 106 else 63
	local chips = Factory.New("ScrollingFrame", {
		Position = UDim2.fromOffset(14, accessoryChipsY),
		Size = UDim2.new(1, -28, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = controls,
	})
	Factory.List(chips, Enum.FillDirection.Horizontal, 7)
	for typeName, label in ACCESSORY_LABELS do
		local chip = Factory.Button(
			chips,
			label,
			UDim2.fromOffset(86, 30),
			nil,
			if self.catalogType == typeName then "primary" else nil
		)
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.catalogType = typeName
			self:_ApplyCatalogFilters()
			self:_RenderActivePage()
		end)
	end
	local filtersToggle = Factory.Button(
		chips,
		if filtersExpanded then "Filters ▲" elseif filtersActive then "Filters ✓" else "Filters ▾",
		UDim2.fromOffset(if filtersActive and not filtersExpanded then 92 else 78, 30),
		nil,
		if filtersExpanded or filtersActive then "primary" else nil
	)
	self:_BindButton(filtersToggle)
	filtersToggle.Activated:Connect(function()
		self.catalogFiltersExpanded = not filtersExpanded
		self:_RenderActivePage()
	end)

	-- Real Roblox Marketplace search options: sort order, then creator name
	-- and price range. A visible Label precedes every input here (rather than
	-- relying on placeholder text alone) so the row reads correctly for
	-- screen-reader-style access and keyboard/gamepad users tabbing through.
	local sortY = accessoryChipsY + 40
	Factory.Label(controls, "SORT", UDim2.fromOffset(60, 32), {
		Position = UDim2.fromOffset(14, sortY),
		AlignY = Enum.TextYAlignment.Center,
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Color = Colors.TextMuted,
	})
	local sortChips = Factory.New("ScrollingFrame", {
		Position = UDim2.fromOffset(66, sortY),
		Size = UDim2.new(1, -80, 0, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = controls,
	})
	Factory.List(sortChips, Enum.FillDirection.Horizontal, 7)
	for _, sortKey in CATALOG_SORT_ORDER do
		local chip = Factory.Button(
			sortChips,
			CATALOG_SORT_LABELS[sortKey],
			UDim2.fromOffset(math.max(72, #CATALOG_SORT_LABELS[sortKey] * 7 + 24), 30),
			nil,
			if self.catalogSortType == sortKey then "primary" else nil
		)
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.catalogSortType = sortKey
			self:_ApplyCatalogFilters()
			self:_RenderActivePage()
		end)
	end

	self.catalogSearchBox = search
	if filtersExpanded then
		local filterY = sortY + 40
		local filterFieldHeight = 34
		local creatorField = self:_TextBox(
			controls,
			"Search by creator",
			if self.compact then UDim2.new(1, -28, 0, filterFieldHeight) else UDim2.new(0, 220, 0, filterFieldHeight),
			UDim2.fromOffset(14, filterY),
			false
		)
		creatorField.Text = self.catalogCreatorName
		local priceRowY = if self.compact then filterY + filterFieldHeight + 8 else filterY
		local minField = self:_TextBox(
			controls,
			"Min R$",
			if self.compact then UDim2.new(0.5, -18, 0, filterFieldHeight) else UDim2.fromOffset(90, filterFieldHeight),
			if self.compact then UDim2.fromOffset(14, priceRowY) else UDim2.fromOffset(242, filterY),
			false
		)
		minField.Text = self.catalogMinPrice
		minField.TextXAlignment = Enum.TextXAlignment.Center
		local maxField = self:_TextBox(
			controls,
			"Max R$",
			if self.compact then UDim2.new(0.5, -18, 0, filterFieldHeight) else UDim2.fromOffset(90, filterFieldHeight),
			if self.compact then UDim2.new(0.5, 4, 0, priceRowY) else UDim2.fromOffset(340, filterY),
			false
		)
		maxField.Text = self.catalogMaxPrice
		maxField.TextXAlignment = Enum.TextXAlignment.Center
		self.catalogCreatorBox = creatorField
		self.catalogMinBox = minField
		self.catalogMaxBox = maxField
		for _, field in { creatorField, minField, maxField } do
			field.FocusLost:Connect(function(enterPressed)
				if enterPressed then
					self:_ApplyCatalogFilters()
				end
			end)
		end
	else
		-- _ApplyCatalogFilters nil-guards every box before reading it, so
		-- clearing these is enough to stop it re-reading stale, unparented
		-- TextBoxes from the last time the filter row was open; the values
		-- already copied into catalogCreatorName/catalogMinPrice/
		-- catalogMaxPrice stay in effect either way.
		self.catalogCreatorBox = nil
		self.catalogMinBox = nil
		self.catalogMaxBox = nil
	end
	searchButton.Activated:Connect(function()
		self:_ApplyCatalogFilters()
	end)
	search.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:_ApplyCatalogFilters()
		end
	end)

	if self.catalogAccess ~= true then
		if self.catalogAccess == nil and not self.catalogAccessPrompting then
			self:_RequestCatalogAccess()
		end
		local access = Factory.Card(
			self.content,
			UDim2.new(0.95, 0, 0, 190),
			UDim2.new(0.025, 0, 0, 94 + controlsHeight + 16),
			"CatalogAccess"
		)
		Factory.Label(access, "Enable Roblox catalog access", UDim2.new(1, -32, 0, 34), {
			Position = UDim2.fromOffset(16, 18),
			Font = Theme.Fonts.Black,
			TextSize = 20,
		})
		Factory.Label(
			access,
			self.catalogError
				or "Roblox asks once per session before Forge can search your inventory and the avatar marketplace.",
			UDim2.new(1, -32, 0, 62),
			{
				Position = UDim2.fromOffset(16, 56),
				Color = Colors.TextMuted,
				TextSize = 12,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
		local enable = Factory.Button(
			access,
			if self.catalogAccessPrompting then "Waiting for Roblox…" else "Enable catalog",
			UDim2.new(0.42, 0, 0, 40),
			UDim2.fromOffset(16, 132),
			"primary"
		)
		enable.Active = not self.catalogAccessPrompting
		self:_BindButton(enable)
		enable.Activated:Connect(function()
			self:_RequestCatalogAccess()
		end)
		return
	end
	if self.catalogResults == nil and not self.catalogSearching then
		self:_SearchCatalog(self.catalogQuery)
	end
	local belowControls = 94 + controlsHeight + 16
	if self.catalogSearching then
		Factory.Label(self.content, "Searching Roblox Marketplace…", UDim2.new(1, -52, 0, 60), {
			Position = UDim2.fromOffset(26, belowControls + 20),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			Font = Theme.Fonts.Bold,
		})
		return
	end
	local grid = Factory.New("ScrollingFrame", {
		Position = UDim2.new(0.02, 0, 0, belowControls),
		Size = UDim2.new(0.96, 0, 1, -(belowControls + 16)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Cyan,
		Parent = self.content,
	})
	Factory.ScalePadding(grid, 0.004, 0.004)
	Factory.New("UIGridLayout", {
		CellSize = UDim2.new(1 / self.gridColumns, -12 * (self.gridColumns - 1) / self.gridColumns, 0, 292),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, item in self.catalogResults or {} do
		local assetId = tonumber(item.Id or item.AssetId) or 0
		if assetId > 0 then
			local card = Factory.Card(grid, UDim2.fromScale(1, 1), nil, "CatalogItem")
			card.LayoutOrder = index
			local image = Factory.New("ImageLabel", {
				Size = UDim2.new(1, -20, 0, 180),
				Position = UDim2.fromOffset(10, 10),
				BackgroundColor3 = Colors.Ink,
				BorderSizePixel = 0,
				Image = thumbnail(assetId, 420),
				ScaleType = Enum.ScaleType.Crop,
				Parent = card,
			})
			Factory.Corner(image, 11)
			Factory.Label(card, tostring(item.Name or "Catalog item"), UDim2.new(1, -20, 0, 28), {
				Position = UDim2.fromOffset(10, 196),
				Font = Theme.Fonts.Bold,
				TextSize = 13,
				Truncate = Enum.TextTruncate.AtEnd,
			})
			local price = tonumber(item.Price or item.LowestPrice)
			Factory.Label(
				card,
				if price then string.format("R$ %d", price) else "View details",
				UDim2.new(1, -20, 0, 22),
				{
					Position = UDim2.fromOffset(10, 222),
					Color = if price then Colors.Mint else Colors.TextMuted,
					Font = Theme.Fonts.Bold,
					TextSize = 11,
				}
			)
			local try = Factory.Button(card, "Try", UDim2.new(0.45, -12, 0, 38), UDim2.fromOffset(10, 248), "primary")
			local buy = Factory.Button(card, "Buy", UDim2.new(0.55, -8, 0, 38), UDim2.new(0.45, 4, 0, 248), "mint")
			self:_BindButton(try)
			self:_BindButton(buy)
			try.Activated:Connect(function()
				try.Active = false
				try.Text = "Applying…"
				task.spawn(function()
					local success = self:_Invoke(Network.Actions.TryCatalogAsset, {
						assetId = assetId,
						avatarAssetType = self.catalogType,
					})
					if success then
						self:_Toast("success", "Catalog item applied. Keep browsing to build your look.")
					end
					if try.Parent then
						try.Active = true
						try.Text = "Try"
					end
				end)
			end)
			buy.Activated:Connect(function()
				local success, problem = pcall(function()
					MarketplaceService:PromptPurchase(player, assetId)
				end)
				if not success then
					warn(string.format("[App] Catalog purchase prompt failed: %s", tostring(problem)))
					self:_Toast("error", "Roblox could not open the catalog purchase prompt.")
				end
			end)
		end
	end
	if #(self.catalogResults or {}) == 0 then
		Factory.Label(grid, self.catalogError or "No catalog items matched this search.", UDim2.new(1, -8, 0, 100), {
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			Wrapped = true,
			TextSize = 13,
		})
	end
end

function App:_UpdateSetting(key: string, value: any)
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.UpdateSettings, { [key] = value })
		if success then
			self.state.profile.settings = data.settings
			if key == "reduceMotion" then
				self:_SetAmbientMotion(data.settings.reduceMotion ~= true)
			end
		end
		self:_RenderActivePage()
	end)
end

function App:_RenderSettings()
	self:_PageHeader("Settings", "Accessibility, audio, what's equipped right now, and your achievements.")
	local page = Factory.New("ScrollingFrame", {
		Name = "SettingsScroll",
		Position = UDim2.new(0.02, 0, 0, 96),
		Size = UDim2.new(0.96, 0, 1, -112),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Violet,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = self.content,
	})
	Factory.ScalePadding(page, 0.006, 0.006)
	local stack = Factory.New("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = page,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 14)

	local settings = self.state.profile.settings

	-- ACCESSIBILITY -----------------------------------------------------
	local accessibility =
		Factory.Card(stack, UDim2.new(1, 0, 0, if self.compact then 396 else 320), nil, "Accessibility")
	accessibility.LayoutOrder = 1
	Factory.Pill(accessibility, "ACCESSIBILITY", Colors.Cyan, 140).Position = UDim2.fromOffset(16, 14)
	Factory.Label(accessibility, "Interface size", UDim2.new(1, -32, 0, 22), {
		Position = UDim2.fromOffset(16, 52),
		Font = Theme.Fonts.Bold,
		TextSize = 13,
	})
	local scaleRow = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, 78),
		Size = UDim2.new(1, -32, 0, 36),
		BackgroundTransparency = 1,
		Parent = accessibility,
	})
	Factory.List(scaleRow, Enum.FillDirection.Horizontal, 8)
	local currentScale = tonumber(settings.uiScale) or 1
	for _, option in
		{
			{ Label = "Small", Value = 0.9 },
			{ Label = "Default", Value = 1 },
			{ Label = "Large", Value = 1.15 },
			{ Label = "Extra large", Value = 1.3 },
		}
	do
		local isSelected = math.abs(currentScale - option.Value) < 0.01
		local chip = Factory.Button(
			scaleRow,
			option.Label,
			UDim2.fromOffset(if self.compact then 84 else 108, 34),
			nil,
			if isSelected then "primary" else nil
		)
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.uiScaleInstance.Scale = option.Value
			if self.arcadeUiScale then
				self.arcadeUiScale.Scale = option.Value
			end
			self:_UpdateSetting("uiScale", option.Value)
		end)
	end
	Factory.Label(
		accessibility,
		"Scales every control and label together, including touch and click targets.",
		UDim2.new(1, -32, 0, 20),
		{ Position = UDim2.fromOffset(16, 120), Color = Colors.TextMuted, TextSize = 11 }
	)

	local highContrastButton = Factory.Button(
		accessibility,
		if settings.highContrast then "High contrast · ON" else "High contrast · OFF",
		if self.compact then UDim2.new(1, -32, 0, 40) else UDim2.new(0.5, -22, 0, 40),
		UDim2.fromOffset(16, 156),
		if settings.highContrast then "mint" else nil
	)
	self:_BindButton(highContrastButton)
	highContrastButton.Activated:Connect(function()
		local enabled = not settings.highContrast
		self:_SetHighContrast(enabled)
		self:_UpdateSetting("highContrast", enabled)
	end)

	local reduceMotionButton = Factory.Button(
		accessibility,
		if settings.reduceMotion then "Reduce motion · ON" else "Reduce motion · OFF",
		if self.compact then UDim2.new(1, -32, 0, 40) else UDim2.new(0.5, -22, 0, 40),
		if self.compact then UDim2.fromOffset(16, 202) else UDim2.new(0.5, 6, 0, 156),
		if settings.reduceMotion then "mint" else nil
	)
	self:_BindButton(reduceMotionButton)
	reduceMotionButton.Activated:Connect(function()
		self:_UpdateSetting("reduceMotion", not settings.reduceMotion)
	end)

	Factory.Label(
		accessibility,
		"Brighter borders and text for low-vision contrast · fewer sliding/fading animations for motion sensitivity.",
		UDim2.new(1, -32, 0, 34),
		{
			Position = UDim2.fromOffset(16, if self.compact then 250 else 204),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
		}
	)
	Factory.Label(
		accessibility,
		"Keyboard & gamepad: press Tab, or a gamepad's Y button, any time to jump into the navigation rail and move through the studio with arrows or the D-pad.",
		UDim2.new(1, -32, 0, if self.compact then 60 else 44),
		{
			Position = UDim2.fromOffset(16, if self.compact then 292 else 246),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)

	-- AUDIO ---------------------------------------------------------------
	local audio = Factory.Card(stack, UDim2.new(1, 0, 0, 108), nil, "Audio")
	audio.LayoutOrder = 2
	Factory.Pill(audio, "AUDIO", Colors.Violet, 90).Position = UDim2.fromOffset(16, 14)
	self:_BuildSoundButton(audio, UDim2.new(1, -32, 0, 42), UDim2.fromOffset(16, 52))

	-- INVITE FRIENDS --------------------------------------------------------
	local invite = Factory.Card(stack, UDim2.new(1, 0, 0, if self.compact then 158 else 108), nil, "InviteFriends")
	invite.LayoutOrder = 3
	Factory.Pill(invite, "GROW THE STUDIO", Colors.Rose, 150).Position = UDim2.fromOffset(16, 14)
	Factory.Label(
		invite,
		"Send a Roblox invite to a friend for a small one-time Forge Token reward.",
		if self.compact then UDim2.new(1, -32, 0, 40) else UDim2.new(1, -260, 0, 40),
		{
			Position = UDim2.fromOffset(16, 48),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)
	local inviteButton = Factory.Button(
		invite,
		"Invite a friend",
		if self.compact then UDim2.new(1, -32, 0, 42) else UDim2.fromOffset(200, 42),
		if self.compact then UDim2.fromOffset(16, 100) else UDim2.new(1, -216, 0, 33),
		"mint"
	)
	self:_BindButton(inviteButton)
	inviteButton.Activated:Connect(function()
		self:_PromptFriendInvite()
	end)

	-- EQUIPPED NOW ----------------------------------------------------------
	local profile = self.state.profile
	local equippedIds = profile.equippedItemIds or {}
	local loadout =
		Factory.Card(stack, UDim2.new(1, 0, 0, math.max(140, 70 + math.max(1, #equippedIds) * 66)), nil, "Loadout")
	loadout.LayoutOrder = 4
	Factory.Pill(loadout, string.format("EQUIPPED · %d", #equippedIds), Colors.Mint, 130).Position =
		UDim2.fromOffset(16, 14)
	if #equippedIds == 0 then
		Factory.Label(loadout, "Nothing equipped yet. Equip an item from My Studio.", UDim2.new(1, -32, 0, 40), {
			Position = UDim2.fromOffset(16, 52),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
		})
	else
		local y = 54
		for _, itemId in equippedIds do
			local item = profile.items[itemId]
			if item then
				local row = Factory.New("Frame", {
					Position = UDim2.fromOffset(16, y),
					Size = UDim2.new(1, -32, 0, 56),
					BackgroundColor3 = Colors.Ink,
					BackgroundTransparency = 0.22,
					BorderSizePixel = 0,
					Parent = loadout,
				})
				Factory.Corner(row, 10)
				local image = Factory.New("ImageLabel", {
					Size = UDim2.fromOffset(44, 44),
					Position = UDim2.fromOffset(6, 6),
					BackgroundColor3 = Colors.Panel,
					BorderSizePixel = 0,
					Image = thumbnail(item.thumbnailAssetId, 120),
					ScaleType = Enum.ScaleType.Crop,
					Parent = row,
				})
				Factory.Corner(image, 8)
				Factory.Label(row, item.name, UDim2.new(1, -204, 0, 24), {
					Position = UDim2.fromOffset(58, 8),
					Font = Theme.Fonts.Bold,
					TextSize = 13,
					Truncate = Enum.TextTruncate.AtEnd,
				})
				Factory.Label(row, ACCESSORY_LABELS[item.fit.accessoryType] or "Accessory", UDim2.new(1, -204, 0, 20), {
					Position = UDim2.fromOffset(58, 30),
					Color = Colors.TextMuted,
					TextSize = 11,
				})
				local unequip = Factory.Button(row, "Unequip", UDim2.fromOffset(120, 38), UDim2.new(1, -128, 0, 9), nil)
				self:_BindButton(unequip)
				unequip.Activated:Connect(function()
					unequip.Active = false
					unequip.Text = "Removing…"
					task.spawn(function()
						local success = self:_Invoke(Network.Actions.UnequipItem, { itemId = itemId })
						if success then
							local index = table.find(self.state.profile.equippedItemIds, itemId)
							if index then
								table.remove(self.state.profile.equippedItemIds, index)
							end
							self:_Toast("success", "Unequipped.")
							self:_RenderActivePage()
							return
						end
						if unequip.Parent then
							unequip.Active = true
							unequip.Text = "Unequip"
						end
					end)
				end)
				y += 62
			end
		end
	end

	-- ACHIEVEMENTS ---------------------------------------------------------
	local unlockedAchievements = profile.achievements or {}
	local unlockedCount = 0
	for _ in unlockedAchievements do
		unlockedCount += 1
	end
	local achievementColumns = if self.compact then 1 else 2
	local achievementRows = math.ceil(#Achievements.List / achievementColumns)
	local achievementTileHeight = 74
	local achievements =
		Factory.Card(stack, UDim2.new(1, 0, 0, 58 + achievementRows * (achievementTileHeight + 8)), nil, "Achievements")
	achievements.LayoutOrder = 5
	Factory.Pill(
		achievements,
		string.format("ACHIEVEMENTS · %d/%d", unlockedCount, #Achievements.List),
		Colors.Gold,
		170
	).Position =
		UDim2.fromOffset(16, 14)
	local achievementGrid = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 0, achievementRows * (achievementTileHeight + 8)),
		BackgroundTransparency = 1,
		Parent = achievements,
	})
	Factory.New("UIGridLayout", {
		CellSize = UDim2.new(
			1 / achievementColumns,
			-8 * (achievementColumns - 1) / achievementColumns,
			0,
			achievementTileHeight
		),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = achievementGrid,
	})
	for index, definition in Achievements.List do
		local unlocked = unlockedAchievements[definition.id] ~= nil
		local tile = Factory.New("Frame", {
			BackgroundColor3 = if unlocked then Colors.Ink else Colors.Panel,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = achievementGrid,
		})
		Factory.Corner(tile, 11)
		Factory.Stroke(tile, if unlocked then Colors.Gold else Colors.Line, if unlocked then 0.3 else 0.6)
		Factory.Label(tile, if unlocked then "✓" else "○", UDim2.fromOffset(24, 24), {
			Position = UDim2.fromOffset(10, 8),
			Font = Theme.Fonts.Black,
			TextSize = 15,
			AlignX = Enum.TextXAlignment.Center,
			Color = if unlocked then Colors.Gold else Colors.TextMuted,
		})
		Factory.Label(tile, definition.name, UDim2.new(1, -80, 0, 20), {
			Position = UDim2.fromOffset(36, 8),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			Color = if unlocked then Colors.Text else Colors.TextMuted,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		Factory.Label(tile, string.format("+%d", definition.tokens), UDim2.fromOffset(44, 20), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			AlignX = Enum.TextXAlignment.Right,
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = if unlocked then Colors.Gold else Colors.TextMuted,
		})
		Factory.Label(tile, definition.description, UDim2.new(1, -48, 0, 38), {
			Position = UDim2.fromOffset(36, 30),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		})
	end
end

function App:_ShowOnboarding()
	local overlay = Factory.New("Frame", {
		Name = "Onboarding",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		ZIndex = 200,
		Parent = self.gui,
	})
	local modal = Factory.Card(overlay, UDim2.new(1, -32, 0, 430), UDim2.fromScale(0.5, 0.5), "OnboardingModal")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 201
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(610, 430),
		Parent = modal,
	})
	for _, descendant in modal:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 202
		end
	end
	local step = 1
	local slides = {
		{
			kicker = "WELCOME TO THE FORGE",
			title = "Your idea becomes a Roblox-ready object.",
			body = "Choose Direct Forge for value, Art-Directed for an AI reference, or unlock Upload Reference for your own Roblox-moderated art. Style and detail controls guide every path.",
			icon = "✦",
		},
		{
			kicker = "FIT WITH PRECISION",
			title = "Position, rotate, and scale on an avatar.",
			body = "Every generated model targets one mesh, fewer than 4,000 triangles and vertices, with a 2K-or-smaller texture. Save separate fits for originals and purchased copies.",
			icon = "◈",
		},
		{
			kicker = "SHARE ON YOUR TERMS",
			title = "Try freely. Sell only when you choose.",
			body = "Public designs can always be tried on. Owners control listings. Buying requires Roblox Plus and a verified transfer receipt; purchased copies can never be resold.",
			icon = "◎",
		},
	}
	local function draw()
		for _, child in modal:GetChildren() do
			if
				not child:IsA("UICorner")
				and not child:IsA("UIStroke")
				and not child:IsA("UIGradient")
				and child.Name ~= "Gloss"
			then
				child:Destroy()
			end
		end
		local slide = slides[step]
		Factory.Label(modal, slide.icon, UDim2.new(1, 0, 0, 92), {
			Position = UDim2.fromOffset(0, 34),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 66,
			Color = if step == 1 then Colors.Cyan elseif step == 2 then Colors.Violet else Colors.Rose,
			ZIndex = 203,
		})
		Factory.Label(modal, slide.kicker, UDim2.new(1, -60, 0, 24), {
			Position = UDim2.fromOffset(30, 126),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			Color = Colors.Mint,
			ZIndex = 203,
		})
		Factory.Label(modal, slide.title, UDim2.new(1, -72, 0, 66), {
			Position = UDim2.fromOffset(36, 158),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 24,
			Wrapped = true,
			ZIndex = 203,
		})
		Factory.Label(modal, slide.body, UDim2.new(1, -90, 0, 94), {
			Position = UDim2.fromOffset(45, 230),
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Top,
			Color = Colors.TextMuted,
			TextSize = 14,
			Wrapped = true,
			ZIndex = 203,
		})
		local nextButton = Factory.Button(
			modal,
			if step == #slides then "Enter the studio" else "Continue",
			UDim2.fromOffset(190, 44),
			UDim2.new(0.5, -95, 1, -68),
			"primary"
		)
		nextButton.ZIndex = 204
		self:_BindButton(nextButton)
		nextButton.Activated:Connect(function()
			if step < #slides then
				step += 1
				self:_Track({ event = "OnboardingStep", step = step })
				draw()
			else
				task.spawn(function()
					local success = self:_Invoke(Network.Actions.CompleteOnboarding, {})
					if success then
						self.state.profile.onboarding.completed = true
					end
				end)
				overlay:Destroy()
				self.sounds:Play("Success")
				self:_Toast("success", "Your studio is ready. Start with today's brief or your own idea.")
			end
		end)
		Factory.Label(modal, string.format("%d  /  %d", step, #slides), UDim2.fromOffset(90, 24), {
			Position = UDim2.fromOffset(24, 378),
			Color = Colors.TextMuted,
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			ZIndex = 203,
		})
	end
	draw()
	self:_AnimateModalIn(overlay, modal)
end

function App:_ShowPlus()
	local overlay = Factory.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 210,
		Parent = self.gui,
	})
	local modal = Factory.Card(overlay, UDim2.new(1, -32, 0, 400), UDim2.fromScale(0.5, 0.5), "PlusModal")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ClipsDescendants = false
	modal.ZIndex = 211
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(480, 400),
		Parent = modal,
	})
	-- Soft gold glow behind the modal reads as a premium/upsell accent from
	-- across the screen, before the reader's eye even reaches the copy.
	local glow = Factory.Blob(modal, 360, UDim2.new(0.5, 0, 0, -40), Colors.Gold, 0.88)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.ZIndex = 210

	local badge = Factory.New("Frame", {
		Name = "PlusBadge",
		Size = UDim2.fromOffset(64, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = 212,
		Parent = modal,
	})
	Factory.Corner(badge, 32)
	Factory.Gradient(badge, { Color3.fromRGB(255, 220, 130), Colors.Gold }, 120)
	Factory.Stroke(badge, Colors.Ink, 0.3, 1.5)
	local badgeShadow = Factory.New("Frame", {
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = 211,
		Parent = badge,
	})
	Factory.Corner(badgeShadow, 32)
	Factory.Label(badge, "♛", UDim2.fromScale(1, 1), {
		Color = Colors.Ink,
		TextSize = 30,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 213,
	})

	Factory.Label(modal, "Support creators directly", UDim2.new(1, -50, 0, 30), {
		Position = UDim2.fromOffset(25, 96),
		AlignX = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Black,
		TextSize = 21,
		ZIndex = 212,
	})
	Factory.Label(
		modal,
		"Plus is required to send Robux to another creator. You can still sell your own work and try on every public design without it.",
		UDim2.new(1, -70, 0, 56),
		{
			Position = UDim2.fromOffset(35, 130),
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Top,
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			ZIndex = 212,
		}
	)

	local benefits = Factory.New("Frame", {
		Position = UDim2.fromOffset(28, 196),
		Size = UDim2.new(1, -56, 0, 96),
		BackgroundTransparency = 1,
		ZIndex = 212,
		Parent = modal,
	})
	Factory.List(benefits, Enum.FillDirection.Vertical, 8)
	for _, line in
		{
			"Send Robux straight to the creators you support",
			"Unlock purchasing across every listed design",
			"Nothing changes about selling or trying on your own work",
		}
	do
		local row = Factory.New("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			ZIndex = 212,
			Parent = benefits,
		})
		local check = Factory.New("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromOffset(0, 4),
			BackgroundColor3 = Colors.Mint,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 213,
			Parent = row,
		})
		Factory.Corner(check, 9)
		Factory.Label(check, "✓", UDim2.fromScale(1, 1), {
			Color = Colors.Ink,
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 214,
		})
		Factory.Label(row, line, UDim2.new(1, -30, 1, 0), {
			Position = UDim2.fromOffset(28, 0),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			ZIndex = 213,
		})
	end

	local subscribe =
		Factory.Button(modal, "View Roblox Plus", UDim2.new(0.5, -24, 0, 44), UDim2.fromOffset(16, 316), "mint")
	local closeButton = Factory.Button(modal, "Maybe later", UDim2.new(0.5, -24, 0, 44), UDim2.new(0.5, 8, 0, 316), nil)
	subscribe.ZIndex = 213
	closeButton.ZIndex = 213
	self:_BindButton(subscribe)
	self:_BindButton(closeButton)
	subscribe.Activated:Connect(function()
		task.spawn(function()
			self:_Invoke(Network.Actions.PromptPlus, {})
		end)
		self.sounds:Play("PanelClose")
		overlay:Destroy()
	end)
	closeButton.Activated:Connect(function()
		self.sounds:Play("PanelClose")
		overlay:Destroy()
	end)
	self:_AnimateModalIn(overlay, modal)
end

function App:_ShowLeaderboard()
	local overlay = Factory.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 210,
		Parent = self.gui,
	})
	local modal = Factory.Card(overlay, UDim2.new(1, -32, 0, 480), UDim2.fromScale(0.5, 0.5), "LeaderboardModal")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 211
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(440, 480),
		Parent = modal,
	})
	Factory.Pill(modal, "TOP CREATORS", Colors.Gold, 130).Position = UDim2.fromOffset(16, 16)
	Factory.Label(
		modal,
		"Ranked by likes received across every published and listed creation.",
		UDim2.new(1, -100, 0, 34),
		{
			Position = UDim2.fromOffset(16, 46),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			ZIndex = 212,
		}
	)
	local closeButton = Factory.Button(modal, "×", UDim2.fromOffset(34, 34), UDim2.new(1, -50, 0, 14), nil)
	closeButton.ZIndex = 213
	self:_BindButton(closeButton)
	closeButton.Activated:Connect(function()
		self.sounds:Play("PanelClose")
		overlay:Destroy()
	end)
	self:_AnimateModalIn(overlay, modal)
	local list = Factory.New("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 88),
		Size = UDim2.new(1, -24, 1, -100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Gold,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 212,
		Parent = modal,
	})
	local listStack = Factory.New("Frame", {
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 212,
		Parent = list,
	})
	Factory.List(listStack, Enum.FillDirection.Vertical, 8)
	Factory.Label(listStack, "Loading leaderboard…", UDim2.new(1, 0, 0, 40), {
		AlignX = Enum.TextXAlignment.Center,
		Color = Colors.TextMuted,
		TextSize = 12,
		ZIndex = 212,
	})
	task.spawn(function()
		local success, result = self:_Invoke(Network.Actions.GetLeaderboard, {})
		if not overlay.Parent then
			return
		end
		clear(listStack)
		local creators = if success and type(result) == "table" then result.creators or {} else {}
		if #creators == 0 then
			Factory.Label(listStack, "No liked creations yet — be the first!", UDim2.new(1, 0, 0, 40), {
				AlignX = Enum.TextXAlignment.Center,
				Color = Colors.TextMuted,
				TextSize = 12,
				ZIndex = 212,
			})
			return
		end
		local medals = { "🥇", "🥈", "🥉" }
		-- Top 3 get their own tinted treatment (gold/silver/bronze) rather
		-- than reading identically to everyone else with just a different
		-- emoji -- the same rank-tinting idea the Arcade's leaderboards use.
		local rankColors = { Colors.Gold, Color3.fromRGB(200, 208, 224), Color3.fromRGB(214, 158, 100) }
		for rank, creator in creators do
			local rankColor = rankColors[rank]
			local row = Factory.New("Frame", {
				Size = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = if rankColor then rankColor else Colors.Ink,
				BackgroundTransparency = if rankColor then 0.88 else 0,
				BorderSizePixel = 0,
				LayoutOrder = rank,
				ZIndex = 212,
				Parent = listStack,
			})
			Factory.Corner(row, 10)
			if rankColor then
				Factory.Stroke(row, rankColor, 0.6, 1)
			else
				Factory.Gradient(row, {
					Color3.fromRGB(36, 40, 62),
					Color3.fromRGB(22, 25, 40),
				}, 90)
			end
			local rankBadge = Factory.New("Frame", {
				Name = "RankBadge",
				Size = UDim2.fromOffset(32, 32),
				Position = UDim2.fromOffset(7, 7),
				BackgroundColor3 = if rankColor then rankColor else Colors.PanelSoft,
				BackgroundTransparency = if rankColor then 0.15 else 0,
				BorderSizePixel = 0,
				ZIndex = 213,
				Parent = row,
			})
			Factory.Corner(rankBadge, 11)
			Factory.Label(rankBadge, medals[rank] or string.format("#%d", rank), UDim2.fromScale(1, 1), {
				Font = Theme.Fonts.Black,
				Color = if rankColor then Colors.Ink else Colors.TextMuted,
				TextSize = if medals[rank] then 15 else 12,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				ZIndex = 214,
			})
			Factory.Label(row, string.format("@%s", tostring(creator.name)), UDim2.new(1, -150, 0, 46), {
				Position = UDim2.fromOffset(48, 0),
				Font = Theme.Fonts.Bold,
				TextSize = 13,
				Truncate = Enum.TextTruncate.AtEnd,
				ZIndex = 213,
			})
			Factory.Label(
				row,
				string.format("♥ %s", formatNumber(tonumber(creator.likes) or 0)),
				UDim2.fromOffset(80, 46),
				{
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 0),
					AlignX = Enum.TextXAlignment.Right,
					Color = Colors.Rose,
					Font = Theme.Fonts.Bold,
					TextSize = 13,
					ZIndex = 213,
				}
			)

			-- A quick staggered fade/rise -- each row starts a little later
			-- than the one above it, so the list reads as settling into
			-- place rather than popping in all at once.
			if not (self.state and self.state.profile.settings.reduceMotion == true) then
				row.BackgroundTransparency = 1
				local targetTransparency = if rankColor then 0.88 else 0
				local rowScale = Factory.New("UIScale", { Scale = 0.94, Parent = row })
				task.delay(math.min(rank * 0.035, 0.35), function()
					if row.Parent then
						TweenService:Create(
							row,
							TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ BackgroundTransparency = targetTransparency }
						):Play()
						TweenService:Create(
							rowScale,
							TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
							{ Scale = 1 }
						):Play()
					end
				end)
			end
		end
	end)
end

function App:_Toast(tone: string, message: string)
	self.toastVersion += 1
	local toast = Factory.New("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(350, 70),
		BackgroundColor3 = Colors.PanelRaised,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		LayoutOrder = -self.toastVersion,
		ZIndex = 51,
		Parent = self.toastHost,
	})
	Factory.Corner(toast, 13)
	local color = if tone == "error" then Colors.Danger elseif tone == "ready" then Colors.Cyan else Colors.Mint
	-- A glyph, not just the accent color, marks the tone so the toast still
	-- reads correctly for colorblind players and in high-contrast mode.
	local icon = if tone == "error" then "✕" elseif tone == "ready" then "◆" else "✓"
	Factory.Stroke(toast, color, 0.2, 1.2)
	Factory.Gradient(toast, {
		Color3.fromRGB(66, 74, 106),
		Color3.fromRGB(44, 50, 78),
	}, 120)
	local bar = Factory.New("Frame", {
		Size = UDim2.fromOffset(5, 48),
		Position = UDim2.fromOffset(10, 11),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = toast,
	})
	Factory.Corner(bar, 99)
	local iconBadge = Factory.New("Frame", {
		Name = "IconBadge",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(22, 8),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 52,
		Parent = toast,
	})
	Factory.Corner(iconBadge, 10)
	Factory.Label(iconBadge, icon, UDim2.fromScale(1, 1), {
		Color = color,
		Font = Theme.Fonts.Black,
		TextSize = 15,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 53,
	})
	Factory.Label(toast, message, UDim2.new(1, -70, 1, -18), {
		Position = UDim2.fromOffset(62, 9),
		Color = Colors.Text,
		TextSize = 12,
		Wrapped = true,
		ZIndex = 52,
	})

	-- A combined slide-and-scale entrance -- the scale (via UIScale, since a
	-- Frame's own Size can't itself "pop") is the extra flourish; the slide
	-- is the part that was already there.
	local toastScale = Factory.New("UIScale", { Scale = 0.9, Parent = toast })
	toast.Position = UDim2.fromOffset(40, 0)
	self:_Animate(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = UDim2.new() })
	self:_Animate(toastScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	if tone == "error" then
		self.sounds:Play("Error")
	elseif tone == "ready" then
		self.sounds:Play("GenerationReady")
	end
	task.delay(5, function()
		if toast.Parent then
			local tween = self:_Animate(toast, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
			if tween then
				tween.Completed:Wait()
			end
			toast:Destroy()
		end
	end)
end

return App
