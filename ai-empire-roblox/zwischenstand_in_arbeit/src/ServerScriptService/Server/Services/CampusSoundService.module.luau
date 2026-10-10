--!strict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(ReplicatedStorage.Shared.Config.CampusAudioConfig)
local Service={}
function Service.play(parent: Instance,key: string)
 local id=Config.INTERACTIONS[key];if not id or id=="" then return end
 local sound=Instance.new("Sound");sound.Name="CampusSFX";sound.SoundId=id;sound.Volume=.12;sound.RollOffMinDistance=3;sound.RollOffMaxDistance=28;sound.RollOffMode=Enum.RollOffMode.InverseTapered;sound.Parent=parent;sound:Play()
 task.delay(8,function()if sound.Parent then sound:Destroy() end end)
end
return Service
