-- 农场文案适配器：用英文源句匹配动态文案，按词条键和参数交给翻译接口
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local TranslationTool = require(replicatedStorage:WaitForChild("Core"):WaitForChild("Scripts"):WaitForChild("Client"):WaitForChild("TranslationTool"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local FarmTextTool = {}
local textFitConnections: { [TextLabel]: RBXScriptConnection? } = {}

local function EscapePattern(value: string): string
	return (value:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function GetPattern(template: string): string
	local result = "^"
	local cursor = 1
	while true do
		local first, last = template:find("%%[ds]", cursor)
		if not first or not last then
			break
		end
		result ..= EscapePattern(template:sub(cursor, first - 1)) .. (if template:sub(last, last) == "d" then "(%d+)" else "(.-)")
		cursor = last + 1
	end
	return result .. EscapePattern(template:sub(cursor)) .. "$"
end

local function PlaceholderSource(source: string): string
	local index = 0
	return (source:gsub("%%[ds]", function(): string
		index += 1
		return "{" .. index .. "}"
	end))
end

local function PlaceholderCount(source: string): number
	local _, count = source:gsub("%%[ds]", "")
	return count
end

local function DisconnectTextFit(label: TextLabel): ()
	local connection = textFitConnections[label]
	if connection == nil then
		return
	end
	connection:Disconnect()
	textFitConnections[label] = nil
end

local function ShouldFitScreenText(label: TextLabel): boolean
	if typeof(label:GetAttribute("DesignTextSize")) ~= "number" then
		return false
	end
	if label:FindFirstAncestorOfClass("BillboardGui") ~= nil or label:FindFirstAncestorOfClass("SurfaceGui") ~= nil then
		return false
	end
	return true
end

local function WatchScreenText(label: TextLabel): ()
	if not ShouldFitScreenText(label) then
		return
	end
	if textFitConnections[label] == nil then
		local function OnTextChanged(): ()
			UIManager.FitMarkedText(label)
		end
		local function OnDestroying(): ()
			DisconnectTextFit(label)
		end
		textFitConnections[label] = label:GetPropertyChangedSignal("Text"):Connect(OnTextChanged)
		label.Destroying:Connect(OnDestroying)
	end
	UIManager.FitMarkedText(label)
end

local function ReleaseGui(gui: Instance): ()
	if gui:IsA("TextLabel") then
		DisconnectTextFit(gui)
	end
	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		TranslationTool.RemoveCustomAutoLocalizeGui(gui)
	end
end

local function LocalizeArgument(context: Instance, argument: string): string
	if argument:match("^%d+$") ~= nil then
		return argument
	end
	return TranslationTool.Translate(context, argument)
end

local function FindFarmEntry(message: string): (string?, string?, { string }?)
	local farmTexts: { [string]: GameTexts.TextData } = GameTexts.Farm
	local bestCount = -1
	local bestSource: string? = nil
	local bestKey: string? = nil
	local bestArgs: { string }? = nil
	for _, entry in farmTexts do
		local pattern = GetPattern(entry.source)
		if message:match(pattern) == nil then
			continue
		end
		local count = PlaceholderCount(entry.source)
		if count <= bestCount then
			continue
		end
		local captures: { string } = { message:match(pattern) }
		local args: { string } = {}
		for index = 1, count do
			args[index] = captures[index]
		end
		bestCount = count
		bestSource = PlaceholderSource(entry.source)
		bestKey = entry.key
		bestArgs = args
	end
	return bestSource, bestKey, bestArgs
end

local function ApplyLabel(label: TextLabel, message: string, source: string?, key: string?, args: { string }?): ()
	label.AutoLocalize = false
	if source ~= nil and key ~= nil and key ~= "" and args ~= nil then
		local localizedArgs: { string } = {}
		for index, argument in args do
			localizedArgs[index] = LocalizeArgument(label, argument)
		end
		TranslationTool.CustomAutoLocalizeTextLabel(label, source, key, localizedArgs)
	else
		TranslationTool.RemoveCustomAutoLocalizeGui(label)
		label.Text = message
	end
end

local function ApplyButton(button: TextButton, message: string, source: string?, key: string?, args: { string }?): ()
	button.AutoLocalize = false
	if source ~= nil and key ~= nil and key ~= "" and args ~= nil then
		local localizedArgs: { string } = {}
		for index, argument in args do
			localizedArgs[index] = LocalizeArgument(button, argument)
		end
		TranslationTool.CustomAutoLocalizeTextButton(button, source, key, localizedArgs)
	else
		TranslationTool.RemoveCustomAutoLocalizeGui(button)
		button.Text = message
	end
end

local function ApplyText(target: TextLabel | TextButton | ImageButton, message: string): TextLabel | TextButton
	local source, key, args = FindFarmEntry(message)
	if target:IsA("ImageButton") then
		local label = target:WaitForChild("ContentText") :: TextLabel
		ApplyLabel(label, message, source, key, args)
		return label
	elseif target:IsA("TextLabel") then
		ApplyLabel(target, message, source, key, args)
		return target
	else
		ApplyButton(target, message, source, key, args)
		return target
	end
end

function FarmTextTool.Set(target: TextLabel | TextButton | ImageButton, message: string): ()
	local gui = ApplyText(target, message)
	if gui:IsA("TextLabel") then
		WatchScreenText(gui)
	end
end

function FarmTextTool.Remove(root: Instance): ()
	ReleaseGui(root)
	for _, gui in root:GetDescendants() do
		ReleaseGui(gui)
	end
end

return FarmTextTool
