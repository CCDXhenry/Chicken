-- 工具店首页控制器：仅绑定四个独立功能窗口的导航入口
--!strict
local Common = require(script.Parent.Common)
local ToolShop = {}
function ToolShop.Bind(ctx: Common.Context): ()
	for _, id in { "WeaponShop", "WeaponEnhance", "CollectorShop", "BasketShop" } do
		local function OnOpen(): () if ctx.allowed() then ctx.open(id) end end
		ctx.window.scope:Connect(Common.Button(ctx.panel:WaitForChild(id .. "CardFrame"), "OpenButton").Activated:Connect(OnOpen))
	end
	local function Render(): () Common.Wallet(ctx) end
	Common.Observe(ctx, Render)
end
return ToolShop
