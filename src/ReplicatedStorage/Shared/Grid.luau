--!strict
-- Explorer: ReplicatedStorage/Shared/Grid (ModuleScript)
-- Cell <-> world maths for the 2D mine, shared by server, client and sim.
-- Pure numbers only (no Vector3) so it also runs under the luau CLI.
--
-- Columns run along world X, centred on the plot origin. Row r spans world
-- Y from SurfaceY - r*Cell (floor) to SurfaceY - (r-1)*Cell (ceiling); row 0
-- is the open surface above the mine. The mine slab is one cell deep in Z,
-- centred on the plot origin's Z, so its front face is at originZ + Cell/2.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Grid = {}

local G = GameConfig.Geometry
local CELL = G.Cell
local COLS = G.Columns
local KEY_STRIDE = 64 -- > Columns, so keys never collide

Grid.CELL = CELL
Grid.COLS = COLS
Grid.CORE_ROW = GameConfig.CoreDepth

function Grid.key(col: number, row: number): number
	return row * KEY_STRIDE + col
end

function Grid.unkey(key: number): (number, number)
	return key % KEY_STRIDE, key // KEY_STRIDE
end

function Grid.inBounds(col: number, row: number): boolean
	return col >= 1 and col <= COLS and row >= 1 and row <= Grid.CORE_ROW
end

--- X offset from the plot origin and world Y of a cell centre.
function Grid.cellOffset(col: number, row: number): (number, number)
	return (col - (COLS + 1) / 2) * CELL, G.SurfaceY - (row - 0.5) * CELL
end

--- Column containing an X offset from the plot origin (may be out of range).
function Grid.colAt(xOffset: number): number
	return math.floor(xOffset / CELL + (COLS + 1) / 2 + 0.5)
end

--- Row containing a world Y (0 or less means at/above the surface).
function Grid.rowAt(y: number): number
	return math.floor((G.SurfaceY - y) / CELL) + 1
end

--- Half width of the diggable strip in studs.
function Grid.halfWidth(): number
	return COLS * CELL / 2
end

--- Plot origin (centre of the mine's top edge) in world X/Z for a 1-based plot index.
function Grid.plotOrigin(index: number): (number, number)
	local i = index - 1
	local cols = G.PlotColumns
	local rows = math.ceil(G.MaxPlayers / cols)
	local col, row = i % cols, i // cols
	return (col - (cols - 1) / 2) * G.PlotSpacingX, (row - (rows - 1) / 2) * G.PlotSpacingZ
end

Grid.NEIGHBOURS = {
	{ 0, 1 }, -- down
	{ -1, 0 }, -- left
	{ 1, 0 }, -- right
	{ 0, -1 }, -- up
}

return Grid
