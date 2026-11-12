--!strict
-- Explorer: ServerScriptService/Services/RateLimiter (ModuleScript)
-- Token bucket per player per remote. Over-limit calls are dropped, not
-- queued, so a flooding client only hurts itself.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { tokens: number, last: number }

export type Limiter = typeof(setmetatable(
	{} :: { capacity: number, refill: number, buckets: { [Player]: Bucket } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refill: number): Limiter
	return setmetatable({ capacity = capacity, refill = refill, buckets = {} }, RateLimiter)
end

function RateLimiter.allow(self: Limiter, player: Player): boolean
	local now = os.clock()
	local bucket = self.buckets[player]
	if not bucket then
		bucket = { tokens = self.capacity, last = now }
		self.buckets[player] = bucket
	end
	bucket.tokens = math.min(self.capacity, bucket.tokens + (now - bucket.last) * self.refill)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.forget(self: Limiter, player: Player)
	self.buckets[player] = nil
end

return RateLimiter
