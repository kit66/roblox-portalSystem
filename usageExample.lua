
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