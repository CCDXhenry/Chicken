-- 声音池回归：带倍率播放后回池，下一次普通播放必须回到模板音量和播放速度
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local checks = 0
local function Check(condition: boolean, message: string): ()
	assert(condition, message)
	checks += 1
end

local function CreateSignal(): any
	local listeners: { () -> () } = {}
	return {
		Connect = function(_self: any, callback: () -> ())
			table.insert(listeners, callback)
			return { Disconnect = function() end }
		end,
		Fire = function()
			for _, callback in listeners do
				callback()
			end
		end,
	}
end

local function CreateSound(volume: number, playbackSpeed: number): any
	local sound = {
		Volume = volume,
		PlaybackSpeed = playbackSpeed,
		TimePosition = 0,
		Looped = false,
		SoundGroup = nil,
		Parent = nil,
		Ended = CreateSignal(),
		Stopped = CreateSignal(),
		Destroying = CreateSignal(),
	}
	function sound:IsA(className: string): boolean
		return className == "Sound"
	end
	function sound:Play() end
	function sound:Stop()
		self.Stopped.Fire()
	end
	function sound:Clone(): any
		return CreateSound(self.Volume, self.PlaybackSpeed)
	end
	function sound:Destroy()
		self.Destroying.Fire()
	end
	return sound
end

local template = CreateSound(0.5, 1)
local soundsFolder = {
	Parent = nil,
	FindFirstChild = function(_self: any, name: string): any
		if name == "Coin" then
			return template
		end
		return nil
	end,
	IsA = function(_self: any, className: string): boolean
		return className == "Folder"
	end,
}
local replicatedStorage = {
	FindFirstChild = function(_self: any, name: string): any
		if name == "Sounds" then
			return soundsFolder
		end
		return nil
	end,
}
soundsFolder.Parent = replicatedStorage
local soundService = {
	FindFirstChild = function(): any
		return nil
	end,
	IsA = function(_self: any, className: string): boolean
		return className == "SoundService"
	end,
}

local environment = setmetatable({
	game = {
		GetService = function(_self: any, name: string): any
			if name == "ReplicatedStorage" then
				return replicatedStorage
			end
			if name == "SoundService" then
				return soundService
			end
			error("unexpected service " .. name)
		end,
	},
	table = table,
	type = type,
	typeof = typeof,
	tostring = tostring,
	error = error,
	assert = assert,
	pairs = pairs,
	ipairs = ipairs,
	next = next,
	string = string,
	math = math,
	print = print,
}, { __index = _G })

local source = fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/FarmSoundTool.luau")
local Sound = luau.load(source, { environment = environment })()

local first = Sound.Play("Coin", nil, 0.2)
Check(first ~= nil, "scaled play returns a sound")
Check(first.Volume == 0.1, "0.5 template times 0.2 multiplier is 0.1")
first.PlaybackSpeed = 3
first.TimePosition = 4.5
first:Stop()

local second = Sound.Play("Coin")
Check(second == first, "stopped sound is reused from the pool")
Check(second.Volume == 0.5, "reused sound restores the template volume")
Check(second.PlaybackSpeed == 1, "reused sound restores the template playback speed")
Check(second.TimePosition == 0, "reused sound restarts at the beginning")

second:Stop()
local silent = Sound.Play("Coin", nil, 0)
Check(silent == first, "zero multiplier still reuses the pooled sound")
Check(silent.Volume == 0, "explicit zero multiplier is silence, not the template volume")

silent:Stop()
local restored = Sound.Play("Coin")
Check(restored.Volume == 0.5, "play after a zero multiplier returns to the template volume")

print("SoundPoolRegression passed:", checks, "checks; volume, speed and time position")
