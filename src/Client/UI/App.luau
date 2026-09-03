--!strict

local AdService = game:GetService("AdService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Achievements = require(ReplicatedStorage:WaitForChild("Achievements"))
local AccessoryBounds = require(ReplicatedStorage:WaitForChild("AccessoryBounds"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Factory = require(script.Parent.Factory)
local GamesHub = require(script.Parent.GamesHub)
local RunwayHub = require(script.Parent.RunwayHub)
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

-- The concept art studs each saved-look / category chip with a gem, walking
-- down the palette rather than repeating one colour. Used wherever a page
-- draws a row of chips whose contents are player data (saved outfits,
-- catalog categories, avatar views), so the colour depends only on the
-- chip's position in its row.
local CHIP_GEMS = { "GemCyan", "GemRose", "GemGold", "GemMint", "GemAmethyst", "GemRuby" }

-- Where a chip row already has one accent colour of its own (Avatar
-- Graphics' step rows), the art studs every chip in that row with a gem of
-- the matching colour instead of walking the palette.
local function gemForAccent(color: Color3): string
	if color == Colors.Mint then
		return "GemMint"
	elseif color == Colors.Violet then
		return "GemAmethyst"
	elseif color == Colors.Gold then
		return "GemGold"
	elseif color == Colors.Rose then
		return "GemRose"
	end
	return "GemCyan"
end

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
	CREATION_TOKEN_NOT_CONFIGURED = "Add the Avatar Creation Token for this type to ServerStorage/ForgeUGCSecrets.",
	MODEL_UNAVAILABLE = "The model asset is not available yet.",
	ASSET_STILL_PROCESSING = "Roblox is still processing this new model. Wait a few seconds and try again.",
	MODEL_TEXTURE_PROCESSING = "Roblox is still processing or moderating this model's texture. Your item is saved; retry when the texture appears.",
	ASSET_LOAD_FAILED = "Roblox could not load this model. Check that the uploaded asset belongs to this experience's creator.",
	MESH_NOT_FOUND = "The uploaded model does not contain a usable MeshPart.",
	ACCESSORY_PREPARATION_FAILED = "Roblox could not turn this model into an accessory. The server log now includes the exact failure.",
	EDITABLE_ASSET_FAILED = "Roblox could not prepare this mesh for wearable publishing. Check EditableMesh permissions and memory limits.",
	EQUIP_FAILED = "Roblox could not attach this model to your avatar. Try another fit region or rejoin.",
	CHARACTER_UNAVAILABLE = "Your avatar is still loading. Try again in a moment.",
	PLAYER_GUI_UNAVAILABLE = "Your private preview cache is unavailable. Rejoin and try again.",
	AVATAR_CREATION_UNAVAILABLE = "Roblox could not open the wearable publishing prompt. Check the creation token and asset permissions.",
	AVATAR_CREATION_REJECTED = "Wearable publishing was cancelled or Roblox rejected the asset.",
	AVATAR_CREATION_CANCELLED = "Wearable publishing was cancelled. Your model and fit are still saved.",
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
	UGC_BOUNDS_TOO_LARGE = "This wearable exceeds Roblox's size limit. Check the measured X/Y/Z bounds in Fitting and reduce the highlighted scale axes.",
	UGC_MODERATION_PENDING = "Roblox is still processing or moderating this model or texture. Your item is saved; retry publishing later.",
	ITEM_NOT_EQUIPPED = "That item is not currently equipped.",
	INVALID_IMAGE_QUALITY = "Choose one of the available reference image quality tiers.",
	FIT_PRESET_LIMIT_REACHED = "You have saved the maximum number of fit presets. Delete one to save another.",
	FIT_PRESET_NOT_FOUND = "That saved fit preset no longer exists.",
	INSUFFICIENT_TOKENS = "You don't have enough Forge Tokens for that yet. Watch a rewarded ad to earn more.",
	INSUFFICIENT_AD_TOKENS = "Generations need ad-earned tokens specifically — free tokens (achievements, streaks) only cover the Priority Pass. Watch a rewarded ad to earn more.",
	TOKENS_NOT_ACCEPTED = "Forge Tokens can't pay for that.",
	AD_UNAVAILABLE = "No rewarded ad is available right now. Try again in a few minutes.",
	AD_NOT_COMPLETED = "The ad was closed before it finished, so no tokens were earned.",
	INVALID_AVATAR_VIEW = "Choose one of the available avatar views.",
	BACKEND_GRAPHIC_MISSING = "The generator finished without returning a usable image. A retry credit was added.",
	NOT_FOUND = "That could not be found. It may have already been removed.",
	GRAPHIC_NOT_FOUND = "That graphic is no longer available. Refresh the page and try again.",
	GRAPHIC_NOT_SHAREABLE = "Only original creations can be shared publicly.",
	GRAPHIC_NOT_LISTABLE = "Only an original creation can be listed for sale.",
	TEXT_INVALID = "That text could not be read.",
	TEXT_TOO_LONG = "Keep that within the character limit.",
	TEXT_BLOCKED = "That text could not pass Roblox text filtering. Try different wording.",
	CONTENT_NOT_FOUND = "That creation is no longer available. Refresh and try again.",
	CANNOT_TIP_SELF = "You can't tip your own creation.",
	INVALID_TIP_AMOUNT = "Choose one of the available tip amounts.",
	RUNWAY_JOIN_CLOSED = "This runway round has already moved to voting. Join the next one.",
	RUNWAY_ROUND_ACTIVE = "Finish the active runway round before leaving it.",
	RUNWAY_NOT_STYLING = "Looks can only be locked during the styling phase.",
	RUNWAY_NOT_JOINED = "Join the runway before locking in a look.",
	RUNWAY_SELF_VOTE = "Choose another creator's look—you cannot vote for yourself.",
	RUNWAY_ALREADY_VOTED = "You already cast your vote for this round.",
	RUNWAY_LOOK_UNAVAILABLE = "That look left the runway or was not locked in.",
	RUNWAY_NOT_VOTING = "Voting is not open for this runway round.",
	RUNWAY_LOOK_LOCKED = "Your runway look is frozen during voting and results.",
}

-- The nav rail is a fixed slice of the app's width, so the longest page
-- names ("Avatar Graphics", "My Studio") truncated to "Avata...", "My...".
-- These are the labels the rail shows; the page ids themselves (the keys)
-- stay exactly as every other part of the app refers to them. The concept
-- art's own sidebar reads "Avatar Art" for the same reason.
local NAV_LABELS: { [string]: string } = {
	["Avatar Graphics"] = "Avatar Art",
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

-- rbxthumb://type=Asset requests a RENDERED THUMBNAIL of an asset -- the
-- right choice for a genuine catalog item (a hat, a 3D model) where there's
-- no raw 2D image to show directly. Every image this game generates and
-- uploads itself (a reference image, a Meshy model thumbnail, an avatar
-- graphic) is already a flat PNG Image asset, not something needing a
-- separate render step, so it should be referenced directly instead --
-- rbxthumb's extra render/caching layer for an asset that's already just an
-- image is a plausible reason it can stay blank far longer than the asset
-- itself takes to become viewable.
local function directImage(assetId: any): string
	local id = tonumber(assetId) or 0
	if id <= 0 then
		return ""
	end
	return string.format("rbxassetid://%d", id)
end

-- Generated models normally have a separately uploaded flat thumbnail. If
-- that image is absent or still propagating, Roblox's rendered model thumbnail
-- is a useful independent fallback instead of leaving every ImageLabel blank.
local function modelPreviewImage(item: { [string]: any }): string
	local uploadedThumbnail = directImage(item.thumbnailAssetId)
	if uploadedThumbnail ~= "" then
		return uploadedThumbnail
	end
	return thumbnail(item.modelAssetId, 420)
end

local function vectorFromData(value: any): Vector3?
	if
		type(value) ~= "table"
		or type(value.x) ~= "number"
		or type(value.y) ~= "number"
		or type(value.z) ~= "number"
	then
		return nil
	end
	return Vector3.new(value.x, value.y, value.z)
end

-- Cheap, instant client-side avatar preview. `thumbType` is one of
-- Config.Generation.AvatarViews' ThumbType values (AvatarHeadShot/
-- AvatarBust/Avatar) -- the engine resolves this locally, no HTTP call
-- (and unlike a fetchable URL, HttpService couldn't make this call anyway:
-- Roblox blocks HttpService from reaching Roblox-owned domains). The real
-- fetchable image URL the generation job itself needs is instead resolved
-- by the external backend, from the avatarView this client sends and the
-- playerUserId already stamped on every job -- see GenerationService.
--
-- Unlike type=Asset thumbnails, avatar thumbnail types only accept one of a
-- fixed discrete size set -- 48/60/100/150/180/352/420 (plus 720 for the
-- full-body Avatar type only) -- any other w/h silently fails to render.
local function avatarThumbnail(userId: number, thumbType: string, size: number?): string
	local pixels = size or 420
	return string.format("rbxthumb://type=%s&id=%d&w=%d&h=%d", thumbType, userId, pixels, pixels)
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
	AvatarConversion = true,
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
		-- Not a real player choice any more -- there's no "choose detail
		-- density" UI left anywhere on Create (see _RenderCreate). Kept as
		-- a field, not a literal in the generation payload, only because
		-- GenerationService still expects a valid Config.Generation.
		-- DetailLevels id on every request.
		selectedDetailLevel = "BALANCED",
		selectedImageQuality = "LOW",
		selectedAvatarView = "HEADSHOT",
		customImageAssetId = "",
		draftPrompt = "",
		avatarGraphicPrompt = "",
		-- "AVATAR" (existing Avatar Graphics flow) or "TEXT" (pure text-to-image,
		-- no avatar reference). Kept as its own prompt field below since the two
		-- modes have different defaults/requirements -- an avatar graphic prompt
		-- is optional scene direction, a text-to-image prompt is the only
		-- description of the image and required.
		graphicMode = "AVATAR",
		textImagePrompt = "",
		-- "CREATE" (composer + personal gallery) or "DISCOVER" (public gallery),
		-- mirroring the item Discover page's search/sort/like/buy pattern.
		graphicsTab = "CREATE",
		selectedItemId = nil :: string?,
		fitDrafts = {} :: { [string]: { [string]: any } },
		pageConnections = {} :: { RBXScriptConnection },
		marketplaceItems = nil :: { any }?,
		featuredCommunityItem = nil :: { [string]: any }?,
		marketplaceQuery = "",
		marketplaceSearchBy = "NAME",
		marketplaceSortBy = "TRENDING",
		graphicsMarketplaceItems = nil :: { any }?,
		graphicsMarketplaceQuery = "",
		graphicsMarketplaceSearchBy = "CREATOR",
		graphicsMarketplaceSortBy = "TRENDING",
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
		-- Survives _RenderActivePage's destroy/rebuild cycle (unlike the
		-- ScrollingFrame instances themselves) -- see _TrackScroll.
		scrollPositions = {} :: { [string]: Vector2 },
		triedOnAssetIds = {} :: { [number]: boolean },
		-- Display metadata for the avatar preview panel's "TRIED ON" list
		-- (name + accessory type per assetId) -- triedOnAssetIds alone is
		-- just a set, with nothing to show besides the asset ID itself.
		triedOnAssetInfo = {} :: { [number]: { name: string, assetType: string } },
		avatarAccessoriesLoaded = false,
		avatarAccessoriesLoading = false,
		avatarAccessoriesDirty = true,
		communityTryOnItem = nil :: { [string]: any }?,
		-- De-duplicates guide impressions across Discover's frequent re-renders
		-- while retaining click telemetry for the same stage.
		firstLookGuideEvents = {} :: { [string]: boolean },
		-- True whenever the player's actual applied avatar description may
		-- have changed since the panel's ViewportController last snapshotted
		-- it (see ViewportController.new), so the panel knows to rebuild the
		-- 3D mannequin. Left true after Try/Untry/Reset; never set for
		-- unrelated re-renders (search, filters, sort) so those don't pay for
		-- an avatar rebuild that wouldn't show anything different.
		avatarPreviewDirty = true,
		usePriority = false,
		paymentMethod = "ROBUX",
		adAvailable = nil :: boolean?,
		adAvailabilityChecking = false,
		afkAdChecking = false,
		adWatchesToday = nil :: number?,
		afkSnapshot = nil :: { [string]: any }?,
		afkOverlay = nil :: Frame?,
		afkRunId = 0,
		runwayState = nil :: { [string]: any }?,
		runwayOverlay = nil :: Frame?,
		runwayRefresh = nil :: (({ [string]: any }) -> ())?,
		pageVersion = 0,
		toastVersion = 0,
		queuedSoundIds = {} :: { [string]: boolean },
		completionShownIds = {} :: { [string]: boolean },
		tutorialOverlay = nil :: Frame?,
		visualTutorialShown = false,
		generationOfferEvents = {} :: { [string]: boolean },
		navButtons = {} :: { [string]: TextButton },
		navHasIcon = {} :: { [string]: boolean },
		activeViewport = nil :: any,
		ambientMotionEnabled = false,
		ambientBlobs = {} :: { { instance: Frame, restPosition: UDim2 } },
		ambientEmbers = {} :: { Frame },
		-- Set by GamesHub while the Arcade modal is open (nil otherwise) so
		-- the Settings page's UIScale chips can keep it live-scaled too --
		-- see the "Make Arcade modal inherit UIScale" fix in GamesHub.luau.
		arcadeUiScale = nil :: UIScale?,
		runwayUiScale = nil :: UIScale?,
	}, App)
	self:_BuildChrome()
	-- Nothing opens before Bootstrap resolves -- self.state doesn't exist
	-- yet, so there's nothing to decide a first-timer vs. returning player
	-- with. The base view (Forge Studio / Arcade / Runway / AFK launchers)
	-- is the safe default until then; Bootstrap itself immediately reopens
	-- the shell to Create for anyone who's never finished a generation (see
	-- the Bootstrap success handler below), so this stays closed only for
	-- returning creators.
	self:_SetStudioOpen(false)
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
	player.CharacterAdded:Connect(function()
		self.communityTryOnItem = nil
		self.avatarPreviewDirty = true
		self.avatarAccessoriesDirty = true
		-- ItemService restores saved Forge accessories shortly after spawn. Wait
		-- until that pass has run before snapshotting the live mannequin.
		task.delay(1.1, function()
			if self.state then
				self.avatarPreviewDirty = true
				self.avatarAccessoriesDirty = true
				if self.activePage == "Avatar Lab" or self.activePage == "Discover" then
					self:_RenderActivePage()
				end
			end
		end)
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
		-- Create was prepared behind the closed shell during Bootstrap. Rebuild
		-- it now that it is genuinely visible so impression analytics describe
		-- what the player saw, not hidden UI.
		if self.state then
			self:_RenderActivePage()
		end
	end)
	self.launcher = launcher

	-- The primary repeatable social loop. It lives beside the launchers and
	-- renders avatars in isolated ViewportFrames; it never constructs a map
	-- stage or changes global Lighting.
	local runwayLauncher = buildLauncher(
		"◆",
		"Forge Runway",
		"6-minute live style battles",
		-146,
		Colors.Rose,
		Color3.fromRGB(255, 139, 188),
		Color3.fromRGB(189, 59, 126),
		Colors.Text
	)
	runwayLauncher.Name = "RunwayLauncher"
	self:_BindButton(runwayLauncher)
	runwayLauncher.Activated:Connect(function()
		RunwayHub.Show(self)
	end)
	self.runwayLauncher = runwayLauncher

	-- A separate entry point from the Forge Studio launcher above, not a
	-- variant of it: this opens the Arcade (see GamesHub), which has nothing
	-- to do with creation/fitting/marketplace. Same visibility rule as the
	-- Forge launcher (only shown on the closed/idle base view) since it's a
	-- peer of it, not something nested inside the studio.
	local arcadeLauncher = buildLauncher(
		"🎮",
		"Arcade",
		string.format("%d mini-games · weekly prizes", #Config.Arcade.Games),
		-214,
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

	local afkLauncher = buildLauncher(
		"✧",
		"Tokens for AFK",
		"Passive bonus tokens · optional ads",
		-282,
		Color3.fromRGB(54, 44, 112),
		Color3.fromRGB(105, 86, 212),
		Color3.fromRGB(22, 19, 54),
		Colors.Text
	)
	afkLauncher.Name = "AfkLauncher"
	self:_BindButton(afkLauncher)
	afkLauncher.Activated:Connect(function()
		task.spawn(function()
			self:_OpenAfkLounge()
		end)
	end)
	self.afkLauncher = afkLauncher

	local topbar = Factory.New("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, 78),
		BackgroundColor3 = Color3.fromRGB(21, 12, 46),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Parent = shell,
	})
	-- The concept art's topbar has a curved gold bottom edge rather than a
	-- flat line -- a single continuous curve can't be 9-sliced, so this
	-- stretches across the topbar's real (dynamic) width instead once the
	-- asset exists; the flat line stays as the fallback until then.
	local topbarCurve = Factory.Icon(topbar, "TopbarCurve", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 1, -20))
	if topbarCurve then
		topbarCurve.ScaleType = Enum.ScaleType.Stretch
	else
		Factory.New("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			Position = UDim2.new(0, 0, 1, -2),
			BackgroundColor3 = Colors.Gold,
			BorderSizePixel = 0,
			Parent = topbar,
		})
	end
	-- Factory.Icon returns nil until design/upload_ui_assets.py (or
	-- apply_asset_ids.py) has actually put a real id in UIAssets.Logo, so
	-- the original flat-color mark stays as the fallback rather than
	-- leaving a blank corner before that upload happens.
	local logoIcon = Factory.Icon(topbar, "Logo", UDim2.fromOffset(43, 43), UDim2.fromOffset(20, 17))
	if not logoIcon then
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
	end
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
		Size = UDim2.fromOffset(560, 48),
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
	local closeStudio = Factory.ImageButton(topbar, "×", UDim2.fromOffset(40, 40), UDim2.new(1, -54, 0.5, -20), nil)
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

	for index, page in { "Create", "My Studio", "Discover", "Avatar Lab", "Avatar Graphics", "Settings" } do
		local symbols = { "✦", "◈", "◎", "◇", "❑", "⚙" }
		-- One id per nav row: NavCreate, NavStudio, NavDiscover, NavAvatarLab,
		-- NavAvatarArt, NavSettings -- see design/export_ui_assets.py.
		local iconKeys = { "NavCreate", "NavStudio", "NavDiscover", "NavAvatarLab", "NavAvatarArt", "NavSettings" }
		local label = NAV_LABELS[page] or page
		local button = Factory.ImageButton(navStack, symbols[index] .. "   " .. label, UDim2.new(1, 0, 0, 48), nil, nil)
		button.Name = page
		button.LayoutOrder = index
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Selectable = true
		Factory.Padding(button, 15, 0)
		-- Only swap the unicode symbol for the decal icon once it's actually
		-- uploaded (Factory.Icon returns nil until then) -- otherwise the
		-- symbol stays exactly as it always has.
		local icon = Factory.Icon(button, iconKeys[index], UDim2.fromOffset(22, 22), UDim2.fromOffset(10, 13))
		if icon then
			icon.ZIndex = 2
			button.Text = "      " .. label
			-- _ApplyResponsiveLayout rewrites this text on every resize --
			-- it has to know the decal icon is already carrying the glyph,
			-- or it puts the unicode symbol back in front of the label and
			-- the row wraps to two lines against the nav rail's width.
			self.navHasIcon[page] = true
		end
		-- Whatever the rail's width ends up being, a nav row is one line:
		-- wrapping "Create" to "Crea/te" over its own icon is never the
		-- better answer. attachDecal's mirrored label is the one that
		-- actually renders, so both it and the button itself get this.
		button.TextWrapped = false
		button.TextTruncate = Enum.TextTruncate.AtEnd
		local mirrored = button:FindFirstChild("Label")
		if mirrored and mirrored:IsA("TextLabel") then
			mirrored.TextWrapped = false
			mirrored.TextTruncate = Enum.TextTruncate.AtEnd
		end
		self.sounds:Bind(button)
		button.Activated:Connect(function()
			self:_OpenPage(page)
		end)
		self.navButtons[page] = button
	end

	-- Sidebar extras below the 6 nav rows -- the concept art's creator-rank
	-- crest and Simple/Advanced switch, plus the pre-existing group-boost
	-- reminder -- share a scrolling stack instead of fixed pixel offsets.
	-- The floating Shell window's own height is clamped between 450 and
	-- 860px (see the UISizeConstraint above), and even at that max there
	-- isn't reliably room below the nav rows for all three at once, so
	-- this scrolls instead of silently overlapping or clipping.
	local navExtras = Factory.New("ScrollingFrame", {
		Name = "NavExtras",
		Position = UDim2.fromOffset(0, 405),
		Size = UDim2.new(1, 0, 1, -405),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Gold,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = nav,
	})
	Factory.List(navExtras, Enum.FillDirection.Vertical, 10)
	Factory.Padding(navExtras, 12, 6)
	self.navExtras = navExtras

	-- Creator rank crest, matching the concept art's sidebar level badge +
	-- ring. Filled in by _RenderStatus (self.creatorLevelLabel/
	-- creatorXPLabel/creatorRingUpdate), the same place that already
	-- refreshes the topbar's level pill on every CreatorProgress push.
	local rankCard = Factory.New("Frame", {
		Name = "CreatorRank",
		Size = UDim2.new(1, 0, 0, 128),
		BackgroundTransparency = 1,
		Parent = navExtras,
	})
	-- The ring is a band of segments just outside the badge's own edge
	-- (84px vs the badge's 64px), sitting on a plain dark circular Frame.
	-- Segments past the current progress stay in ringTrackColor, so the
	-- unfilled part of the ring reads as a track rather than a gap.
	local ringTrackColor = Color3.fromRGB(58, 37, 96)
	local ringWrap = Factory.New("Frame", {
		Name = "RingWrap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = Color3.fromRGB(22, 14, 48),
		BorderSizePixel = 0,
		Parent = rankCard,
	})
	Factory.Corner(ringWrap, 42)
	self.creatorRingUpdate = Factory.RadialRing(ringWrap, 84, 8, Colors.Gold, ringTrackColor, 60)
	local badge = Factory.New("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Color3.fromRGB(22, 14, 48),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = ringWrap,
	})
	Factory.Corner(badge, 32)
	Factory.Stroke(badge, Colors.Gold, 0.1, 2.4)
	self.creatorLevelLabel = Factory.Label(badge, "1", UDim2.fromScale(1, 1), {
		Font = Theme.Fonts.Black,
		TextSize = 24,
		Color = Colors.Gold,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
	})
	Factory.Label(rankCard, "CREATOR RANK", UDim2.new(1, 0, 0, 14), {
		Position = UDim2.fromOffset(0, 92),
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Center,
	})
	self.creatorXPLabel = Factory.Label(rankCard, "0 / 0 XP", UDim2.new(1, 0, 0, 14), {
		Position = UDim2.fromOffset(0, 108),
		TextSize = 10,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Center,
	})

	-- Sidebar Simple/Advanced mode toggle, matching the concept art's
	-- persistent switch -- every page still keeps its own inline "Switch to
	-- Advanced Mode" link too (a second entry point to the same setting,
	-- not a replacement); _RefreshModeToggle (called from _UpdateSetting,
	-- so it stays in sync regardless of which entry point was used) keeps
	-- this one's highlight matching the real state.
	local modeCard = Factory.ImageCard(navExtras, UDim2.new(1, 0, 0, 104), nil, "ModeToggle")
	Factory.Label(modeCard, "MODE", UDim2.new(1, -20, 0, 14), {
		Position = UDim2.fromOffset(0, 10),
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Color = Colors.TextMuted,
		AlignX = Enum.TextXAlignment.Center,
	})
	local simpleModeButton = Factory.ImageButton(modeCard, "Simple", UDim2.new(1, -20, 0, 32), UDim2.fromOffset(10, 28))
	self:_BindButton(simpleModeButton)
	simpleModeButton.Activated:Connect(function()
		self:_UpdateSetting("simpleMode", true)
	end)
	local advancedModeButton =
		Factory.ImageButton(modeCard, "Advanced", UDim2.new(1, -20, 0, 32), UDim2.fromOffset(10, 64))
	self:_BindButton(advancedModeButton)
	advancedModeButton.Activated:Connect(function()
		self:_UpdateSetting("simpleMode", false)
	end)
	self.modeButtons = { simple = simpleModeButton, advanced = advancedModeButton }
	self:_RefreshModeToggle()

	local tip = Factory.ImageCard(navExtras, UDim2.new(1, 0, 0, 142), nil, "GroupTip")
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

	self.backdrop = backdrop
	self:_BuildAvatarPreviewPanel(backdrop)

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

-- Builds the Avatar Lab side panel's chrome once: a live viewport of the
-- player's own avatar (so Roblox catalog items can be seen on them while
-- browsing) with a "TRIED ON" list underneath listing what's currently
-- applied, each with a Remove button. A sibling of `shell` under `backdrop`
-- -- like AmbientBackground above -- rather than a child of `shell`, since
-- `shell` has ClipsDescendants and this panel needs to sit outside its
-- bounds, to its right. Its own geometry is recomputed live off `shell`'s
-- AbsolutePosition/AbsoluteSize (see _LayoutAvatarPreviewPanel) because
-- `shell` is scale-sized but clamped by a UISizeConstraint, so no fixed
-- scale/offset formula tracks its edges exactly. Its content (the 3D
-- mannequin and the list rows) is filled in later by _SyncAvatarPreviewPanel,
-- called once per _RenderActivePage rather than here.
function App:_BuildAvatarPreviewPanel(backdrop: Frame)
	local panel = Factory.New("Frame", {
		Name = "AvatarPreviewPanel",
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 2,
		Parent = backdrop,
	})
	Factory.Corner(panel, 22)
	Factory.Stroke(panel, Color3.fromRGB(101, 113, 170), 0.35, 1.2)
	self.avatarPreviewPanel = panel

	Factory.Label(panel, "YOUR AVATAR", UDim2.new(1, -28, 0, 18), {
		Position = UDim2.fromOffset(16, 14),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.TextMuted,
	})

	-- Split the panel's height 50/50 between the viewport and the list below
	-- it, in scale rather than fixed offsets, since the panel's own height
	-- (== shell's) ranges anywhere from 450 to 860px depending on the
	-- player's window size.
	local viewport = Factory.New("ViewportFrame", {
		Name = "PreviewViewport",
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0.5, -44),
		BackgroundColor3 = Color3.fromRGB(62, 72, 108),
		BorderSizePixel = 0,
		Parent = panel,
	})
	Factory.Corner(viewport, 14)
	Factory.Stroke(viewport, Colors.Violet, 0.45)
	self.avatarPreviewViewport = viewport

	local resetCameraButton =
		Factory.ImageButton(viewport, "↺", UDim2.fromOffset(32, 28), UDim2.new(1, -42, 0, 8), nil)
	resetCameraButton.Name = "ResetCamera"
	resetCameraButton.TextSize = 15
	resetCameraButton.ZIndex = 5
	self:_BindButton(resetCameraButton)
	resetCameraButton.Activated:Connect(function()
		if self.avatarPreviewViewportController then
			self.avatarPreviewViewportController:ResetCamera()
		end
	end)

	Factory.New("Frame", {
		Name = "Divider",
		Position = UDim2.new(0, 14, 0.5, 4),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = panel,
	})
	Factory.Label(panel, "WORN NOW", UDim2.new(1, -32, 0, 16), {
		Position = UDim2.new(0, 16, 0.5, 14),
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		Color = Colors.TextMuted,
	})

	local list = Factory.New("ScrollingFrame", {
		Name = "TriedOnList",
		Position = UDim2.new(0, 14, 0.5, 40),
		Size = UDim2.new(1, -28, 0.5, -54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Cyan,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		Parent = panel,
	})
	Factory.List(list, Enum.FillDirection.Vertical, 8)
	Factory.Padding(list, 0, 0).PaddingRight = UDim.new(0, 10)
	self.avatarPreviewList = list

	self.avatarPreviewEmptyLabel =
		Factory.Label(list, "Your Roblox and Forge accessories will show up here.", UDim2.new(1, 0, 0, 40), {
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		})

	local function relayout()
		self:_LayoutAvatarPreviewPanel()
	end
	self.shell:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	self.shell:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout)
end

-- Positions the panel against `shell`'s current on-screen rect AND actively
-- carves out room for it by shrinking/recentering `shell` itself, rather
-- than passively hoping there happens to be leftover space to shell's
-- right. `shell` is already sized at 90% of the full screen width (clamped
-- 330-1440px) -- at nearly every common desktop resolution (1920x1080
-- included) that alone already reaches the screen edge with nothing left
-- over, which is why the panel never actually appeared: the old version of
-- this function only ever positioned it in whatever space was left, and
-- there wasn't any. Subtracting PANEL_RESERVE from shell's own width/
-- position (both in the same UDim2, scale and offset combined) guarantees
-- that much room exists on its right for any screen at least
-- MIN_VIEWPORT_FOR_PANEL wide, regardless of how shell's own 90%-scale
-- sizing would otherwise fill the screen. Safe to call often -- driven by
-- `shell`'s AbsoluteSize/AbsolutePosition signals above, from
-- _ApplyResponsiveLayout on every viewport resize, and once per
-- _RenderActivePage via _SyncAvatarPreviewPanel.
local PANEL_WIDTH = 280
local PANEL_GAP = 16
local MIN_VIEWPORT_FOR_PANEL = 1180
function App:_LayoutAvatarPreviewPanel()
	local panel = self.avatarPreviewPanel
	if not panel then
		return
	end
	local shell = self.shell
	local backdrop = self.backdrop
	local camera = Workspace.CurrentCamera
	local viewportWidth = if camera then camera.ViewportSize.X else 1200
	local wanted = (self.activePage == "Avatar Lab" or self.activePage == "Discover")
		and not self.compact
		and shell.Visible
		and viewportWidth >= MIN_VIEWPORT_FOR_PANEL
	local reserve = if wanted then PANEL_WIDTH + PANEL_GAP else 0
	-- Only ever the two hardcoded base values (no panel) or those values
	-- minus one fixed reserve (panel) -- comparing against those computed
	-- UDim2s (UDim2 supports ==) skips reassigning Size/Position, and
	-- therefore skips re-firing the AbsoluteSize/AbsolutePosition signals
	-- that call back into this same function, on every one of the many
	-- calls that don't actually need to change anything.
	local targetSize = UDim2.new(0.9, -reserve, 0.88, 0)
	local targetPosition = UDim2.new(0.5, -reserve / 2, 0.5, 0)
	if shell.Size ~= targetSize then
		shell.Size = targetSize
	end
	if shell.Position ~= targetPosition then
		shell.Position = targetPosition
	end
	if not wanted or shell.AbsoluteSize.Y <= 0 then
		panel.Visible = false
		return
	end
	local shellRight = (shell.AbsolutePosition.X - backdrop.AbsolutePosition.X) + shell.AbsoluteSize.X
	local shellTop = shell.AbsolutePosition.Y - backdrop.AbsolutePosition.Y
	panel.Position = UDim2.fromOffset(shellRight + PANEL_GAP, shellTop)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, shell.AbsoluteSize.Y)
	panel.Visible = true
end

-- Reads the avatar's actual HumanoidDescription on the server, including
-- accessories the player arrived wearing. This is deliberately separate
-- from profile.equippedItemIds because Forge accessories are physical
-- Accessory instances and are not written into the player's saved Roblox
-- HumanoidDescription.
function App:_RefreshAvatarAccessories()
	if self.avatarAccessoriesLoading then
		return
	end
	self.avatarAccessoriesLoading = true
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.GetEquippedAvatarAccessories, {})
		self.avatarAccessoriesLoading = false
		if success then
			local equipped = {} :: { [number]: boolean }
			local info = {} :: { [number]: { name: string, assetType: string } }
			for _, accessory in data.accessories or {} do
				local assetId = tonumber(accessory.assetId)
				if assetId and assetId > 0 then
					equipped[assetId] = true
					info[assetId] = {
						name = tostring(accessory.name or string.format("Avatar accessory %d", assetId)),
						assetType = tostring(accessory.assetType or "Accessory"),
					}
				end
			end
			self.triedOnAssetIds = equipped
			self.triedOnAssetInfo = info
			self.avatarAccessoriesLoaded = true
			self.avatarAccessoriesDirty = false
		end
		if self.activePage == "Avatar Lab" or self.activePage == "Discover" then
			self:_SyncAvatarPreviewPanel()
		end
	end)
end

-- Rebuilds the try-on list's rows every call (cheap: a handful of local
-- table reads and small labels, no network round trip) and rebuilds the 3D
-- mannequin only when avatarPreviewDirty says the player's applied avatar
-- description may actually have changed since it was last snapshotted --
-- ViewportController.new() reads that description once at construction and
-- never again, so cheaply-triggered re-renders (search, sort, filters) on
-- the Avatar Lab page must not treat that as a reason to rebuild it. Called
-- once at the end of every _RenderActivePage.
function App:_SyncAvatarPreviewPanel()
	self:_LayoutAvatarPreviewPanel()
	local panel = self.avatarPreviewPanel
	if not panel or not panel.Visible then
		if self.avatarPreviewViewportController then
			self.avatarPreviewViewportController:Destroy()
			self.avatarPreviewViewportController = nil
		end
		return
	end
	if (not self.avatarAccessoriesLoaded or self.avatarAccessoriesDirty) and not self.avatarAccessoriesLoading then
		self:_RefreshAvatarAccessories()
	end
	for _, child in self.avatarPreviewList:GetChildren() do
		if child.Name == "TriedOnItemRow" then
			child:Destroy()
		end
	end
	local rows = {}
	for assetId, info in self.triedOnAssetInfo do
		if self.triedOnAssetIds[assetId] then
			table.insert(rows, {
				key = string.format("catalog:%d", assetId),
				source = "CATALOG",
				assetId = assetId,
				name = info.name,
				assetType = info.assetType,
				image = thumbnail(assetId, 150),
			})
		end
	end
	table.sort(rows, function(left, right)
		return string.lower(left.name) < string.lower(right.name)
	end)
	local profile = self.state and self.state.profile
	if profile then
		for _, itemId in profile.equippedItemIds or {} do
			local item = profile.items[itemId]
			if item then
				table.insert(rows, {
					key = "forge:" .. itemId,
					source = "FORGE",
					itemId = itemId,
					name = item.name or "Forge accessory",
					assetType = item.fit and item.fit.accessoryType or "Accessory",
					image = modelPreviewImage(item),
				})
			end
		end
	end
	if self.communityTryOnItem then
		local item = self.communityTryOnItem
		table.insert(rows, {
			key = "community:" .. tostring(item.id),
			source = "COMMUNITY",
			itemId = item.id,
			name = item.title or item.name or "Community accessory",
			assetType = item.fit and item.fit.accessoryType or "Accessory",
			image = modelPreviewImage(item),
		})
	end
	for _, entry in rows do
		self:_BuildWornRow(entry)
	end
	self.avatarPreviewEmptyLabel.Visible = #rows == 0
	self.avatarPreviewEmptyLabel.Text = if self.avatarAccessoriesLoading
		then "Reading your current avatar…"
		else "No accessories are currently equipped."
	if self.avatarPreviewDirty or not self.avatarPreviewViewportController then
		if self.avatarPreviewViewportController then
			self.avatarPreviewViewportController:Destroy()
		end
		self.avatarPreviewViewportController = ViewportController.new(self.avatarPreviewViewport)
		self.avatarPreviewDirty = false
	end
end

-- One row in the shared "WORN NOW" list. Each source has its own server
-- removal path: Roblox avatar-description assets, saved Forge accessories,
-- and the temporary community try-on are intentionally not conflated.
function App:_BuildWornRow(entry: { [string]: any })
	local row = Factory.New("Frame", {
		Name = "TriedOnItemRow",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Colors.PanelSoft,
		BorderSizePixel = 0,
		Parent = self.avatarPreviewList,
	})
	Factory.Corner(row, Theme.SmallCorner)
	local icon = Factory.New("ImageLabel", {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		Image = entry.image,
		ScaleType = Enum.ScaleType.Crop,
		Parent = row,
	})
	Factory.Corner(icon, 8)
	Factory.Label(row, tostring(entry.name), UDim2.new(1, -104, 0, 22), {
		Position = UDim2.fromOffset(52, 6),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Truncate = Enum.TextTruncate.AtEnd,
		AlignY = Enum.TextYAlignment.Top,
	})
	Factory.Label(row, string.upper(tostring(entry.source)), UDim2.new(1, -132, 0, 14), {
		Position = UDim2.fromOffset(52, 29),
		Color = if entry.source == "FORGE"
			then Colors.Cyan
			elseif entry.source == "COMMUNITY" then Colors.Gold
			else Colors.TextMuted,
		Font = Theme.Fonts.Bold,
		TextSize = 8,
	})
	local removeButton =
		Factory.ImageButton(row, "Remove", UDim2.fromOffset(72, 26), UDim2.new(1, -78, 1, -32), "danger")
	removeButton.TextSize = 11
	self:_BindButton(removeButton)
	removeButton.Activated:Connect(function()
		removeButton.Active = false
		removeButton.Text = "Removing…"
		task.spawn(function()
			local action = if entry.source == "CATALOG"
				then Network.Actions.UntryCatalogAsset
				elseif entry.source == "FORGE" then Network.Actions.UnequipItem
				else Network.Actions.ClearCommunityTryOn
			local payload = if entry.source == "CATALOG"
				then { assetId = entry.assetId, avatarAssetType = entry.assetType }
				elseif entry.source == "FORGE" then { itemId = entry.itemId }
				else {}
			local success = self:_Invoke(action, payload)
			if success then
				if entry.source == "CATALOG" then
					self.triedOnAssetIds[entry.assetId] = nil
					self.triedOnAssetInfo[entry.assetId] = nil
					self.avatarAccessoriesDirty = true
					self.communityTryOnItem = nil
				elseif entry.source == "FORGE" then
					local equippedIndex = table.find(self.state.profile.equippedItemIds, entry.itemId)
					if equippedIndex then
						table.remove(self.state.profile.equippedItemIds, equippedIndex)
					end
				else
					self.communityTryOnItem = nil
				end
				self.avatarPreviewDirty = true
				self:_Toast("success", "Accessory removed from your current look.")
				self:_RenderActivePage()
			elseif removeButton.Parent then
				removeButton.Active = true
				removeButton.Text = "Remove"
			end
		end)
	end)
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
	-- AvatarPreviewPanel is a sibling of the studio shell so it can sit to
	-- the shell's right without being clipped. That also means hiding the
	-- shell does not hide the panel automatically; recompute its visibility
	-- in the same frame as every open/close transition.
	self:_LayoutAvatarPreviewPanel()
	local showLaunchers = not open and self.afkOverlay == nil and self.runwayOverlay == nil
	self.launcher.Visible = showLaunchers
	self.runwayLauncher.Visible = showLaunchers
	self.arcadeLauncher.Visible = showLaunchers
	self.afkLauncher.Visible = showLaunchers
	if changed and open then
		self.sounds:Play("PanelOpen")
	elseif changed then
		self.sounds:Play("PanelClose")
	end
	-- The first Bootstrap opens Create behind the visual tutorial before the
	-- player has chosen a path. Do not send the gated journey action early;
	-- it would correctly fail ONBOARDING_REQUIRED and show a frightening,
	-- generic error toast during the very first seconds of play.
	if open and self.state and self.state.profile.onboarding.completed == true then
		self:_MarkJourneyOpen()
	end
end

function App:_ApplyResponsiveLayout()
	local camera = Workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1200
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
	self.navStack.Size = UDim2.new(1, if compact then -16 else -24, 0, 387)
	for page, button in self.navButtons do
		local symbol = if page == "Create"
			then "✦"
			elseif page == "My Studio" then "◈"
			elseif page == "Discover" then "◎"
			elseif page == "Avatar Lab" then "◇"
			elseif page == "Avatar Graphics" then "❑"
			else "⚙"
		-- Once the decal icon is in place it *is* the glyph for this row --
		-- prefixing the unicode symbol as well double-draws it (and the
		-- extra width is what wrapped these rows onto a second line).
		local hasIcon = self.navHasIcon[page] == true
		local label = NAV_LABELS[page] or page
		button.Text = if compact
			then (if hasIcon then "" else symbol)
			elseif hasIcon then "      " .. label
			else symbol .. "   " .. label
		button.TextXAlignment = if compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	end
	self:_UpdateSoundButton()
	-- The nav rail's own narrow width in compact mode (icon-only rows,
	-- see the symbol swap above) can't fit these text-heavy cards, so the
	-- whole scrolling stack (see _BuildChrome's navExtras) hides there;
	-- everywhere else it scrolls instead of a height-based on/off switch.
	if self.navExtras then
		self.navExtras.Visible = not compact
	end
	self.statusArea.Visible = width >= 1120
	-- Belt-and-suspenders alongside the AbsoluteSize/AbsolutePosition signals
	-- wired up in _BuildAvatarPreviewPanel: those cover shell's rect actually
	-- moving/resizing, but self.compact (read by _LayoutAvatarPreviewPanel)
	-- can flip without either changing, e.g. when shell is already pinned to
	-- its UISizeConstraint's clamped size on both sides of the resize.
	self:_LayoutAvatarPreviewPanel()
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
	Factory.SetSwitch(self.soundButton, enabled)
end

-- Builds the sound toggle used on the Settings page. Extracted from the old
-- persistent nav-rail button so it can be recreated each time that page
-- renders, like every other page-scoped control. Drawn as the concept
-- art's gold switch -- it flips optimistically and rolls back if the server
-- rejects the change, so it is moved between states in place rather than
-- rebuilt.
function App:_BuildSoundButton(parent: Instance, position: UDim2): TextButton
	local button = Factory.Switch(parent, true, position)
	button.Name = "SoundToggle"
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

-- One short, visual explanation replaces the old multi-page onboarding. The
-- audience skews young, so the hierarchy is circles first, verbs second, and
-- supporting copy last: TRY -> MAKE -> WEAR. It is versioned server-side so a
-- materially clearer edition can reach existing players once without becoming
-- a modal they must dismiss every session.
function App:_ShowVisualTutorial()
	if not self.state then
		return
	end
	if self.tutorialOverlay and self.tutorialOverlay.Parent then
		return
	end

	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1200, 800)
	local vertical = self.compact == true or viewport.X < 760
	local modalWidth = math.floor(math.clamp(viewport.X * 0.9, 300, if vertical then 560 else 760))
	local modalHeight =
		math.floor(math.clamp(viewport.Y * 0.88, if vertical then 460 else 440, if vertical then 520 else 500))
	local ZBASE = 350

	local overlay = Factory.New("Frame", {
		Name = "HowToPlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(5, 7, 20),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = ZBASE,
		Parent = self.gui,
	})
	self.tutorialOverlay = overlay
	local modal = Factory.New("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(modalWidth, modalHeight),
		BackgroundColor3 = Colors.Panel,
		BorderSizePixel = 0,
		ZIndex = ZBASE + 1,
		Parent = overlay,
	})
	Factory.Corner(modal, 26)
	Factory.Stroke(modal, Colors.Cyan, 0.18, 2)
	Factory.Gradient(modal, { Color3.fromRGB(72, 67, 119), Colors.Panel, Color3.fromRGB(37, 45, 76) }, 125)

	local badge = Factory.ImagePill(modal, "FREE START · NO ROBUX", Colors.Mint, 166)
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, if vertical then 11 else 17)
	badge.ZIndex = ZBASE + 3
	Factory.Label(modal, "HOW TO PLAY", UDim2.new(1, -36, 0, if vertical then 28 else 34), {
		Position = UDim2.fromOffset(18, if vertical then 38 else 49),
		Font = Theme.Fonts.Black,
		TextSize = if vertical then 23 else 29,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = ZBASE + 3,
	})
	Factory.Label(modal, "Try a look for free. Make your own when you're ready.", UDim2.new(1, -48, 0, 34), {
		Position = UDim2.fromOffset(24, if vertical then 68 else 84),
		Color = Colors.TextMuted,
		TextSize = if vertical then 12 else 13,
		Wrapped = true,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Top,
		ZIndex = ZBASE + 3,
	})

	local steps = {
		{ number = "1", word = "TRY", body = "Tap a free look", color = Colors.Mint },
		{ number = "2", word = "MAKE", body = "Type your idea", color = Colors.Violet },
		{ number = "3", word = "WEAR", body = "Fit it on your avatar", color = Colors.Cyan },
	}
	if vertical then
		local connector = Factory.New("Frame", {
			Position = UDim2.fromOffset(44, 128),
			Size = UDim2.fromOffset(3, 132),
			BackgroundColor3 = Colors.Line,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = ZBASE + 2,
			Parent = modal,
		})
		Factory.Corner(connector, 2)
		for index, step in steps do
			local rowY = 106 + (index - 1) * 59
			local circle = Factory.New("Frame", {
				Position = UDim2.fromOffset(22, rowY),
				Size = UDim2.fromOffset(47, 47),
				BackgroundColor3 = step.color,
				BorderSizePixel = 0,
				ZIndex = ZBASE + 4,
				Parent = modal,
			})
			Factory.Corner(circle, 24)
			Factory.Stroke(circle, Colors.Text, 0.55, 1.5)
			Factory.Label(circle, step.number, UDim2.fromScale(1, 1), {
				Color = if index == 1 then Colors.Ink else Colors.Text,
				Font = Theme.Fonts.Black,
				TextSize = 20,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				ZIndex = ZBASE + 5,
			})
			Factory.Label(modal, step.word, UDim2.new(1, -112, 0, 22), {
				Position = UDim2.fromOffset(86, rowY + 2),
				Color = step.color,
				Font = Theme.Fonts.Black,
				TextSize = 17,
				ZIndex = ZBASE + 4,
			})
			Factory.Label(modal, step.body, UDim2.new(1, -112, 0, 20), {
				Position = UDim2.fromOffset(86, rowY + 25),
				Color = Colors.TextMuted,
				TextSize = 12,
				ZIndex = ZBASE + 4,
			})
		end
	else
		local stepArea = Factory.New("Frame", {
			Position = UDim2.fromOffset(24, 125),
			Size = UDim2.new(1, -48, 0, 160),
			BackgroundTransparency = 1,
			ZIndex = ZBASE + 2,
			Parent = modal,
		})
		for index, step in steps do
			local card = Factory.New("Frame", {
				Position = UDim2.new((index - 1) / 3, if index == 1 then 0 else 8, 0, 0),
				Size = UDim2.new(1 / 3, -11, 1, 0),
				BackgroundColor3 = Colors.PanelSoft,
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				ZIndex = ZBASE + 3,
				Parent = stepArea,
			})
			Factory.Corner(card, 18)
			Factory.Stroke(card, step.color, 0.38, 1.4)
			local circle = Factory.New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 13),
				Size = UDim2.fromOffset(56, 56),
				BackgroundColor3 = step.color,
				BorderSizePixel = 0,
				ZIndex = ZBASE + 4,
				Parent = card,
			})
			Factory.Corner(circle, 28)
			Factory.Label(circle, step.number, UDim2.fromScale(1, 1), {
				Color = if index == 1 then Colors.Ink else Colors.Text,
				Font = Theme.Fonts.Black,
				TextSize = 23,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				ZIndex = ZBASE + 5,
			})
			Factory.Label(card, step.word, UDim2.new(1, -20, 0, 25), {
				Position = UDim2.fromOffset(10, 79),
				Color = step.color,
				Font = Theme.Fonts.Black,
				TextSize = 18,
				AlignX = Enum.TextXAlignment.Center,
				ZIndex = ZBASE + 4,
			})
			Factory.Label(card, step.body, UDim2.new(1, -20, 0, 30), {
				Position = UDim2.fromOffset(10, 108),
				Color = Colors.TextMuted,
				TextSize = 12,
				Wrapped = true,
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Top,
				ZIndex = ZBASE + 4,
			})
			if index < #steps then
				Factory.Label(stepArea, "→", UDim2.fromOffset(28, 34), {
					Position = UDim2.new(index / 3, -14, 0, 62),
					Color = Colors.Gold,
					Font = Theme.Fonts.Black,
					TextSize = 25,
					AlignX = Enum.TextXAlignment.Center,
					ZIndex = ZBASE + 6,
				})
			end
		end
	end

	local noteY = if vertical then 286 else 300
	local note = Factory.New("Frame", {
		Position = UDim2.fromOffset(22, noteY),
		Size = UDim2.new(1, -44, 0, if vertical then 38 else 40),
		BackgroundColor3 = Colors.Gold,
		BackgroundTransparency = 0.86,
		BorderSizePixel = 0,
		ZIndex = ZBASE + 3,
		Parent = modal,
	})
	Factory.Corner(note, 10)
	Factory.Label(
		note,
		"Making your own can cost Robux. Roblox always asks before charging.",
		UDim2.new(1, -18, 1, 0),
		{
			Position = UDim2.fromOffset(9, 0),
			Color = Colors.Text,
			Font = Theme.Fonts.Bold,
			TextSize = if vertical then 10 else 11,
			Wrapped = true,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = ZBASE + 4,
		}
	)

	local primaryY = if vertical then 332 else 352
	local primary = Factory.ImageButton(
		modal,
		"START FREE LOOK  →",
		UDim2.new(1, -44, 0, 42),
		UDim2.fromOffset(22, primaryY),
		"primary"
	)
	local makeOwn = Factory.ImageButton(
		modal,
		"MAKE MY OWN",
		if vertical then UDim2.new(1, -44, 0, 38) else UDim2.new(0.5, -28, 0, 42),
		if vertical then UDim2.fromOffset(22, primaryY + 48) else UDim2.new(0.5, 6, 0, primaryY),
		nil
	)
	if not vertical then
		primary.Size = UDim2.new(0.5, -28, 0, 42)
	end
	primary.ZIndex = ZBASE + 4
	makeOwn.ZIndex = ZBASE + 4
	self:_BindButton(primary)
	self:_BindButton(makeOwn)
	local skipY = if vertical then primaryY + 91 else primaryY + 48
	local skip = Factory.New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, skipY),
		Size = UDim2.fromOffset(140, 26),
		BackgroundTransparency = 1,
		Text = "Skip tutorial",
		TextColor3 = Colors.TextMuted,
		BackgroundColor3 = Colors.PanelSoft,
		BackgroundTransparency = 0.65,
		Font = Theme.Fonts.Medium,
		TextSize = 12,
		ZIndex = ZBASE + 4,
		Parent = modal,
	})
	Factory.Corner(skip, 13)
	self:_BindButton(skip)

	if not self.visualTutorialShown then
		self.visualTutorialShown = true
		self:_Track({ event = "VisualTutorialShown" })
	end
	local choosing = false
	local function choose(choice: string)
		if choosing then
			return
		end
		choosing = true
		primary.Active = false
		makeOwn.Active = false
		skip.Active = false
		if choice == "START_FREE" then
			primary.Text = "OPENING FREE LOOK…"
		elseif choice == "MAKE_OWN" then
			makeOwn.Text = "OPENING CREATOR…"
		else
			skip.Text = "Opening…"
		end
		task.spawn(function()
			local success, result = self:_Invoke(Network.Actions.CompleteTutorial, { choice = choice })
			if not success then
				choosing = false
				primary.Active = true
				makeOwn.Active = true
				skip.Active = true
				primary.Text = "START FREE LOOK  →"
				makeOwn.Text = "MAKE MY OWN"
				skip.Text = "Skip tutorial"
				return
			end
			self.state.profile.tutorialVersion = if type(result) == "table"
				then tonumber(result.tutorialVersion) or Config.Tutorial.Version
				else Config.Tutorial.Version
			self.state.profile.onboarding.completed = true
			self.state.profile.onboarding.step = math.max(self.state.profile.onboarding.step or 1, 2)
			if self.tutorialOverlay == overlay then
				self.tutorialOverlay = nil
			end
			overlay:Destroy()
			self:_SetStudioOpen(true)
			if choice == "START_FREE" then
				self:_OpenPage(if self.state.policy.contentSharingAllowed then "Discover" else "Avatar Lab")
			else
				if choice == "MAKE_OWN" then
					self.scrollPositions.Create = Vector2.new(0, 150)
				end
				self:_OpenPage("Create")
			end
		end)
	end
	primary.Activated:Connect(function()
		choose("START_FREE")
	end)
	makeOwn.Activated:Connect(function()
		choose("MAKE_OWN")
	end)
	skip.Activated:Connect(function()
		choose("SKIP")
	end)
	self:_AnimateModalIn(overlay, modal)
	GuiService.SelectedObject = primary
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

function App:_MarkJourneyOpen()
	local state = self.state
	local journey = state and state.journeyState
	if not state or not journey or journey.completed or (journey.done and journey.done.OPEN_STUDIO) then
		return
	end
	task.spawn(function()
		local success, result = self:_Invoke(Network.Actions.ReportJourneyAction, { action = "OPEN_STUDIO" })
		if success and self.state then
			self.state.journeyState = result
			if self.runwayState then
				self.runwayState.journeyState = result
			end
			self:_RenderActivePage()
		end
	end)
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
		local details = response.details
		local detailedMessage = if type(details) == "table" and type(details.userMessage) == "string"
			then details.userMessage
			else nil
		self:_Toast("error", detailedMessage or ERROR_MESSAGES[code] or "That action could not be completed.")
		return false, code
	end
	if response.data == nil then
		warn(string.format("[App] Remote %s succeeded without response data; using an empty result", action))
		return true, {}
	end
	return true, response.data
end

-- Creation requests can already have opened a purchase prompt, spent tokens,
-- or consumed a retry credit by the time their response reaches the client.
-- Never repeat one just because a malformed success response omitted its data:
-- normalize at the point of use so presentation code cannot crash while the
-- accepted server-side action continues normally.
function App:_GenerationResult(action: string, result: any): { [string]: any }
	if type(result) == "table" then
		return result
	end
	warn(
		string.format(
			"[App] Generation action %s returned %s after success; continuing without repeating the request",
			action,
			typeof(result)
		)
	)
	return {}
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

-- A freshly generated Image/Decal asset can take Roblox's own content
-- moderation and CDN a little while to actually become renderable even
-- though the generation pipeline itself already finished (see
-- docs/ARCHITECTURE.md on the moderation gate) -- without this, the
-- ImageLabel just sits on its plain background color with no indication
-- anything is still happening, which reads as broken rather than pending.
-- Polls via ContentProvider:PreloadAsync -- the same primitive Roblox's own
-- loading screens use to know when content is actually ready -- with
-- backoff, rather than guessing a fixed timer, so `hintLabel` clears the
-- moment the asset actually becomes visible instead of after some arbitrary
-- delay. `imageLabel.Parent` is checked on every iteration as the life
-- token: once the card re-renders (a fresh ImageLabel replaces this one) or
-- the page navigates away, this stops on its own.
local IMAGE_LOAD_RETRY_DELAYS = { 2, 3, 5, 8, 13, 20, 30, 45, 60 }
function App:_WatchImageLoad(
	imageLabel: ImageLabel,
	hintLabel: TextLabel,
	fallbackImage: string?,
	statusContainer: GuiObject?
)
	task.spawn(function()
		local switchedToFallback = false
		for attempt, delaySeconds in IMAGE_LOAD_RETRY_DELAYS do
			if not imageLabel.Parent then
				return
			end
			local loaded = false
			pcall(function()
				ContentProvider:PreloadAsync({ imageLabel }, function(_, status)
					if status == Enum.AssetFetchStatus.Success then
						loaded = true
					end
				end)
			end)
			if not imageLabel.Parent then
				return
			end
			if loaded then
				if statusContainer then
					-- Destroying the gallery's whole status group also stops its
					-- decorative spinner tween; loaded cards should carry no hidden
					-- animation cost after the placeholder disappears.
					statusContainer:Destroy()
				else
					hintLabel.Visible = false
				end
				return
			end
			if
				attempt == 4
				and type(fallbackImage) == "string"
				and fallbackImage ~= ""
				and fallbackImage ~= imageLabel.Image
			then
				imageLabel.Image = fallbackImage
				switchedToFallback = true
				hintLabel.Text = "Roblox is still processing the uploaded preview — trying the model thumbnail…"
			end
			task.wait(delaySeconds)
		end
		if imageLabel.Parent then
			hintLabel.Text = if switchedToFallback
				then "Preview still processing/moderating on Roblox. The model is saved; open Fitting or retry later."
				else "Still awaiting Roblox processing/moderation — this can occasionally take longer than usual."
		end
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

function App:_RefreshAfkDisplay()
	local snapshot = self.afkSnapshot
	if not snapshot or not self.afkOverlay or not self.afkOverlay.Parent then
		return
	end
	local profile = self.state and self.state.profile
	local tokens = if profile then (profile.tokens or 0) else (snapshot.tokens or 0)
	local bonusTokens = if profile then (profile.bonusTokens or 0) else (snapshot.bonusTokens or 0)
	local total = tokens + bonusTokens
	local gained = math.max(0, total - (self.afkStartingTotal or total))
	local remaining = math.max(0, (snapshot.nextRewardAt or os.time()) - os.time())
	if self.afkGainLabel and self.afkGainLabel.Parent then
		self.afkGainLabel.Text = string.format("+%d TOKEN%s THIS VISIT", gained, if gained == 1 then "" else "S")
	end
	if self.afkBalanceLabel and self.afkBalanceLabel.Parent then
		self.afkBalanceLabel.Text = string.format("%s total Forge Tokens", formatNumber(total))
	end
	if self.afkCountdownLabel and self.afkCountdownLabel.Parent then
		self.afkCountdownLabel.Text = if (snapshot.dailyEarned or 0) >= (snapshot.dailyCap or 0)
			then "Daily passive limit reached · rewarded ads remain available"
			else string.format("Next passive token in %ds", remaining)
	end
	if self.afkDailyLabel and self.afkDailyLabel.Parent then
		self.afkDailyLabel.Text = string.format(
			"Passive today: %d / %d · Session: +%d",
			snapshot.dailyEarned or 0,
			snapshot.dailyCap or 0,
			snapshot.sessionEarned or 0
		)
	end
end

function App:_RefreshAfkAdAvailability()
	if self.afkAdChecking or not self.afkOverlay or not self.afkOverlay.Parent then
		return
	end
	self.afkAdChecking = true
	if self.afkAdButton and self.afkAdButton.Parent then
		self.afkAdButton.Active = false
		self.afkAdButton.Text = "Checking ad availability…"
	end
	task.spawn(function()
		local success, result = pcall(function()
			return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		end)
		self.afkAdChecking = false
		if not self.afkOverlay or not self.afkOverlay.Parent then
			return
		end
		local available = success
			and type(result) == "table"
			and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
		self.adAvailable = available
		if self.afkAdButton and self.afkAdButton.Parent then
			self.afkAdButton.Active = available
			self.afkAdButton.Text = if available
				then string.format("Watch next ad · +%d token", Config.Ads.TokenGrantPerAd)
				else "No rewarded ad available yet"
		end
		if self.afkAdStatusLabel and self.afkAdStatusLabel.Parent then
			self.afkAdStatusLabel.Text = if available
				then "AD READY · each ad starts only when you press the button"
				else "AUTO-CHECKING · we'll keep looking while you relax"
			self.afkAdStatusLabel.TextColor3 = if available then Colors.Mint else Colors.TextMuted
		end
	end)
end

function App:_CloseAfkLounge()
	if not self.afkOverlay then
		return
	end
	self.afkRunId += 1
	if self.afkInputConnection then
		self.afkInputConnection:Disconnect()
		self.afkInputConnection = nil
	end
	local overlay = self.afkOverlay
	self.afkOverlay = nil
	overlay:Destroy()
	self.launcher.Visible = not self.shell.Visible
	self.runwayLauncher.Visible = not self.shell.Visible
	self.arcadeLauncher.Visible = not self.shell.Visible
	self.afkLauncher.Visible = not self.shell.Visible
	self.afkSnapshot = nil
	task.spawn(function()
		self:_Invoke(Network.Actions.LeaveAfkLounge, {})
	end)
end

function App:_OpenAfkLounge()
	if self.afkOverlay then
		return
	end
	local success, snapshot = self:_Invoke(Network.Actions.EnterAfkLounge, {})
	if not success then
		return
	end

	self.afkSnapshot = snapshot
	self.afkStartingTotal = (self.state.profile.tokens or 0) + (self.state.profile.bonusTokens or 0)
	self.afkRunId += 1
	local runId = self.afkRunId
	self.launcher.Visible = false
	self.runwayLauncher.Visible = false
	self.arcadeLauncher.Visible = false
	self.afkLauncher.Visible = false

	local overlay = Factory.New("Frame", {
		Name = "AfkTokenLounge",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(2, 3, 10),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 240,
		Parent = self.gui,
	})
	self.afkOverlay = overlay
	Factory.Gradient(overlay, {
		Color3.fromRGB(1, 2, 8),
		Color3.fromRGB(10, 6, 28),
		Color3.fromRGB(2, 9, 19),
	}, 135)

	for _ = 1, 46 do
		local diameter = math.random(2, 5)
		local star = Factory.New("Frame", {
			Name = "Star",
			Position = UDim2.fromScale(math.random(10, 990) / 1000, math.random(10, 990) / 1000),
			Size = UDim2.fromOffset(diameter, diameter),
			BackgroundColor3 = if math.random() > 0.7 then Colors.Cyan else Color3.new(1, 1, 1),
			BackgroundTransparency = math.random(30, 75) / 100,
			BorderSizePixel = 0,
			ZIndex = 241,
			Parent = overlay,
		})
		Factory.Corner(star, diameter)
		if not self.state.profile.settings.reduceMotion then
			TweenService:Create(
				star,
				TweenInfo.new(math.random(12, 30) / 10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.08 }
			):Play()
		end
	end
	local violetCloud = Factory.Blob(overlay, 520, UDim2.new(0.15, -260, 0.35, -260), Color3.fromRGB(87, 56, 210), 0.84)
	violetCloud.ZIndex = 241
	local cyanCloud = Factory.Blob(overlay, 420, UDim2.new(0.88, -210, 0.72, -210), Color3.fromRGB(24, 145, 188), 0.9)
	cyanCloud.ZIndex = 241
	if not self.state.profile.settings.reduceMotion then
		TweenService:Create(
			violetCloud,
			TweenInfo.new(8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = violetCloud.Position + UDim2.fromOffset(44, 24) }
		):Play()
		TweenService:Create(
			cyanCloud,
			TweenInfo.new(10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = cyanCloud.Position + UDim2.fromOffset(-36, -22) }
		):Play()
	end

	local leave =
		Factory.ImageButton(overlay, "← Leave lounge", UDim2.fromOffset(154, 42), UDim2.fromOffset(24, 22), nil)
	leave.ZIndex = 246
	self:_BindButton(leave)
	leave.Activated:Connect(function()
		self:_CloseAfkLounge()
	end)

	local center = Factory.New("Frame", {
		Name = "LoungeCenter",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = if self.compact then UDim2.new(0.9, 0, 0.78, 0) else UDim2.new(0.62, 0, 0.58, 0),
		BackgroundColor3 = Color3.fromRGB(9, 9, 22),
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		ZIndex = 243,
		Parent = overlay,
	})
	Factory.Corner(center, 28)
	Factory.Stroke(center, Colors.Violet, 0.24, 2)
	Factory.New("UISizeConstraint", {
		MinSize = Vector2.new(300, 380),
		MaxSize = Vector2.new(780, 590),
		Parent = center,
	})
	local orbit = Factory.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(70, 70),
		BackgroundColor3 = Colors.Violet,
		BorderSizePixel = 0,
		ZIndex = 244,
		Parent = center,
	})
	Factory.Corner(orbit, 35)
	Factory.Gradient(orbit, { Colors.Violet, Colors.Cyan, Colors.Rose }, 45)
	Factory.Label(orbit, "✧", UDim2.fromScale(1, 1), {
		Font = Theme.Fonts.Black,
		TextSize = 34,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 245,
	})
	Factory.Label(center, "ORBITAL TOKEN LOUNGE", UDim2.new(1, -40, 0, 38), {
		Position = UDim2.fromOffset(20, 96),
		Font = Theme.Fonts.Black,
		TextSize = if self.compact then 21 else 27,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 244,
	})
	self.afkBalanceLabel = Factory.Label(center, "", UDim2.new(1, -40, 0, 26), {
		Position = UDim2.fromOffset(20, 132),
		Color = Colors.Gold,
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 244,
	})
	self.afkCountdownLabel = Factory.Label(center, "", UDim2.new(1, -48, 0, 28), {
		Position = UDim2.fromOffset(24, 169),
		Color = Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		AlignX = Enum.TextXAlignment.Center,
		Wrapped = true,
		ZIndex = 244,
	})
	self.afkDailyLabel = Factory.Label(center, "", UDim2.new(1, -48, 0, 22), {
		Position = UDim2.fromOffset(24, 201),
		Color = Colors.TextMuted,
		TextSize = 11,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 244,
	})
	local adButton = Factory.ImageButton(
		center,
		"Checking ad availability…",
		UDim2.new(1, -70, 0, 48),
		UDim2.fromOffset(35, 235),
		"mint"
	)
	adButton.ZIndex = 244
	adButton.Active = false
	self:_BindButton(adButton)
	self.afkAdButton = adButton
	self.afkAdStatusLabel = Factory.Label(center, "", UDim2.new(1, -48, 0, 34), {
		Position = UDim2.fromOffset(24, 291),
		Color = Colors.TextMuted,
		TextSize = 10,
		AlignX = Enum.TextXAlignment.Center,
		Wrapped = true,
		ZIndex = 244,
	})
	Factory.Label(
		center,
		"Passive rewards are bonus tokens for Priority Passes. Roblox may disconnect fully idle players, so check in occasionally.",
		UDim2.new(1, -48, 0, 48),
		{
			Position = UDim2.fromOffset(24, 329),
			Color = Colors.TextMuted,
			TextSize = 10,
			AlignX = Enum.TextXAlignment.Center,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
			ZIndex = 244,
		}
	)
	adButton.Activated:Connect(function()
		adButton.Active = false
		adButton.Text = "Checking ad availability…"
		task.spawn(function()
			local checkSuccess, checkResult = pcall(function()
				return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
			end)
			local available = checkSuccess
				and type(checkResult) == "table"
				and checkResult.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
			if not available then
				self:_Toast("error", "No ad is available right now. The lounge will keep checking.")
				self:_RefreshAfkAdAvailability()
				return
			end
			adButton.Text = "Playing rewarded ad…"
			local adSuccess, result = self:_Invoke(Network.Actions.RequestRewardedAd, {})
			if adSuccess then
				self.adWatchesToday = result.watchesToday
				self:_Toast("ready", "Ad completed. Roblox is delivering your token.")
			end
			task.delay(2, function()
				self:_RefreshAfkAdAvailability()
			end)
		end)
	end)

	self.afkGainLabel = Factory.Label(overlay, "+0 TOKENS THIS VISIT", UDim2.new(0.8, 0, 0, 48), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Font = Theme.Fonts.Black,
		TextSize = if self.compact then 20 else 25,
		Color = Colors.Mint,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 246,
	})

	self.afkInputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.afkOverlay ~= overlay then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			self:_CloseAfkLounge()
		end
	end)
	GuiService.SelectedObject = leave
	self:_RefreshAfkDisplay()
	self:_RefreshAfkAdAvailability()
	self:_Track({ event = "AfkLoungeOpened", fields = {} })
	task.spawn(function()
		local lastAdCheck = os.clock()
		while self.afkRunId == runId and self.afkOverlay == overlay and overlay.Parent do
			task.wait(1)
			self:_RefreshAfkDisplay()
			if os.clock() - lastAdCheck >= 30 and not self.afkAdChecking and self.adAvailable ~= true then
				lastAdCheck = os.clock()
				self:_RefreshAfkAdAvailability()
			end
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
		self.runwayState = data.runwayState
		self.adWatchesToday = watchesTodayFromProfile(data.profile)
		self.sounds:SetEnabled(data.profile.settings.soundsEnabled ~= false)
		if data.profile.settings.highContrast == true then
			Theme.SetHighContrast(true)
			self.gui:Destroy()
			self:_BuildChrome()
		end
		self:_ApplyLauncherEmphasis()
		self.uiScaleInstance.Scale = tonumber(data.profile.settings.uiScale) or 1
		self:_UpdateSoundButton()
		self:_SetAmbientMotion(data.profile.settings.reduceMotion ~= true)
		self.loading:Destroy()
		self:_RenderStatus()
		self:_ConnectPush()
		self:_OpenPage("Create")
		self:_RefreshLocalizedPrices()
		if (data.profile.stats.generationsCompleted or 0) == 0 then
			-- Open the useful destination immediately, but do not silently
			-- complete onboarding. The visual tutorial records the path the
			-- player actually chooses and then repeats OPEN_STUDIO after the
			-- server permits the free First Look journey.
			self:_SetStudioOpen(true)
			self:_RenderActivePage()
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
				table.insert(
					parts,
					string.format(
						"Day %d login: +%d bonus Forge Tokens",
						data.dailyBrief.rewardDay or 1,
						data.dailyBrief.tokensGranted
					)
				)
			end
			if data.dailyBrief.rewardGranted then
				table.insert(
					parts,
					string.format("%d-day streak reward: one free Priority Pass", data.dailyBrief.streak)
				)
			end
			if data.dailyBrief.milestoneReward then
				local milestone = data.dailyBrief.milestoneReward
				local milestoneText = string.format(
					"🏆 %d-day milestone: +%d Priority Pass%s",
					milestone.day,
					milestone.priorityPasses,
					if milestone.priorityPasses == 1 then "" else "es"
				)
				if (milestone.tokens or 0) > 0 then
					milestoneText ..= string.format(" and +%d tokens", milestone.tokens)
				end
				table.insert(parts, milestoneText)
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
		if (tonumber(data.profile.tutorialVersion) or 0) < Config.Tutorial.Version then
			task.defer(function()
				if self.state == data and self.gui.Parent then
					self:_ShowVisualTutorial()
				end
			end)
		end
	end)
end

function App:_RefreshBootstrap()
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.Bootstrap, {})
		if success then
			self.state = data
			self.runwayState = data.runwayState
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
	-- _BuildAvatarPreviewPanel wires connections (relayout, ResetCamera) and
	-- ViewportController owns its own (drag/zoom input) that gui:Destroy()
	-- below won't tear down on its own -- only destroying the Instance tree,
	-- not running our Lua-side :Destroy() cleanup -- so the controller has to
	-- go first, same as _RenderActivePage already does for activeViewport.
	if self.avatarPreviewViewportController then
		self.avatarPreviewViewportController:Destroy()
		self.avatarPreviewViewportController = nil
	end
	self.avatarPreviewDirty = true
	self.gui:Destroy()
	self:_BuildChrome()
	self.loading:Destroy()
	self.shell.Visible = wasOpen
	self.launcher.Visible = not wasOpen
	self.runwayLauncher.Visible = not wasOpen
	self.arcadeLauncher.Visible = not wasOpen
	self.afkLauncher.Visible = not wasOpen
	self:_UpdateSoundButton()
	-- _BuildChrome creates fresh blob/ember instances but doesn't itself
	-- know whether ambient motion should be running -- carry the previous
	-- state over rather than defaulting back to off.
	self:_SetAmbientMotion(motionWasEnabled)
	self:_RenderStatus()
	self:_RenderActivePage()
end

function App:_ShowCreationComplete(kind: string, record: { [string]: any }, completionId: string)
	if self.completionShownIds[completionId] then
		return
	end
	self.completionShownIds[completionId] = true
	if self.completionOverlay then
		self.completionOverlay:Destroy()
	end

	local title = if kind == "MODEL"
		then "YOUR MODEL IS READY"
		elseif kind == "REFERENCE" then "REFERENCE IMAGE READY"
		else "YOUR IMAGE IS READY"
	local subtitle = if kind == "MODEL"
		then "The forge cooled perfectly. Fit it, equip it, and make it yours."
		elseif kind == "REFERENCE" then "Your concept has arrived. Review it, then send it into the 3D forge."
		else "Fresh from the renderer and saved in your Avatar Graphics gallery."
	local imageId = record.thumbnailAssetId or record.previewAssetId
	local previewImage = if kind == "MODEL" then modelPreviewImage(record) else directImage(imageId)
	local overlay = Factory.New("Frame", {
		Name = "CreationComplete",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 4, 15),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 300,
		Parent = self.gui,
	})
	self.completionOverlay = overlay
	local glow = Factory.Blob(
		overlay,
		620,
		UDim2.new(0.5, -310, 0.5, -310),
		if kind == "MODEL" then Colors.Violet else Colors.Cyan,
		0.78
	)
	glow.ZIndex = 301
	local card = Factory.New("Frame", {
		Name = "CelebrationCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if self.compact then UDim2.new(0.9, 0, 0.78, 0) else UDim2.fromOffset(570, 600),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ZIndex = 303,
		Parent = overlay,
	})
	Factory.Corner(card, 28)
	Factory.Stroke(card, if kind == "MODEL" then Colors.Violet else Colors.Cyan, 0.12, 2)
	Factory.New("UISizeConstraint", {
		MinSize = Vector2.new(300, 430),
		MaxSize = Vector2.new(570, 600),
		Parent = card,
	})
	local badge = Factory.ImagePill(card, if kind == "MODEL" then "FORGED" else "CREATED", Colors.Mint, 112)
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 25)
	badge.ZIndex = 304
	Factory.Label(card, title, UDim2.new(1, -40, 0, 40), {
		Position = UDim2.fromOffset(20, 62),
		Font = Theme.Fonts.Black,
		TextSize = if self.compact then 22 else 28,
		AlignX = Enum.TextXAlignment.Center,
		ZIndex = 304,
	})
	Factory.Label(card, subtitle, UDim2.new(1, -56, 0, 48), {
		Position = UDim2.fromOffset(28, 102),
		Color = Colors.TextMuted,
		TextSize = 12,
		Wrapped = true,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Top,
		ZIndex = 304,
	})
	local preview = Factory.New("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 162),
		Size = if self.compact then UDim2.new(0.68, 0, 0.42, 0) else UDim2.fromOffset(300, 300),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		Image = previewImage,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 304,
		Parent = card,
	})
	Factory.Corner(preview, 22)
	Factory.Stroke(preview, Colors.Cyan, 0.3, 1.5)
	if previewImage == "" then
		Factory.Label(preview, if kind == "MODEL" then "◇" else "❑", UDim2.fromScale(1, 1), {
			Font = Theme.Fonts.Black,
			TextSize = 76,
			Color = if kind == "MODEL" then Colors.Violet else Colors.Cyan,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 305,
		})
	end
	local previewHint = Factory.Label(
		preview,
		if kind == "MODEL" then "Checking Roblox preview processing…" else "Checking Roblox image processing…",
		UDim2.new(1, -20, 0, 42),
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -10),
			Color = Colors.Text,
			TextSize = 11,
			Wrapped = true,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			ZIndex = 306,
		}
	)
	previewHint.BackgroundColor3 = Colors.Ink
	previewHint.BackgroundTransparency = 0.12
	Factory.Corner(previewHint, 9)
	if previewImage ~= "" then
		self:_WatchImageLoad(preview, previewHint, if kind == "MODEL" then thumbnail(record.modelAssetId, 420) else nil)
	else
		previewHint.Text = "Roblox has not issued a preview yet. The creation is saved; open it again shortly."
	end
	local close = Factory.ImageButton(card, "×", UDim2.fromOffset(38, 38), UDim2.new(1, -50, 0, 12), nil)
	close.TextSize = 20
	close.ZIndex = 305
	self:_BindButton(close)
	local view = Factory.ImageButton(
		card,
		if kind == "MODEL" then "Fit this model" elseif kind == "REFERENCE" then "Review reference" else "Open gallery",
		UDim2.new(0.5, -27, 0, 46),
		UDim2.new(0, 18, 1, -64),
		"primary"
	)
	view.ZIndex = 305
	self:_BindButton(view)
	local another =
		Factory.ImageButton(card, "Create another", UDim2.new(0.5, -27, 0, 46), UDim2.new(0.5, 9, 1, -64), "mint")
	another.ZIndex = 305
	self:_BindButton(another)

	local function dismiss()
		if self.completionOverlay == overlay then
			self.completionOverlay = nil
		end
		overlay:Destroy()
	end
	close.Activated:Connect(dismiss)
	view.Activated:Connect(function()
		dismiss()
		self:_SetStudioOpen(true)
		if kind == "MODEL" then
			self.selectedItemId = record.id
			self:_OpenPage("My Studio")
		elseif kind == "GRAPHIC" then
			self.graphicsTab = "CREATE"
			self:_OpenPage("Avatar Graphics")
		else
			self:_OpenPage("Create")
		end
	end)
	another.Activated:Connect(function()
		dismiss()
		self:_SetStudioOpen(true)
		self:_OpenPage("Create")
	end)
	self.sounds:Play("GenerationReady")
	self:_AnimateModalIn(overlay, card)
	if self.state.profile.settings.reduceMotion ~= true then
		for _ = 1, 24 do
			local particle = Factory.New("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.48),
				Size = UDim2.fromOffset(math.random(5, 11), math.random(5, 11)),
				BackgroundColor3 = ({ Colors.Gold, Colors.Cyan, Colors.Rose, Colors.Mint })[math.random(1, 4)],
				BorderSizePixel = 0,
				Rotation = math.random(0, 180),
				ZIndex = 302,
				Parent = overlay,
			})
			Factory.Corner(particle, 3)
			local target = UDim2.fromScale(math.random(8, 92) / 100, math.random(8, 92) / 100)
			local tween = TweenService:Create(
				particle,
				TweenInfo.new(math.random(8, 16) / 10, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = target, BackgroundTransparency = 1, Rotation = particle.Rotation + math.random(90, 300) }
			)
			tween:Play()
			tween.Completed:Connect(function()
				particle:Destroy()
			end)
		end
	end
	GuiService.SelectedObject = view
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
			self:_RefreshAfkDisplay()
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
				if
					generation.stage == "IMAGE_READY"
					and generation.previewAssetId ~= nil
					and generation.itemId == nil
				then
					self:_ShowCreationComplete("REFERENCE", generation, "reference:" .. payload.generationId)
				end
				if self.activePage == "Create" then
					self:_RenderActivePage()
				end
			else
				task.delay(0.25, function()
					self:_RefreshBootstrap()
				end)
			end
		elseif eventName == Network.PushEvents.Item then
			local profile = self.state.profile
			local isNew = payload.item and profile.items[payload.itemId] == nil
			if payload.item then
				profile.items[payload.itemId] = payload.item
				if not table.find(profile.itemOrder, payload.itemId) then
					table.insert(profile.itemOrder, 1, payload.itemId)
				end
				if isNew then
					self:_ShowCreationComplete("MODEL", payload.item, "item:" .. payload.itemId)
				end
			end
			self:_RenderActivePage()
			task.delay(0.5, function()
				self:_RefreshBootstrap()
			end)
		elseif eventName == Network.PushEvents.Graphic then
			local profile = self.state.profile
			if payload.deleted then
				profile.graphics[payload.graphicId] = nil
				local index = table.find(profile.graphicOrder, payload.graphicId)
				if index then
					table.remove(profile.graphicOrder, index)
				end
			elseif payload.graphic then
				local isNew = profile.graphics[payload.graphicId] == nil
				profile.graphics[payload.graphicId] = payload.graphic
				if not table.find(profile.graphicOrder, payload.graphicId) then
					table.insert(profile.graphicOrder, 1, payload.graphicId)
				end
				if isNew then
					self:_ShowCreationComplete("GRAPHIC", payload.graphic, "graphic:" .. payload.graphicId)
				end
			end
			self:_RenderActivePage()
		elseif eventName == Network.PushEvents.Transfer then
			task.delay(0.2, function()
				self:_RefreshBootstrap()
			end)
		elseif eventName == Network.PushEvents.Afk then
			self.afkSnapshot = payload
			self:_RefreshAfkDisplay()
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
		elseif eventName == Network.PushEvents.Runway then
			self.runwayState = payload
			self.state.runwayState = payload
			self.state.creatorProgress = payload.creatorProgress or self.state.creatorProgress
			self.state.journeyState = payload.journeyState or self.state.journeyState
			if self.runwayRefresh then
				self.runwayRefresh(payload)
			end
			self:_RenderStatus()
		elseif eventName == Network.PushEvents.Journey then
			self.state.journeyState = payload.state
			if self.runwayState then
				self.runwayState.journeyState = payload.state
			end
			if self.runwayRefresh and self.runwayState then
				self.runwayRefresh(self.runwayState)
			end
			self:_RenderActivePage()
		elseif eventName == Network.PushEvents.CreatorProgress then
			self.state.profile.creator = payload.creator
			self.state.creatorProgress = payload.progress
			if self.runwayState then
				self.runwayState.creatorProgress = payload.progress
			end
			if self.runwayRefresh and self.runwayState then
				self.runwayRefresh(self.runwayState)
			end
			self:_RenderStatus()
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
	local creator = self.state.creatorProgress
	-- Small cut-gem stud on the left of each badge, matching the concept
	-- art's status pills -- a no-op (pill just keeps its plain look) while
	-- that gem asset's id is still 0.
	local function gemIcon(pill: TextLabel, assetKey: string)
		local icon = Factory.Icon(pill, assetKey, UDim2.fromOffset(14, 14), UDim2.fromOffset(10, 6))
		if icon then
			icon.ZIndex = 6
		end
	end
	if creator then
		local pill =
			Factory.ImagePill(self.statusArea, string.format("LV. %d CREATOR", creator.level or 1), Colors.Gold, 112)
		pill.LayoutOrder = 1
		gemIcon(pill, "GemGold")
	end
	-- Sidebar creator-rank crest (see _BuildChrome) -- same data as the
	-- topbar's level pill above, refreshed alongside it on every
	-- CreatorProgress push.
	if creator and self.creatorLevelLabel then
		self.creatorLevelLabel.Text = tostring(creator.level or 1)
		self.creatorXPLabel.Text =
			string.format("%s / %s XP", formatNumber(creator.xp or 0), formatNumber(creator.nextLevelXP or 0))
		if self.creatorRingUpdate then
			self.creatorRingUpdate(creator.levelProgress or 0)
		end
	end
	if daily then
		local pill =
			Factory.ImagePill(self.statusArea, string.format("🔥 %d DAY STREAK", daily.streak), Colors.Rose, 112)
		pill.LayoutOrder = 2
		gemIcon(pill, "GemRuby")
	end
	do
		local pill = Factory.ImagePill(
			self.statusArea,
			string.format("%d QUEUE SLOT%s", benefits.queueSlots, if benefits.queueSlots == 1 then "" else "S"),
			Colors.Cyan,
			118
		)
		pill.LayoutOrder = 3
		gemIcon(pill, "GemCyan")
	end
	do
		local pill = Factory.ImagePill(
			self.statusArea,
			if benefits.plusSubscriber then "PLUS ACTIVE" else "PLUS: SELL ONLY",
			if benefits.plusSubscriber then Colors.Mint else Colors.Gold,
			124
		)
		pill.LayoutOrder = 4
		gemIcon(pill, if benefits.plusSubscriber then "GemMint" else "GemRose")
	end
end

function App:_OpenPage(page: string)
	self.activePage = page
	self.sounds:Play("PanelOpen")
	self:_HighlightNavigation()
	self:_RenderActivePage()
	self:_Track({ event = "AppOpenedTab", fields = { page = page } })
	-- Opening Discover (or Avatar Lab when community sharing is policy-
	-- unavailable) is now the actual free First Look. Record the journey
	-- only when a player intentionally reaches it, not automatically while
	-- their profile is merely booting behind the onboarding modal.
	if
		(page == "Discover" or page == "Avatar Lab")
		and self.state
		and self.state.profile.onboarding.completed == true
	then
		self:_MarkJourneyOpen()
	end
end

function App:_HighlightNavigation()
	for page, button in self.navButtons do
		local active = page == self.activePage
		self:_Animate(
			button,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad),
			{ BackgroundColor3 = if active then Colors.Violet else Colors.PanelSoft }
		)
		-- Once a real PanelFrame/ButtonPrimary/etc. decal is live, the button's
		-- own BackgroundColor3 above is invisible (its background is fully
		-- transparent behind the opaque image) -- swap the decal itself
		-- between the molten ButtonPrimary look and the plain ButtonDefault
		-- one instead, a no-op fallback to the tween above while either id is
		-- still 0.
		Factory.SwapDecal(button, if active then "ButtonPrimary" else "ButtonDefault")
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

-- _RenderActivePage tears down and rebuilds every ScrollingFrame from
-- scratch on every re-render -- which happens far more often than an actual
-- page change: any click that touches state, and every ~4s of generation-
-- progress polling while Create is open (see the AmbientBackground comment
-- above). A freshly created ScrollingFrame always starts at CanvasPosition
-- (0,0), so without this a player scrolled partway down would get silently
-- snapped back to the top on the next unrelated re-render. `key` must be
-- unique and stable across re-renders of the same scroll region (not the
-- Instance itself, which is destroyed and recreated every time) --
-- self.scrollPositions lives on the App object, not under self.content, so
-- it survives the destroy/rebuild cycle that wipes the ScrollingFrame.
function App:_TrackScroll(scrollingFrame: ScrollingFrame, key: string)
	local saved = self.scrollPositions[key]
	if saved then
		-- Every one of these ScrollingFrames uses AutomaticCanvasSize, and at
		-- the moment it's created (right before its children get built below
		-- it in the same render pass) its canvas is still empty. Restoring
		-- CanvasPosition immediately here gets silently clamped back to
		-- (0, 0) -- there's nothing to scroll to yet -- which is exactly why
		-- the previous version of this fix still snapped back to the top on
		-- every re-render. Waiting one Heartbeat lets Roblox finish the
		-- UIListLayout + AutomaticCanvasSize pass for everything this render
		-- just added before the restore is attempted.
		local version = self.pageVersion
		task.spawn(function()
			RunService.Heartbeat:Wait()
			if version == self.pageVersion and scrollingFrame.Parent then
				scrollingFrame.CanvasPosition = saved
			end
		end)
	end
	table.insert(
		self.pageConnections,
		scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self.scrollPositions[key] = scrollingFrame.CanvasPosition
		end)
	)
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
		self:_SyncAvatarPreviewPanel()
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
	elseif self.activePage == "Avatar Graphics" then
		self:_RenderAvatarGraphics()
	else
		self:_RenderSettings()
	end
	self:_SyncAvatarPreviewPanel()
end

function App:_PageHeader(title: string, subtitle: string, accent: boolean?)
	Factory.Label(self.content, title, UDim2.new(0.95, 0, 0, 42), {
		Position = UDim2.new(0.025, 0, 0, 18),
		Font = Theme.Fonts.Black,
		TextSize = 28,
	})
	if accent then
		-- The concept art's small flourish ornament next to the page
		-- title -- only Create opts in for now (accent is optional and
		-- defaults to off) since it's the only page checked pixel-for-
		-- pixel against its mockup so far. Anchored to the header's own
		-- right edge rather than after the title text, since a
		-- TextLabel's rendered width isn't available synchronously here.
		Factory.Icon(self.content, "FlourishDivider", UDim2.fromOffset(26, 15), UDim2.new(0.95, -26, 0, 32))
	end
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

-- The concept art gives exactly one field per page the "glowing inscription
-- well" treatment -- Create's idea prompt, Discover's and Avatar Lab's
-- search bars -- rather than every textbox _TextBox builds across the app,
-- so this overrides that one instance's stroke instead of the default.
-- `studCorners` adds the small diamond accents the art puts on the taller
-- multi-line wells; a single-line search bar has no room for them, and the
-- art doesn't draw them there either.
function App:_GlowField(box: TextBox, studCorners: boolean?)
	local stroke = box:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Colors.Cyan
		stroke.Transparency = 0.3
		stroke.Thickness = 1.6
	end
	if not studCorners then
		return
	end
	for _, corner in { "left", "right" } do
		local stud = Factory.Icon(
			box,
			"SparkleStar",
			UDim2.fromOffset(10, 10),
			if corner == "left" then UDim2.fromOffset(6, 6) else UDim2.new(1, -16, 0, 6)
		)
		if stud then
			stud.ZIndex = 6
			stud.ImageColor3 = Colors.Cyan
		end
	end
end

function App:_RenderCreate()
	-- Simple Mode is a real, persisted setting (profile.settings.
	-- simpleMode, defaulting true for every account -- see ProfileService's
	-- defaultProfile), not a one-time first-timer nicety: a player picks
	-- it, in Settings or via the switch link below, and it stays picked
	-- across sessions until they change it back. In Simple Mode, Create
	-- shows one method instead of four, no reference-image/upload/avatar
	-- jargon, and a few tappable example prompts near the text box -- the
	-- full four-method, art-direction-heavy page is exactly one tap away,
	-- never removed, just not the default for an audience that skews young.
	local simpleMode = self.state.profile.settings.simpleMode ~= false
	local showAllMethods = not simpleMode
	-- A player can enter Simple Mode after selecting an advanced method in the
	-- same session. Keep the hidden state honest: the one visible creator is
	-- always Direct Forge, never a stale image/avatar method with mismatched
	-- copy and price.
	if simpleMode then
		self.selectedMethod = "TEXT_TO_3D"
	end
	self:_PageHeader(
		if showAllMethods
			then "Create something impossible"
			else if self.compact then "Make an item" else "Make your own Roblox item",
		if showAllMethods
			then "Three paths, precise art direction, one Roblox-ready accessory. Every input is moderated."
			else "Pick an idea or type one. Roblox shows the price and asks before you buy.",
		true
	)
	local howToPlay = Factory.ImageButton(
		self.content,
		if self.compact then "?" else "?  HOW TO PLAY",
		UDim2.fromOffset(if self.compact then 34 else 122, 30),
		UDim2.new(1, if self.compact then -46 else -138, 0, 16),
		nil
	)
	howToPlay.TextSize = if self.compact then 10 else 11
	self:_BindButton(howToPlay)
	howToPlay.Activated:Connect(function()
		self:_ShowVisualTutorial()
	end)
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
	self:_TrackScroll(page, "Create")
	Factory.ScalePadding(page, 0.012, 0.012)
	-- The concept art runs a narrower right rail (Tokens/Daily Quests/In
	-- the Forge/queue) alongside the main Direct Forge + prompt column
	-- instead of stacking everything in one long scroll. `columns` only
	-- exists in wide layouts -- compact keeps the old single-column stack,
	-- since a ~37%-width rail would be unreadable at phone-ish widths.
	-- `rightStack` collapsing back to the same `stack` in compact mode
	-- means every card below just keeps working unchanged there.
	local columns = if self.compact
		then nil
		else Factory.New("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = page,
		})
	if columns then
		Factory.List(columns, Enum.FillDirection.Horizontal, 20)
	end
	local stack = Factory.New("Frame", {
		Size = if self.compact then UDim2.new(1, -8, 0, 0) else UDim2.new(0.63, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = if self.compact then page else columns,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 14)
	local rightStack = if self.compact
		then stack
		else Factory.New("Frame", {
			Size = UDim2.new(0.37, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = columns,
		})
	if not self.compact then
		Factory.List(rightStack, Enum.FillDirection.Vertical, 14)
	end

	-- The real first-session path, kept visible on Create until completed.
	-- It produces a satisfying outfit/runway result without requiring a paid
	-- AI call, then becomes a permanent shortcut back to the social loop.
	local firstLook = self.state.journeyState
	if firstLook then
		local complete = firstLook.completed == true
		local done = firstLook.done or {}
		local card = Factory.ImageCard(stack, UDim2.new(1, 0, 0, if self.compact then 158 else 132), nil, "FirstLook")
		card.LayoutOrder = if simpleMode then -30 else -1
		local icon = Factory.New("Frame", {
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(16, 16),
			BackgroundColor3 = if complete then Colors.Mint else Colors.Rose,
			BorderSizePixel = 0,
			Parent = card,
		})
		Factory.Corner(icon, 15)
		Factory.Gradient(icon, if complete then { Colors.Mint, Colors.Cyan } else { Colors.Rose, Colors.Violet }, 135)
		Factory.Label(icon, if complete then "✓" else "◆", UDim2.fromScale(1, 1), {
			Font = Theme.Fonts.Black,
			TextSize = 20,
			Color = if complete then Colors.Ink else Colors.Text,
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
		})
		Factory.Label(
			card,
			if complete then "First Look complete" else "Try a look for FREE",
			UDim2.new(1, if self.compact then -88 else -240, 0, 26),
			{
				Position = UDim2.fromOffset(72, 13),
				Font = Theme.Fonts.Black,
				TextSize = 17,
				Truncate = Enum.TextTruncate.AtEnd,
			}
		)
		Factory.Label(
			card,
			if complete
				then "Keep leveling up in six-minute Forge Runway style battles."
				else "Put a creator's item on your avatar, then join a runway round. No Robux needed.",
			UDim2.new(if self.compact then 1 else 0.68, if self.compact then -32 else -80, 0, 38),
			{
				Position = UDim2.fromOffset(if self.compact then 16 else 72, if self.compact then 67 else 42),
				Color = Colors.TextMuted,
				TextSize = 11,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
		local total = math.max(1, firstLook.total or #Config.Retention.FirstLookJourney)
		local progress = if complete then 1 else math.clamp((firstLook.doneCount or 0) / total, 0, 1)
		local track = Factory.New("Frame", {
			Position = UDim2.fromOffset(16, if self.compact then 104 else 92),
			Size = UDim2.new(if self.compact then 1 else 0.68, if self.compact then -32 else -32, 0, 9),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = card,
		})
		Factory.Corner(track, 5)
		local fill = Factory.New("Frame", {
			Size = UDim2.new(progress, 0, 1, 0),
			BackgroundColor3 = if complete then Colors.Mint else Colors.Rose,
			BorderSizePixel = 0,
			Parent = track,
		})
		Factory.Corner(fill, 5)
		local continue = Factory.ImageButton(
			card,
			if complete
				then "Open Forge Runway"
				else if not done.TRY_STYLE then "START FREE →" else "Enter Forge Runway →",
			if self.compact then UDim2.new(1, -32, 0, 36) else UDim2.new(0.27, -12, 0, 42),
			if self.compact then UDim2.fromOffset(16, 116) else UDim2.new(0.72, 0, 0, 45),
			if complete then "mint" else "primary"
		)
		self:_BindButton(continue)
		continue.Activated:Connect(function()
			if not done.OPEN_STUDIO or not done.TRY_STYLE then
				self:_OpenPage(if self.state.policy.contentSharingAllowed then "Discover" else "Avatar Lab")
			else
				RunwayHub.Show(self)
			end
		end)
	end

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
	local tokensDescriptionText = if simpleMode
		then "Watch ads for spendable tokens, or buy 70. Free reward tokens only speed up finished creations."
		else "Earn tokens by watching ads. Ad tokens fund generations or the Pass; "
			.. "free tokens (achievements, streaks) fund the Pass only."
	-- Right-hand controls: this card now always sits in a narrow column --
	-- the page-compact single stack, or the desktop right rail (~37% of
	-- content width, see `columns`/`rightStack` above) -- so the "PAY
	-- WITH" column always collapses to full width BELOW the balance/
	-- description now, the way it used to only in compact. Its start
	-- (payLabelY) has to clear however tall that description wraps to,
	-- not a number guessed once and left to drift the next time the copy
	-- changes -- that mismatch is exactly how the description text
	-- overlapping "PAY WITH" would happen.
	local rightX = 0
	local rightWidth = 1
	local inset = 16
	local gap = 8
	local tokensDescriptionY = 70
	-- Was 46, sized back when this label was only ever 42% of a much wider
	-- card (see the width fix below) -- at this card's real width now
	-- (always narrow: the compact single stack, or the ~37%-wide right
	-- rail) the same copy wraps to more, shorter lines and needs more
	-- room, or it overflows past this box's bottom edge into "PAY WITH".
	local tokensDescriptionHeight = 64
	local payLabelY = tokensDescriptionY + tokensDescriptionHeight + 12
	local toggleY = payLabelY + 20
	local watchAdY = toggleY + 38
	local buyTokensY = watchAdY + 42
	local tokensCardHeight = buyTokensY + 30 + 16
	local tokensCard = Factory.ImageCard(rightStack, UDim2.new(1, 0, 0, tokensCardHeight), nil, "TokensCard")
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
	-- Full card width now (was 0.42, left over from when "PAY WITH" sat
	-- beside this description in a wide card) -- the card is always
	-- narrow now, so there's no side-by-side column to leave room for.
	Factory.Label(tokensCard, tokensDescriptionText, UDim2.new(1, -32, 0, tokensDescriptionHeight), {
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
	local payRobux = Factory.ImageButton(
		tokensCard,
		"Robux",
		toggleWidth,
		UDim2.new(rightX, inset, 0, toggleY),
		if self.paymentMethod == "ROBUX" then "primary" else nil
	)
	local payTokens = Factory.ImageButton(
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
	local watchAd = Factory.ImageButton(
		tokensCard,
		if self.adAvailabilityChecking
			then "Checking for an ad…"
			elseif self.adAvailable == false then "No ad available right now"
			else string.format(
				"Watch ad · +%d token%s%s",
				Config.Ads.TokenGrantPerAd,
				if Config.Ads.TokenGrantPerAd == 1 then "" else "s",
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
		watchAd.Text = "Checking for an ad…"
		task.spawn(function()
			-- Re-check availability right before showing, per Roblox's own
			-- guidance, instead of trusting whatever self.adAvailable was
			-- left at from when this page first loaded. Skipping this was
			-- the actual bug behind "closed before it finished" repeating
			-- on every later click: the first watch succeeds, but this
			-- button then stayed enabled indefinitely off that stale flag,
			-- so every next click re-showed an ad Roblox had no fresh
			-- inventory for yet and failed with a misleading message.
			local checkSuccess, checkResult = pcall(function()
				return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
			end)
			local nowAvailable = checkSuccess
				and type(checkResult) == "table"
				and checkResult.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
			self.adAvailable = nowAvailable
			if not nowAvailable then
				self:_Toast("error", "No ad is available right now. Try again in a few minutes.")
				self:_RenderActivePage()
				return
			end
			watchAd.Text = "Loading ad…"
			local success, result = self:_Invoke(Network.Actions.RequestRewardedAd, {})
			if success then
				self.adWatchesToday = result.watchesToday
				self:_Toast("ready", "Thanks for watching! Your tokens are on the way.")
			end
			self:_RenderActivePage()
		end)
	end)
	local buyTokens = Factory.ImageButton(
		tokensCard,
		string.format(
			"Buy %d token%s · R$ %d",
			Config.Ads.TokenPackGrant,
			if Config.Ads.TokenPackGrant == 1 then "" else "s",
			self.state.prices.TokenPack70
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
	local allMethods = {
		{
			id = "TEXT_TO_3D",
			title = if showAllMethods then "Direct Forge" else "Your custom item",
			kicker = if showAllMethods then "FASTEST VALUE" else "AI CREATION",
			body = if showAllMethods
				then "Text → Smart Topology 3D. Lower cost and ideal for bold, simple silhouettes."
				else "Forge turns your words into one 3D item you can fit and wear in this game.",
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
		{
			id = "AVATAR_TO_3D",
			title = "My Avatar",
			kicker = "INSTANT SOURCE",
			body = "Your current Roblox avatar → 3D. Nothing to upload -- we fetch your look automatically.",
			price = self.state.prices.AvatarConversion,
			color = Colors.Mint,
		},
	}
	-- A first-timer only ever sees Direct Forge -- the cheapest, simplest
	-- path -- so the very first thing Create shows isn't a 4-way decision
	-- between jargon like "Smart Topology" and "reference quality tier".
	-- "Show more ways to create" below reveals the rest on demand, and
	-- self.selectedMethod already defaults to TEXT_TO_3D, so nothing about
	-- the actual generation call changes for someone who never expands it.
	local visibleMethods = if showAllMethods then allMethods else { allMethods[1] }
	local methodRow = Factory.New("Frame", {
		Size = UDim2.new(1, 0, 0, if showAllMethods then (if self.compact then 656 else 364) else 210),
		BackgroundTransparency = 1,
		LayoutOrder = if simpleMode then -10 else 1,
		Parent = stack,
	})
	for index, method in visibleMethods do
		-- 2x2 grid in wide mode (156px cards, 12px column gap, 8px row gap --
		-- see the compact-mode stack below for the matching vertical rhythm),
		-- 4-tall stack in compact mode; a single full-width card when
		-- collapsed. methodRow.Size above is derived from these same
		-- constants, not eyeballed.
		local col = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local card = if not showAllMethods
			then Factory.ImageCard(methodRow, UDim2.new(1, 0, 0, 156))
			elseif self.compact then Factory.ImageCard(
				methodRow,
				UDim2.new(1, 0, 0, 144),
				UDim2.fromOffset(0, (index - 1) * 156)
			)
			else Factory.ImageCard(
				methodRow,
				UDim2.new(0.5, -6, 0, 156),
				UDim2.new(col * 0.5, col * 6, 0, row * 164)
			)
		local selected = self.selectedMethod == method.id
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if selected then method.color else Colors.Line
			stroke.Transparency = if selected then 0.12 else 0.55
			stroke.Thickness = if selected then 2 else 1
		end
		if method.id == "TEXT_TO_3D" and not showAllMethods then
			-- The concept art's mid-edge rivet studs on this exact panel's
			-- top/bottom border, and its diagonal "START HERE" ribbon
			-- clipping the top-left corner -- both scale-positioned so
			-- they hold up at this card's real (much narrower) width.
			for _, edge in { "top", "bottom" } do
				for _, x in { 0.3, 0.7 } do
					local rivet = Factory.Icon(
						card,
						"RivetStud",
						UDim2.fromOffset(10, 10),
						UDim2.new(x, -5, if edge == "top" then 0 else 1, if edge == "top" then 3 else -13)
					)
					if rivet then
						rivet.ZIndex = 3
					end
				end
			end
			local ribbon = Factory.New("TextLabel", {
				Name = "StartHereRibbon",
				AnchorPoint = Vector2.new(0, 0.5),
				-- Was centred on y=6, so half of it hung above the card's
				-- own top edge and collided with whatever card sat above.
				Position = UDim2.fromOffset(2, 18),
				Size = UDim2.fromOffset(96, 20),
				Rotation = -8,
				BackgroundColor3 = Colors.Gold,
				BorderSizePixel = 0,
				Text = "START HERE",
				TextColor3 = Color3.fromRGB(58, 18, 6),
				Font = Theme.Fonts.Black,
				TextSize = 11,
				ZIndex = 4,
				Parent = card,
			})
			Factory.Corner(ribbon, 4)
		end
		-- The START HERE ribbon above claims the top-left corner (out to
		-- roughly x=92 once its rotation is accounted for) on this one
		-- card -- shift the kicker pill clear of it there instead of
		-- overlapping.
		local kickerX = if method.id == "TEXT_TO_3D" and not showAllMethods then 100 else 16
		Factory.ImagePill(card, method.kicker, method.color, 104).Position = UDim2.fromOffset(kickerX, 14)
		-- The Direct Forge card gives its right side over to the crystal
		-- and the price cartouche (see below): the copy stops short of
		-- that band instead of running underneath the art, which is what
		-- left the crystal sitting in the middle of a sentence.
		local heroCard = method.id == "TEXT_TO_3D" and not showAllMethods
		local copyInset = if heroCard then -176 else -32
		Factory.Label(card, method.title, UDim2.new(1, if heroCard then copyInset else -150, 0, 31), {
			Position = UDim2.fromOffset(16, 46),
			Font = Theme.Fonts.Black,
			TextSize = if self.compact then 20 else 18,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		Factory.Label(card, method.body, UDim2.new(1, copyInset, 0, 52), {
			Position = UDim2.fromOffset(16, 80),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		})
		local priceText = method.priceText or string.format("R$ %d", method.price)
		-- The concept art's price cartouche frame, behind the price text
		-- only on this one card (the single full-width Direct Forge panel
		-- a first-timer sees) -- everywhere else keeps the plain price
		-- label as-is.
		local cartouche = if heroCard
			then Factory.Icon(card, "PriceCartouche", UDim2.fromOffset(124, 58), UDim2.new(1, -24, 1, -18))
			else nil
		if cartouche then
			cartouche.ZIndex = 1
			-- Sits in the card's bottom-right corner, leaving the space
			-- above it for the crystal to stack on.
			cartouche.AnchorPoint = Vector2.new(1, 1)
		end
		-- Parented to the cartouche and centred when there is one, rather
		-- than positioned against the card's edge and hoping the two line
		-- up: Icon draws with ScaleType.Fit, which letterboxes the art
		-- inside its box, so a card-relative offset drifted off the shape
		-- as the card's width changed. Centring inside the same box tracks
		-- the art exactly, since Fit centres it there too.
		Factory.Label(
			cartouche or card,
			priceText,
			if cartouche then UDim2.fromScale(1, 1) else UDim2.fromOffset(106, 35),
			{
				AnchorPoint = if cartouche then Vector2.new(0, 0) else Vector2.new(1, 0),
				Position = if cartouche then UDim2.fromScale(0, 0) else UDim2.new(1, -15, 0, 48),
				AlignX = if cartouche then Enum.TextXAlignment.Center else Enum.TextXAlignment.Right,
				AlignY = if cartouche then Enum.TextYAlignment.Center else Enum.TextYAlignment.Top,
				Font = Theme.Fonts.Black,
				TextSize = 18,
				Color = method.color,
				ZIndex = 2,
			}
		)
		if heroCard then
			-- Stacked directly above the price cartouche and centred on it:
			-- the cartouche is 124 wide ending 24 from the card's right
			-- edge, so its centre is at -86, and its top edge is 76 above
			-- the card's bottom. Both come off the same corner, so the two
			-- stay stacked whatever the card's width.
			local crystal = Factory.Icon(card, "CrystalHero", UDim2.fromOffset(46, 52), UDim2.new(1, -86, 1, -80))
			if crystal then
				crystal.ZIndex = 2
				crystal.AnchorPoint = Vector2.new(0.5, 1)
			end
		end
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
	if showAllMethods then
		local collapse = Factory.ImageButton(
			methodRow,
			"← Switch to Simple Mode",
			UDim2.new(1, 0, 0, 34),
			UDim2.fromOffset(0, if self.compact then 612 else 320)
		)
		self:_BindButton(collapse)
		collapse.Activated:Connect(function()
			-- Its own toggle button is about to disappear -- if it was left
			-- on, Simple Mode's next generation would otherwise silently
			-- spend a Priority Pass the player has no visible way left to
			-- turn back off.
			self.usePriority = false
			self:_UpdateSetting("simpleMode", true)
		end)
	else
		local expand = Factory.ImageButton(
			methodRow,
			"Switch to Advanced Mode →",
			UDim2.new(1, 0, 0, 34),
			UDim2.fromOffset(0, 168)
		)
		self:_BindButton(expand)
		expand.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
		-- The concept art flanks this exact link with a small flourish on
		-- each side.
		Factory.FlourishFlank(methodRow, 182, 108)
	end

	local isUpload = self.selectedMethod == "IMAGE_UPLOAD"
	local isAvatar = self.selectedMethod == "AVATAR_TO_3D"
	if isUpload and not customUploadOwned then
		local unlock =
			Factory.ImageCard(stack, UDim2.new(1, 0, 0, if self.compact then 246 else 196), nil, "UploadUnlock")
		unlock.LayoutOrder = 2
		Factory.ImagePill(unlock, "PERMANENT CREATOR TOOL", Colors.Gold, 164).Position = UDim2.fromOffset(16, 15)
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
		local unlockButton = Factory.ImageButton(
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
		local promptCard = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 560), nil, "PromptCard")
		promptCard.LayoutOrder = if simpleMode then -20 else 2
		Factory.Label(
			promptCard,
			if isAvatar
				then "1  STYLING NOTES (OPTIONAL)"
				elseif simpleMode then "1  TYPE YOUR IDEA"
				else "1  DESCRIBE YOUR ACCESSORY",
			UDim2.new(1, -32, 0, 24),
			{
				Position = UDim2.fromOffset(16, cursorY),
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				Color = Colors.Cyan,
			}
		)
		cursorY += 32
		local prompt = self:_TextBox(
			promptCard,
			if isAvatar
				then 'Optional -- e.g. "Make it glossy with a violet crystal accent." Leave blank to match your avatar as-is.'
				else if simpleMode
					then "Try: Glowing dragon wings, a crystal crown, or a neon sword…"
					else "Example: A glossy crescent-moon crown made of translucent violet crystal, chunky silhouette, no floating pieces",
			UDim2.new(1, -32, 0, 80),
			UDim2.fromOffset(16, cursorY),
			true
		)
		prompt.Text = self.draftPrompt
		self:_GlowField(prompt, true)
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

		-- One-tap example prompts for anyone staring at a blank box with no
		-- idea what to type -- shown throughout Simple Mode, not just a
		-- first-timer's first visit (isAvatar's "styling notes" field is a
		-- different kind of prompt, so it's excluded here regardless).
		if not isAvatar and not showAllMethods then
			Factory.Label(promptCard, "NEED AN IDEA? TRY ONE:", UDim2.fromOffset(158, 16), {
				Position = UDim2.fromOffset(16, cursorY),
				Font = Theme.Fonts.Bold,
				TextSize = 10,
				Color = Colors.TextMuted,
			})
			-- The concept art trails this label with a thin divider line
			-- out to the panel's edge.
			Factory.New("Frame", {
				Position = UDim2.new(0, 182, 0, cursorY + 8),
				Size = UDim2.new(1, -198, 0, 1),
				BackgroundColor3 = Colors.Gold,
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
				Parent = promptCard,
			})
			cursorY += 20
			local sparkRow = Factory.New("ScrollingFrame", {
				Position = UDim2.fromOffset(16, cursorY),
				Size = UDim2.new(1, -32, 0, 34),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 0,
				AutomaticCanvasSize = Enum.AutomaticSize.X,
				CanvasSize = UDim2.new(),
				ScrollingDirection = Enum.ScrollingDirection.X,
				Parent = promptCard,
			})
			Factory.List(sparkRow, Enum.FillDirection.Horizontal, 8)
			for _, spark in
				{
					{
						label = "🐉 Dragon Wings",
						text = "A pair of large translucent dragon wings backpack, glowing red veins, leathery texture, folded slightly for a battle-ready silhouette",
						accessoryType = "BackAccessory",
						icon = "ItemWings",
					},
					{
						label = "👑 Crystal Crown",
						text = "A glossy crescent-moon crown made of translucent violet crystal, chunky silhouette, no floating pieces",
						accessoryType = "Hat",
						icon = "ItemCrown",
					},
					{
						label = "⚔️ Neon Katana",
						text = "A neon-edged katana strapped to the back, glowing cyan blade, sleek black hilt, faint energy trail",
						accessoryType = "BackAccessory",
						icon = "ItemKatana",
					},
					{
						label = "🎩 Steampunk Hat",
						text = "A steampunk top hat with brass gears, a small ticking clock face on the brim, weathered leather band",
						accessoryType = "Hat",
						icon = "ItemHat",
					},
					{
						label = "🦋 Fairy Wings",
						text = "A pair of iridescent fairy wings, delicate vein patterns, glowing softly at the edges, lightweight and symmetrical",
						accessoryType = "BackAccessory",
						icon = "ItemButterfly",
					},
				}
			do
				local chip = Factory.ImageButton(sparkRow, spark.label, UDim2.fromOffset(140, 34))
				self:_BindButton(chip)
				-- These 5 idea chips are the one place a fixed, non-user-generated
				-- item icon is honest: every other item image in the app is a real
				-- render of generated content, but these example prompts always
				-- describe the same 5 things. Factory.Icon returns nil (still 0 in
				-- UIAssets) until an upload happens, so the emoji-prefixed label
				-- stays exactly as it always has until then.
				local chipIcon = Factory.Icon(chip, spark.icon, UDim2.fromOffset(20, 20), UDim2.fromOffset(8, 7))
				if chipIcon then
					chipIcon.ZIndex = 2
					chip.Text = "   " .. spark.label:gsub("^%S+%s*", "")
				end
				chip.Activated:Connect(function()
					prompt.Text = spark.text
					prompt.CursorPosition = #spark.text + 1
					prompt:CaptureFocus()
					-- Advanced options (including fit region) are collapsed
					-- for a first-timer -- without this, every example would
					-- still submit against the "Hat" default regardless of
					-- what it actually depicts.
					self.selectedAccessoryType = spark.accessoryType
				end)
			end
			cursorY += 42

			-- The concept art's ember-mascot writing tip -- net-new content,
			-- not a restyle of anything that existed here before. Guides a
			-- first-timer staring at a blank prompt box on how to phrase a
			-- good one, right where the idea chips leave off.
			local tipRow = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, cursorY),
				Size = UDim2.new(1, -32, 0, 44),
				BackgroundColor3 = Color3.fromRGB(36, 22, 69),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Parent = promptCard,
			})
			Factory.Corner(tipRow, 14)
			Factory.Stroke(tipRow, Colors.Gold, 0.5)
			local ember = Factory.Icon(tipRow, "EmberMascot", UDim2.fromOffset(30, 30), UDim2.fromOffset(8, 7))
			Factory.Label(
				tipRow,
				`A colour + a material + a shape works best — "gold crown made of lava".`,
				UDim2.new(1, if ember then -56 else -24, 0, 44),
				{
					Position = UDim2.fromOffset(if ember then 46 else 12, 0),
					Color = Colors.TextMuted,
					TextSize = 12,
					Wrapped = true,
					AlignY = Enum.TextYAlignment.Center,
				}
			)
			cursorY += 52
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
				local chip = Factory.ImageButton(
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
		elseif isAvatar then
			Factory.Label(promptCard, "2  CHOOSE YOUR AVATAR VIEW", UDim2.new(1, -32, 0, 22), {
				Position = UDim2.fromOffset(16, cursorY),
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				Color = Colors.Mint,
			})
			cursorY += 27
			choiceRow(Config.Generation.AvatarViews, self.selectedAvatarView, cursorY, Colors.Mint, function(value)
				self.selectedAvatarView = value
				self:_RenderActivePage()
			end)
			cursorY += 46
			local previewThumbType = "AvatarHeadShot"
			for _, view in Config.Generation.AvatarViews do
				if view.Id == self.selectedAvatarView then
					previewThumbType = view.ThumbType
					break
				end
			end
			local avatarPreview = Factory.New("ImageLabel", {
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.fromOffset(16, cursorY),
				BackgroundColor3 = Colors.Ink,
				BorderSizePixel = 0,
				Image = avatarThumbnail(player.UserId, previewThumbType, 150),
				ScaleType = Enum.ScaleType.Crop,
				Parent = promptCard,
			})
			Factory.Corner(avatarPreview, 12)
			Factory.Label(
				promptCard,
				"Fetched automatically from your current Roblox avatar -- nothing to upload",
				UDim2.new(1, -32 - 76, 0, 64),
				{
					Position = UDim2.fromOffset(16 + 64 + 12, cursorY),
					Color = Colors.TextMuted,
					TextSize = 11,
					Wrapped = true,
					AlignY = Enum.TextYAlignment.Center,
				}
			)
			cursorY += 74
			step = 3
		end

		-- Style and fit region default to something sensible (AUTO /
		-- whichever example chip was tapped, or "Hat") and stay hidden in
		-- Simple Mode, same as the other three methods -- switching to
		-- Advanced Mode above reveals both together, so Simple Mode ends
		-- at the prompt box + Generate. Detail density isn't a choice at
		-- all any more, in either mode -- selectedDetailLevel is
		-- permanently "BALANCED" (see App.new), there's no UI left that
		-- ever changes it.
		if showAllMethods then
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

			if self.selectedMethod == "IMAGE_PREVIEW" then
				Factory.Label(
					promptCard,
					string.format("%d  CHOOSE REFERENCE QUALITY", step),
					UDim2.new(1, -32, 0, 22),
					{
						Position = UDim2.fromOffset(16, cursorY),
						Font = Theme.Fonts.Bold,
						TextSize = 12,
						Color = Colors.Gold,
					}
				)
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
					local chip = Factory.ImageButton(
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
				local chip = Factory.ImageButton(
					chipRow,
					label,
					UDim2.fromOffset(88, 34),
					nil,
					if selected then "primary" else nil
				)
				self:_BindButton(chip)
				chip.Activated:Connect(function()
					self.selectedAccessoryType = typeName
					self:_RenderActivePage()
				end)
			end
			cursorY += 50
		else
			Factory.Label(
				promptCard,
				"We'll choose the best style and fit. Advanced Mode lets you change them.",
				UDim2.new(1, -32, 0, 18),
				{ Position = UDim2.fromOffset(16, cursorY), Color = Colors.TextMuted, TextSize = 10, Wrapped = true }
			)
			cursorY += 26
		end

		local safetyY = cursorY
		-- This note used to sit *beside* the action buttons in Advanced
		-- Mode, on the assumption the card ran nearly the page's width.
		-- In the left column it doesn't: the note got a ~228px ribbon to
		-- wrap into and ran straight through the buttons. It always sits
		-- full width above them now, like every other layout here.
		local buttonY = safetyY + 39
		local simpleRetryAvailable = (self.state.profile.retryCredits.DirectGeneration or 0) > 0
		promptCard.Size = UDim2.new(1, 0, 0, buttonY + 58)
		Factory.Label(
			promptCard,
			if simpleMode
				then if simpleRetryAvailable
					then "Your retry credit will be used · No Robux charge"
					elseif
						self.state.policy.commerceAllowed ~= true
					then "Roblox has disabled purchases for this account · Try a free look instead"
					elseif self.paymentMethod == "TOKENS" then string.format(
						"One custom 3D accessory · %d ad tokens · Free reward tokens cannot pay for AI",
						tokenPrice(self.state.prices.DirectGeneration, "DirectGeneration")
					)
					else string.format(
						"One custom 3D accessory · Roblox asks before charging R$ %d · Nothing starts until you confirm",
						self.state.prices.DirectGeneration
					)
				elseif
					isUpload
				then "Roblox asset moderation + ownership verification · no duplicate OpenAI image check"
				elseif isAvatar then "Your avatar is fetched automatically · Roblox TextService + provider moderation"
				else "Roblox TextService + provider moderation · 3,600 triangle target · 2K texture",
			UDim2.new(1, -32, 0, 34),
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
			elseif self.selectedMethod == "AVATAR_TO_3D" then "AvatarConversion"
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
		local hasRetryCredit = (self.state.profile.retryCredits[generationProductKey] or 0) > 0
		-- Do not count an offer rendered behind the first-session tutorial as
		-- seen. It becomes a real impression only after the player exits that
		-- overlay and Create is visible again.
		if
			self.shell.Visible
			and not isUpload
			and not hasRetryCredit
			and self.state.policy.commerceAllowed == true
			and (tonumber(self.state.profile.tutorialVersion) or 0) >= Config.Tutorial.Version
		then
			local offerKey = string.format("%s:%s:%s", generationProductKey, self.paymentMethod, tostring(simpleMode))
			if not self.generationOfferEvents[offerKey] then
				self.generationOfferEvents[offerKey] = true
				self:_Track({
					event = "GenerationOfferShown",
					fields = {
						productKey = generationProductKey,
						paymentMethod = self.paymentMethod,
						price = price,
						simpleMode = simpleMode,
					},
				})
			end
		end
		-- Simple Mode's button says what it does in plain words instead of
		-- brand terms ("Forge 3D") a first-time young creator hasn't been
		-- taught yet -- always the TEXT_TO_3D case, since that's the only
		-- method Simple Mode ever leaves selected.
		local actionText = if hasRetryCredit
			then if not showAllMethods then "Retry My Accessory · FREE CREDIT" else "Use retry credit · FREE"
			elseif
				self.state.policy.commerceAllowed ~= true and not isUpload
			then "Purchases unavailable on this account"
			elseif not showAllMethods then string.format("Make My Accessory · %s", priceText)
			elseif self.selectedMethod == "TEXT_TO_3D" then string.format("Forge 3D · %s", priceText)
			elseif self.selectedMethod == "IMAGE_PREVIEW" then string.format("Create reference · %s", priceText)
			elseif self.selectedMethod == "AVATAR_TO_3D" then string.format(
				"Forge from my avatar · %s",
				priceText
			)
			else "Moderate my reference · Included"
		local generate = Factory.ImageButton(
			promptCard,
			actionText,
			if not showAllMethods
				then UDim2.new(1, -32, 0, 42)
				elseif self.compact then UDim2.new(0.5, -20, 0, 42)
				else UDim2.new(0, 250, 0, 42),
			if not showAllMethods
				then UDim2.fromOffset(16, buttonY)
				elseif self.compact then UDim2.new(0.5, 5, 0, buttonY)
				else UDim2.new(1, -266, 0, buttonY),
			"primary"
		)
		generate.Active = isUpload or hasRetryCredit or self.state.policy.commerceAllowed == true
		self:_BindButton(generate)
		-- The concept art's molten CTA has a small gold rivet stud near each
		-- end -- a light corner accent that scales with the button's own
		-- width via scale-based offsets, so it holds up across Simple Mode's
		-- full-width layout and Advanced Mode's fixed-width one alike.
		for _, edge in { "left", "right" } do
			local rivet = Factory.Icon(
				generate,
				"RivetStud",
				UDim2.fromOffset(13, 13),
				if edge == "left" then UDim2.fromOffset(9, 15) else UDim2.new(1, -22, 0, 15)
			)
			if rivet then
				rivet.ZIndex = 6
			end
		end
		-- The Priority Pass upsell -- a second button competing for
		-- attention right beside the one action Simple Mode actually needs
		-- -- only shows in Advanced Mode. Both places that switch into
		-- Simple Mode (below, and the Settings toggle) reset
		-- self.usePriority to false first, so a generation made here never
		-- silently spends a pass through a toggle the player can no longer
		-- see or reach.
		local availablePasses = self.state.profile.retryCredits.PriorityPass or 0
		if showAllMethods then
			local priority = Factory.ImageButton(
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
			self:_BindButton(priority)
			priority.Activated:Connect(function()
				if availablePasses > 0 then
					self.usePriority = not self.usePriority
					self:_RenderActivePage()
				else
					self:_BuyPriorityPass()
				end
			end)
		end
		generate.Activated:Connect(function()
			self.draftPrompt = prompt.Text
			generate.Active = false
			generate.Text = if isUpload
				then "Moderating image…"
				elseif isAvatar then "Fetching your avatar…"
				else "Checking prompt…"
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
				if isAvatar then
					request.avatarView = self.selectedAvatarView
				end
				-- Keep the action separate from the multi-return call: wrapping
				-- `_Invoke` in an if-expression would discard its second return.
				local creationAction = Network.Actions.CreateGeneration
				if isUpload then
					creationAction = Network.Actions.CreateUploadedImage
				elseif isAvatar then
					creationAction = Network.Actions.CreateFromAvatar
				end
				local success, result = self:_Invoke(creationAction, request)
				generate.Active = true
				generate.Text = actionText
				if success then
					result = self:_GenerationResult(creationAction, result)
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
			Factory.ImageCard(stack, UDim2.new(1, 0, 0, if self.compact then 382 else 234), nil, "ReferenceReview")
		reference.LayoutOrder = 3
		local image = Factory.New("ImageLabel", {
			Size = if self.compact then UDim2.fromOffset(132, 132) else UDim2.fromOffset(172, 172),
			Position = if self.compact then UDim2.new(0.5, -66, 0, 16) else UDim2.fromOffset(18, 19),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			Image = directImage(readyImage.previewAssetId),
			ScaleType = Enum.ScaleType.Crop,
			Parent = reference,
		})
		Factory.Corner(image, 13)
		local imageLoadHint = Factory.Label(
			image,
			"Preparing image — likely still awaiting Roblox moderation.",
			UDim2.new(1, -8, 0, 44),
			{
				Name = "LoadHint",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Color = Colors.Text,
				TextSize = 10,
				Wrapped = true,
				AlignX = Enum.TextXAlignment.Center,
				ZIndex = image.ZIndex + 1,
			}
		)
		Factory.New("UIStroke", { Color = Colors.Ink, Thickness = 1.5, Transparency = 0.2, Parent = imageLoadHint })
		self:_WatchImageLoad(image, imageLoadHint)
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
				-- 21 ran past this card's right edge once the left column
				-- narrowed -- the trailing "?" was the first thing lost.
				TextSize = if self.compact then 21 else 18,
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
			-- Was 54 -- sized for a near-full-page card; the left column
			-- is always narrower now (see `stack`/`columns` above), so
			-- this same copy wraps to more lines and needs more room.
			if self.compact then UDim2.new(1, -36, 0, 66) else UDim2.new(1, -232, 0, 78),
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
		local approve = Factory.ImageButton(
			reference,
			if self.compact
				then string.format("Build · %s", conversionPriceText)
				else string.format("Approve & build · %s", conversionPriceText),
			-- Sized off the card rather than a flat 210px so it always
			-- stops short of the reroll button pinned to the right edge.
			if self.compact then UDim2.new(0.5, -22, 0, 42) else UDim2.new(0.72, -226, 0, 42),
			if self.compact then UDim2.new(0, 14, 1, -58) else UDim2.fromOffset(210, 174),
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
					result = self:_GenerationResult(Network.Actions.ConvertImage, result)
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
		local reroll = Factory.ImageButton(
			reference,
			if readyImage.method == "IMAGE_UPLOAD"
				then (if self.compact then "Replace" else "Use another image")
				else (if self.compact then "Reroll" else "Reroll · new reference"),
			if self.compact then UDim2.new(0.5, -22, 0, 42) else UDim2.new(0.26, 0, 0, 42),
			-- Was a flat x=430 offset, from when this card ran near the
			-- page's full width -- in the left column that put the button
			-- past the card's own right edge, over the next column. It is
			-- pinned to the card's right edge now, so it stays inside at
			-- any width, and shares the approve button's row (that moved
			-- to y=174 when the description above it grew; this did not).
			if self.compact then UDim2.new(0.5, 8, 1, -58) else UDim2.new(1, -16, 0, 174),
			nil
		)
		if not self.compact then
			reroll.AnchorPoint = Vector2.new(1, 0)
		end
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
	local activityHeight = (if rowCount == 0 then 144 else 49 + rowCount * 50 + 14) + (if showUpsell then 46 else 0)
	local activity = Factory.ImageCard(rightStack, UDim2.new(1, 0, 0, activityHeight), nil, "Activity")
	activity.LayoutOrder = 2
	-- Concept art labels this panel "IN THE FORGE" and shows a global feed
	-- of OTHER creators' in-progress items -- an aspirational social feed
	-- with no server support (no broadcast of anonymized generation events
	-- exists). This keeps the real, honest data (the player's own queue)
	-- under the concept art's label, rather than fabricating other players'
	-- activity.
	Factory.SectionBanner(activity, "In the Forge")
	local y = 49
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

			local isModel = generation.method == "TEXT_TO_3D"
				or generation.method == "IMAGE_TO_3D"
				or generation.method == "AVATAR_TO_3D"
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

	-- Concept art's queue-slots footer. self.state.benefits.queueSlots is
	-- the same total already shown as the topbar's "N SLOTS" pill; this
	-- pairs it with how many of those slots are free right now, counted
	-- from the player's own active (non-terminal) generations -- the same
	-- terminal-stage set GenerationService uses server-side
	-- (SUCCEEDED/FAILED/IMAGE_READY), so this can't drift out of sync with
	-- what actually blocks a new submission.
	local activeGenerations = 0
	for _, generationId in self.state.profile.generationOrder do
		local generation = self.state.profile.generations[generationId]
		if generation then
			local stage = generation.stage
			if stage ~= "SUCCEEDED" and stage ~= "FAILED" and stage ~= "IMAGE_READY" then
				activeGenerations += 1
			end
		end
	end
	local totalQueueSlots = self.state.benefits.queueSlots or 1
	local openQueueSlots = math.max(0, totalQueueSlots - activeGenerations)
	local queueCard = Factory.New("Frame", {
		Name = "QueueSlots",
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Parent = rightStack,
	})
	Factory.Corner(queueCard, 20)
	Factory.Stroke(queueCard, Colors.Cyan, 0.6, 1.4)
	local queueBadge = Factory.New("Frame", {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(15, 15),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		Parent = queueCard,
	})
	Factory.Corner(queueBadge, 20)
	Factory.Stroke(queueBadge, Colors.Cyan, 0.3, 1.6)
	Factory.Label(queueBadge, "⚡", UDim2.fromScale(1, 1), {
		TextSize = 16,
		AlignX = Enum.TextXAlignment.Center,
		AlignY = Enum.TextYAlignment.Center,
	})
	Factory.Label(
		queueCard,
		string.format("%d queue slot%s open", openQueueSlots, if openQueueSlots == 1 then "" else "s"),
		UDim2.new(1, -72, 0, 20),
		{
			Position = UDim2.fromOffset(66, 13),
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			Color = Colors.Cyan,
		}
	)
	Factory.Label(
		queueCard,
		string.format(
			"Up to %d generation%s running at once",
			totalQueueSlots,
			if totalQueueSlots == 1 then "" else "s"
		),
		UDim2.new(1, -82, 0, 32),
		{
			Position = UDim2.fromOffset(66, 34),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)

	local brief = self.state.dailyBrief
	if brief then
		local hasMilestoneBanner = brief.milestoneReward ~= nil
		-- 222 before the two tail lines below started wrapping to two
		-- lines each at this card's real width in the right rail.
		local cardHeight = 250 + (if hasMilestoneBanner then 36 else 0)
		local daily = Factory.ImageCard(rightStack, UDim2.new(1, 0, 0, cardHeight), nil, "DailyBrief")
		-- Extra content beyond the concept art (which has no streak-calendar
		-- panel) -- kept, but after every panel the mockup does show.
		daily.LayoutOrder = 4

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
				if (milestone.tokens or 0) > 0
					then string.format(
						"🏆 %d-day milestone! +%d Forge Tokens · +%d Priority Pass%s",
						milestone.day,
						milestone.tokens,
						milestone.priorityPasses,
						if milestone.priorityPasses == 1 then "" else "es"
					)
					else string.format(
						"🏆 %d-day milestone! +%d Priority Pass%s",
						milestone.day,
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

		local calendar = Factory.New("Frame", {
			Name = "LoginCalendar",
			Position = UDim2.fromOffset(15, briefY),
			Size = UDim2.new(1, -30, 0, 54),
			BackgroundTransparency = 1,
			Parent = daily,
		})
		Factory.New("UIGridLayout", {
			CellSize = UDim2.new(1 / 7, -6, 1, 0),
			CellPadding = UDim2.fromOffset(7, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = calendar,
		})
		for dayNumber, reward in Config.Retention.DailyStreakTokens do
			local current = dayNumber == (brief.rewardDay or 1)
			local dayCard = Factory.New("Frame", {
				Name = string.format("Day%d", dayNumber),
				LayoutOrder = dayNumber,
				BackgroundColor3 = if current then Colors.Gold else Colors.Ink,
				BackgroundTransparency = if current then 0.08 else 0.28,
				BorderSizePixel = 0,
				Parent = calendar,
			})
			Factory.Corner(dayCard, 9)
			Factory.Stroke(dayCard, if current then Colors.Gold else Colors.Line, if current then 0.2 else 0.7, 1)
			Factory.Label(dayCard, string.format("D%d", dayNumber), UDim2.new(1, 0, 0, 19), {
				Position = UDim2.fromOffset(0, 4),
				Font = Theme.Fonts.Bold,
				TextSize = 9,
				Color = if current then Colors.Ink else Colors.TextMuted,
				AlignX = Enum.TextXAlignment.Center,
			})
			Factory.Label(dayCard, string.format("+%d", reward), UDim2.new(1, 0, 0, 22), {
				Position = UDim2.fromOffset(0, 24),
				Font = Theme.Fonts.Black,
				TextSize = if reward >= 40 then 11 else 12,
				Color = if current then Colors.Ink else Colors.Mint,
				AlignX = Enum.TextXAlignment.Center,
			})
		end
		briefY += 66

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
			-- Both of these tails wrap now: in the right rail this card is
			-- far narrower than the near-full-width one they were written
			-- against, so on one line they ran off the card's edge.
			UDim2.new(1, -30, 0, 32),
			{
				Position = UDim2.fromOffset(15, briefY),
				Color = Colors.TextMuted,
				TextSize = 11,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
		briefY += 36

		Factory.Label(
			daily,
			"Use the theme as inspiration—or forge anything you can imagine.",
			UDim2.new(1, -30, 0, 34),
			{
				Position = UDim2.fromOffset(15, briefY),
				Color = Colors.TextMuted,
				TextSize = 12,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
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
		local cardHeight = #quests * 46 + (if allDone then 126 else 50)
		local questCard = Factory.ImageCard(rightStack, UDim2.new(1, 0, 0, cardHeight), nil, "DailyQuests")
		questCard.LayoutOrder = 1
		-- Titled by the concept art's notched banner tab across the card's
		-- top edge, with the progress count folded into the caption the same
		-- way the art's own "COLLECTION * 6" tab does -- there is no room
		-- beside a centred tab for the separate right-aligned counter this
		-- used to carry.
		Factory.SectionBanner(questCard, string.format("Daily Quests · %d/%d", doneCount, #quests))

		local qy = 44
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
			-- 50 tall used to give the label and the invite pill below it only
			-- ~2px of daylight between them (and ~4px above the card's own
			-- bottom edge); grown to 68 with the label/pill/bottom-edge gaps
			-- each opened to a real ~10px.
			local banner = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, qy),
				Size = UDim2.new(1, -32, 0, 68),
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
					Position = UDim2.fromOffset(10, 8),
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
				Size = UDim2.fromOffset(150, 24),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 34),
				BackgroundColor3 = Colors.Gold,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "👥 Invite a friend",
				TextColor3 = Colors.Ink,
				Font = Theme.Fonts.Bold,
				TextSize = 11,
				Parent = banner,
			})
			Factory.Corner(inviteRow, 12)
			self:_BindButton(inviteRow)
			inviteRow.Activated:Connect(function()
				self:_PromptFriendInvite()
			end)
		end
	end
	self.questJustCompleted = nil
end

function App:_RenderStudio()
	local profile = self.state.profile
	local simpleMode = profile.settings.simpleMode ~= false
	local showAllMethods = not simpleMode
	self:_PageHeader(
		"My Studio",
		if showAllMethods
			then "Fit, equip, share, list, or publish every original and personal copy you own."
			else "Tap an item below, then equip it or publish it as a real Roblox wearable.",
		true
	)
	if #profile.itemOrder == 0 then
		local empty = Factory.ImageCard(self.content, UDim2.new(0.95, 0, 0, 260), UDim2.new(0.025, 0, 0, 112))
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
		local create = Factory.ImageButton(
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

	-- Outfits: a snapshot of every currently-equipped item, saved together
	-- under one name and re-equipped as a set later -- distinct from a fit
	-- preset below (one item's transform, reusable on a different item).
	-- The concept art runs this whole bar as ONE row -- the OUTFITS caption
	-- and its "Save your look" subtitle, the name box, the save button, then
	-- the saved-look chips -- instead of stacking caption / box+button /
	-- chips down three lines. Only in wide layouts: at compact widths four
	-- things side by side would leave the name box a few characters wide, so
	-- there it keeps the original stack.
	local outfitsHeight = if self.compact then 100 else 86
	local outfits =
		Factory.ImageCard(self.content, UDim2.new(0.95, 0, 0, outfitsHeight), UDim2.new(0.025, 0, 0, 100), "Outfits")
	Factory.Label(outfits, "OUTFITS", UDim2.new(0.4, 0, 0, 24), {
		Position = UDim2.fromOffset(if self.compact then 14 else 16, if self.compact then 10 else 20),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.Mint,
	})
	if not self.compact then
		Factory.Label(outfits, "Save your look", UDim2.fromOffset(124, 18), {
			Position = UDim2.fromOffset(16, 42),
			Color = Colors.TextMuted,
			TextSize = 11,
		})
	end
	-- Wide: caption block (16..146), name box, save button, chips -- each
	-- start derived from the one before it so the row can't overlap itself
	-- at any width. Compact: the original two stacked rows.
	local outfitNameBox = self:_TextBox(
		outfits,
		"Name this look…",
		if self.compact then UDim2.new(1, -208, 0, 30) else UDim2.new(0.3, 0, 0, 36),
		if self.compact then UDim2.fromOffset(14, 36) else UDim2.fromOffset(146, 25),
		false
	)
	local saveOutfitButton =
		-- 110px used to leave almost no room around "Save current look" at
		-- Bold 14px -- the label nearly touched the pill's own edges. Widened
		-- to fit the text with real breathing room and a clean 10px gap from
		-- the name box.
		Factory.ImageButton(
			outfits,
			if self.compact then "Save current look" else "Save look",
			if self.compact then UDim2.fromOffset(170, 30) else UDim2.fromOffset(140, 36),
			if self.compact then UDim2.new(1, -184, 0, 36) else UDim2.new(0.3, 156, 0, 25),
			"mint"
		)
	self:_BindButton(saveOutfitButton)
	saveOutfitButton.Activated:Connect(function()
		saveOutfitButton.Active = false
		task.spawn(function()
			local success, data = self:_Invoke(Network.Actions.SaveOutfit, { name = outfitNameBox.Text })
			if success then
				self.state.profile.outfits[data.outfit.id] = data.outfit
				table.insert(self.state.profile.outfitOrder, 1, data.outfit.id)
				self.sounds:Play("Success")
				self:_Toast("success", "Outfit saved.")
				self:_RenderActivePage()
				return
			end
			if saveOutfitButton.Parent then
				saveOutfitButton.Active = true
			end
		end)
	end)
	local outfitList = Factory.New("ScrollingFrame", {
		Position = if self.compact then UDim2.fromOffset(14, 70) else UDim2.new(0.3, 306, 0, 25),
		Size = if self.compact then UDim2.new(1, -28, 0, 24) else UDim2.new(0.7, -322, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Mint,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		Parent = outfits,
	})
	Factory.List(outfitList, Enum.FillDirection.Horizontal, 8)
	local outfitOrder = profile.outfitOrder or {}
	local chipHeight = if self.compact then 24 else 36
	if #outfitOrder == 0 then
		Factory.Label(
			outfitList,
			"No saved outfits yet -- equip a look, then save it above.",
			UDim2.fromOffset(340, chipHeight),
			{
				AlignY = Enum.TextYAlignment.Center,
				Color = Colors.TextMuted,
				TextSize = 11,
			}
		)
	else
		for index, outfitId in outfitOrder do
			local record = profile.outfits[outfitId]
			if record then
				local nameWidth = math.clamp(#record.name * 7 + 40, 90, 150)
				local chip = Factory.New("Frame", {
					Size = UDim2.fromOffset(nameWidth + 34, chipHeight),
					BackgroundTransparency = 1,
					Parent = outfitList,
				})
				local apply = Factory.ImageButton(
					chip,
					record.name,
					UDim2.fromOffset(nameWidth, chipHeight),
					UDim2.fromOffset(0, 0),
					nil
				)
				apply.TextTruncate = Enum.TextTruncate.AtEnd
				-- Every saved-look chip in the concept art carries a small
				-- gem stud, cycling through the palette down the row. Same
				-- pattern as Create's idea chips: the stud only appears once
				-- its asset id is real, and the label steps aside for it
				-- rather than being drawn over.
				local studGem = CHIP_GEMS[(index - 1) % #CHIP_GEMS + 1]
				local stud =
					Factory.Icon(apply, studGem, UDim2.fromOffset(14, 14), UDim2.fromOffset(9, (chipHeight - 14) // 2))
				if stud then
					stud.ZIndex = 2
					apply.Text = "  " .. record.name
				end
				self:_BindButton(apply)
				apply.Activated:Connect(function()
					apply.Active = false
					task.spawn(function()
						local success = self:_Invoke(Network.Actions.EquipOutfit, { outfitId = outfitId })
						if success then
							self.sounds:Play("Success")
							self:_Toast("success", string.format('Wearing "%s".', record.name))
							self:_RefreshBootstrap()
							return
						end
						if apply.Parent then
							apply.Active = true
						end
					end)
				end)
				local remove = Factory.ImageButton(
					chip,
					"×",
					UDim2.fromOffset(26, chipHeight),
					UDim2.fromOffset(nameWidth + 8, 0),
					"danger"
				)
				self:_BindButton(remove)
				remove.Activated:Connect(function()
					task.spawn(function()
						local success = self:_Invoke(Network.Actions.DeleteOutfit, { outfitId = outfitId })
						if success then
							self.state.profile.outfits[outfitId] = nil
							local index = table.find(self.state.profile.outfitOrder, outfitId)
							if index then
								table.remove(self.state.profile.outfitOrder, index)
							end
							self:_RenderActivePage()
						end
					end)
				end)
			end
		end
	end

	local topOffset = 100 + outfitsHeight + 14
	local collection = if self.compact
		then Factory.ImageCard(
			self.content,
			UDim2.new(0.95, 0, 0, 164),
			UDim2.new(0.025, 0, 0, topOffset),
			"Collection"
		)
		else Factory.ImageCard(
			self.content,
			UDim2.new(0.39, 0, 1, -18 - topOffset),
			UDim2.new(0.02, 0, 0, topOffset),
			"Collection"
		)
	Factory.SectionBanner(collection, string.format("Collection · %d", #profile.itemOrder))
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
	self:_TrackScroll(itemScroll, "StudioCollection")
	Factory.ScalePadding(itemScroll, 0.016, 0.016)
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
			-- Gold, not violet, for the selected row: the concept art marks
			-- the open item with the same gold the panel frames use, which
			-- is what ties it to the inspector panel beside it.
			Factory.Stroke(
				row,
				if itemId == self.selectedItemId then Colors.Gold else Colors.Line,
				if itemId == self.selectedItemId then 0.15 else 0.62,
				if itemId == self.selectedItemId then 2 else 1
			)
			local image = Factory.New("ImageLabel", {
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.fromOffset(9, 9),
				BackgroundColor3 = Colors.Panel,
				BorderSizePixel = 0,
				Image = modelPreviewImage(item),
				ScaleType = Enum.ScaleType.Crop,
				Parent = row,
			})
			Factory.Corner(image, 9)
			local imageHint = Factory.Label(image, "…", UDim2.fromScale(1, 1), {
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = 18,
				Color = Colors.Cyan,
				ZIndex = 2,
			})
			self:_WatchImageLoad(image, imageHint, thumbnail(item.modelAssetId, 150))
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
		then Factory.ImageCard(
			self.content,
			UDim2.new(0.95, 0, 1, -10 - (topOffset + 164 + 10)),
			UDim2.new(0.025, 0, 0, topOffset + 164 + 10),
			"Inspector"
		)
		else Factory.ImageCard(
			self.content,
			UDim2.new(0.56, 0, 1, -18 - topOffset),
			UDim2.new(0.42, 0, 0, topOffset),
			"Inspector"
		)

	-- Name, pills, and the viewport live in a fixed header that never
	-- scrolls, separate from the controls/presets/actions below -- they used
	-- to share one scrolling body, so reaching the sliders scrolled the
	-- viewport out of view right along with them.
	-- Trimmed from an earlier 380 (with a 292-tall viewport): on a real
	-- desktop window this fixed, never-scrolling header was leaving almost
	-- nothing of the FIT CONTROLS card below visible before the player
	-- scrolled at all. A smaller viewport here buys back room for the
	-- sliders to actually show up front.
	local header = Factory.New("Frame", {
		Size = UDim2.new(1, -12, 0, 298),
		Position = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 1,
		Parent = inspector,
	})
	Factory.Label(header, selected.name, UDim2.new(1, -32, 0, 32), {
		Position = UDim2.fromOffset(16, 10),
		Font = Theme.Fonts.Black,
		TextSize = 20,
		Truncate = Enum.TextTruncate.AtEnd,
	})
	Factory.ImagePill(
		header,
		if selected.license == "PERSONAL_COPY" then "PERSONAL COPY" else "ORIGINAL",
		if selected.license == "PERSONAL_COPY" then Colors.Gold else Colors.Mint,
		106
	).Position =
		UDim2.fromOffset(16, 47)
	Factory.ImagePill(
		header,
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
		Size = UDim2.new(1, -32, 0, 210),
		BackgroundColor3 = Color3.fromRGB(62, 72, 108),
		BorderSizePixel = 0,
		Parent = header,
	})
	Factory.Corner(viewport, 14)
	Factory.Stroke(viewport, Colors.Violet, 0.45)
	local controller = ViewportController.new(viewport, selected.id)
	self.activeViewport = controller
	-- The concept art's Simple Mode viewport carries the one hint a player
	-- actually needs to discover the camera ("DRAG TO ORBIT") rather than
	-- the full mouse-button reference; Advanced Mode keeps both pills, since
	-- pan and zoom matter once there are fit sliders to line a model up
	-- against.
	local orbitHint = Factory.ImagePill(
		viewport,
		if showAllMethods then "DRAG ORBIT · RIGHT/SHIFT DRAG PAN" else "DRAG TO ORBIT",
		Colors.Cyan,
		if showAllMethods then 234 else 118
	)
	orbitHint.Position = UDim2.fromOffset(12, 12)
	orbitHint.ZIndex = 5
	if showAllMethods then
		local zoomHint = Factory.ImagePill(viewport, "WHEEL ZOOM", Colors.Violet, 92)
		zoomHint.Position = UDim2.fromOffset(12, 43)
		zoomHint.ZIndex = 5
	end
	local resetCamera = Factory.ImageButton(viewport, "↺", UDim2.fromOffset(38, 34), UDim2.new(1, -50, 0, 10), nil)
	resetCamera.Name = "ResetCamera"
	resetCamera.TextSize = 18
	resetCamera.ZIndex = 5
	self:_BindButton(resetCamera)
	resetCamera.Activated:Connect(function()
		controller:ResetCamera()
	end)
	local previewStatus = Factory.Label(viewport, "Loading model and generated texture…", UDim2.new(1, -128, 0, 38), {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Color = Colors.Text,
		TextSize = 11,
		Wrapped = true,
		AlignY = Enum.TextYAlignment.Center,
		ZIndex = 6,
	})
	previewStatus.BackgroundColor3 = Colors.Ink
	previewStatus.BackgroundTransparency = 0.08
	Factory.Corner(previewStatus, 8)
	local retryPreview =
		Factory.ImageButton(viewport, "Retry preview", UDim2.fromOffset(104, 38), UDim2.new(1, -116, 1, -50), "primary")
	retryPreview.ZIndex = 6
	retryPreview.Visible = false
	self:_BindButton(retryPreview)

	if not self.fitDrafts[selected.id] then
		self.fitDrafts[selected.id] = deepCopy(selected.fit)
	end
	local fit = self.fitDrafts[selected.id]
	local baseMeshSize = nil :: Vector3?
	local textureStatus = "CHECKING"
	local meshStats = nil :: { [string]: any }?

	local inspectScroll = Factory.New("ScrollingFrame", {
		Size = UDim2.new(1, -12, 1, -310),
		Position = UDim2.fromOffset(6, 310),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Colors.Cyan,
		Parent = inspector,
	})
	self:_TrackScroll(inspectScroll, "StudioInspect")
	Factory.ScalePadding(inspectScroll, 0.012, 0.012)
	local body = Factory.New("Frame", {
		-- +184 (168 card + 16 gap) for the Title & Description card inserted
		-- above SHARING & SALES below -- only present for an original (a
		-- personal copy has nothing to title/describe, so it keeps the base
		-- height instead of an empty 184px gap at the bottom of the panel).
		-- Simple Mode skips FIT CONTROLS/PRESETS/TITLE & DESCRIPTION/SHARING &
		-- SALES entirely (see the showAllMethods branch below) so its body is
		-- a short, fixed 278 regardless of license.
		Size = UDim2.new(
			1,
			-8,
			0,
			if not showAllMethods then 246 elseif selected.license == "PERSONAL_COPY" then 1240 else 1424
		),
		BackgroundTransparency = 1,
		Parent = inspectScroll,
	})
	-- Simple Mode gets the concept art's version of this: a status badge, a
	-- one-word verdict, and a single plain-language line -- not the stud-by-
	-- stud measurement against Roblox's publishing bounds, which is only
	-- actionable next to Advanced Mode's fit sliders. Both are driven by the
	-- exact same refreshReadiness() below; only what it puts on screen
	-- differs.
	local simpleReadiness = not showAllMethods
	local readiness = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, if simpleReadiness then 72 else 104),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = body,
	})
	Factory.Corner(readiness, 13)
	local readinessStroke = Factory.Stroke(readiness, Colors.Gold, 0.35)
	local readinessBadge = if simpleReadiness
		then Factory.New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = Colors.Gold,
			BorderSizePixel = 0,
			Parent = readiness,
		})
		else nil
	local readinessBadgeGlyph = nil :: TextLabel?
	if readinessBadge then
		Factory.Corner(readinessBadge, 15)
		readinessBadgeGlyph = Factory.Label(readinessBadge, "…", UDim2.fromScale(1, 1), {
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 15,
			Color = Colors.Ink,
		})
	end
	local textX = if simpleReadiness then 56 else 14
	local verdict = Factory.Label(
		readiness,
		if simpleReadiness then "CHECKING FIT…" else "WEARABLE READINESS · RTHRO NORMAL",
		UDim2.new(1, -(textX + 14), 0, 20),
		{
			Position = UDim2.fromOffset(textX, if simpleReadiness then 14 else 10),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = if simpleReadiness then Colors.Gold else Colors.Cyan,
		}
	)
	local sizeStatus = Factory.Label(readiness, "Measuring the model…", UDim2.new(1, -28, 0, 24), {
		Position = UDim2.fromOffset(14, 32),
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		Wrapped = true,
	})
	sizeStatus.Visible = not simpleReadiness
	local textureStatusLabel = Factory.Label(
		readiness,
		"Checking whether Roblox has released the generated texture…",
		UDim2.new(1, -(textX + 14), 0, 34),
		{
			Position = UDim2.fromOffset(textX, if simpleReadiness then 34 else 57),
			Color = Colors.Gold,
			TextSize = if simpleReadiness then 11 else 10,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)

	-- readinessStroke.Color is already the tri-state signal every branch of
	-- measureReadiness() below settles on (rose = over the bounds, mint =
	-- publishable, gold = still checking), so Simple Mode's badge and
	-- verdict read it back rather than re-deriving the same three cases.
	local function applyVerdict()
		if not simpleReadiness then
			return
		end
		local color = readinessStroke.Color
		local glyph, text = "…", "CHECKING FIT…"
		if color == Colors.Rose then
			glyph, text = "!", "TOO LARGE TO PUBLISH"
		elseif color == Colors.Mint then
			glyph, text = "✓", "READY TO WEAR"
		end
		verdict.Text = text
		verdict.TextColor3 = color
		if readinessBadge then
			readinessBadge.BackgroundColor3 = color
		end
		if readinessBadgeGlyph then
			readinessBadgeGlyph.Text = glyph
		end
	end

	local function measureReadiness()
		local maximum = AccessoryBounds.GetMaximum(fit.accessoryType)
		if not baseMeshSize or not maximum then
			sizeStatus.Text = "Measuring the model against Roblox's publishing bounds…"
			sizeStatus.TextColor3 = Colors.Gold
			readinessStroke.Color = Colors.Gold
		else
			local fittedSize = AccessoryBounds.GetFittedSize(baseMeshSize, fit)
			local exceededAxes = AccessoryBounds.ExceededAxes(fittedSize, maximum)
			sizeStatus.Text = string.format(
				"%s · X %.2f/%.2f  Y %.2f/%.2f  Z %.2f/%.2f studs",
				ACCESSORY_LABELS[fit.accessoryType] or "Accessory",
				fittedSize.X,
				maximum.X,
				fittedSize.Y,
				maximum.Y,
				fittedSize.Z,
				maximum.Z
			)
			if #exceededAxes > 0 then
				sizeStatus.TextColor3 = Colors.Rose
				readinessStroke.Color = Colors.Rose
				textureStatusLabel.Text = string.format(
					"Too large on %s. Reduce those scale axes before publishing; position can also affect Roblox's final check.",
					table.concat(exceededAxes, ", ")
				)
				textureStatusLabel.TextColor3 = Colors.Rose
				return
			end
			sizeStatus.TextColor3 = Colors.Mint
			readinessStroke.Color = if textureStatus == "READY" then Colors.Mint else Colors.Gold
		end

		if textureStatus == "READY" then
			local textureDetail = if meshStats
					and meshStats.textureWidth
					and meshStats.textureHeight
				then string.format(" · %d×%d source", meshStats.textureWidth, meshStats.textureHeight)
				else ""
			textureStatusLabel.Text = "✓ Generated texture is available on Roblox" .. textureDetail .. "."
			textureStatusLabel.TextColor3 = Colors.Mint
		elseif textureStatus == "PROCESSING" or textureStatus == "FETCH_FAILED" then
			textureStatusLabel.Text =
				"Texture is still processing/moderating on Roblox. The model is saved; use Retry preview before publishing."
			textureStatusLabel.TextColor3 = Colors.Gold
		else
			textureStatusLabel.Text = "Checking whether Roblox has released the generated texture…"
			textureStatusLabel.TextColor3 = Colors.Gold
		end
	end

	local function refreshReadiness()
		measureReadiness()
		applyVerdict()
	end
	refreshReadiness()

	local previewLoadId = 0
	local function loadPrivatePreview()
		previewLoadId += 1
		local thisLoad = previewLoadId
		previewStatus.Text = "Loading a fresh model and generated texture…"
		previewStatus.Visible = true
		retryPreview.Visible = false
		textureStatus = "CHECKING"
		refreshReadiness()
		task.spawn(function()
			local version = self.pageVersion
			local success, dataOrCode =
				self:_Invoke(Network.Actions.RequestPrivateModel, { itemId = selected.id, refresh = true })
			if thisLoad ~= previewLoadId or version ~= self.pageVersion or not viewport.Parent then
				return
			end
			if not success then
				textureStatus = if dataOrCode == "ASSET_STILL_PROCESSING" then "PROCESSING" else "FETCH_FAILED"
				previewStatus.Text = if dataOrCode == "ASSET_STILL_PROCESSING"
					then "Roblox is still processing/moderating this model. It is saved — retry shortly."
					else "Preview could not be loaded. Your model is saved — tap Retry preview."
				retryPreview.Visible = true
				refreshReadiness()
				return
			end

			local data = dataOrCode
			local diagnostics = if type(data.diagnostics) == "table" then data.diagnostics else {}
			baseMeshSize = vectorFromData(diagnostics.baseSize)
			meshStats = diagnostics
			textureStatus = tostring(diagnostics.textureStatus or "CHECKING")
			refreshReadiness()

			local cache = player.PlayerGui:WaitForChild("ForgeAssetCache", 8)
			local model = cache and cache:WaitForChild(data.cacheName, 8)
			if thisLoad ~= previewLoadId or version ~= self.pageVersion or not viewport.Parent then
				return
			end
			if not model or not model:IsA("Model") then
				textureStatus = "FETCH_FAILED"
				previewStatus.Text = "Roblox has not delivered the preview model yet. It is saved — retry shortly."
				retryPreview.Visible = true
				refreshReadiness()
				return
			end

			controller:SetAccessory(model, fit)
			local contentReady = true
			local preloadSuccess = pcall(function()
				ContentProvider:PreloadAsync({ model }, function(_, status)
					if status ~= Enum.AssetFetchStatus.Success then
						contentReady = false
					end
				end)
			end)
			if thisLoad ~= previewLoadId or version ~= self.pageVersion or not viewport.Parent then
				return
			end
			if textureStatus == "READY" and preloadSuccess and contentReady then
				previewStatus.Visible = false
				retryPreview.Visible = false
			else
				textureStatus = "PROCESSING"
				previewStatus.Text =
					"Texture is still processing/moderating on Roblox. The model is saved — retry shortly."
				previewStatus.Visible = true
				retryPreview.Visible = true
				refreshReadiness()
			end
		end)
	end
	retryPreview.Activated:Connect(loadPrivatePreview)
	loadPrivatePreview()

	if showAllMethods then
		-- Sized ~1.6x its original dials/labels/track/knob so the fit sliders are
		-- actually legible and easy to grab, not just the item name/pills above
		-- them -- everything below (presets/actions/note/social) keeps its
		-- original size and simply shifts down to sit under the taller card.
		local controls = Factory.New("Frame", {
			Position = UDim2.fromOffset(16, 128),
			Size = UDim2.new(1, -32, 0, 664),
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Parent = body,
		})
		Factory.Corner(controls, 13)
		Factory.Stroke(controls, Colors.Line, 0.5)
		Factory.Label(controls, "FIT CONTROLS", UDim2.new(0.5, -14, 0, 38), {
			Position = UDim2.fromOffset(14, 16),
			Font = Theme.Fonts.Bold,
			TextSize = 19,
			Color = Colors.Cyan,
		})
		Factory.Label(controls, "Drag a dial or tap − / +", UDim2.new(0.5, -24, 0, 38), {
			Position = UDim2.new(0.5, 8, 0, 16),
			AlignX = Enum.TextXAlignment.Right,
			Color = Colors.TextMuted,
			TextSize = 16,
		})

		local function sliderRow(field: string, axis: string, y: number, minimum: number, maximum: number, step: number)
			Factory.Label(controls, string.upper(axis), UDim2.new(0.06, 0, 0, 45), {
				Position = UDim2.new(0.015, 0, 0, y),
				AlignX = Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Bold,
				TextSize = 18,
				Color = if axis == "x" then Colors.Rose elseif axis == "y" then Colors.Mint else Colors.Cyan,
			})
			local minus =
				Factory.ImageButton(controls, "−", UDim2.new(0.075, -4, 0, 45), UDim2.new(0.08, 0, 0, y), nil)
			Factory.New("UISizeConstraint", { MinSize = Vector2.new(42, 45), Parent = minus })
			local track = Factory.New("TextButton", {
				Position = UDim2.new(0.17, 0, 0, y + 6),
				Size = UDim2.new(0.55, 0, 0, 32),
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
				Size = UDim2.fromOffset(26, 26),
				BackgroundColor3 = Color3.fromRGB(248, 250, 255),
				BorderSizePixel = 0,
				Parent = track,
			})
			Factory.Corner(knob, 99)
			Factory.Stroke(knob, Colors.Cyan, 0.15)
			local plus = Factory.ImageButton(controls, "+", UDim2.new(0.075, -4, 0, 45), UDim2.new(0.735, 0, 0, y), nil)
			Factory.New("UISizeConstraint", { MinSize = Vector2.new(42, 45), Parent = plus })
			local valueLabel = Factory.Label(controls, "", UDim2.new(0.17, -10, 0, 45), {
				Position = UDim2.new(0.82, 0, 0, y),
				AlignX = Enum.TextXAlignment.Right,
				Font = Theme.Fonts.Bold,
				TextSize = 18,
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
				refreshReadiness()
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

		local dialY = 102
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
			Factory.Label(controls, group.title, UDim2.new(1, -28, 0, 32), {
				Position = UDim2.fromOffset(14, dialY - 35),
				Font = Theme.Fonts.Bold,
				TextSize = 16,
				Color = Colors.TextMuted,
			})
			for _, axis in { "x", "y", "z" } do
				sliderRow(group.field, axis, dialY, group.minimum, group.maximum, group.step)
				dialY += 48
			end
			dialY += 37
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
			Factory.ImageButton(presets, "Save preset", UDim2.fromOffset(96, 32), UDim2.new(1, -110, 0, 52), "mint")
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
					local apply = Factory.ImageButton(
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
					local remove = Factory.ImageButton(
						chip,
						"×",
						UDim2.fromOffset(26, 30),
						UDim2.fromOffset(nameWidth + 8, 0),
						"danger"
					)
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
		local save = Factory.ImageButton(
			body,
			"Save fit",
			UDim2.new(0.25, -22, 0, 42),
			UDim2.fromOffset(16, actionsY),
			"primary"
		)
		local equip = Factory.ImageButton(
			body,
			if isEquipped then "Unequip" else "Equip in game",
			UDim2.new(0.25, -12, 0, 42),
			UDim2.new(0.25, 6, 0, actionsY),
			if isEquipped then "danger" else "mint"
		)
		local publish = Factory.ImageButton(
			body,
			if selected.publishedAssetId then "Published ✓" else "Publish wearable",
			UDim2.new(0.25, -12, 0, 42),
			UDim2.new(0.5, 6, 0, actionsY),
			nil
		)
		local resetFit = Factory.ImageButton(
			body,
			"↺ Reset fit",
			UDim2.new(0.25, -22, 0, 42),
			UDim2.new(0.75, 6, 0, actionsY),
			nil
		)
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
						self.avatarPreviewDirty = true
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
							self.avatarPreviewDirty = true
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

		-- Title/description editing only makes sense for an original -- a
		-- personal copy shows its own static license note below instead, same
		-- scope as the SHARING & SALES card just under it.
		local socialY = noteY + 26
		if selected.license ~= "PERSONAL_COPY" then
			local details = Factory.New("Frame", {
				Position = UDim2.fromOffset(16, socialY),
				Size = UDim2.new(1, -32, 0, 168),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Parent = body,
			})
			Factory.Corner(details, 12)
			Factory.Stroke(details, Colors.Line, 0.55)
			Factory.Label(details, "TITLE & DESCRIPTION", UDim2.new(1, -28, 0, 25), {
				Position = UDim2.fromOffset(14, 10),
				Font = Theme.Fonts.Bold,
				Color = Colors.Cyan,
				TextSize = 11,
			})
			local titleBox =
				self:_TextBox(details, "Untitled creation", UDim2.new(1, -28, 0, 36), UDim2.fromOffset(14, 40), false)
			titleBox.Text = selected.title or ""
			local descriptionBox = self:_TextBox(
				details,
				"Tell people about this creation…",
				UDim2.new(1, -28, 0, 62),
				UDim2.fromOffset(14, 82),
				true
			)
			descriptionBox.Text = selected.description or ""
			local saveDetails = Factory.ImageButton(
				details,
				"Save details",
				UDim2.fromOffset(120, 32),
				UDim2.new(1, -134, 0, 152),
				"primary"
			)
			self:_BindButton(saveDetails)
			saveDetails.Activated:Connect(function()
				saveDetails.Active = false
				task.spawn(function()
					local success, data = self:_Invoke(Network.Actions.SetItemDetails, {
						itemId = selected.id,
						title = titleBox.Text,
						description = descriptionBox.Text,
					})
					if success then
						self.state.profile.items[selected.id] = data.item
						self.sounds:Play("Success")
						self:_Toast("success", "Details saved.")
						self:_RenderActivePage()
					end
					if saveDetails.Parent then
						saveDetails.Active = true
					end
				end)
			end)
			socialY = socialY + 184
		end
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
			local visibility = Factory.ImageButton(
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
			local list = Factory.ImageButton(
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
	else
		-- Independent short body: no sliders, no presets, no title/pricing --
		-- just try it on or send it to Roblox. Reuses EquipItem/UnequipItem/
		-- PublishItem directly (skipping the Advanced branch's saveCurrentFit()
		-- pre-step above) since there is no fit-editing UI here for the fit
		-- draft to ever drift from what the server already has saved.
		-- Sits directly under the 72-tall Simple Mode readiness strip above
		-- (8 + 72 + a 16px gap), not the 104-tall Advanced one.
		local actionsY = 96
		local isEquipped = table.find(profile.equippedItemIds or {}, selected.id) ~= nil
		-- The concept art gives the molten treatment to Equip, not Publish:
		-- wearing the thing you just made is the moment worth reaching for,
		-- and publishing is the deliberate, less frequent second step.
		local equip = Factory.ImageButton(
			body,
			if isEquipped then "Unequip" else "Equip in game",
			UDim2.new(0.5, -22, 0, 46),
			UDim2.fromOffset(16, actionsY),
			if isEquipped then "danger" else "primary"
		)
		local publish = Factory.ImageButton(
			body,
			if selected.publishedAssetId then "Published ✓" else "Publish wearable",
			UDim2.new(0.5, -22, 0, 46),
			UDim2.new(0.5, 6, 0, actionsY),
			nil
		)
		self:_BindButton(equip)
		self:_BindButton(publish)
		publish.Active = not selected.publishedAssetId
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
						self.avatarPreviewDirty = true
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
				equip.Text = "Equipping…"
				task.spawn(function()
					local success = self:_Invoke(Network.Actions.EquipItem, { itemId = selected.id })
					if success then
						if not table.find(self.state.profile.equippedItemIds, selected.id) then
							table.insert(self.state.profile.equippedItemIds, selected.id)
						end
						self.avatarPreviewDirty = true
						self:_Toast("success", "Equipped on your in-game avatar.")
						self:_RenderActivePage()
						return
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
				local success, data = self:_Invoke(Network.Actions.PublishItem, { itemId = selected.id })
				if success then
					self.state.profile.items[selected.id].publishedAssetId = data.assetId
					self:_Toast("success", "Your wearable was published to Roblox.")
					self:_RenderActivePage()
					return
				end
				if publish.Parent then
					publish.Active = true
					publish.Text = "Publish wearable"
				end
			end)
		end)

		local noteY = actionsY + 60
		Factory.Label(
			body,
			"Equip wears it right now. Publish sends it to Roblox to become a real wearable -- this can open Roblox's own purchase prompt.",
			UDim2.new(1, -32, 0, 34),
			{
				Position = UDim2.fromOffset(16, noteY),
				Color = Colors.TextMuted,
				TextSize = 10,
				Wrapped = true,
				AlignX = Enum.TextXAlignment.Center,
			}
		)

		-- Centred and flanked by a flourish either side, the way the concept
		-- art draws every one of these mode-switch links. Fixed-width so the
		-- flourishes can be paired to its actual edges; at compact widths a
		-- 420px link would overflow the panel, so there it stays full-width
		-- and unflanked.
		local switchY = noteY + 44
		local switchAdvanced = Factory.ImageButton(
			body,
			"Switch to Advanced Mode for fit, pricing & sharing ✦",
			if self.compact then UDim2.new(1, -32, 0, 30) else UDim2.fromOffset(420, 30),
			if self.compact then UDim2.fromOffset(16, switchY) else UDim2.new(0.5, -210, 0, switchY),
			nil
		)
		switchAdvanced.TextSize = 12
		if not self.compact then
			Factory.FlourishFlank(body, switchY + 15, 228)
		end
		self:_BindButton(switchAdvanced)
		switchAdvanced.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
	end
end

function App:_TrackFirstLookGuide(stage: string, action: string)
	local key = action .. ":" .. stage
	if self.firstLookGuideEvents[key] then
		return
	end
	self.firstLookGuideEvents[key] = true
	self:_Track({
		event = "FirstLookGuide",
		fields = { stage = stage, action = action },
	})
end

-- Shared by the featured First Look card and the regular marketplace grid.
-- A successful response means ItemService actually attached the model; the
-- server now logs funnel step two only at that point.
function App:_ApplyCommunityTryOn(item: { [string]: any }, button: TextButton, entryPoint: string)
	local removing = self.communityTryOnItem ~= nil and self.communityTryOnItem.id == item.id
	button.Active = false
	button.Text = if removing then "Removing…" else "Applying…"
	task.spawn(function()
		local success, errorCode = self:_Invoke(
			if removing then Network.Actions.ClearCommunityTryOn else Network.Actions.TryOnCommunityItem,
			if removing
				then {}
				else {
					itemId = item.id,
					entryPoint = if entryPoint == "FIRST_LOOK" then "FIRST_LOOK" else "GRID",
				}
		)
		if success then
			self.communityTryOnItem = if removing then nil else item
			self.avatarPreviewDirty = true
			if not removing then
				self.sounds:Play("Success")
			end
			self:_Toast(
				"success",
				if removing
					then "Community model removed."
					else "Look applied! Check your avatar, then take it to Forge Runway."
			)
			self:_RenderActivePage()
			return
		end
		if button.Parent then
			button.Active = true
			button.Text = if removing
				then "Remove"
				else if entryPoint == "FIRST_LOOK" then "Try this look · FREE" else "Try on"
		end
		if not removing and errorCode == "ITEM_NOT_FOUND" then
			self.featuredCommunityItem = nil
			self.marketplaceItems = nil
			self:_RefreshMarketplace("")
		end
	end)
end

-- Returns the vertical space consumed above Discover's search controls.
-- Until First Look is complete, this is the page's dominant action: a free
-- public-model try-on with no AvatarEditorService permission prompt, then a
-- direct handoff to the already-performing Runway loop.
function App:_RenderDiscoverFirstLook(topY: number): number
	local journey = self.state.journeyState
	if not journey or journey.completed == true then
		return 0
	end

	local done = journey.done or {}
	local height = if self.compact then 190 else 146
	local card =
		Factory.ImageCard(self.content, UDim2.new(0.95, 0, 0, height), UDim2.new(0.025, 0, 0, topY), "FirstLookGuide")
	Factory.Stroke(card, if done.TRY_STYLE then Colors.Mint else Colors.Cyan, 0.18, 1.5)

	local featured = self.featuredCommunityItem
		or (if self.marketplaceItems and #self.marketplaceItems > 0 then self.marketplaceItems[1] else nil)
	local previewRecord = if done.TRY_STYLE and self.communityTryOnItem then self.communityTryOnItem else featured
	local previewImage = if previewRecord then modelPreviewImage(previewRecord) else ""
	local previewModelId = if previewRecord then tonumber(previewRecord.modelAssetId) else nil
	local previewFallback = if previewModelId and previewModelId > 0 then thumbnail(previewModelId, 150) else nil
	if previewImage == "" and previewFallback then
		previewImage = previewFallback
	end
	local visualSize = if self.compact then 72 else 116
	local visual = Factory.New("ImageLabel", {
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(visualSize, visualSize),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		Image = previewImage,
		ScaleType = Enum.ScaleType.Crop,
		Parent = card,
	})
	Factory.Corner(visual, 14)
	if visual.Image == "" then
		Factory.Gradient(visual, { Color3.fromRGB(28, 35, 72), Color3.fromRGB(64, 39, 108) }, 135)
		Factory.Label(visual, if self.marketplaceItems == nil then "…" else "◇", UDim2.fromScale(1, 1), {
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 32,
			Color = Colors.Cyan,
		})
	elseif previewRecord then
		local hint = Factory.Label(visual, "Loading preview…", UDim2.new(1, -12, 0, 28), {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 6, 1, -6),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.Text,
			TextSize = 9,
			Wrapped = true,
			ZIndex = 2,
		})
		hint.BackgroundColor3 = Colors.Ink
		hint.BackgroundTransparency = 0.18
		Factory.Corner(hint, 7)
		self:_WatchImageLoad(visual, hint, previewFallback)
	end

	local textX = if self.compact then 98 else 146
	local headingWidth = if self.compact then UDim2.new(1, -112, 0, 28) else UDim2.new(1, -390, 0, 28)
	local stage = "TRY_FREE_LOOK"
	local heading = "Your free First Look"
	local description = "One tap puts a featured creator accessory on your avatar. No Robux. No catalog permission."
	local buttonText = "Try this look · FREE"
	local badgeText = "STEP 2 OF 4"
	if done.TRY_STYLE then
		if done.JOIN_RUNWAY then
			stage = "FINISH_RUNWAY"
			heading = "Finish your style round"
			description = "Your look is locked. Complete the round to finish First Look and earn the completion reward."
			buttonText = "Return to Runway"
			badgeText = "FINAL STEP"
		else
			stage = "ENTER_RUNWAY"
			heading = "Your look is on!"
			description = "Now bring it to Forge Runway. Locking your look is the next step—and the round is free."
			buttonText = "Enter Forge Runway →"
			badgeText = "STEP 3 OF 4"
		end
	elseif not featured and self.marketplaceItems ~= nil and #self.marketplaceItems == 0 then
		stage = "EMPTY_MARKETPLACE"
		heading = "No community looks are live yet"
		description = "You can still complete this step with a free Roblox catalog try-on in Avatar Lab."
		buttonText = "Open Avatar Lab"
		badgeText = "FREE FALLBACK"
	elseif not featured and self.marketplaceItems == nil then
		heading = "Finding a free look…"
		description = "Loading the current trending community accessory. This does not spend Robux or Forge Tokens."
		buttonText = "Loading…"
		badgeText = "FIRST LOOK"
	end

	-- The concept art leads with the step badge and reads downward from it
	-- into the heading and the line of copy -- the step you are on is the
	-- first thing to land, not a footnote under the description.
	local badge = Factory.ImagePill(card, badgeText, if done.TRY_STYLE then Colors.Mint else Colors.Cyan, 124)
	badge.Position = UDim2.fromOffset(textX, 14)
	local badgeStud = Factory.Icon(badge, if done.TRY_STYLE then "GemMint" else "GemCyan", UDim2.fromOffset(12, 12))
	if badgeStud then
		badgeStud.Position = UDim2.fromOffset(10, 8)
		badgeStud.ZIndex = 2
		badge.Text = "   " .. badge.Text
	end
	Factory.Label(card, heading, headingWidth, {
		Position = UDim2.fromOffset(textX, 44),
		Font = Theme.Fonts.Black,
		TextSize = if self.compact then 17 else 20,
		Truncate = Enum.TextTruncate.AtEnd,
	})
	Factory.Label(card, description, if self.compact then UDim2.new(1, -112, 0, 48) else UDim2.new(1, -390, 0, 48), {
		Position = UDim2.fromOffset(textX, 76),
		Color = Colors.TextMuted,
		TextSize = if self.compact then 10 else 12,
		Wrapped = true,
		AlignY = Enum.TextYAlignment.Top,
	})

	local action = Factory.ImageButton(
		card,
		buttonText,
		if self.compact then UDim2.new(1, -28, 0, 42) else UDim2.fromOffset(218, 46),
		if self.compact then UDim2.fromOffset(14, 134) else UDim2.new(1, -232, 0, 50),
		if done.TRY_STYLE then "mint" else "primary"
	)
	self:_BindButton(action)
	local actionReady = done.TRY_STYLE or featured ~= nil or self.marketplaceItems ~= nil
	action.Active = actionReady
	if actionReady then
		self:_TrackFirstLookGuide(stage, "IMPRESSION")
	end
	action.Activated:Connect(function()
		self:_TrackFirstLookGuide(stage, "CLICK")
		if done.TRY_STYLE then
			RunwayHub.Show(self)
		elseif featured then
			self:_ApplyCommunityTryOn(featured, action, "FIRST_LOOK")
		else
			self:_OpenPage("Avatar Lab")
		end
	end)

	return height + 12
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
			local items = if type(data) == "table" and type(data.items) == "table" then data.items else {}
			self.marketplaceItems = items
			if
				self.marketplaceQuery == ""
				and self.marketplaceSearchBy == "NAME"
				and self.marketplaceSortBy == "TRENDING"
				and items[1]
			then
				self.featuredCommunityItem = items[1]
			end
			if self.activePage == "Discover" then
				self:_RenderActivePage()
			end
		end
	end)
end

function App:_RenderDiscover()
	local simpleMode = self.state.profile.settings.simpleMode ~= false
	local showAllMethods = not simpleMode
	self:_PageHeader(
		"Discover",
		if showAllMethods
			then "Try on every public design for free. Like, favorite, and support creators through verified Plus transfers."
			else "Try on things other players made. Tap Try on, then Like the ones you love.",
		true
	)
	if not self.state.policy.contentSharingAllowed then
		local blocked = Factory.ImageCard(self.content, UDim2.new(0.95, 0, 0, 230), UDim2.new(0.025, 0, 0, 112))
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
	local firstLookOffset: number = self:_RenderDiscoverFirstLook(96)
	local toolsY = 96 + firstLookOffset
	local toolsHeight: number = if showAllMethods
		then (if self.compact then 98 else 48)
		else (if self.compact then 92 else 48)
	local gridY: number
	local tools = Factory.New("Frame", {
		Position = UDim2.new(0.025, 0, 0, toolsY),
		Size = UDim2.new(0.95, 0, 0, toolsHeight),
		BackgroundTransparency = 1,
		Parent = self.content,
	})
	local search = self:_TextBox(
		tools,
		if self.marketplaceSearchBy == "CREATOR" then "Search by creator username" else "Search public designs",
		if self.compact
			then UDim2.new(1, 0, 0, 42)
			elseif showAllMethods then UDim2.new(1, -232, 0, 42)
			else UDim2.new(1, -112, 0, 42),
		UDim2.new(),
		false
	)
	search.Text = self.marketplaceQuery
	-- The concept art draws this bar as the page's glowing well, with a
	-- magnifier sitting inside its right edge rather than on the button.
	self:_GlowField(search)
	Factory.Label(search, "🔍", UDim2.fromOffset(24, 24), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		AlignX = Enum.TextXAlignment.Center,
		TextSize = 16,
		Color = Colors.Cyan,
	})
	local refresh = Factory.ImageButton(
		tools,
		"Search",
		if self.compact then UDim2.new(0.5, -5, 0, 40) else UDim2.fromOffset(96, 42),
		if self.compact
			then UDim2.fromOffset(0, 50)
			elseif showAllMethods then UDim2.new(1, -216, 0, 0)
			else UDim2.new(1, -96, 0, 0),
		"primary"
	)
	self:_BindButton(refresh)
	refresh.Activated:Connect(function()
		self:_RefreshMarketplace(search.Text)
	end)
	search.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:_RefreshMarketplace(search.Text)
		end
	end)

	if showAllMethods then
		local plus = Factory.ImageButton(
			tools,
			if self.state.benefits.plusSubscriber then "Plus active ✓" else "Get Roblox Plus",
			if self.compact then UDim2.new(0.5, -5, 0, 40) else UDim2.fromOffset(110, 42),
			if self.compact then UDim2.new(0.5, 5, 0, 50) else UDim2.new(1, -110, 0, 0),
			if self.state.benefits.plusSubscriber then "mint" else nil
		)
		self:_BindButton(plus)
		plus.Activated:Connect(function()
			if not self.state.benefits.plusSubscriber then
				task.spawn(function()
					self:_Invoke(Network.Actions.PromptPlus, {})
				end)
			end
		end)

		local filtersY = toolsY + toolsHeight + 6
		local filters = Factory.New("ScrollingFrame", {
			Position = UDim2.new(0.025, 0, 0, filtersY),
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
			local chip = Factory.ImageButton(
				filters,
				mode.Label,
				UDim2.fromOffset(96, 30),
				nil,
				if selected then "primary" else nil
			)
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
			local chip = Factory.ImageButton(
				filters,
				sort.Label,
				UDim2.fromOffset(94, 30),
				nil,
				if selected then "primary" else nil
			)
			self:_BindButton(chip)
			chip.Activated:Connect(function()
				self.marketplaceSortBy = sort.Id
				self:_RefreshMarketplace(search.Text)
				self:_RenderActivePage()
			end)
		end
		local leaderboardChip =
			Factory.ImageButton(filters, "🏆 Top Creators", UDim2.fromOffset(130, 30), nil, "mint")
		self:_BindButton(leaderboardChip)
		leaderboardChip.Activated:Connect(function()
			self:_ShowLeaderboard()
		end)
		local simpleChip = Factory.ImageButton(filters, "← Simple Mode", UDim2.fromOffset(120, 30), nil, nil)
		self:_BindButton(simpleChip)
		simpleChip.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", true)
		end)

		gridY = filtersY + 58
	else
		-- Centred and flanked by a flourish either side, exactly as the
		-- concept art draws every one of these mode-switch links. Fixed
		-- width in wide layouts so the flourishes pair to its real edges;
		-- compact keeps the full-width bar, where 440px would overflow.
		local switchY = toolsY + toolsHeight + 10
		local switchAdvanced = Factory.ImageButton(
			self.content,
			"Switch to Advanced Mode for filters, sorting & buying ✦",
			if self.compact then UDim2.new(0.95, 0, 0, 30) else UDim2.fromOffset(440, 30),
			if self.compact then UDim2.new(0.025, 0, 0, switchY) else UDim2.new(0.5, -220, 0, switchY),
			nil
		)
		switchAdvanced.TextSize = 12
		if not self.compact then
			Factory.FlourishFlank(self.content, switchY + 15, 238)
		end
		self:_BindButton(switchAdvanced)
		switchAdvanced.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
		gridY = switchY + 30 + 16
	end

	if self.marketplaceItems == nil then
		Factory.Label(self.content, "Loading trending creations…", UDim2.new(1, -52, 0, 60), {
			Position = UDim2.fromOffset(26, gridY + 22),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			Font = Theme.Fonts.Bold,
		})
		self:_RefreshMarketplace(self.marketplaceQuery)
		return
	end
	local grid = Factory.New("ScrollingFrame", {
		Position = UDim2.new(0.02, 0, 0, gridY),
		Size = UDim2.new(0.96, 0, 1, -(gridY + 16)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Violet,
		Parent = self.content,
	})
	self:_TrackScroll(grid, "DiscoverGrid")
	Factory.ScalePadding(grid, 0.008, 0.008)
	Factory.New("UIGridLayout", {
		-- 336 left only 8px between the Try on/Buy copy row (bottom at 288)
		-- and the like/favorite row below it; both gaps opened to ~10px.
		CellSize = UDim2.new(1 / self.gridColumns, -12 * (self.gridColumns - 1) / self.gridColumns, 0, 338),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, item in self.marketplaceItems do
		local card = Factory.ImageCard(grid, UDim2.fromScale(1, 1), nil, "CommunityItem")
		card.LayoutOrder = index
		local image = Factory.New("ImageLabel", {
			Size = UDim2.new(1, -20, 0, 176),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			Image = modelPreviewImage(item),
			ScaleType = Enum.ScaleType.Crop,
			Parent = card,
		})
		Factory.Corner(image, 11)
		-- The concept art frames each gallery preview in its own thin gold
		-- rim rather than letting the render sit flush on the card.
		Factory.Stroke(image, Colors.Gold, 0.45)
		local imageHint = Factory.Label(image, "Preview processing on Roblox…", UDim2.new(1, -16, 0, 34), {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 8, 1, -8),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.Text,
			TextSize = 10,
			Wrapped = true,
			ZIndex = 2,
		})
		imageHint.BackgroundColor3 = Colors.Ink
		imageHint.BackgroundTransparency = 0.18
		Factory.Corner(imageHint, 8)
		self:_WatchImageLoad(image, imageHint, thumbnail(item.modelAssetId, 420))
		if showAllMethods and item.isListed then
			Factory.ImagePill(card, string.format("R$ %d", item.listingPriceRobux), Colors.Mint, 68).Position =
				UDim2.fromOffset(156, 18)
		end
		-- The concept art centres a gallery card's title over its byline and
		-- drops the style/detail metadata from it: in Simple Mode "AUTO /
		-- BALANCED" is art-direction jargon for settings that page can't
		-- even change. Advanced Mode keeps the full line, where those two
		-- values are things the player picked.
		Factory.Label(card, item.title or item.name, UDim2.new(1, -20, 0, 27), {
			Position = UDim2.fromOffset(10, 194),
			AlignX = if showAllMethods then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		local itemMeta = string.format(
			"%s / %s",
			string.gsub(item.stylePreset or "AUTO", "_", " "),
			string.gsub(item.detailLevel or "BALANCED", "_", " ")
		)
		Factory.Label(
			card,
			if showAllMethods
				then string.format("by @%s · %s", tostring(item.ownerName), itemMeta)
				else string.format("by @%s", tostring(item.ownerName)),
			UDim2.new(1, -20, 0, 22),
			{
				Position = UDim2.fromOffset(10, 221),
				AlignX = if showAllMethods then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
				Color = Colors.TextMuted,
				TextSize = 11,
				Truncate = Enum.TextTruncate.AtEnd,
			}
		)
		-- Invisible hit target over the preview/title/subtitle area (everything
		-- above where Try on/Buy copy start) so clicking the card opens the
		-- full detail overlay -- sized to stop exactly at y=250 so it can never
		-- steal a click from either button below it.
		local expand = Factory.New("TextButton", {
			Name = "ExpandHit",
			Size = UDim2.new(1, 0, 0, 250),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			Parent = card,
		})
		self.sounds:Bind(expand)
		expand.MouseEnter:Connect(function()
			self:_Animate(expand, TweenInfo.new(0.14), { BackgroundTransparency = 0.94 })
		end)
		expand.MouseLeave:Connect(function()
			self:_Animate(expand, TweenInfo.new(0.14), { BackgroundTransparency = 1 })
		end)
		expand.Activated:Connect(function()
			self:_ShowContentDetail({
				kind = "ITEM",
				id = item.id,
				ownerUserId = item.ownerUserId,
				ownerName = item.ownerName,
				title = item.title or item.name,
				meta = itemMeta,
				description = item.description,
				imageId = item.thumbnailAssetId,
				modelAssetId = item.modelAssetId,
				previewImage = modelPreviewImage(item),
				isListed = item.isListed,
				listingPriceRobux = item.listingPriceRobux,
				likes = item.likes,
				favorites = item.favorites,
				viewerLiked = item.viewerLiked,
				viewerFavorited = item.viewerFavorited,
				refresh = function()
					self:_RefreshMarketplace(search.Text)
				end,
			})
		end)
		-- The old -5/-15 split left "Buy copy" only ~5px from the card's own
		-- right edge (and an equally cramped 5px between the two buttons);
		-- widened both gaps to a real ~10px.
		local isCommunityTryOn = self.communityTryOnItem ~= nil and self.communityTryOnItem.id == item.id
		local try = Factory.ImageButton(
			card,
			if isCommunityTryOn then "Remove" else "Try on",
			if showAllMethods then UDim2.new(0.48, -14, 0, 38) else UDim2.new(1, -20, 0, 38),
			UDim2.fromOffset(10, 250),
			if isCommunityTryOn then "danger" else "primary"
		)
		self:_BindButton(try)
		try.Activated:Connect(function()
			self:_ApplyCommunityTryOn(item, try, "GRID")
		end)
		if showAllMethods then
			local buy = Factory.ImageButton(
				card,
				if item.isListed then "Buy copy" else "Not for sale",
				UDim2.new(0.52, -14, 0, 38),
				UDim2.new(0.48, 4, 0, 250),
				if item.isListed then "mint" else nil
			)
			self:_BindButton(buy)
			buy.Active = item.isListed == true
			buy.Activated:Connect(function()
				buy.Active = false
				buy.Text = "Checking listing…"
				task.spawn(function()
					local success, errorCode =
						self:_Invoke(Network.Actions.BeginMarketplacePurchase, { itemId = item.id })
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
		end
		-- Coloured glyphs, per the concept art's red heart and gold star --
		-- a TextButton has one TextColor3, so each glyph is its own label
		-- sitting beside a count-only button rather than one two-tone string.
		local like = Factory.ImageButton(
			card,
			formatNumber(item.likes),
			UDim2.new(0.5, -15, 0, 30),
			UDim2.fromOffset(10, 298),
			nil
		)
		local favorite = Factory.ImageButton(
			card,
			formatNumber(item.favorites),
			UDim2.new(0.5, -15, 0, 30),
			UDim2.new(0.5, 5, 0, 298),
			nil
		)
		for _, glyph in
			{
				{ button = like, text = if item.viewerLiked then "♥" else "♡", color = Colors.Rose },
				{ button = favorite, text = if item.viewerFavorited then "★" else "☆", color = Colors.Gold },
			}
		do
			Factory.Label(glyph.button, glyph.text, UDim2.fromOffset(20, 30), {
				Position = UDim2.fromOffset(10, 0),
				AlignX = Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = 14,
				Color = glyph.color,
				ZIndex = 6,
			})
			glyph.button.Text = "   " .. glyph.button.Text
		end
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
	local simpleMode = self.state.profile.settings.simpleMode ~= false
	local showAllMethods = not simpleMode
	self:_PageHeader(
		"Avatar Lab",
		if showAllMethods
			then "Mix Roblox Marketplace accessories with your Forge creations and stay longer in the look."
			else "Try on free Roblox items. Tap a category below, then Try on.",
		true
	)
	-- The creator-name/price-range row is the single biggest thing in this
	-- card, and most searches never touch it — collapsed by default, it only
	-- renders (and only counts toward controlsHeight) once a player asks for
	-- it, so the catalog grid below gets that space back instead of always
	-- reserving it for filters most sessions never open. Simple Mode never
	-- expands it at all (nor the SORT row below) -- see the showAllMethods
	-- branches further down.
	local filtersExpanded = showAllMethods and self.catalogFiltersExpanded == true
	local filtersActive = showAllMethods
		and (self.catalogCreatorName ~= "" or self.catalogMinPrice ~= "" or self.catalogMaxPrice ~= "")
	local controlsHeight: number
	if showAllMethods then
		controlsHeight = if filtersExpanded
			then (if self.compact then 276 else 200)
			else (if self.compact then 194 else 151)
	else
		-- accessoryChipsY (106 compact / 63 desktop, computed below) + the
		-- 32px chip row + 16px bottom padding. Simple Mode's switch-to-
		-- Advanced control is the last chip in that same row now (the
		-- concept art puts it there), not a separate bar below it.
		controlsHeight = if self.compact then 154 else 111
	end
	local runwayState = self.runwayState or self.state.runwayState
	local runwayJoined = runwayState and runwayState.joined == true
	local controlsTop = if runwayJoined then 164 else 94
	if runwayJoined then
		local runwayBanner =
			Factory.ImageCard(self.content, UDim2.new(0.95, 0, 0, 54), UDim2.new(0.025, 0, 0, 94), "RunwayReturn")
		local runwayLabel = Factory.Label(runwayBanner, "", UDim2.new(1, -154, 1, 0), {
			Position = UDim2.fromOffset(14, 0),
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			Color = Colors.Rose,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		local returnButton = Factory.ImageButton(
			runwayBanner,
			if runwayState.ready then "View round" else "Return & lock in",
			UDim2.fromOffset(126, 34),
			UDim2.new(1, -140, 0, 10),
			"primary"
		)
		self:_BindButton(returnButton)
		returnButton.Activated:Connect(function()
			RunwayHub.Show(self)
		end)
		local bannerVersion = self.pageVersion
		task.spawn(function()
			while bannerVersion == self.pageVersion and runwayLabel.Parent do
				local liveState = self.runwayState or runwayState
				local remaining = math.max(0, math.floor((liveState.endsAt or os.time()) - os.time()))
				runwayLabel.Text = string.format(
					"◆  %s · %d:%02d",
					liveState.theme or "Forge Runway",
					math.floor(remaining / 60),
					remaining % 60
				)
				returnButton.Text = if liveState.joined == false
					then "Next round"
					elseif liveState.ready then "View round"
					else "Return & lock in"
				task.wait(1)
			end
		end)
	end
	local controls = Factory.ImageCard(
		self.content,
		UDim2.new(0.95, 0, 0, controlsHeight),
		UDim2.new(0.025, 0, 0, controlsTop),
		"CatalogControls"
	)
	local search = self:_TextBox(
		controls,
		"Search the Roblox avatar marketplace",
		if self.compact then UDim2.new(1, -28, 0, 40) else UDim2.new(1, -346, 0, 42),
		UDim2.fromOffset(14, 13),
		false
	)
	search.Text = self.catalogQuery
	-- Same glowing well the concept art gives Create's prompt and
	-- Discover's search, with the magnifier inside its right edge.
	self:_GlowField(search)
	Factory.Label(search, "🔍", UDim2.fromOffset(24, 24), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		AlignX = Enum.TextXAlignment.Center,
		TextSize = 16,
		Color = Colors.Cyan,
	})
	local searchButton = Factory.ImageButton(
		controls,
		"Search",
		if self.compact then UDim2.new(0.32, -8, 0, 36) else UDim2.fromOffset(92, 42),
		if self.compact then UDim2.fromOffset(14, 59) else UDim2.new(1, -322, 0, 13),
		"primary"
	)
	local saveAvatar = Factory.ImageButton(
		controls,
		if self.compact then "Save" else "Save avatar",
		if self.compact then UDim2.new(0.34, -8, 0, 36) else UDim2.fromOffset(100, 42),
		if self.compact then UDim2.new(0.32, 7, 0, 59) else UDim2.new(1, -220, 0, 13),
		"mint"
	)
	local reset = Factory.ImageButton(
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
			local success = self:_Invoke(Network.Actions.ResetAvatar, {})
			if success then
				-- Reset reapplies the player's saved Roblox avatar wholesale,
				-- discarding every catalog try-on at once, so the client's
				-- per-item tracking must be cleared to match.
				self.triedOnAssetIds = {}
				self.triedOnAssetInfo = {}
				self.avatarAccessoriesDirty = true
				self.communityTryOnItem = nil
				self.avatarPreviewDirty = true
				self:_RenderActivePage()
			end
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
	local chipIndex = 0
	for typeName, label in ACCESSORY_LABELS do
		chipIndex += 1
		local chip = Factory.ImageButton(
			chips,
			label,
			UDim2.fromOffset(94, 30),
			nil,
			if self.catalogType == typeName then "primary" else nil
		)
		-- The concept art studs every category chip with a gem, walking down
		-- the palette across the row.
		local stud = Factory.Icon(
			chip,
			CHIP_GEMS[(chipIndex - 1) % #CHIP_GEMS + 1],
			UDim2.fromOffset(12, 12),
			UDim2.fromOffset(9, 9)
		)
		if stud then
			stud.ZIndex = 2
			chip.Text = "  " .. label
		end
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.catalogType = typeName
			self:_ApplyCatalogFilters()
			self:_RenderActivePage()
		end)
	end
	if not showAllMethods then
		-- The concept art keeps this at the end of the category row rather
		-- than as its own full-width bar below -- the mirror image of
		-- Advanced Mode's "<- Simple Mode" chip in the same spot.
		local switchAdvanced = Factory.ImageButton(chips, "Advanced Mode ✦", UDim2.fromOffset(140, 30), nil, nil)
		self:_BindButton(switchAdvanced)
		switchAdvanced.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
	end
	if showAllMethods then
		local filtersToggle = Factory.ImageButton(
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
		local simpleChip = Factory.ImageButton(chips, "← Simple Mode", UDim2.fromOffset(120, 30), nil, nil)
		self:_BindButton(simpleChip)
		simpleChip.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", true)
		end)
	end

	-- Also the Y the creator/price filter fields build on below (once
	-- expanded) -- kept in scope outside the branch since filtersExpanded
	-- can only be true when showAllMethods is true, but that check happens
	-- well after this branch closes.
	local sortY = accessoryChipsY + 40
	if showAllMethods then
		-- Real Roblox Marketplace search options: sort order, then creator
		-- name and price range. A visible Label precedes every input here
		-- (rather than relying on placeholder text alone) so the row reads
		-- correctly for screen-reader-style access and keyboard/gamepad
		-- users tabbing through. Simple Mode skips sorting/creator/price
		-- entirely -- see controlsHeight above for its shorter card.
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
			local chip = Factory.ImageButton(
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
		local access = Factory.ImageCard(
			self.content,
			UDim2.new(0.95, 0, 0, 190),
			UDim2.new(0.025, 0, 0, controlsTop + controlsHeight + 16),
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
		local enable = Factory.ImageButton(
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
	local belowControls = controlsTop + controlsHeight + 16
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
	self:_TrackScroll(grid, "AvatarLabGrid")
	Factory.ScalePadding(grid, 0.008, 0.008)
	Factory.New("UIGridLayout", {
		-- 292 left only 6px between the Try/Buy row (bottom at 286) and the
		-- card's own bottom edge; grown 4px so that's a real ~10px.
		CellSize = UDim2.new(1 / self.gridColumns, -12 * (self.gridColumns - 1) / self.gridColumns, 0, 296),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, item in self.catalogResults or {} do
		local assetId = tonumber(item.Id or item.AssetId) or 0
		if assetId > 0 then
			local card = Factory.ImageCard(grid, UDim2.fromScale(1, 1), nil, "CatalogItem")
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
			-- Same thin gold rim the concept art frames every gallery
			-- preview in, on Discover and here alike.
			Factory.Stroke(image, Colors.Gold, 0.45)
			Factory.Label(card, tostring(item.Name or "Catalog item"), UDim2.new(1, -20, 0, 28), {
				Position = UDim2.fromOffset(10, 196),
				AlignX = if showAllMethods then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Bold,
				TextSize = 13,
				Truncate = Enum.TextTruncate.AtEnd,
			})
			local price = tonumber(item.Price or item.LowestPrice)
			if showAllMethods then
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
			end
			-- The old -12/-8 split left "Buy" only ~4px from the card's own
			-- right edge; widened both the outer and inter-button gaps to a
			-- real ~10px (matching the CellSize bump above).
			-- "Try on" in Simple Mode, matching the concept art's full-width
			-- button; Advanced Mode keeps the shorter "Try" that has to
			-- share the row with Buy.
			local try = Factory.ImageButton(
				card,
				if self.triedOnAssetIds[assetId] then "Unequip" elseif showAllMethods then "Try" else "Try on",
				if showAllMethods then UDim2.new(0.45, -14, 0, 38) else UDim2.new(1, -20, 0, 38),
				UDim2.fromOffset(10, 248),
				if self.triedOnAssetIds[assetId] then "danger" else "primary"
			)
			self:_BindButton(try)
			if showAllMethods then
				local buy =
					Factory.ImageButton(card, "Buy", UDim2.new(0.55, -14, 0, 38), UDim2.new(0.45, 4, 0, 248), "mint")
				self:_BindButton(buy)
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
			try.Activated:Connect(function()
				local removing = self.triedOnAssetIds[assetId] == true
				try.Active = false
				try.Text = if removing then "Removing…" else "Applying…"
				task.spawn(function()
					local success = self:_Invoke(
						if removing then Network.Actions.UntryCatalogAsset else Network.Actions.TryCatalogAsset,
						{ assetId = assetId, avatarAssetType = self.catalogType }
					)
					if success then
						-- Applying a HumanoidDescription replaces temporary physical
						-- try-ons. Forge-owned equipped items are restored server-side;
						-- a community preview is intentionally cleared.
						self.communityTryOnItem = nil
						if removing then
							self.triedOnAssetIds[assetId] = nil
							self.triedOnAssetInfo[assetId] = nil
							self.avatarAccessoriesDirty = true
							self:_Toast("success", "Catalog item removed.")
						else
							self.triedOnAssetIds[assetId] = true
							self.triedOnAssetInfo[assetId] =
								{ name = tostring(item.Name or "Catalog item"), assetType = self.catalogType }
							self.avatarAccessoriesLoaded = true
							self:_Toast("success", "Catalog item applied. Keep browsing to build your look.")
						end
						self.avatarPreviewDirty = true
						self:_RenderActivePage()
					elseif try.Parent then
						try.Active = true
						try.Text = if removing then "Unequip" elseif showAllMethods then "Try" else "Try on"
					end
				end)
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

-- A standalone image section, deliberately separate from every accessory /
-- 3D-model generation method above: nothing created here can be equipped,
-- fitted, or converted to a mesh. It exists purely to turn the player's own
-- current Roblox avatar into a piece of art they can browse and keep, using
-- the same purchasable image-quality tiers as the reference-image step
-- (Config.Generation.ImageQualityTiers) since both are a single OpenAI image
-- call with no Meshy pipeline cost behind them -- see
-- GenerationService:CreateAvatarGraphic.
function App:_RefreshGraphicsMarketplace(query: string?)
	self.graphicsMarketplaceQuery = query or self.graphicsMarketplaceQuery or ""
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.GetGraphicsMarketplace, {
			query = self.graphicsMarketplaceQuery,
			searchBy = self.graphicsMarketplaceSearchBy,
			sortBy = self.graphicsMarketplaceSortBy,
		})
		if success then
			self.graphicsMarketplaceItems = data.graphics
			if self.activePage == "Avatar Graphics" and self.graphicsTab == "DISCOVER" then
				self:_RenderActivePage()
			end
		end
	end)
end

-- Mirrors _RenderDiscover's search/sort/grid pattern (see that function for
-- the item-marketplace original this was mirrored from), scoped to graphics:
-- no "try on" concept (graphics aren't wearable), and search matches the
-- prompt text since graphics have no separate name field.
function App:_RenderGraphicsDiscoverBody()
	local simpleMode = self.state.profile.settings.simpleMode ~= false
	local showAllMethods = not simpleMode
	if not self.state.policy.contentSharingAllowed then
		local blocked = Factory.ImageCard(self.content, UDim2.new(0.95, 0, 0, 200), UDim2.new(0.025, 0, 0, 150))
		Factory.Label(blocked, "Shared graphics are unavailable", UDim2.new(1, -40, 0, 32), {
			Position = UDim2.fromOffset(20, 30),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = 20,
		})
		Factory.Label(
			blocked,
			"Forge respects Roblox PolicyService. Community sharing is hidden for this account.",
			UDim2.new(1, -70, 0, 60),
			{
				Position = UDim2.fromOffset(35, 68),
				AlignX = Enum.TextXAlignment.Center,
				Color = Colors.TextMuted,
				TextSize = 13,
				Wrapped = true,
			}
		)
		return
	end
	local tools = Factory.New("Frame", {
		Position = UDim2.new(0.025, 0, 0, 144),
		Size = UDim2.new(0.95, 0, 0, if self.compact then 98 else 48),
		BackgroundTransparency = 1,
		Parent = self.content,
	})
	local search = self:_TextBox(
		tools,
		if self.graphicsMarketplaceSearchBy == "CREATOR" then "Search by creator username" else "Search prompts",
		if self.compact then UDim2.new(1, 0, 0, 42) else UDim2.new(1, -140, 0, 42),
		UDim2.new(),
		false
	)
	search.Text = self.graphicsMarketplaceQuery
	-- Same glowing well with an inset magnifier the concept art gives every
	-- other search bar in the app.
	self:_GlowField(search)
	Factory.Label(search, "🔍", UDim2.fromOffset(24, 24), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		AlignX = Enum.TextXAlignment.Center,
		TextSize = 16,
		Color = Colors.Cyan,
	})
	local refresh = Factory.ImageButton(
		tools,
		"Search",
		if self.compact then UDim2.new(1, 0, 0, 40) else UDim2.fromOffset(96, 42),
		if self.compact then UDim2.fromOffset(0, 50) else UDim2.new(1, -96, 0, 0),
		"primary"
	)
	self:_BindButton(refresh)
	refresh.Activated:Connect(function()
		self:_RefreshGraphicsMarketplace(search.Text)
	end)
	search.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:_RefreshGraphicsMarketplace(search.Text)
		end
	end)

	if showAllMethods then
		local filters = Factory.New("ScrollingFrame", {
			Position = UDim2.new(0.025, 0, 0, if self.compact then 248 else 198),
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
		for _, mode in { { Id = "PROMPT", Label = "By prompt" }, { Id = "CREATOR", Label = "By creator" } } do
			local selected = self.graphicsMarketplaceSearchBy == mode.Id
			local chip = Factory.ImageButton(
				filters,
				mode.Label,
				UDim2.fromOffset(96, 30),
				nil,
				if selected then "primary" else nil
			)
			self:_BindButton(chip)
			chip.Activated:Connect(function()
				self.graphicsMarketplaceSearchBy = mode.Id
				self:_RefreshGraphicsMarketplace(search.Text)
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
			local selected = self.graphicsMarketplaceSortBy == sort.Id
			local chip = Factory.ImageButton(
				filters,
				sort.Label,
				UDim2.fromOffset(94, 30),
				nil,
				if selected then "primary" else nil
			)
			self:_BindButton(chip)
			chip.Activated:Connect(function()
				self.graphicsMarketplaceSortBy = sort.Id
				self:_RefreshGraphicsMarketplace(search.Text)
				self:_RenderActivePage()
			end)
		end
		local simpleChip = Factory.ImageButton(filters, "← Simple Mode", UDim2.fromOffset(120, 30), nil, nil)
		self:_BindButton(simpleChip)
		simpleChip.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", true)
		end)
	end

	-- Simple Mode skips the By prompt/creator + sort filter row above
	-- entirely (tools row bottom: 242 compact / 192 desktop), and shows a
	-- switch-to-Advanced link in that freed space instead of the filter row.
	local toolsBottom = 144 + (if self.compact then 98 else 48)
	local gridTop = if showAllMethods then (if self.compact then 306 else 256) else toolsBottom + 10 + 28 + 16
	if self.graphicsMarketplaceItems == nil then
		Factory.Label(self.content, "Loading trending graphics…", UDim2.new(1, -52, 0, 60), {
			Position = UDim2.fromOffset(26, gridTop - 30),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			Font = Theme.Fonts.Bold,
		})
		self:_RefreshGraphicsMarketplace(self.graphicsMarketplaceQuery)
		return
	end
	if not showAllMethods then
		local switchAdvanced = Factory.ImageButton(
			self.content,
			"Switch to Advanced Mode for filters, sorting & buying →",
			UDim2.new(0.95, 0, 0, 28),
			UDim2.new(0.025, 0, 0, toolsBottom + 10),
			nil
		)
		self:_BindButton(switchAdvanced)
		switchAdvanced.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
	end
	local grid = Factory.New("ScrollingFrame", {
		Position = UDim2.new(0.02, 0, 0, gridTop),
		Size = UDim2.new(0.96, 0, 1, -(gridTop + 16)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Mint,
		Parent = self.content,
	})
	self:_TrackScroll(grid, "GraphicsDiscoverGrid")
	Factory.ScalePadding(grid, 0.008, 0.008)
	-- 300 left only 4px between the Buy row (bottom at 256) and the
	-- like/favorite row below it (top at 260); grown 6px alongside that
	-- row's own move so both gaps read as a real ~10px. Simple Mode skips
	-- the price pill and Buy row (financial, Advanced-only) so its
	-- like/favorite row moves up into that space and the card is shorter.
	local cardHeight = if showAllMethods then 306 else 266
	Factory.New("UIGridLayout", {
		CellSize = UDim2.new(1 / self.gridColumns, -12 * (self.gridColumns - 1) / self.gridColumns, 0, cardHeight),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, graphic in self.graphicsMarketplaceItems do
		local card = Factory.ImageCard(grid, UDim2.fromScale(1, 1), nil, "CommunityGraphic")
		card.LayoutOrder = index
		local image = Factory.New("ImageLabel", {
			Size = UDim2.new(1, -20, 0, 150),
			Position = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			Image = directImage(graphic.previewAssetId),
			ScaleType = Enum.ScaleType.Crop,
			Parent = card,
		})
		Factory.Corner(image, 11)
		-- The same thin gold rim the concept art frames every gallery
		-- preview in.
		Factory.Stroke(image, Colors.Gold, 0.45)
		if showAllMethods and graphic.isListed then
			Factory.ImagePill(card, string.format("R$ %d", graphic.listingPriceRobux), Colors.Mint, 68).Position =
				UDim2.fromOffset(156, 18)
		end
		local graphicTitle = if type(graphic.title) == "string" and graphic.title ~= ""
			then graphic.title
			else string.sub(graphic.filteredPrompt or "Graphic", 1, 60)
		Factory.Label(card, graphicTitle, UDim2.new(1, -20, 0, 30), {
			Position = UDim2.fromOffset(10, 168),
			Font = Theme.Fonts.Medium,
			TextSize = 11,
			Wrapped = true,
		})
		Factory.Label(card, string.format("by @%s", tostring(graphic.ownerName)), UDim2.new(1, -20, 0, 16), {
			Position = UDim2.fromOffset(10, 200),
			Color = Colors.TextMuted,
			TextSize = 11,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		-- Same invisible-hit-target pattern as the item card above, stopping
		-- exactly at y=222 where Buy copy starts.
		local expand = Factory.New("TextButton", {
			Name = "ExpandHit",
			Size = UDim2.new(1, 0, 0, 222),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			Parent = card,
		})
		self.sounds:Bind(expand)
		expand.MouseEnter:Connect(function()
			self:_Animate(expand, TweenInfo.new(0.14), { BackgroundTransparency = 0.94 })
		end)
		expand.MouseLeave:Connect(function()
			self:_Animate(expand, TweenInfo.new(0.14), { BackgroundTransparency = 1 })
		end)
		expand.Activated:Connect(function()
			self:_ShowContentDetail({
				kind = "GRAPHIC",
				id = graphic.id,
				ownerUserId = graphic.ownerUserId,
				ownerName = graphic.ownerName,
				title = graphicTitle,
				description = graphic.description,
				imageId = graphic.previewAssetId,
				isListed = graphic.isListed,
				listingPriceRobux = graphic.listingPriceRobux,
				likes = graphic.likes,
				favorites = graphic.favorites,
				viewerLiked = graphic.viewerLiked,
				viewerFavorited = graphic.viewerFavorited,
				refresh = function()
					self:_RefreshGraphicsMarketplace(search.Text)
				end,
			})
		end)
		if showAllMethods then
			local buy = Factory.ImageButton(
				card,
				if graphic.isListed then "Buy copy" else "Not for sale",
				UDim2.new(1, -20, 0, 34),
				UDim2.fromOffset(10, 222),
				if graphic.isListed then "mint" else nil
			)
			self:_BindButton(buy)
			buy.Active = graphic.isListed == true
			buy.Activated:Connect(function()
				buy.Active = false
				buy.Text = "Checking listing…"
				task.spawn(function()
					local success, errorCode =
						self:_Invoke(Network.Actions.BeginGraphicPurchase, { graphicId = graphic.id })
					if success then
						self:_Toast("success", "Confirm the verified creator transfer in Roblox.")
					elseif errorCode == "PLUS_REQUIRED" then
						self:_ShowPlus()
					elseif errorCode == "LISTING_UNAVAILABLE" then
						self.graphicsMarketplaceItems = nil
						self:_RefreshGraphicsMarketplace(search.Text)
					end
					if buy.Parent then
						buy.Active = graphic.isListed == true
						buy.Text = if graphic.isListed then "Buy copy" else "Not for sale"
					end
				end)
			end)
		end
		local likeFavoriteY = if showAllMethods then 266 else 222
		local like = Factory.ImageButton(
			card,
			formatNumber(graphic.likes),
			UDim2.new(0.5, -15, 0, 30),
			UDim2.fromOffset(10, likeFavoriteY),
			nil
		)
		local favorite = Factory.ImageButton(
			card,
			formatNumber(graphic.favorites),
			UDim2.new(0.5, -15, 0, 30),
			UDim2.new(0.5, 5, 0, likeFavoriteY),
			nil
		)
		-- Red heart, gold star, per the concept art -- each its own label,
		-- since a TextButton has only one TextColor3 for its whole string.
		for _, glyph in
			{
				{ button = like, text = if graphic.viewerLiked then "♥" else "♡", color = Colors.Rose },
				{ button = favorite, text = if graphic.viewerFavorited then "★" else "☆", color = Colors.Gold },
			}
		do
			Factory.Label(glyph.button, glyph.text, UDim2.fromOffset(20, 30), {
				Position = UDim2.fromOffset(10, 0),
				AlignX = Enum.TextXAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = 14,
				Color = glyph.color,
				ZIndex = 6,
			})
			glyph.button.Text = "   " .. glyph.button.Text
		end
		self:_BindButton(like)
		self:_BindButton(favorite)
		like.Activated:Connect(function()
			task.spawn(function()
				local success = self:_Invoke(Network.Actions.ToggleGraphicLike, { graphicId = graphic.id })
				if success then
					self.sounds:Play("Like")
					self:_RefreshGraphicsMarketplace(search.Text)
				end
			end)
		end)
		favorite.Activated:Connect(function()
			task.spawn(function()
				local success = self:_Invoke(Network.Actions.ToggleGraphicFavorite, { graphicId = graphic.id })
				if success then
					self:_RefreshGraphicsMarketplace(search.Text)
				end
			end)
		end)
	end
	if #self.graphicsMarketplaceItems == 0 then
		Factory.Label(
			grid,
			"No public graphics match yet. Be the first creator to share one.",
			if self.compact then UDim2.new(1, -8, 0, 100) else UDim2.fromOffset(520, 100),
			{
				Color = Colors.TextMuted,
				Wrapped = true,
				TextSize = 14,
			}
		)
	end
end

function App:_RenderAvatarGraphics()
	local simpleMode = self.state.profile.settings.simpleMode ~= false
	local showAllMethods = not simpleMode
	self:_PageHeader(
		"Avatar Graphics",
		if showAllMethods
			then "Turn your current Roblox avatar -- or just a prompt -- into a standalone piece of art -- no accessory, no 3D model, just a picture worth keeping."
			else "Turn a prompt or your avatar into a picture you can keep.",
		true
	)

	local tabs = Factory.New("Frame", {
		Position = UDim2.new(0.02, 0, 0, 96),
		Size = UDim2.new(0.96, 0, 0, 38),
		BackgroundTransparency = 1,
		Parent = self.content,
	})
	Factory.List(tabs, Enum.FillDirection.Horizontal, 8)
	for _, tab in { { Id = "CREATE", Label = "Create" }, { Id = "DISCOVER", Label = "Discover" } } do
		local selected = self.graphicsTab == tab.Id
		local chip =
			Factory.ImageButton(tabs, tab.Label, UDim2.fromOffset(120, 34), nil, if selected then "primary" else nil)
		self:_BindButton(chip)
		chip.Activated:Connect(function()
			self.graphicsTab = tab.Id
			self:_RenderActivePage()
		end)
	end

	if self.graphicsTab == "DISCOVER" then
		self:_RenderGraphicsDiscoverBody()
		return
	end

	-- Everything below -- the composer, any in-progress activity, and the
	-- full personal gallery -- lives inside one scrolling stack, the same
	-- pattern the Create page uses. A fixed-height controls-card-plus-
	-- scrolling-grid split (like Avatar Lab's catalog) only works when the
	-- controls card is short; this page's composer alone can run past
	-- 450px, which left the gallery with zero or negative remaining height
	-- on smaller screens -- exactly why some options were unreachable. One
	-- scroll that grows with its content is reachable at any screen size.
	local page = Factory.New("ScrollingFrame", {
		Name = "AvatarGraphicsScroll",
		Position = UDim2.new(0.02, 0, 0, 144),
		Size = UDim2.new(0.96, 0, 1, -160),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Colors.Mint,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = self.content,
	})
	self:_TrackScroll(page, "AvatarGraphics")
	Factory.ScalePadding(page, 0.012, 0.012)
	-- The concept art runs the composer beside a narrower rail carrying
	-- IN PROGRESS and YOUR GRAPHICS, not one long stack of all three. Same
	-- split Create uses, including collapsing back to a single stack in
	-- compact layouts, where a ~37%-wide rail would be unreadable.
	local columns = if self.compact
		then nil
		else Factory.New("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = page,
		})
	if columns then
		Factory.List(columns, Enum.FillDirection.Horizontal, 20)
	end
	local stack = Factory.New("Frame", {
		Size = if self.compact then UDim2.new(1, -8, 0, 0) else UDim2.new(0.63, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = if self.compact then page else columns,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 14)
	local rightStack = if self.compact
		then stack
		else Factory.New("Frame", {
			Size = UDim2.new(0.37, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = columns,
		})
	if not self.compact then
		Factory.List(rightStack, Enum.FillDirection.Vertical, 14)
	end

	local isTextMode = self.graphicMode == "TEXT"
	local composer = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 460), nil, "GraphicComposer")
	composer.LayoutOrder = 1
	local cursorY = 16

	Factory.Label(composer, "SOURCE", UDim2.new(1, -32, 0, 18), {
		Position = UDim2.fromOffset(16, cursorY),
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		Color = Colors.TextMuted,
	})
	cursorY += 22
	local sourceRow = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, cursorY),
		Size = UDim2.new(1, -32, 0, 36),
		BackgroundTransparency = 1,
		Parent = composer,
	})
	local fromAvatar = Factory.ImageButton(
		sourceRow,
		"🧑 From My Avatar",
		UDim2.new(0.5, -5, 1, 0),
		nil,
		if isTextMode then nil else "primary"
	)
	local fromText = Factory.ImageButton(
		sourceRow,
		"✍ Text Prompt",
		UDim2.new(0.5, -5, 1, 0),
		UDim2.new(0.5, 5, 0, 0),
		if isTextMode then "primary" else nil
	)
	self:_BindButton(fromAvatar)
	self:_BindButton(fromText)
	fromAvatar.Activated:Connect(function()
		self.graphicMode = "AVATAR"
		self:_RenderActivePage()
	end)
	fromText.Activated:Connect(function()
		self.graphicMode = "TEXT"
		self:_RenderActivePage()
	end)
	cursorY += 48

	local function chipRow(
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
			Parent = composer,
		})
		Factory.List(row, Enum.FillDirection.Horizontal, 8)
		for _, option in options do
			local selected = selectedValue == option.Id
			local chip = Factory.ImageButton(
				row,
				option.Label,
				UDim2.fromOffset(106, 34),
				nil,
				if selected then "primary" else nil
			)
			if selected then
				chip.BackgroundColor3 = color
			end
			-- Every step chip in the concept art carries a gem in its own
			-- step's accent colour.
			local stud = Factory.Icon(chip, gemForAccent(color), UDim2.fromOffset(12, 12), UDim2.fromOffset(10, 11))
			if stud then
				stud.ZIndex = 2
				chip.Text = "  " .. option.Label
			end
			self:_BindButton(chip)
			chip.Activated:Connect(function()
				onChoose(option.Id)
			end)
		end
	end

	if not isTextMode then
		Factory.Label(composer, "1  CHOOSE YOUR AVATAR VIEW", UDim2.new(1, -32, 0, 22), {
			Position = UDim2.fromOffset(16, cursorY),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Mint,
		})
		cursorY += 27

		chipRow(Config.Generation.AvatarViews, self.selectedAvatarView, cursorY, Colors.Mint, function(value)
			self.selectedAvatarView = value
			self:_RenderActivePage()
		end)
		cursorY += 46

		local previewThumbType = "AvatarBust"
		for _, view in Config.Generation.AvatarViews do
			if view.Id == self.selectedAvatarView then
				previewThumbType = view.ThumbType
				break
			end
		end
		local avatarPreview = Factory.New("ImageLabel", {
			Size = UDim2.fromOffset(64, 64),
			Position = UDim2.fromOffset(16, cursorY),
			BackgroundColor3 = Colors.Ink,
			BorderSizePixel = 0,
			Image = avatarThumbnail(player.UserId, previewThumbType, 150),
			ScaleType = Enum.ScaleType.Crop,
			Parent = composer,
		})
		Factory.Corner(avatarPreview, 12)
		Factory.Label(
			composer,
			"Fetched automatically from your current Roblox avatar -- nothing to upload",
			UDim2.new(1, -32 - 76, 0, 64),
			{
				Position = UDim2.fromOffset(16 + 64 + 12, cursorY),
				Color = Colors.TextMuted,
				TextSize = 11,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Center,
			}
		)
		cursorY += 74
	end

	-- Style and quality (a pricing-tier picker) are both Advanced-only --
	-- Simple Mode leaves them at their defaults (AUTO style, LOW quality,
	-- see App.new()) exactly like Create hides Style behind the same toggle.
	if showAllMethods then
		local simpleLink = Factory.ImageButton(
			composer,
			"← Simple Mode",
			UDim2.fromOffset(120, 24),
			UDim2.fromOffset(16, cursorY),
			nil
		)
		self:_BindButton(simpleLink)
		simpleLink.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", true)
		end)
		cursorY += 32

		local styleStepLabel = if isTextMode then "1  CHOOSE A VISUAL STYLE" else "2  CHOOSE A VISUAL STYLE"
		Factory.Label(composer, styleStepLabel, UDim2.new(1, -32, 0, 22), {
			Position = UDim2.fromOffset(16, cursorY),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Violet,
		})
		cursorY += 27
		chipRow(Config.Generation.StylePresets, self.selectedStylePreset, cursorY, Colors.Violet, function(value)
			self.selectedStylePreset = value
			self:_RenderActivePage()
		end)
		cursorY += 46

		local qualityStepLabel = if isTextMode then "2  CHOOSE IMAGE QUALITY" else "3  CHOOSE IMAGE QUALITY"
		Factory.Label(composer, qualityStepLabel, UDim2.new(1, -32, 0, 22), {
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
			Parent = composer,
		})
		Factory.List(qualityRow, Enum.FillDirection.Horizontal, 8)
		for _, tier in Config.Generation.ImageQualityTiers do
			local tierSelected = self.selectedImageQuality == tier.Id
			local chip = Factory.ImageButton(
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
	end

	local promptStepLabel
	if isTextMode then
		promptStepLabel = if showAllMethods
			then "3  DESCRIBE YOUR IMAGE (REQUIRED)"
			else "1  DESCRIBE YOUR IMAGE (REQUIRED)"
	else
		promptStepLabel = if showAllMethods
			then "4  DESCRIBE A SCENE OR THEME (OPTIONAL)"
			else "2  DESCRIBE A SCENE OR THEME (OPTIONAL)"
	end
	Factory.Label(composer, promptStepLabel, UDim2.new(1, -32, 0, 22), {
		Position = UDim2.fromOffset(16, cursorY),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		Color = Colors.Rose,
	})
	cursorY += 27
	local prompt = self:_TextBox(
		composer,
		if isTextMode
			then "For example: a neon-lit cyberpunk city skyline at dusk, reflections on wet streets"
			else "For example: a heroic fantasy portrait bathed in golden light",
		UDim2.new(1, -32, 0, 64),
		UDim2.fromOffset(16, cursorY),
		true
	)
	prompt.Text = if isTextMode then self.textImagePrompt else self.avatarGraphicPrompt
	self:_GlowField(prompt, true)
	local count = Factory.Label(
		composer,
		string.format("%d / %d", #prompt.Text, Config.Generation.PromptMaxLength),
		UDim2.fromOffset(120, 20),
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, cursorY + 46),
			AlignX = Enum.TextXAlignment.Right,
			Color = Colors.TextMuted,
			TextSize = 11,
		}
	)
	prompt:GetPropertyChangedSignal("Text"):Connect(function()
		local trimmed = string.sub(prompt.Text, 1, Config.Generation.PromptMaxLength)
		if isTextMode then
			self.textImagePrompt = trimmed
		else
			self.avatarGraphicPrompt = trimmed
		end
		count.Text = string.format("%d / %d", #prompt.Text, Config.Generation.PromptMaxLength)
	end)
	cursorY += 72

	-- The concept art closes the composer with one row: the Advanced Mode
	-- link on the left and the molten Create button on the right. Compact
	-- keeps the link on its own full-width row above, where the two would
	-- not fit side by side.
	local simpleSwitchInline = not showAllMethods and not self.compact
	if not showAllMethods and self.compact then
		local switchAdvanced = Factory.ImageButton(
			composer,
			"Advanced Mode: style & quality ✦",
			UDim2.new(1, -32, 0, 26),
			UDim2.fromOffset(16, cursorY),
			nil
		)
		self:_BindButton(switchAdvanced)
		switchAdvanced.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
		cursorY += 34
	end

	local safetyY = cursorY
	local buttonY = if self.compact or simpleSwitchInline then safetyY + 39 else safetyY
	composer.Size = UDim2.new(1, 0, 0, buttonY + 58)
	if simpleSwitchInline then
		local switchAdvanced = Factory.ImageButton(
			composer,
			"Advanced Mode: style & quality ✦",
			UDim2.fromOffset(300, 42),
			UDim2.fromOffset(16, buttonY),
			nil
		)
		switchAdvanced.TextSize = 12
		self:_BindButton(switchAdvanced)
		switchAdvanced.Activated:Connect(function()
			self:_UpdateSetting("simpleMode", false)
		end)
	end
	Factory.Label(
		composer,
		if isTextMode
			then "Roblox TextService + provider moderation · never becomes a 3D model or accessory"
			else "Your avatar is fetched automatically · Roblox TextService + provider moderation · never becomes a 3D model or accessory",
		if self.compact or simpleSwitchInline then UDim2.new(1, -32, 0, 34) else UDim2.new(1, -300, 0, 42),
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
	local graphicProductKey = if selectedQualityTier then selectedQualityTier.ProductKey else "ImagePreviewLow"
	local price = self.state.prices[graphicProductKey]
	local payWithTokens = self.paymentMethod == "TOKENS"
	local priceText = if payWithTokens
		then string.format("%d ad tokens", tokenPrice(price, graphicProductKey))
		else string.format("R$ %d", price)
	local actionText =
		string.format(if isTextMode then "Create image · %s" else "Create avatar graphic · %s", priceText)
	local generate = Factory.ImageButton(
		composer,
		actionText,
		if self.compact then UDim2.new(1, -32, 0, 42) else UDim2.new(0, 260, 0, 42),
		if self.compact then UDim2.new(0, 16, 0, buttonY) else UDim2.new(1, -276, 0, buttonY),
		"primary"
	)
	self:_BindButton(generate)
	generate.Activated:Connect(function()
		if isTextMode and #string.gsub(prompt.Text, "%s", "") == 0 then
			self:_Toast("error", "Describe what you want to see first.")
			return
		end
		generate.Active = false
		generate.Text = if isTextMode then "Painting…" else "Fetching your avatar…"
		task.spawn(function()
			local success, result
			if isTextMode then
				success, result = self:_Invoke(Network.Actions.CreateTextImage, {
					stylePreset = self.selectedStylePreset,
					imageQuality = self.selectedImageQuality,
					prompt = prompt.Text,
					paymentMethod = self.paymentMethod,
				})
			else
				success, result = self:_Invoke(Network.Actions.CreateAvatarGraphic, {
					avatarView = self.selectedAvatarView,
					stylePreset = self.selectedStylePreset,
					imageQuality = self.selectedImageQuality,
					prompt = prompt.Text,
					paymentMethod = self.paymentMethod,
				})
			end
			generate.Active = true
			generate.Text = actionText
			if success then
				local graphicAction = if isTextMode
					then Network.Actions.CreateTextImage
					else Network.Actions.CreateAvatarGraphic
				result = self:_GenerationResult(graphicAction, result)
				if result.usedRetryCredit then
					self:_Toast("success", "Retry credit applied. Your image is entering the queue.")
				elseif result.mocked then
					self:_Toast("success", "Studio mock purchase confirmed. Your image is entering the queue.")
				elseif result.tokensSpent then
					self.state.profile.tokens = result.tokens
					self.state.profile.bonusTokens = result.bonusTokens
					self.sounds:Play("Success")
					self:_Toast(
						"success",
						string.format("%d tokens spent. Your image is entering the queue.", result.tokensSpent)
					)
				else
					self.sounds:Play("PurchasePrompt")
					self:_Toast("success", "Purchase prompt opened. Generation begins only after Roblox confirms it.")
				end
			end
		end)
	end)

	local inFlightCount = 0
	for _, generationId in self.state.profile.generationOrder do
		local generation = self.state.profile.generations[generationId]
		if
			generation
			and (generation.method == "AVATAR_GRAPHIC" or generation.method == "TEXT_TO_IMAGE")
			and generation.stage ~= "SUCCEEDED"
		then
			inFlightCount += 1
			if inFlightCount >= 3 then
				break
			end
		end
	end
	if inFlightCount > 0 then
		local activityHeight = 49 + inFlightCount * 50 + 14
		local activity = Factory.ImageCard(rightStack, UDim2.new(1, 0, 0, activityHeight), nil, "GraphicActivity")
		activity.LayoutOrder = 2
		Factory.SectionBanner(activity, "In Progress")
		local y = 49
		local shown = 0
		for _, generationId in self.state.profile.generationOrder do
			if shown >= 3 then
				break
			end
			local generation = self.state.profile.generations[generationId]
			if generation and generation.method == "AVATAR_GRAPHIC" and generation.stage ~= "SUCCEEDED" then
				shown += 1
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
				local stageColor = if generation.stage == "FAILED" then Colors.Danger else Colors.Cyan
				local badge = Factory.New("Frame", {
					Size = UDim2.fromOffset(30, 30),
					Position = UDim2.fromOffset(7, 7),
					BackgroundColor3 = Colors.Cyan,
					BorderSizePixel = 0,
					Parent = row,
				})
				Factory.Corner(badge, 15)
				Factory.Gradient(badge, { Colors.Cyan, Color3.fromRGB(70, 170, 220) }, 135)
				Factory.Label(badge, "🖼", UDim2.fromScale(1, 1), {
					TextSize = 14,
					AlignX = Enum.TextXAlignment.Center,
					AlignY = Enum.TextYAlignment.Center,
				})
				Factory.Label(
					row,
					string.sub(generation.filteredPrompt or "Avatar graphic", 1, 40),
					UDim2.new(1, -108, 0, 16),
					{
						Position = UDim2.fromOffset(46, 4),
						Font = Theme.Fonts.Medium,
						TextSize = 12,
						Truncate = Enum.TextTruncate.AtEnd,
					}
				)
				Factory.Label(
					row,
					string.format("%d%%", math.floor(generation.progress or 0)),
					UDim2.fromOffset(46, 16),
					{
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -8, 0, 4),
						AlignX = Enum.TextXAlignment.Right,
						Font = Theme.Fonts.Black,
						Color = stageColor,
						TextSize = 12,
					}
				)
				Factory.Label(row, generation.stageText or generation.stage, UDim2.new(1, -58, 0, 14), {
					Position = UDim2.fromOffset(46, 22),
					Color = Colors.TextMuted,
					TextSize = 10,
					Truncate = Enum.TextTruncate.AtEnd,
				})
				local track = Factory.New("Frame", {
					Position = UDim2.fromOffset(46, 39),
					Size = UDim2.new(1, -58, 0, 3),
					BackgroundColor3 = Colors.PanelSoft,
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					Parent = row,
				})
				Factory.Corner(track, 2)
				Factory.New("Frame", {
					Size = UDim2.new(math.clamp((generation.progress or 0) / 100, 0, 1), 0, 1, 0),
					BackgroundColor3 = stageColor,
					BorderSizePixel = 0,
					Parent = track,
				})
				y += 50
			end
		end
	end

	-- The gallery becomes its own banner-tabbed panel in the rail, the way
	-- the concept art draws it, rather than a bare caption over a loose
	-- grid. Two columns there whatever the window: the rail is ~37% of the
	-- content width, so the page-wide gridColumns count would slice each
	-- card down to a sliver. Compact keeps the single stack and its own
	-- column count.
	local graphicCount = #(self.state.profile.graphicOrder or {})
	local gridColumns = if self.compact then self.gridColumns else 2
	local cardHeight = if showAllMethods then 460 else 310
	local galleryRows = math.max(1, math.ceil(graphicCount / gridColumns))
	local galleryCard = Factory.ImageCard(
		rightStack,
		UDim2.new(1, 0, 0, if graphicCount == 0 then 122 else 34 + galleryRows * (cardHeight + 12) + 4),
		nil,
		"GraphicsGallery"
	)
	galleryCard.LayoutOrder = 3
	Factory.SectionBanner(galleryCard, "Your Graphics")

	if graphicCount == 0 then
		Factory.Label(galleryCard, "No graphics yet. Create one above to see it here.", UDim2.new(1, -32, 0, 60), {
			Position = UDim2.fromOffset(16, 40),
			AlignX = Enum.TextXAlignment.Center,
			Color = Colors.TextMuted,
			Wrapped = true,
			TextSize = 13,
		})
		return
	end

	local gallery = Factory.New("Frame", {
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, galleryRows * (cardHeight + 12)),
		BackgroundTransparency = 1,
		Parent = galleryCard,
	})
	-- Simple Mode skips the title/description editor and the sharing/sales
	-- block per card (same "financial and metadata editing are Advanced"
	-- rule as My Studio/Discover/Avatar Lab) straight to the download link
	-- and Delete, so its shorter shared card height drops the same ~160px
	-- those two blocks would have cost -- cardHeight above.
	Factory.New("UIGridLayout", {
		-- +80 for the title/description editor inserted below the kind
		-- label; every card in the grid shares one CellSize, so this height
		-- covers both license branches even though only the shared content
		-- (link/delete) below the editor visually differs by license.
		CellSize = UDim2.new(1 / gridColumns, -12 * (gridColumns - 1) / gridColumns, 0, cardHeight),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gallery,
	})
	for index, graphicId in self.state.profile.graphicOrder do
		local graphic = self.state.profile.graphics[graphicId]
		if graphic then
			local card = Factory.ImageCard(gallery, UDim2.fromScale(1, 1), nil, "GraphicItem")
			card.LayoutOrder = index
			local previewSource = directImage(graphic.previewAssetId)
			local image = Factory.New("ImageLabel", {
				Size = UDim2.new(1, -20, 0, 132),
				Position = UDim2.fromOffset(10, 10),
				BackgroundColor3 = Colors.Ink,
				BorderSizePixel = 0,
				Image = previewSource,
				ScaleType = Enum.ScaleType.Crop,
				Parent = card,
			})
			Factory.Corner(image, 11)
			-- This gallery used to leave the entire 132px media area blank while
			-- Roblox processed/moderated a new Image asset. Give that state an
			-- explicit, self-clearing explanation just like model/detail previews
			-- already have, so a saved creation never reads as lost or broken.
			local previewState = Factory.New("Frame", {
				Name = "PreviewLoadingState",
				Size = UDim2.new(1, -20, 0, 58),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				BackgroundColor3 = Colors.Panel,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = image,
			})
			Factory.Corner(previewState, 10)
			Factory.Stroke(previewState, Colors.Cyan, 0.58, 1)
			local spinner = Factory.Label(previewState, "◌", UDim2.fromOffset(34, 34), {
				Position = UDim2.fromOffset(8, 12),
				AlignX = Enum.TextXAlignment.Center,
				AlignY = Enum.TextYAlignment.Center,
				Font = Theme.Fonts.Black,
				TextSize = 22,
				Color = Colors.Cyan,
				ZIndex = 4,
			})
			local previewHint = Factory.Label(
				previewState,
				if previewSource == ""
					then "Preview queued\nSaved safely — check again shortly"
					else "Loading preview…\nRoblox may be processing or moderating it",
				UDim2.new(1, -54, 1, -10),
				{
					Position = UDim2.fromOffset(48, 5),
					Color = Colors.Text,
					Font = Theme.Fonts.Medium,
					TextSize = 10,
					Wrapped = true,
					AlignY = Enum.TextYAlignment.Center,
					ZIndex = 4,
				}
			)
			if self.state.profile.settings.reduceMotion ~= true then
				TweenService:Create(
					spinner,
					TweenInfo.new(1.15, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
					{ Rotation = 360 }
				):Play()
			end
			if previewSource ~= "" then
				self:_WatchImageLoad(image, previewHint, nil, previewState)
			end
			Factory.Label(
				card,
				string.sub(graphic.filteredPrompt or "Graphic", 1, 60),
				UDim2.new(1, -20, 0, 28),
				{ Position = UDim2.fromOffset(10, 148), Font = Theme.Fonts.Medium, TextSize = 11, Wrapped = true }
			)
			local kindLabel = "Text prompt"
			if graphic.kind ~= "TEXT_TO_IMAGE" then
				kindLabel = "Bust"
				for _, view in Config.Generation.AvatarViews do
					if view.Id == graphic.avatarView then
						kindLabel = view.Label
						break
					end
				end
			end
			Factory.Label(card, kindLabel, UDim2.new(1, -20, 0, 14), {
				Position = UDim2.fromOffset(10, 178),
				Color = Colors.TextMuted,
				TextSize = 10,
			})
			-- Title/description editing and sharing/sales are both Advanced
			-- Mode only (same rule as My Studio/Discover/Avatar Lab) --
			-- Simple Mode goes straight from the kind label to the download
			-- link and Delete, hence the two different linkY/deleteY below.
			if showAllMethods then
				-- Never shown publicly for a private/personal copy (its
				-- visibility can never go public -- see the license branch
				-- below), but harmless to let the owner keep one anyway, and
				-- keeping this block unconditional means every card in the grid
				-- shares the same layout below it regardless of license.
				local titleBox =
					self:_TextBox(card, "Untitled graphic", UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 196), false)
				titleBox.Text = graphic.title or ""
				local descriptionBox = self:_TextBox(
					card,
					"Add a description…",
					UDim2.new(1, -20, 0, 40),
					UDim2.fromOffset(10, 228),
					true
				)
				descriptionBox.Text = graphic.description or ""
				local function saveGraphicDetails()
					task.spawn(function()
						self:_Invoke(Network.Actions.SetGraphicDetails, {
							graphicId = graphic.id,
							title = titleBox.Text,
							description = descriptionBox.Text,
						})
					end)
				end
				titleBox.FocusLost:Connect(saveGraphicDetails)
				descriptionBox.FocusLost:Connect(saveGraphicDetails)
				if graphic.license == "PERSONAL_COPY" then
					Factory.Label(card, "Personal copy · yours to keep, never resellable", UDim2.new(1, -20, 0, 60), {
						Position = UDim2.fromOffset(10, 276),
						Color = Colors.Gold,
						TextSize = 11,
						Wrapped = true,
						AlignY = Enum.TextYAlignment.Top,
					})
				else
					local visibility = Factory.ImageButton(
						card,
						if graphic.visibility == "PUBLIC" then "Private" else "Share",
						UDim2.new(0.48, -5, 0, 32),
						UDim2.fromOffset(10, 276),
						nil
					)
					self:_BindButton(visibility)
					visibility.Activated:Connect(function()
						task.spawn(function()
							local success, data = self:_Invoke(Network.Actions.SetGraphicVisibility, {
								graphicId = graphic.id,
								isPublic = graphic.visibility ~= "PUBLIC",
							})
							if success then
								self.state.profile.graphics[graphic.id] = data.graphic
								self:_RenderActivePage()
							end
						end)
					end)
					local priceBox = self:_TextBox(
						card,
						"R$ 10–500",
						UDim2.new(0.52, -5, 0, 32),
						UDim2.new(0.48, 5, 0, 276),
						false
					)
					priceBox.Text = tostring(graphic.listingPriceRobux or 50)
					priceBox.TextXAlignment = Enum.TextXAlignment.Center
					priceBox.FocusLost:Connect(function()
						priceBox.Text = tostring(math.clamp(math.floor(tonumber(priceBox.Text) or 50), 10, 500))
					end)
					local list = Factory.ImageButton(
						card,
						if graphic.isListed then "End listing" else "List for sale",
						UDim2.new(1, -20, 0, 32),
						UDim2.fromOffset(10, 312),
						"primary"
					)
					self:_BindButton(list)
					list.Activated:Connect(function()
						task.spawn(function()
							local success, data = self:_Invoke(Network.Actions.SetGraphicListing, {
								graphicId = graphic.id,
								isListed = not graphic.isListed,
								priceRobux = tonumber(priceBox.Text),
							})
							if success then
								self.state.profile.graphics[graphic.id] = data.graphic
								self:_RenderActivePage()
							end
						end)
					end)
				end
			end
			-- Roblox experiences cannot save a file to the player's device --
			-- there is no such API in the client sandbox, for any experience.
			-- This is the closest honest substitute: the backend already has
			-- the full-resolution PNG it generated, and serves it back with
			-- no auth required at GET /v1/graphics/{backendJobId}/image (see
			-- server.ts) specifically so this link works from a plain browser
			-- outside Roblox. TextEditable = false lets the player select and
			-- copy it (Ctrl+A, Ctrl+C) without being able to edit it.
			local linkLabelY = if showAllMethods then 350 else 200
			local linkBoxY = if showAllMethods then 363 else 213
			local hasLink = graphic.backendJobId ~= nil and graphic.backendJobId ~= ""
			Factory.Label(
				card,
				if hasLink then "FULL-RES DOWNLOAD LINK · COPY INTO BROWSER" else "LINK UNAVAILABLE (STUDIO MOCK)",
				UDim2.new(1, -20, 0, 12),
				{ Position = UDim2.fromOffset(10, linkLabelY), Color = Colors.TextMuted, TextSize = 8 }
			)
			local linkBox = Factory.New("TextBox", {
				Size = UDim2.new(1, -20, 0, 34),
				Position = UDim2.fromOffset(10, linkBoxY),
				BackgroundColor3 = Colors.Ink,
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Text = if hasLink
					then string.format("%s/v1/graphics/%s/image", Config.Backend.BaseUrl, graphic.backendJobId)
					else "Open this graphic from a real generation to get its link.",
				TextColor3 = Colors.Text,
				Font = Theme.Fonts.Regular,
				TextSize = 9,
				TextWrapped = true,
				TextEditable = hasLink,
				ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = card,
			})
			Factory.Corner(linkBox, 8)
			Factory.Padding(linkBox, 6, 4)
			local deleteY = if showAllMethods then 406 else 256
			local delete =
				Factory.ImageButton(card, "Delete", UDim2.new(1, -20, 0, 30), UDim2.fromOffset(10, deleteY), nil)
			self:_BindButton(delete)
			delete.Activated:Connect(function()
				delete.Active = false
				delete.Text = "Removing…"
				task.spawn(function()
					local success = self:_Invoke(Network.Actions.DeleteGraphic, { graphicId = graphicId })
					if success then
						self.state.profile.graphics[graphicId] = nil
						local orderIndex = table.find(self.state.profile.graphicOrder, graphicId)
						if orderIndex then
							table.remove(self.state.profile.graphicOrder, orderIndex)
						end
						self:_Toast("success", "Graphic deleted.")
						self:_RenderActivePage()
					elseif delete.Parent then
						delete.Active = true
						delete.Text = "Delete"
					end
				end)
			end)
		end
	end
end

-- Keeps the sidebar's own Simple/Advanced buttons (see _BuildChrome) in
-- sync with the real setting, regardless of which entry point last changed
-- it -- this one, a page's inline "Switch to Advanced Mode" link, or the
-- Settings page toggle.
function App:_RefreshModeToggle()
	if not self.modeButtons or not self.state then
		return
	end
	local simpleActive = self.state.profile.settings.simpleMode ~= false
	Factory.SwapDecal(self.modeButtons.simple, if simpleActive then "ButtonPrimary" else "ButtonDefault")
	Factory.SwapDecal(self.modeButtons.advanced, if simpleActive then "ButtonDefault" else "ButtonPrimary")
end

function App:_UpdateSetting(key: string, value: any)
	task.spawn(function()
		local success, data = self:_Invoke(Network.Actions.UpdateSettings, { [key] = value })
		if success then
			self.state.profile.settings = data.settings
			if key == "reduceMotion" then
				self:_SetAmbientMotion(data.settings.reduceMotion ~= true)
			end
			self:_RefreshModeToggle()
		end
		self:_RenderActivePage()
	end)
end

function App:_RenderSettings()
	self:_PageHeader(
		"Settings",
		"Simple/Advanced Create mode, accessibility, audio, what's equipped right now, and your achievements.",
		true
	)
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
	self:_TrackScroll(page, "Settings")
	Factory.ScalePadding(page, 0.012, 0.012)
	-- The concept art runs Settings as two even columns -- the three things
	-- you change on the left, the two things you look at on the right --
	-- rather than one tall stack. Compact collapses to that single stack,
	-- where a half-width Equipped/Achievements panel would be unreadable.
	-- The 22px row gap (not 14) leaves room for each panel's banner tab,
	-- which overhangs 12px above the card it titles.
	local columns = if self.compact
		then nil
		else Factory.New("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = page,
		})
	if columns then
		Factory.List(columns, Enum.FillDirection.Horizontal, 20)
	end
	local stack = Factory.New("Frame", {
		Size = if self.compact then UDim2.new(1, -8, 0, 0) else UDim2.new(0.5, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = if self.compact then page else columns,
	})
	Factory.List(stack, Enum.FillDirection.Vertical, 22)
	local rightStack = if self.compact
		then stack
		else Factory.New("Frame", {
			Size = UDim2.new(0.5, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = columns,
		})
	if not self.compact then
		Factory.List(rightStack, Enum.FillDirection.Vertical, 22)
	end

	local settings = self.state.profile.settings

	-- CREATE MODE ---------------------------------------------------------
	-- The single most consequential setting for Forge's actual audience
	-- (young creators): whether Create shows one method, a text box, and a
	-- few example ideas, or the full four-method art-direction toolkit.
	-- Also switchable right from Create itself (see _RenderCreate's
	-- "Switch to Advanced/Simple Mode" links); this card exists so it's
	-- somewhere a player -- or a parent -- would think to look for it, not
	-- only stumbled into mid-creation.
	local createMode = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 168), nil, "CreateMode")
	createMode.LayoutOrder = 0
	Factory.SectionBanner(createMode, "Create Mode")
	local simpleModeOn = settings.simpleMode ~= false
	Factory.Label(createMode, "Simple Mode", UDim2.new(1, -32, 0, 26), {
		Position = UDim2.fromOffset(16, 32),
		Font = Theme.Fonts.Black,
		TextSize = 17,
	})
	Factory.Label(
		createMode,
		"One way to make something, a text box, and a few ideas to tap. Turn it off to unlock every method, style, fit, pricing and sharing.",
		UDim2.new(1, -32, 0, 44),
		{
			Position = UDim2.fromOffset(16, 60),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)
	-- Two buttons, one lit -- the concept art states the current mode
	-- rather than asking the player to read a single button's label and
	-- work out whether it reports the state or the action.
	local simpleButton = Factory.ImageButton(
		createMode,
		if simpleModeOn then "Simple Mode · ON" else "Simple Mode",
		UDim2.new(0.5, -22, 0, 44),
		UDim2.fromOffset(16, 110),
		if simpleModeOn then "primary" else nil
	)
	local advancedButton = Factory.ImageButton(
		createMode,
		if simpleModeOn then "Advanced Mode" else "Advanced Mode · ON",
		UDim2.new(0.5, -22, 0, 44),
		UDim2.new(0.5, 6, 0, 110),
		if simpleModeOn then nil else "primary"
	)
	self:_BindButton(simpleButton)
	self:_BindButton(advancedButton)
	simpleButton.Activated:Connect(function()
		if simpleModeOn then
			return
		end
		-- Turning Simple Mode ON: Create's Priority Pass toggle is about to
		-- disappear -- if it was left on, the next generation would
		-- otherwise silently spend a pass with no visible way left to turn
		-- it back off.
		self.usePriority = false
		self:_UpdateSetting("simpleMode", true)
	end)
	advancedButton.Activated:Connect(function()
		if not simpleModeOn then
			return
		end
		self:_UpdateSetting("simpleMode", false)
	end)

	-- ACCESSIBILITY -----------------------------------------------------
	local keyboardNoteHeight = if self.compact then 60 else 44
	local accessibility = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 232 + keyboardNoteHeight), nil, "Accessibility")
	accessibility.LayoutOrder = 1
	Factory.SectionBanner(accessibility, "Accessibility")
	-- One row per option: what it is, what it does, and the concept art's
	-- gold switch showing (and setting) its state -- not a full-width
	-- button whose own label has to double as the readout.
	local function toggleRow(title: string, description: string, on: boolean, y: number, onFlip: (boolean) -> ())
		Factory.Label(accessibility, title, UDim2.new(1, -140, 0, 22), {
			Position = UDim2.fromOffset(16, y),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
		})
		Factory.Label(accessibility, description, UDim2.new(1, -140, 0, 20), {
			Position = UDim2.fromOffset(16, y + 22),
			Color = Colors.TextMuted,
			TextSize = 11,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		local switch = Factory.Switch(accessibility, on, UDim2.new(1, -108, 0, y + 10))
		self:_BindButton(switch)
		switch.Activated:Connect(function()
			onFlip(not on)
		end)
	end
	toggleRow(
		"Reduce motion",
		"Turns off pulses, drifting embers and sweeps.",
		settings.reduceMotion == true,
		36,
		function(enabled)
			self:_UpdateSetting("reduceMotion", enabled)
		end
	)
	toggleRow(
		"High contrast",
		"Darker panels, brighter text and borders.",
		settings.highContrast == true,
		96,
		function(enabled)
			self:_SetHighContrast(enabled)
			self:_UpdateSetting("highContrast", enabled)
		end
	)

	-- Interface size: a real slider, as the concept art draws it, over the
	-- same 0.8-1.4 range the server accepts (see Main.server's
	-- UpdateSettings validation). The scale is applied live while dragging
	-- and only persisted on release -- _UpdateSetting re-renders the page,
	-- which would destroy the slider mid-drag.
	local scaleMinimum, scaleMaximum, scaleStep = 0.8, 1.4, 0.05
	Factory.Label(accessibility, "Interface size", UDim2.new(1, -32, 0, 22), {
		Position = UDim2.fromOffset(16, 156),
		Font = Theme.Fonts.Bold,
		TextSize = 13,
	})
	local scaleTrack = Factory.New("TextButton", {
		Position = UDim2.new(0.42, 0, 0, 162),
		Size = UDim2.new(0.58, -16, 0, 16),
		BackgroundColor3 = Colors.Ink,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = accessibility,
	})
	Factory.Corner(scaleTrack, 8)
	Factory.Stroke(scaleTrack, Colors.Gold, 0.5)
	local scaleFill = Factory.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		Parent = scaleTrack,
	})
	Factory.Corner(scaleFill, 8)
	local scaleKnob = Factory.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Colors.Gold,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = scaleTrack,
	})
	Factory.Corner(scaleKnob, 11)
	Factory.Gradient(scaleKnob, { Color3.fromRGB(255, 243, 196), Colors.Gold }, 90)
	Factory.Stroke(scaleKnob, Color3.fromRGB(255, 243, 196), 0.35)
	local scaleValueLabel = Factory.Label(accessibility, "", UDim2.new(1, -32, 0, 18), {
		Position = UDim2.fromOffset(16, 180),
		Color = Colors.TextMuted,
		TextSize = 11,
	})
	local currentScale = math.clamp(tonumber(settings.uiScale) or 1, scaleMinimum, scaleMaximum)
	local function showScale(value: number)
		local alpha = (value - scaleMinimum) / (scaleMaximum - scaleMinimum)
		scaleFill.Size = UDim2.fromScale(alpha, 1)
		scaleKnob.Position = UDim2.fromScale(alpha, 0.5)
		scaleValueLabel.Text = string.format("%d%%", math.floor(value * 100 + 0.5))
	end
	local function applyScale(value: number)
		self.uiScaleInstance.Scale = value
		if self.arcadeUiScale then
			self.arcadeUiScale.Scale = value
		end
		if self.runwayUiScale then
			self.runwayUiScale.Scale = value
		end
	end
	local function scaleFromPointer(pointerX: number): number
		if scaleTrack.AbsoluteSize.X <= 0 then
			return currentScale
		end
		local alpha = math.clamp((pointerX - scaleTrack.AbsolutePosition.X) / scaleTrack.AbsoluteSize.X, 0, 1)
		local steps = math.floor(((scaleMaximum - scaleMinimum) * alpha) / scaleStep + 0.5)
		return math.clamp(scaleMinimum + steps * scaleStep, scaleMinimum, scaleMaximum)
	end
	showScale(currentScale)
	local scaleDragging = false
	local scaleDragTouch = nil :: InputObject?
	scaleTrack.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			scaleDragging = true
			scaleDragTouch = if input.UserInputType == Enum.UserInputType.Touch then input else nil
			currentScale = scaleFromPointer(input.Position.X)
			showScale(currentScale)
			applyScale(currentScale)
		end
	end)
	table.insert(
		self.pageConnections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if
				scaleDragging
				and (input.UserInputType == Enum.UserInputType.MouseMovement or input == scaleDragTouch)
			then
				currentScale = scaleFromPointer(input.Position.X)
				showScale(currentScale)
				applyScale(currentScale)
			end
		end)
	)
	table.insert(
		self.pageConnections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if not scaleDragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input == scaleDragTouch then
				scaleDragging = false
				scaleDragTouch = nil
				self:_UpdateSetting("uiScale", currentScale)
			end
		end)
	)
	Factory.Label(
		accessibility,
		"Scales every control and label together, including touch and click targets. Keyboard & gamepad: press Tab, or a gamepad's Y button, any time to jump into the navigation rail and move through the studio with arrows or the D-pad.",
		UDim2.new(1, -32, 0, keyboardNoteHeight),
		{
			Position = UDim2.fromOffset(16, 208),
			Color = Colors.TextMuted,
			TextSize = 11,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)

	-- AUDIO ---------------------------------------------------------------
	local audio = Factory.ImageCard(stack, UDim2.new(1, 0, 0, 104), nil, "Audio")
	audio.LayoutOrder = 2
	Factory.SectionBanner(audio, "Audio")
	Factory.Label(audio, "Sound effects", UDim2.new(1, -140, 0, 22), {
		Position = UDim2.fromOffset(16, 38),
		Font = Theme.Fonts.Bold,
		TextSize = 13,
	})
	Factory.Label(audio, "Taps, forge chimes and reward stings.", UDim2.new(1, -140, 0, 20), {
		Position = UDim2.fromOffset(16, 60),
		Color = Colors.TextMuted,
		TextSize = 11,
		Truncate = Enum.TextTruncate.AtEnd,
	})
	self:_BuildSoundButton(audio, UDim2.new(1, -108, 0, 48))

	-- INVITE FRIENDS --------------------------------------------------------
	local invite = Factory.ImageCard(stack, UDim2.new(1, 0, 0, if self.compact then 150 else 104), nil, "InviteFriends")
	invite.LayoutOrder = 3
	Factory.SectionBanner(invite, "Grow the Studio")
	Factory.Label(
		invite,
		"Send a Roblox invite to a friend for a small one-time Forge Token reward.",
		if self.compact then UDim2.new(1, -32, 0, 40) else UDim2.new(1, -240, 0, 44),
		{
			Position = UDim2.fromOffset(16, 38),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			AlignY = Enum.TextYAlignment.Top,
		}
	)
	local inviteButton = Factory.ImageButton(
		invite,
		"Invite a friend",
		if self.compact then UDim2.new(1, -32, 0, 42) else UDim2.fromOffset(190, 42),
		if self.compact then UDim2.fromOffset(16, 92) else UDim2.new(1, -206, 0, 40),
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
		Factory.ImageCard(rightStack, UDim2.new(1, 0, 0, 46 + math.max(1, #equippedIds) * 62), nil, "Loadout")
	loadout.LayoutOrder = 4
	Factory.SectionBanner(loadout, string.format("Equipped Now · %d", #equippedIds))
	if #equippedIds == 0 then
		Factory.Label(loadout, "Nothing equipped yet. Equip an item from My Studio.", UDim2.new(1, -32, 0, 40), {
			Position = UDim2.fromOffset(16, 42),
			Color = Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
		})
	else
		local y = 38
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
				Factory.Stroke(row, Colors.Gold, 0.55)
				local image = Factory.New("ImageLabel", {
					Size = UDim2.fromOffset(44, 44),
					Position = UDim2.fromOffset(6, 6),
					BackgroundColor3 = Colors.Panel,
					BorderSizePixel = 0,
					Image = modelPreviewImage(item),
					ScaleType = Enum.ScaleType.Crop,
					Parent = row,
				})
				Factory.Corner(image, 8)
				Factory.Stroke(image, Colors.Gold, 0.45)
				Factory.Label(row, item.name, UDim2.new(1, -180, 0, 24), {
					Position = UDim2.fromOffset(58, 8),
					Font = Theme.Fonts.Bold,
					TextSize = 13,
					Truncate = Enum.TextTruncate.AtEnd,
				})
				Factory.Label(row, ACCESSORY_LABELS[item.fit.accessoryType] or "Accessory", UDim2.new(1, -180, 0, 20), {
					Position = UDim2.fromOffset(58, 30),
					Color = Colors.TextMuted,
					TextSize = 11,
				})
				-- "Remove", per the concept art -- "Unequip" is Studio's word
				-- for the same action, next to the fit controls that make it
				-- mean something specific.
				local unequip =
					Factory.ImageButton(row, "Remove", UDim2.fromOffset(104, 38), UDim2.new(1, -112, 0, 9), nil)
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
							self.avatarPreviewDirty = true
							self:_Toast("success", "Unequipped.")
							self:_RenderActivePage()
							return
						end
						if unequip.Parent then
							unequip.Active = true
							unequip.Text = "Remove"
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
	-- Circular medallions in a wide grid, the way the concept art draws
	-- them, rather than a two-column list of text rows. Each keeps its
	-- description line, which the art has no room for and which is the only
	-- thing on the page that says how a locked one is earned.
	local achievementColumns = if self.compact then 2 else 4
	local achievementRows = math.ceil(#Achievements.List / achievementColumns)
	local achievementTileHeight = 122
	local achievements = Factory.ImageCard(
		rightStack,
		UDim2.new(1, 0, 0, 46 + achievementRows * (achievementTileHeight + 8)),
		nil,
		"Achievements"
	)
	achievements.LayoutOrder = 5
	Factory.SectionBanner(achievements, string.format("Achievements · %d/%d", unlockedCount, #Achievements.List))
	local achievementGrid = Factory.New("Frame", {
		Position = UDim2.fromOffset(16, 38),
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
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = achievementGrid,
		})
		local medallion = Factory.New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.fromOffset(54, 54),
			BackgroundColor3 = if unlocked then Colors.Ink else Colors.Panel,
			BackgroundTransparency = if unlocked then 0 else 0.35,
			BorderSizePixel = 0,
			Parent = tile,
		})
		Factory.Corner(medallion, 27)
		Factory.Stroke(medallion, if unlocked then Colors.Gold else Colors.Line, if unlocked then 0.1 else 0.55, 2)
		if unlocked then
			Factory.Gradient(medallion, { Color3.fromRGB(58, 40, 96), Colors.Ink }, 90)
		end
		Factory.Label(medallion, if unlocked then "✦" else "🔒", UDim2.fromScale(1, 1), {
			AlignX = Enum.TextXAlignment.Center,
			AlignY = Enum.TextYAlignment.Center,
			Font = Theme.Fonts.Black,
			TextSize = if unlocked then 24 else 18,
			Color = if unlocked then Colors.Gold else Colors.TextMuted,
		})
		Factory.Label(tile, definition.name, UDim2.new(1, 0, 0, 18), {
			Position = UDim2.fromOffset(0, 60),
			AlignX = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = if unlocked then Colors.Text else Colors.TextMuted,
			Truncate = Enum.TextTruncate.AtEnd,
		})
		Factory.Label(
			tile,
			string.format("%s · +%d", definition.description, definition.tokens),
			UDim2.new(1, -6, 0, 40),
			{
				Position = UDim2.fromOffset(3, 78),
				AlignX = Enum.TextXAlignment.Center,
				Color = if unlocked then Colors.Gold else Colors.TextMuted,
				TextSize = 9,
				Wrapped = true,
				AlignY = Enum.TextYAlignment.Top,
			}
		)
	end
end

-- A first-timer no longer lands on the launcher screen at all (Bootstrap
-- opens Studio straight to Create instead -- see the Bootstrap success
-- handler), but they still reach these four buttons the moment they close
-- Studio to look around, and nothing there marks Forge Studio as the one
-- that matters over Forge Runway / Arcade / Tokens for AFK. This dims the
-- other three and puts a slow pulsing glow on Forge Studio's own outline
-- for anyone who's never finished a generation, without touching any
-- button's size or position -- every launcher's vertical spacing
-- (buildLauncher's bottomOffset math) assumes today's exact footprints.
function App:_ApplyLauncherEmphasis()
	local hasCreatedBefore = (self.state.profile.stats.generationsCompleted or 0) > 0
	if hasCreatedBefore then
		return
	end
	for _, secondaryLauncher in { self.runwayLauncher, self.arcadeLauncher, self.afkLauncher } do
		secondaryLauncher.BackgroundTransparency = 0.35
		local stroke = secondaryLauncher:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.75
		end
		for _, child in secondaryLauncher:GetChildren() do
			if child:IsA("TextLabel") then
				child.TextTransparency = 0.35
			end
		end
	end
	local primaryStroke = self.launcher:FindFirstChildOfClass("UIStroke")
	if not primaryStroke then
		return
	end
	primaryStroke.Thickness = 2.5
	primaryStroke.Color = Colors.Cyan
	if self.state.profile.settings.reduceMotion == true then
		primaryStroke.Transparency = 0.1
		return
	end
	local pulse = TweenService:Create(
		primaryStroke,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.1 }
	)
	pulse:Play()
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
	local modal = Factory.ImageCard(overlay, UDim2.new(1, -32, 0, 400), UDim2.fromScale(0.5, 0.5), "PlusModal")
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
		Factory.ImageButton(modal, "View Roblox Plus", UDim2.new(0.5, -24, 0, 44), UDim2.fromOffset(16, 316), "mint")
	local closeButton =
		Factory.ImageButton(modal, "Maybe later", UDim2.new(0.5, -24, 0, 44), UDim2.new(0.5, 8, 0, 316), nil)
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
	local modal = Factory.ImageCard(overlay, UDim2.new(1, -32, 0, 480), UDim2.fromScale(0.5, 0.5), "LeaderboardModal")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ZIndex = 211
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(440, 480),
		Parent = modal,
	})
	local topCreatorsPill = Factory.ImagePill(modal, "TOP CREATORS", Colors.Gold, 130)
	topCreatorsPill.Position = UDim2.fromOffset(16, 16)
	-- Every other element in this modal explicitly escalates ZIndex past the
	-- overlay/modal's own (210/211) since this app's ScreenGui compares
	-- ZIndex globally, not just among siblings -- this pill was left at
	-- Factory.Pill's un-overridden default of 1, so it was painting behind
	-- the Discover page's own cards (ZIndex >= 1) showing through the
	-- semi-transparent backdrop behind the modal instead of on top of it.
	topCreatorsPill.ZIndex = 212
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
	local closeButton = Factory.ImageButton(modal, "×", UDim2.fromOffset(34, 34), UDim2.new(1, -50, 0, 14), nil)
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

-- Shared "blown up" detail overlay for a Discover-tab item or graphic --
-- built from a normalized descriptor rather than the raw item/graphic
-- record so one function covers both content types. Their card-building
-- loops differ (an item has a style/detail readout, a graphic doesn't; the
-- purchase and like/favorite actions are different Network.Actions), but
-- everything laid out here -- preview, title, description, like/favorite,
-- buy, tip -- is identical in shape once resolved to a content id/owner.
--
-- descriptor: {
--   kind: "ITEM" | "GRAPHIC", id: string, ownerUserId: number, ownerName: string,
--   title: string, meta: string, description: string?, imageId: number?,
--   isListed: boolean, listingPriceRobux: number?,
--   likes: number, favorites: number, viewerLiked: boolean, viewerFavorited: boolean,
--   refresh: () -> (),
-- }
function App:_ShowContentDetail(descriptor: { [string]: any })
	local ZBASE = 150
	local overlay = Factory.New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = ZBASE,
		Parent = self.gui,
	})
	local isOwnContent = descriptor.ownerUserId == Players.LocalPlayer.UserId
	local showTip = not isOwnContent
	local modalHeight = if showTip then 606 else 522
	local modal =
		Factory.ImageCard(overlay, UDim2.new(1, -32, 0, modalHeight), UDim2.fromScale(0.5, 0.5), "ContentDetail")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.ClipsDescendants = false
	modal.ZIndex = ZBASE + 1
	Factory.New("UISizeConstraint", {
		MaxSize = Vector2.new(460, modalHeight + 60),
		Parent = modal,
	})

	-- Soft accent glow behind the modal, the same "spotlight" trick Plus's
	-- gold badge glow uses -- violet here to read as the app's own brand
	-- accent rather than borrowing Plus's upsell gold.
	local glow = Factory.Blob(modal, 340, UDim2.new(0.5, 0, 0, 40), Colors.Violet, 0.9)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.ZIndex = ZBASE

	-- Top-left instead of top-right (and above the preview image's own
	-- ZIndex, since it now sits over that image's corner rather than beside
	-- it) per the user's request to move this one specifically.
	local closeButton = Factory.ImageButton(modal, "×", UDim2.fromOffset(34, 34), UDim2.fromOffset(14, 14), nil)
	closeButton.ZIndex = ZBASE + 4
	self:_BindButton(closeButton)
	closeButton.Activated:Connect(function()
		self.sounds:Play("PanelClose")
		overlay:Destroy()
	end)

	local previewFrame = Factory.New("Frame", {
		Name = "Preview",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 0, 230),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = ZBASE + 2,
		Parent = modal,
	})
	Factory.Corner(previewFrame, 14)
	local previewImage = Factory.New("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = descriptor.previewImage or directImage(descriptor.imageId),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = ZBASE + 3,
		Parent = previewFrame,
	})
	if descriptor.kind == "ITEM" then
		local previewHint =
			Factory.Label(previewFrame, "Preview processing/moderating on Roblox…", UDim2.new(1, -24, 0, 38), {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 12, 1, -12),
				AlignX = Enum.TextXAlignment.Center,
				Color = Colors.Text,
				TextSize = 11,
				Wrapped = true,
				ZIndex = ZBASE + 4,
			})
		previewHint.BackgroundColor3 = Colors.Ink
		previewHint.BackgroundTransparency = 0.12
		Factory.Corner(previewHint, 8)
		self:_WatchImageLoad(previewImage, previewHint, thumbnail(descriptor.modelAssetId, 420))
	end
	if descriptor.isListed then
		local pricePill =
			Factory.ImagePill(modal, string.format("R$ %d", descriptor.listingPriceRobux), Colors.Mint, 76)
		pricePill.Position = UDim2.new(1, -90, 0, 24)
		pricePill.ZIndex = ZBASE + 3
	end

	Factory.Label(modal, tostring(descriptor.title), UDim2.new(1, -28, 0, 26), {
		Position = UDim2.fromOffset(14, 254),
		Font = Theme.Fonts.Black,
		TextSize = 19,
		Truncate = Enum.TextTruncate.AtEnd,
		ZIndex = ZBASE + 2,
	})
	local bylineText = string.format("by @%s", tostring(descriptor.ownerName))
	if type(descriptor.meta) == "string" and descriptor.meta ~= "" then
		bylineText = bylineText .. " · " .. descriptor.meta
	end
	Factory.Label(modal, bylineText, UDim2.new(1, -28, 0, 16), {
		Position = UDim2.fromOffset(14, 282),
		Color = Colors.TextMuted,
		TextSize = 11,
		Truncate = Enum.TextTruncate.AtEnd,
		ZIndex = ZBASE + 2,
	})
	local hasDescription = type(descriptor.description) == "string" and descriptor.description ~= ""
	Factory.Label(
		modal,
		if hasDescription then descriptor.description else "No description yet.",
		UDim2.new(1, -28, 0, 70),
		{
			Position = UDim2.fromOffset(14, 302),
			Color = if hasDescription then Colors.Text else Colors.TextMuted,
			TextSize = 12,
			Wrapped = true,
			Truncate = Enum.TextTruncate.AtEnd,
			AlignY = Enum.TextYAlignment.Top,
			ZIndex = ZBASE + 2,
		}
	)

	Factory.New("Frame", {
		Position = UDim2.fromOffset(14, 380),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = Colors.Line,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = ZBASE + 2,
		Parent = modal,
	})

	local likeAction = if descriptor.kind == "ITEM"
		then Network.Actions.ToggleLike
		else Network.Actions.ToggleGraphicLike
	local favoriteAction = if descriptor.kind == "ITEM"
		then Network.Actions.ToggleFavorite
		else Network.Actions.ToggleGraphicFavorite
	local idField = if descriptor.kind == "ITEM" then "itemId" else "graphicId"

	local like = Factory.ImageButton(
		modal,
		string.format("%s %s", if descriptor.viewerLiked then "♥" else "♡", formatNumber(descriptor.likes)),
		UDim2.new(0.5, -18, 0, 36),
		UDim2.fromOffset(14, 392),
		nil
	)
	like.ZIndex = ZBASE + 2
	local favorite = Factory.ImageButton(
		modal,
		string.format("%s %s", if descriptor.viewerFavorited then "★" else "☆", formatNumber(descriptor.favorites)),
		UDim2.new(0.5, -18, 0, 36),
		UDim2.new(0.5, 4, 0, 392),
		nil
	)
	favorite.ZIndex = ZBASE + 2
	self:_BindButton(like)
	self:_BindButton(favorite)
	like.Activated:Connect(function()
		task.spawn(function()
			local success = self:_Invoke(likeAction, { [idField] = descriptor.id })
			if success then
				self.sounds:Play("Like")
				descriptor.viewerLiked = not descriptor.viewerLiked
				descriptor.likes += if descriptor.viewerLiked then 1 else -1
				if like.Parent then
					like.Text = string.format(
						"%s %s",
						if descriptor.viewerLiked then "♥" else "♡",
						formatNumber(descriptor.likes)
					)
				end
				if descriptor.refresh then
					descriptor.refresh()
				end
			end
		end)
	end)
	favorite.Activated:Connect(function()
		task.spawn(function()
			local success = self:_Invoke(favoriteAction, { [idField] = descriptor.id })
			if success then
				descriptor.viewerFavorited = not descriptor.viewerFavorited
				descriptor.favorites += if descriptor.viewerFavorited then 1 else -1
				if favorite.Parent then
					favorite.Text = string.format(
						"%s %s",
						if descriptor.viewerFavorited then "★" else "☆",
						formatNumber(descriptor.favorites)
					)
				end
				if descriptor.refresh then
					descriptor.refresh()
				end
			end
		end)
	end)

	if descriptor.isListed and not isOwnContent then
		local buy = Factory.ImageButton(
			modal,
			string.format("Buy copy · R$ %d", descriptor.listingPriceRobux),
			UDim2.new(1, -28, 0, 40),
			UDim2.fromOffset(14, 436),
			"mint"
		)
		buy.ZIndex = ZBASE + 2
		self:_BindButton(buy)
		buy.Activated:Connect(function()
			buy.Active = false
			buy.Text = "Checking listing…"
			task.spawn(function()
				local purchaseAction = if descriptor.kind == "ITEM"
					then Network.Actions.BeginMarketplacePurchase
					else Network.Actions.BeginGraphicPurchase
				local success, errorCode = self:_Invoke(purchaseAction, { [idField] = descriptor.id })
				if success then
					self.sounds:Play("PurchasePrompt")
					self:_Toast("success", "Confirm the verified creator transfer in Roblox.")
				elseif errorCode == "PLUS_REQUIRED" then
					self:_ShowPlus()
				elseif errorCode == "LISTING_UNAVAILABLE" and descriptor.refresh then
					descriptor.refresh()
				end
				if buy.Parent then
					buy.Active = true
					buy.Text = string.format("Buy copy · R$ %d", descriptor.listingPriceRobux)
				end
			end)
		end)
	elseif not isOwnContent then
		Factory.Label(modal, "Not currently listed for sale.", UDim2.new(1, -28, 0, 20), {
			Position = UDim2.fromOffset(14, 446),
			Color = Colors.TextMuted,
			TextSize = 12,
			AlignX = Enum.TextXAlignment.Center,
			ZIndex = ZBASE + 2,
		})
	end

	if showTip then
		Factory.Label(modal, "💛  TIP THE CREATOR", UDim2.new(1, -28, 0, 18), {
			Position = UDim2.fromOffset(14, 490),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			Color = Colors.Gold,
			ZIndex = ZBASE + 2,
		})
		local tipRow = Factory.New("Frame", {
			Position = UDim2.fromOffset(14, 512),
			Size = UDim2.new(1, -28, 0, 40),
			BackgroundTransparency = 1,
			ZIndex = ZBASE + 2,
			Parent = modal,
		})
		Factory.List(tipRow, Enum.FillDirection.Horizontal, 8)
		local tierButtons: { TextButton } = {}
		for _, amount in Config.Marketplace.TipTiers do
			local tier = Factory.ImageButton(tipRow, string.format("R$ %d", amount), UDim2.fromOffset(84, 40), nil, nil)
			tier.ZIndex = ZBASE + 2
			self:_BindButton(tier)
			table.insert(tierButtons, tier)
			tier.Activated:Connect(function()
				for _, sibling in tierButtons do
					sibling.Active = false
				end
				local originalText = tier.Text
				tier.Text = "…"
				task.spawn(function()
					local success, errorCode = self:_Invoke(Network.Actions.BeginTip, {
						contentType = descriptor.kind,
						contentId = descriptor.id,
						amount = amount,
					})
					if success then
						self.sounds:Play("PurchasePrompt")
						self:_Toast("success", "Confirm the tip in Roblox.")
					elseif errorCode == "PLUS_REQUIRED" then
						self:_ShowPlus()
					end
					if tier.Parent then
						tier.Text = originalText
					end
					for _, sibling in tierButtons do
						if sibling.Parent then
							sibling.Active = true
						end
					end
				end)
			end)
		end
		Factory.Label(modal, "Requires Roblox Plus. Sends Robux straight to the creator.", UDim2.new(1, -28, 0, 16), {
			Position = UDim2.fromOffset(14, 558),
			Color = Colors.TextMuted,
			TextSize = 10,
			AlignX = Enum.TextXAlignment.Center,
			ZIndex = ZBASE + 2,
		})
	end

	self:_AnimateModalIn(overlay, modal)
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
