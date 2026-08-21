--!strict

local Network = {}

Network.FolderName = "ForgeUGCRemotes"
Network.RequestName = "Request"
Network.PushName = "Push"

Network.Actions = table.freeze({
	Bootstrap = "Bootstrap",
	CreateGeneration = "CreateGeneration",
	ConvertImage = "ConvertImage",
	BuyPriorityPass = "BuyPriorityPass",
	GetGeneration = "GetGeneration",
	SaveFit = "SaveFit",
	EquipItem = "EquipItem",
	PublishItem = "PublishItem",
	SetVisibility = "SetVisibility",
	SetListing = "SetListing",
	GetMarketplace = "GetMarketplace",
	ToggleLike = "ToggleLike",
	ToggleFavorite = "ToggleFavorite",
	BeginMarketplacePurchase = "BeginMarketplacePurchase",
	RequestPrivateModel = "RequestPrivateModel",
	TryOnCommunityItem = "TryOnCommunityItem",
	PromptPlus = "PromptPlus",
	TryCatalogAsset = "TryCatalogAsset",
	ResetAvatar = "ResetAvatar",
	UpdateSettings = "UpdateSettings",
	CompleteOnboarding = "CompleteOnboarding",
	Track = "Track",
})

Network.PushEvents = table.freeze({
	Profile = "Profile",
	Generation = "Generation",
	Item = "Item",
	Toast = "Toast",
	Transfer = "Transfer",
})

return table.freeze(Network)
