local dataStoreS = game:GetService("DataStoreService")
local moneyDS = dataStoreS:GetDataStore("money")

dataManager = {}

-- init money statistics for the player
function dataManager.initMoney(player)
	-- leaderstats - roblox gui in right top corner
	local leaderboard = Instance.new("Folder")
	leaderboard.Name = "leaderstats"
	leaderboard.Parent = player

	-- init money instance for player. Default zero
	local money = Instance.new("IntValue")
	money.Name = "money"
	money.Value = 0
	money.Parent = leaderboard
end

-- get player money instance, if not- create
function dataManager:getMoney(player)
	-- if player already have leaderstats
	if not player:FindFirstChild("leaderstats") then
		self.initMoney(player)
	end
	return player.leaderstats.money
end


-- add money to player
function dataManager:addMoney(player, count)
	-- get money instance
	local money = self:getMoney(player)
	money.Value += count
end


-- add money to everyone in the list
function dataManager:addMoneyList(playerList, count)
	for player, _ in pairs(playerList) do
		self:addMoney(player, count)
	end
end

-- 2) storage system

-- save data to dataStore
function dataManager:saveData(player)
	-- use user ID as unique key for dataStore
	local key = player.UserId
	-- get current player money
	local moneyValue = self:getMoney(player).Value

	-- save data
	local success, err = pcall(function()
		-- using SetAsync because only triggered when player leaves
		moneyDS:SetAsync(key, moneyValue)
	end)

	if not success then
		warn("Failed to save money. userID:", key ," error:", tostring(err))
		return
	end
end