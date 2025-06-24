-- define module
local portalManager = {} -- teleport and timer logic
local portalInitializer = {}  -- portal init
local dataManager = {} -- data manipulation

-- define services
local dataStoreS = game:GetService("DataStoreService")
local playersS = game:GetService("Players")

-- define dataStore
local moneyDS = dataStoreS:GetDataStore("money")

playersS.PlayerRemoving:Connect(function(player: Player)
	dataManager:saveData(player)
end)

playersS.PlayerAdded:Connect(function(player)
	-- delay to let player load before loading data
	task.wait(1)
	dataManager:loadData(player)
end)

-- main function that make portal from instance
function portalManager.manageTeleport(portalInstance:Instance, placeID:number, maxPartySize:number, timeUntilTeleport:number)
	-- init portal logic (Gui events, timer, capacity)
	local portal = portalInitializer.initTeleport(placeID, maxPartySize, timeUntilTeleport)

	-- portal enter
	portalInstance.Touched:Connect(function(part)
		local char = part:FindFirstAncestorWhichIsA("Model") -- check only "model" instances to optimize loop
		if not char then
			return
		end

		-- get player who touched
		local player = playersS:GetPlayerFromCharacter(char)
		if not player then
			return
		end

		-- start teleport if first player
		portal:AddPlayer(player)
	end)
	
	-- portal exit
	portalInstance.TouchEnded:Connect(function(part)
		local char = part:FindFirstAncestorWhichIsA("Model") -- check only "model" instances to optimize loop
		if not char then
			return
		end

		-- get player who touched
		local player = playersS:GetPlayerFromCharacter(char)
		if not player then
			return
		end
		-- stop teleport if nobody in
		portal:RemovePlayer(player)
	end)
end