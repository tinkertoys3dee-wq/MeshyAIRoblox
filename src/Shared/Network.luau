--!strict

local Network = {}

Network.FolderName = "ForgeUGCRemotes"
Network.RequestName = "Request"
Network.PushName = "Push"

Network.Actions = table.freeze({
	Bootstrap = "Bootstrap",
	CreateGeneration = "CreateGeneration",
	CreateUploadedImage = "CreateUploadedImage",
	CreateFromAvatar = "CreateFromAvatar",
	ConvertImage = "ConvertImage",
	PromptCustomImagePass = "PromptCustomImagePass",
	BuyPriorityPass = "BuyPriorityPass",
	GetGeneration = "GetGeneration",
	SaveFit = "SaveFit",
	ResetFitToSuggested = "ResetFitToSuggested",
	SaveFitPreset = "SaveFitPreset",
	DeleteFitPreset = "DeleteFitPreset",
	EquipItem = "EquipItem",
	UnequipItem = "UnequipItem",
	PublishItem = "PublishItem",
	SetVisibility = "SetVisibility",
	SetListing = "SetListing",
	GetMarketplace = "GetMarketplace",
	GetLeaderboard = "GetLeaderboard",
	ToggleLike = "ToggleLike",
	ToggleFavorite = "ToggleFavorite",
	BeginMarketplacePurchase = "BeginMarketplacePurchase",
	RequestPrivateModel = "RequestPrivateModel",
	TryOnCommunityItem = "TryOnCommunityItem",
	PromptPlus = "PromptPlus",
	TryCatalogAsset = "TryCatalogAsset",
	UntryCatalogAsset = "UntryCatalogAsset",
	ResetAvatar = "ResetAvatar",
	UpdateSettings = "UpdateSettings",
	CompleteOnboarding = "CompleteOnboarding",
	Track = "Track",
	RequestRewardedAd = "RequestRewardedAd",
	BuyTokens = "BuyTokens",
	ReportInviteSent = "ReportInviteSent",
	SubmitArcadeScore = "SubmitArcadeScore",
	GetArcadeLeaderboard = "GetArcadeLeaderboard",
	GetFriendArcadeLeaderboard = "GetFriendArcadeLeaderboard",
})

Network.PushEvents = table.freeze({
	Profile = "Profile",
	Generation = "Generation",
	Item = "Item",
	Toast = "Toast",
	Transfer = "Transfer",
	Entitlements = "Entitlements",
	Quests = "Quests",
})

return table.freeze(Network)
