-- define module for each subsystem
local portalManager = {} -- teleport and timer logic
local portalInitializer = {}  -- portal init
local guiInitializer = {} -- gui init
local dataManager = {} -- data manipulation

-- define services
local dataStoreS = game:GetService("DataStoreService")
local teleportS = game:GetService("TeleportService")
local playersS = game:GetService("Players")
local replicatedStorageS = game:GetService("ReplicatedStorage")
local runS    = game:GetService("RunService")
local marketPlaceS = game:GetService("MarketplaceService")
local badgeS = game:GetService("BadgeService")


-- define dataStore
local moneyDS = dataStoreS:GetDataStore("money")

-- default values if not setted
local defaultValues = {
	maxPartySize = 4,
	timeUntilTeleport = 15,
	moneyReward = 1
}

-- 1) money system

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
	for _, player in ipairs(playerList) do
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
playersS.PlayerRemoving:Connect(function(player: Player)
	dataManager:saveData(player)
end)


-- load data from dataStore
function dataManager:loadData(player)
	-- use user ID as unique key for dataStore
	local key = player.UserId
	-- default value if data not found or new player
	local moneyValue = 0

	-- get data from dataStore. Kick if not succsess
	local success, err = pcall(function()
		moneyValue = moneyDS:GetAsync(key)
	end)
	if not success then
		warn("Failed to load money. userID:", key ," error:", tostring(err))
		player:Kick("Error occured. Please, rejoin the game")
		return
	end

	-- get player money
	local money = self:getMoney(player)
	money.Value = moneyValue
end
playersS.PlayerAdded:Connect(function(player)
	-- delay to let player load before loading data
	task.wait(1)
	dataManager:loadData(player)
end)

-- 3) teleport system

-- init Gui methods (party counter, timer, gui manipulation)
function guiInitializer.initGui(guiInstance:ScreenGui)

	local gui = {
		guiInstance = guiInstance
	}

	-- update player count in GUI every player
	function gui:updatePartyCount(players, partyCount, maxPartySize)
		for _,player in ipairs(players) do
			local gui = player.PlayerGui:WaitForChild(self.guiInstance.Name)
			gui.playersCount.Text = partyCount.."/"..maxPartySize
		end
	end

	-- update portal timer in GUI on every player
	function gui:updateTimer(players, timeLeft)
		for _,player in ipairs(players) do
			local gui = player.PlayerGui:WaitForChild(self.guiInstance.Name)
			gui.timer.Text = timeLeft.."s"
		end
	end

	-- clone gui to the player
	function gui:showGui(player)
		self.guiInstance:Clone().Parent = player.PlayerGui
	end

	-- delete gui from the player
	function gui:deleteGui(player)
		player.PlayerGui:WaitForChild(self.guiInstance.Name):Destroy()	
	end

	return gui
end



-- init teleport with entry, countdown, rewards and teleport handlers
function portalInitializer.initTeleport(placeID:number, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
	-- create teleport object from params
	local portal = {
		gui = guiInitializer.initGui(guiInstance),

		-- default values if not given
		maxPartySize = maxPartySize or defaultValues.maxPartySize,
		timeUntilTeleport = timeUntilTeleport or defaultValues.timeUntilTeleport,
		placeID = placeID,

		teleporting = false,
		playersList = {}
	}

	-- start/end teleport
	function portal:manageTimer()
		if self.playersList == 0 or self.teleporting then 
			return
		end
		
		self.teleporting = true
		-- reward players each second. stop if teleport is emptyteleport
		for i=self.timeUntilTeleport,0,-1 do
			task.wait(1) -- wait before check to avoid join/exit spam

			-- teleport is empty
			if #self.playersList == 0 then
				self.teleporting = false
				return
			end

			self.gui:updateTimer(self.playersList, i)
			dataManager:addMoneyList(self.playersList, defaultValues.moneyReward)
		end

		-- init teleport parameters
		local tData = {
			playerCount = #self.playersList
		}
		local tOptions = Instance.new("TeleportOptions")
		tOptions.ShouldReserveServer = true
		tOptions:SetTeleportData(tData)

		-- do teleportation
		teleportS:TeleportAsync(self.placeID, self.playersList, tOptions)
		-- reset teleport state
		self.teleporting = false
	end

	-- add/remove player when start/end overlapping
	function portal:manageParty(overlappingPlayers)
		-- remove form party if not in overlapping list
		for i, player in ipairs(self.playersList) do
			if overlappingPlayers[player] ~= nil  then
				continue
			end

			table.remove(self.playersList, i)
			self.gui:deleteGui(player)
			self.gui:updatePartyCount(self.playersList, #self.playersList, self.maxPartySize)
			self:manageTimer()
		end

		-- add to party if new player in overlapping
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

-- main function that make portal from instance
function portalManager.manageTeleport(portalInstance:Instance, placeID:number, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
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

-- map of handlers for each product
local makepurchase = {
	[products.coins5000] = function(player)
		dataManager:addMoney(player, 5000)
	end,
	[products.coins400] = function(player)
		dataManager:addMoney(player, 400)
	end,
}

-- tiggers for purchase
workspace.shop.ProximityPrompt.Triggered:Connect(function(player)
	marketPlaceS:PromptProductPurchase(player, products.coins5000) 
end)

workspace.smallShop.ProximityPrompt.Triggered:Connect(function(player)
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
	local purchaseFunction = makepurchase[info.ProductId]
	if not purchaseFunction then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- run handler
	local succsess, result = pcall(purchaseFunction, player)
	if not succsess then
		warn("error while purchasing", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	giveBadge(player, purchaseBadgeId) -- checking if player already has badge - not necessary
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

portalManager.manageTeleport(workspace.bigWhitePortal.teleportZone, 130643888530121, replicatedStorageS.portalStorage.partyGui, 2, 7) -- all settings (2 capacity, 7 seconds)

portalManager.manageTeleport(workspace.bigRedPortal.teleportZone, 94142630952968, replicatedStorageS.portalStorage.partyGui, nil, 40) -- default capacity, 11 seconds

portalManager.manageTeleport(workspace.bigGreenPortal.teleportZone, 72467583695069, replicatedStorageS.portalStorage.partyGui) -- default time and size