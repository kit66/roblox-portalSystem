-- manage players coins 
local eventfolder = game:GetService("ReplicatedStorage").events
local Players = game:GetService("Players")

-- init player stat
local function onPlayerAdd(player)
	local leaderboard = Instance.new("Folder")
	leaderboard.Name = "leaderstats"
	leaderboard.Parent = player
	
	
	local money = Instance.new("IntValue")
	money.Name = "money"
	money.Value = 0
	money.Parent = leaderboard
end

-- add coin to player
local function collect(player,ID)
	local points = player.leaderstats.money
	points.Value += 10^ID/10
end



eventfolder.collected.OnServerEvent:Connect(collect)
Players.PlayerAdded:Connect(onPlayerAdd)