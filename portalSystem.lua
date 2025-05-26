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

-- define data store with name "money"
local moneyDS = dataStoreS:GetDataStore("money")

-- default values if the developer doesn't set the input
local defaultValues = {
	maxPartySize = 4,
	timeUntilTeleport = 15,
	moneyReward = 1
}


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
		if self.playersList == 0 then return end

		if not self.teleporting then
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
	end

	-- add/remove players from playerList by checking overlapping
	function portal:manageParty(overlappingPlayers)
		-- remove players who left the portal
		for i, player in ipairs(self.playersList) do
			if overlappingPlayers[player] == nil  then

				table.remove(self.playersList, i)
				self.gui:deleteGui(player)
				self.gui:updatePartyCount(self.playersList, #self.playersList, self.maxPartySize)
				self:manageTimer()
				return
			end

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
function portalManager.manageTeleport(portalInstance:Instance, placeID:NumberValue, guiInstance:ScreenGui, maxPartySize:IntValue, timeUntilTeleport:IntValue)
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
			if char then
				local player = playersS:GetPlayerFromCharacter(char)
				if player then
					overlappingPlayers[player] = true
				end
			end
		end
		portal.portal:manageParty(overlappingPlayers)
	end
end)


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