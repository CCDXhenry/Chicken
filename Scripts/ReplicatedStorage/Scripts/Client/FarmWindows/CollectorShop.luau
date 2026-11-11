-- CollectorShop 独立窗口控制器：绑定对应购买行为与生命周期
--!strict
local Common = require(script.Parent.Common)
local Purchase = require(script.Parent.Purchase)
local Controller = {}
function Controller.Bind(ctx: Common.Context): ()
	Purchase.Bind(ctx, "buyCollect")
end
return Controller
