--!strict

-- Standard Roblox "leaderstats" folder -- Roblox's own PlayerList UI reads
-- any Player.leaderstats Folder of value objects natively, with each
-- child's Name becoming a column header, no client code required. Kept as
-- its own tiny service (rather than folded into ProfileService) since it's
-- purely a presentation concern over profile.stats, not profile storage.

local LeaderstatsService = {}
LeaderstatsService.__index = LeaderstatsService

function LeaderstatsService.new()
	return setmetatable({}, LeaderstatsService)
end

-- Total Robux this player has sent to OTHER creators -- buying a copy of
-- their item/graphic and tipping them are both PromptRobuxTransferAsync
-- transfers, tracked as two separate profile.stats fields (purchaseRobuxSent,
-- tipRobuxSent) for finer-grained analytics; this is their sum for display.
local function robuxSpentOnCreators(stats: { [string]: number }): number
	return (stats.purchaseRobuxSent or 0) + (stats.tipRobuxSent or 0)
end

function LeaderstatsService:Init(player: Player, profile: { [string]: any })
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local function valueFor(name: string): IntValue
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("IntValue") then
			return existing
		end
		if existing then
			existing:Destroy()
		end
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = folder
		return value
	end
	valueFor("Creations")
	valueFor("Bought")
	valueFor("Robux Spent")
	self:Refresh(player, profile)
end

function LeaderstatsService:Refresh(player: Player, profile: { [string]: any })
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local stats = profile.stats or {}
	local creations = folder:FindFirstChild("Creations")
	if creations and creations:IsA("IntValue") then
		creations.Value = stats.generationsCompleted or 0
	end
	local bought = folder:FindFirstChild("Bought")
	if bought and bought:IsA("IntValue") then
		bought.Value = stats.marketplacePurchases or 0
	end
	local robuxSpent = folder:FindFirstChild("Robux Spent")
	if robuxSpent and robuxSpent:IsA("IntValue") then
		robuxSpent.Value = robuxSpentOnCreators(stats)
	end
end

return LeaderstatsService
