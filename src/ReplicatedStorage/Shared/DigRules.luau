--!strict
-- Explorer: ReplicatedStorage/Shared/DigRules (ModuleScript)
-- The server's dig validation as a pure function, so the self tests can
-- exercise every branch outside Studio. Order: shape -> phase -> state ->
-- adjacency -> reach -> timing. Only cheat-shaped failures are violations;
-- everything an honest client can trigger (lag, stale prediction, a dig
-- that raced a round reset) is a quiet rejection.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local CellGen = require(script.Parent.CellGen)
local Economy = require(script.Parent.Economy)
local Grid = require(script.Parent.Grid)
local Types = require(script.Parent.Types)

local DigRules = {}

local D = GameConfig.Dig

export type Context = {
	seed: number,
	phase: string,
	traveling: boolean,
	reachedCore: boolean,
	isOpen: (col: number, row: number) -> boolean, -- dug or cave; row 0 counts as open
	hasRoot: boolean,
	rootDx: number, -- character root X offset from the plot origin
	rootY: number, -- world Y
	rootDz: number, -- Z offset from the plot origin
	now: number,
	digClock: number,
	power: number,
}

export type Verdict = {
	ok: boolean,
	reason: string,
	violation: boolean,
	digClock: number,
	cell: Types.Cell?,
}

local function reject(ctx: Context, reason: string, violation: boolean): Verdict
	return { ok = false, reason = reason, violation = violation, digClock = ctx.digClock, cell = nil }
end

local function isInteger(value: any): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0 and math.abs(value) < 1e6
end

function DigRules.validate(col: any, row: any, ctx: Context): Verdict
	if not isInteger(col) or not isInteger(row) then
		return reject(ctx, "malformed", true)
	end
	if not Grid.inBounds(col, row) then
		return reject(ctx, "out of bounds", true)
	end
	if ctx.phase ~= "Active" then
		return reject(ctx, "not active", false)
	end
	if ctx.reachedCore then
		return reject(ctx, "finished", false)
	end
	if ctx.traveling then
		return reject(ctx, "traveling", false)
	end
	if ctx.isOpen(col, row) then
		return reject(ctx, "already open", false)
	end

	local adjacent = false
	for _, offset in Grid.NEIGHBOURS do
		local c, r = col + offset[1], row + offset[2]
		if r == 0 or (c >= 1 and c <= Grid.COLS and r >= 1 and ctx.isOpen(c, r)) then
			adjacent = true
			break
		end
	end
	if not adjacent then
		return reject(ctx, "not adjacent", false)
	end

	if not ctx.hasRoot then
		return reject(ctx, "no character", false)
	end
	local cx, cy = Grid.cellOffset(col, row)
	local dx, dy = ctx.rootDx - cx, ctx.rootY - cy
	local distance = math.sqrt(dx * dx + dy * dy)
	if distance > D.ViolationReachStuds or math.abs(ctx.rootDz) > Grid.CELL * 4 then
		return reject(ctx, "far out of reach", true)
	end
	if distance > D.ReachStuds then
		return reject(ctx, "out of reach", false)
	end

	local cell = CellGen.at(ctx.seed, col, row)
	local required = ctx.digClock + Economy.digTime(cell.hardness, ctx.power)
	if required > ctx.now + D.ToleranceSeconds then
		return reject(ctx, "too fast", required > ctx.now + D.ViolationAheadSeconds)
	end
	return {
		ok = true,
		reason = "ok",
		violation = false,
		digClock = math.max(required, ctx.now - D.BankSeconds),
		cell = cell,
	}
end

return DigRules
