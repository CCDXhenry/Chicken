--!strict
local ParticleExtension = {}
local runService: RunService = game:GetService("RunService")
local debris: Debris = game:GetService("Debris")

--模拟自动播放的粒子
type SimulatedAutoPlayingParticle = {
	particleEmitter: ParticleEmitter,
	emitInterval: number,
	emitTimer: number,
}

--模拟自动播放的特效
type SimulatedAutoPlayingEffect = {
	isPlaying: boolean,
	descendantAddedConnection: RBXScriptConnection,
	destroyingConnection: RBXScriptConnection,
	particleMap: { [ParticleEmitter]: SimulatedAutoPlayingParticle },
}

local simulatedAutoPlayingEffectMap: { [Instance]: SimulatedAutoPlayingEffect } = {}

local function GetWeldPart(particleInstance: PVInstance): BasePart?
	if particleInstance:IsA("BasePart") then
		return particleInstance
	end
	local model: Model = particleInstance :: Model
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end
	return particleInstance:FindFirstChildWhichIsA("BasePart", true)
end

local function PrepareAttachedParticleInstance(particleInstance: PVInstance, attachTo: BasePart)
	if particleInstance:IsA("BasePart") then
		particleInstance.Anchored = false
		particleInstance.Massless = true
	end
	for _, descendant: Instance in particleInstance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
		end
	end
	local weldPart: BasePart? = GetWeldPart(particleInstance)
	if weldPart == nil then
		return
	end
	local weldConstraint: WeldConstraint = Instance.new("WeldConstraint")
	weldConstraint.Part0 = attachTo
	weldConstraint.Part1 = weldPart
	weldConstraint.Parent = particleInstance
end

--播放粒子特效
function ParticleExtension.PlayParticleEffect(particleInstanceTemplate: PVInstance, emitCFrame: CFrame, attachTo: BasePart?)
	local particleInstance: PVInstance = particleInstanceTemplate:Clone()
	particleInstance:PivotTo(emitCFrame)
	if attachTo ~= nil then
		particleInstance.Parent = attachTo
		PrepareAttachedParticleInstance(particleInstance, attachTo)
	else
		particleInstance.Parent = workspace
	end
	local liftTime: number = 0
	for descendantIndex: number, descendant: Instance in particleInstance:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitCount: number? = descendant:GetAttribute("EmitCount") :: number?
			descendant:Emit(emitCount)
			if descendant.Lifetime.Max > liftTime then
				liftTime = descendant.Lifetime.Max
			end
		end
	end
	debris:AddItem(particleInstance, liftTime)
end

--模拟特效自动播放
function ParticleExtension.SimulateEffectAutoPlay(effect: Instance)
	local simulatedAutoPlayingEffect: SimulatedAutoPlayingEffect = simulatedAutoPlayingEffectMap[effect]
	if simulatedAutoPlayingEffect ~= nil then
		for particleEmitter: ParticleEmitter, simulatedAutoPlayingParticle: SimulatedAutoPlayingParticle in simulatedAutoPlayingEffect.particleMap do
			simulatedAutoPlayingParticle.emitTimer = 0
		end
		simulatedAutoPlayingEffect.isPlaying = true
		return
	end
	local simulatedAutoPlayingParticleMap: { [ParticleEmitter]: SimulatedAutoPlayingParticle } = {}
	local descendantAddedConnection: RBXScriptConnection = effect.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ParticleEmitter") then
			if simulatedAutoPlayingParticleMap[descendant] ~= nil then
				return
			end
			local emitInterval: number = 1 / descendant.Rate / descendant.TimeScale
			local simulatedAutoPlayingParticle: SimulatedAutoPlayingParticle = {
				particleEmitter = descendant,
				emitInterval = emitInterval,
				emitTimer = 0,
			}
			simulatedAutoPlayingParticleMap[descendant] = simulatedAutoPlayingParticle
		end
	end)
	for descendantIndex: number, descendant: Instance in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitInterval: number = 1 / descendant.Rate / descendant.TimeScale
			local simulatedAutoPlayingParticle: SimulatedAutoPlayingParticle = {
				particleEmitter = descendant,
				emitInterval = emitInterval,
				emitTimer = 0,
			}
			simulatedAutoPlayingParticleMap[descendant] = simulatedAutoPlayingParticle
		end
	end
	local destroyingConnection: RBXScriptConnection = effect.Destroying:Connect(function()
		ParticleExtension.StopSimulatingEffectAutoPlay(effect)
		simulatedAutoPlayingEffect.descendantAddedConnection:Disconnect()
		simulatedAutoPlayingEffect.destroyingConnection:Disconnect()
		simulatedAutoPlayingEffectMap[effect] = nil
	end)
	simulatedAutoPlayingEffect = {
		isPlaying = true,
		descendantAddedConnection = descendantAddedConnection,
		destroyingConnection = destroyingConnection,
		particleMap = simulatedAutoPlayingParticleMap,
	}
	simulatedAutoPlayingEffectMap[effect] = simulatedAutoPlayingEffect
end

--停止模拟特效自动播放
function ParticleExtension.StopSimulatingEffectAutoPlay(effect: Instance)
	local simulatedAutoPlayingEffect: SimulatedAutoPlayingEffect = simulatedAutoPlayingEffectMap[effect]
	if simulatedAutoPlayingEffect == nil then
		return
	end
	for particleEmitter: ParticleEmitter, simulatedAutoPlayingParticle: SimulatedAutoPlayingParticle in simulatedAutoPlayingEffect.particleMap do
		particleEmitter:Clear()
	end
	simulatedAutoPlayingEffect.isPlaying = false
end

local function OnRenderStepped(deltaTime: number)
	for effect: Instance, simulatedAutoPlayingEffect: SimulatedAutoPlayingEffect in simulatedAutoPlayingEffectMap do
		if simulatedAutoPlayingEffect.isPlaying then
			for particleEmitter: ParticleEmitter, simulatedAutoPlayingParticle: SimulatedAutoPlayingParticle in simulatedAutoPlayingEffect.particleMap do
				simulatedAutoPlayingParticle.emitTimer -= deltaTime
				local emitCount: number = 0
				while simulatedAutoPlayingParticle.emitTimer <= 0 do
					emitCount += 1
					simulatedAutoPlayingParticle.emitTimer += simulatedAutoPlayingParticle.emitInterval
				end
				if emitCount > 0 then
					particleEmitter:Emit(emitCount)
				end
			end
		end
	end
end

runService:BindToRenderStep(string.format("%s.RenderStepped", script.Name), Enum.RenderPriority.Camera.Value + 1, OnRenderStepped)

return ParticleExtension
