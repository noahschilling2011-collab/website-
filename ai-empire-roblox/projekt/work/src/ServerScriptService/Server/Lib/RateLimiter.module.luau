--!strict
-- Token-Bucket pro Spieler: `burst` Anfragen sofort, danach `perSecond` nachfüllend.

export type Limiter = {
	allow: (player: Player) -> boolean,
	forget: (player: Player) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiter = {}

function RateLimiter.new(burst: number, perSecond: number): Limiter
	local buckets: { [Player]: Bucket } = {}

	local function allow(player: Player): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if not bucket then
			bucket = { tokens = burst, last = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * perSecond)
		bucket.last = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	local function forget(player: Player)
		buckets[player] = nil
	end

	return { allow = allow, forget = forget }
end

return RateLimiter
