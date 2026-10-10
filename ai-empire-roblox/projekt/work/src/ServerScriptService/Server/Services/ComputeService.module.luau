--!strict
-- Compute: GPUs kaufen/verkaufen. Das Rack hat RACK_SLOTS Plätze, der Start-Laptop belegt keinen.
-- Verkaufen während eines Trainings nur, solange der restliche VRAM den laufenden Job noch trägt.
-- Rack slots per office stage: HardwareConfig.slots (3 / 6 / 12 / 24 / 48, x1.5 with Distributed Cluster).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HardwareConfig = require(ReplicatedStorage.Shared.Config.HardwareConfig)
local ModelMath = require(ReplicatedStorage.Shared.ModelMath)
local ModelConfig = require(ReplicatedStorage.Shared.Config.ModelConfig)
local ServerTypes = require(script.Parent.Parent.Lib.ServerTypes)
local Guard = require(script.Parent.Parent.Lib.Guard)
local Remote = require(script.Parent.Parent.Lib.Remote)
local SessionService = require(script.Parent.SessionService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)

type Session = ServerTypes.Session

local ComputeService = {}

local function gpuFromPayload(payload: ServerTypes.Payload): HardwareConfig.GPUDef?
	local gpuId = Guard.id(payload.gpuId)
	local gpu = if gpuId then HardwareConfig.getGPU(gpuId) else nil
	if not gpu or gpu.starter then
		return nil
	end
	return gpu
end

local function buyGPU(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local gpu = gpuFromPayload(payload)
	if not gpu then
		return { ok = false, err = "BAD_INPUT" }
	end
	if ModelMath.fleet(session.data.gpus).slotsUsed >= HardwareConfig.slots(session.data.empire) then
		return { ok = false, err = "RACK_FULL" }
	end
	if not EconomyService.spend(session, gpu.price, "gpu") then
		return { ok = false, err = "NO_MONEY" }
	end
	session.data.gpus[gpu.id] = (session.data.gpus[gpu.id] or 0) + 1
	SessionService.markDirty(session)
	PlotService.refresh(session)
	return { ok = true }
end

local function sellGPU(session: Session, payload: ServerTypes.Payload): ServerTypes.Result
	local gpu = gpuFromPayload(payload)
	if not gpu then
		return { ok = false, err = "BAD_INPUT" }
	end
	if session.data.empire.projectJob then return {ok=false,err="PROJECT_ACTIVE"} end
	if session.data.training then
		-- allowed while the remaining VRAM still fits the running job (CORE_SPEC: GPU swaps when servers are full)
		local job = session.data.models[session.data.training.modelId or ""]
		local size = job and ModelConfig.getSize(job.sizeId)
		local left = table.clone(session.data.gpus)
		left[gpu.id] = (left[gpu.id] or 0) - 1
		if not size or ModelMath.fleet(left).vram < size.vram then
			return { ok = false, err = "TRAINING_ACTIVE" }
		end
	end
	local owned = session.data.gpus[gpu.id] or 0
	if owned <= 0 then
		return { ok = false, err = "NOT_OWNED" }
	end
	if owned > 1 then
		session.data.gpus[gpu.id] = owned - 1
	else
		(session.data.gpus :: any)[gpu.id] = nil -- Eintrag entfernen statt 0 speichern
	end
	EconomyService.grant(session, math.floor(gpu.price * HardwareConfig.SELL_REFUND), "gpusale")
	SessionService.markDirty(session)
	PlotService.refresh(session)
	return { ok = true }
end

local function setShare(s: any,p: any): any
	local share=Guard.number(p.share,.25,.9)
	if not share then return {ok=false,err="BAD_INPUT"} end
	s.data.empire.infrastructure.trainingShare=share;SessionService.markDirty(s);return {ok=true}
end
local function cooling(s: any,_p: any): any
	local level=s.data.empire.infrastructure.cooling
	if level>=8 then return {ok=false,err="MAX_COOLING"} end
	if not EconomyService.spend(s,math.floor(8000*1.7^(level-1)),"cooling") then return {ok=false,err="NO_MONEY"} end
	s.data.empire.infrastructure.cooling+=1;SessionService.markDirty(s);PlotService.refresh(s);return {ok=true}
end
function ComputeService.init()
	Remote.bind("SetComputeShare",{burst=3,perSecond=1,company=true},setShare)
	Remote.bind("UpgradeCooling",{burst=2,perSecond=.5,company=true},cooling)
	Remote.bind("BuyGPU", { burst = 4, perSecond = 2, company = true }, buyGPU)
	Remote.bind("SellGPU", { burst = 4, perSecond = 2, company = true }, sellGPU)
end

return ComputeService
