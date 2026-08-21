--!strict

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: {
		windowSeconds: number,
		maximum: number,
		entries: { [number]: { number } },
	},
	RateLimiter
))

function RateLimiter.new(maximum: number, windowSeconds: number): RateLimiter
	return setmetatable({
		windowSeconds = windowSeconds,
		maximum = maximum,
		entries = {},
	}, RateLimiter)
end

function RateLimiter.consume(self: RateLimiter, userId: number): boolean
	local now = os.clock()
	local cutoff = now - self.windowSeconds
	local previous = self.entries[userId] or {}
	local current = {}
	for _, timestamp in previous do
		if timestamp >= cutoff then
			table.insert(current, timestamp)
		end
	end
	if #current >= self.maximum then
		self.entries[userId] = current
		return false
	end
	table.insert(current, now)
	self.entries[userId] = current
	return true
end

function RateLimiter.remove(self: RateLimiter, userId: number)
	self.entries[userId] = nil
end

return RateLimiter
