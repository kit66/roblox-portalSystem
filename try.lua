local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")


local playerDataStore = DataStoreService:GetDataStore("PlayerData")

local PROJECTILE_TAG = "projectile"
local WALK_DEFAULT = 16
local JUMP_DEFAULT = 7.2


local GetCameraDirectionFunction = ReplicatedStorage:WaitForChild("getCameraDirection")
local castFunction = ReplicatedStorage:WaitForChild("cast")


local Abilities = {}
Abilities.__index = Abilities

type AbilitiesType = typeof(setmetatable( {} :: AbilityData, Abilities))

type AbilityData = {
	config: { 
		cooldown: number,
		allowCastStates: { StateName },
	},
	onActivate: ((config: {}, player: Player) -> ()),
}

function Abilities.new(cfg: AbilityData, handler)
	local self = setmetatable({
		config = cfg,
		lastUsed = -math.huge,
		onActivate = handler,
	}, Abilities)
	return self
end

function Abilities:isReady(): boolean
	return (tick() - self.lastUsed) >= self.config.cooldown
end

function Abilities:use(player: Player)	
	self.lastUsed = tick()
	self.onActivate(self.config, player)
end

function Abilities:refreshCooldown()
	self.lastUsed = -math.huge
end


local States = {}
States.__index = States

type StateName = "Silenced" | "Stunned" | "Poisoned"

type StateTasks = {
	mainTask: thread?,
	cancelTask: thread?,
	onCancel: (() -> ())?,
	endAt: number?,
}

type StatesType = typeof(setmetatable( {} :: {[StateName]: StateTasks}, States))

function States.new(): StatesType
	return setmetatable({}, States)
end

function States:setState(stateName: StateName, duration: number, onActivate: ((...any) -> ())?, onCancel: ((...any) -> ())?)
	local currentState = self[stateName]
	-- prevent applying same, but shorter buff 
	if currentState and currentState.endAt > tick() + duration then return end
	-- do not restart state, extend existing
	if currentState then
		self:updateState(stateName, duration)
		return
	end

	self[stateName] = {
		mainTask = onActivate and task.spawn(onActivate) or nil,
		cancelTask = task.delay(duration, function()
			-- prevent self-cancelling in removeState
			self[stateName].cancelTask = nil
			self:removeState(stateName)
		end),
		onCancel = onCancel,
		endAt = tick() + duration,
	}
end

function States:updateState(stateName: string, duration: number)
	local state = self[stateName]
	if not state then return end
	
	task.cancel(state.cancelTask)
	
	state.cancelTask = task.delay(duration, function()
		-- prevent self-cancelling in removeState
		state.cancelTask = nil
		self:removeState(stateName)
	end)
	state.endAt = tick() + duration
end

function States:removeState(stateName: StateName)
	local state = self[stateName]
	if not state then return end
	
	-- nothing to cancel if duration expired (setState set to nil after duration)
	if state.cancelTask then task.cancel(state.cancelTask) end
	if state.onCancel then state.onCancel() end
	if state.mainTask then task.cancel(state.mainTask) end

	self[stateName] = nil
end

function States:hasState(stateName: StateName): boolean
	if self[stateName] then
		return true
	end
	return false
end


type playerData = {
	kills: number,
}

local data = {} :: {[number]: playerData}

local defaultData: playerData = {
	kills = 0
}

local function getData(player: Player)
	return data[player.UserId]
end

local function setData(player: Player, newData: playerData)
	data[player.UserId] = newData
end

local function getKills(player: Player)
	return data[player.UserId]["kills"] 
end

local function incrementKills(player: Player)
	data[player.UserId]["kills"] += 1
	player.leaderstats.kills.Value += 1
end


local function initLeaderstats(player: Player)
	local data = getData(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local kills = Instance.new("IntValue")
	kills.Name = "kills"
	kills.Parent = leaderstats
	kills.Value = data.kills
end


local function saveData(player: Player)
	local dataToSave = getData(player)
	if not dataToSave then return end

	local maxRetries = 3
	for i = 1, maxRetries do
		local success, err = pcall(function()
			playerDataStore:SetAsync(player.UserId, dataToSave)
		end)

		if success then return end
		warn("Save attempt " .. i .. " failed for " .. player.Name .. ": " .. err)
		if i < maxRetries then task.wait(3) end
	end
	warn("All save attempts failed for " .. player.Name)
end

local function loadData(player: Player)	
	local success, saved = pcall(function()
		return playerDataStore:GetAsync(player.UserId)
	end)

	-- set data anyway: from store or default 
	setData(player, (success and saved) or table.clone(defaultData))

	initLeaderstats(player)
end


type playerRegister = {
	state: StatesType,
	abilities: {[string]: AbilitiesType},
}	
local playersRegister: {[number]: playerRegister} = {}

local function refreshPlayer(player: Player)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	humanoid.Health = humanoid.MaxHealth

	for _, ability in pairs(playersRegister[player.UserId].abilities) do
		ability:refreshCooldown()
	end
end


-- return true if humanoid died
local function applyDamage(Target: Humanoid, damage: number): boolean
	local oldHealth = Target.Health

	Target:TakeDamage(damage)

	return oldHealth > 0 and Target.Health <= 0
end


local function applyStunState(targetPlayer: Player, humanoid: Humanoid, duration: number)
	playersRegister[targetPlayer.UserId].state:setState(
		"Stunned",
		duration,
		-- game don't have any other ways to change speed/jump - safe constant use
		function() humanoid.WalkSpeed = 0 humanoid.JumpHeight = 0 end,
		function() humanoid.WalkSpeed = WALK_DEFAULT humanoid.JumpHeight = JUMP_DEFAULT end
	)
end

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

local function forEachEnemyInPart(part: BasePart, player: Player, applyFunc : (Player, Player, Humanoid) -> ())
	-- clear 'applied' table every loop - apply status every tick, but not twice in tick
	local applied = {}
	
	for _, part in workspace:GetPartsInPart(part) do
		local character = part:FindFirstAncestorWhichIsA("Model")
		if not character then continue end

		local targetPlayer = Players:GetPlayerFromCharacter(character)
		if targetPlayer == player then continue end

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid then continue end

		if applied[humanoid] then continue end
		applied[humanoid] = true
		
		applyFunc(targetPlayer, player, humanoid)
	end
end

local function castFireball(config : {}, player : Player)
	local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

	local fireball = ReplicatedStorage:WaitForChild("fireball"):Clone()
	fireball.Position = player.Character:WaitForChild("HumanoidRootPart").Position + lookDirection * 2 + Vector3.new(0, 1, 0)
	fireball.Parent = workspace:WaitForChild("Projectiles")

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = fireball.Attachment
	velocity.VectorVelocity = lookDirection.Unit * config.speed
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = fireball

	Debris:AddItem(fireball, config.stayTime)

	local applied = {}

	fireball.Touched:Connect(function(otherPart: BasePart)
		-- save touching with other projectiles
		if otherPart:HasTag(PROJECTILE_TAG) then return end

		local character = otherPart:FindFirstAncestorWhichIsA("Model")
		if not character then fireball:Destroy() return end

		-- save touching with owner
		local targetPlayer = Players:GetPlayerFromCharacter(character)
		if targetPlayer == player then return end	

		-- collided with someting - destroy anyway
		fireball:Destroy()

		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid then return end 
		
		-- can be touched multiple times in one tick - need to be checked
		if applied[humanoid] then return end
		applied[humanoid] = true

		local dead = applyDamage(humanoid, config.damage)
		if not dead then return end

		incrementKills(player)
		-- bonus on kill (only for fireball) heal and reset cooldowns	
		refreshPlayer(player)
		castFunction:InvokeClient(player)	
	end)
end

local function castIceCouns(config : {}, player: Player)
	local lookDirection = GetCameraDirectionFunction:InvokeClient(player)

	local position = player.Character:WaitForChild("HumanoidRootPart").Position - Vector3.new(0, 3, 0)

	-- ignore vertical camera direction
	local flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)

	local conus = ReplicatedStorage:WaitForChild("conus"):Clone()
	conus:PivotTo(CFrame.lookAt(position, position + flatDirection.Unit))
	conus.Parent = workspace:WaitForChild("Projectiles")

	
	Debris:AddItem(conus, config.stayTime)
	-- until conus in workspace
	while conus.Parent do		
		forEachEnemyInPart(conus.conus, player, function(targetPlayer, player, humanoid)
			if not applyDamage(humanoid, config.damage) then return end
			incrementKills(player)				
		end)
		
		task.wait(config.damageInterval)
	end	
end

-- same as IceConus, but with 'poison' effect
local function castPoisonCloud(config : {}, player: Player)
	local lookDirection = GetCameraDirectionFunction:InvokeClient(player)
 
	local position = player.Character:WaitForChild("HumanoidRootPart").Position + lookDirection.Unit * 10

	local cloud = ReplicatedStorage:WaitForChild("poisonCloud"):Clone()
	cloud:PivotTo(CFrame.lookAt(position, position + lookDirection.Unit))
	cloud.Parent = workspace:WaitForChild("Projectiles")

	Debris:AddItem(cloud, config.stayTime)
	
	-- until cloud in workspace
	while cloud.Parent do
		forEachEnemyInPart(cloud.poisonCloud, player, function(targetPlayer, player, humanoid)
			-- poison only players, NPC does not have register
			if targetPlayer then applyPoisonState(player, targetPlayer, humanoid, config.duration, config.damageInterval, config.damage) end			
		end)
		task.wait(config.applyStatusInterval)
	end	
end

local function castSilenceRing(config : {}, player: Player)
	local position = player.Character:WaitForChild("HumanoidRootPart").Position 

	local ring = ReplicatedStorage:WaitForChild("ring"):Clone()
	ring:PivotTo(CFrame.new(position))
	ring.Parent = workspace:WaitForChild("Projectiles")

	Debris:AddItem(ring, config.stayTime)

	local applied = {}
	
	-- apply effect only once when activated, destroy by debris after 'stayTime' for visual effect
	forEachEnemyInPart(ring.ring, player, function(targetPlayer, player, humanoid)
		-- silence only players, NPC does not have register
		if targetPlayer then playersRegister[targetPlayer.UserId].state:setState("Silenced", config.duration) end
		
		if not applyDamage(humanoid, config.damage) then return end
		incrementKills(player)		
	end)
end

-- same as SilenceRing, but with 'stun' effect
local function castSlam(config : {}, player: Player)
	local position = player.Character:WaitForChild("HumanoidRootPart").Position 

	local slamRing = ReplicatedStorage:WaitForChild("slamRing"):Clone()
	slamRing:PivotTo(CFrame.new(position - Vector3.new(0, 3, 0)))
	slamRing.Parent = workspace:WaitForChild("Projectiles")

	Debris:AddItem(slamRing, config.stayTime)

	local applied = {}

	-- apply effect only once when activated, destroy by debris after 'stayTime' for visual effect
	forEachEnemyInPart(slamRing.ring, player, function(targetPlayer, player, humanoid)
		-- stun only players, NPC does not have register
		if targetPlayer then applyStunState(targetPlayer, humanoid, config.duration) end

		if not applyDamage(humanoid, config.damage) then return end
		incrementKills(player)
	end)
end

local function castCleanse(config: {}, player: Player)
	local states = playersRegister[player.UserId].state
	-- remove all states until table is empty
	while next(states) do
		states:removeState(next(states))
	end
end


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

		-- could be activated when any status 
		blockedStates = {},
	}
}


local abilitiesHanlders = {
	["Fireball"] = castFireball,
	["iceConus"] = castIceCouns,
	["poisonCloud"] = castPoisonCloud,
	["silenceRing"] = castSilenceRing,
	["cleanse"] = castCleanse,
	["slam"] = castSlam,
}


-- boost ability config if players has premium
local function boostAbilityIfPremium(player: Player, abilityConfig: AbilityData) : AbilityData
	if player.MembershipType ~= Enum.MembershipType.Premium then return abilityConfig end

	local newAbilityConfig = table.clone(abilityConfig)
	if newAbilityConfig.damage then
		newAbilityConfig.damage *= 2
	end
	
	return newAbilityConfig
end

local function castSpellRequest(player: Player, abilityName: string)
	local playerState = playersRegister[player.UserId]
	if not playerState then return false end	

	local ability = playerState.abilities[abilityName]
	if not ability then return false end
	
	if not ability:isReady() then return false end
	
	for _, state in pairs(ability.config.blockedStates) do
		if playerState.state:hasState(state) then return false end
	end
	
	task.spawn(function()
		ability:use(player)
	end)
	
	-- say client that use cast is success and cooldown started, not full casting func 
	return true, ability.config.cooldown
end

local function onPlayerAdded(player: Player)
	loadData(player)
	playersRegister[player.UserId] = {
		state = States.new(),
		-- could be skills from dataStore that player have (buyed or obtained), but for now - fixed list of skills
		abilities = {
			Fireball    = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.Fireball), abilitiesHanlders.Fireball),
			iceConus    = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.iceConus), abilitiesHanlders.iceConus),
			poisonCloud = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.poisonCloud), abilitiesHanlders.poisonCloud),
			silenceRing = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.silenceRing), abilitiesHanlders.silenceRing),
			slam        = Abilities.new(boostAbilityIfPremium(player, abilitiesConfig.slam), abilitiesHanlders.slam),
			cleanse     = Abilities.new(abilitiesConfig.cleanse, abilitiesHanlders.cleanse),
		},
	}
	
	player.CharacterAdded:Connect(function(character)
		castCleanse({}, player)
	end)
	
	player.CharacterRemoving:Connect(function(character)
		castCleanse({}, player)
	end)
end

local function onPlayerRemoved(player: Player)
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

if not RunService:IsStudio() then
	game:BindToClose(saveEverbodyData)
end

local TIME_BETWEEN_SAVE = 300
task.spawn(function()
	while task.wait(TIME_BETWEEN_SAVE) do
		saveEverbodyData()	
	end
end)