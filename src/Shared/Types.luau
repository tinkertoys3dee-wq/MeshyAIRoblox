--!strict

export type VectorRecord = { x: number, y: number, z: number }

export type FitTransform = {
	position: VectorRecord,
	rotation: VectorRecord,
	scale: VectorRecord,
	accessoryType: string,
}

export type ItemLicense = "ORIGINAL" | "PERSONAL_COPY"
export type Visibility = "PRIVATE" | "PUBLIC"
export type GenerationMethod =
	"TEXT_TO_3D"
	| "IMAGE_PREVIEW"
	| "IMAGE_UPLOAD"
	| "IMAGE_TO_3D"
	| "AVATAR_TO_3D"
	| "AVATAR_GRAPHIC"

export type ItemRecord = {
	id: string,
	ownerUserId: number,
	originalOwnerUserId: number,
	sourceItemId: string?,
	license: ItemLicense,
	canList: boolean,
	canPublish: boolean,
	name: string,
	filteredPrompt: string,
	method: GenerationMethod,
	stylePreset: string,
	detailLevel: string,
	status: string,
	createdAt: number,
	updatedAt: number,
	backendJobId: string?,
	modelAssetId: number?,
	previewAssetId: number?,
	thumbnailAssetId: number?,
	fit: FitTransform,
	visibility: Visibility,
	isListed: boolean,
	listingPriceRobux: number?,
	likes: number,
	favorites: number,
	views: number,
	publishedAssetId: number?,
}

export type GenerationRecord = {
	id: string,
	method: GenerationMethod,
	productKey: string,
	priority: boolean,
	stage: string,
	stageText: string,
	progress: number,
	filteredPrompt: string,
	-- Absent for AVATAR_GRAPHIC: it produces a standalone image, never an
	-- accessory, so it has no accessory slot to record.
	accessoryType: string?,
	stylePreset: string,
	detailLevel: string,
	imageQuality: string?,
	sourceImageAssetId: number?,
	avatarView: string?,
	backendJobId: string?,
	sourceBackendJobId: string?,
	previewAssetId: number?,
	itemId: string?,
	-- Set only for AVATAR_GRAPHIC once its PlayerProfile.graphics entry
	-- exists -- the graphic equivalent of itemId above.
	graphicId: string?,
	errorCode: string?,
	failureHandled: boolean?,
	createdAt: number,
	updatedAt: number,
}

-- A standalone stylized image generated from the player's own avatar --
-- never an accessory, never converted to 3D. Kept in its own gallery
-- (PlayerProfile.graphics) rather than PlayerProfile.items since it has none
-- of an ItemRecord's accessory-specific concepts (fit, license, publishing).
export type GraphicRecord = {
	id: string,
	ownerUserId: number,
	filteredPrompt: string,
	stylePreset: string,
	avatarView: string,
	previewAssetId: number,
	-- The backend job that produced this graphic. The backend serves the
	-- full-resolution PNG it already generated at GET /v1/graphics/{backendJobId}/image
	-- with no auth required, so the client can build a link the player can
	-- open in their own browser to view or save it -- Roblox itself has no
	-- API for an experience to save a file to the player's device.
	backendJobId: string,
	createdAt: number,
	updatedAt: number,
}

export type PendingIntent = {
	id: string,
	productKey: string,
	payload: { [string]: any },
	createdAt: number,
	expiresAt: number,
}

export type FitPreset = {
	id: string,
	name: string,
	accessoryType: string,
	fit: FitTransform,
	createdAt: number,
}

export type PendingTransfer = {
	transferRequestId: string,
	status: "PROMPTING" | "AWAITING_RECEIPT",
	itemId: string,
	sellerUserId: number,
	amount: number,
	sourceItem: ItemRecord,
	createdAt: number,
}

export type PlayerProfile = {
	schemaVersion: number,
	userId: number,
	items: { [string]: ItemRecord },
	itemOrder: { string },
	generations: { [string]: GenerationRecord },
	generationOrder: { string },
	graphics: { [string]: GraphicRecord },
	graphicOrder: { string },
	likedItems: { [string]: boolean },
	favoriteItems: { [string]: boolean },
	pendingIntents: { [string]: PendingIntent },
	pendingTransfers: { [string]: PendingTransfer },
	processedReceipts: { [string]: number },
	grantedIntents: { [string]: { [string]: any } },
	retryCredits: { [string]: number },
	equippedItemIds: { string },
	fitPresets: { [string]: FitPreset },
	fitPresetOrder: { string },
	-- Real-money-backed (ads, direct Robux purchase) — may fund generation
	-- products. See ProfileService.defaultProfile for why this stays apart
	-- from bonusTokens.
	tokens: number,
	-- Free grants (achievements, daily check-in, invites, group join) — may
	-- only ever buy the Priority Pass.
	bonusTokens: number,
	adWatch: { day: number, count: number },
	achievements: { [string]: number },
	settings: { soundsEnabled: boolean, reduceMotion: boolean, highContrast: boolean, uiScale: number },
	stats: { [string]: number },
	daily: { lastDay: number, streak: number, best: number },
	onboarding: { completed: boolean, step: number },
	createdAt: number,
	updatedAt: number,
}

export type PolicySnapshot = {
	contentSharingAllowed: boolean,
	commerceAllowed: boolean,
	subscriptionAllowed: boolean,
	paidTradingAllowed: boolean,
}

return nil
