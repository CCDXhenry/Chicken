-- 业务生命周期工具：统一管理连接、任务、缓动及临时实例，不依赖或修改 Core
--!strict
local LifecycleTool = {}
LifecycleTool.__index = LifecycleTool

export type Lifecycle = typeof(setmetatable(
	{} :: {
		alive: boolean,
		connections: { RBXScriptConnection },
		threads: { [thread]: boolean },
		instances: { [Instance]: boolean },
		tweens: { [Tween]: RBXScriptConnection },
	},
	LifecycleTool
))

function LifecycleTool.new(): Lifecycle
	return setmetatable({ alive = true, connections = {}, threads = {}, instances = {}, tweens = {} }, LifecycleTool)
end

function LifecycleTool.Connect(self: Lifecycle, connection: RBXScriptConnection): RBXScriptConnection
	if self.alive then
		table.insert(self.connections, connection)
	else
		connection:Disconnect()
	end
	return connection
end

function LifecycleTool.Own(self: Lifecycle, instance: Instance): ()
	if self.alive then
		self.instances[instance] = true
		instance.Destroying:Once(function(): ()
			self.instances[instance] = nil
		end)
	else
		instance:Destroy()
	end
end

function LifecycleTool.Play(self: Lifecycle, tween: Tween): ()
	if not self.alive then
		tween:Destroy()
		return
	end
	if not self.tweens[tween] then
		self.tweens[tween] = tween.Completed:Connect(function(): ()
			local connection = self.tweens[tween]
			if connection then
				connection:Disconnect()
				self.tweens[tween] = nil
			end
		end)
	end
	tween:Play()
end

function LifecycleTool.Delay(self: Lifecycle, seconds: number, callback: () -> ()): ()
	if not self.alive then
		return
	end
	local pending: thread
	pending = task.delay(seconds, function()
		self.threads[pending] = nil
		if self.alive then
			callback()
		end
	end)
	self.threads[pending] = true
end

function LifecycleTool.Spawn(self: Lifecycle, callback: () -> ()): ()
	if not self.alive then
		return
	end
	local pending: thread
	pending = coroutine.create(function()
		callback()
		self.threads[pending] = nil
	end)
	self.threads[pending] = true
	task.spawn(pending)
end

function LifecycleTool.Destroy(self: Lifecycle): ()
	if not self.alive then
		return
	end
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for pending in self.threads do
		if pending ~= coroutine.running() and coroutine.status(pending) ~= "dead" then
			task.cancel(pending)
		end
	end
	for tween, connection in self.tweens do
		connection:Disconnect()
		tween:Cancel()
		tween:Destroy()
	end
	for instance in self.instances do
		instance:Destroy()
	end
	table.clear(self.connections)
	table.clear(self.threads)
	table.clear(self.tweens)
	table.clear(self.instances)
end

return LifecycleTool
