-- 农场声音工具模块：负责管理 ReplicatedStorage.Sounds 模板音效、3D 空间音效对象池回收与 SoundService 背景音乐播放
--!strict
local FarmSoundTool = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local soundService: SoundService = game:GetService("SoundService")

local soundsFolder: Folder? = nil
local localSoundAttachmentsPool: { Attachment } = {}
local soundsPools: { [Sound]: { Sound } } = {}

local soundGroups: Folder? = soundService:FindFirstChild("SoundGroups") :: Folder?
local bgmSoundGroup: SoundGroup? = if soundGroups then soundGroups:FindFirstChild("BGM") :: SoundGroup? else nil
local soundEffectsGroup: SoundGroup? = if soundGroups then soundGroups:FindFirstChild("SoundEffects") :: SoundGroup? else nil

local localSoundsPart: Part? = nil

-- 获取局部声音载体 Part
local function GetLocalSoundsPart(): Part
	if localSoundsPart and localSoundsPart.Parent then
		return localSoundsPart
	end
	local part = Instance.new("Part")
	part.Name = "FarmLocalSoundEffects"
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Position = Vector3.zero
	part.Parent = workspace
	localSoundsPart = part
	return part
end

-- 获取 Sounds 目录引用
local function GetSoundsFolder(): Folder?
	if soundsFolder and soundsFolder.Parent then
		return soundsFolder
	end
	local folder = replicatedStorage:FindFirstChild("Sounds")
	if folder and folder:IsA("Folder") then
		soundsFolder = folder
		return folder
	end
	return nil
end

-- 回收局部 Attachment
local function RestoreAttachment(attachment: Attachment)
	attachment.Parent = nil
	table.insert(localSoundAttachmentsPool, attachment)
end

-- 回收 Sound 实例
local function RestoreSound(sound: Sound, template: Sound)
	local parent = sound.Parent
	if parent and parent:IsA("Attachment") then
		RestoreAttachment(parent)
	end
	sound.Parent = nil
	local pool = soundsPools[template]
	if pool then
		table.insert(pool, sound)
	else
		sound:Destroy()
	end
end

-- 回收后的实例会带着上次的音量和播放速度，取出时先回到模板
local function ResetPlayback(sound: Sound, template: Sound): ()
	sound.Volume = template.Volume
	sound.PlaybackSpeed = template.PlaybackSpeed
	sound.TimePosition = 0
end

-- 从对象池获取或实例化 Sound
local function GetSoundFromPool(soundTemplate: Sound): Sound?
	local pool = soundsPools[soundTemplate]
	if pool == nil then
		local newPool: { Sound } = {}
		soundsPools[soundTemplate] = newPool
		soundTemplate.Destroying:Connect(function()
			local activePool = soundsPools[soundTemplate]
			if activePool then
				for _, sound in activePool do
					sound:Destroy()
				end
			end
			soundsPools[soundTemplate] = nil
		end)
		pool = newPool
	end

	local recycled = table.remove(pool)
	if recycled then
		ResetPlayback(recycled, soundTemplate)
		return recycled
	end

	local cloned: Sound? = soundTemplate:Clone()
	if not cloned then
		return nil
	end

	cloned.Ended:Connect(function()
		RestoreSound(cloned, soundTemplate)
	end)
	cloned.Stopped:Connect(function()
		RestoreSound(cloned, soundTemplate)
	end)

	return cloned
end

-- 获取或复用局部音效挂载的 Attachment
local function GetLocalSoundAttachment(): Attachment
	local attachment = table.remove(localSoundAttachmentsPool)
	if attachment then
		attachment.Parent = GetLocalSoundsPart()
		return attachment
	end
	local newAttachment = Instance.new("Attachment")
	newAttachment.Name = "LocalSoundAttachment"
	newAttachment.Parent = GetLocalSoundsPart()
	return newAttachment
end

-- 获取指定音效模板（从 ReplicatedStorage.Sounds）
function FarmSoundTool.GetSoundTemplate(soundName: string): Sound?
	local folder = GetSoundsFolder()
	if not folder then
		return nil
	end
	local child = folder:FindFirstChild(soundName)
	if child and child:IsA("Sound") then
		return child
	end
	return nil
end

-- 播放 2D 全局音效模板
function FarmSoundTool.PlayGlobal(soundTemplate: Sound, looped: boolean?, soundGroup: SoundGroup?): Sound?
	local sound = GetSoundFromPool(soundTemplate)
	if not sound then
		return nil
	end
	sound.SoundGroup = soundGroup or soundEffectsGroup
	sound.Looped = looped == true
	sound.Parent = soundService
	sound:Play()
	return sound
end

-- 播放 3D 局部空间音效模板
function FarmSoundTool.PlayLocal(soundTemplate: Sound, soundPosition: Vector3, looped: boolean?, soundGroup: SoundGroup?): Sound?
	local sound = GetSoundFromPool(soundTemplate)
	if not sound then
		return nil
	end
	local attachment = GetLocalSoundAttachment()
	sound.SoundGroup = soundGroup or soundEffectsGroup
	sound.Looped = looped == true
	attachment.WorldCFrame = CFrame.new(soundPosition)
	sound.Parent = attachment
	sound:Play()
	return sound
end

-- 按名称播放音效（统一便捷接口：自动按是否提供坐标切换 2D/3D）
function FarmSoundTool.Play(soundName: string, soundPosition: Vector3?, volumeMultiplier: number?): Sound?
	local template = FarmSoundTool.GetSoundTemplate(soundName)
	if not template then
		return nil
	end

	local sound: Sound? = nil
	if soundPosition then
		sound = FarmSoundTool.PlayLocal(template, soundPosition, false)
	else
		sound = FarmSoundTool.PlayGlobal(template, false)
	end

	if sound then
		local multiplier = if volumeMultiplier ~= nil then volumeMultiplier else 1
		sound.Volume = template.Volume * multiplier
		sound.PlaybackSpeed = template.PlaybackSpeed
	end

	return sound
end

-- 播放背景音乐（优先从 SoundService.BGM 获取）
function FarmSoundTool.PlayBGM(bgmInstanceOrName: (Sound | string)?): Sound?
	local bgm: Sound? = nil
	if typeof(bgmInstanceOrName) == "Instance" and bgmInstanceOrName:IsA("Sound") then
		bgm = bgmInstanceOrName
	elseif typeof(bgmInstanceOrName) == "string" then
		local foundInService = soundService:FindFirstChild(bgmInstanceOrName)
		if foundInService and foundInService:IsA("Sound") then
			bgm = foundInService
		else
			bgm = FarmSoundTool.GetSoundTemplate(bgmInstanceOrName)
		end
	else
		local defaultBGM = soundService:FindFirstChild("BGM")
		if defaultBGM and defaultBGM:IsA("Sound") then
			bgm = defaultBGM
		end
	end

	if not bgm then
		return nil
	end

	if bgmSoundGroup then
		bgm.SoundGroup = bgmSoundGroup
	end
	bgm.Looped = true
	bgm:Play()
	return bgm
end

-- 停止背景音乐
function FarmSoundTool.StopBGM(bgmInstanceOrName: (Sound | string)?)
	local bgm: Sound? = nil
	if typeof(bgmInstanceOrName) == "Instance" and bgmInstanceOrName:IsA("Sound") then
		bgm = bgmInstanceOrName
	elseif typeof(bgmInstanceOrName) == "string" then
		local found = soundService:FindFirstChild(bgmInstanceOrName)
		if found and found:IsA("Sound") then
			bgm = found
		end
	else
		local defaultBGM = soundService:FindFirstChild("BGM")
		if defaultBGM and defaultBGM:IsA("Sound") then
			bgm = defaultBGM
		end
	end

	if bgm then
		bgm:Stop()
	end
end

-- 设置背景音乐音量
function FarmSoundTool.SetBGMVolume(volume: number)
	if bgmSoundGroup then
		bgmSoundGroup.Volume = volume
	else
		local defaultBGM = soundService:FindFirstChild("BGM")
		if defaultBGM and defaultBGM:IsA("Sound") then
			defaultBGM.Volume = volume
		end
	end
end

-- 设置音效音量
function FarmSoundTool.SetSoundEffectVolume(volume: number)
	if soundEffectsGroup then
		soundEffectsGroup.Volume = volume
	end
end

return FarmSoundTool
