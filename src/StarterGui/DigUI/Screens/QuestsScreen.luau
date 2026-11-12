--!strict
-- Explorer: StarterGui/DigUI/Screens/QuestsScreen (ModuleScript)
-- Three daily quests, same for everyone: progress bar, gem reward chip and
-- a claim button that lights up the moment a quest is done.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Button = require(script.Parent.Parent.Components.Button)
local Icon = require(script.Parent.Parent.Components.Icon)
local Label = require(script.Parent.Parent.Components.Label)
local Modal = require(script.Parent.Parent.Components.Modal)
local Panel = require(script.Parent.Parent.Components.Panel)

local QuestsScreen = {}

type Row = {
	frame: GuiObject,
	title: TextLabel,
	reward: TextLabel,
	bar: Bar.Handle,
	claim: Button.Handle,
}

function QuestsScreen.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Daily quests", name = "Quests", maxWidth = 620, maxHeight = 440, sfx = sfx, color = "orange", icon = "Quest" })

	local resetLabel = Label.new({ parent = modal.content, text = "", size = UDim2.new(1, 0, 0, 24), textSize = 17, color = UITheme.Colors.TextDim })
	local list = Base.frame(modal.content, "List", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 32))
	list.AutomaticSize = Enum.AutomaticSize.Y
	Base.list(list, Enum.FillDirection.Vertical, 10)

	local rows: { Row } = {}
	for i = 1, Quests.PER_DAY do
		local frame = Panel.new({ parent = list, style = "card", size = UDim2.new(1, 0, 0, 96), padding = 12, layoutOrder = i })
		local title = Label.new({ parent = frame, text = "", size = UDim2.new(1, -150, 0, 28), textSize = 22, display = true, truncate = true })
		local chip = Base.fill(frame, "Reward", Color3.new(1, 1, 1), UDim2.fromOffset(0, 26), UDim2.fromOffset(0, 32))
		chip.AutomaticSize = Enum.AutomaticSize.X
		Base.round(chip)
		Base.stroke(chip, UITheme.Colors.Ink, 2.5)
		Base.gradient(chip, UITheme.Swatches.purple.top, UITheme.Swatches.purple.bottom)
		local chipPad = Instance.new("UIPadding")
		chipPad.PaddingLeft = UDim.new(0, 8)
		chipPad.PaddingRight = UDim.new(0, 10)
		chipPad.Parent = chip
		Base.list(chip, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		Icon.new({ parent = chip, name = "Gem", size = UDim2.fromOffset(20, 20), layoutOrder = 1 })
		local reward = Label.new({ parent = chip, text = "", size = UDim2.new(0, 0, 1, 0), textSize = 16, display = true, layoutOrder = 2 })
		reward.AutomaticSize = Enum.AutomaticSize.X
		local bar = Bar.new({ parent = frame, size = UDim2.new(1, -150, 0, 22), position = UDim2.new(0, 0, 1, 0), anchor = Vector2.new(0, 1), swatch = "green", label = true, textSize = 14 })
		local claim = Button.new({
			parent = frame,
			text = "CLAIM",
			size = UDim2.new(0, 130, 0, 60),
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			kind = "green",
			textSize = 22,
			sfx = sfx,
		})
		rows[i] = { frame = frame, title = title, reward = reward, bar = bar, claim = claim }
	end

	local function refresh()
		local quests = state.quests
		local set = Quests.dailySet(if quests.day > 0 then quests.day else Quests.dayNumber())
		for i, row in rows do
			local quest = set[i]
			row.frame.Visible = quest ~= nil
			if not quest then
				continue
			end
			local progress = math.min(quests.progress[quest.id] or 0, quest.goal)
			local claimed = quests.claimed[quest.id] == true
			local done = progress >= quest.goal
			row.title.Text = quest.title
			row.reward.Text = `+{quest.reward}`
			row.bar.setFraction(progress / quest.goal)
			row.bar.setLabel(`{Format.cash(progress)} / {Format.cash(quest.goal)}`)
			row.claim.setEnabled(not claimed and done)
			row.claim.setText(if claimed then "DONE ✓" elseif done then "CLAIM!" else "IN PROGRESS")
			row.claim.setKind(if claimed then "grey" else "green")
			row.claim.setOnClick(function()
				state.send("ClaimQuest", quest.id)
			end)
		end
	end

	state.onQuests:Connect(refresh)
	modal.onOpen:Connect(refresh)
	state.onNotify:Connect(function(kind)
		if kind == "gems" then
			ctx.sfx.play("QuestClaim", { volume = 0.6 })
		end
	end)
	RunService.Heartbeat:Connect(function()
		if modal.isOpen() then
			resetLabel.Text = `⏰ New quests in {Format.clock(Quests.secondsUntilReset())}`
		end
	end)
	return modal
end

return QuestsScreen
