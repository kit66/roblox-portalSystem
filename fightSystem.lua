-- Discord: kit661 (displayed: kit) | Roblox: @SAME_KIT
-- may 2026
-- fightSystem.lua fight system.

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local Players = game:GetService("Players")
local Debris = game:GetService("Debris") 
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

--// Globals
local playerDataStore = DataStoreService:GetDataStore("PlayerData")
local PROJECTILE_TAG = "projectile" -- Every ability projectiles should have this tag for proper colliding.
local WALK_DEFAULT = 16
local JUMP_DEFAULT = 7.2
local GetCameraDirectionFunction = ReplicatedStorage:WaitForChild("getCameraDirection") -- Returning workspace.CurrentCamera.CFrame.LookVector from player.
local castFunction = ReplicatedStorage:WaitForChild("cast") -- Calls from client to cast ability.
local refreshRemote = ReplicatedStorage:WaitForChild("refresh") -- Send to client for refreshing cooldowns on gui.


--// Core

-- # Abilities

-- Ability Class
-- Abilities are individual instanses, they handle cooldowns and states using metatable.
local Abilities = {}
Abilities.__index = Abilities

-- Fixed types to prevent errors later.
type AbilitiesType = typeof(setmetatable( {} :: AbilityData, Abilities))

type AbilityData = {
	config: { -- Config inside for editing only this spell (if need to be buffed for special player or else before initing) .
		cooldown: number, -- Seconds
		allowCastStates: { StateName }, -- For state managment
	},
	lastUsed : number, -- For cooldown managment.
	onActivate: ((config: {}, player: Player) -> ()), -- Unique callback for skill.
}

-- Constructs a new object of the ability class.
function Abilities.new(cfg: AbilityData, handler)
	local self = setmetatable({
		config = cfg, 
		lastUsed = -math.huge,
		onActivate = handler, 
	}, Abilities)
	return self
end

-- Returns a boolean representing whether the skill may be used at this point.
function Abilities:isReady(): boolean
	return (tick() - self.lastUsed) >= self.config.cooldown
end

-- Activates the ability by updating the lastUsed attribute and calling the onActivate method; providing the given player.
function Abilities:use(player: Player)	
	self.lastUsed = tick() -- Lock skill using
	self.onActivate(self.config, player) -- For reading unique config of this skill
end

-- Resets the cooldown of this ability.
function Abilities:refreshCooldown()
	self.lastUsed = -math.huge -- This is equal as a cooldown of zero.
end


-- # States

-- Using metatables, we have a unique state manager for each player.
local States = {}
States.__index = States

-- Fixed types to prevent any errors later. 
type StateName = "Silenced" | "Stunned" | "Poisoned"

type StateTasks = {
	mainTask: thread?, -- For handling state task.
	cancelTask: thread?, -- For auto-cancel after time.
	onCancel: (() -> ())?, -- Unique ending for state.
	endAt: number?, -- Absolute timestamp for proper extending. 
}

type StatesType = typeof(setmetatable( {} :: {[StateName]: StateTasks}, States))

-- Constructs a new object of the states class.
function States.new(): StatesType
	return setmetatable({}, States)
end

-- Takes a stateName parameter for the player and updates the player's state.
-- Updating/ending the current state if neccessary.
function States:setState(stateName: StateName, duration: number, onActivate: ((...any) -> ())?, onCancel: ((...any) -> ())?)
	local currentState = self[stateName]
	-- To prevent duration leak (when applying same, but shorter buff).
	if currentState and currentState.endAt > tick() + duration then return end
	-- To prevent multi apply-effect on applying - extend existing.
	if currentState then
		self:updateState(stateName, duration)
		return
	end

	self[stateName] = {
		mainTask = onActivate and task.spawn(onActivate) or nil, -- Handle skills that don't have onActivate thread.
		cancelTask = task.delay(duration, function()
			-- Prevent self-cancelling in removeState.
			self[stateName].cancelTask = nil
			self:removeState(stateName)
		end),
		onCancel = onCancel,
		endAt = tick() + duration,
	}
end

-- Aborts any cancellation in progress and delays a task to cancel the current state.
function States:updateState(stateName: string, duration: number)
	local state = self[stateName] -- Ensure the requested state exists.
	if not state then return end

	task.cancel(state.cancelTask) -- Prevent unwanted state cancelling.

	state.cancelTask = task.delay(duration, function()
		-- Prevent self-cancelling in removeState.
		state.cancelTask = nil
		self:removeState(stateName)
	end)
	state.endAt = tick() + duration
end

-- Removes the current state and cancels if the ability has a cancel effect.
function States:removeState(stateName: StateName)
	local state = self[stateName] -- can't remove if not exist
	if not state then return end

	-- There is nothing to cancel if the duration has expired ('setState' set to nil after duration).
	if state.cancelTask then task.cancel(state.cancelTask) end
	if state.onCancel then state.onCancel() end
	if state.mainTask then task.cancel(state.mainTask) end

	self[stateName] = nil
end

-- Returns a boolean representing whether the player has the provided statename in the list of their states.
function States:hasState(stateName: StateName): boolean
	if self[stateName] then
		return true
	end
	return false
end

-- # DataStore / leaderstats

-- Fixed type to prevent errors later. 
type playerData = {
	kills: number,
}

local data = {} :: {[number]: playerData}

-- Prevent nil data for new players.
local defaultData: playerData = {
	kills = 0
}

-- CRUD State Operations
-- Fetch the provided players data.
local function getData(player: Player)
	return data[player.UserId]
end

-- Assign the provided player a new data table.
local function setData(player: Player, newData: playerData)
	data[player.UserId] = newData
end

-- Remove the provided players data from the state table.
local function removeData(player: Player)
	data[player.UserId] = nil
end

-- Increment kill-counter in data-map for the provided player.
local function incrementKills(player: Player)
	-- Constant because could be gained only 1 kill per killed person.
	data[player.UserId]["kills"] += 1 
	player.leaderstats.kills.Value += 1
end

-- Construct leaderstats representing the provided players kills by fetching their data via the getData function.
local function initLeaderstats(player: Player)
	local data = getData(player) -- Fetch Data.
	
	-- Construct Leaderstats.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- Set the kills count for the player.
	local kills = Instance.new("IntValue")
	kills.Name = "kills"
	kills.Parent = leaderstats
	kills.Value = data.kills
end

--------------------------------------
-- Saves the players data to the DataStore, using getData to first fetch it.
local function saveData(player: Player)
	-- Fetch their data and ensure it exists.
	local dataToSave = getData(player)
	if not dataToSave then return end

	local maxRetries = 3
	-- Ensure a maximum of 3(maxRetries) DataStore calls.
	for i = 1, maxRetries do
		local success, err = pcall(function()
			playerDataStore:SetAsync(player.UserId, dataToSave)
		end)

		if success then return end -- Abort any further attempts.
		warn("Save attempt " .. i .. " failed for " .. player.Name .. ": " .. err)
		if i < maxRetries then task.wait(3) end
	end
	warn("All save attempts failed for " .. player.Name)
end

-- Fetch the provided data from the DataStore if existed, using setData to store it id data-map.
local function loadData(player: Player)	
	local success, saved = pcall(function()
		return playerDataStore:GetAsync(player.UserId)
	end)

	-- Prevent nil if not loaded.
	setData(player, (success and saved) or table.clone(defaultData))

	initLeaderstats(player) -- Create Leaderstats.
end

-- # PlayerRegister

-- Use a fixed type to prevent any errors later. 
type playerRegister = {
	state: StatesType, -- each player has their own states.
	abilities: {[string]: AbilitiesType}, -- Each player has their own abilities.
}	

-- For initialising and storing player states and abilities.
local playersRegister: {[number]: playerRegister} = {}

-- Restore health and set all skills to zero cooldown.
local function refreshPlayer(player: Player)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	humanoid.Health = humanoid.MaxHealth

	-- Refresh each cooldown of the player's abilities.
	for _, ability in pairs(playersRegister[player.UserId].abilities) do
		ability:refreshCooldown()
	end
end

-- # State Appliers

-- Take a target Humanoid and damage integer, apply that damage and then
-- return a boolean representing if the player has died.
local function applyDamage(Target: Humanoid, damage: number): boolean
	local oldHealth = Target.Health

	Target:TakeDamage(damage)

	-- Prevent killing an already dead humanoid. Each can only die once.
	return oldHealth > 0 and Target.Health <= 0
end


-- Applies a state of Stun to the target Player and humanoid for the given duration.
-- Used in skills that may stun.
local function applyStunState(targetPlayer: Player, humanoid: Humanoid, duration: number)
	playersRegister[targetPlayer.UserId].state:setState(
		"Stunned",
		duration,
		-- Game don't have any other ways to change speed/jump - safe constant use.
		function() 
			humanoid.WalkSpeed = 0 
			humanoid.JumpHeight = 0 
		end,
		function() 
			humanoid.WalkSpeed = WALK_DEFAULT
			humanoid.JumpHeight = JUMP_DEFAULT
		end
	)
end

-- Applies a state of poison to the target Player and humanoid for the given duration.
-- Used in skills that may posison.
local function applyPoisonState(poisonOwner: Player, targetPlayer: Player, humanoid: Humanoid, duration: number, tickDuration:number, damage: number)
	playersRegister[targetPlayer.UserId].state:setState(
		"Poisoned",
		duration,
		function()
			while task.wait(tickDuration) do
				if not applyDamage(humanoid, damage) then continue end
				incrementKills(poisonOwner)
			end
		end
	)
end

-- # Utilities

-- Prevent any duplicated effects for similar working abilities.
local function forEachEnemyInPart(part: BasePart, player: Player, applyFunc : (Player, Player, Humanoid) -> ())
	-- Clear 'applied' table every loop - apply status every tick, but not twice in tick.
	local applied = {}

	for _, part in workspace:GetPartsInPart(part) do
		local character = part:FindFirstAncestorWhichIsA("Model") -- Player character cannot be not Model.
		if not character then continue end

		local targetPlayer = Players:GetPlayerFromCharacter(character) -- Do not apply to skill owner.
		if targetPlayer == player then continue end

		local humanoid = character:FindFirstChild("Humanoid") -- Every player character has Humanoid. no humanoid = not player.
		if not humanoid then continue end

		if applied[humanoid] then continue end -- Need to apply state once.
		applied[humanoid] = true

		applyFunc(targetPlayer, player, humanoid)
	end
end

-- # Skill functions

-- Spawn an orb that flies in the player's camera direction.   
local function castFireball(config : {}, player : Player)
	local lookDirection = GetCameraDirectionFunction:InvokeClient(player) -- Fetch the camera direction from the client.

	local fireball = ReplicatedStorage:WaitForChild("fireball"):Clone()
	fireball.Position = player.Character:WaitForChild("HumanoidRootPart").Position + lookDirection * 2 + Vector3.new(0, 1, 0) -- In front of player.
	fireball.Parent = workspace:WaitForChild("Projectiles")

	-- For proper movement it is better to create a new LinearVelocity, and not replicate from ReplicatedStorage.
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = fireball.Attachment
	velocity.VectorVelocity = lookDirection.Unit * config.speed
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = fireball

	Debris:AddItem(fireball, config.stayTime) -- Delete when time is over.

	local applied = {}

	fireball.Touched:Connect(function(otherPart: BasePart)
		if otherPart:HasTag(PROJECTILE_TAG) then return end -- Projectiles can't touch other projectiles.

		local character = otherPart:FindFirstAncestorWhichIsA("Model") -- Player character cannot be not Model.
		if not character then 
			fireball:Destroy() 
			return
		end

		local targetPlayer = Players:GetPlayerFromCharacter(character) -- Do not apply to skill owner.
		if targetPlayer == player then return end	

		fireball:Destroy() -- Collided with someting - destroy anyway.

		local humanoid = character:FindFirstChild("Humanoid") -- Every player character has Humanoid. no humanoid = not player.
		if not humanoid then return end 

		if applied[humanoid] then return end  -- Need to apply state once.
		applied[humanoid] = true

		local dead = applyDamage(humanoid, config.damage) -- Damage can be not lethal.
		if not dead then return end

		incrementKills(player)

		-- Bonus on kill (only for fireball).
		refreshPlayer(player) -- Heal and reset cooldown.
		refreshRemote:FireClient(player) -- Inform client that cooldowns refreshed.
	end)
end

-- Create a conus that deals damage if players collide with it.
local function castIceCouns(config : {}, player: Player)
	local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

	local position = player.Character:WaitForChild("HumanoidRootPart").Position - Vector3.new(0, 3, 0) -- In front of player.

	local flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z) -- Apply without vertical to place on ground level.

	local conus = ReplicatedStorage:WaitForChild("conus"):Clone()
	conus:PivotTo(CFrame.lookAt(position, position + flatDirection.Unit))
	conus.Parent = workspace:WaitForChild("Projectiles")


	Debris:AddItem(conus, config.stayTime)
	-- Until conus in workspace.
	while conus.Parent do		
		forEachEnemyInPart(conus.conus, player, function(targetPlayer, player, humanoid)
			if not applyDamage(humanoid, config.damage) then return end -- Prevent not lethal damage.
			incrementKills(player)				
		end)

		task.wait(config.damageInterval)
	end	
end

-- The same as IceConus, but with a 'poison' effect.
local function castPoisonCloud(config : {}, player: Player)
	local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

	local position = player.Character:WaitForChild("HumanoidRootPart").Position + lookDirection.Unit * 10  -- In front of player.

	local cloud = ReplicatedStorage:WaitForChild("poisonCloud"):Clone()
	cloud:PivotTo(CFrame.lookAt(position, position + lookDirection.Unit))
	cloud.Parent = workspace:WaitForChild("Projectiles")

	Debris:AddItem(cloud, config.stayTime)

	-- While the cloud is still in the workspace.
	while cloud.Parent do
		forEachEnemyInPart(cloud.poisonCloud, player, function(targetPlayer, player, humanoid)
			-- Poison only players, NPC does not have register.
			if targetPlayer then applyPoisonState(player, targetPlayer, humanoid, config.duration, config.damageInterval, config.damage) end			
		end)
		task.wait(config.applyStatusInterval)
	end	
end

-- Create a ring around player that deals damage and applies a Silence state to the players that collide with it.
local function castSilenceRing(config : {}, player: Player)
	local position = player.Character:WaitForChild("HumanoidRootPart").Position -- Inside player (looks like around player).

	local ring = ReplicatedStorage:WaitForChild("ring"):Clone()
	ring:PivotTo(CFrame.new(position))
	ring.Parent = workspace:WaitForChild("Projectiles")

	Debris:AddItem(ring, config.stayTime)

	-- Apply effect only once when activated, destroy by debris after 'stayTime' for visual effect.
	forEachEnemyInPart(ring.ring, player, function(targetPlayer, player, humanoid)
		-- Silence only the players, NPC does not have a register.
		if targetPlayer then playersRegister[targetPlayer.UserId].state:setState("Silenced", config.duration) end

		if not applyDamage(humanoid, config.damage) then return end -- Prevent not lethal damage.
		incrementKills(player)		
	end)
end

-- Same as SilenceRing, but with 'stun' effect.
local function castSlam(config : {}, player: Player)
	local position = player.Character:WaitForChild("HumanoidRootPart").Position 

	local slamRing = ReplicatedStorage:WaitForChild("slamRing"):Clone()
	slamRing:PivotTo(CFrame.new(position - Vector3.new(0, 3, 0)))
	slamRing.Parent = workspace:WaitForChild("Projectiles")

	Debris:AddItem(slamRing, config.stayTime)

	-- Apply effect only once when activated, destroy by debris after 'stayTime' for visual effect.
	forEachEnemyInPart(slamRing.ring, player, function(targetPlayer, player, humanoid)
		-- Stun only players, NPC does not have register
		if targetPlayer then applyStunState(targetPlayer, humanoid, config.duration) end

		if not applyDamage(humanoid, config.damage) then return end -- Prevent not lethal damage.
		incrementKills(player)
	end)
end

-- Remove all states from the player state map.
local function castCleanse(config: {}, player: Player)
	local states = playersRegister[player.UserId].state
	-- Order doesn't matter - remove all states.
	while next(states) do
		states:removeState(next(states))
	end
end

-- # config

local abilitiesConfig = {
	["Fireball"] = {
		damage = 40,
		cooldown = 1,
		stayTime = 2,
		speed = 20,

		blockedStates = {"Stunned", "Silenced"},
	},
	["iceConus"] = {
		damage = 4,
		cooldown = 3,
		stayTime = 5,
		damageInterval = 0.5,

		blockedStates = {"Stunned", "Silenced"},
	},
	["poisonCloud"] = {
		damage = 1,
		cooldown = 10,
		stayTime = 3,
		applyStatusInterval = 0.2,
		damageInterval = 0.4,
		duration = 15,

		blockedStates = {"Stunned", "Silenced"},
	},
	["silenceRing"] = {
		damage = 20,
		cooldown = 4,
		stayTime = 0.3,
		duration = 10,

		blockedStates = {"Stunned"},
	},
	["slam"] = {
		damage = 30,
		cooldown = 10,
		stayTime = 1,
		duration = 7,

		blockedStates = {"Stunned", "Silenced"},
	},
	["cleanse"] = {
		cooldown = 10,

		-- Could be activated when any status. 
		blockedStates = {},
	}
}

-- For easy connecting skill with player when initing.
local abilitiesHanlders = {
	["Fireball"] = castFireball,
	["iceConus"] = castIceCouns,
	["poisonCloud"] = castPoisonCloud,
	["silenceRing"] = castSilenceRing,
	["cleanse"] = castCleanse,
	["slam"] = castSlam,
}

--------------------------------------

-- Return the player's ability configuration, which varies on whether or not they have a Premium membership.
local function boostAbilityIfPremium(player: Player, abilityConfig: AbilityData) : AbilityData
	if player.MembershipType ~= Enum.MembershipType.Premium then return abilityConfig end -- No change for default player.

	local newAbilityConfig = table.clone(abilityConfig)
	if newAbilityConfig.damage then
		newAbilityConfig.damage *= 2 -- Can be multiplied - damage always > 0 (else its useless).
	end

	return newAbilityConfig
end

-- Client call - return whether an ability has been succsesfully casted.
local function castSpellRequest(player: Player, abilityName: string)
	local playerState = playersRegister[player.UserId] -- To prevent calls from non-registered players.
	if not playerState then return false end	

	local ability = playerState.abilities[abilityName] -- To prevent cast abilities that player doesn't have.
	if not ability then return false end

	if not ability:isReady() then return false end

	for _, state in pairs(ability.config.blockedStates) do
		if playerState.state:hasState(state) then return false end
	end

	task.spawn(function()
		ability:use(player)
	end)

	-- Say client that use cast is success and cooldown started.
	return true, ability.config.cooldown
end

-- Handle new clients.
-- Register the client, load their data and set up Character events.
local function onPlayerAdded(player: Player)
	loadData(player)
	playersRegister[player.UserId] = {
		state = States.new(),
		-- Could be skills from dataStore that player have (buyed or obtained), but for now - fixed list of skills.
		abilities = {
			Fireball    = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.Fireball), abilitiesHanlders.Fireball),
			iceConus    = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.iceConus), abilitiesHanlders.iceConus),
			poisonCloud = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.poisonCloud), abilitiesHanlders.poisonCloud),
			silenceRing = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.silenceRing), abilitiesHanlders.silenceRing),
			slam        = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.slam), abilitiesHanlders.slam),
			cleanse     = Abilities.new(abilitiesConfig.cleanse, abilitiesHanlders.cleanse),
		},
	}

	player.CharacterAdded:Connect(function(character) -- Do not spawn player with states.
		castCleanse({}, player)
	end)

	player.CharacterRemoving:Connect(function(character) -- No reason to have states when player is died - remove.
		castCleanse({}, player)
	end)
end

-- Save data to DataStore and remove player data from register.
local function onPlayerRemoved(player: Player)
	saveData(player)
	removeData(player)
	playersRegister[player.UserId] = nil
end

-- Save all players data to DataStore.
local function saveEverbodyData()
	for _, player in Players:GetPlayers() do
		saveData(player)
	end
end

castFunction.OnServerInvoke = castSpellRequest
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoved)

-- No reason to save in studio, only lags after stopping playtest.
if not RunService:IsStudio() then
	game:BindToClose(saveEverbodyData) -- Prevent data loss when last player on server leaving.
end

-- Save everyones data to the DataStore periodically.
local TIME_BETWEEN_SAVE = 300
task.spawn(function()
	while task.wait(TIME_BETWEEN_SAVE) do
		saveEverbodyData()	
	end
end)
