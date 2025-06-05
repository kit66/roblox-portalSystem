-- This script manages the teleport system and creates teleporters to other locations.
-- Stand on a teleporter and it will teleport you to another place.
-- Each teleporter has a capacity, and all players standing on it will be teleported together.

-- Define module tables for each subsystem
local portalManager = {} -- core teleport and timer logic
local portalInitializer = {}  -- init and configure portals
local guiInitializer = {} -- show and update GUI elements
local dataManager = {} -- save and load player data


-- defines services
local dataStoreS = game:GetService("DataStoreService")
local teleportS = game:GetService("TeleportService")
local playersS = game:GetService("Players")
local replicatedStorageS = game:GetService("ReplicatedStorage")
local runS    = game:GetService("RunService")
local marketPlaceS = game:GetService("MarketplaceService")
local badgeS = game:GetService("BadgeService")



-- define data store with name "money"
local moneyDS = dataStoreS:GetDataStore("money")

-- default values if the developer doesn't set the input
local defaultValues = {
	maxPartySize = 4,
	timeUntilTeleport = 15,
	moneyReward = 1
}

-- 1) money system

-- init the player money stat for the leaderboard
function dataManager.initMoney(player)
	-- leaderstats folder enables Roblox to show leaderboard in up-right corner
	local leaderboard = Instance.new("Folder")
	leaderboard.Name = "leaderstats"
	leaderboard.Parent = player

	-- init IntValue to track player money. Default zero
	local money = Instance.new("IntValue")
	money.Name = "money"
	money.Value = 0
	money.Parent = leaderboard
end


-- get player money instance, if not - create leaderstats
function dataManager:getMoney(player)
	-- check if player already have "leaderstats" instance
	if not player:FindFirstChild("leaderstats") then
		self.initMoney(player)
	end
	return player.leaderstats.money
end


-- add money to player
function dataManager:addMoney(player, count)
	-- get money from "leaderstats". Create "leaderstats" if not exits
	local money = self:getMoney(player)
	-- add specific amount
	money.Value += count
end


--add specific amount money to every player in the list
function dataManager:addMoneyList(playerList, count)
	for _, player in ipairs(playerList) do
		self:addMoney(player, count)
	end
end

-- 2) storage system

-- save player money when they leave the game
function dataManager:saveData(player)
	-- use userId as unique DS key for every player
	local key = player.UserId
	-- get player current money value
	local moneyValue = self:getMoney(player).Value

	-- use SetAsync to save data (only on "PlayerRemoving" trigger to minimize contention)
	local success, err = pcall(function()
		moneyDS:SetAsync(key, moneyValue)
	end)

	if not success then
		warn("Failed to save money. userID:", key ," error:", tostring(err))
		return
	end
end
-- enable data save func when player if removed from the game (exit, kick)
playersS.PlayerRemoving:Connect(function(player: Player)
	dataManager:saveData(player)
end)


-- load player money when they join the game
function dataManager:loadData(player)
	-- use userId as unique DS key for every player
	local key = player.UserId
	--- default value if player don't have data in DS
	local moneyValue = 0

	-- try to fetch money from DS; kick on failure to prevent desynced play
	local success, err = pcall(function()
		moneyValue = moneyDS:GetAsync(key)
	end)
	if not success then
		warn("Failed to load money. userID:", key ," error:", tostring(err))
		player:Kick("Error occured. Please, rejoin the game")
		return
	end

	-- get money from "leaderstats". Create "leaderstats" if not exits
	local money = self:getMoney(player)
	money.Value = moneyValue
end
-- enable data load func when player if added to the game
playersS.PlayerAdded:Connect(function(player)
	-- delay to let character and leaderstats load
	task.wait(1)
	dataManager:loadData(player)
end)

-- 3) teleport system

-- init portal Gui methods (party count, timer, show/delete Gui)
function guiInitializer.initGui(guiInstance:ScreenGui)

	local gui = {
		guiInstance = guiInstance
	}

	-- update every players Gui with current party size
	function gui:updatePartyCount(players, partyCount, maxPartySize)
		for _,player in ipairs(players) do
			local gui = player.PlayerGui:WaitForChild(self.guiInstance.Name)
			gui.playersCount.Text = partyCount.."/"..maxPartySize
		end
	end

	-- update every players Gui countdown before teleport
	function gui:updateTimer(players, timeLeft)
		for _,player in ipairs(players) do
			local gui = player.PlayerGui:WaitForChild(self.guiInstance.Name)
			gui.timer.Text = timeLeft.."s"
		end
	end

	-- clone gui template into the player
	function gui:showGui(player)
		self.guiInstance:Clone().Parent = player.PlayerGui
	end

	-- delete the portal Gui for a player
	function gui:deleteGui(player)
		player.PlayerGui:WaitForChild(self.guiInstance.Name):Destroy()	
	end

	return gui
end



-- create teleport controller that handle entry, countdown, rewards, and teleport
function portalInitializer.initTeleport(placeID:NumberValue, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
	-- build the portal object with settings and state
	local portal = {
		gui = guiInitializer.initGui(guiInstance),

		-- set default values if it not given
		maxPartySize = maxPartySize or defaultValues.maxPartySize,
		timeUntilTeleport = timeUntilTeleport or defaultValues.timeUntilTeleport,
		placeID = placeID,

		teleporting = false,
		playersList = {}
	}

	-- start or resume the teleport countdown when someone inside.
	function portal:manageTimer()
		if self.playersList == 0 or self.teleporting then 
			return
		end
		
		self.teleporting = true
		-- reward players and update Gui each second. Stop if nobody in teleport
		for i=self.timeUntilTeleport,0,-1 do
			task.wait(1) -- wait before check to avoid join/exit farm

			-- abort if everyone left
			if #self.playersList == 0 then
				self.teleporting = false
				return
			end

			self.gui:updateTimer(self.playersList, i)
			dataManager:addMoneyList(self.playersList, defaultValues.moneyReward)
		end

		-- prepare teleport parameters for this party
		local tData = {
			playerCount = #self.playersList
		}
		local tOptions = Instance.new("TeleportOptions")
		tOptions.ShouldReserveServer = true
		tOptions:SetTeleportData(tData)

		-- teleport players to another place
		teleportS:TeleportAsync(self.placeID, self.playersList, tOptions)
		self.teleporting = false -- reset state to start new teleportation
	end

	-- add/remove players from playerList by checking overlapping
	function portal:manageParty(overlappingPlayers)
		-- remove players who left the portal
		for i, player in ipairs(self.playersList) do
			if overlappingPlayers[player] ~= nil  then
				continue
			end

			table.remove(self.playersList, i)
			self.gui:deleteGui(player)
			self.gui:updatePartyCount(self.playersList, #self.playersList, self.maxPartySize)
			self:manageTimer()
		end

		-- add players who joined the portal and teleport has capasity
		for player, _ in pairs(overlappingPlayers) do
			
			if table.find(self.playersList,player) == nil and #self.playersList < self.maxPartySize then
				table.insert(self.playersList, player)
				self.gui:showGui(player)
				self.gui:updatePartyCount(self.playersList, #self.playersList, self.maxPartySize)
				self:manageTimer()
			end
		end

	end
	return portal
end


local overlapParams = OverlapParams.new()
local activePortals = {}

-- main function that register part as a teleport with its settings
function portalManager.manageTeleport(portalInstance:Instance, placeID:String, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
	-- init portal logic (Gui, timer, capacity)
	local portal = portalInitializer.initTeleport(placeID,guiInstance, maxPartySize, timeUntilTeleport) 
	-- track part and portal to check overlapping
	table.insert(activePortals,
		{portalInstance = portalInstance,
			portal = portal})
end

-- every frame check who inside each portal
runS.Heartbeat:Connect(function()
	for _, portal in ipairs(activePortals) do
		-- get all parts that overlapping portal
		local overlapping = workspace:GetPartsInPart(portal.portalInstance, overlapParams)
		local overlappingPlayers = {}

		-- get map of players that overplapping the portal
		for _, part in ipairs(overlapping) do
			local char = part:FindFirstAncestorWhichIsA("Model") -- check only "model" instances to optimize loop
			if not char then
				continue
			end

			local player = playersS:GetPlayerFromCharacter(char)
			if player then
				overlappingPlayers[player] = true
			end
		end
		portal.portal:manageParty(overlappingPlayers)
	end
end)


-- 4) badge system

local purchaseBadgeId = 3225353430882368


-- give badge to player
local function giveBadge(player, badgeId)
	-- get badge info
	local success, badgeInfo = pcall(function()
		return badgeS:GetBadgeInfoAsync(badgeId)
	end)
	if not success then
		warn("GetBadgeInfo error:", badgeInfo)
		return
	end

	-- if not active badge - return
	if not badgeInfo.IsEnabled then
		return
	end
	
	-- Try to award the badge
	local awardSuccess, result = pcall(function()
		return badgeS:AwardBadge(player.UserId, badgeId)
	end)
	if not awardSuccess or not result then
		warn("giveBadge error:", result)
	end
end



-- 5) shop system 

-- products table
local products = {
	coins5000 = 3297475576,
	coins400 = 3297566965
}

-- map for each product to a function for handling purchases 
local makePurchare = {
	[products.coins5000] = function(player)
		dataManager:addMoney(player, 5000)
	end,
	[products.coins400] = function(player)
		dataManager:addMoney(player, 400)
	end,
}

-- when player trigger the shop prompt - open purchase
local proximityShop = workspace.shop.ProximityPrompt

proximityShop.Triggered:Connect(function(player)
	marketPlaceS:PromptProductPurchase(player, products.coins5000) 
end)

local proximitySmallShop = workspace.smallShop.ProximityPrompt

proximitySmallShop.Triggered:Connect(function(player)
	marketPlaceS:PromptProductPurchase(player, products.coins400) 
end)



-- handle purchases
local function process(info)
	-- theck that the player is still in game
	local player = playersS:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- look up the handler for this product
	local purchareFunction = makePurchare[info.ProductId]
	if not purchareFunction then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- run purchase handler
	local succsess, result = pcall(purchareFunction, player)
	if not succsess then
		warn("error while purcharing", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Checking if player already has the badge is not necessary
	giveBadge(player, purchaseBadgeId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

marketPlaceS.ProcessReceipt = process




-------------------------------------------------------------------
-- example
--  make portals from the folder teleport to different locations using default settings

local portalFolders = workspace.portals

-- make portal from model if model have instance "teleportZone"
function initPortal(portal, placeID)
	if not portal:IsA("Model") then
		return
	end

	local teleportZone = portal:FindFirstChild("teleportZone")
	if teleportZone == nil then 
		warn("Model:", portal.Name, "in", portal.Parent, "doesn't have instance: teleportZone - SKIP")	
		return
	end

	portalManager.manageTeleport(teleportZone,placeID,replicatedStorageS.portalStorage.partyGui)

end

-- initialize all portals in folder
function initPortals(portalFolder, placeId)

	for _, portal in ipairs(portalFolder:GetDescendants()) do
		initPortal(portal, placeId.Value)
	end
end

-- get folders with properties "placeId"
function initPortalFolders()
	for _, portalFolder in ipairs(portalFolders:GetDescendants()) do

		if not  portalFolder:IsA("Folder") then
			return
		end

		local placeId = portalFolder:FindFirstChild("placeID")
		if placeId == nil then
			warn("placeID is not declare in folder:",portalFolder.Name,"- SKIP FOLDER")
			continue
		end

		initPortals(portalFolder, placeId)
	end
end


initPortalFolders()

-- use only one line to create teleporter

portalManager.manageTeleport(workspace.bigWhitePortal.teleportZone, "130643888530121", replicatedStorageS.portalStorage.partyGui, 2, 7) -- all settings (2 capacity, 7 seconds)

portalManager.manageTeleport(workspace.bigRedPortal.teleportZone, "94142630952968", replicatedStorageS.portalStorage.partyGui, nil, 40) -- default capacity, 11 seconds

portalManager.manageTeleport(workspace.bigGreenPortal.teleportZone, "72467583695069", replicatedStorageS.portalStorage.partyGui) -- default time and size