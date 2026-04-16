-- services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

-- data store
local playerDataStore = DataStoreService:GetDataStore("PlayerData")

-- projectiles has to have "projectile" tag
local PROJECTILE_TAG = "projectile"

-- get player current camera direction (cframe.LookVector) 
local GetCameraDirectionFunction = ReplicatedStorage:WaitForChild("getCameraDirection")
-- remote ability cast request
local castFunction = ReplicatedStorage:WaitForChild("cast")

local Abilities = {}
Abilities.__index = Abilities

-- types for abilities
type AbilitiesType = typeof(setmetatable( {} :: AbilityData, Abilities))

type AbilityData = {
	config: { 
		damage: number,
		cooldown: number?,
		allowCastStates: { StateName }?,
	},
	onActivate: ((self: AbilityData, player: Player) -> ())?,
}

-- init new ability by config
function Abilities.new(cfg: AbilityData)
	local self = setmetatable({}, Abilities)
	self.config = cfg
	self.lastUsed  = -math.huge
	self.onActivate = cfg.onActivate
	return self
end

-- check if ability has cooldown
function Abilities:isReady(): boolean
	return (tick() - self.lastUsed) >= self.config.cooldown
end

-- activate ability and set cooldown
function Abilities:use(player: Player)	
	self.lastUsed = tick()
	self:onActivate(player)
end

-- refresh ability cooldown
function Abilities:refresh()
	self.lastUsed = -math.huge
end


-- states - use to control player state
local States = {}
States.__index = States

-- types for states
type StateName = "Idle" | "Silenced"

type StatesType = typeof(setmetatable( {} :: { current: StateName, removeSilenceTask: thread?}, States))
	

-- init new state object
function States.new(): StatesType
	return setmetatable({current = "Idle"}, States)
end

-- remove silence state and cancel removeSilenceTask
function States:CancelSilence()
	-- cancel current removeSilenceTask
	if self.removeSilenceTask then
		task.cancel(self.removeSilenceTask)
	end
	-- set default state
	self.current = "Idle"
	self.removeSilenceTask = nil
end

-- set silence state and create removeSilenceTask
function States:setSilence(duration: number)
	-- cancel any current removeSilenceTask to prevent from stacking
	if self.removeSilenceTask then
		task.cancel(self.removeSilenceTask)
	end

	self.current = "Silenced"

	-- remove silence in task after duration
	self.removeSilenceTask = task.delay(duration, function()
		--prevent check for the same call
		self.removeSilenceTask = nil  
		self:CancelSilence()
	end)
end

-- initialize player leaderstats
local function initLeaderstats(player)
	local data = getData(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local kills = Instance.new("IntValue")
	kills.Name = "kills"
	kills.Parent = leaderstats
	kills.Value = data.kills
end


-- type for data
type playerData = {
	kills: number,
}

-- data storage
local data = {} :: {[number]: playerData}

local defaultData: playerData = {
	kills = 0
}

-- get full player data from storage
function getData(player: Player)
	return data[player.UserId]
end

-- set full player data to storage
function setData(player: Player, newData: playerData)
	data[player.UserId] = newData
end

-- get player kills from storage
function getKills(player: Player)
	return data[player.UserId]["kills"] 
end

-- increment player kills in storage and leaderstats
function incrementKills(player: Player)
	data[player.UserId]["kills"] += 1
	player.leaderstats.kills.Value += 1
end


-- save data to dataStore
local function saveData(player: Player)
	-- get what to save
	local dataToSave = getData(player)
	if not dataToSave then return end

	-- try to save
	local maxRetries = 3
	for i = 1, maxRetries do
		local success, err = pcall(function()
			playerDataStore:UpdateAsync(player.UserId, function(old)
				return dataToSave
			end)
		end)
		
		if success then return end
		warn("Save attempt " .. i .. " failed for " .. player.Name .. ": " .. err)
		if i < maxRetries then task.wait(3) end
	end
	warn("All save attempts failed for " .. player.Name)
end

-- load data from dataStore
local function loadData(player: Player)	
	-- try to get
	local success, saved = pcall(function()
		return playerDataStore:GetAsync(player.UserId)
	end)
	
	-- set data anyway: from store or default 
	setData(player, (success and saved) or table.clone(defaultData))
	
	initLeaderstats(player)
end


-- table for storing player state and registered abilities
type playerRegister = {
	state: StatesType,
	abilities: {[string]: AbilitiesType},
}	
local playersRegister: {[number]: playerRegister} = {}

-- heal player and reset cooldown on every ability
local function refreshPlayer(player)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	humanoid.Health = humanoid.MaxHealth

	for _, ability in pairs(playersRegister[player.UserId].abilities) do
		ability:refresh()
	end
end

-- apply damage to target and return true if target died
local function applyDamage(Target: Humanoid, damage: number): boolean
	local oldHealth = Target.Health

	Target:TakeDamage(damage)

	return oldHealth > 0 and Target.Health <= 0
end


-- config
local abilitiesConfig = {
	["Fireball"] = {
		damage = 40,
		cooldown = 1,
		travelTime = 2,
		speed = 20,

		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

			-- Spawn projectile slightly in front of the character in camera direction
			local fireball = ReplicatedStorage:WaitForChild("fireball"):Clone()
			fireball.Position = player.Character:WaitForChild("HumanoidRootPart").Position + lookDirection * 2 + Vector3.new(0, 1, 0)
			fireball.Parent = workspace:WaitForChild("Projectiles")
			
			-- apply velocity to attachemnt in fireball
			local velocity = Instance.new("LinearVelocity")
			velocity.Attachment0 = fireball.Attachment
			velocity.VectorVelocity = lookDirection.Unit * self.config.speed
			velocity.MaxForce = math.huge
			velocity.RelativeTo = Enum.ActuatorRelativeTo.World
			velocity.Parent = fireball
			
			-- destroy projectile after travel time if not collided with anyting
			Debris:AddItem(fireball, self.config.travelTime)

			local damaged = {}

			fireball.Touched:Connect(function(otherPart: BasePart)
				-- do not destroy if collided with any other projectile
				if otherPart:HasTag(PROJECTILE_TAG) then return end

				local character = otherPart:FindFirstAncestorWhichIsA("Model")
				if character then 
					-- do not destroy and do not deal damage if collided with a owner of the projectile
					local targetPlayer = Players:GetPlayerFromCharacter(character)
					if targetPlayer and targetPlayer == player then return end	

					-- collided with another player 
					fireball:Destroy()
					
					local humanoid = character:FindFirstChild("Humanoid")
					if not humanoid then return end 
					
					-- do not damage same humanoid twice
					if damaged[humanoid] then return end
					damaged[humanoid] = true

					local oldHealth = humanoid.Health
					
					local dead = applyDamage(humanoid, self.config.damage)
					if not dead then return end
										
					incrementKills(player)
					-- bonus on kill - only for fireball
					refreshPlayer(player)
					-- update cooldown timer on client
					castFunction:InvokeClient(player)	
				else
					-- collided with something else
					fireball:Destroy()
				end
			end)
		end

	},
	["iceConus"] = {
		damage = 4,
		cooldown = 3,
		stayTime = 5,

		allowCastStates = {"Idle"},

		onActivate = function (self, player)
			local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

			-- position under player
			local position = player.Character:WaitForChild("HumanoidRootPart").Position - Vector3.new(0, 3, 0)

			-- ignore vertical camera direction
			local flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)
			
			-- spawn cone in camera direction without vertical component
			local conus = ReplicatedStorage:WaitForChild("conus"):Clone()
			conus:PivotTo(CFrame.lookAt(position, position + flatDirection.Unit))
			conus.Parent = workspace:WaitForChild("Projectiles")

			-- destroy cone after stayTime
			Debris:AddItem(conus, self.config.stayTime)

			-- damage until exists
			task.spawn(function()
				while conus.Parent do
					local damaged = {}
					local parts = workspace:GetPartsInPart(conus.conus)
					
					-- damage multiple players
					for _, part in pairs(parts) do
						local character = part:FindFirstAncestorWhichIsA("Model")
						if not character then continue end
						
						-- do not damage projectile owner
						local targetPlayer = Players:GetPlayerFromCharacter(character)
						if  targetPlayer and targetPlayer == player then continue end

						local humanoid = character:FindFirstChild("Humanoid")
						if not humanoid then continue end

						-- do not damage same humanoid twice
						if damaged[humanoid] then continue end
						damaged[humanoid] = true

						local dead = applyDamage(humanoid, self.config.damage)
						if not dead then continue end
						
						incrementKills(player)
					end
					task.wait(0.5)
				end	
			end)
		end,
	},
	["silenceRing"] = {
		damage = 20,
		cooldown = 4,
		stayTime = 0.3,
		SilenceDuration = 10,
		
		allowCastStates = {"Idle", "Silenced"}, -- could be cast when silenced for demostrate purpose

		onActivate = function (self, player)
			local position = player.Character:WaitForChild("HumanoidRootPart").Position 
			
			-- ring around player
			local ring = ReplicatedStorage:WaitForChild("ring"):Clone()
			ring:PivotTo(CFrame.new(position))
			ring.Parent = workspace:WaitForChild("Projectiles")
			
			-- destroy ring after stayTime
			Debris:AddItem(ring, self.config.stayTime)


			-- deal damage and apply status one time to all players that collided
			local damaged = {}
			local parts = workspace:GetPartsInPart(ring.ring)

			for _, part in pairs(parts) do
				local character = part:FindFirstAncestorWhichIsA("Model")
				if not character then continue end

				local targetPlayer = Players:GetPlayerFromCharacter(character)
				if targetPlayer and targetPlayer == player then continue end

				local humanoid = character:FindFirstChild("Humanoid")
				if not humanoid then continue end

				-- do not damage/silence same humanoid twice
				if damaged[humanoid] then continue end
				damaged[humanoid] = true

				-- silence only players, NPC does not have register
				if targetPlayer then
					playersRegister[targetPlayer.UserId].state:setSilence(self.config.SilenceDuration)
				end
				
				local dead = applyDamage(humanoid, self.config.damage)
				if not dead then continue end
				
				incrementKills(player)
			end
		end,
	},
	["cleanse"] = {
		cooldown = 10,

		-- could be activated only when silenced 
		allowCastStates = {"Silenced"},

		onActivate = function (self, player)
			playersRegister[player.UserId].state:CancelSilence()
		end,
	}
}



-- boost ability config if players has premium
local function boostAbilityIfPremium(player: Player, abilityConfig: AbilityData) : AbilityData
	-- return without boost
	if player.MembershipType ~= Enum.MembershipType.Premium then return abilityConfig end
	
	-- new boosted config
	local newAbilityConfig = table.clone(abilityConfig)
	newAbilityConfig.damage *= 2

	return newAbilityConfig
end

-- handle remote cast spell request
local function castSpellRequest(player: Player, abilityName: string)
	-- player must have registered ability on server
	local playerState = playersRegister[player.UserId]
	if not playerState then return false end	

	local ability = playerState.abilities[abilityName]
	if not ability  then return false end

	-- player have right state for skill
	if not table.find(ability.config.allowCastStates, playerState.state.current) then return end

	if not ability:isReady() then return false end

	task.spawn(function()
		ability:use(player)
	end)
	
	-- send cooldown time to client
	return true, ability.config.cooldown
end

local function onPlayerAdded(player: Player)
	-- register every skill for player and state
	loadData(player)
	playersRegister[player.UserId] = {
		state = States.new(),
		-- could be skills from dataStore that player have (buyed or obtained), but for now - fixed list of skills
		abilities = {
			Fireball   = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.Fireball)),
			iceConus   = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.iceConus)),
			silenceRing = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.silenceRing)),
			cleanse = Abilities.new(abilitiesConfig.cleanse),
		},
	}
end

local function onPlayerRemoved(player: Player)
	-- clear space in memory
	saveData(player)
	playersRegister[player.UserId] = nil
end

local function saveEverbodyData()
	for _, player in Players:GetPlayers() do
		saveData(player)
	end
end

castFunction.OnServerInvoke = castSpellRequest
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoved)
game:BindToClose(saveEverbodyData)

local TIME_BETWEEN_SAVE = 300
task.spawn(function()
	while task.wait(TIME_BETWEEN_SAVE) do
		saveEverbodyData()	
	end
end)
