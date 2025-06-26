-- 1) SERVER SIDE
------------------------------------------------------
-- dataManager
------------------------------------------------------

local dataStoreS = game:GetService("DataStoreService")
local moneyDS = dataStoreS:GetDataStore("money")

dataManager = {}

-- init money statistics for the player
function dataManager._initMoney(player)
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
		self._initMoney(player)
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
	for _, player in pairs(playerList) do
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

return dataManager

-- PortalManager
------------------------------------------------------

local playersS = game:GetService("Players")

local portalModule = require(script.Parent.portalModule)

local PortalManager = {}

local function _getPlayerFromPart(part)
	local char = part:FindFirstAncestorWhichIsA("Model") -- check only "model" instances to optimize loop
	if not char then
		return nil
	end

	-- get player who touched
	local player = playersS:GetPlayerFromCharacter(char)
	if not player then
		return nil
	end

	return player
end

-- main function that make portal from instance
function PortalManager.manageTeleport(portalInstance:Instance, placeID:number, config)
	-- init portal logic (Gui events, timer, capacity)
	local portal = portalModule.New(placeID, config)

	-- portal enter
	portalInstance.Touched:Connect(function(part)
		local player = _getPlayerFromPart(part)
		if not player then
			return
		end

		-- start teleport if first player
		portal:AddPlayer(player)
	end)

	-- portal exit
	portalInstance.TouchEnded:Connect(function(part)
		-- get player who touched
		local player = _getPlayerFromPart(part)
		if not player then
			return
		end
		-- stop teleport if nobody in
		portal:RemovePlayer(player)
	end)
end

return PortalManager

-- portalModule
------------------------------------------------------

local teleportS = game:GetService("TeleportService")
local replicatedStorageS = game:GetService("ReplicatedStorage")

local dataManager = require(script.Parent.dataManager)

-- define remote events
local showGuiEvent = replicatedStorageS.events:WaitForChild("showGui")
local removeGuiEvent = replicatedStorageS.events:WaitForChild("removeGui")
local updateTimerEvent = replicatedStorageS.events:WaitForChild("updateTimer")
local updatePlayerCountEvent = replicatedStorageS.events:WaitForChild("updatePlayerCount")


-- create config type to verify that config is correct
type Config = {
	maxPartySize: number,
	timeUntilTeleport: number, 
	moneyReward: number
} 

-- use default if config not provided
local defaultConfig: Config = {
	maxPartySize = 4,
	timeUntilTeleport = 15,
	moneyReward = 1
}

local Portal = {}

-- create new portal
function Portal.New(placeID: number, config: Config)
	local self = setmetatable({}, {__index = Portal})
	self.placeID = placeID
	self.config = config or defaultConfig
	self.players = {}
	self.teleporting = false


	return self
end

-- add to players list if not and start teleportation
function Portal:AddPlayer(player)
	-- check if possible to add
	if not self:_playerIsInside(player) and #self.players < self.config.maxPartySize then
		table.insert(self.players, player)
	end
	
	-- start if not started
	if not self.teleporting and #self.players == 1 then
		self:StartTimer()
	end

	-- update gui
	showGuiEvent:FireClient(player)
	for _, iPlayer in pairs(self.players) do
		updatePlayerCountEvent:FireClient(iPlayer, #self.players, self.config.maxPartySize)
	end

end

-- remove player from list
function Portal:RemovePlayer(player)
	-- create new table with players without removed player
	local players = {}
	for _, iPlayer in ipairs(self.players) do
		if iPlayer == player then
			continue
		end
		table.insert(players, iPlayer)
	end

	-- update gui
	removeGuiEvent:FireClient(player)
	for _, iPlayer in ipairs(self.players) do
		updatePlayerCountEvent:FireClient(iPlayer, #self.players, self.config.maxPartySize)
	end
	-- set new list of players
	self.players = players
end

-- star timer teleportation
function Portal:StartTimer()
	self.teleporting = true
	
	local function _timer()
		for i=self.config.timeUntilTeleport,0,-1 do
			task.wait(1) -- wait before check to avoid join/exit spam

			-- teleport is empty
			if #self.players < 1 then
				self.teleporting = false
				return
			end

			-- fire to every player in teleport
			for _, iPlayer in ipairs(self.players) do
				-- TODO мб убрать и другую функцию использовать
				updateTimerEvent:FireClient(iPlayer, i)
			end

			dataManager:addMoneyList(self.players, self.config.moneyReward)
		end

		-- init teleport parameters
		local tData = {
			playerCount = #self.players
		}
		local tOptions = Instance.new("TeleportOptions")
		tOptions.ShouldReserveServer = true
		tOptions:SetTeleportData(tData)

		-- do teleportation
		teleportS:TeleportAsync(self.placeID, self.players, tOptions)

		-- reset teleport state
		self.teleporting = false
		self.players = {}
	end

	-- spawn task
	task.spawn(_timer)
end

-- check if player in teleport
function Portal:_playerIsInside(player)
	for _, iPlayer in ipairs(self.players) do
		if iPlayer == player then
			return true
		end
	end
	return false
end

return Portal


-- shopManager
------------------------------------------------------

local marketPlaceS = game:GetService("MarketplaceService")
local badgeS = game:GetService("BadgeService")
local playersS = game:GetService("Players")

local ShopManager = {}
ShopManager.productsList = {}

ShopManager.BadgeId = 3225353430882368

-- add product to product list
function ShopManager:addProduct(productId, ProximityPrompt:ProximityPrompt, handler)
	self.productsList[productId] = handler

	ProximityPrompt.Triggered:Connect(function(playerWhoTriggered)
		marketPlaceS:PromptProductPurchase(playerWhoTriggered, productId)
	end)
end

-- handle purchases
function ShopManager:_handlePurchases(info)
	print("купил!")
	-- check that the player is still in game
	local player = playersS:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- look up the handler for this product
	local purchaseFunction = self.productsList[info.ProductId]
	if not purchaseFunction then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- run handler
	local success, result = pcall(purchaseFunction, player)
	if not success then
		warn("error while purchasing", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	badgeS:AwardBadge(info.PlayerId, self.BadgeId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- bind ShopManager to hanlder
marketPlaceS.ProcessReceipt = function(info)
	return ShopManager:_handlePurchases(info)
end

return ShopManager

-- main
------------------------------------------------------

-- define managers
local dataManager = require(script.Parent.modules.dataManager) 
local ShopManager = require(script.Parent.modules.shopModule)
local portalManager = require(script.Parent.modules.portalManager)

local dataStoreS = game:GetService("DataStoreService")
local playersS = game:GetService("Players")

-- bind data saving to leave event
playersS.PlayerRemoving:Connect(function(player: Player)
	dataManager:saveData(player)
end)

-- bind data loading to join event
playersS.PlayerAdded:Connect(function(player)
	task.wait(1) -- delay to let player load before loading data
	dataManager:loadData(player)
end)

local places = {
	whitePlace = 130643888530121,
	redPlace = 94142630952968,
	greenPlace = 72467583695069
}

-- init teleports
portalManager.manageTeleport(workspace.bigWhitePortal.teleportZone, places.whitePlace, {maxPartySize= 4, moneyReward = 1, timeUntilTeleport = 5}) -- custom config

portalManager.manageTeleport(workspace.bigRedPortal.teleportZone, places.redPlace, {maxPartySize= 2, moneyReward =7, timeUntilTeleport = 12}) -- custom config

portalManager.manageTeleport(workspace.bigGreenPortal.teleportZone, places.greenPlace) -- default config

local products = {
	coins5000 = 3297475576,
	coins400 = 3297566965
}

-- add products to shop
ShopManager:addProduct(products.coins5000, workspace.shop.ProximityPrompt, function(player)
	dataManager:addMoney(player, 5000)
end)
ShopManager:addProduct(products.coins400, workspace.smallShop.ProximityPrompt, function(player)
	dataManager:addMoney(player, 400)
end)




-- doAnimation MAGICBLOCK
------------------------------------------------------
local RS = game:GetService("ReplicatedStorage")
local TweenS = game:GetService("TweenService")

-- set default position to perform animation
local magicBlock = workspace:WaitForChild("magicBlock")
local defaultPosition = magicBlock.Position

local config = {
	jiggleDistance = -5,
	animationDuration = 3,
	animationType = Enum.EasingStyle.Elastic
}



-- make object 'jiggle' on activation
local function doAnimation(player,object, direction)
	if object ~= magicBlock then -- save server-side check 
		return
	end
	
	-- set new object position 
	object.Position = (CFrame.new(object.Position, object.Position + direction.Unit) * CFrame.new(0, 0, config.jiggleDistance)).Position
	
	-- create animation from new position to default position
	local tweenInfo = TweenInfo.new(config.animationDuration, config.animationType)
	local tween = TweenS:Create(object, tweenInfo, {Position = defaultPosition})
	
	-- do animation without checking completion - it's gonna return to default postion anyway
	tween:Play()

end

-- connect event to animation function
RS.events.doAnimation.OnServerEvent:Connect(doAnimation)


-- 2) CLIENT SIDE
------------------------------------------------------

-- guiController (StarterPlayerScript)
------------------------------------------------------
local replicatedStorageS = game:GetService("ReplicatedStorage")
local playersS = game:GetService("Players")

-- define remote events
local showGuiEvent = replicatedStorageS.events:WaitForChild("showGui")
local removeGuiEvent = replicatedStorageS.events:WaitForChild("removeGui")
local updateTimerEvent = replicatedStorageS.events:WaitForChild("updateTimer")
local updatePlayerCountEvent = replicatedStorageS.events:WaitForChild("updatePlayerCount")

-- define variables
local replicatedGui = replicatedStorageS.portalStorage.partyGui

local player = playersS.LocalPlayer
local currentGui

-- give gui to the player with teleport time and players count when touched the portal
showGuiEvent.OnClientEvent:Connect(function() 
	-- gui exists
	if currentGui  then
		return
	end
	currentGui = replicatedGui:Clone()
	currentGui.Parent = player.PlayerGui
end)

-- remove gui when exit the portal
removeGuiEvent.OnClientEvent:Connect(function() 
	-- gui exists
	if not currentGui  then
		return
	end
	currentGui:Destroy()
	currentGui = nil
end)

-- update timer in gui every second
updateTimerEvent.OnClientEvent:Connect(function(timeLeft) 
	-- gui exists
	if not currentGui  then
		return
	end
	currentGui.timer.Text = timeLeft.."s"
end)

-- update player count in gui when somebody joined/removed
updatePlayerCountEvent.OnClientEvent:Connect(function(playerCount, maxPartySize)
	-- gui exists
	if not currentGui  then
		return
	end
	currentGui.playersCount.Text = playerCount.."/"..maxPartySize
end)


-- toolRaycaster (tool local script) MAGICBLOCK 
------------------------------------------------------
local userInputS = game:GetService("UserInputService")
local playersS = game:GetService("Players")
local replicatedStorageS = game:GetService("ReplicatedStorage")


local tool = script.Parent

local raycastLenght = 1000
local raycastParams = RaycastParams.new()
raycastParams.FilterDescendantsInstances = {playersS.LocalPlayer.Character}


-- do raycast from camera to mouse to get world mouse position
local function getMousePosition()
	-- get mouse location on screen
	local mousePosition = userInputS:GetMouseLocation()

	-- make ray from mouse position 
	local rayToMouse = workspace.CurrentCamera:ViewportPointToRay(mousePosition.x, mousePosition.y)
	local directionVector = rayToMouse.Direction * raycastLenght
	
	-- do raycast
	local raycastResult = workspace:Raycast(rayToMouse.Origin, directionVector, raycastParams)
	if raycastResult then
		return raycastResult.Position
	end
end

-- do raycast from tool to mouse
function raycastFromTool()
	-- get mouse position in workspace
	local mouseLocation = getMousePosition()
	if not mouseLocation then
		return
	end
	
	-- make vector from tool to mouse
	local direction = (mouseLocation - tool.Handle.Position).Unit
	local directionVector = direction * raycastLenght

	-- do raycast
	local raycastResult = workspace:Raycast(tool.Handle.Position, directionVector, raycastParams)
	if not raycastResult then
		return
	end
	
	local HitObject = raycastResult.Instance
	return HitObject, direction
end

-- target to hit for event 
local hitTarget = workspace:WaitForChild("magicBlock")

-- check if tool is activated and casted on target 
local function toolActivated()
	local hittedObject, direction = raycastFromTool()
	if hittedObject and hittedObject == hitTarget then -- not safe client-side check, to evade server spam
		replicatedStorageS.events.doAnimation:FireServer(hittedObject, direction)
	end
end

-- connect tool activation
tool.Activated:Connect(toolActivated)
