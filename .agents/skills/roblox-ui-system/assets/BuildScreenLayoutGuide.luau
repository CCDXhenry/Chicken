-- 静态屏幕禁放参考构建器：仅在 Studio Edit 根据离线并集更新设计参考模板。
--!strict
local RunService = game:GetService("RunService")
export type DesignRect = { number }
local function Build(uiFolder: Folder, rectangles: { DesignRect }): Frame
 assert(RunService:IsStudio() and not RunService:IsRunning(), "Build only in Studio Edit")
 for _, rect in rectangles do
  assert(#rect == 4 and rect[1] == rect[1] and rect[2] == rect[2] and rect[3] == rect[3] and rect[4] == rect[4], "Invalid rectangle")
  assert(rect[1] >= 0 and rect[2] >= 0 and rect[3] <= 1920 and rect[4] <= 1080 and rect[3] > rect[1] and rect[4] > rect[2], "Rectangle outside canvas")
 end
 local previous = uiFolder:FindFirstChild("ScreenLayoutGuideFrame")
 assert(not previous or (previous:IsA("Frame") and previous:GetAttribute("ScreenLayoutGuideVersion") == 1), "Unowned guide name conflict")
 local root = Instance.new("Frame")
 root.Name = "ScreenLayoutGuideFrame"
 root.Size = UDim2.fromOffset(1920, 1080)
 root.BackgroundTransparency, root.BorderSizePixel, root.Active, root.ZIndex = 1, 0, false, 100
 root:SetAttribute("DesignOnly", true)
 root:SetAttribute("ScreenLayoutGuideVersion", 1)
 local areas = Instance.new("Frame")
 areas.Name, areas.Size = "ReservedAreasFrame", UDim2.fromScale(1, 1)
 areas.BackgroundTransparency, areas.BorderSizePixel, areas.Active, areas.ZIndex = 1, 0, false, 100
 areas.Parent = root
 for index, rect in rectangles do
  local frame = Instance.new("Frame")
  frame.Name = string.format("Reserved%02dFrame", index)
  frame.Position = UDim2.fromOffset(rect[1], rect[2])
  frame.Size = UDim2.fromOffset(rect[3] - rect[1], rect[4] - rect[2])
  frame.BackgroundColor3 = Color3.fromRGB(240, 51, 51)
  frame.BackgroundTransparency, frame.BorderSizePixel, frame.Active, frame.ZIndex = 0.45, 0, false, 100
  frame.Parent = areas
 end
 if previous then previous:Destroy() end
 root.Parent = uiFolder
 return root
end
return Build
