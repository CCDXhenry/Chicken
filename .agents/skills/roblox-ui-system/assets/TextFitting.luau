-- 通用单行文本自适应拟合模块：提供二分查找字号计算、单行文本只缩不放拟合及阴影文本同步
--!strict
local TextService = game:GetService("TextService")

local TextFitting = {}

local TextFitPadding = Vector2.new(8, 8)
local TextMeasureExtent = 1000000
local TextFitMinimumSize = 1

export type TextFitOptions = {
	maxSize: number?,
	minSize: number?,
	padding: Vector2?,
	stripRichText: boolean?,
}

type TextFitCache = {
	text: string,
	boxSize: Vector2,
	font: Enum.Font,
	designSize: number,
	fittedSize: number,
}

local textFitCache: { [TextLabel]: TextFitCache } = setmetatable({}, { __mode = "k" }) :: any

local function AncestorScale(label: GuiObject): number
	local scale = 1
	local current: Instance? = label
	while current ~= nil do
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale ~= nil and uiScale:IsA("UIScale") and uiScale.Scale > 0 then
			scale *= uiScale.Scale
		end
		current = current.Parent
	end
	return scale
end

-- 自动撑开宽度的动态文本不能拿当前实际宽度当设计框，否则每次连击都会按更窄结果再次缩小
local function FitLimit(label: TextLabel, axis: "X" | "Y"): number?
	local constraint = label:FindFirstChildOfClass("UISizeConstraint")
	if constraint == nil or not constraint:IsA("UISizeConstraint") then
		return nil
	end
	local limit = if axis == "X" then constraint.MaxSize.X else constraint.MaxSize.Y
	if limit > 0 and limit < math.huge then
		return limit
	end
	return nil
end

local function DesignBox(label: TextLabel, padding: Vector2): Vector2
	local scale = AncestorScale(label)
	local automatic = label.AutomaticSize
	local function Axis(offset: number, absolute: number, grows: boolean, axis: "X" | "Y"): number
		if offset > 0 then
			return offset
		end
		if grows then
			local limit = FitLimit(label, axis)
			if limit ~= nil then
				return limit
			end
		end
		return absolute / scale
	end
	local width = Axis(label.Size.X.Offset, label.AbsoluteSize.X, automatic == Enum.AutomaticSize.X or automatic == Enum.AutomaticSize.XY, "X")
	local height = Axis(label.Size.Y.Offset, label.AbsoluteSize.Y, automatic == Enum.AutomaticSize.Y or automatic == Enum.AutomaticSize.XY, "Y")
	return Vector2.new(math.max(1, width - padding.X), math.max(1, height - padding.Y))
end

local function PlainText(label: TextLabel, options: TextFitOptions?): string
	if label.RichText and (options == nil or options.stripRichText ~= false) then
		return string.gsub(label.Text, "<[^>]->", "")
	end
	return label.Text
end

-- 在设计框内二分查找能放下整行的最大字号，上限不超过设计上限
function TextFitting.CalculateFittedFontSize(
	text: string,
	availableSize: Vector2,
	font: Enum.Font,
	maxSize: number,
	minSize: number?
): number
	local minimum = minSize or TextFitMinimumSize
	local maximum = math.max(minimum, math.floor(maxSize))
	local best = minimum
	local measureBound = Vector2.new(TextMeasureExtent, TextMeasureExtent)
	while minimum <= maximum do
		local candidate = math.floor((minimum + maximum) / 2)
		local bounds = TextService:GetTextSize(text, candidate, font, measureBound)
		if bounds.X <= availableSize.X and bounds.Y <= availableSize.Y then
			best = candidate
			minimum = candidate + 1
		else
			maximum = candidate - 1
		end
	end
	return best
end

-- 单行文字关闭原生缩放和换行，先缩进设计框，再由根 UIScale 整体缩放
function TextFitting.FitTextLabel(label: TextLabel, options: TextFitOptions?): number
	label.TextScaled = false
	label.TextWrapped = false
	local previous = textFitCache[label]
	local configuredDesign = label:GetAttribute("DesignTextSize")
	local designSize = if options ~= nil and typeof(options.maxSize) == "number"
		then options.maxSize
		elseif typeof(configuredDesign) == "number" then configuredDesign
		elseif previous ~= nil then previous.designSize
		else label.TextSize
	local pendingWidth = label.Size.X.Offset <= 0 and label.AbsoluteSize.X <= 0
	local pendingHeight = label.Size.Y.Offset <= 0 and label.AbsoluteSize.Y <= 0
	if pendingWidth or pendingHeight then
		local fallback = if previous ~= nil then previous.fittedSize else designSize
		label.TextSize = fallback
		return fallback
	end
	local padding = if options ~= nil and typeof(options.padding) == "Vector2" then options.padding else TextFitPadding
	local availableSize = DesignBox(label, padding)
	if
		previous ~= nil
		and previous.text == label.Text
		and previous.boxSize == availableSize
		and previous.font == label.Font
		and previous.designSize == designSize
	then
		label.TextSize = previous.fittedSize
		return previous.fittedSize
	end
	local minimum = if options ~= nil then options.minSize else TextFitMinimumSize
	local fittedSize = TextFitting.CalculateFittedFontSize(
		PlainText(label, options),
		availableSize,
		label.Font,
		designSize,
		minimum
	)
	label.TextSize = fittedSize
	textFitCache[label] = {
		text = label.Text,
		boxSize = availableSize,
		font = label.Font,
		designSize = designSize,
		fittedSize = fittedSize,
	}
	return fittedSize
end

-- 阴影层使用与主字相同的文案和字号，避免两层在缩放后错位
function TextFitting.FitTextWithShadow(mainLabel: TextLabel, shadowLabel: Instance?, options: TextFitOptions?): number
	local fittedSize = TextFitting.FitTextLabel(mainLabel, options)
	if shadowLabel ~= nil and shadowLabel:IsA("TextLabel") then
		shadowLabel.TextScaled = false
		shadowLabel.TextWrapped = false
		shadowLabel.Text = mainLabel.Text
		shadowLabel.TextSize = fittedSize
	end
	return fittedSize
end

-- 只拟合带 DesignTextSize 标记的屏幕单行标签；世界标牌和多行段落保持原样
function TextFitting.FitMarkedText(label: TextLabel): number?
	if typeof(label:GetAttribute("DesignTextSize")) ~= "number" then
		return nil
	end
	if label:FindFirstAncestorOfClass("BillboardGui") ~= nil or label:FindFirstAncestorOfClass("SurfaceGui") ~= nil then
		return nil
	end
	local parent = label.Parent
	local shadow = if parent ~= nil then parent:FindFirstChild("ShadowText") else nil
	if shadow == label then
		shadow = nil
	end
	if shadow ~= nil then
		return TextFitting.FitTextWithShadow(label, shadow)
	end
	return TextFitting.FitTextLabel(label)
end

-- 模板里的静态单行文字不会再次赋值，布局或初始化时对容器内所有带标记文本执行一次拟合
function TextFitting.FitMarkedRoot(root: Instance): ()
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") then
			TextFitting.FitMarkedText(descendant)
		end
	end
end

return TextFitting
