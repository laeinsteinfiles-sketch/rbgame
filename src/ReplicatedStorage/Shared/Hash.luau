--!strict
-- Explorer: ReplicatedStorage/Shared/Hash (ModuleScript)
-- Deterministic 32-bit mixing shared by server and client. Everything here is
-- exact integer arithmetic on doubles (< 2^53) plus bit32, so both sides agree
-- without ever exchanging block data.

local Hash = {}

local TWO32 = 4294967296

-- Exact 32-bit multiply without overflowing double precision.
local function mul32(a: number, b: number): number
	local ah, al = a // 65536, a % 65536
	local bh, bl = b // 65536, b % 65536
	return (al * bl + ((ah * bl + al * bh) % 65536) * 65536) % TWO32
end

-- murmur3 finaliser
local function fmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

--- Returns an integer in [0, 2^32).
function Hash.u32(seed: number, index: number, salt: number): number
	local h = fmix(bit32.bxor(seed % TWO32, mul32(index % TWO32, 0x9E3779B1)))
	h = fmix(bit32.bxor(h, mul32((salt + 1) % TWO32, 0x85EBCA77)))
	return h
end

--- Returns a float in [0, 1).
function Hash.unit(seed: number, index: number, salt: number): number
	return Hash.u32(seed, index, salt) / TWO32
end

Hash.mul32 = mul32

return Hash
