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
	currentGui = replicatedGui:Clone()
	currentGui.Parent = player.PlayerGui
end)

-- remove gui when exit the portal
removeGuiEvent.OnClientEvent:Connect(function() 
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