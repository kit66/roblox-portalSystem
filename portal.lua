-- define services
local teleportS = game:GetService("TeleportService")
local replicatedStorageS = game:GetService("ReplicatedStorage")

-- define remote events
local showGuiEvent = replicatedStorageS.events:WaitForChild("showGui")
local removeGuiEvent = replicatedStorageS.events:WaitForChild("removeGui")
local updateTimerEvent = replicatedStorageS.events:WaitForChild("updateTimer")
local updatePlayerCountEvent = replicatedStorageS.events:WaitForChild("updatePlayerCount")

dataManager = require(script.Parent.dataManager)


local defaultConfig = {
   	maxPartySize = 4,
	timeUntilTeleport = 15,
	moneyReward = 1
}

local Portal = {}

function Portal.New(placeID:number, config)
	local self = setmetatable({}, Portal)
    self.placeID = placeID
    self.config = config or defaultConfig
    self.players = {}
    self.teleporting = false

	
	return self
end

function Portal:AddPlayer(player)
    if #self.players < self.config.maxPartySize then
        table.insert(self.players, player)
    end

    if not self.teleporting and #self.players == 1 then
        self:StartTimer()
    end

	-- update gui
	showGuiEvent:FireClient(player)
	for iPlayer, _ in pairs(self.players) do
		updatePlayerCountEvent:FireClient(iPlayer, #self.players, self.maxPartySize)
	end

end

function Portal:RemovePlayer(player)
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
		updatePlayerCountEvent:FireClient(iPlayer, #self.players, self.maxPartySize)
	end
    -- 
    self.players = players
end

function Portal:StartTimer()
    self.teleporting = true

    local function _timer()
        for i=self.timeUntilTeleport,0,-1 do
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