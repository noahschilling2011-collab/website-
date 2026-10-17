--!strict
-- Compute: GPU-Katalog für Phase 1 (Tier 1-3 + Start-Laptop).
-- GPU-Server, Cluster, Rechenzentren und Cloud-Miete kommen in Phase 4 als eigene Systeme.

export type GPUDef = {
	id: string,
	label: string,
	tier: string,
	price: number,
	throughput: number, -- Compute-Einheiten pro Sekunde
	vram: number, -- GB
	powerCost: number, -- $ pro Compute-Einheit (Strom); bessere Hardware = billiger pro Arbeit
	starter: boolean?, -- Start-Hardware: belegt keinen Rack-Slot, nicht verkaufbar
}

local HardwareConfig = {}

HardwareConfig.GPUS = {
	{
		id = "laptop",
		label = "Old Laptop GPU",
		tier = "Starter",
		price = 0,
		throughput = 0.5,
		vram = 6,
		powerCost = 32,
		starter = true,
	},
	{ id = "consumer", label = "Consumer GPU", tier = "Tier 1", price = 2_500, throughput = 1, vram = 12, powerCost = 26 },
	{
		id = "workstation",
		label = "Workstation GPU",
		tier = "Tier 2",
		price = 14_000,
		throughput = 3.2,
		vram = 48,
		powerCost = 22,
	},
	{
		id = "accelerator",
		label = "AI Accelerator",
		tier = "Tier 3",
		price = 60_000,
		throughput = 9,
		vram = 80,
		powerCost = 18,
	},
} :: { GPUDef }

table.insert(HardwareConfig.GPUS, {id="datacenter", label="HBM Datacenter GPU", tier="Tier 4", price=180000, throughput=28, vram=192, powerCost=13})
table.insert(HardwareConfig.GPUS, {id="superpod", label="Eight-GPU Compute Pod", tier="Tier 5", price=1200000, throughput=200, vram=1536, powerCost=10})
-- GPU rack slots and the thermal budget follow the office stage (CORE_SPEC 2.1; office index 1 = Garage Lab):
-- slots 3 / 6 / 12 / 24 / 48 (x1.5 with Distributed Cluster), thermal 20 x {0.5, 1, 2, 3, 4} per cooling level.
HardwareConfig.STAGE_SLOTS = { 3, 6, 12, 24, 48 }
HardwareConfig.STAGE_THERMAL = { 0.5, 1, 2, 3, 4 }
local function stageOf(empire: any): number
	return math.clamp(math.floor(tonumber(empire.office) or 1), 1, #HardwareConfig.STAGE_SLOTS)
end
function HardwareConfig.slots(empire: any): number
	local research = if typeof(empire.research) == "table" then empire.research else {}
	return math.floor(HardwareConfig.STAGE_SLOTS[stageOf(empire)] * (if research.cluster then 1.5 else 1))
end
HardwareConfig.RACK_SLOTS = 6 -- Garagen-Rack. später (Phase 4): Serverräume mit Strom/Kühlung
function HardwareConfig.thermal(empire: any,throughput: number): number
	local cooling=(empire.infrastructure and empire.infrastructure.cooling) or 1
	local budget=20*HardwareConfig.STAGE_THERMAL[stageOf(empire)]*cooling
	return math.min(1,budget/math.max(1,throughput))
end
HardwareConfig.SELL_REFUND = 0.5
HardwareConfig.SERVE_POWER = 0.025 -- $ per compute unit per second while any model is live (MarketService.tick; ComputeApp shows it)
HardwareConfig.TFLOPS_PER_UNIT = 35 -- nur für die Anzeige

function HardwareConfig.getGPU(id: string): GPUDef?
	for _, gpu in HardwareConfig.GPUS do
		if gpu.id == id then
			return gpu
		end
	end
	return nil
end

return HardwareConfig
