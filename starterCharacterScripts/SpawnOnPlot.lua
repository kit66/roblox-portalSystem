-- get plot and spawn player on it

local replicatedStorage = game:GetService("ReplicatedStorage")
local getPlot = replicatedStorage.request:WaitForChild("requestPlot")

local character = script.Parent

local plot = getPlot:InvokeServer()

character:SetPrimaryPartCFrame(CFrame.new(plot.spawnpoint.CFrame.X,plot.spawnpoint.CFrame.Y+2,plot.spawnpoint.CFrame.Z))