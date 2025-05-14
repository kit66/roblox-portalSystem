-- handle plot actions
local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local plotManager = require(script.Parent.ServerModules.PlotManager)
local requestPlot = replicatedStorage.request.requestPlot
local plots = workspace.plots

-- link plot to player
local function privatePlot(player)
	plotManager.assignPlot(plots, player)
end


local function spawnplot(player)
	return plotManager.returnPlot(plots, player)
end


requestPlot.OnServerInvoke = spawnplot
Players.PlayerAdded:Connect(privatePlot)