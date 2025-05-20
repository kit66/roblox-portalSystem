-- This script manages the teleport system and creates teleporters to other locations.
-- Stand on a teleporter and it will teleport you to another place.
-- Each teleporter has a capacity, and all players standing on it will be teleported together.

local portalManager = {}
local util = {}
local portalInitializer = {}
local guiInitializer = {}
local dataManager = {}



local dataStoreS = game:GetService("DataStoreService")
local teleportS = game:GetService("TeleportService")
local playersS = game:GetService("Players")
local replicatedStorageS = game:GetService("ReplicatedStorage")
local runS    = game:GetService("RunService")

local moneyDS = dataStoreS:GetDataStore("money")



-- Default values if the developer doesn't set the input
local defaultValues = {
	maxPartySize = 4,
	timeUntilTeleport = 15,
	moneyReward = 1
}

local requestedPart = "Head" -- default part to check for player teleporting


-- get player only if "requestedPart" is touched
function util.getPlayer(part)

	if part.Name ~= requestedPart then
		return nil
	end

	return playersS:GetPlayerFromCharacter(part.Parent)
end


-- add instance "money" to the player
function dataManager.addLeaderstats(player)
	local leaderboard = Instance.new("Folder")
	leaderboard.Name = "leaderstats"
	leaderboard.Parent = player

	local money = Instance.new("IntValue")
	money.Name = "money"
	money.Value = 0
	money.Parent = leaderboard
end


-- get player money instance, if not - create leaderstats
function dataManager:getMoney(player)
	if not player:FindFirstChild("leaderstats") then
		self.addLeaderstats(player)
	end
	return player.leaderstats.money
end


-- add money to player
function dataManager:addMoney(player, count)	
	local money = self:getMoney(player)
	money.Value += count
end


-- do "addMoney" to all players in the list
function dataManager:addMoneyList(playerList, count)
	for _, player in ipairs(playerList) do
		self:addMoney(player, count)
	end
end


-- save data to DS (money)
function dataManager:saveData(player)
	local key = player.UserId
	local moneyValue = self:getMoney(player).Value

	local success, err = pcall(function()
		moneyDS:UpdateAsync(key, function(moneyBefore)
			return (moneyBefore or 0) + moneyValue
		end)
	end)

	if not success then
		warn("setAsync error:", tostring(err))
		return
	end
end
-- save data when player is leave
playersS.PlayerRemoving:Connect(function(player: Player) 
	dataManager:saveData(player)
end)


-- load data from DS (money)
function dataManager:loadData(player)
	local key = player.UserId
	local moneyValue = 0

	local success, err = pcall(function()
		moneyValue = moneyDS:GetAsync(key)
	end)

	if not success then
		warn("getAsync error:" .. tostring(err))
		player:Kick("failed to read data")
		return
	end

	local money = self:getMoney(player)
	money.Value = moneyValue
end
-- load data when player is joined
playersS.PlayerAdded:Connect(function(player)
	task.wait(1)
	dataManager:loadData(player)
end)


-- manage gui and show portal capacity, playerCount and timer
function guiInitializer.initGui(guiInstance:ScreenGui)

	local gui = {
		guiInstance = guiInstance
	}

	function gui:updatePartyCount(players, partyCount, maxPartySize)
		for _,player in ipairs(players) do
			local gui = player.PlayerGui:WaitForChild(self.guiInstance.Name)
			gui.playersCount.Text = partyCount.."/"..maxPartySize
		end
	end

	function gui:updateTimer(players, timeLeft)
		for _,player in ipairs(players) do
			local gui = player.PlayerGui:WaitForChild(self.guiInstance.Name)
			gui.timer.Text = timeLeft.."s"
		end
	end

	function gui:showGui(player)
		self.guiInstance:Clone().Parent = player.PlayerGui
	end

	function gui:deleteGui(player)
		player.PlayerGui:WaitForChild(self.guiInstance.Name):Destroy()	
	end

	return gui
end



-- init teleport instance
function portalInitializer.initTeleport(placeID:NumberValue, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
	-- set settings for the portal
	local portal = {
		gui = guiInitializer.initGui(guiInstance),

		maxPartySize = maxPartySize or defaultValues.maxPartySize,
		timeUntilTeleport = timeUntilTeleport or defaultValues.timeUntilTeleport,
		placeID = placeID,

		teleporting = false,
		playersList = {}	
	}

	-- function that managing the teleportation timer nad make teleportation
	function portal:manageTimer()
		-- check players count in teleporter
		if #self.playersList>0 then
			-- if teleportation not active
			if not self.teleporting then
				self.teleporting = true
				-- start timer
				for i=self.timeUntilTeleport,0,-1 do
					if self.teleporting then
						self.gui:updateTimer(self.playersList, i)
						task.wait(1)
						dataManager:addMoneyList(self.playersList, defaultValues.moneyReward)
					else
						return
					end
				end
				-- Add the players to the teleport list and perform the teleportation
				local tData = {
					playerCount = #self.playersList
				}

				local tOptions = Instance.new("TeleportOptions")
				tOptions.ShouldReserveServer = true	-- This setting is needed for server reservation to create new server for the player
				tOptions:SetTeleportData(tData)
				teleportS:TeleportAsync(self.placeID, self.playersList, tOptions)			
			end
		else
			self.teleporting = false
		end
	end

	function portal:manageParty(playerList)
		
	end


	-- add player to the playersList 
	function portal:addToParty(player)
		-- check if partySize have slot for new player
		if player and #self.playersList < self.maxPartySize then

			table.insert(self.playersList,player)
			self.gui:showGui(player)
			self.gui:updatePartyCount(self.playersList, #self.playersList, self.maxPartySize)
			self:manageTimer()
		end
	end

	-- delete player from the players list
	function portal:deleteFromParty(player)	

		-- find player in the list
		for i, playerInParty in ipairs(self.playersList) do
			if player == playerInParty then

				table.remove(self.playersList,i)
				self.gui:deleteGui(player)
				self.gui:updatePartyCount(self.playersList, #self.playersList, self.maxPartySize)
				self:manageTimer()
				return
			end
		end
	end


	return portal
end


local overlapParams = OverlapParams.new()
overlapParams.FilterType                = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = { workspace.Characters }

-- main function that makes the object a teleporter and sets its settings
function portalManager.manageTeleport(portalInstance:Instance, placeID:NumberValue, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
	local portal = portalInitializer.initTeleport(placeID,guiInstance, maxPartySize, timeUntilTeleport) 

	-- portal entry
	runS.Heartbeat:Connect(function(deltaTime)
		local overlapping = workspace:GetPartsInPart(portalInstance, OverlapParams)
    	local seen = {}

		for _, part in ipairs(overlapping) do
			local char = part:FindFirstAncestorWhichIsA("Model")
			if char then
				local player = playersS:GetPlayerFromCharacter(char)
				if player then
					seen[player] = true
				end
			end
		end
		portal:manageParty()
	end)

	portalInstance.Touched:Connect(function(part)
		local player = util.getPlayer(part)
		if player == nil then
			return
		end

		portal:addToParty(player)
	end)
	-- portal exit
	portalInstance.TouchEnded:Connect(function(part)
		local player = util.getPlayer(part)
		if player == nil then
			return
		end

		portal:deleteFromParty(player)
	end)
end


-------------------------------------------------------------------
-- example how i use this module
-- 1) make portals from the folder teleport to different locations using default settings

local portalFolders = workspace.portals

-- make portal from model if model have instance "teleportZone"
function initPortal(portal, placeID)
	if portal:IsA("Model") then

		local teleportZone = portal:WaitForChild("teleportZone", 0.05)
		if teleportZone == nil then 
			warn("Model:", portal.Name, "in", portal.Parent, "doesn't have instance: teleportZone - SKIP")	
			return
		end

		portalManager.manageTeleport(teleportZone,placeID,replicatedStorageS.portalStorage.partyGui)
	end
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

		if portalFolder:IsA("Folder") then

			local placeId = portalFolder:WaitForChild("placeID",0.05)
			if placeId == nil then
				warn("placeID is not declare in folder:",portalFolder.Name,"- SKIP FOLDER")
				continue
			end

			initPortals(portalFolder, placeId)	
		end
	end
end


initPortalFolders()

-- 2) use only one line to create teleporter

portalManager.manageTeleport(workspace.bigWhitePortal.teleportZone, 130643888530121, replicatedStorageS.portalStorage.partyGui, 2, 7) -- all settings (2 capacity, 7 seconds)

portalManager.manageTeleport(workspace.bigRedPortal.teleportZone, 94142630952968, replicatedStorageS.portalStorage.partyGui, nil, 40) -- default capacity, 11 seconds

portalManager.manageTeleport(workspace.bigGreenPortal.teleportZone, 72467583695069, replicatedStorageS.portalStorage.partyGui) -- default time and size