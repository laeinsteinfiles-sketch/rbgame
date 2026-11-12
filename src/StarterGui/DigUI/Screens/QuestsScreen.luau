--!strict
-- Explorer: StarterGui/DigUI/Screens/QuestsScreen (ModuleScript)
-- Three daily quests, same for everyone, with progress and claim buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Format)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Base = require(script.Parent.Parent.Components.Base)
local Bar = require(script.Parent.Parent.Components.Bar)
local Button = require(script.Parent.Parent.Components.Button)
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
	questId: string,
}

function QuestsScreen.new(ctx: Base.Context): Modal.Handle
	local state = ctx.state
	local sfx = function(name: string)
		ctx.sfx.play(name)
	end
	local modal = Modal.new({ parent = ctx.modals, title = "Daily quests", name = "Quests", maxWidth = 560, maxHeight = 400, sfx = sfx })

	local resetLabel = Label.new({
		parent = modal.content,
		text = "",
		size = UDim2.new(1, 0, 0, 20),
		textSize = UITheme.TextSize.Small,
		color = UITheme.Colors.TextDim,
	})
	local list = Base.frame(modal.content, "List", UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, 26))
	list.AutomaticSize = Enum.AutomaticSize.Y
	Base.list(list, Enum.FillDirection.Vertical, UITheme.Gap)

	local rows: { Row } = {}
	for i = 1, Quests.PER_DAY do
		local frame = Panel.new({ parent = list, inset = true, size = UDim2.new(1, 0, 0, 84), padding = 10, layoutOrder = i })
		local title = Label.new({ parent = frame, text = "", size = UDim2.new(1, -130, 0, 22), textSize = UITheme.TextSize.Body, display = true })
		local reward = Label.new({ parent = frame, text = "", size = UDim2.new(1, -130, 0, 16), position = UDim2.fromOffset(0, 22), textSize = UITheme.TextSize.Small, color = UITheme.Colors.Teal })
		local bar = Bar.new({ parent = frame, size = UDim2.new(1, -130, 0, 16), position = UDim2.fromOffset(0, 46), color = UITheme.Colors.Teal, label = true })
		local claim = Button.new({
			parent = frame,
			text = "Claim",
			size = UDim2.new(0, 110, 0, 48),
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			kind = "primary",
			sfx = sfx,
		})
		rows[i] = { frame = frame, title = title, reward = reward, bar = bar, claim = claim, questId = "" }
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
			local progress = quests.progress[quest.id] or 0
			local claimed = quests.claimed[quest.id] == true
			row.questId = quest.id
			row.title.Text = quest.title
			row.reward.Text = `Reward {quest.reward} gems`
			row.bar.setFraction(progress / quest.goal)
			row.bar.setLabel(`{Format.cash(progress)} / {Format.cash(quest.goal)}`)
			row.claim.setEnabled(not claimed and progress >= quest.goal)
			row.claim.setText(if claimed then "Done" else "Claim")
			row.claim.setKind(if claimed then "secondary" else "primary")
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
			resetLabel.Text = `New quests in {Format.clock(Quests.secondsUntilReset())}`
		end
	end)
	return modal
end

return QuestsScreen
