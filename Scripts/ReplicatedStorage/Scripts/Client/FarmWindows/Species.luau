-- 物种管理独立窗口：展示解锁链并沿用服务端选择与清理确认流程
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage.Scripts.Shared.FarmEconomyConfig)
local Info = require(script.Parent.Parent.ClientGameInfo)
local Common = require(script.Parent.Common)
local Species = {}
function Species.Bind(ctx: Common.Context): ()
	local list = ctx.panel:WaitForChild("ItemsScrollingFrame")
	local function Render(): ()
		local info = Info.GetFarmInfo()
		local unlocked = info.unlockedSpecies or {}
		Common.Wallet(ctx)
		for i, species in Config.Species do
			local card = list:WaitForChild("Item" .. i .. "Frame")
			local previous = i == 1 or unlocked[Config.Species[i - 1].id] == true
			local selected = info.nestLevel == i
			Common.Label(card, "NameText", species.name)
			Common.Label(card, "DetailText", species.health .. " HP  /  " .. species.saleValue .. " coins")
			Common.State(Common.Button(card, "ActionButton"), if ctx.pending then "Working…" elseif selected then "Selected" elseif unlocked[species.id] then "Select" elseif previous then Common.Price(species.unlockPrice) else "Unlock previous first", not ctx.pending and not selected and previous and (unlocked[species.id] == true or info.cash >= species.unlockPrice))
		end
	end
	for i, species in Config.Species do
		local button = Common.Button(list:WaitForChild("Item" .. i .. "Frame"), "ActionButton")
		local function OnSelect(): () if button.Active then Common.Submit(ctx, { action = "selectSpecies", speciesId = species.id }, Render) end end
		ctx.window.scope:Connect(button.Activated:Connect(OnSelect))
	end
	Common.Observe(ctx, Render)
end
return Species
