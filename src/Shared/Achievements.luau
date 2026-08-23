--!strict

-- Shared with the client so the Achievements view can list every milestone
-- (locked and unlocked), not just the ones a player has already earned.
-- AchievementService is the only thing that grants these; this module is
-- data only.

export type AchievementDefinition = {
	id: string,
	name: string,
	description: string,
	tokens: number,
}

local Achievements = {
	-- The id AchievementService grants automatically, not from a call site.
	CompletionistId = "COMPLETIONIST",
	List = {
		{ id = "FIRST_CREATION", name = "First Spark", description = "Complete your first accessory.", tokens = 5 },
		{ id = "FIVE_CREATIONS", name = "Prolific", description = "Complete five accessories.", tokens = 10 },
		{
			id = "FIRST_EQUIP",
			name = "Suit Up",
			description = "Equip a generated item on your avatar.",
			tokens = 3,
		},
		{
			id = "FIRST_FIT_PRESET",
			name = "Dialed In",
			description = "Save your first fit preset.",
			tokens = 3,
		},
		{
			id = "FIRST_PUBLISH",
			name = "Published Creator",
			description = "Publish a wearable to the Roblox catalog.",
			tokens = 10,
		},
		{
			id = "FIRST_LISTING",
			name = "Open For Business",
			description = "List one of your originals for sale.",
			tokens = 5,
		},
		{
			id = "FIRST_LIKE_GIVEN",
			name = "Supportive",
			description = "Like another creator's item in Discover.",
			tokens = 2,
		},
		{
			id = "FIRST_TRY_ON",
			name = "Window Shopper",
			description = "Try on a Roblox catalog item in Avatar Lab.",
			tokens = 2,
		},
		{ id = "FIRST_AD_WATCHED", name = "Ad Break", description = "Watch a rewarded ad.", tokens = 3 },
		{
			id = "FIRST_MARKETPLACE_PURCHASE",
			name = "Collector",
			description = "Buy another creator's listed item.",
			tokens = 5,
		},
		{
			id = "STREAK_SEVEN",
			name = "Week-Long Habit",
			description = "Reach a seven-day studio streak.",
			tokens = 15,
		},
		{
			id = "FIRST_INVITE_SENT",
			name = "Bring a Friend",
			description = "Send a Roblox game invite to a friend.",
			tokens = 3,
		},
		-- Granted automatically by AchievementService once every achievement
		-- above is unlocked; never call Unlock/CheckCount with this id
		-- directly. Kept last in the list so it reads as the finale.
		{
			id = "COMPLETIONIST",
			name = "Forge Legend",
			description = "Unlock every other achievement.",
			tokens = 20,
		},
	} :: { AchievementDefinition },
}

return table.freeze(Achievements)
