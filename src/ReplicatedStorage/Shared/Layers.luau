--!strict
-- Explorer: ReplicatedStorage/Shared/Layers (ModuleScript)
-- Depth -> layer lookups and hardness. A cell in row r spans depth r-1..r,
-- so its layer is decided by its top (r-1).

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Types = require(script.Parent.Types)

type LayerDef = Types.LayerDef

local Layers = {}

local list = GameConfig.Layers

function Layers.count(): number
	return #list
end

function Layers.get(index: number): LayerDef
	return list[math.clamp(index, 1, #list)]
end

--- Layer index for a depth in metres (0 = surface).
function Layers.indexAt(depth: number): number
	local found = 1
	for i, layer in list do
		if depth >= layer.startDepth then
			found = i
		else
			break
		end
	end
	return found
end

function Layers.layerAt(depth: number): LayerDef
	return list[Layers.indexAt(depth)]
end

--- Layer of the cell in row `row`.
function Layers.ofRow(row: number): LayerDef
	return list[Layers.indexAt(math.max(0, row - 1))]
end

--- Depth where the layer after `index` begins (CoreDepth for the last one).
function Layers.endDepth(index: number): number
	local nextLayer = list[index + 1]
	return if nextLayer then nextLayer.startDepth else GameConfig.CoreDepth
end

--- Base hardness of row `row` (1-based). Ramps linearly through each layer.
function Layers.hardnessAt(row: number): number
	if row >= GameConfig.CoreDepth then
		return GameConfig.CoreHardness
	end
	local top = math.max(0, row - 1)
	local li = Layers.indexAt(top)
	local layer = list[li]
	local span = math.max(1, Layers.endDepth(li) - layer.startDepth)
	local t = math.clamp((top - layer.startDepth) / span, 0, 1)
	return layer.hardness + (layer.hardnessEnd - layer.hardness) * t
end

--- 0..1 progress through the current layer, for the HUD depth meter.
function Layers.progressAt(depth: number): number
	local li = Layers.indexAt(depth)
	local layer = list[li]
	local span = math.max(1, Layers.endDepth(li) - layer.startDepth)
	return math.clamp((depth - layer.startDepth) / span, 0, 1)
end

return Layers
