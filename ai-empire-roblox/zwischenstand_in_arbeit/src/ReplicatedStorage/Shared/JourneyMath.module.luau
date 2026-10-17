--!strict
local ModelMath=require(script.Parent.ModelMath)
local ModelConfig=require(script.Parent.Config.ModelConfig)
local Format=require(script.Parent.Format)
local Journey={}
-- lab request #2 (menu package): DESIGN / TRAIN open the Model Studio directly (Computer.open(app, section))
Journey.STEPS={
 {id="data",label="DATA",app="data",title="Get training data",body="Data Operations · scrape free data or buy a pack. Data quantity and quality determine what your AI learns."},
 {id="compute",label="COMPUTE",app="compute",title="Check your compute",body="GPU control · your laptop can train a 100M model. Larger models need more VRAM; more GPU throughput shortens training."},
 {id="design",label="DESIGN",app="lab",section="design",title="Design your model",body="Model Architecture · choose a name, size, focus and recipe. Start small, then increase size when data and hardware support it."},
 {id="train",label="TRAIN",app="lab",section="train",title="Train with your own data",body="Training Control · start the run, watch loss and progress, and respond to training decisions."},
 {id="evaluation",label="EVALUATE",app="lab",section="evaluation",title="Evaluate your model",body="Evaluation Lab · compare coding, reasoning, math, creativity, knowledge and reliability before launch."},
 {id="release",label="LAUNCH",app="lab",section="release",title="Release your model",body="Deployment Studio · choose subscription and API prices, target customers and marketing, then launch."},
 {id="grow",label="GROW",app="market",title="Grow and improve",body="Growth · users and API customers pay for your live model. Hire a team and research improvements for the next generation."},
}
function Journey.latest(data: any,trainedOnly: boolean?): any
 for i=#data.modelOrder,1,-1 do local m=data.models[data.modelOrder[i]];if m and m.status~="training" and (not trainedOnly or m.status=="trained") then return m end end
 return nil
end
function Journey.progress(data: any,selection: any?): any
 local size=ModelConfig.getSize(if selection then selection.sizeId else "s100m") or ModelConfig.SIZES[1]
 local stock=ModelMath.dataSummary(data.data);local fleet=ModelMath.fleet(data.gpus)
 local released=data.stats.modelsReleased>0;local trained=data.stats.modelsTrained>0
 local done={stock.total>=ModelConfig.TRAINING.minTokens or trained or released,fleet.vram>=size.vram and fleet.throughput>0 or trained or released,data.training~=nil or trained or released,trained or released,data.empire.quests.journey_evaluation==true or released,released,released and data.stats.totalRevenue>0}
 local index=7;for i=1,7 do if not done[i] then index=i;break end end
 if data.training then index=4 end
 local missing=math.max(0,size.vram-fleet.vram);local hint=""
 if missing>0 then hint=string.format("%s needs %d GB more VRAM · open Lab → GPUs",size.label,missing)
 elseif stock.total<ModelConfig.TRAINING.minTokens then hint="Collect at least "..Format.tokens(ModelConfig.TRAINING.minTokens).." tokens before training."
 elseif size.id=="s7b" and not data.empire.research.frontier then hint="7B requires Frontier Architecture research in Company."
 else hint=string.format("%s · %d GB VRAM ready · %s tokens · %.0f%% quality",size.label,fleet.vram,Format.tokens(stock.total),stock.quality*100) end
 return {index=index,done=done,step=Journey.STEPS[index],hint=hint,missingVram=missing,complete=done[7]}
end
return Journey
