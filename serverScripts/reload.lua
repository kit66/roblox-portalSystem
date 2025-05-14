-- Reload timing is enforced on the server to prevent client-side exploits
local RS = game:GetService("ReplicatedStorage")
local events = RS.events

-- wait gun reload cooldown 
local function waittime(player,name,reload)
	wait(reload)
	events.cooldown:FireClient(player,name)
end

events.cooldown.OnServerEvent:Connect(waittime)