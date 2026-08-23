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
export type GenerationMethod = "TEXT_TO_3D" | "IMAGE_PREVIEW" | "IMAGE_UPLOAD" | "IMAGE_TO_3D"

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
	accessoryType: string,
	stylePreset: string,
	detailLevel: string,
	imageQuality: string?,
	sourceImageAssetId: number?,
	backendJobId: string?,
	sourceBackendJobId: string?,
	previewAssetId: number?,
	itemId: string?,
	errorCode: string?,
	failureHandled: boolean?,
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
	tokens: number,
	adWatch: { day: number, count: number },
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
