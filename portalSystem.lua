-- SERVER SCRIPT
-------------------------------------------------------------------

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

-- define remote events
local showGuiEvent = replicatedStorageS.events:WaitForChild("showGui")
local removeGuiEvent = replicatedStorageS.events:WaitForChild("removeGui")
local updateTimerEvent = replicatedStorageS.events:WaitForChild("updateTimer")
local updatePlayerCountEvent = replicatedStorageS.events:WaitForChild("updatePlayerCount")



-- define dataStore
local moneyDS = dataStoreS:GetDataStore("money")

playersS.PlayerRemoving:Connect(function(player: Player)
	dataManager:saveData(player)
end)


-- load data from dataStore
function dataManager:loadData(player)
	-- use user ID as unique key for dataStore
	local key = player.UserId
	local moneyValue

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
	-- default value if data not found or new player
	money.Value = moneyValue or 0
end
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


-- USAGE EXAMPLE: SERVER SIDE TELEPORT INITIALIZATION
-------------------------------------------------------------------
--  make portals from the folder teleport to different locations using default settings
local portalFolders = workspace.portals

-- make portal from model if model have instance "teleportZone"
function initPortal(portal, placeID:number)
	if not portal:IsA("Model") then
		return
	end

	local teleportZone = portal:FindFirstChild("teleportZone")
	if teleportZone == nil then 
		warn("Model:", portal.Name, "in", portal.Parent, "doesn't have instance: teleportZone - SKIP")
		return
	end

	portalManager.manageTeleport(teleportZone,placeID)

end

-- initialize all portals in folder
function initPortals(portalFolder, placeId:number)

	for _, portal in ipairs(portalFolder:GetDescendants()) do
		initPortal(portal, placeId)
	end
end

-- get folders with properties "placeId"
function initPortalFolders()
	for _, portalFolder in ipairs(portalFolders:GetDescendants()) do

		if not portalFolder:IsA("Folder") then
			warn("not a folder:", portalFolder.Name,"- SKIP")
			continue
		end

		local placeId = portalFolder:FindFirstChild("placeID")
		if placeId == nil then
			warn("placeID is not declare in folder:", portalFolder.Name,"- SKIP FOLDER")
			continue
		end

		initPortals(portalFolder, placeId.value)
	end
end


initPortalFolders()

-- use only one line to create teleporter

portalManager.manageTeleport(workspace.bigWhitePortal.teleportZone, 130643888530121, 2, 7) -- all settings (2 capacity, 7 seconds)

portalManager.manageTeleport(workspace.bigRedPortal.teleportZone, 94142630952968, nil, 5) -- default capacity, 11 seconds

portalManager.manageTeleport(workspace.bigGreenPortal.teleportZone, 72467583695069) -- default time and size