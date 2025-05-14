local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local WeaponDataStore = DataStoreService:GetDataStore("prog")
local MoneyDataStore = DataStoreService:GetOrderedDataStore("money")
local Run = game:GetService("RunService")

local PlotManager = require(script.Parent.ServerModules.PlotManager)

local dataloaded = false

-- set data to storage
local function serialize(player)
	if dataloaded then
		local plot = PlotManager.returnPlot(workspace.plots,player)
		
		local key = player.UserId
		local data = {}
		
		-- set data for every weapon in game
		for _,weapon in ipairs(plot.LevelData:GetChildren()) do
			local name = weapon.Name
			data[name] = weapon.Value
		end
		
		local success, err = pcall(function()
			print(data)
			MoneyDataStore:SetAsync(key,player.leaderstats.money.Value)
			WeaponDataStore:SetAsync(key, data)
			end)



		if not success then
			warn("Data could not be set." .. tostring(err))
			return
		end
	else
		warn("Data has not been loaded.")
		return
	end
end

-- load data from storage
local function deserialize(player)
	local plot = PlotManager.returnPlot(workspace.plots,player)
	local key = player.UserId
	
	local moneyData
	local data
	local globalData
	local success, err

		
	success, err = pcall(function()
		moneyData = MoneyDataStore:GetAsync(key)
		data = WeaponDataStore:GetAsync(key)
	end)
		if not success then
		warn("Failed to read data." .. tostring(err))

		player:Kick("Failed to read data. Please rejoin the game.")

		return
	else
	end
	
	-- get level for every weapon in a game
	if data then
		player.leaderstats.money.Value = moneyData
		for weaponName,level in data do
			local lvl = plot.LevelData:FindFirstChild(weaponName)
			if lvl then
				lvl.Value = level
			end
		end
		
		dataloaded = true
		return data,moneyData
	else
		dataloaded = true
		return {}
	end
end

-- save data and unlink plot from player
local function unloadData(player)
	local plot = PlotManager.returnPlot(workspace.plots,player)
	serialize(player)
	plot.LuckyBlock.Transparency = 1
	plot.LuckyBlock.CanCollide = false
	plot.owner.Value = ""
	for _,weapon in ipairs(plot.LevelData:GetChildren())	do
		weapon.Value = 1
	end
end

Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	deserialize(player)
	end)
Players.PlayerRemoving:Connect(unloadData)


game:BindToClose(function() -- (only needed inside Studio)
	if Run:IsStudio() then -- (only needed inside Studio)
		wait(3) -- for setAsync
	end
end)