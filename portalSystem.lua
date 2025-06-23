-- SERVER SCRIPT
-------------------------------------------------------------------

-- define module for each subsystem
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

-- 4) badge system

-- 5) shop system

-- products table



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